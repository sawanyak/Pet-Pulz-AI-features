import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pet_core/pet_core.dart';
import 'package:pet_care_ai/studio/photo_enhancer.dart';

/// Average brightness (0-255) of a decoded image.
double meanLuma(img.Image im) {
  var sum = 0.0;
  for (final p in im) {
    sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }
  return sum / (im.width * im.height);
}

/// A photo of smooth horizontal gradient between two brightness levels.
Uint8List gradientJpeg(int w, int h, int from, int to) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    final v = (from + (to - from) * p.x / (w - 1)).round();
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return img.encodeJpg(im, quality: 95);
}

void main() {
  group('computeCrop', () {
    test('wide photo -> 4:5 keeps full height, cuts the sides', () {
      final box = computeCrop(
        width: 1000,
        height: 500,
        aspect: 0.8,
        focusX: 0.5,
        focusY: 0.5,
      );
      expect(box, const CropBox(300, 0, 400, 500)); // centred
    });

    test('follows the focus point', () {
      final box = computeCrop(
        width: 1000,
        height: 500,
        aspect: 0.8,
        focusX: 0.2,
        focusY: 0.5,
      );
      expect(box, const CropBox(0, 0, 400, 500)); // hugs the left edge
    });

    test('never leaves the photo (focus near the right edge)', () {
      final box = computeCrop(
        width: 1000,
        height: 500,
        aspect: 0.8,
        focusX: 0.95,
        focusY: 0.5,
      );
      expect(box, const CropBox(600, 0, 400, 500));
      expect(box.x + box.width, lessThanOrEqualTo(1000));
    });

    test('tall photo -> 1:1 cuts top and bottom around the focus', () {
      final box = computeCrop(
        width: 800,
        height: 1600,
        aspect: 1,
        focusX: 0.5,
        focusY: 0.25,
      );
      expect(box, const CropBox(0, 0, 800, 800)); // 0.25*1600-400 = 0
      final lower = computeCrop(
        width: 800,
        height: 1600,
        aspect: 1,
        focusX: 0.5,
        focusY: 0.6,
      );
      expect(lower.y, 560);
    });

    test('original or already-right shape keeps everything', () {
      expect(
        computeCrop(
          width: 640,
          height: 480,
          aspect: null,
          focusX: .5,
          focusY: .5,
        ),
        const CropBox(0, 0, 640, 480),
      );
      expect(
        computeCrop(
          width: 800,
          height: 1000,
          aspect: 0.8,
          focusX: .1,
          focusY: .9,
        ),
        const CropBox(0, 0, 800, 1000),
      );
    });
  });

  group('enhanceJpeg', () {
    test('output is a 4:5 JPEG no wider than 1080', () {
      final out = enhanceJpeg(
        gradientJpeg(2000, 1500, 30, 220),
        focusX: 0.5,
        focusY: 0.5,
        aspect: 0.8,
      );
      final im = img.decodeJpg(out)!;
      expect(im.width, lessThanOrEqualTo(1080));
      expect(im.width / im.height, closeTo(0.8, 0.01));
    });

    test('never upscales small photos', () {
      final out = enhanceJpeg(
        gradientJpeg(300, 200, 30, 220),
        focusX: 0.5,
        focusY: 0.5,
        aspect: null,
      );
      final im = img.decodeJpg(out)!;
      expect((im.width, im.height), (300, 200));
    });

    test('a dark photo gets brighter', () {
      final dark = gradientJpeg(400, 300, 5, 90);
      final before = meanLuma(img.decodeJpg(dark)!);
      final after = meanLuma(
        img.decodeJpg(enhanceJpeg(dark, focusX: .5, focusY: .5, aspect: null))!,
      );
      expect(after, greaterThan(before + 20));
    });

    test('a low-contrast photo gets more contrast', () {
      final flat = gradientJpeg(400, 300, 100, 150);
      spread(Uint8List b) {
        final im = img.decodeJpg(b)!;
        final left = im.getPixel(2, 150).r.toDouble();
        final right = im.getPixel(im.width - 3, 150).r.toDouble();
        return right - left;
      }

      final after = enhanceJpeg(flat, focusX: .5, focusY: .5, aspect: null);
      expect(spread(after), greaterThan(spread(flat) + 15));
    });

    test('a well-exposed photo stays close to how it was', () {
      final good = gradientJpeg(400, 300, 10, 245);
      final before = meanLuma(img.decodeJpg(good)!);
      final after = meanLuma(
        img.decodeJpg(enhanceJpeg(good, focusX: .5, focusY: .5, aspect: null))!,
      );
      expect((after - before).abs(), lessThan(15));
    });

    test('a bright photo is not darkened much', () {
      final bright = gradientJpeg(400, 300, 170, 255);
      final before = meanLuma(img.decodeJpg(bright)!);
      final after = meanLuma(
        img.decodeJpg(
          enhanceJpeg(bright, focusX: .5, focusY: .5, aspect: null),
        )!,
      );
      expect(after, greaterThan(before - 40));
    });

    test('a flat single-colour photo does not blow up', () {
      final im = img.Image(width: 200, height: 200);
      img.fill(im, color: img.ColorRgb8(120, 120, 120));
      final out = enhanceJpeg(
        img.encodeJpg(im),
        focusX: .5,
        focusY: .5,
        aspect: null,
      );
      final result = img.decodeJpg(out)!;
      expect(meanLuma(result), closeTo(120, 25));
    });

    test('the crop keeps the pet: a red square at the far right survives', () {
      // 1000x500 grey photo with a red square around x=850..950.
      final im = img.Image(width: 1000, height: 500);
      img.fill(im, color: img.ColorRgb8(128, 128, 128));
      img.fillRect(
        im,
        x1: 850,
        y1: 200,
        x2: 950,
        y2: 300,
        color: img.ColorRgb8(230, 20, 20),
      );
      final out = enhanceJpeg(
        img.encodeJpg(im, quality: 98),
        focusX: 0.9,
        focusY: 0.5,
        aspect: 0.8,
      );
      final result = img.decodeJpg(out)!;

      // The square sat at 850-950 of 1000, i.e. 250-350 of the 400px slice
      // that starts at x=600. Its centre must still be strongly red.
      final c = result.getPixel(300, 250);
      expect(c.r, greaterThan(180));
      expect(c.g, lessThan(90));
    });

    test('the same crop with a WRONG focus would lose the pet', () {
      final im = img.Image(width: 1000, height: 500);
      img.fill(im, color: img.ColorRgb8(128, 128, 128));
      img.fillRect(
        im,
        x1: 850,
        y1: 200,
        x2: 950,
        y2: 300,
        color: img.ColorRgb8(230, 20, 20),
      );
      final out = enhanceJpeg(
        img.encodeJpg(im, quality: 98),
        focusX: 0.1,
        focusY: 0.5,
        aspect: 0.8,
      ); // looking left
      final result = img.decodeJpg(out)!;
      var redPixels = 0;
      for (final p in result) {
        if (p.r > 180 && p.g < 90) redPixels++;
      }
      expect(redPixels, 0);
    });

    test('garbage bytes give a friendly error', () {
      expect(
        () => enhanceJpeg(
          Uint8List.fromList([1, 2, 3, 4]),
          focusX: .5,
          focusY: .5,
          aspect: null,
        ),
        throwsA(isA<EnhancementException>()),
      );
    });

    test(
      'a typical 12-megapixel-sized photo is processed in reasonable time',
      () {
        final big = gradientJpeg(2048, 1536, 20, 200);
        final sw = Stopwatch()..start();
        enhanceJpeg(big, focusX: .5, focusY: .5, aspect: 0.8);
        sw.stop();
        // Debug/JIT is much slower than a release build; this is a sanity cap.
        expect(sw.elapsedMilliseconds, lessThan(15000));
      },
    );
  });

  group('ContentSuggestion.fromJson', () {
    test('parses a full result', () {
      final s = ContentSuggestion.fromJson({
        'mood': 'sleepy',
        'focus': {'x': 0.3, 'y': 0.6},
        'subject': ' a cat napping ',
        'captions': [
          {'tone': 'Funny', 'text': ' Nap time. '},
          {'tone': 'sweet', 'text': 'Dreams.'},
        ],
        'hashtags': ['#CatsOfInstagram', 'lazy sunday', 'catsofinstagram', 'x'],
      });
      expect(s.mood, PetMood.sleepy);
      expect((s.focusX, s.focusY), (0.3, 0.6));
      expect(s.subject, 'a cat napping');
      expect(s.captions.first.tone, 'funny');
      expect(s.captions.first.text, 'Nap time.');
      // '#' and spaces removed, duplicate (any case) and 1-char tags dropped
      expect(s.hashtags, ['CatsOfInstagram', 'lazysunday']);
    });

    test('bad values fall back safely', () {
      final s = ContentSuggestion.fromJson({
        'mood': 'furious',
        'focus': {'x': 7, 'y': -3},
        'captions': [
          'not a map',
          {'text': '   '},
          {'tone': 'ok', 'text': 'Fine'},
        ],
        'hashtags': 'nope',
      });
      expect(s.mood, PetMood.sweet);
      expect((s.focusX, s.focusY), (1.0, 0.0)); // clamped
      expect(s.captions.length, 1);
      expect(s.hashtags, isEmpty);
      expect(ContentSuggestion.fromJson({}).focusX, 0.5);
    });

    test('Instagram limits are enforced', () {
      final s = ContentSuggestion.fromJson({
        'captions': [
          {'tone': 'long', 'text': 'a' * 3000},
        ],
        'hashtags': [for (var i = 0; i < 50; i++) 'tag$i'],
      });
      expect(s.captions.first.text.length, instagramMaxCaptionLength);
      expect(s.hashtags.length, instagramMaxHashtags);
    });
  });

  test('composePost joins caption and hashtags', () {
    expect(composePost(' Hi ', ['a1', 'b2']), 'Hi\n\n#a1 #b2');
    expect(composePost('Hi', []), 'Hi');
    expect(composePost('', ['a1']), '#a1');
  });
}
