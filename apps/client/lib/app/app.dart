import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/di/providers.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget: theme, localization and routing.
class CalSnapApp extends ConsumerStatefulWidget {
  const CalSnapApp({this.initialLocation = Routes.splash, super.key});

  final String initialLocation;

  @override
  ConsumerState<CalSnapApp> createState() => _CalSnapAppState();
}

class _CalSnapAppState extends ConsumerState<CalSnapApp> {
  late final GoRouter _router = createRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
