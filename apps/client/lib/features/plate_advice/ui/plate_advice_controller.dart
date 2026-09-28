import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../../meal/ui/plate_analysis_provider.dart';
import '../../recognition/ui/analysis_controller.dart'
    show remoteConfigRepositoryProvider;
import '../data/plate_advice_api.dart';
import '../domain/get_plate_advice_use_case.dart';
import '../domain/plate_advice.dart';
import '../domain/plate_advice_failure.dart';
import '../domain/plate_advice_repository.dart';
import '../domain/plate_advice_request.dart';

final plateAdviceRepositoryProvider = Provider<PlateAdviceRepository>(
  (ref) => PlateAdviceApi(
    ref.watch(dioProvider),
    ref.watch(remoteConfigRepositoryProvider),
    newRequestId: () => ref.read(idsProvider).newId(),
  ),
);

final getPlateAdviceUseCaseProvider = Provider<GetPlateAdviceUseCase>(
  (ref) => GetPlateAdviceUseCase(ref.watch(plateAdviceRepositoryProvider)),
);

/// Whether the backend can turn the local balance into AI suggestions. Read
/// again every time the editor opens; the configuration itself is cached.
final plateAdviceSupportedProvider = FutureProvider.autoDispose<bool>(
  (ref) async =>
      (await ref.watch(remoteConfigRepositoryProvider).current()).plateAdvice,
);

/// The state of the plate advice section for the meal currently open in the
/// editor. Every case carries the fingerprint of the request it belongs to
/// (design.md Decision 13); the UI derives staleness by comparing it with the
/// fingerprint of the current draft.
sealed class PlateAdviceState {
  const PlateAdviceState();
}

class PlateAdviceIdle extends PlateAdviceState {
  const PlateAdviceIdle();
}

class PlateAdviceLoading extends PlateAdviceState {
  const PlateAdviceLoading(this.fingerprint);

  final String fingerprint;
}

class PlateAdviceLoaded extends PlateAdviceState {
  const PlateAdviceLoaded(this.fingerprint, this.advice);

  final String fingerprint;
  final PlateAdvice advice;
}

class PlateAdviceFailed extends PlateAdviceState {
  const PlateAdviceFailed(this.fingerprint, this.failure);

  final String fingerprint;
  final PlateAdviceFailure failure;
}

/// Runs plate advice requests for the open editor. Auto-dispose: closing the
/// editor cancels any in-flight request and drops the kept advice.
class PlateAdviceController extends Notifier<PlateAdviceState> {
  Completer<void>? _cancelSignal;
  int _generation = 0;

  @override
  PlateAdviceState build() {
    ref.onDispose(_cancelCurrent);
    return const PlateAdviceIdle();
  }

  void _cancelCurrent() {
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  /// Sends a plate advice request for the current draft. A no-op while a
  /// request for the same fingerprint is already in flight; otherwise it
  /// cancels any older request (including one for a stale fingerprint) and
  /// starts a new one with a new request id.
  Future<void> request() async {
    final draft = ref.read(mealDraftProvider);
    final analysis = ref.read(plateAnalysisProvider);
    if (draft == null || analysis == null || !analysis.isAnalyzable) {
      // The UI never offers the button in this state; nothing to do.
      return;
    }
    final locale = ref.read(effectiveLanguageCodeProvider);
    final built = PlateAdviceRequest.tryCreate(
      draft: draft,
      analysis: analysis,
      locale: locale,
    );
    if (built == null) return;
    final fingerprint = built.fingerprint;

    final current = state;
    if (current is PlateAdviceLoading && current.fingerprint == fingerprint) {
      return;
    }

    if (ref.read(apiBaseUrlProvider) == null) {
      state = PlateAdviceFailed(
        fingerprint,
        const PlateAdviceServerNotConfigured(),
      );
      return;
    }

    _cancelCurrent();
    final cancelSignal = _cancelSignal = Completer<void>();
    final generation = ++_generation;
    state = PlateAdviceLoading(fingerprint);

    try {
      final advice = await ref
          .read(getPlateAdviceUseCaseProvider)
          .execute(
            draft: draft,
            analysis: analysis,
            locale: locale,
            cancel: cancelSignal.future,
          );
      if (generation != _generation) return; // superseded; drop the response
      state = PlateAdviceLoaded(fingerprint, advice);
    } on DioException catch (e) {
      // A cancellation (ours, on a newer request or on dispose) is never a
      // visible error.
      if (e.type == DioExceptionType.cancel) return;
      if (generation != _generation) return;
      state = PlateAdviceFailed(fingerprint, const PlateAdviceUnavailable());
    } on PlateAdviceFailure catch (failure) {
      if (generation != _generation) return;
      state = PlateAdviceFailed(fingerprint, failure);
    }
  }
}

final plateAdviceControllerProvider =
    NotifierProvider.autoDispose<PlateAdviceController, PlateAdviceState>(
      PlateAdviceController.new,
    );
