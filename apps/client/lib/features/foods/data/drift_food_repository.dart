import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/domain/nutrition.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/ids.dart';
import '../../meal/domain/meal.dart';
import '../../settings/domain/settings_repository.dart';
import '../domain/food.dart';
import '../domain/food_repository.dart';

/// Food cache over the `foods` table.
///
/// Search is matched in Dart rather than with SQL `LIKE`: SQLite folds case for
/// ASCII only, which would break Cyrillic searches such as "греч".
class DriftFoodRepository implements FoodRepository {
  DriftFoodRepository(this._db, {this._ids = const IdGenerator(), Clock? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  static const int _supportedFormatVersion = 1;

  @override
  Future<void> seedCatalog(String catalogJson) async {
    final doc = jsonDecode(catalogJson) as Map<String, dynamic>;
    final format = doc['formatVersion'] as int?;
    if (format != _supportedFormatVersion) {
      throw FormatException('Unsupported catalog formatVersion $format');
    }
    final version = (doc['catalogVersion'] as int).toString();
    final stored =
        await (_db.select(_db.userSettings)
              ..where((t) => t.key.equals(SettingKeys.catalogVersion)))
            .getSingleOrNull();
    if (stored?.value == version) return;

    final entries = (doc['foods'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = {
        for (final row in await (_db.select(
          _db.foods,
        )..where((t) => t.source.equals(NutritionSourceName.catalog))).get())
          row.sourceId: row.id,
      };
      final seen = <String>{};
      for (final e in entries) {
        final catalogId = e['id'] as String;
        seen.add(catalogId);
        final nutrition = e['nutrition'] as Map<String, dynamic>;
        final names = e['name'] as Map<String, dynamic>;
        final aliases = e['aliases'] as Map<String, dynamic>;
        final companion = FoodsCompanion(
          id: Value(existing[catalogId] ?? _ids.newId()),
          name: Value(names['en'] as String),
          nameRu: Value(names['ru'] as String),
          normalizedName: Value(catalogId),
          aliases: Value(
            [
              ...(aliases['en'] as List<dynamic>).cast<String>(),
              ...(aliases['ru'] as List<dynamic>).cast<String>(),
            ].join('\n'),
          ),
          kcalPer100g: Value((nutrition['kcal'] as num).toDouble()),
          proteinPer100g: Value((nutrition['protein'] as num).toDouble()),
          fatPer100g: Value((nutrition['fat'] as num).toDouble()),
          carbsPer100g: Value((nutrition['carbs'] as num).toDouble()),
          gramsPerPiece: Value((e['gramsPerPiece'] as num?)?.toDouble()),
          gramsPerPortion: Value((e['gramsPerPortion'] as num?)?.toDouble()),
          densityGPerMl: Value((e['densityGPerMl'] as num?)?.toDouble()),
          source: const Value(NutritionSourceName.catalog),
          sourceId: Value(catalogId),
          updatedAt: Value(nowMs),
        );
        await _db.into(_db.foods).insertOnConflictUpdate(companion);
      }
      // Drop catalog rows that the new version no longer contains.
      for (final entry in existing.entries) {
        if (!seen.contains(entry.key)) {
          await (_db.delete(
            _db.foods,
          )..where((t) => t.id.equals(entry.value))).go();
        }
      }
      await _db
          .into(_db.userSettings)
          .insertOnConflictUpdate(
            UserSettingsCompanion.insert(
              key: SettingKeys.catalogVersion,
              value: version,
            ),
          );
    });
  }

  @override
  Future<List<Food>> search(String query, {int limit = 50}) async {
    final q = _fold(query.trim());
    final foods = (await _db.select(_db.foods).get()).map(_toFood).toList();
    if (q.isEmpty) {
      foods.sort((a, b) => a.name.compareTo(b.name));
      return foods.take(limit).toList();
    }
    final ranked = <(int, Food)>[];
    for (final food in foods) {
      final rank = _rank(food, q);
      if (rank != null) ranked.add((rank, food));
    }
    ranked.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      if (byRank != 0) return byRank;
      final byLength = a.$2.name.length.compareTo(b.$2.name.length);
      return byLength != 0 ? byLength : a.$2.name.compareTo(b.$2.name);
    });
    return [for (final r in ranked.take(limit)) r.$2];
  }

  /// Lower is better. 0: a name starts with the query; 1: an alias does;
  /// 2/3: a word of a name/alias starts with it; 4/5: it occurs inside a
  /// name/alias. Null: no match.
  int? _rank(Food food, String q) {
    final names = <String>[
      _fold(food.name),
      if (food.nameRu != null) _fold(food.nameRu!),
      if (food.normalizedName != null)
        _fold(food.normalizedName!.replaceAll('_', ' ')),
    ];
    final aliases = [for (final a in food.aliases) _fold(a)];
    bool wordStarts(String s) =>
        s.split(RegExp(r'[\s_\-,]+')).any((w) => w.startsWith(q));
    if (names.any((s) => s.startsWith(q))) return 0;
    if (aliases.any((s) => s.startsWith(q))) return 1;
    if (names.any(wordStarts)) return 2;
    if (aliases.any(wordStarts)) return 3;
    if (names.any((s) => s.contains(q))) return 4;
    if (aliases.any((s) => s.contains(q))) return 5;
    return null;
  }

  /// Lowercases and unifies "ё" with "е" (Unicode-aware, unlike SQLite).
  static String _fold(String s) => s.toLowerCase().replaceAll('ё', 'е');

  @override
  Future<Food?> getById(String id) async {
    final row = await (_db.select(
      _db.foods,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toFood(row);
  }

  @override
  Future<Food?> findByNormalizedName(String normalizedName) async {
    final rows = await (_db.select(
      _db.foods,
    )..where((t) => t.normalizedName.equals(normalizedName))).get();
    if (rows.isEmpty) return null;
    // Prefer the curated catalog over cached AI estimates and user products.
    rows.sort((a, b) => _sourcePriority(a).compareTo(_sourcePriority(b)));
    return _toFood(rows.first);
  }

  static int _sourcePriority(FoodRow r) => switch (r.source) {
    NutritionSourceName.catalog => 0,
    NutritionSourceName.user => 1,
    _ => 2,
  };

  @override
  Future<Food> createCustom(CustomFoodInput input) async {
    final problem = input.validate();
    if (problem != null) {
      throw ArgumentError.value(
        input,
        'input',
        'invalid custom food: $problem',
      );
    }
    final name = input.name.trim();
    final row = FoodsCompanion.insert(
      id: _ids.newId(),
      name: name,
      normalizedName: Value(name.toLowerCase().split(RegExp(r'\s+')).join('_')),
      kcalPer100g: input.per100.kcal,
      proteinPer100g: Value(input.per100.protein),
      fatPer100g: Value(input.per100.fat),
      carbsPer100g: Value(input.per100.carbs),
      source: const Value(NutritionSourceName.user),
      updatedAt: _clock().toUtc().millisecondsSinceEpoch,
    );
    await _db.into(_db.foods).insert(row);
    final created = await (_db.select(
      _db.foods,
    )..where((t) => t.id.equals(row.id.value))).getSingle();
    return _toFood(created);
  }

  static Food _toFood(FoodRow r) => Food(
    id: r.id,
    name: r.name,
    nameRu: r.nameRu,
    normalizedName: r.normalizedName,
    aliases: (r.aliases ?? '').isEmpty ? const [] : r.aliases!.split('\n'),
    per100: Nutrition(
      kcal: r.kcalPer100g,
      protein: r.proteinPer100g,
      fat: r.fatPer100g,
      carbs: r.carbsPer100g,
    ),
    source: r.source ?? NutritionSourceName.user,
    sourceId: r.sourceId,
    gramsPerPiece: r.gramsPerPiece,
    gramsPerPortion: r.gramsPerPortion,
    densityGPerMl: r.densityGPerMl,
  );
}
