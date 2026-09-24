import '../../foods/domain/food.dart';
import '../../foods/domain/food_repository.dart';
import '../../recognition/domain/analysis.dart' show AnalysisFailure;
import 'gtin.dart';
import 'packaged_product.dart';

/// Where product facts come from; the backend in production, a fake in tests.
abstract interface class ProductSource {
  /// Throws [ProductNotFoundException] for an unknown product and an
  /// [AnalysisFailure] subtype for every other problem.
  Future<PackagedProduct> fetch(String barcode, {required String locale});
}

/// Finds a packaged product by barcode: the local cache first, so a product
/// scanned before works offline, then the backend. A product found online is
/// stored in the food cache, where it also shows up in the food search.
class ProductLookup {
  ProductLookup({required this._foods, required this._source});

  final FoodRepository _foods;
  final ProductSource _source;

  /// [rawBarcode] must be a valid GTIN, see [Gtin.normalize]. Throws
  /// [ArgumentError] for anything else, [ProductNotFoundException] for an
  /// unknown product and an `AnalysisFailure` subtype for network problems.
  Future<Food> call(String rawBarcode, {required String locale}) async {
    final code = Gtin.normalize(rawBarcode);
    if (code == null) {
      throw ArgumentError.value(rawBarcode, 'rawBarcode', 'not a valid GTIN');
    }
    final cached = await _foods.findPackaged(code);
    if (cached != null) return cached;
    final product = await _source.fetch(code, locale: locale);
    return _foods.savePackaged(product);
  }
}
