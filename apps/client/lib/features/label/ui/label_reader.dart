import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../camera/data/image_preparer.dart';
import '../../recognition/domain/analysis.dart';
import '../../recognition/ui/analysis_controller.dart';
import '../data/label_api.dart';
import '../domain/label_reading.dart';

/// Where label readings come from: the backend.
final labelSourceProvider = Provider<LabelSource>(
  (ref) => LabelApi(
    ref.watch(dioProvider),
    newRequestId: () => ref.read(idsProvider).newId(),
  ),
);

/// Whether the backend can read nutrition labels. Read again every time a
/// screen offering the label scan opens; the configuration itself is cached.
final labelReadingSupportedProvider = FutureProvider.autoDispose<bool>(
  (ref) async =>
      (await ref.watch(remoteConfigRepositoryProvider).current()).labelReading,
);

/// Prepares a label photo (orientation, size, no metadata), has the backend
/// read it and removes the temporary copy.
class LabelReader {
  LabelReader(this._ref);

  final Ref _ref;

  /// Throws [LabelNotRecognizedException] when the photo shows no table and an
  /// [AnalysisFailure] subtype for every other problem.
  Future<LabelReading> read(String path) async {
    if (_ref.read(apiBaseUrlProvider) == null) {
      throw const ServerNotConfiguredFailure();
    }
    final config = await _ref.read(remoteConfigRepositoryProvider).current();
    final PreparedPhoto prepared;
    try {
      prepared = await _ref
          .read(photoPreparerProvider)
          .prepare(AnalysisSource(path: path), config);
    } on ImagePrepareException catch (e) {
      throw BadImageFailure(
        e.problem == ImagePrepareProblem.tooLarge
            ? BadImageReason.tooLarge
            : BadImageReason.unreadable,
      );
    } on FileSystemException {
      throw const BadImageFailure(BadImageReason.unreadable);
    }
    try {
      return await _ref
          .read(labelSourceProvider)
          .read(
            prepared.jpeg,
            locale: _ref.read(effectiveLanguageCodeProvider),
            config: config,
          );
    } finally {
      await _ref.read(photoStorageProvider).deleteTemp(prepared.tempFile);
    }
  }
}

final labelReaderProvider = Provider<LabelReader>(LabelReader.new);
