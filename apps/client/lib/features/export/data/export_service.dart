import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../domain/exporters.dart';

enum ExportFormat {
  csv('csv', 'text/csv'),
  json('json', 'application/json');

  const ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Opens the system share sheet for a file.
abstract interface class ShareGateway {
  Future<void> shareFile(
    String path, {
    required String mimeType,
    required String subject,
  });
}

class SharePlusGateway implements ShareGateway {
  const SharePlusGateway();

  @override
  Future<void> shareFile(
    String path, {
    required String mimeType,
    required String subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }
}

final shareGatewayProvider = Provider<ShareGateway>(
  (ref) => const SharePlusGateway(),
);

/// Builds an export off the UI isolate, writes it to the cache directory and
/// hands it to the share sheet. Works offline.
class ExportService {
  ExportService(this._ref);

  final Ref _ref;

  Future<void> exportAndShare(
    ExportFormat format, {
    required String subject,
  }) async {
    final meals = await _ref.read(mealRepositoryProvider).mealsWithItems();
    final content = switch (format) {
      ExportFormat.csv => await buildCsvInBackground(meals),
      ExportFormat.json => await buildJsonInBackground(
        meals,
        settings: await _ref.read(settingsRepositoryProvider).read(),
        exportedAt: _ref.read(clockProvider)(),
        appVersion: AppConfig.appVersion,
      ),
    };
    final file = _ref
        .read(photoStorageProvider)
        .newExportFile(format.extension);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    await _ref
        .read(shareGatewayProvider)
        .shareFile(file.path, mimeType: format.mimeType, subject: subject);
  }
}

final exportServiceProvider = Provider<ExportService>(ExportService.new);
