import 'dart:async';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_failure.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_repository.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_request.dart';
import 'package:calsnap/features/plate_advice/ui/plate_advice_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

/// A [PlateAdviceRepository] whose responses are resolved by the test, one
/// completer per call, so late and out-of-order completions can be driven
/// deterministically.
class ControllableRepository implements PlateAdviceRepository {
  final List<PlateAdviceRequest> requests = [];
  final List<Future<void>?> cancelSignals = [];
  final List<Completer<PlateAdvice>> _completers = [];

  @override
  Future<PlateAdvice> getAdvice(
    PlateAdviceRequest request, {
    Future<void>? cancel,
  }) {
    requests.add(request);
    cancelSignals.add(cancel);
    final c = Completer<PlateAdvice>();
    _completers.add(c);
    return c.future;
  }

  void complete(int index, PlateAdvice advice) =>
      _completers[index].complete(advice);

  void fail(int index, Object error) => _completers[index].completeError(error);
}

const _addVeg = PlateAdviceSuggestion(
  action: PlateAdviceAction.add,
  targetGroup: PlateGroup.vegetable,
  title: 'Add vegetables',
  reason: 'Vegetables and fruit are low.',
);

const someAdvice = PlateAdvice(
  summary: 'Add vegetables.',
  suggestions: [_addVeg],
);

MealDraft evaluableDraft({double weight = 150}) => draftOf([
  aiItem(
    'a',
    name: 'Rice',
    weight: weight,
  ).copyWith(plateGroup: PlateGroup.complexCarbohydrate),
  aiItem(
    'b',
    name: 'Chicken',
    weight: 150,
  ).copyWith(plateGroup: PlateGroup.protein),
]);

class Harness {
  Harness(this.repo, {String? apiBaseUrl = 'https://api.test'})
    : container = ProviderContainer(
        overrides: [
          effectiveLanguageCodeProvider.overrideWithValue('en'),
          apiBaseUrlProvider.overrideWithValue(apiBaseUrl),
          plateAdviceRepositoryProvider.overrideWithValue(repo),
        ],
      ) {
    sub = container.listen(plateAdviceControllerProvider, (_, _) {});
  }

  final ControllableRepository repo;
  final ProviderContainer container;
  late final ProviderSubscription<PlateAdviceState> sub;

  void setDraft(MealDraft? draft) =>
      container.read(mealDraftProvider.notifier).state = draft;

  PlateAdviceController get notifier =>
      container.read(plateAdviceControllerProvider.notifier);

  PlateAdviceState get state => container.read(plateAdviceControllerProvider);

  void dispose() {
    sub.close();
    container.dispose();
  }
}

void main() {
  test('exactly one request is sent for two quick calls', () async {
    final h = Harness(ControllableRepository());
    addTearDown(h.dispose);
    h.setDraft(evaluableDraft());

    final f1 = h.notifier.request();
    final f2 = h.notifier.request();
    expect(h.repo.requests, hasLength(1));
    h.repo.complete(0, someAdvice);
    await f1;
    await f2;
    expect(h.state, isA<PlateAdviceLoaded>());
  });

  test('a late response from an older generation is ignored', () async {
    final h = Harness(ControllableRepository());
    addTearDown(h.dispose);
    h.setDraft(evaluableDraft());

    final f1 = h.notifier.request();
    expect(h.repo.requests, hasLength(1));

    h.setDraft(evaluableDraft(weight: 200)); // a different fingerprint
    final f2 = h.notifier.request();
    expect(h.repo.requests, hasLength(2));

    // The stale (first) response arrives late, after the newer request began.
    const staleAdvice = PlateAdvice(summary: 'Stale', suggestions: [_addVeg]);
    h.repo.complete(0, staleAdvice);
    await f1;
    expect(
      h.state,
      isA<PlateAdviceLoading>(),
      reason: 'the stale response must be dropped',
    );

    const freshAdvice = PlateAdvice(summary: 'Fresh', suggestions: [_addVeg]);
    h.repo.complete(1, freshAdvice);
    await f2;
    final loaded = h.state as PlateAdviceLoaded;
    expect(loaded.advice.summary, 'Fresh');
  });

  test(
    'dispose cancels the in-flight request and swallows it silently',
    () async {
      final h = Harness(ControllableRepository());
      h.setDraft(evaluableDraft());
      final future = h.notifier.request();
      expect(h.repo.requests, hasLength(1));

      h.dispose();
      await expectLater(h.repo.cancelSignals[0], completes);

      h.repo.fail(
        0,
        DioException(
          requestOptions: RequestOptions(path: '/v1/plate-advice'),
          type: DioExceptionType.cancel,
        ),
      );
      await expectLater(future, completes);
    },
  );

  test('a failure is stored with its fingerprint', () async {
    final h = Harness(ControllableRepository());
    addTearDown(h.dispose);
    h.setDraft(evaluableDraft());

    final future = h.notifier.request();
    h.repo.fail(0, const PlateAdviceRateLimited());
    await future;

    final failed = h.state as PlateAdviceFailed;
    expect(failed.failure, isA<PlateAdviceRateLimited>());
    expect(failed.fingerprint, isNotEmpty);
  });

  test('retry and refresh start a new request', () async {
    final h = Harness(ControllableRepository());
    addTearDown(h.dispose);
    h.setDraft(evaluableDraft());

    final f1 = h.notifier.request();
    h.repo.complete(0, someAdvice);
    await f1;
    expect(h.state, isA<PlateAdviceLoaded>());

    final f2 = h.notifier.request(); // same fingerprint, but state is Loaded
    expect(h.repo.requests, hasLength(2));
    h.repo.complete(1, someAdvice);
    await f2;
  });

  test('no request is made when there is no server', () async {
    final h = Harness(ControllableRepository(), apiBaseUrl: null);
    addTearDown(h.dispose);
    h.setDraft(evaluableDraft());

    await h.notifier.request();
    expect(h.repo.requests, isEmpty);
    final failed = h.state as PlateAdviceFailed;
    expect(failed.failure, isA<PlateAdviceServerNotConfigured>());
  });

  test('changing the draft alone sends no request', () async {
    final h = Harness(ControllableRepository());
    addTearDown(h.dispose);
    h.setDraft(evaluableDraft());
    h.setDraft(evaluableDraft(weight: 300));
    await Future<void>.delayed(Duration.zero);

    expect(h.repo.requests, isEmpty);
    expect(h.state, isA<PlateAdviceIdle>());
  });
}
