import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A photo ready for upload.
class PreparedImage {
  const PreparedImage({
    required this.jpeg,
    required this.width,
    required this.height,
  });

  final Uint8List jpeg;
  final int width;
  final int height;
}

enum ImagePrepareProblem { undecodable, tooLarge }

class ImagePrepareException implements Exception {
  const ImagePrepareException(this.problem);

  final ImagePrepareProblem problem;

  @override
  String toString() => 'ImagePrepareException($problem)';
}

/// Decodes, orients, downscales and re-encodes a photo off the UI isolate.
///
/// Re-encoding drops all metadata (EXIF including GPS). The orientation is
/// applied to the pixels first, so the upload is upright without EXIF.
Future<PreparedImage> prepareImage(
  Uint8List source, {
  required int maxLongSidePx,
  required int jpegQuality,
  required int maxBytes,
}) => Isolate.run(
  () => prepareImageSync(
    source,
    maxLongSidePx: maxLongSidePx,
    jpegQuality: jpegQuality,
    maxBytes: maxBytes,
  ),
);

/// The synchronous core of [prepareImage] (also used directly in tests).
PreparedImage prepareImageSync(
  Uint8List source, {
  required int maxLongSidePx,
  required int jpegQuality,
  required int maxBytes,
}) {
  final decoded = _decode(source);
  var image = img.bakeOrientation(decoded);

  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > maxLongSidePx) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxLongSidePx,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxLongSidePx,
            interpolation: img.Interpolation.average,
          );
  }
  // Belt and braces: make sure no metadata survives into the encoder.
  image.exif.clear();

  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: jpegQuality));
  if (jpeg.length > maxBytes) {
    throw const ImagePrepareException(ImagePrepareProblem.tooLarge);
  }
  return PreparedImage(jpeg: jpeg, width: image.width, height: image.height);
}

img.Image _decode(Uint8List source) {
  if (source.isNotEmpty) {
    try {
      final decoded = img.decodeImage(source);
      if (decoded != null) return decoded;
    } catch (_) {
      // Decoders throw assorted errors (RangeError, FormatException, ...) on
      // corrupt input; every one of them means "not a usable image".
    }
  }
  throw const ImagePrepareException(ImagePrepareProblem.undecodable);
}
