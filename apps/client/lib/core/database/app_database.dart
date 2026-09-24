import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Thrown when the database on disk was written by a newer app version. The
/// database is left untouched.
class UnsupportedSchemaException implements Exception {
  const UnsupportedSchemaException({
    required this.found,
    required this.supported,
  });

  final int found;
  final int supported;

  @override
  String toString() =>
      'UnsupportedSchemaException(found: $found, supported: $supported)';
}

@DataClassName('MealRow')
@TableIndex(name: 'idx_meals_meal_time', columns: {#mealTime})
class Meals extends Table {
  TextColumn get id => text()();

  /// UTC epoch milliseconds.
  IntColumn get mealTime => integer()();
  TextColumn get mealType => text().nullable()();

  /// Path relative to the app documents directory.
  TextColumn get photoPath => text().nullable()();
  RealColumn get totalKcal => real().withDefault(const Constant(0))();
  RealColumn get totalProtein => real().withDefault(const Constant(0))();
  RealColumn get totalFat => real().withDefault(const Constant(0))();
  RealColumn get totalCarbs => real().withDefault(const Constant(0))();
  TextColumn get aiProvider => text().nullable()();
  TextColumn get aiModel => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MealItemRow')
@TableIndex(name: 'idx_meal_items_meal_id', columns: {#mealId})
class MealItems extends Table {
  TextColumn get id => text()();
  TextColumn get mealId =>
      text().references(Meals, #id, onDelete: KeyAction.cascade)();
  TextColumn get foodId => text().nullable()();
  TextColumn get name => text()();
  RealColumn get estimatedWeightG => real().nullable()();
  RealColumn get weightG => real()();
  RealColumn get kcalPer100g =>
      real().named('kcal_per_100g').withDefault(const Constant(0))();
  RealColumn get proteinPer100g =>
      real().named('protein_per_100g').withDefault(const Constant(0))();
  RealColumn get fatPer100g =>
      real().named('fat_per_100g').withDefault(const Constant(0))();
  RealColumn get carbsPer100g =>
      real().named('carbs_per_100g').withDefault(const Constant(0))();
  RealColumn get kcal => real().withDefault(const Constant(0))();
  RealColumn get protein => real().withDefault(const Constant(0))();
  RealColumn get fat => real().withDefault(const Constant(0))();
  RealColumn get carbs => real().withDefault(const Constant(0))();
  RealColumn get confidence => real().nullable()();
  TextColumn get recognitionSource => text().nullable()();
  BoolColumn get wasCorrected => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FoodRow')
@TableIndex(name: 'idx_foods_normalized_name', columns: {#normalizedName})
class Foods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Russian display name (catalog foods).
  TextColumn get nameRu => text().nullable()();
  TextColumn get normalizedName => text().nullable()();

  /// Newline-separated aliases in both languages.
  TextColumn get aliases => text().nullable()();
  RealColumn get kcalPer100g => real().named('kcal_per_100g')();
  RealColumn get proteinPer100g =>
      real().named('protein_per_100g').withDefault(const Constant(0))();
  RealColumn get fatPer100g =>
      real().named('fat_per_100g').withDefault(const Constant(0))();
  RealColumn get carbsPer100g =>
      real().named('carbs_per_100g').withDefault(const Constant(0))();
  RealColumn get gramsPerPiece => real().nullable()();
  RealColumn get gramsPerPortion => real().nullable()();
  RealColumn get densityGPerMl => real().nullable()();

  /// `catalog`, `ai_estimate` or `user`.
  TextColumn get source => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SettingRow')
class UserSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('AiCorrectionRow')
@TableIndex(name: 'idx_corrections_food', columns: {#normalizedFoodName})
class AiCorrections extends Table {
  /// Equals the id of the corrected meal item.
  TextColumn get id => text()();
  TextColumn get normalizedFoodName => text()();
  RealColumn get aiWeightG => real()();
  RealColumn get userWeightG => real()();
  TextColumn get aiProvider => text().nullable()();
  TextColumn get aiModel => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Meals, MealItems, Foods, UserSettings, AiCorrections])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Version of the schema written by this app. Bump it together with a new
  /// migration step and a schema snapshot in `drift_schemas/`.
  static const int currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // No upgrade steps exist yet: schema 1 is the first release. Future
      // versions add steps here (see drift_schemas/ for the snapshots).
      throw StateError('No migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      final before = details.versionBefore;
      if (before != null && before > currentSchemaVersion) {
        throw UnsupportedSchemaException(
          found: before,
          supported: currentSchemaVersion,
        );
      }
      await customStatement('PRAGMA foreign_keys = ON');
      // Returns the resulting mode; in-memory databases stay in "memory".
      await customSelect('PRAGMA journal_mode = WAL').get();
    },
  );

  /// Deletes every row of every table (clear all data).
  Future<void> wipe() => transaction(() async {
    for (final table in allTables) {
      await delete(table).go();
    }
  });
}
