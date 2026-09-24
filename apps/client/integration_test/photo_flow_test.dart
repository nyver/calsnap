import 'dart:io';

import 'package:calsnap/app/app.dart';
import 'package:calsnap/core/di/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../test/support/photo_flow.dart';

/// Runs the MVP acceptance flow on a device or emulator with the real database,
/// real file system and real image pipeline. The camera is replaced by a photo
/// generated on the fly and the backend by an in-memory fixture server.
///
///   flutter test integration_test/photo_flow_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('photo -> analysis -> edit -> save -> restart -> diary', (
    tester,
  ) async {
    // A clean slate: earlier runs must not leave a diary behind.
    final support = await getApplicationSupportDirectory();
    for (final name in ['calsnap.db', 'calsnap.db-wal', 'calsnap.db-shm']) {
      final f = File(p.join(support.path, name));
      if (f.existsSync()) f.deleteSync();
    }
    final documents = await getApplicationDocumentsDirectory();
    final meals = Directory(p.join(documents.path, 'meals'));
    if (meals.existsSync()) meals.deleteSync(recursive: true);

    // A 64x48 JPEG standing in for the camera photo.
    final temp = await getTemporaryDirectory();
    final photo = File(p.join(temp.path, 'integration-photo.jpg'));
    await photo.writeAsBytes(samplePhotoBytes());

    final backend = FixtureBackendAdapter();
    await runPhotoFlow(
      tester,
      buildApp: () => scoped(
        fixtureBackendOverrides(photoPath: photo.path, backend: backend),
        const CalSnapApp(),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final mealsRows = await container
        .read(mealRepositoryProvider)
        .mealsWithItems();
    expect(mealsRows, hasLength(1));
    expect(mealsRows.single.items, hasLength(4));
    expect(
      container.read(photoStorageProvider).exists(mealsRows.single.photoPath!),
      isTrue,
    );
  });
}
