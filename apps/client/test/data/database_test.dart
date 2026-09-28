import 'dart:io';

import 'package:calsnap/core/database/app_database.dart';
import 'package:calsnap/core/database/database_opener.dart';
import 'package:calsnap/core/utils/ids.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v1.dart' as v1;
import '../support/fixtures.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<void> insertMeal(String id) => db
      .into(db.meals)
      .insert(
        MealsCompanion.insert(
          id: id,
          mealTime: 1000,
          createdAt: 1,
          updatedAt: 1,
        ),
      );

  Future<void> insertItem(String id, String mealId) => db
      .into(db.mealItems)
      .insert(
        MealItemsCompanion.insert(
          id: id,
          mealId: mealId,
          name: 'Rice',
          weightG: 100,
          createdAt: 1,
          updatedAt: 1,
        ),
      );

  test(
    'fresh install creates all tables and indexes at schema version 2',
    () async {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      expect(
        tables.map((r) => r.read<String>('name')),
        containsAll([
          'meals',
          'meal_items',
          'foods',
          'user_settings',
          'ai_corrections',
        ]),
      );
      final indexes = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
          .get();
      expect(
        indexes.map((r) => r.read<String>('name')),
        containsAll([
          'idx_meals_meal_time',
          'idx_meal_items_meal_id',
          'idx_foods_normalized_name',
          'idx_corrections_food',
        ]),
      );
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);
      expect(AppDatabase.currentSchemaVersion, 2);
    },
  );

  test('columns follow the specification (snake_case, TEXT keys)', () async {
    final cols = await db.customSelect('PRAGMA table_info(meal_items)').get();
    final byName = {for (final c in cols) c.read<String>('name'): c};
    for (final name in [
      'id',
      'meal_id',
      'food_id',
      'name',
      'estimated_weight_g',
      'weight_g',
      'kcal_per_100g',
      'protein_per_100g',
      'fat_per_100g',
      'carbs_per_100g',
      'kcal',
      'protein',
      'fat',
      'carbs',
      'confidence',
      'recognition_source',
      'was_corrected',
      'created_at',
      'updated_at',
    ]) {
      expect(byName, contains(name));
    }
    expect(byName['id']!.read<String>('type'), 'TEXT');
    final foods = await db.customSelect('PRAGMA table_info(foods)').get();
    expect(
      foods.map((c) => c.read<String>('name')),
      containsAll([
        'name_ru',
        'aliases',
        'grams_per_piece',
        'grams_per_portion',
        'density_g_per_ml',
        'plate_group',
        'plate_quality',
      ]),
    );
  });

  test('foreign keys are on', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('an orphan item is rejected', () async {
    await expectLater(insertItem('i1', 'missing-meal'), throwsA(anything));
  });

  test('deleting a meal cascades to its items', () async {
    await insertMeal('m1');
    for (final id in ['i1', 'i2', 'i3']) {
      await insertItem(id, 'm1');
    }
    expect(await db.select(db.mealItems).get(), hasLength(3));
    await (db.delete(db.meals)..where((m) => m.id.equals('m1'))).go();
    expect(await db.select(db.mealItems).get(), isEmpty);
  });

  test('wipe clears every table', () async {
    await insertMeal('m1');
    await insertItem('i1', 'm1');
    await db.wipe();
    expect(await db.select(db.meals).get(), isEmpty);
    expect(await db.select(db.mealItems).get(), isEmpty);
  });

  test('ids sort by creation time', () {
    const gen = IdGenerator();
    final ids = [for (var i = 0; i < 2000; i++) gen.newId()];
    final sorted = [...ids]..sort();
    expect(ids, sorted);
    expect(ids.toSet(), hasLength(ids.length));
  });

  group('file database', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('calsnap_db_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('opens in WAL mode with foreign keys on', () async {
      final file = File('${dir.path}/calsnap.db');
      final opened = await openAppDatabase(file);
      addTearDown(opened.close);
      final mode = await opened.customSelect('PRAGMA journal_mode').getSingle();
      expect(mode.read<String>('journal_mode'), 'wal');
      final fk = await opened.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.read<int>('foreign_keys'), 1);
    });

    test('data survives closing and reopening', () async {
      final file = File('${dir.path}/calsnap.db');
      var opened = await openAppDatabase(file);
      await opened
          .into(opened.meals)
          .insert(
            MealsCompanion.insert(
              id: 'm1',
              mealTime: 5,
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await opened.close();
      opened = await openAppDatabase(file);
      addTearDown(opened.close);
      expect(await opened.select(opened.meals).get(), hasLength(1));
    });

    test(
      'a database from a newer app is rejected and left untouched',
      () async {
        final file = File('${dir.path}/newer.db');
        final raw = sqlite.sqlite3.open(file.path);
        raw
          ..execute('CREATE TABLE marker (v TEXT)')
          ..execute("INSERT INTO marker VALUES ('keep me')")
          ..execute('PRAGMA user_version = 3');
        raw.close();
        final before = file.readAsBytesSync();

        await expectLater(
          openAppDatabase(file),
          throwsA(
            isA<UnsupportedSchemaException>()
                .having((e) => e.found, 'found', 3)
                .having((e) => e.supported, 'supported', 2),
          ),
        );
        expect(file.readAsBytesSync(), before);
        expect(
          Directory(dir.path)
              .listSync()
              .map((e) => e.path.split(Platform.pathSeparator).last),
          isNot(contains('newer.db-wal')),
        );
      },
    );
  });

  test('the v2 schema snapshot matches the current schema', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(2);
    final current = AppDatabase(connection);
    addTearDown(current.close);
    await verifier.migrateAndValidate(current, 2);
  });

  test('upgrading from schema 1 to 2 preserves every row and adds nullable '
      'plate columns', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);
    addTearDown(schema.close);
    final old = v1.DatabaseAtV1(schema.newConnection());

    await old.customStatement('''
        INSERT INTO meals (id, meal_time, meal_type, photo_path, total_kcal,
          total_protein, total_fat, total_carbs, ai_provider, ai_model,
          created_at, updated_at)
        VALUES ('m1', 1000, 'lunch', NULL, 500, 30, 10, 60, 'openai', 'gpt',
          1, 1)
      ''');
    await old.customStatement('''
        INSERT INTO meal_items (id, meal_id, food_id, name,
          estimated_weight_g, weight_g, kcal_per_100g, protein_per_100g,
          fat_per_100g, carbs_per_100g, kcal, protein, fat, carbs,
          confidence, recognition_source, was_corrected, created_at,
          updated_at)
        VALUES ('i1', 'm1', 'f-catalog', 'Chicken breast', 150, 150, 165,
          31, 3.6, 0, 247.5, 46.5, 5.4, 0, 0.9, 'ai', 0, 1, 1)
      ''');
    await old.customStatement('''
        INSERT INTO foods (id, name, name_ru, normalized_name, aliases,
          kcal_per_100g, protein_per_100g, fat_per_100g, carbs_per_100g,
          grams_per_piece, grams_per_portion, density_g_per_ml, source,
          source_id, updated_at)
        VALUES ('f-catalog', 'Chicken breast', 'Куриная грудка',
          'chicken_breast', NULL, 165, 31, 3.6, 0, NULL, 150, NULL,
          'catalog', 'chicken_breast', 1)
      ''');
    await old.customStatement('''
        INSERT INTO foods (id, name, name_ru, normalized_name, aliases,
          kcal_per_100g, protein_per_100g, fat_per_100g, carbs_per_100g,
          grams_per_piece, grams_per_portion, density_g_per_ml, source,
          source_id, updated_at)
        VALUES ('f-custom', 'My snack', NULL, NULL, NULL, 300, 5, 10, 40,
          NULL, NULL, NULL, 'user', NULL, 2)
      ''');
    await old.customStatement('''
        INSERT INTO foods (id, name, name_ru, normalized_name, aliases,
          kcal_per_100g, protein_per_100g, fat_per_100g, carbs_per_100g,
          grams_per_piece, grams_per_portion, density_g_per_ml, source,
          source_id, updated_at)
        VALUES ('f-packaged', 'Some bar', NULL, NULL, NULL, 450, 8, 20, 50,
          NULL, NULL, NULL, 'packaged', NULL, 3)
      ''');
    await old.customStatement('''
        INSERT INTO user_settings (key, value) VALUES ('language', 'en')
      ''');
    await old.customStatement('''
        INSERT INTO ai_corrections (id, normalized_food_name, ai_weight_g,
          user_weight_g, ai_provider, ai_model, created_at)
        VALUES ('i1', 'chicken_breast', 150, 180, 'openai', 'gpt', 1)
      ''');
    await old.close();

    final migrated = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(migrated, 2);

    final version = await migrated
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.read<int>('user_version'), 2);

    final meals = await migrated.select(migrated.meals).get();
    expect(meals, hasLength(1));
    expect(meals.single.id, 'm1');
    expect(meals.single.totalKcal, 500);
    expect(meals.single.mealType, 'lunch');

    final items = await migrated.select(migrated.mealItems).get();
    expect(items, hasLength(1));
    expect(items.single.name, 'Chicken breast');
    expect(items.single.weightG, 150);

    final foods = await migrated.select(migrated.foods).get();
    expect(foods, hasLength(3));
    for (final food in foods) {
      expect(food.plateGroup, null);
      expect(food.plateQuality, null);
    }
    final catalogFood = foods.firstWhere((f) => f.id == 'f-catalog');
    expect(catalogFood.source, 'catalog');
    expect(catalogFood.nameRu, 'Куриная грудка');

    final settings = await migrated.select(migrated.userSettings).get();
    expect(settings, hasLength(1));
    expect(settings.single.value, 'en');

    final corrections = await migrated.select(migrated.aiCorrections).get();
    expect(corrections, hasLength(1));
    expect(corrections.single.userWeightG, 180);

    final cols = await migrated.customSelect('PRAGMA table_info(foods)').get();
    expect(
      cols.map((c) => c.read<String>('name')),
      containsAll(['plate_group', 'plate_quality']),
    );
    await migrated.close();
  });
}
