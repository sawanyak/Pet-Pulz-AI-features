// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pet_core/pet_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's anonymous login with the backend.
///
/// There are no accounts. The first time the app talks to the server it
/// "registers" and receives a signed token that says "the server issued this
/// anonymous identity". The token is kept on the phone and sent with every
/// request. It is renewed shortly before it expires (keeping the same
/// identity, so daily limits carry over), and replaced if the server ever
/// rejects it.
///
/// The token is stored in shared_preferences, which is not encrypted. That is
/// acceptable here because it identifies nobody and unlocks only this app's
/// own quota; a hardening step would be flutter_secure_storage.
class BackendSession {
  BackendSession({
    required this.baseUrl,
    required SharedPreferences prefs,
    http.Client? client,
    DateTime Function()? clock,
  }) : _prefs = prefs,
       client = client ?? http.Client(),
       _now = clock ?? DateTime.now;

  final Uri baseUrl;
  final http.Client client;
  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _tokenKey = 'backend_token_v1';
  static const _expiresKey = 'backend_token_expires_v1';

  /// A token is renewed once it has less than this left.
  static const renewBefore = Duration(days: 7);

  Future<String>? _inFlight;

  Uri url(String path) => baseUrl.replace(path: path);

  String? get _token => _prefs.getString(_tokenKey);

  DateTime? get _expires {
    final raw = _prefs.getString(_expiresKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// A token that is valid now, registering or renewing if necessary.
  Future<String> token() async {
    final token = _token;
    final expires = _expires;
    final now = _now().toUtc();
    if (token != null &&
        expires != null &&
        expires.isAfter(now.add(renewBefore))) {
      return token;
    }
    // Only ONE registration at a time, however many requests are waiting.
    return _inFlight ??= _register(
      existing: token,
      stillValid: expires != null && expires.isAfter(now),
    ).whenComplete(() => _inFlight = null);
  }

  /// Forget the token (the server rejected it), so the next call registers.
  Future<void> reset() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_expiresKey);
  }

  Future<String> _register({
    required String? existing,
    required bool stillValid,
  }) async {
    try {
      final response = await client
          .post(
            url(ApiRoutes.register),
            headers: {
              // Presenting a still-valid token renews the same identity.
              if (existing != null && stillValid)
                'authorization': 'Bearer $existing',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw AiServiceException(
          response.statusCode == 429
              ? 'Too many sign-ups from this network. Please try again later.'
              : 'Couldn\'t sign in to the Whiskers service '
                    '(error ${response.statusCode}).',
        );
      }
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final token = json['token'] as String;
      await _prefs.setString(_tokenKey, token);
      await _prefs.setString(_expiresKey, json['expiresAt'] as String);
      return token;
    } on AiServiceException catch (e) {
      // Renewal failed but the old token still works: keep going with it.
      if (existing != null && stillValid) return existing;
      throw AiServiceException(e.message);
    } on SocketException {
      if (existing != null && stillValid) return existing;
      throw AiServiceException(_offline);
    } on http.ClientException {
      if (existing != null && stillValid) return existing;
      throw AiServiceException(_offline);
    } on TimeoutException {
      if (existing != null && stillValid) return existing;
      throw AiServiceException(_offline);
    } on FormatException {
      throw AiServiceException(
        'The Whiskers service sent an unexpected answer.',
      );
    } on TypeError {
      throw AiServiceException(
        'The Whiskers service sent an unexpected answer.',
      );
    }
  }

  static const _offline =
      'Couldn\'t reach the Whiskers service. Check your connection and try '
      'again.';
}
