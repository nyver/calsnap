import 'dart:io';
import 'dart:math' as math;

import 'package:calsnap/features/camera/data/photo_analyzer.dart';
import 'package:calsnap/features/camera/domain/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A phone-sized colour "photo" of a plate, written as a real JPEG so the whole
/// path is exercised: decode, orientation, downscale, luma, checks.
File plateJpeg(
  Directory dir,
  String name, {
  int w = 800,
  int h = 600,
  double a = 240,
  double b = 240,
  double theta = 0.4,
  int blur = 0,
  double brightness = 1,
}) {
  final image = img.Image(width: w, height: h);
  final cos = math.cos(theta), sin = math.sin(theta);
  final random = math.Random(3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var r = 120.0, g = 90.0, bl = 60.0; // a wooden table
      final dx = x - w / 2, dy = y - h / 2;
      final u = (dx * cos + dy * sin) / a;
      final s = (-dx * sin + dy * cos) / b;
      final radius = math.sqrt(u * u + s * s);
      if (radius <= 1) {
        final rim = radius > 0.93;
        r = rim ? 170 : 225;
        g = rim ? 170 : 225;
        bl = rim ? 165 : 220;
        if (radius < 0.5) {
          r = 200;
          g = 150;
          bl = 70;
        }
      }
      final n = (random.nextDouble() - 0.5) * 16;
      image.setPixelRgb(
        x,
        y,
        ((r + n) * brightness).clamp(0, 255).round(),
        ((g + n) * brightness).clamp(0, 255).round(),
        ((bl + n) * brightness).clamp(0, 255).round(),
      );
    }
  }
  final out = blur > 0 ? img.gaussianBlur(image, radius: blur) : image;
  return File('${dir.path}/$name')
    ..writeAsBytesSync(img.encodeJpg(out, quality: 85));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('calsnap_photo_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a sharp top-down photo is fine, in landscape and portrait', () {
    final landscape = plateJpeg(dir, 'a.jpg');
    final portrait = plateJpeg(dir, 'b.jpg', w: 600, h: 800);
    for (final file in [landscape, portrait]) {
      final q = assessPhotoFileSync(file.path, checkPlate: true)!;
      expect(q.issues, isEmpty, reason: '${file.path}: sharp ${q.sharpness}');
      expect(q.plate, isNotNull);
      expect(q.plate!.roundness, greaterThan(0.85));
    }
  });

  test('a tilted camera is reported from the plate shape', () {
    final file = plateJpeg(dir, 'tilt.jpg', a: 300, b: 150);
    final q = assessPhotoFileSync(file.path, checkPlate: true)!;
    expect(q.plate!.roundness, closeTo(0.5, 0.1));
    expect(q.issues, contains(PhotoIssue.steepAngle));
  });

  test('a blurred photo is reported', () {
    final file = plateJpeg(dir, 'blur.jpg', blur: 14);
    final q = assessPhotoFileSync(file.path, checkPlate: true)!;
    expect(q.issues, contains(PhotoIssue.blurry));
  });

  test('a dark photo is reported', () {
    final file = plateJpeg(dir, 'dark.jpg', brightness: 0.12);
    final q = assessPhotoFileSync(file.path, checkPlate: true)!;
    expect(q.issues, contains(PhotoIssue.tooDark));
  });

  test('a side photo skips the plate checks', () {
    final file = plateJpeg(dir, 'side.jpg', a: 300, b: 90);
    final q = assessPhotoFileSync(file.path, checkPlate: false)!;
    expect(q.plate, isNull);
    expect(q.issues, isNot(contains(PhotoIssue.steepAngle)));
  });

  test('the checks read the file and leave it alone', () {
    final file = plateJpeg(dir, 'keep.jpg');
    final before = file.readAsBytesSync();
    assessPhotoFileSync(file.path, checkPlate: true);
    expect(file.readAsBytesSync(), before);
  });
}
