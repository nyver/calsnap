import 'dart:convert';

import 'package:calsnap/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';
import '../support/fixtures.dart';
import '../support/photo_flow.dart';

void main() {
  test('the inlined backend fixture equals the shared protocol fixture', () {
    final shared = jsonDecode(
      protocolFile('fixtures/analyze-response-full.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final inlined = jsonDecode(analyzeFullJson) as Map<String, dynamic>;
    // The shared fixture carries Russian display names; everything else must match.
    List<Map<String, dynamic>> strip(Map<String, dynamic> m) => [
      for (final i
          in (m['items'] as List<dynamic>).cast<Map<String, dynamic>>())
        {...i}..remove('name'),
    ];
    expect(strip(inlined), strip(shared));
    expect(inlined['warnings'], shared['warnings']);
  });

  appTest(
    'photo -> analysis -> edit -> save -> restart -> diary, history and statistics',
    (tester, app) async {
      final backend = FixtureBackendAdapter();
      final photo = protocolFile('fixtures/sample.jpg').absolute.path;
      await runPhotoFlow(
        tester,
        today: app.clock.now,
        buildApp: () => scoped([
          ...fixtureBackendOverrides(photoPath: photo, backend: backend),
          ...app.baseOverrides(),
        ], const CalSnapApp()),
      );

      expect(
        backend.requests.where((r) => r.path == '/v1/meals/analyze'),
        hasLength(1),
      );
      final request = backend.requests.firstWhere(
        (r) => r.path == '/v1/meals/analyze',
      );
      expect(
        request.headers['X-Request-Id'],
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      // The saved meal has its photo stored as a file, not in SQLite.
      final meal = (await app.mealRows()).single;
      expect(meal.mealType, 'lunch', reason: '12:30 defaults to lunch');
      expect(meal.photoPath, isNotNull);
      expect(app.services.photos.exists(meal.photoPath!), isTrue);
    },
  );
}
