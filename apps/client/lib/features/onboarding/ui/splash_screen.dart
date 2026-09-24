import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../shared/l10n_x.dart';

/// Initializes the app (database, migrations, catalog, temp cleanup, settings)
/// and routes to onboarding or the diary.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _routed = false;

  Future<void> _route(AppServices services) async {
    if (_routed) return;
    _routed = true;
    final settings = await services.settings.read();
    if (!mounted) return;
    context.go(settings.onboardingCompleted ? Routes.diary : Routes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final init = ref.watch(appServicesProvider);
    init.whenData(
      (services) =>
          WidgetsBinding.instance.addPostFrameCallback((_) => _route(services)),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: init.when(
            data: (_) => const CircularProgressIndicator(),
            loading: () => const CircularProgressIndicator(),
            error: (error, _) => _InitError(
              unsupported: error is UnsupportedSchemaException,
              onRetry: () {
                _routed = false;
                ref.invalidate(appServicesProvider);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InitError extends StatelessWidget {
  const _InitError({required this.unsupported, required this.onRetry});

  final bool unsupported;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unsupported ? Icons.system_update : Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            unsupported ? l10n.unsupportedSchemaTitle : l10n.initErrorTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            unsupported ? l10n.unsupportedSchemaBody : l10n.initErrorBody,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('initRetry'),
            onPressed: onRetry,
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}
