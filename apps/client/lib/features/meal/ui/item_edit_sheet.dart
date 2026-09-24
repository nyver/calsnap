import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/nutrition.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/l10n_x.dart';
import '../domain/meal_draft.dart';
import 'weight_input.dart';

/// Result of the item editor.
sealed class ItemEditResult {
  const ItemEditResult();
}

class ItemEdited extends ItemEditResult {
  const ItemEdited({
    required this.name,
    required this.weightG,
    required this.per100,
  });

  final String name;
  final double weightG;
  final Nutrition per100;
}

/// The user asked to replace the product instead of editing values.
class ItemReplaceRequested extends ItemEditResult {
  const ItemReplaceRequested();
}

/// Quick weight change: one dialog with a numeric field. Returns grams.
Future<double?> showWeightDialog(BuildContext context, DraftItem item) {
  final l10n = context.l10n;
  double? grams = item.weightG;
  return showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(item.name),
        content: WeightInput(
          initialGrams: item.weightG,
          units: item.units,
          autofocus: true,
          onChanged: (g) => setState(() => grams = g),
        ),
        actions: [
          TextButton(
            key: const Key('weightCancel'),
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('weightApply'),
            onPressed: grams == null
                ? null
                : () => Navigator.pop(context, grams),
            child: Text(l10n.apply),
          ),
        ],
      ),
    ),
  );
}

/// Asks for the quantity of a newly added food.
Future<double?> showQuantityDialog(
  BuildContext context, {
  required String name,
  required double initialGrams,
  required FoodUnits? units,
}) {
  final l10n = context.l10n;
  double? grams = initialGrams;
  return showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(name),
        content: WeightInput(
          initialGrams: initialGrams,
          units: units,
          autofocus: true,
          onChanged: (g) => setState(() => grams = g),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('quantityApply'),
            onPressed: grams == null
                ? null
                : () => Navigator.pop(context, grams),
            child: Text(l10n.addItem),
          ),
        ],
      ),
    ),
  );
}

/// The full editor: name, weight and per-100 g values.
Future<ItemEditResult?> showItemEditSheet(
  BuildContext context,
  DraftItem item,
) => showModalBottomSheet<ItemEditResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _ItemEditForm(item: item),
  ),
);

class _ItemEditForm extends StatefulWidget {
  const _ItemEditForm({required this.item});

  final DraftItem item;

  @override
  State<_ItemEditForm> createState() => _ItemEditFormState();
}

class _ItemEditFormState extends State<_ItemEditForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item.name,
  );
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _fat;
  late final TextEditingController _carbs;
  double? _grams;

  @override
  void initState() {
    super.initState();
    final f = NutritionFormatter('en');
    final n = widget.item.per100;
    _kcal = TextEditingController(text: f.weight(n.kcal));
    _protein = TextEditingController(text: f.weight(n.protein));
    _fat = TextEditingController(text: f.weight(n.fat));
    _carbs = TextEditingController(text: f.weight(n.carbs));
    _grams = widget.item.weightG;
  }

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _fat, _carbs]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _nameValid {
    final t = _name.text.trim();
    return t.isNotEmpty && t.length <= 100;
  }

  static bool _inRange(String text, double max) {
    final v = parseNumber(text);
    return v != null && v >= 0 && v <= max;
  }

  bool get _kcalValid => _inRange(_kcal.text, 900);
  bool get _macrosValid =>
      _inRange(_protein.text, 100) &&
      _inRange(_fat.text, 100) &&
      _inRange(_carbs.text, 100);

  bool get _valid => _nameValid && _grams != null && _kcalValid && _macrosValid;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget numeric(
      Key key,
      TextEditingController c,
      String label,
      String? error,
    ) => TextField(
      key: key,
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: (_) => setState(() {}),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.editItemTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('itemNameField'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: l10n.itemNameLabel,
              errorText: _nameValid ? null : l10n.errNameRequired,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          WeightInput(
            initialGrams: widget.item.weightG,
            units: widget.item.units,
            onChanged: (g) => setState(() => _grams = g),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.per100Title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          numeric(
            const Key('kcalPer100Field'),
            _kcal,
            l10n.kcalPer100Label,
            _kcalValid ? null : l10n.errKcal900,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: numeric(
                  const Key('proteinPer100Field'),
                  _protein,
                  l10n.proteinLabel,
                  _inRange(_protein.text, 100) ? null : l10n.errMacro100,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: numeric(
                  const Key('fatPer100Field'),
                  _fat,
                  l10n.fatLabel,
                  _inRange(_fat.text, 100) ? null : l10n.errMacro100,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: numeric(
                  const Key('carbsPer100Field'),
                  _carbs,
                  l10n.carbsLabel,
                  _inRange(_carbs.text, 100) ? null : l10n.errMacro100,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            key: const Key('replaceProduct'),
            onPressed: () =>
                Navigator.pop(context, const ItemReplaceRequested()),
            icon: const Icon(Icons.swap_horiz),
            label: Text(l10n.replaceProduct),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('itemApply'),
                onPressed: _valid
                    ? () => Navigator.pop(
                        context,
                        ItemEdited(
                          name: _name.text.trim(),
                          weightG: _grams!,
                          per100: Nutrition(
                            kcal: parseNumber(_kcal.text)!,
                            protein: parseNumber(_protein.text)!,
                            fat: parseNumber(_fat.text)!,
                            carbs: parseNumber(_carbs.text)!,
                          ),
                        ),
                      )
                    : null,
                child: Text(l10n.apply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
