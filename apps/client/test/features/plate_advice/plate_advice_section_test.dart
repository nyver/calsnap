import 'dart:async';
import 'dart:convert';

import 'package:calsnap/core/di/providers.dart';
import 'package:calsnap/features/balanced_plate/domain/plate_group.dart';
import 'package:calsnap/features/meal/domain/meal_draft.dart';
import 'package:calsnap/features/meal/ui/meal_draft_notifier.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_failure.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_repository.dart';
import 'package:calsnap/features/plate_advice/domain/plate_advice_request.dart';
import 'package:calsnap/features/plate_advice/ui/plate_advice_controller.dart';
import 'package:calsnap/features/plate_advice/ui/plate_advice_section.dart';
import 'package:calsnap/features/settings/domain/settings_repository.dart';
import 'package:calsnap/features/settings/domain/user_settings.dart';
import 'package:calsnap/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(protocolFile('fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// An in-memory [SettingsRepository]; only getRaw/setRaw are exercised.
class FakeSettingsRepository implements SettingsRepository {
  final Map<String, String> raw = {};

  @override
  Future<String?> getRaw(String key) async => raw[key];

  @override
  Future<void> setRaw(String key, String value) async => raw[key] = value;

  @override
  Stream<AppSettings> watch() => const Stream.empty();

  @override
  Future<AppSettings> read() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

/// A repository whose responses are resolved by the test.
class ControllableRepository implements PlateAdviceRepository {
  final List<PlateAdviceRequest> requests = [];
  final List<Completer<PlateAdvice>> _completers = [];

  @override
  Future<PlateAdvice> getAdvice(
    PlateAdviceRequest request, {
    Future<void>? cancel,
  }) {
    requests.add(request);
    final c = Completer<PlateAdvice>();
    _completers.add(c);
    return c.future;
  }

  void complete(int index, PlateAdvice advice) =>
      _completers[index].complete(advice);

  void fail(int index, Object error) => _completers[index].completeError(error);
}

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

final insufficientDraft = draftOf([manualItem('m', weight: 1)]);

class Env {
  Env._(this.repo, this.settings, this.container);

  factory Env({
    ControllableRepository? repo,
    bool supported = true,
    String? apiBaseUrl = 'https://api.test',
  }) {
    final r = repo ?? ControllableRepository();
    final s = FakeSettingsRepository();
    final container = ProviderContainer(
      overrides: [
        plateAdviceSupportedProvider.overrideWith((ref) async => supported),
        effectiveLanguageCodeProvider.overrideWithValue('en'),
        apiBaseUrlProvider.overrideWithValue(apiBaseUrl),
        plateAdviceRepositoryProvider.overrideWithValue(r),
        settingsRepositoryProvider.overrideWithValue(s),
      ],
    );
    return Env._(r, s, container);
  }

  final ControllableRepository repo;
  final FakeSettingsRepository settings;
  final ProviderContainer container;

  void setDraft(MealDraft? draft) =>
      container.read(mealDraftProvider.notifier).state = draft;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: PlateAdviceSection()),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'the button is visible for an evaluable meal on a capable backend',
    (tester) async {
      final env = Env();
      addTearDown(env.container.dispose);
      env.setDraft(evaluableDraft());
      await env.pump(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plateAdviceButton')), findsOneWidget);
    },
  );

  testWidgets('hidden when the meal is not evaluable', (tester) async {
    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(insufficientDraft);
    await env.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plateAdviceSection')), findsNothing);
  });

  testWidgets('hidden when the backend does not support it', (tester) async {
    final env = Env(supported: false);
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await env.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plateAdviceSection')), findsNothing);
    expect(find.byKey(const Key('plateAdviceButton')), findsNothing);
  });

  Future<void> acceptNoticeAndTap(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('plateAdviceButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plateAdviceNoticeContinue')));
    await tester.pump();
  }

  testWidgets('loading shows a live region and a progress indicator', (
    tester,
  ) async {
    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await env.pump(tester);
    await tester.pumpAndSettle();

    await acceptNoticeAndTap(tester);
    expect(find.byKey(const Key('plateAdviceLoading')), findsOneWidget);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.bySemanticsLabel(l10n.plateAdviceLoading), findsOneWidget);

    env.repo.complete(0, const PlateAdvice(summary: 's', suggestions: []));
    await tester.pumpAndSettle();
  });

  testWidgets('success shows the fixture summary, suggestion and disclaimer', (
    tester,
  ) async {
    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await env.pump(tester);
    await tester.pumpAndSettle();

    await acceptNoticeAndTap(tester);
    final advice = PlateAdvice.fromJson(
      fixture('plate-advice-response-en.json'),
    );
    env.repo.complete(0, advice);
    await tester.pumpAndSettle();

    expect(find.text(advice.summary), findsOneWidget);
    expect(find.text(advice.suggestions.first.title), findsOneWidget);
    expect(find.text('General guidance, not medical advice'), findsOneWidget);
    expect(find.byKey(const Key('plateAdviceRefresh')), findsOneWidget);
  });

  final failureCases = <String, (PlateAdviceFailure, String, String)>{
    'offline': (
      const PlateAdviceOffline(),
      'AI suggestions require a connection to the CalSnap server.',
      'plateAdviceTryAgain',
    ),
    'server not configured': (
      const PlateAdviceServerNotConfigured(),
      'Set up your CalSnap server to get AI suggestions.',
      'plateAdviceSetupServer',
    ),
    'rate limited': (
      const PlateAdviceRateLimited(),
      'Too many AI requests. Try again later.',
      'plateAdviceTryAgain',
    ),
    'invalid response': (
      const PlateAdviceInvalidResponse(),
      'The AI returned an invalid answer. Try again.',
      'plateAdviceTryAgain',
    ),
    'unavailable': (
      const PlateAdviceUnavailable(),
      "Couldn't get suggestions. The local balance assessment is still available.",
      'plateAdviceTryAgain',
    ),
  };
  for (final entry in failureCases.entries) {
    testWidgets('failure (${entry.key}) shows its message and action', (
      tester,
    ) async {
      final (failure, message, actionKey) = entry.value;
      final env = Env();
      addTearDown(env.container.dispose);
      env.setDraft(evaluableDraft());
      await env.pump(tester);
      await tester.pumpAndSettle();
      await acceptNoticeAndTap(tester);
      env.repo.fail(0, failure);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.byKey(Key(actionKey)), findsOneWidget);
    });
  }

  testWidgets('stale after a weight change and restored after reverting', (
    tester,
  ) async {
    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await env.pump(tester);
    await tester.pumpAndSettle();

    await acceptNoticeAndTap(tester);
    final advice = PlateAdvice.fromJson(
      fixture('plate-advice-response-en.json'),
    );
    env.repo.complete(0, advice);
    await tester.pumpAndSettle();
    expect(find.text(advice.summary), findsOneWidget);

    env.setDraft(evaluableDraft(weight: 999));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plateAdviceStale')), findsOneWidget);
    expect(find.text(advice.summary), findsNothing);
    expect(
      env.repo.requests,
      hasLength(1),
      reason: 'reverting must not re-request yet',
    );

    env.setDraft(evaluableDraft());
    await tester.pumpAndSettle();
    expect(find.text(advice.summary), findsOneWidget);
    expect(find.byKey(const Key('plateAdviceStale')), findsNothing);
    expect(
      env.repo.requests,
      hasLength(1),
      reason: 'the kept advice is shown without a new request',
    );
  });

  testWidgets(
    'the notice: cancel sends nothing, continue sends and is not shown again',
    (tester) async {
      final env = Env();
      addTearDown(env.container.dispose);
      env.setDraft(evaluableDraft());
      await env.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plateAdviceButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plateAdviceNotice')), findsOneWidget);
      await tester.tap(find.byKey(const Key('plateAdviceNoticeCancel')));
      await tester.pumpAndSettle();
      expect(env.repo.requests, isEmpty);
      expect(find.byKey(const Key('plateAdviceButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('plateAdviceButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plateAdviceNotice')), findsOneWidget);
      await tester.tap(find.byKey(const Key('plateAdviceNoticeContinue')));
      await tester.pump();
      expect(env.repo.requests, hasLength(1));
      expect(env.settings.raw[SettingKeys.plateAdviceNoticeAccepted], 'true');
      env.repo.complete(0, const PlateAdvice(summary: 's1', suggestions: []));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plateAdviceRefresh')));
      await tester.pump();
      expect(find.byKey(const Key('plateAdviceNotice')), findsNothing);
      expect(env.repo.requests, hasLength(2));
      env.repo.complete(1, const PlateAdvice(summary: 's2', suggestions: []));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Russian texts', (tester) async {
    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await env.pump(tester, locale: const Locale('ru'));
    await tester.pumpAndSettle();
    expect(find.text('Получить рекомендации ИИ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plateAdviceButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plateAdviceNoticeContinue')));
    await tester.pump();
    env.repo.complete(0, const PlateAdvice(summary: 's', suggestions: []));
    await tester.pumpAndSettle();
    expect(
      find.text('Общие рекомендации, не медицинская консультация'),
      findsOneWidget,
    );
  });

  testWidgets('text scale 2.0 does not overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: UncontrolledProviderScope(
          container: env.container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(child: PlateAdviceSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await acceptNoticeAndTap(tester);
    final advice = PlateAdvice.fromJson(
      fixture('plate-advice-response-ru.json'),
    );
    env.repo.complete(0, advice);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap targets are at least 48dp', (tester) async {
    final env = Env();
    addTearDown(env.container.dispose);
    env.setDraft(evaluableDraft());
    await env.pump(tester);
    await tester.pumpAndSettle();
    final buttonSize = tester.getSize(
      find.byKey(const Key('plateAdviceButton')),
    );
    expect(buttonSize.height, greaterThanOrEqualTo(48));

    await acceptNoticeAndTap(tester);
    env.repo.complete(0, const PlateAdvice(summary: 's', suggestions: []));
    await tester.pumpAndSettle();
    final refreshSize = tester.getSize(
      find.byKey(const Key('plateAdviceRefresh')),
    );
    expect(refreshSize.height, greaterThanOrEqualTo(48));
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('golden: loaded state ($mode)', (tester) async {
      final env = Env();
      addTearDown(env.container.dispose);
      env.setDraft(evaluableDraft());
      await env.pump(
        tester,
        theme: dark ? ThemeData.dark() : ThemeData.light(),
      );
      await tester.pumpAndSettle();
      await acceptNoticeAndTap(tester);
      final advice = PlateAdvice.fromJson(
        fixture('plate-advice-response-en.json'),
      );
      env.repo.complete(0, advice);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/plate_advice_loaded_$mode.png'),
      );
    });
  }
}
