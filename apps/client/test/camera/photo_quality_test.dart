import 'dart:math' as math;
import 'dart:typed_data';

import 'package:calsnap/features/camera/domain/photo_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deterministic pseudo-random value in [0, 1) for a pixel.
double _hash(int x, int y, int seed) {
  var h = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return ((h ^ (h >> 16)) & 0xffff) / 0x10000;
}

/// A synthetic top-down meal: textured table, a light plate with a darker rim
/// and a textured "food" area, drawn as an ellipse of the given shape.
GrayImage plateScene({
  int w = 320,
  int h = 240,
  double cx = 160,
  double cy = 120,
  double a = 90,
  double b = 90,
  double theta = 0,
  bool plate = true,
  double table = 85,
  double noise = 8,
  int seed = 1,
}) {
  final luma = Uint8List(w * h);
  final cos = math.cos(theta), sin = math.sin(theta);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = table + (_hash(x, y, seed) - 0.5) * 2 * noise;
      if (plate) {
        final dx = x - cx, dy = y - cy;
        final u = (dx * cos + dy * sin) / a;
        final s = (-dx * sin + dy * cos) / b;
        final r = math.sqrt(u * u + s * s);
        if (r <= 1) {
          v = r > 0.93 ? 150 : 205;
          v += (_hash(x, y, seed + 5) - 0.5) * 2 * noise;
          // Some food in the middle of the plate.
          if (r < 0.45) v = 120 + (_hash(x ~/ 3, y ~/ 3, seed + 9) - 0.5) * 60;
        }
      }
      luma[y * w + x] = v.round().clamp(0, 255);
    }
  }
  return GrayImage(w, h, luma);
}

GrayImage flat(int value, {int w = 320, int h = 240}) =>
    GrayImage(w, h, Uint8List(w * h)..fillRange(0, w * h, value));

/// Box blur, several passes: a stand-in for defocus or motion blur.
GrayImage blurred(GrayImage g, {int radius = 3, int passes = 3}) {
  var cur = g.luma;
  for (var p = 0; p < passes; p++) {
    final next = Uint8List(cur.length);
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        var sum = 0, n = 0;
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= g.width || yy >= g.height) continue;
            sum += cur[yy * g.width + xx];
            n++;
          }
        }
        next[y * g.width + x] = sum ~/ n;
      }
    }
    cur = next;
  }
  return GrayImage(g.width, g.height, cur);
}

void main() {
  group('a good top-down photo', () {
    test('has no issues and a round plate', () {
      final q = assessPhoto(plateScene());
      expect(q.issues, isEmpty, reason: '$q sharp=${q.sharpness}');
      expect(q.plate, isNotNull);
      expect(q.plate!.roundness, greaterThan(0.9));
      expect(q.plate!.semiMajor, closeTo(90, 8));
      expect(q.plate!.cx, closeTo(160, 5));
      expect(q.plate!.cy, closeTo(120, 5));
    });

    test('the plate is found wherever the plate is turned', () {
      for (final theta in [0.0, 0.5, 1.2, 2.3]) {
        final q = assessPhoto(
          plateScene(a: 105, b: 80, theta: theta, cx: 150, cy: 125),
        );
        final plate = q.plate;
        expect(plate, isNotNull, reason: 'theta $theta');
        expect(
          plate!.roundness,
          closeTo(80 / 105, 0.08),
          reason: 'theta $theta',
        );
        expect(q.issues, isNot(contains(PhotoIssue.steepAngle)));
      }
    });

    test('is deterministic', () {
      final image = plateScene(a: 100, b: 60, theta: 0.7);
      final one = assessPhoto(image).plate!;
      final two = assessPhoto(image).plate!;
      expect(
        (one.cx, one.cy, one.semiMajor, one.semiMinor, one.angle),
        (two.cx, two.cy, two.semiMajor, two.semiMinor, two.angle),
      );
    });
  });

  group('camera angle', () {
    test('a plate seen at a steep angle is reported', () {
      for (final ratio in [0.35, 0.5, 0.62]) {
        final q = assessPhoto(
          plateScene(a: 110, b: 110 * ratio, theta: 0.3, cy: 120),
        );
        expect(q.plate, isNotNull, reason: 'ratio $ratio');
        expect(
          q.plate!.roundness,
          closeTo(ratio, 0.08),
          reason: 'ratio $ratio',
        );
        expect(
          q.issues,
          contains(PhotoIssue.steepAngle),
          reason: 'ratio $ratio',
        );
      }
    });

    test('a slight tilt is fine', () {
      for (final ratio in [0.8, 0.9, 1.0]) {
        final q = assessPhoto(plateScene(a: 100, b: 100 * ratio));
        expect(
          q.issues,
          isNot(contains(PhotoIssue.steepAngle)),
          reason: '$ratio',
        );
      }
    });

    test('a side photo is never judged by its angle', () {
      final q = assessPhoto(plateScene(a: 110, b: 40), checkPlate: false);
      expect(q.plate, isNull);
      expect(q.issues, isNot(contains(PhotoIssue.steepAngle)));
    });
  });

  group('plate visibility', () {
    test('a plate running out of the frame is reported', () {
      final q = assessPhoto(plateScene(cx: 250, a: 100, b: 100));
      expect(q.plate, isNotNull);
      expect(q.issues, contains(PhotoIssue.plateCutOff));
    });

    test('a plate that merely fills the frame is not', () {
      final q = assessPhoto(plateScene(a: 112, b: 112));
      expect(q.issues, isNot(contains(PhotoIssue.plateCutOff)));
    });

    test('no plate means no plate verdict at all', () {
      final q = assessPhoto(plateScene(plate: false));
      expect(q.plate, isNull);
      expect(q.issues, isEmpty, reason: 'silence, not a false alarm');
    });
  });

  group('blur', () {
    test('a sharp photo passes and a blurred one is reported', () {
      final sharp = plateScene();
      expect(assessPhoto(sharp).issues, isNot(contains(PhotoIssue.blurry)));
      final soft = assessPhoto(blurred(sharp));
      expect(soft.issues, contains(PhotoIssue.blurry));
      expect(soft.sharpness, lessThan(assessPhoto(sharp).sharpness));
    });

    test('a smooth soup on a tablecloth is not mistaken for blur', () {
      // Mostly flat, but the plate rim and a few details are crisp.
      final q = assessPhoto(plateScene(noise: 1));
      expect(
        q.issues,
        isNot(contains(PhotoIssue.blurry)),
        reason: '${q.sharpness}',
      );
    });

    test('a tiny picture cannot be judged', () {
      expect(assessPhoto(flat(120, w: 10, h: 10)).issues, isEmpty);
    });
  });

  group('brightness', () {
    test('dark, bright and blown-out pictures', () {
      final dim = plateScene();
      for (var i = 0; i < dim.luma.length; i++) {
        dim.luma[i] = dim.luma[i] ~/ 6;
      }
      expect(assessPhoto(dim).issues, contains(PhotoIssue.tooDark));
      expect(assessPhoto(flat(20)).issues, contains(PhotoIssue.tooDark));
      expect(assessPhoto(flat(240)).issues, contains(PhotoIssue.tooBright));
      // Mid-gray on average but a third of it is pure white.
      final glare = plateScene(table: 100);
      for (var i = 0; i < glare.luma.length ~/ 2.5; i++) {
        glare.luma[i] = 255;
      }
      expect(assessPhoto(glare).issues, contains(PhotoIssue.tooBright));
    });

    test('ordinary indoor light is fine', () {
      final q = assessPhoto(plateScene(table: 70));
      expect(q.issues, isNot(contains(PhotoIssue.tooDark)));
      expect(q.issues, isNot(contains(PhotoIssue.tooBright)));
    });
  });

  test('several problems are all reported', () {
    final q = assessPhoto(blurred(plateScene(table: 15, b: 40, a: 110)));
    expect(q.issues, containsAll([PhotoIssue.blurry, PhotoIssue.tooDark]));
  });
}
