import '../../../core/domain/nutrition.dart';

/// A packaged product as returned by `GET /v1/products/{barcode}`.
class PackagedProduct {
  const PackagedProduct({
    required this.barcode,
    required this.name,
    required this.per100,
    this.brand,
    this.servingSizeG,
  });

  /// Throws [FormatException] when the payload does not match the contract.
  factory PackagedProduct.fromJson(Map<String, dynamic> json) {
    try {
      final nutrition = json['nutrition'] as Map<String, dynamic>;
      final serving = (json['servingSizeG'] as num?)?.toDouble();
      final brand = (json['brand'] as String?)?.trim();
      return PackagedProduct(
        barcode: json['barcode'] as String,
        name: (json['name'] as String).trim(),
        brand: brand == null || brand.isEmpty ? null : brand,
        servingSizeG: serving != null && serving > 0 ? serving : null,
        per100: Nutrition(
          kcal: (nutrition['kcalPer100g'] as num).toDouble(),
          protein: (nutrition['proteinPer100g'] as num).toDouble(),
          fat: (nutrition['fatPer100g'] as num).toDouble(),
          carbs: (nutrition['carbsPer100g'] as num).toDouble(),
        ),
      );
    } on TypeError catch (e) {
      throw FormatException('Unexpected product response shape: $e');
    }
  }

  final String barcode;
  final String name;
  final String? brand;

  /// The declared serving in grams, when the source knows it.
  final double? servingSizeG;
  final Nutrition per100;

  /// The name to show: the brand first unless the name already has it.
  String get displayName {
    final b = brand;
    if (b == null || name.toLowerCase().contains(b.toLowerCase())) return name;
    return '$b $name';
  }
}

/// The backend knows no usable product for the barcode: unknown, or known
/// without trustworthy nutrition data.
class ProductNotFoundException implements Exception {
  const ProductNotFoundException();

  @override
  String toString() => 'ProductNotFoundException';
}
