import 'dart:convert';
import 'dart:typed_data';

import 'package:calsnap/features/camera/data/image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fixtures.dart';

bool containsBytes(Uint8List haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

Uint8List gradientJpeg(int width, int height, {bool withGps = false}) {
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ width
      ..g = p.y * 255 ~/ height
      ..b = 128;
  }
  if (withGps) {
    image.exif.gpsIfd.data[0x0002] = img.IfdValueAscii('55.7558');
    image.exif.exifIfd.data[0x010F] = img.IfdValueAscii('SecretCamera');
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  test('applies EXIF orientation to the pixels and strips all metadata', () {
    final source = protocolFile('fixtures/sample-exif-rotated.jpg')
        .readAsBytesSync();
    // Precondition: the fixture really carries EXIF.
    expect(containsBytes(source, ascii.encode('Exif')), isTrue);
    expect(containsBytes(source, ascii.encode('CalSnapTestCamera')), isTrue);

    final out = prepareImageSync(
      source,
      maxLongSidePx: 1280,
      jpegQuality: 85,
      maxBytes: 1 << 20,
    );

    // 60x30 stored with orientation 6 is a 30x60 portrait photo.
    expect((out.width, out.height), (30, 60));
    expect(containsBytes(out.jpeg, ascii.encode('Exif')), isFalse);
    expect(containsBytes(out.jpeg, ascii.encode('CalSnapTestCamera')), isFalse);
    expect(
      containsBytes(out.jpeg, [0xFF, 0xE1]),
      isFalse,
      reason: 'no APP1 segment',
    );

    // The blue left half of the stored image ends up at the top after rotating 90 degrees clockwise.
    final decoded = img.decodeJpg(out.jpeg)!;
    final top = decoded.getPixel(15, 5);
    final bottom = decoded.getPixel(15, 55);
    expect(top.b, greaterThan(top.r), reason: 'top is blue');
    expect(bottom.r, greaterThan(bottom.b), reason: 'bottom is red');
  });

  test('downscales a 4000x3000 photo with GPS EXIF to 1280x960', () {
    final source = gradientJpeg(4000, 3000, withGps: true);
    expect(containsBytes(source, ascii.encode('SecretCamera')), isTrue);

    final out = prepareImageSync(
      source,
      maxLongSidePx: 1280,
      jpegQuality: 85,
      maxBytes: 4 << 20,
    );
    expect((out.width, out.height), (1280, 960));
    expect(containsBytes(out.jpeg, ascii.encode('SecretCamera')), isFalse);
    expect(containsBytes(out.jpeg, ascii.encode('Exif')), isFalse);
    expect(img.decodeJpg(out.jpeg)!.width, 1280);
  });

  test('portrait photos are limited by their height', () {
    final out = prepareImageSync(
      gradientJpeg(1500, 3000),
      maxLongSidePx: 1280,
      jpegQuality: 80,
      maxBytes: 4 << 20,
    );
    expect((out.width, out.height), (640, 1280));
  });

  test('small photos are not enlarged', () {
    final out = prepareImageSync(
      gradientJpeg(400, 300),
      maxLongSidePx: 1280,
      jpegQuality: 80,
      maxBytes: 4 << 20,
    );
    expect((out.width, out.height), (400, 300));
  });

  test('the configured long side and quality are honoured', () {
    final source = gradientJpeg(1000, 800);
    final small = prepareImageSync(
      source,
      maxLongSidePx: 512,
      jpegQuality: 50,
      maxBytes: 4 << 20,
    );
    expect(small.width, 512);
    final low = prepareImageSync(
      source,
      maxLongSidePx: 1280,
      jpegQuality: 30,
      maxBytes: 4 << 20,
    );
    final high = prepareImageSync(
      source,
      maxLongSidePx: 1280,
      jpegQuality: 95,
      maxBytes: 4 << 20,
    );
    expect(low.jpeg.length, lessThan(high.jpeg.length));
  });

  test('PNG and WebP sources are converted to JPEG', () {
    for (final name in ['sample.png', 'sample.webp']) {
      final out = prepareImageSync(
        protocolFile('fixtures/$name').readAsBytesSync(),
        maxLongSidePx: 1280,
        jpegQuality: 85,
        maxBytes: 1 << 20,
      );
      expect(out.jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF], reason: name);
      expect((out.width, out.height), (64, 48), reason: name);
    }
  });

  test('undecodable files are rejected', () {
    for (final bytes in [
      Uint8List.fromList(utf8.encode('this is not an image')),
      protocolFile('fixtures/corrupt.jpg').readAsBytesSync(),
      Uint8List(0),
    ]) {
      expect(
        () => prepareImageSync(
          bytes,
          maxLongSidePx: 1280,
          jpegQuality: 85,
          maxBytes: 1 << 20,
        ),
        throwsA(
          isA<ImagePrepareException>().having(
            (e) => e.problem,
            'problem',
            ImagePrepareProblem.undecodable,
          ),
        ),
      );
    }
  });

  test('results above the upload limit are rejected', () {
    expect(
      () => prepareImageSync(
        gradientJpeg(800, 600),
        maxLongSidePx: 1280,
        jpegQuality: 95,
        maxBytes: 1024,
      ),
      throwsA(
        isA<ImagePrepareException>().having(
          (e) => e.problem,
          'problem',
          ImagePrepareProblem.tooLarge,
        ),
      ),
    );
  });

  test('runs in a background isolate', () async {
    final out = await prepareImage(
      gradientJpeg(2000, 1000),
      maxLongSidePx: 1280,
      jpegQuality: 85,
      maxBytes: 4 << 20,
    );
    expect((out.width, out.height), (1280, 640));
  });
}
