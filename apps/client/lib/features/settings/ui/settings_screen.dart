import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/l10n_x.dart';
import '../../export/data/export_service.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../domain/user_settings.dart';

/// Targets, photo retention, language, export, clearing data, privacy and version.
/// Every change is stored and applied immediately.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _save(WidgetRef ref, AppSettings settings) =>
      ref.read(settingsRepositoryProvider).save(settings);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(currentSettingsProvider);

    String kcalText(int? v) =>
        v == null ? l10n.notSet : l10n.valueUnitKcal('$v');
    String gramsText(int? v) =>
        v == null ? l10n.notSet : l10n.valueUnitGrams('$v');

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _Section(l10n.settingsTargetsSection),
          ListTile(
            key: const Key('settingKcal'),
            title: Text(l10n.settingsCalories),
            trailing: Text(kcalText(settings.dailyKcalTarget)),
            onTap: () async {
              final result = await showNumberDialog(
                context,
                title: l10n.settingsCalories,
                initial: settings.dailyKcalTarget?.toString() ?? '',
                allowEmpty: false,
                decimal: false,
                validator: (t) => SettingsLimits.validKcal(parseWholeNumber(t)),
                errorText: l10n.errKcalRange,
              );
              if (result != null) {
                await _save(
                  ref,
                  settings.copyWith(
                    dailyKcalTarget: () => parseWholeNumber(result),
                  ),
                );
              }
            },
          ),
          for (final entry in [
            (
              const Key('settingProtein'),
              l10n.proteinLabel,
              settings.dailyProteinTargetG,
              (AppSettings s, int? v) =>
                  s.copyWith(dailyProteinTargetG: () => v),
            ),
            (
              const Key('settingFat'),
              l10n.fatLabel,
              settings.dailyFatTargetG,
              (AppSettings s, int? v) => s.copyWith(dailyFatTargetG: () => v),
            ),
            (
              const Key('settingCarbs'),
              l10n.carbsLabel,
              settings.dailyCarbsTargetG,
              (AppSettings s, int? v) => s.copyWith(dailyCarbsTargetG: () => v),
            ),
          ])
            ListTile(
              key: entry.$1,
              title: Text(entry.$2),
              trailing: Text(gramsText(entry.$3)),
              onTap: () async {
                final result = await showNumberDialog(
                  context,
                  title: entry.$2,
                  initial: entry.$3?.toString() ?? '',
                  allowEmpty: true,
                  decimal: false,
                  validator: (t) =>
                      SettingsLimits.validMacro(parseWholeNumber(t)),
                  errorText: l10n.errMacroRange,
                );
                if (result != null) {
                  await _save(
                    ref,
                    entry.$4(
                      settings,
                      result.isEmpty ? null : parseWholeNumber(result),
                    ),
                  );
                }
              },
            ),
          ListTile(
            key: const Key('settingPlate'),
            title: Text(l10n.settingsPlate),
            trailing: Text(
              settings.plateDiameterCm == null
                  ? l10n.notSet
                  : l10n.valueUnitCm(
                      context.fmt.weight(settings.plateDiameterCm!),
                    ),
            ),
            onTap: () async {
              final result = await showNumberDialog(
                context,
                title: l10n.settingsPlate,
                initial: settings.plateDiameterCm == null
                    ? ''
                    : context.fmt.weight(settings.plateDiameterCm!),
                allowEmpty: true,
                decimal: true,
                validator: (t) => SettingsLimits.validPlate(parseNumber(t)),
                errorText: l10n.errPlateRange,
              );
              if (result != null) {
                await _save(
                  ref,
                  settings.copyWith(
                    plateDiameterCm: () =>
                        result.isEmpty ? null : parseNumber(result),
                  ),
                );
              }
            },
          ),
          const Divider(),
          _Section(l10n.settingsPhotosSection),
          SwitchListTile(
            key: const Key('settingSavePhotos'),
            title: Text(l10n.settingsSavePhotos),
            subtitle: Text(l10n.settingsSavePhotosHint),
            value: settings.savePhotos,
            onChanged: (v) => _save(ref, settings.copyWith(savePhotos: v)),
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.settingsLanguage),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<AppLanguage>(
                key: const Key('settingLanguage'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppLanguage.system,
                    label: Text(l10n.languageSystem),
                  ),
                  ButtonSegment(
                    value: AppLanguage.ru,
                    label: Text(l10n.languageRussian),
                  ),
                  ButtonSegment(
                    value: AppLanguage.en,
                    label: Text(l10n.languageEnglish),
                  ),
                ],
                selected: {settings.language},
                onSelectionChanged: (s) =>
                    _save(ref, settings.copyWith(language: s.first)),
              ),
            ),
          ),
          const Divider(),
          _Section(l10n.settingsDataSection),
          ListTile(
            key: const Key('exportCsv'),
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(l10n.settingsExportCsv),
            onTap: () => _export(context, ref, ExportFormat.csv),
          ),
          ListTile(
            key: const Key('exportJson'),
            leading: const Icon(Icons.data_object),
            title: Text(l10n.settingsExportJson),
            onTap: () => _export(context, ref, ExportFormat.json),
          ),
          ListTile(
            key: const Key('clearData'),
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              l10n.settingsClearData,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _confirmClear(context, ref),
          ),
          const Divider(),
          _Section(l10n.settingsAbout),
          ListTile(
            key: const Key('openPrivacy'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.settingsPrivacy),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.privacy),
          ),
          ListTile(
            key: const Key('appVersion'),
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsVersion(AppConfig.appVersion)),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    ExportFormat format,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(exportServiceProvider)
          .exportAndShare(format, subject: l10n.exportSubject);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
    }
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearDataTitle),
        content: Text(l10n.clearDataBody),
        actions: [
          TextButton(
            key: const Key('clearCancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('clearConfirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.clearDataConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(servicesProvider).clearAllData();
    ref.read(mealDraftProvider.notifier).clear();
    if (context.mounted) context.go(Routes.splash);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// A small numeric prompt. Returns the entered text (empty when cleared and
/// [allowEmpty]), or null when cancelled.
Future<String?> showNumberDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required bool allowEmpty,
  required bool decimal,
  required bool Function(String) validator,
  required String errorText,
}) => showDialog<String>(
  context: context,
  builder: (context) => _NumberDialog(
    title: title,
    initial: initial,
    allowEmpty: allowEmpty,
    decimal: decimal,
    validator: validator,
    errorText: errorText,
  ),
);

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.initial,
    required this.allowEmpty,
    required this.decimal,
    required this.validator,
    required this.errorText,
  });

  final String title;
  final String initial;
  final bool allowEmpty;
  final bool decimal;
  final bool Function(String) validator;
  final String errorText;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  // Owned by the dialog state so that it lives as long as the exit animation.
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = _controller.text.trim();
    final valid = text.isEmpty ? widget.allowEmpty : widget.validator(text);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('numberDialogField'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            widget.decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
          ),
        ],
        decoration: InputDecoration(errorText: valid ? null : widget.errorText),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('numberDialogApply'),
          onPressed: valid ? () => Navigator.pop(context, text) : null,
          child: Text(l10n.apply),
        ),
      ],
    );
  }
}
