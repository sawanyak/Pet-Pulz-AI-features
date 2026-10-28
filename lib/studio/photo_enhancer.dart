import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Instagram feed shapes.
enum StudioAspect {
  portrait('4:5', 4 / 5), // the tallest allowed feed shape: most screen space
  square('1:1', 1),
  original('Original', null);

  const StudioAspect(this.label, this.ratio);

  final String label;

  /// width / height, or null to keep the photo's own shape.
  final double? ratio;
}

class EnhancementException implements Exception {
  EnhancementException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A rectangle in pixels.
class CropBox {
  const CropBox(this.x, this.y, this.width, this.height);
  final int x, y, width, height;

  @override
  bool operator ==(Object other) =>
      other is CropBox &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'CropBox($x, $y, $width x $height)';
}

/// Works out which part of a [width] x [height] photo to keep for the given
/// [aspect] (width / height), centred on the focus point ([focusX],
/// [focusY], each 0..1) but never leaving the photo.
///
/// Example: a wide 1000x500 photo cropped to 4:5 keeps a 400x500 slice. With
/// the cat's face at focusX 0.9 the slice is centred at x=900, i.e. from 700,
/// but that would run past the edge, so it slides back to 600..1000.
CropBox computeCrop({
  required int width,
  required int height,
  required double? aspect,
  required double focusX,
  required double focusY,
}) {
  if (aspect == null) return CropBox(0, 0, width, height);

  final current = width / height;
  if ((current - aspect).abs() < 0.005) return CropBox(0, 0, width, height);

  if (current > aspect) {
    // Too wide: keep full height, cut the sides.
    final w = (height * aspect).round().clamp(1, width);
    final x = (focusX * width - w / 2).round().clamp(0, width - w);
    return CropBox(x, 0, w, height);
  } else {
    // Too tall: keep full width, cut top and bottom.
    final h = (width / aspect).round().clamp(1, height);
    final y = (focusY * height - h / 2).round().clamp(0, height - h);
    return CropBox(0, y, width, h);
  }
}

/// Makes a photo Instagram-ready. An interface so tests can skip the heavy
/// image work.
abstract class PhotoEnhancer {
  Future<Uint8List> enhance(
    Uint8List bytes, {
    required double focusX,
    required double focusY,
    required StudioAspect aspect,
  });
}

/// Does the work on a background isolate. Decoding and processing a
/// photo can take a second or more; on the main isolate that would freeze the
/// screen (the loading spinner would stop spinning).
class IsolatePhotoEnhancer implements PhotoEnhancer {
  @override
  Future<Uint8List> enhance(
    Uint8List bytes, {
    required double focusX,
    required double focusY,
    required StudioAspect aspect,
  }) {
    final ratio = aspect.ratio;
    return Isolate.run(
      () => enhanceJpeg(bytes, focusX: focusX, focusY: focusY, aspect: ratio),
    );
  }
}

/// The actual pipeline (synchronous, so it is easy to test):
///   1. decode and fix the phone's rotation flag,
///   2. crop to the chosen shape around the pet,
///   3. shrink to Instagram's 1080 px width,
///   4. auto-tone: stretch contrast, lift dark photos, slightly richer colour,
///   5. encode as a high-quality JPEG.
Uint8List enhanceJpeg(
  Uint8List bytes, {
  required double focusX,
  required double focusY,
  required double? aspect,
  int maxWidth = 1080,
  int quality = 90,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null; // some decoders throw on damaged data instead of null
  }
  if (decoded == null) {
    throw EnhancementException('That photo format isn\'t supported.');
  }
  var image = decoded;
  // Phones often store a photo sideways plus a "rotate me" flag. Apply it.
  image = img.bakeOrientation(image);
  // Normalise to plain 8-bit RGB so the maths below is simple.
  image = image.convert(format: img.Format.uint8, numChannels: 3);

  final box = computeCrop(
    width: image.width,
    height: image.height,
    aspect: aspect,
    focusX: focusX,
    focusY: focusY,
  );
  if (box.width != image.width || box.height != image.height) {
    image = img.copyCrop(
      image,
      x: box.x,
      y: box.y,
      width: box.width,
      height: box.height,
    );
  }

  if (image.width > maxWidth) {
    image = img.copyResize(
      image,
      width: maxWidth,
      interpolation: img.Interpolation.average,
    );
  }

  _autoTone(image);
  return img.encodeJpg(image, quality: quality);
}

/// Automatic exposure + contrast + colour, in one pass over the pixels.
///
/// Idea: build a 256-entry lookup table (input brightness -> output
/// brightness) from the photo's own histogram, then apply it to every pixel.
///  * Contrast: brightness values below the darkest 0.5% and above the
///    brightest 0.5% are treated as pure black / pure white, stretching the
///    rest to fill the range ("auto levels"). Blended 80/20 with the original
///    so it never looks harsh.
///  * Exposure: a gamma curve nudges the average brightness toward mid-grey.
///    Dark photos are lifted a lot; bright photos are only darkened a little
///    (a white cat on snow should stay bright).
///  * Colour: a gentle 8% saturation boost.
void _autoTone(img.Image image) {
  final total = image.width * image.height;
  final hist = List<int>.filled(256, 0);
  for (final p in image) {
    hist[_luma(p.r, p.g, p.b).round().clamp(0, 255)]++;
  }

  int percentile(double fraction) {
    final target = total * fraction;
    var sum = 0;
    for (var i = 0; i < 256; i++) {
      sum += hist[i];
      if (sum >= target) return i;
    }
    return 255;
  }

  final rawLo = percentile(0.005);
  final rawHi = percentile(0.995);
  // A nearly flat photo (fog, a solid colour) would be blown up into noise.
  final canStretch = rawHi - rawLo >= 30;
  // Don't let the stretch move the black / white points too far: a bright
  // photo (snow, a white cat) must not have its light tones dragged down to
  // grey just because it has no dark pixels. So "black" is at most 40 and
  // "white" at least 215.
  final lo = math.min(rawLo, 40);
  final hi = math.max(rawHi, 215);
  final range = hi - lo;

  double stretched(int i) {
    final original = i / 255;
    if (!canStretch) return original;
    final full = ((i - lo) / range).clamp(0.0, 1.0);
    return 0.8 * full + 0.2 * original;
  }

  // Average brightness after stretching, to choose the gamma.
  var mean = 0.0;
  for (var i = 0; i < 256; i++) {
    mean += hist[i] * stretched(i);
  }
  mean /= total;

  var gamma = 1.0;
  if (mean > 0.02 && mean < 0.98 && (mean < 0.42 || mean > 0.58)) {
    gamma = (math.log(0.47) / math.log(mean)).clamp(0.6, 1.15);
  }

  final lut = List<int>.generate(
    256,
    (i) => (math.pow(stretched(i), gamma) * 255).round().clamp(0, 255),
  );

  const saturation = 1.08;
  for (final p in image) {
    final r = lut[p.r.toInt()];
    final g = lut[p.g.toInt()];
    final b = lut[p.b.toInt()];
    final l = _luma(r, g, b);
    p.r = (l + (r - l) * saturation).round().clamp(0, 255);
    p.g = (l + (g - l) * saturation).round().clamp(0, 255);
    p.b = (l + (b - l) * saturation).round().clamp(0, 255);
  }
}

double _luma(num r, num g, num b) => 0.299 * r + 0.587 * g + 0.114 * b;
