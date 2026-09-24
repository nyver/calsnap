import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../camera/data/image_preparer.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../data/remote_config_repository.dart';
import '../domain/analysis.dart';

/// The photo to analyze.
class AnalysisSource {
  const AnalysisSource({required this.path, this.top});

  final String path;

  /// Set when [path] is a side photo that refines the analysis of this
  /// already prepared main photo (its temporary file belongs to the draft).
  final PreparedPhoto? top;

  bool get isSidePhoto => top != null;
}

/// A photo prepared for upload.
class PreparedPhoto {
  const PreparedPhoto({required this.jpeg, this.tempFile});

  final Uint8List jpeg;

  /// The prepared JPEG on disk; it becomes the meal photo when photos are saved.
  final String? tempFile;
}

/// Turns the captured or picked file into an upload-ready JPEG.
abstract interface class PhotoPreparer {
  Future<PreparedPhoto> prepare(AnalysisSource source, RemoteConfig config);
}

/// Decodes and re-encodes the image off the UI isolate and stores the result in
/// the temporary capture directory.
class FilePhotoPreparer implements PhotoPreparer {
  FilePhotoPreparer(this._ref);

  final Ref _ref;

  @override
  Future<PreparedPhoto> prepare(
    AnalysisSource source,
    RemoteConfig config,
  ) async {
    final bytes = await File(source.path).readAsBytes();
    final prepared = await prepareImage(
      bytes,
      maxLongSidePx: config.imageMaxLongSidePx,
      jpegQuality: config.imageJpegQuality,
      maxBytes: config.maxUploadBytes,
    );
    final file = await _ref.read(photoStorageProvider).newTempFile();
    await file.writeAsBytes(prepared.jpeg, flush: true);
    return PreparedPhoto(jpeg: prepared.jpeg, tempFile: file.path);
  }
}

final photoPreparerProvider = Provider<PhotoPreparer>(FilePhotoPreparer.new);

final remoteConfigRepositoryProvider = Provider<RemoteConfigRepository>(
  (ref) => RemoteConfigRepository(
    ref.watch(settingsRepositoryProvider),
    ref.watch(analysisApiProvider),
  ),
);

/// Whether the backend accepts a side photo. Read again every time the result
/// screen opens, so that a newer cached configuration is picked up.
final sidePhotoSupportedProvider = FutureProvider.autoDispose<bool>(
  (ref) async => (await ref.watch(remoteConfigRepositoryProvider).current())
      .supportsSidePhoto,
);

enum AnalysisPhase { working, failed, done, cancelled }

class AnalysisState {
  const AnalysisState({
    this.phase = AnalysisPhase.working,
    this.failure,
    this.uploading = false,
  });

  final AnalysisPhase phase;
  final AnalysisFailure? failure;

  /// False while the photo is being prepared, true once it is on its way.
  final bool uploading;
}

/// Runs one analysis: prepare the photo, upload it, build the draft. For a side
/// photo it uploads the main photo of the current draft together with it and
/// replaces the items of that draft.
class AnalysisController extends Notifier<AnalysisState> {
  CancelToken? _cancelToken;
  PreparedPhoto? _prepared;
  AnalysisSource? _source;
  bool _cancelled = false;
  bool _handedToDraft = false;

  @override
  AnalysisState build() {
    // Dependencies are read up front: Riverpod forbids ref.read in onDispose.
    final photos = ref.read(photoStorageProvider);
    ref.onDispose(() {
      _cancelToken?.cancel();
      if (!_handedToDraft) {
        unawaited(photos.deleteTemp(_prepared?.tempFile));
      }
    });
    return const AnalysisState();
  }

  Future<void> start(AnalysisSource source) async {
    _source = source;
    await _run();
  }

  /// Uploads the already prepared photo again (a new analysis with a new id).
  Future<void> retry() => _run();

  Future<void> _run() async {
    _cancelled = false;
    if (ref.read(apiBaseUrlProvider) == null) {
      state = const AnalysisState(
        phase: AnalysisPhase.failed,
        failure: ServerNotConfiguredFailure(),
      );
      return;
    }
    state = const AnalysisState();
    final token = _cancelToken = CancelToken();
    try {
      final config = await ref.read(remoteConfigRepositoryProvider).current();
      final source = _source!;
      final prepared = _prepared ??= await ref
          .read(photoPreparerProvider)
          .prepare(source, config);
      if (_cancelled) return;
      final top = source.top;
      state = const AnalysisState(uploading: true);

      // The repository is authoritative; the live stream may not have emitted yet.
      final settings = await ref.read(settingsRepositoryProvider).read();
      final result = await ref
          .read(analysisApiProvider)
          .analyze(
            jpeg: top?.jpeg ?? prepared.jpeg,
            sideJpeg: top == null ? null : prepared.jpeg,
            locale: ref.read(effectiveLanguageCodeProvider),
            requestId: ref.read(idsProvider).newId(),
            config: config,
            plateDiameterCm: settings.plateDiameterCm,
            cancelToken: token,
          );
      if (_cancelled) return;

      if (top != null) {
        // The draft keeps its own main photo; the side photo is only a
        // temporary file and is removed when this controller is disposed.
        await ref.read(mealDraftProvider.notifier).refineWithSidePhoto(result);
        state = const AnalysisState(phase: AnalysisPhase.done);
        return;
      }

      // With photo saving off the temporary photo is deleted right after a
      // successful analysis and the meal is saved without one.
      String? photo = prepared.tempFile;
      if (!settings.savePhotos) {
        await ref.read(photoStorageProvider).deleteTemp(photo);
        photo = null;
      }
      await ref
          .read(mealDraftProvider.notifier)
          .startFromRecognition(
            result,
            tempPhotoFile: photo,
            sourceJpeg: prepared.jpeg,
          );
      _handedToDraft = photo != null;
      state = const AnalysisState(phase: AnalysisPhase.done);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || _cancelled) {
        state = const AnalysisState(phase: AnalysisPhase.cancelled);
      } else {
        // AnalysisApi maps every other transport error itself.
        state = const AnalysisState(
          phase: AnalysisPhase.failed,
          failure: UnknownFailure(),
        );
      }
    } on AnalysisFailure catch (failure) {
      if (_cancelled) return;
      state = AnalysisState(phase: AnalysisPhase.failed, failure: failure);
    } on ImagePrepareException catch (e) {
      state = AnalysisState(
        phase: AnalysisPhase.failed,
        failure: BadImageFailure(
          e.problem == ImagePrepareProblem.tooLarge
              ? BadImageReason.tooLarge
              : BadImageReason.unreadable,
        ),
      );
    } on FileSystemException {
      state = const AnalysisState(
        phase: AnalysisPhase.failed,
        failure: BadImageFailure(BadImageReason.unreadable),
      );
    } on Exception {
      // Anything unexpected is shown as a generic, retryable failure.
      state = const AnalysisState(
        phase: AnalysisPhase.failed,
        failure: UnknownFailure(),
      );
    }
  }

  /// Aborts the request; the screen returns to the preview.
  void cancel() {
    _cancelled = true;
    _cancelToken?.cancel('user');
    state = const AnalysisState(phase: AnalysisPhase.cancelled);
  }
}

final analysisControllerProvider =
    NotifierProvider.autoDispose<AnalysisController, AnalysisState>(
      AnalysisController.new,
    );
