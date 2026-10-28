import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// An anonymous identity: one per app installation.
class Identity {
  const Identity({required this.installId, required this.expiresAt});

  final String installId;
  final DateTime expiresAt;
}

/// Creates and checks signed tokens.
///
/// There are no user accounts, so the app registers anonymously and receives
/// a token proving "the server issued this identity". A token looks like
///
///     w1.<payload>.<signature>
///
/// where the payload is base64url JSON `{sub, iat, exp}` and the signature is
/// HMAC-SHA256 of the payload with the server's secret. Nobody without the
/// secret can create or alter a token, and the server needs no database to
/// check one.
class TokenService {
  TokenService({
    required String secret,
    required this.ttl,
    DateTime Function()? clock,
    Random? random,
  }) : _key = utf8.encode(secret),
       _now = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Duration ttl;
  final List<int> _key;
  final DateTime Function() _now;
  final Random _random;

  static const _prefix = 'w1';

  /// A fresh random identity (128 bits, hex).
  String newInstallId() => List.generate(
    16,
    (_) => _random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Signs a token for [installId], valid for [ttl] from now.
  ({String token, DateTime expiresAt}) issue(String installId) {
    final now = _now().toUtc();
    final expires = now.add(ttl);
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': installId,
          'iat': now.millisecondsSinceEpoch ~/ 1000,
          'exp': expires.millisecondsSinceEpoch ~/ 1000,
        }),
      ),
    );
    return (token: '$_prefix.$payload.${_sign(payload)}', expiresAt: expires);
  }

  /// Returns the identity, or null if the token is malformed, forged or
  /// expired. Never throws.
  Identity? verify(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _prefix) return null;

    if (!_constantTimeEquals(parts[2], _sign(parts[1]))) return null;

    try {
      final data =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final sub = data['sub'];
      final exp = data['exp'];
      if (sub is! String || sub.isEmpty || sub.length > 64 || exp is! int) {
        return null;
      }
      final expires = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );
      if (!expires.isAfter(_now().toUtc())) return null;
      return Identity(installId: sub, expiresAt: expires);
    } catch (_) {
      return null;
    }
  }

  String _sign(String payload) => base64Url
      .encode(Hmac(sha256, _key).convert(utf8.encode(payload)).bytes)
      .replaceAll('=', '');

  /// Compares in time that does not depend on where the strings differ, so
  /// an attacker cannot guess a signature one character at a time.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
