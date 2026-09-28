import 'package:calsnap/features/balanced_plate/domain/plate_analysis.dart';
import 'package:calsnap/features/balanced_plate/ui/balanced_plate_card.dart';
import 'package:calsnap/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) => MaterialApp(
  locale: locale,
  theme: theme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

const _balanced = PlateAnalysis(
  verdict: PlateVerdict.nicelyBalanced,
  vegetableFruitRatio: 0.5,
  proteinRatio: 0.25,
  complexCarbohydrateRatio: 0.25,
  coverage: 1,
  eligibleWeightG: 400,
  healthyFatPresent: false,
  recommendations: [],
);

const _insufficientData = PlateAnalysis(
  verdict: PlateVerdict.insufficientData,
  vegetableFruitRatio: 0,
  proteinRatio: 0,
  complexCarbohydrateRatio: 0,
  coverage: 0,
  eligibleWeightG: 0,
  healthyFatPresent: false,
  recommendations: [],
);

const _twoRecommendations = PlateAnalysis(
  verdict: PlateVerdict.improvable,
  vegetableFruitRatio: 0.125,
  proteinRatio: 0.125,
  complexCarbohydrateRatio: 0.75,
  coverage: 1,
  eligibleWeightG: 400,
  healthyFatPresent: false,
  recommendations: [
    PlateRecommendation(
      type: PlateRecommendationType.addVegetables,
      priority: 100,
    ),
    PlateRecommendation(
      type: PlateRecommendationType.reduceCarbohydrateDominance,
      priority: 90,
    ),
  ],
);

const _partialCoverage = PlateAnalysis(
  verdict: PlateVerdict.nearlyBalanced,
  vegetableFruitRatio: 0.4,
  proteinRatio: 0.3,
  complexCarbohydrateRatio: 0.3,
  coverage: 0.72,
  eligibleWeightG: 360,
  healthyFatPresent: false,
  recommendations: [],
);

void main() {
  testWidgets('the balanced state shows rows summing to 100 and no tip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const BalancedPlateCard(analysis: _balanced)),
    );
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('25%'), findsNWidgets(2));
    expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
    expect(
      find.byKey(const Key('balancedPlateInsufficientData')),
      findsNothing,
    );
  });

  testWidgets('insufficient data shows only the message', (tester) async {
    await tester.pumpWidget(
      _wrap(const BalancedPlateCard(analysis: _insufficientData)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('balancedPlateInsufficientData')),
      findsOneWidget,
    );
    expect(find.textContaining('%'), findsNothing);
    expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
  });

  testWidgets('shows at most 2 recommendation tiles', (tester) async {
    await tester.pumpWidget(
      _wrap(const BalancedPlateCard(analysis: _twoRecommendations)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lightbulb_outline), findsNWidgets(2));
  });

  testWidgets('shows a coverage note at 72%', (tester) async {
    await tester.pumpWidget(
      _wrap(const BalancedPlateCard(analysis: _partialCoverage)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('balancedPlateCoverageNote')), findsOneWidget);
    expect(find.textContaining('72%'), findsOneWidget);
  });

  testWidgets('the info sheet opens with the disclaimer', (tester) async {
    await tester.pumpWidget(
      _wrap(const BalancedPlateCard(analysis: _balanced)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('balancedPlateInfo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('balancedPlateDisclaimer')), findsOneWidget);
  });

  testWidgets('long Russian recommendation texts at 2x scale do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _wrap(
          const BalancedPlateCard(analysis: _twoRecommendations),
          locale: const Locale('ru'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark theme', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const BalancedPlateCard(analysis: _twoRecommendations),
        theme: ThemeData.dark(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BalancedPlateCard), findsOneWidget);
  });

  testWidgets('each share row exposes an accessible semantics label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const BalancedPlateCard(analysis: _balanced)),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Vegetables & fruit, 50 percent of classified plate weight',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Protein, 25 percent of classified plate weight'),
      findsOneWidget,
    );
    handle.dispose();
  });

  appTest('the card is hidden for an empty manual draft', (tester, app) async {
    await app.completeOnboarding();
    await tester.pumpWidget(app.app());
    await settle(tester);
    await tapKey(tester, 'addMeal');
    await settle(tester, frames: 10);
    await tapKey(tester, 'addManually');
    await settle(tester, frames: 15);

    expect(find.byKey(const Key('balancedPlateCard')), findsNothing);
  });
}
