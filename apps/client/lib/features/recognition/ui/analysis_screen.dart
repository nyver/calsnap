import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/l10n_x.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../domain/analysis.dart';
import 'analysis_controller.dart';

export 'analysis_controller.dart' show AnalysisSource;

/// How the analysis screen was left, reported to the capture screen.
enum AnalysisExit { cancelled, tryAnother }

/// Shows the progress of an analysis (cancellable) and its failures.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({required this.source, super.key});

  final AnalysisSource source;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  Timer? _stageTimer;
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    // Purely cosmetic progress messages; no duration is promised.
    _stageTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _stage < 2) setState(() => _stage++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analysisControllerProvider.notifier).start(widget.source);
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    super.dispose();
  }

  void _leave(AnalysisExit exit) {
    if (context.canPop()) context.pop(exit);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(analysisControllerProvider, (previous, next) {
      switch (next.phase) {
        case AnalysisPhase.done:
          context.pushReplacement(Routes.result);
        case AnalysisPhase.cancelled:
          _leave(AnalysisExit.cancelled);
        case AnalysisPhase.working:
        case AnalysisPhase.failed:
          break;
      }
    });
    final state = ref.watch(analysisControllerProvider);
    final l10n = context.l10n;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(analysisControllerProvider.notifier).cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.analyzingTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: state.phase == AnalysisPhase.failed
                ? _Failure(
                    failure: state.failure ?? const UnknownFailure(),
                    onRetry: () =>
                        ref.read(analysisControllerProvider.notifier).retry(),
                    onManual: () {
                      ref.read(mealDraftProvider.notifier).startManual();
                      context.pushReplacement(Routes.newMeal);
                    },
                    onAnother: () => _leave(AnalysisExit.tryAnother),
                    onServerSettings: () => context.go(Routes.settings),
                  )
                : _Progress(
                    stage: state.uploading ? _stage + 1 : 0,
                    onCancel: () =>
                        ref.read(analysisControllerProvider.notifier).cancel(),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.stage, required this.onCancel});

  /// 0 preparing, 1 identifying, 2 portions, 3 nutrition.
  final int stage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [
      l10n.stepPreparing,
      l10n.stepIdentifying,
      l10n.stepPortions,
      l10n.stepNutrition,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 32),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: i < stage
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : i == stage
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          Icons.circle_outlined,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    labels[i],
                    style: i == stage
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: i > stage
                                ? Theme.of(context).colorScheme.outline
                                : null,
                          ),
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('analysisCancel'),
            onPressed: onCancel,
            child: Text(l10n.cancel),
          ),
        ),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({
    required this.failure,
    required this.onRetry,
    required this.onManual,
    required this.onAnother,
    required this.onServerSettings,
  });

  final AnalysisFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onManual;
  final VoidCallback onAnother;
  final VoidCallback onServerSettings;

  static String message(AppLocalizations l10n, AnalysisFailure failure) =>
      switch (failure) {
        OfflineFailure() => l10n.errOffline,
        TimeoutFailure() => l10n.errTimeout,
        RateLimitedFailure() => l10n.errRateLimited,
        UnavailableFailure() => l10n.errUnavailable,
        NotRecognizedFailure() => l10n.errNotRecognized,
        BadImageFailure(:final reason) => switch (reason) {
          BadImageReason.unreadable => l10n.imageUnreadable,
          BadImageReason.tooLarge => l10n.imageTooLarge,
          BadImageReason.rejected => l10n.errBadImage,
        },
        ServerNotConfiguredFailure() => l10n.errServerNotConfigured,
        CertificateFailure() => l10n.errCertificate,
        UnknownFailure() => l10n.errUnknown,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final photoProblem =
        failure is NotRecognizedFailure || failure is BadImageFailure;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          failure is OfflineFailure ? Icons.wifi_off : Icons.error_outline,
          size: 56,
          color: scheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          message(l10n, failure),
          key: const Key('analysisError'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 32),
        if (failure is ServerNotConfiguredFailure ||
            failure is CertificateFailure)
          FilledButton(
            key: const Key('openServerSettings'),
            onPressed: onServerSettings,
            child: Text(l10n.serverSettingsAction),
          )
        else if (photoProblem)
          FilledButton(
            key: const Key('tryAnotherPhoto'),
            onPressed: onAnother,
            child: Text(l10n.tryAnotherPhoto),
          )
        else
          FilledButton(
            key: const Key('analysisRetry'),
            onPressed: onRetry,
            child: Text(l10n.retry),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('analysisAddManually'),
          onPressed: onManual,
          child: Text(l10n.addManually),
        ),
        if (failure is OfflineFailure || failure is UnknownFailure)
          TextButton(
            key: const Key('checkServerSettings'),
            onPressed: onServerSettings,
            child: Text(l10n.serverSettingsAction),
          ),
      ],
    );
  }
}
