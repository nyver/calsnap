import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/camera/ui/capture_screen.dart';
import '../features/diary/ui/diary_screen.dart';
import '../features/diary/ui/history_screen.dart';
import '../features/foods/ui/food_search_screen.dart';
import '../features/meal/ui/draft_editor_screen.dart';
import '../features/onboarding/ui/onboarding_screen.dart';
import '../features/onboarding/ui/splash_screen.dart';
import '../features/recognition/ui/analysis_screen.dart';
import '../features/settings/ui/privacy_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../features/statistics/ui/statistics_screen.dart';
import 'shell.dart';

/// Route locations.
abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const diary = '/diary';
  static const history = '/history';
  static const statistics = '/statistics';
  static const settings = '/settings';
  static const capture = '/capture';
  static const analysis = '/analysis';
  static const result = '/result';
  static const newMeal = '/meal/new';
  static const foodSearch = '/foods/search';
  static const privacy = '/privacy';

  static String editMeal(String id) => '/meal/$id';
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter({String initialLocation = Routes.splash}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: Routes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: Routes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.diary,
              builder: (context, state) => const DiaryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.history,
              builder: (context, state) => const HistoryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.statistics,
              builder: (context, state) => const StatisticsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: Routes.capture,
      builder: (context, state) =>
          CaptureScreen(startWithGallery: state.extra == true),
    ),
    GoRoute(
      path: Routes.analysis,
      builder: (context, state) =>
          AnalysisScreen(source: state.extra! as AnalysisSource),
    ),
    GoRoute(
      path: Routes.result,
      builder: (context, state) =>
          const DraftEditorScreen(mode: EditorMode.recognition),
    ),
    GoRoute(
      path: Routes.newMeal,
      builder: (context, state) =>
          const DraftEditorScreen(mode: EditorMode.manual),
    ),
    GoRoute(
      path: '/meal/:id',
      builder: (context, state) => DraftEditorScreen(
        mode: EditorMode.edit,
        mealId: state.pathParameters['id'],
      ),
    ),
    GoRoute(
      path: Routes.foodSearch,
      builder: (context, state) => const FoodSearchScreen(),
    ),
    GoRoute(
      path: Routes.privacy,
      builder: (context, state) => const PrivacyScreen(),
    ),
  ],
);
