import '../../../core/domain/nutrition.dart';

/// One recognized food as returned by the backend.
class RecognizedItem {
  const RecognizedItem({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.estimatedWeightG,
    required this.confidence,
    required this.nutritionSource,
    required this.per100,
  });

  factory RecognizedItem.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition'] as Map<String, dynamic>;
    return RecognizedItem(
      id: json['id'] as String,
      name: json['name'] as String,
      normalizedName: json['normalizedName'] as String,
      estimatedWeightG: (json['estimatedWeightG'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      nutritionSource: json['nutritionSource'] as String,
      per100: Nutrition(
        kcal: (nutrition['kcalPer100g'] as num).toDouble(),
        protein: (nutrition['proteinPer100g'] as num).toDouble(),
        fat: (nutrition['fatPer100g'] as num).toDouble(),
        carbs: (nutrition['carbsPer100g'] as num).toDouble(),
      ),
    );
  }

  final String id;
  final String name;
  final String normalizedName;
  final double estimatedWeightG;
  final double confidence;

  /// `catalog` or `ai_estimate`.
  final String nutritionSource;
  final Nutrition per100;
}

/// The response of `POST /v1/meals/analyze`.
class AnalysisResult {
  const AnalysisResult({
    required this.requestId,
    required this.items,
    required this.warnings,
  });

  /// Throws [FormatException] when the payload does not match the contract.
  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    try {
      return AnalysisResult(
        requestId: json['requestId'] as String,
        items: [
          for (final item in json['items'] as List<dynamic>)
            RecognizedItem.fromJson(item as Map<String, dynamic>),
        ],
        warnings: (json['warnings'] as List<dynamic>).cast<String>().toSet(),
      );
    } on TypeError catch (e) {
      throw FormatException('Unexpected analysis response shape: $e');
    }
  }

  final String requestId;
  final List<RecognizedItem> items;
  final Set<String> warnings;
}

/// Warning codes of the analyze response.
abstract final class WarningCode {
  static const noFoodDetected = 'NO_FOOD_DETECTED';
  static const partialRecognition = 'PARTIAL_RECOGNITION';
  static const lowConfidence = 'LOW_CONFIDENCE';
  static const nutritionEstimated = 'NUTRITION_ESTIMATED';
}

/// Client-safe tunables from `GET /v1/config`, with local defaults.
class RemoteConfig {
  const RemoteConfig({
    this.imageMaxLongSidePx = 1280,
    this.imageJpegQuality = 85,
    this.maxUploadBytes = 4 * 1024 * 1024,
    this.analyzeTimeoutSeconds = 60,
    this.maxImages = 1,
    this.barcodeLookup = false,
  });

  /// Clamps every value to a safe range; unknown fields are ignored.
  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    const defaults = RemoteConfig();
    int read(String key, int fallback) {
      final v = json[key];
      return v is num ? v.toInt() : fallback;
    }

    return RemoteConfig(
      imageMaxLongSidePx: read(
        'imageMaxLongSidePx',
        defaults.imageMaxLongSidePx,
      ).clamp(512, 2048),
      imageJpegQuality: read(
        'imageJpegQuality',
        defaults.imageJpegQuality,
      ).clamp(30, 100),
      maxUploadBytes: read(
        'maxUploadBytes',
        defaults.maxUploadBytes,
      ).clamp(64 * 1024, 32 * 1024 * 1024),
      analyzeTimeoutSeconds: read(
        'analyzeTimeoutSeconds',
        defaults.analyzeTimeoutSeconds,
      ).clamp(5, 300),
      // Servers that predate the side photo do not send it: one photo.
      maxImages: read('maxImages', defaults.maxImages).clamp(1, 2),
      // Servers that predate barcode lookup do not send it: no scanner.
      barcodeLookup: json['barcodeLookup'] == true,
    );
  }

  final int imageMaxLongSidePx;
  final int imageJpegQuality;
  final int maxUploadBytes;
  final int analyzeTimeoutSeconds;

  /// Photos per analysis the backend accepts; 2 means a side photo is welcome.
  final int maxImages;

  bool get supportsSidePhoto => maxImages >= 2;

  /// True when the backend can look packaged products up by barcode.
  final bool barcodeLookup;

  Map<String, dynamic> toJson() => {
    'imageMaxLongSidePx': imageMaxLongSidePx,
    'imageJpegQuality': imageJpegQuality,
    'maxUploadBytes': maxUploadBytes,
    'analyzeTimeoutSeconds': analyzeTimeoutSeconds,
    'maxImages': maxImages,
    'barcodeLookup': barcodeLookup,
  };
}

/// Why an analysis did not produce a result. Each case maps to a localized
/// message and a set of actions in the UI; raw exception text is never shown.
sealed class AnalysisFailure implements Exception {
  const AnalysisFailure();
}

/// No connection to the backend.
class OfflineFailure extends AnalysisFailure {
  const OfflineFailure();
}

class TimeoutFailure extends AnalysisFailure {
  const TimeoutFailure();
}

class RateLimitedFailure extends AnalysisFailure {
  const RateLimitedFailure();
}

/// Backend or AI provider problems that a retry might fix.
class UnavailableFailure extends AnalysisFailure {
  const UnavailableFailure();
}

enum BadImageReason {
  /// The file cannot be decoded as an image.
  unreadable,

  /// Even after downscaling the photo exceeds the upload limit.
  tooLarge,

  /// The backend rejected the photo.
  rejected,
}

/// The photo itself was rejected or cannot be read.
class BadImageFailure extends AnalysisFailure {
  const BadImageFailure([this.reason = BadImageReason.rejected]);

  final BadImageReason reason;
}

/// The backend found no food (or nothing it was confident about).
class NotRecognizedFailure extends AnalysisFailure {
  const NotRecognizedFailure();
}

/// No backend address is configured (none in the settings and no default).
class ServerNotConfiguredFailure extends AnalysisFailure {
  const ServerNotConfiguredFailure();
}

/// TLS to the backend failed because its certificate is not trusted, or it is
/// not the one the user confirmed (for example after the server regenerated it).
class CertificateFailure extends AnalysisFailure {
  const CertificateFailure();
}

class UnknownFailure extends AnalysisFailure {
  const UnknownFailure();
}
