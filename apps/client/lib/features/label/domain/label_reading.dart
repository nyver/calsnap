import 'dart:typed_data';

import '../../recognition/domain/analysis.dart';

/// Warning codes of `POST /v1/labels/analyze`.
abstract final class LabelWarning {
  static const lowConfidence = 'LOW_CONFIDENCE';
  static const energyMismatch = 'ENERGY_MISMATCH';
  static const energyEstimated = 'ENERGY_ESTIMATED';
  static const valuesConverted = 'VALUES_CONVERTED';
  static const volumeBasis = 'VOLUME_BASIS';
}

/// What the backend read from a nutrition facts table, per 100 g. A value the
/// table did not show is null, never zero.
class LabelReading {
  const LabelReading({
    this.name,
    this.servingSizeG,
    this.kcal,
    this.protein,
    this.fat,
    this.carbs,
    this.warnings = const {},
  });

  /// Throws [FormatException] when the payload does not match the contract.
  factory LabelReading.fromJson(Map<String, dynamic> json) {
    try {
      final nutrition = json['nutrition'] as Map<String, dynamic>;
      double? number(String key) => (nutrition[key] as num?)?.toDouble();
      final name = (json['name'] as String?)?.trim();
      final serving = (json['servingSizeG'] as num?)?.toDouble();
      return LabelReading(
        name: name == null || name.isEmpty ? null : name,
        servingSizeG: serving != null && serving > 0 ? serving : null,
        kcal: number('kcalPer100g'),
        protein: number('proteinPer100g'),
        fat: number('fatPer100g'),
        carbs: number('carbsPer100g'),
        warnings: (json['warnings'] as List<dynamic>).cast<String>().toSet(),
      );
    } on TypeError catch (e) {
      throw FormatException('Unexpected label response shape: $e');
    }
  }

  final String? name;
  final double? servingSizeG;
  final double? kcal;
  final double? protein;
  final double? fat;
  final double? carbs;
  final Set<String> warnings;

  /// True when every number the form needs was read.
  bool get isComplete =>
      kcal != null && protein != null && fat != null && carbs != null;
}

/// The photo shows no readable nutrition table.
class LabelNotRecognizedException implements Exception {
  const LabelNotRecognizedException();

  @override
  String toString() => 'LabelNotRecognizedException';
}

/// Where label readings come from; the backend in production, a fake in tests.
abstract interface class LabelSource {
  /// Throws [LabelNotRecognizedException] for a photo without a table and an
  /// [AnalysisFailure] subtype for every other problem.
  Future<LabelReading> read(
    Uint8List jpeg, {
    required String locale,
    required RemoteConfig config,
  });
}
