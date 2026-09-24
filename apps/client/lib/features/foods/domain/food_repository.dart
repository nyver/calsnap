import '../../barcode/domain/packaged_product.dart';
import 'food.dart';

/// Access to the local food cache.
abstract interface class FoodRepository {
  /// Seeds or upgrades the bundled catalog. Idempotent; never touches
  /// products created by the user.
  Future<void> seedCatalog(String catalogJson);

  /// Case-insensitive substring search over names (both languages), aliases
  /// and normalized names, prefix matches first, at most [limit] results.
  Future<List<Food>> search(String query, {int limit = 50});

  Future<Food?> getById(String id);

  /// The catalog or cached food with this normalized name, if any.
  Future<Food?> findByNormalizedName(String normalizedName);

  /// Stores a custom product with `source = "user"`.
  Future<Food> createCustom(CustomFoodInput input);

  /// The packaged product cached for this normalized barcode, if any.
  Future<Food?> findPackaged(String barcode);

  /// Caches a packaged product (`source = "packaged"`, `sourceId` = barcode)
  /// or refreshes the cached one, keeping its id. Its barcode is searchable.
  Future<Food> savePackaged(PackagedProduct product);
}
