import 'dart:convert';
import 'dart:io';

import 'package:calsnap/core/domain/nutrition.dart';
import 'package:calsnap/core/files/photo_storage.dart';
import 'package:calsnap/core/network/server_certificate.dart';
import 'package:calsnap/features/foods/domain/food.dart';
import 'package:calsnap/features/meal/domain/meal.dart';
import 'package:calsnap/features/settings/domain/settings_repository.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late TestRepos r;
  setUp(() => r = TestRepos());
  tearDown(() => r.close());

  group('catalog seeding', () {
    test('seeds every catalog food once and is idempotent', () async {
      await r.foods.seedCatalog(readCatalogJson());
      final count = (await r.db.select(r.db.foods).get()).length;
      expect(count, greaterThan(150));
      final ids = (await r.db.select(r.db.foods).get())
          .map((f) => f.id)
          .toSet();

      await r.foods.seedCatalog(readCatalogJson());
      final again = await r.db.select(r.db.foods).get();
      expect(again, hasLength(count));
      expect(again.map((f) => f.id).toSet(), ids);
    });

    test(
      'seeded rows carry names, aliases, units and the catalog source',
      () async {
        await r.foods.seedCatalog(readCatalogJson());
        final egg = (await r.foods.search('egg'))
            .firstWhere((f) => f.normalizedName == 'egg');
        expect(egg.source, 'catalog');
        expect(egg.nameRu, 'Яйцо');
        expect(egg.gramsPerPiece, 50);
        expect(egg.aliases, contains('boiled egg'));
        final milk = (await r.foods.search('milk'))
            .firstWhere((f) => f.normalizedName == 'milk');
        expect(milk.densityGPerMl, 1.03);
      },
    );

    test('a newer catalog updates catalog rows, drops removed ones and keeps user and ai rows', () async {
      String catalog(int version, List<Map<String, Object?>> foods) =>
          jsonEncode({
            'formatVersion': 1,
            'catalogVersion': version,
            'modifiers': {'en': <String>[], 'ru': <String>[]},
            'foods': foods,
          });
      Map<String, Object?> food(String id, num kcal) => {
        'id': id,
        'name': {'en': id, 'ru': id},
        'aliases': {'en': <String>[], 'ru': <String>[]},
        'nutrition': {'kcal': kcal, 'protein': 1, 'fat': 1, 'carbs': 1},
        'source': 'test',
      };

      await r.foods.seedCatalog(catalog(1, [food('a', 10), food('b', 20)]));
      final custom = await r.foods.createCustom(
        const CustomFoodInput(name: 'My bar', per100: Nutrition(kcal: 400)),
      );
      await r.meals.save(
        draftOf([
          aiItem(
            'i',
            name: 'Odd dish',
            normalized: 'odd_dish',
            nutritionSource: NutritionSourceName.aiEstimate,
          ),
        ]),
      );
      final aRow = await (r.db.select(
        r.db.foods,
      )..where((f) => f.sourceId.equals('a'))).getSingle();

      await r.foods.seedCatalog(catalog(2, [food('a', 11), food('c', 30)]));

      final rows = await r.db.select(r.db.foods).get();
      final bySource = <String, List<String?>>{};
      for (final row in rows) {
        bySource
            .putIfAbsent(row.source!, () => [])
            .add(row.normalizedName ?? row.name);
      }
      expect(bySource['catalog']!.toSet(), {'a', 'c'});
      expect(bySource['user'], ['my_bar']);
      expect(bySource['ai_estimate'], ['odd_dish']);
      final updated = await (r.db.select(
        r.db.foods,
      )..where((f) => f.sourceId.equals('a'))).getSingle();
      expect(updated.id, aRow.id, reason: 'catalog row ids stay stable');
      expect(updated.kcalPer100g, 11);
      expect((await r.foods.getById(custom.id))!.name, 'My bar');
    });

    test('rejects an unsupported format version', () async {
      await expectLater(
        r.foods.seedCatalog(
          jsonEncode({
            'formatVersion': 2,
            'catalogVersion': 1,
            'foods': <Object>[],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('search', () {
    setUp(() => r.foods.seedCatalog(readCatalogJson()));

    test('finds buckwheat by a Russian substring', () async {
      final found = await r.foods.search('греч');
      expect(found.map((f) => f.normalizedName), contains('buckwheat'));
    });

    test('is case-insensitive and treats ё as е', () async {
      expect(
        (await r.foods.search('ГРЕЧКА')).map((f) => f.normalizedName),
        contains('buckwheat'),
      );
      expect(
        (await r.foods.search('свёкла')).map((f) => f.normalizedName),
        contains('beetroot'),
      );
      expect(
        (await r.foods.search('CHICKEN')).map((f) => f.normalizedName),
        contains('chicken_breast'),
      );
    });

    test('matches aliases and the normalized name', () async {
      expect(
        (await r.foods.search('kasha')).map((f) => f.normalizedName),
        contains('buckwheat'),
      );
      expect(
        (await r.foods.search('cottage cheese')).map((f) => f.normalizedName),
        contains('cottage_cheese'),
      );
    });

    test('ranks prefix matches before inner matches', () async {
      final found = await r.foods.search('rice');
      final names = found.map((f) => f.name.toLowerCase()).toList();
      final firstInner = names.indexWhere((n) => !n.startsWith('rice'));
      final lastPrefix = names.lastIndexWhere((n) => n.startsWith('rice'));
      expect(names.first.startsWith('rice'), isTrue);
      if (firstInner != -1 && lastPrefix != -1) {
        expect(lastPrefix, lessThan(firstInner));
      }
    });

    test('is limited to 50 results and answers quickly', () async {
      final watch = Stopwatch()..start();
      final all = await r.foods.search('a');
      watch.stop();
      expect(all.length, lessThanOrEqualTo(50));
      expect(watch.elapsedMilliseconds, lessThan(500));
      expect(await r.foods.search('a', limit: 5), hasLength(5));
    });

    test('an unknown query finds nothing', () async {
      expect(await r.foods.search('zzzzqqq'), isEmpty);
    });
  });

  group('custom products', () {
    test('are stored with source user and can be found', () async {
      final created = await r.foods.createCustom(
        const CustomFoodInput(
          name: '  Protein bar ',
          per100: Nutrition(kcal: 380, protein: 30, fat: 12, carbs: 40),
        ),
      );
      expect(created.source, NutritionSourceName.user);
      expect(created.name, 'Protein bar');
      expect(
        (await r.foods.search('protein')).map((f) => f.id),
        contains(created.id),
      );
    });

    test('validation follows the specification', () {
      CustomFoodProblem? check(String name, Nutrition n) =>
          CustomFoodInput(name: name, per100: n).validate();
      expect(
        check(
          'Ok',
          const Nutrition(kcal: 100, protein: 10, fat: 10, carbs: 10),
        ),
        isNull,
      );
      expect(check('', const Nutrition()), CustomFoodProblem.name);
      expect(check('   ', const Nutrition()), CustomFoodProblem.name);
      expect(check('x' * 101, const Nutrition()), CustomFoodProblem.name);
      expect(check('x' * 100, const Nutrition()), isNull);
      expect(check('A', const Nutrition(kcal: 901)), CustomFoodProblem.kcal);
      expect(check('A', const Nutrition(kcal: -1)), CustomFoodProblem.kcal);
      expect(check('A', const Nutrition(fat: 150)), CustomFoodProblem.macros);
      expect(
        check('A', const Nutrition(carbs: -0.1)),
        CustomFoodProblem.macros,
      );
      expect(
        check('A', const Nutrition(kcal: double.nan)),
        CustomFoodProblem.kcal,
      );
    });

    test('invalid input is refused by the repository', () async {
      await expectLater(
        r.foods.createCustom(
          const CustomFoodInput(name: 'x', per100: Nutrition(fat: 150)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('settings', () {
    test('defaults', () async {
      final s = await r.settings.read();
      expect(s.dailyKcalTarget, isNull);
      expect(s.savePhotos, isTrue);
      expect(s.language, AppLanguage.system);
      expect(s.onboardingCompleted, isFalse);
      expect(s.unitSystem, 'metric');
    });

    test('save, read and remove optional values', () async {
      await r.settings.save(
        const AppSettings(
          dailyKcalTarget: 2200,
          dailyProteinTargetG: 150,
          dailyFatTargetG: 75,
          dailyCarbsTargetG: 240,
          plateDiameterCm: 26.5,
          savePhotos: false,
          language: AppLanguage.ru,
          onboardingCompleted: true,
        ),
      );
      var s = await r.settings.read();
      expect(s.dailyKcalTarget, 2200);
      expect(s.dailyProteinTargetG, 150);
      expect(s.plateDiameterCm, 26.5);
      expect(s.savePhotos, isFalse);
      expect(s.language, AppLanguage.ru);
      expect(s.onboardingCompleted, isTrue);
      expect(await r.settings.getRaw(SettingKeys.unitSystem), 'metric');

      await r.settings.save(
        s.copyWith(
          dailyProteinTargetG: () => null,
          plateDiameterCm: () => null,
        ),
      );
      s = await r.settings.read();
      expect(s.dailyProteinTargetG, isNull);
      expect(s.plateDiameterCm, isNull);
      expect(s.dailyKcalTarget, 2200);
    });

    test(
      'the server address is stored and removed like other settings',
      () async {
        await r.settings.save(
          const AppSettings(apiBaseUrl: 'https://calsnap.example.com'),
        );
        var s = await r.settings.read();
        expect(s.apiBaseUrl, 'https://calsnap.example.com');
        // Saving other settings keeps it; clearing it removes the row.
        await r.settings.save(s.copyWith(savePhotos: false));
        expect(
          (await r.settings.read()).apiBaseUrl,
          'https://calsnap.example.com',
        );
        await r.settings.save(s.copyWith(apiBaseUrl: () => null));
        s = await r.settings.read();
        expect(s.apiBaseUrl, isNull);
        expect(await r.settings.getRaw(SettingKeys.apiBaseUrl), isNull);
      },
    );

    test(
      'the confirmed certificate is stored, and a damaged value is ignored',
      () async {
        final fingerprint = List.filled(32, 'AB').join(':');
        final pin = TrustedCertificate.forUrl(
          'https://calsnap.lan:8445',
          fingerprint,
        );
        await r.settings.save(AppSettings(trustedCertificate: pin));
        var s = await r.settings.read();
        expect(s.trustedCertificate, pin);
        // Saving other settings keeps it.
        await r.settings.save(s.copyWith(savePhotos: false));
        expect((await r.settings.read()).trustedCertificate, pin);

        await r.settings.setRaw(SettingKeys.trustedCertificate, 'garbage');
        expect((await r.settings.read()).trustedCertificate, isNull);

        await r.settings.save(s.copyWith(trustedCertificate: () => null));
        s = await r.settings.read();
        expect(s.trustedCertificate, isNull);
        expect(await r.settings.getRaw(SettingKeys.trustedCertificate), isNull);
      },
    );

    test('watch emits changes immediately', () async {
      final values = <int?>[];
      final sub = r.settings.watch().listen(
        (s) => values.add(s.dailyKcalTarget),
      );
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await r.settings.save(const AppSettings(dailyKcalTarget: 1800));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(values.last, 1800);
    });

    test('raw values round-trip', () async {
      expect(await r.settings.getRaw('x'), isNull);
      await r.settings.setRaw('x', '1');
      await r.settings.setRaw('x', '2');
      expect(await r.settings.getRaw('x'), '2');
    });
  });

  group('PhotoStorage', () {
    late Directory root;
    late PhotoStorage storage;

    setUp(() {
      root = Directory.systemTemp.createTempSync('calsnap_photos_');
      storage = PhotoStorage(
        documentsDir: Directory('${root.path}/docs')..createSync(),
        tempDir: Directory('${root.path}/tmp')..createSync(),
        cacheDir: Directory('${root.path}/cache')..createSync(),
        clock: () => DateTime(2026, 3, 10, 9, 5),
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('persist copies a temp file to meals/YYYY/MM/DD/<uuid>.jpg', () async {
      final temp = await storage.newTempFile();
      temp.writeAsBytesSync([1, 2, 3]);
      final relative = await storage.persist(temp, DateTime(2026, 3, 9));
      expect(
        relative,
        matches(RegExp(r'^meals/2026/03/09/[0-9a-f-]{36}\.jpg$')),
      );
      expect(storage.resolve(relative).readAsBytesSync(), [1, 2, 3]);
      expect(
        temp.existsSync(),
        isTrue,
        reason: 'the caller removes the temp file',
      );
      expect(storage.exists(relative), isTrue);
    });

    test('delete removes the file and tolerates a missing one', () async {
      final temp = await storage.newTempFile()
        ..writeAsBytesSync([1]);
      final relative = await storage.persist(temp, DateTime(2026, 3, 9));
      await storage.delete(relative);
      expect(storage.exists(relative), isFalse);
      await storage.delete(relative);
      await storage.delete(null);
    });

    test('paths that leave the documents directory are rejected', () {
      expect(() => storage.resolve('../secret.txt'), throwsArgumentError);
      expect(() => storage.resolve('meals/../../x'), throwsArgumentError);
    });

    test('sweeps and clears', () async {
      final temp = await storage.newTempFile()
        ..writeAsBytesSync([1]);
      final stored = await storage.newTempFile()
        ..writeAsBytesSync([2]);
      final relative = await storage.persist(stored, DateTime(2026, 3, 9));
      final export = storage.newExportFile('csv');
      export.parent.createSync(recursive: true);
      export.writeAsStringSync('x');

      await storage.sweepTemp();
      expect(temp.existsSync(), isFalse);
      await storage.sweepExports();
      expect(export.existsSync(), isFalse);
      expect(storage.exists(relative), isTrue);
      await storage.clearPhotos();
      expect(storage.exists(relative), isFalse);
    });

    test('export files are named with a timestamp', () {
      expect(
        storage.newExportFile('json').path.replaceAll('\\', '/'),
        endsWith('calsnap-export-20260310-0905.json'),
      );
    });
  });
}
