import '../../balanced_plate/domain/plate_group.dart';
import '../../foods/domain/food.dart';
import '../../foods/domain/food_repository.dart';
import 'meal.dart';

/// The food whose plate classification applies to a saved item linked to
/// [food]. Saving an AI item links it to an `ai_estimate` row, which carries
/// no classification, while recognition classified it by the catalog row with
/// the same normalized name; this repeats that lookup so a reopened meal
/// keeps its groups.
Future<Food?> plateClassificationSource(
  FoodRepository foods,
  Food? food,
) async {
  final key = food?.normalizedName;
  if (food == null ||
      food.plateGroup != PlateGroup.unknown ||
      food.source != NutritionSourceName.aiEstimate ||
      key == null) {
    return food;
  }
  return await foods.findByNormalizedName(key) ?? food;
}
