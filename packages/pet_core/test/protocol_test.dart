import 'dart:convert';
import 'dart:typed_data';

import 'package:pet_core/pet_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> msg(String role, String text) => {
  'role': role,
  'text': text,
};

Map<String, dynamic> photoJson({
  String mime = 'image/jpeg',
  List<int> bytes = const [1, 2, 3],
}) => {'mimeType': mime, 'data': base64Encode(bytes)};

void main() {
  group('ChatRequest', () {
    test('round trip', () {
      final req = ChatRequest(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            text: 'hi',
            timestamp: DateTime(2026),
          ),
        ],
        cat: const CatProfile(name: 'Luna', ageYears: 3),
        spoken: true,
      );
      final back = ChatRequest.fromJson(jsonDecode(jsonEncode(req.toJson())));
      expect(back.messages.single.text, 'hi');
      expect(back.cat?.name, 'Luna');
      expect(back.cat?.ageYears, 3);
      expect(back.spoken, isTrue);
    });

    test('rejects malformed requests with a readable message', () {
      void bad(Object? json, String contains_) => expect(
        () => ChatRequest.fromJson(json),
        throwsA(
          isA<RequestValidationException>().having(
            (e) => e.message,
            'message',
            contains_.isEmpty
                ? isNotEmpty
                : anyOf(contains(contains_), contains(contains_.toLowerCase())),
          ),
        ),
        reason: '$json',
      );

      bad(null, '');
      bad('text', '');
      bad({}, 'messages');
      bad({'messages': []}, 'messages');
      bad({'messages': 'x'}, 'messages');
      bad({
        'messages': [msg('system', 'hi')],
      }, 'role');
      bad({
        'messages': [msg('user', '')],
      }, 'empty');
      bad({
        'messages': [msg('user', '   ')],
      }, 'empty');
      bad({
        'messages': [
          {'role': 'user', 'text': 5},
        ],
      }, 'text');
      bad({
        'messages': [msg('user', 'x' * (ApiLimits.maxMessageChars + 1))],
      }, 'too long');
      bad({
        'messages': [
          for (var i = 0; i < ApiLimits.maxMessages + 1; i++)
            msg(i.isEven ? 'user' : 'assistant', 'hi'),
        ],
      }, 'Too many');
    });

    test('the whole conversation has a size cap', () {
      final long = 'x' * ApiLimits.maxMessageChars;
      expect(
        () => ChatRequest.fromJson({
          'messages': [
            for (var i = 0; i < 9; i++)
              msg(i.isEven ? 'user' : 'assistant', long),
          ],
        }),
        throwsA(isA<RequestValidationException>()),
      );
    });

    test('must start and end with the user', () {
      expect(
        () => ChatRequest.fromJson({
          'messages': [msg('assistant', 'hi'), msg('user', 'q')],
        }),
        throwsA(isA<RequestValidationException>()),
      );
      expect(
        () => ChatRequest.fromJson({
          'messages': [msg('user', 'q'), msg('assistant', 'a')],
        }),
        throwsA(isA<RequestValidationException>()),
      );
    });

    test('a broken or nameless cat is ignored, not fatal', () {
      final ok = ChatRequest.fromJson({
        'messages': [msg('user', 'q')],
        'cat': {'name': '   '},
      });
      expect(ok.cat, isNull);
      expect(
        () => ChatRequest.fromJson({
          'messages': [msg('user', 'q')],
          'cat': 'not an object',
        }),
        throwsA(isA<RequestValidationException>()),
      );
    });
  });

  group('ChatEvent', () {
    test('round trips and tolerates unknown events', () {
      ChatEvent rt(ChatEvent e) =>
          ChatEvent.fromJson(jsonDecode(jsonEncode(e.toJson())));
      expect((rt(const ChatDelta('hello')) as ChatDelta).text, 'hello');
      final err = rt(const ChatError('busy', 'Try later')) as ChatError;
      expect((err.code, err.message), ('busy', 'Try later'));
      expect(rt(const ChatDone()), isA<ChatDone>());
      expect(ChatEvent.fromJson({'type': 'mystery'}), isA<ChatDelta>());
    });
  });

  group('WirePhoto', () {
    test('round trip keeps the bytes', () {
      final p = WirePhoto(
        mimeType: 'image/png',
        bytes: Uint8List.fromList([9, 8, 7]),
      );
      final back = WirePhoto.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.bytes, [9, 8, 7]);
      expect(back.mimeType, 'image/png');
    });

    test('rejects bad photos', () {
      void bad(Object? json) => expect(
        () => WirePhoto.fromJson(json),
        throwsA(isA<RequestValidationException>()),
        reason: '$json',
      );
      bad(photoJson(mime: 'application/pdf'));
      bad(photoJson(mime: 'image/svg+xml'));
      bad({'mimeType': 'image/jpeg'});
      bad({'mimeType': 'image/jpeg', 'data': ''});
      bad({'mimeType': 'image/jpeg', 'data': '!!!not base64!!!'});
      bad(photoJson(bytes: List.filled(ApiLimits.maxPhotoBytes + 1, 1)));
      bad('nope');
    });

    test('an oversize photo is refused without decoding it', () {
      // If decoding happened first this would allocate 60 MB.
      final huge = 'A' * (60 * 1024 * 1024);
      expect(
        () => WirePhoto.fromJson({'mimeType': 'image/jpeg', 'data': huge}),
        throwsA(isA<RequestValidationException>()),
      );
    });
  });

  group('ScreenRequest', () {
    test('round trip', () {
      final req = ScreenRequest(
        photos: [
          WirePhoto(mimeType: 'image/jpeg', bytes: Uint8List.fromList([1])),
        ],
        concern: 'red eye',
        duration: 'A few days',
        cat: const CatProfile(name: 'Luna'),
      );
      final back = ScreenRequest.fromJson(jsonDecode(jsonEncode(req.toJson())));
      expect(back.concern, 'red eye');
      expect(back.duration, 'A few days');
      expect(back.photos.length, 1);
      expect(back.cat?.name, 'Luna');
    });

    test('enforces limits', () {
      void bad(Map<String, dynamic> json) => expect(
        () => ScreenRequest.fromJson(json),
        throwsA(isA<RequestValidationException>()),
        reason: '$json',
      );
      bad({});
      bad({'photos': []});
      bad({
        'photos': [for (var i = 0; i < 4; i++) photoJson()],
      });
      bad({
        'photos': [photoJson()],
        'concern': 'x' * 301,
      });
      bad({
        'photos': [photoJson()],
        'duration': 'x' * 41,
      });
    });
  });

  group('StudioRequest', () {
    test('round trip and limits', () {
      final req = StudioRequest(
        photo: WirePhoto(mimeType: 'image/png', bytes: Uint8List.fromList([1])),
        note: 'first snow',
      );
      final back = StudioRequest.fromJson(jsonDecode(jsonEncode(req.toJson())));
      expect(back.note, 'first snow');
      expect(
        () => StudioRequest.fromJson({'photo': photoJson(), 'note': 'x' * 121}),
        throwsA(isA<RequestValidationException>()),
      );
      expect(
        () => StudioRequest.fromJson({}),
        throwsA(isA<RequestValidationException>()),
      );
    });
  });

  group('result JSON', () {
    test('HealthScreening survives toJson -> fromJson', () {
      const original = HealthScreening(
        urgency: Urgency.seeVetSoon,
        summary: 'Red patch.',
        observations: ['red'],
        possibleCauses: ['allergy'],
        homeCare: ['keep clean'],
        seeVetIf: ['worse'],
        photoNote: 'closer',
      );
      final back = HealthScreening.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(back.urgency, Urgency.seeVetSoon);
      expect(back.observations, ['red']);
      expect(back.photoNote, 'closer');
      for (final u in Urgency.values) {
        final round = HealthScreening.fromJson(
          HealthScreening(urgency: u, summary: '').toJson(),
        );
        expect(round.urgency, u);
      }
    });

    test('ContentSuggestion survives toJson -> fromJson', () {
      const original = ContentSuggestion(
        mood: PetMood.regal,
        focusX: 0.25,
        focusY: 0.75,
        subject: 'a waterfall',
        captions: [CaptionOption(tone: 'funny', text: 'Ha')],
        hashtags: ['catsofinstagram', 'lazysunday'],
      );
      final back = ContentSuggestion.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(back.mood, PetMood.regal);
      expect((back.focusX, back.focusY), (0.25, 0.75));
      expect(back.captions.single.text, 'Ha');
      expect(back.hashtags, ['catsofinstagram', 'lazysunday']);
    });
  });

  test('errorJson has the documented shape', () {
    expect(errorJson('busy', 'later'), {
      'error': {'code': 'busy', 'message': 'later'},
    });
  });
}
