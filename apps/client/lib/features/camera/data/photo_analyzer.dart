import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../domain/photo_quality.dart';

/// Checks a photo on disk. Returns null when the file cannot be judged (it
/// cannot be read or decoded); the caller then simply shows no advice.
typedef PhotoQualityCheck = Future<PhotoQuality?> Function(
  String path, {
  required bool checkPlate,
});

/// Decodes the photo off the UI isolate, shrinks it and runs the local checks.
/// Nothing leaves the device and the file is only read.
Future<PhotoQuality?> assessPhotoFile(
  String path, {
  required bool checkPlate,
}) => Isolate.run(() => assessPhotoFileSync(path, checkPlate: checkPlate));

/// The synchronous core of [assessPhotoFile] (also used directly in tests).
PhotoQuality? assessPhotoFileSync(String path, {required bool checkPlate}) {
  try {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) return null;
    return assessPhoto(toGray(decoded), checkPlate: checkPlate);
  } catch (_) {
    // Decoders throw assorted errors on corrupt input; "cannot judge".
    return null;
  }
}

/// Orients the picture upright, shrinks it to the analysis size and converts
/// it to luma.
GrayImage toGray(img.Image source) {
  var image = img.bakeOrientation(source);
  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > PhotoThresholds.analysisSidePx) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: PhotoThresholds.analysisSidePx,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: PhotoThresholds.analysisSidePx,
            interpolation: img.Interpolation.average,
          );
  }
  final luma = Uint8List(image.width * image.height);
  var i = 0;
  for (final p in image) {
    luma[i++] =
        ((0.299 * p.rNormalized +
                    0.587 * p.gNormalized +
                    0.114 * p.bNormalized) *
                255)
            .round()
            .clamp(0, 255);
  }
  return GrayImage(image.width, image.height, luma);
}

/// The photo check the capture screen uses; tests replace it.
final photoQualityProvider = Provider<PhotoQualityCheck>(
  (ref) => assessPhotoFile,
);
