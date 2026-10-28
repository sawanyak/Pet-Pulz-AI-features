import 'package:test/test.dart';
import 'package:whiskers_backend/whiskers_backend.dart';

import 'harness.dart';

const goodEnv = {'TOKEN_SECRET': testSecret, 'GEMINI_API_KEY': 'g-key'};

void main() {
  group('ServerConfig.fromEnv', () {
    test('a minimal valid environment works, with sane defaults', () {
      final c = ServerConfig.fromEnv(goodEnv);
      expect(c.provider, ProviderChoice.gemini);
      expect(c.port, 8080);
      expect(c.tokenTtl, const Duration(days: 30));
      expect(c.dailyRequestCap, 5000);
      expect(c.trustedProxyHops, 0);
    });

    test('refuses to start without a strong secret', () {
      expect(
        () => ServerConfig.fromEnv({'GEMINI_API_KEY': 'k'}),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ServerConfig.fromEnv({
          'TOKEN_SECRET': 'too-short',
          'GEMINI_API_KEY': 'k',
        }),
        throwsA(isA<ConfigException>()),
      );
    });

    test('refuses to start without any provider key', () {
      expect(
        () => ServerConfig.fromEnv({'TOKEN_SECRET': testSecret}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('provider choice: auto prefers Gemini, override, and mismatches', () {
      expect(
        ServerConfig.fromEnv({
          ...goodEnv,
          'ANTHROPIC_API_KEY': 'a-key',
        }).provider,
        ProviderChoice.gemini,
      );
      expect(
        ServerConfig.fromEnv({
          'TOKEN_SECRET': testSecret,
          'ANTHROPIC_API_KEY': 'a-key',
        }).provider,
        ProviderChoice.anthropic,
      );
      expect(
        ServerConfig.fromEnv({
          ...goodEnv,
          'ANTHROPIC_API_KEY': 'a-key',
          'PROVIDER': 'anthropic',
        }).provider,
        ProviderChoice.anthropic,
      );
      expect(
        () => ServerConfig.fromEnv({...goodEnv, 'PROVIDER': 'anthropic'}),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => ServerConfig.fromEnv({...goodEnv, 'PROVIDER': 'llama'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('numbers are validated', () {
      final c = ServerConfig.fromEnv({
        ...goodEnv,
        'PORT': '9000',
        'CHAT_PER_MINUTE': '5',
        'DAILY_REQUEST_CAP': '10',
        'TRUSTED_PROXY_HOPS': '1',
      });
      expect(
        (c.port, c.chatPerMinute, c.dailyRequestCap, c.trustedProxyHops),
        (9000, 5, 10, 1),
      );
      for (final bad in [
        {'PORT': 'abc'},
        {'PORT': '0'},
        {'PORT': '70000'},
        {'CHAT_PER_MINUTE': '0'},
        {'TRUSTED_PROXY_HOPS': '-1'},
      ]) {
        expect(
          () => ServerConfig.fromEnv({...goodEnv, ...bad}),
          throwsA(isA<ConfigException>()),
          reason: '$bad',
        );
      }
    });

    test('whitespace around values is ignored', () {
      final c = ServerConfig.fromEnv({
        'TOKEN_SECRET': '  $testSecret  ',
        'GEMINI_API_KEY': ' g ',
      });
      expect(c.tokenSecret, testSecret);
      expect(c.providers.geminiApiKey, 'g');
    });
  });

  group('parseEnvFile', () {
    test('reads keys, ignores comments and blanks, strips quotes', () {
      final env = parseEnvFile('''
# a comment
PORT=8080

GEMINI_API_KEY="abc"
NAME='x y'
EMPTY=
BROKEN LINE
  SPACED = value  
''');
      expect(env['PORT'], '8080');
      expect(env['GEMINI_API_KEY'], 'abc');
      expect(env['NAME'], 'x y');
      expect(env['EMPTY'], '');
      expect(env['SPACED'], 'value');
      expect(env.containsKey('BROKEN LINE'), isFalse);
    });
  });

  group('TokenService', () {
    late DateTime now;
    TokenService make({String secret = testSecret}) => TokenService(
      secret: secret,
      ttl: const Duration(days: 30),
      clock: () => now,
    );
    setUp(() => now = DateTime.utc(2026, 9, 30, 12));

    test('issue -> verify round trip', () {
      final t = make();
      final id = t.newInstallId();
      final issued = t.issue(id);
      final identity = t.verify(issued.token)!;
      expect(identity.installId, id);
      expect(identity.expiresAt, issued.expiresAt);
      expect(issued.expiresAt, now.add(const Duration(days: 30)));
    });

    test('install ids are random, 32 hex chars', () {
      final t = make();
      final ids = {for (var i = 0; i < 50; i++) t.newInstallId()};
      expect(ids.length, 50);
      expect(ids.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('a token signed with another secret is rejected', () {
      final token = make(secret: 'x' * 40).issue('abc').token;
      expect(make().verify(token), isNull);
    });

    test('tampering with the payload or signature is detected', () {
      final t = make();
      final token = t.issue('victim').token;
      final parts = token.split('.');

      // Forge a payload for another identity, keep the old signature.
      final forged = [
        parts[0],
        parts[1].replaceFirst(parts[1][5], parts[1][5] == 'A' ? 'B' : 'A'),
        parts[2],
      ].join('.');
      expect(t.verify(forged), isNull);

      final badSig = [parts[0], parts[1], '${parts[2]}x'].join('.');
      expect(t.verify(badSig), isNull);
      expect(t.verify([parts[0], parts[1], ''].join('.')), isNull);
    });

    test('expired tokens are rejected', () {
      final t = make();
      final token = t.issue('abc').token;
      now = now.add(const Duration(days: 30, seconds: 1));
      expect(t.verify(token), isNull);
    });

    test('garbage never throws', () {
      final t = make();
      for (final junk in [
        null,
        '',
        'abc',
        'a.b',
        'a.b.c.d',
        'w1..',
        'w1.!!!.???',
        'w2.${'x' * 10}.${'y' * 10}',
      ]) {
        expect(t.verify(junk), isNull, reason: '$junk');
      }
    });
  });

  group('WindowLimiter', () {
    test('allows up to the limit, then blocks with a Retry-After', () {
      var now = DateTime.utc(2026, 1, 1, 12, 0, 20);
      final l = WindowLimiter(
        limit: 3,
        window: const Duration(minutes: 1),
        clock: () => now,
      );
      expect(
        [for (var i = 0; i < 3; i++) l.hit('a').allowed],
        [true, true, true],
      );
      final blocked = l.hit('a');
      expect(blocked.allowed, isFalse);
      expect(blocked.retryAfter, const Duration(seconds: 40));
    });

    test('resets when the next window starts', () {
      var now = DateTime.utc(2026, 1, 1, 12, 0, 20);
      final l = WindowLimiter(
        limit: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );
      expect(l.hit('a').allowed, isTrue);
      expect(l.hit('a').allowed, isFalse);
      now = now.add(const Duration(seconds: 41));
      expect(l.hit('a').allowed, isTrue);
    });

    test('keys are independent', () {
      final l = WindowLimiter(limit: 1, window: const Duration(hours: 1));
      expect(l.hit('a').allowed, isTrue);
      expect(l.hit('b').allowed, isTrue);
      expect(l.hit('a').allowed, isFalse);
    });

    test('memory stays bounded: old windows are purged', () {
      var now = DateTime.utc(2026, 1, 1);
      final l = WindowLimiter(
        limit: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );
      for (var i = 0; i < 400; i++) {
        l.hit('user$i');
      }
      now = now.add(const Duration(minutes: 5));
      for (var i = 0; i < 600; i++) {
        l.hit('other$i'); // triggers the purge of the finished window
      }
      expect(l.used('user0'), 0);
    });
  });

  group('DailyBudget', () {
    test('caps the day and refills at UTC midnight', () {
      var now = DateTime.utc(2026, 9, 30, 23, 0);
      final b = DailyBudget(cap: 2, clock: () => now);
      expect([b.tryTake(), b.tryTake(), b.tryTake()], [true, true, false]);
      expect(b.untilReset, const Duration(hours: 1));
      now = DateTime.utc(2026, 10, 1, 0, 0, 1);
      expect(b.tryTake(), isTrue);
      expect(b.used, 1);
    });
  });
}
