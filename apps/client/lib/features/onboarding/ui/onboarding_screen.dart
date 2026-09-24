import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/l10n_x.dart';
import '../../camera/data/gateways.dart';
import '../../settings/domain/user_settings.dart';

/// First-run flow: description, calorie target, optional macros, optional plate
/// diameter and the camera permission. No account is involved.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _steps = 5;

  final _kcal = TextEditingController(text: '${AppSettings.defaultKcalTarget}');
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _carbs = TextEditingController();
  final _plate = TextEditingController();
  int _step = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _kcal.dispose();
    _protein.dispose();
    _fat.dispose();
    _carbs.dispose();
    _plate.dispose();
    super.dispose();
  }

  bool get _kcalValid => SettingsLimits.validKcal(parseWholeNumber(_kcal.text));

  static bool _macroOk(String text) =>
      text.trim().isEmpty || SettingsLimits.validMacro(parseWholeNumber(text));

  bool get _macrosValid =>
      _macroOk(_protein.text) && _macroOk(_fat.text) && _macroOk(_carbs.text);

  bool get _plateValid =>
      _plate.text.trim().isEmpty ||
      SettingsLimits.validPlate(parseNumber(_plate.text));

  bool get _canContinue => switch (_step) {
    1 => _kcalValid,
    2 => _macrosValid,
    3 => _plateValid,
    _ => true,
  };

  void _next() {
    if (_step < _steps - 1 && _canContinue) setState(() => _step++);
  }

  void _skip() {
    switch (_step) {
      case 2:
        _protein.clear();
        _fat.clear();
        _carbs.clear();
      case 3:
        _plate.clear();
    }
    setState(() => _step++);
  }

  Future<void> _finish({required bool askCamera}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    if (askCamera) {
      await ref.read(permissionGatewayProvider).requestCamera();
    }
    int? macro(TextEditingController c) =>
        c.text.trim().isEmpty ? null : parseWholeNumber(c.text);
    final settings = AppSettings(
      dailyKcalTarget: parseWholeNumber(_kcal.text),
      dailyProteinTargetG: macro(_protein),
      dailyFatTargetG: macro(_fat),
      dailyCarbsTargetG: macro(_carbs),
      plateDiameterCm: _plate.text.trim().isEmpty
          ? null
          : parseNumber(_plate.text),
      onboardingCompleted: true,
    );
    await ref.read(settingsRepositoryProvider).save(settings);
    if (!mounted) return;
    context.go(Routes.diary);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isLast = _step == _steps - 1;
    final canSkip = _step == 2 || _step == 3;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _steps),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.onboardingStep(_step + 1, _steps),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _stepBody(context),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: isLast
                        ? FilledButton(
                            key: const Key('onboardingAllowCamera'),
                            onPressed: _finishing
                                ? null
                                : () => _finish(askCamera: true),
                            child: Text(l10n.allowCamera),
                          )
                        : FilledButton(
                            key: const Key('onboardingNext'),
                            onPressed: _canContinue ? _next : null,
                            child: Text(l10n.next),
                          ),
                  ),
                  Row(
                    children: [
                      if (_step > 0)
                        TextButton(
                          key: const Key('onboardingBack'),
                          onPressed: _finishing
                              ? null
                              : () => setState(() => _step--),
                          child: Text(l10n.back),
                        ),
                      const Spacer(),
                      if (canSkip)
                        TextButton(
                          key: const Key('onboardingSkip'),
                          onPressed: _skip,
                          child: Text(l10n.skip),
                        ),
                      if (isLast)
                        TextButton(
                          key: const Key('onboardingSkipCamera'),
                          onPressed: _finishing
                              ? null
                              : () => _finish(askCamera: false),
                          child: Text(l10n.skip),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.onboardingIntroTitle,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(l10n.onboardingIntroBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.onboardingEstimateNotice)),
                  ],
                ),
              ),
            ),
          ],
        );
      case 1:
        return _fieldStep(
          title: l10n.onboardingTargetTitle,
          children: [
            _numberField(
              key: const Key('kcalField'),
              controller: _kcal,
              label: l10n.onboardingTargetHint,
              error: _kcalValid ? null : l10n.errKcalRange,
              decimal: false,
            ),
          ],
        );
      case 2:
        return _fieldStep(
          title: l10n.onboardingMacrosTitle,
          body: l10n.onboardingMacrosBody,
          children: [
            _numberField(
              key: const Key('proteinField'),
              controller: _protein,
              label: l10n.proteinFieldLabel,
              error: _macroOk(_protein.text) ? null : l10n.errMacroRange,
              decimal: false,
            ),
            const SizedBox(height: 12),
            _numberField(
              key: const Key('fatField'),
              controller: _fat,
              label: l10n.fatFieldLabel,
              error: _macroOk(_fat.text) ? null : l10n.errMacroRange,
              decimal: false,
            ),
            const SizedBox(height: 12),
            _numberField(
              key: const Key('carbsField'),
              controller: _carbs,
              label: l10n.carbsFieldLabel,
              error: _macroOk(_carbs.text) ? null : l10n.errMacroRange,
              decimal: false,
            ),
          ],
        );
      case 3:
        return _fieldStep(
          title: l10n.onboardingPlateTitle,
          body: l10n.onboardingPlateBody,
          children: [
            _numberField(
              key: const Key('plateField'),
              controller: _plate,
              label: l10n.plateFieldLabel,
              error: _plateValid ? null : l10n.errPlateRange,
              decimal: true,
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.onboardingCameraTitle,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(l10n.onboardingCameraBody, style: theme.textTheme.bodyLarge),
          ],
        );
    }
  }

  Widget _fieldStep({
    required String title,
    String? body,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineMedium),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String? error,
    required bool decimal,
  }) => TextField(
    key: key,
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
      ),
    ],
    decoration: InputDecoration(labelText: label, errorText: error),
    onChanged: (_) => setState(() {}),
  );
}
