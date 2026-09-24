import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/l10n_x.dart';
import '../../foods/domain/food.dart';
import '../../foods/ui/custom_food_form.dart';
import '../domain/label_reading.dart';

/// What to double-check after a label scan, in order of importance. The label
/// is a transcription of a photo, so the first note is always there.
List<String> labelNotes(AppLocalizations l10n, LabelReading reading) => [
  if (!reading.isComplete) l10n.labelIncomplete,
  if (reading.warnings.contains(LabelWarning.lowConfidence))
    l10n.labelLowConfidence,
  if (reading.warnings.contains(LabelWarning.energyMismatch))
    l10n.labelEnergyMismatch,
  if (reading.warnings.contains(LabelWarning.energyEstimated))
    l10n.labelEnergyEstimated,
  if (reading.warnings.contains(LabelWarning.valuesConverted))
    l10n.labelConverted,
  if (reading.warnings.contains(LabelWarning.volumeBasis)) l10n.labelVolume,
  l10n.labelCheckValues,
];

/// The values for the custom product form.
CustomFoodPrefill labelPrefill(AppLocalizations l10n, LabelReading reading) =>
    CustomFoodPrefill(
      name: reading.name,
      kcal: reading.kcal,
      protein: reading.protein,
      fat: reading.fat,
      carbs: reading.carbs,
      servingSizeG: reading.servingSizeG,
      notes: labelNotes(l10n, reading),
    );

/// Opens the label camera and returns what it read, or null when the user
/// backed out.
Future<LabelReading?> scanLabel(BuildContext context) =>
    context.push<LabelReading>(Routes.captureLabel);

/// The "fill from a label photo" action of the custom product form.
Future<CustomFoodPrefill?> fillFromLabel(BuildContext context) async {
  final l10n = context.l10n;
  final reading = await scanLabel(context);
  return reading == null ? null : labelPrefill(l10n, reading);
}

/// The confirmation step after a label scan: the custom product form, filled
/// with what was read. Nothing is saved until the user taps Create. Returns
/// the saved [Food], or null when the user cancelled.
Future<Food?> confirmLabelReading(
  BuildContext context,
  LabelReading reading, {
  String? barcode,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<Food>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CustomFoodForm(
        initialName: '',
        prefill: labelPrefill(l10n, reading),
        barcode: barcode,
      ),
    ),
  );
}
