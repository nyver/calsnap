/// The plate-balance group of a food, mirroring the catalog's `plate.group`.
///
/// `unknown` never appears in the catalog; it is the client-side meaning of
/// "no plate metadata" or an unrecognized stored value.
enum PlateGroup {
  vegetable,
  fruit,
  protein,
  complexCarbohydrate,
  healthyFat,
  dairy,
  other,
  unknown;

  String get wireName => switch (this) {
    PlateGroup.vegetable => 'vegetable',
    PlateGroup.fruit => 'fruit',
    PlateGroup.protein => 'protein',
    PlateGroup.complexCarbohydrate => 'complex_carbohydrate',
    PlateGroup.healthyFat => 'healthy_fat',
    PlateGroup.dairy => 'dairy',
    PlateGroup.other => 'other',
    PlateGroup.unknown => 'unknown',
  };

  /// Unrecognized or null input is `unknown`; the literal wire value
  /// `"unknown"` never occurs in the catalog but is still accepted here so
  /// that a corrupted stored value degrades gracefully instead of throwing.
  static PlateGroup fromWire(String? value) {
    for (final g in PlateGroup.values) {
      if (g.wireName == value) return g;
    }
    return PlateGroup.unknown;
  }
}

/// The plate-balance quality of a food, mirroring the catalog's
/// `plate.quality`. Only `mixed` is populated by this change; the others are
/// accepted by validation but not yet used by any rule.
enum PlateQuality {
  nonStarchyVegetable,
  starchyVegetable,
  wholeGrain,
  refinedGrain,
  leanProtein,
  plantProtein,
  fish,
  redMeat,
  processedMeat,
  unsaturatedFat,
  saturatedFat,
  addedSugar,
  highlyProcessed,
  mixed;

  String get wireName => switch (this) {
    PlateQuality.nonStarchyVegetable => 'non_starchy_vegetable',
    PlateQuality.starchyVegetable => 'starchy_vegetable',
    PlateQuality.wholeGrain => 'whole_grain',
    PlateQuality.refinedGrain => 'refined_grain',
    PlateQuality.leanProtein => 'lean_protein',
    PlateQuality.plantProtein => 'plant_protein',
    PlateQuality.fish => 'fish',
    PlateQuality.redMeat => 'red_meat',
    PlateQuality.processedMeat => 'processed_meat',
    PlateQuality.unsaturatedFat => 'unsaturated_fat',
    PlateQuality.saturatedFat => 'saturated_fat',
    PlateQuality.addedSugar => 'added_sugar',
    PlateQuality.highlyProcessed => 'highly_processed',
    PlateQuality.mixed => 'mixed',
  };

  /// Unrecognized or null input is null (no known quality), never a thrown
  /// error, so a corrupted stored value degrades gracefully.
  static PlateQuality? fromWire(String? value) {
    if (value == null) return null;
    for (final q in PlateQuality.values) {
      if (q.wireName == value) return q;
    }
    return null;
  }
}
