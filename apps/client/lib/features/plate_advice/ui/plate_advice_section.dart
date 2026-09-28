import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/l10n_x.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../../meal/ui/plate_analysis_provider.dart';
import '../../settings/domain/settings_repository.dart';
import '../domain/plate_advice.dart';
import '../domain/plate_advice_failure.dart';
import '../domain/plate_advice_request.dart';
import 'plate_advice_controller.dart';

/// Minimum touch target side, per Material accessibility guidance.
const double _minTapTarget = 48;

/// The AI plate-advice section, attached as the [BalancedPlateCard] footer.
/// Hidden unless the backend advertises `plateAdvice` (spec: "The AI button
/// is offered only for an evaluable plate on a capable backend"). When
/// mounted, the meal is already known to be analyzable: the parent card only
/// renders its footer in that case.
class PlateAdviceSection extends ConsumerWidget {
  const PlateAdviceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(plateAdviceSupportedProvider).value ?? false;
    if (!supported) return const SizedBox.shrink();
    return const _PlateAdviceBody();
  }
}

enum _View { idle, stale, loading, loaded, failed }

class _PlateAdviceBody extends ConsumerWidget {
  const _PlateAdviceBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final draft = ref.watch(mealDraftProvider);
    final analysis = ref.watch(plateAnalysisProvider);
    final locale = ref.watch(effectiveLanguageCodeProvider);
    final request = (draft != null && analysis != null && analysis.isAnalyzable)
        ? PlateAdviceRequest.tryCreate(
            draft: draft,
            analysis: analysis,
            locale: locale,
          )
        : null;
    // The parent card only shows this footer for an analyzable meal; this is
    // a defensive fallback, not an expected path.
    if (request == null) return const SizedBox.shrink();
    final currentFingerprint = request.fingerprint;

    final state = ref.watch(plateAdviceControllerProvider);
    final stale = switch (state) {
      PlateAdviceIdle() => false,
      PlateAdviceLoading(:final fingerprint) =>
        fingerprint != currentFingerprint,
      PlateAdviceLoaded(:final fingerprint) =>
        fingerprint != currentFingerprint,
      PlateAdviceFailed(:final fingerprint) =>
        fingerprint != currentFingerprint,
    };
    final view = switch (state) {
      PlateAdviceIdle() => _View.idle,
      _ when stale => _View.stale,
      PlateAdviceLoading() => _View.loading,
      PlateAdviceLoaded() => _View.loaded,
      PlateAdviceFailed() => _View.failed,
    };

    Future<void> requestAdvice() async {
      final settings = ref.read(settingsRepositoryProvider);
      final accepted =
          await settings.getRaw(SettingKeys.plateAdviceNoticeAccepted) ==
          'true';
      if (!accepted) {
        if (!context.mounted) return;
        final proceed = await showPlateAdviceNotice(context);
        if (proceed != true) return;
        await settings.setRaw(SettingKeys.plateAdviceNoticeAccepted, 'true');
      }
      await ref.read(plateAdviceControllerProvider.notifier).request();
    }

    void openServerSettings() => context.go(Routes.settings);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        key: const Key('plateAdviceSection'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.plateAdviceSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          switch (view) {
            _View.idle => _IdleButton(onPressed: requestAdvice),
            _View.stale => _StaleView(l10n: l10n, onRefresh: requestAdvice),
            _View.loading => _LoadingView(l10n: l10n),
            _View.loaded => _LoadedView(
              advice: (state as PlateAdviceLoaded).advice,
              l10n: l10n,
              theme: theme,
              onRefresh: requestAdvice,
            ),
            _View.failed => _FailedView(
              failure: (state as PlateAdviceFailed).failure,
              l10n: l10n,
              onRetry: requestAdvice,
              onSetupServer: openServerSettings,
            ),
          },
        ],
      ),
    );
  }
}

class _IdleButton extends StatelessWidget {
  const _IdleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ElevatedButton.icon(
      key: const Key('plateAdviceButton'),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, _minTapTarget),
      ),
      icon: const Icon(Icons.auto_awesome),
      label: Text(l10n.plateAdviceButton),
    );
  }
}

class _StaleView extends StatelessWidget {
  const _StaleView({required this.l10n, required this.onRefresh});

  final AppLocalizations l10n;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10n.plateAdviceStale,
        key: const Key('plateAdviceStale'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      _ActionButton(
        key: const Key('plateAdviceRefresh'),
        label: l10n.plateAdviceRefresh,
        onPressed: onRefresh,
      ),
    ],
  );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: l10n.plateAdviceLoading,
    container: true,
    excludeSemantics: true,
    child: Row(
      key: const Key('plateAdviceLoading'),
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.plateAdviceLoading,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({
    required this.advice,
    required this.l10n,
    required this.theme,
    required this.onRefresh,
  });

  final PlateAdvice advice;
  final AppLocalizations l10n;
  final ThemeData theme;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('plateAdviceLoaded'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        advice.summary,
        key: const Key('plateAdviceSummary'),
        style: theme.textTheme.bodyMedium,
      ),
      for (final s in advice.suggestions)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(s.reason, style: theme.textTheme.bodyMedium),
              for (final example in s.examples)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 8),
                  child: Text('•  $example', style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      Text(
        l10n.plateAdviceDisclaimer,
        key: const Key('plateAdviceDisclaimer'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      _ActionButton(
        key: const Key('plateAdviceRefresh'),
        label: l10n.plateAdviceRefresh,
        onPressed: onRefresh,
      ),
    ],
  );
}

class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.failure,
    required this.l10n,
    required this.onRetry,
    required this.onSetupServer,
  });

  final PlateAdviceFailure failure;
  final AppLocalizations l10n;
  final VoidCallback onRetry;
  final VoidCallback onSetupServer;

  String get _message => switch (failure) {
    PlateAdviceOffline() => l10n.errPlateAdviceOffline,
    PlateAdviceServerNotConfigured() => l10n.errPlateAdviceServerNotConfigured,
    PlateAdviceCertificateUntrusted() => l10n.errCertificate,
    PlateAdviceRateLimited() => l10n.errPlateAdviceRateLimited,
    PlateAdviceInvalidResponse() => l10n.errPlateAdviceInvalidResponse,
    PlateAdviceUnavailable() => l10n.errPlateAdviceUnavailable,
  };

  bool get _needsServerSetup =>
      failure is PlateAdviceServerNotConfigured ||
      failure is PlateAdviceCertificateUntrusted;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('plateAdviceFailed'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _message,
        key: const Key('plateAdviceErrorMessage'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      if (_needsServerSetup)
        _ActionButton(
          key: const Key('plateAdviceSetupServer'),
          label: l10n.serverSettingsAction,
          onPressed: onSetupServer,
        )
      else
        _ActionButton(
          key: const Key('plateAdviceTryAgain'),
          label: l10n.retry,
          onPressed: onRetry,
        ),
    ],
  );
}

/// A text button that meets the minimum touch target on every platform.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(minimumSize: const Size(0, _minTapTarget)),
    child: Text(label),
  );
}

/// Shows the one-time privacy notice; returns true when the user continues.
/// See spec's "Privacy notice before first use".
Future<bool?> showPlateAdviceNotice(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('plateAdviceNotice'),
      title: Text(l10n.plateAdviceNoticeTitle),
      content: Text(l10n.plateAdviceNoticeBody),
      actions: [
        TextButton(
          key: const Key('plateAdviceNoticeCancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('plateAdviceNoticeContinue'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.plateAdviceNoticeContinue),
        ),
      ],
    ),
  );
}
