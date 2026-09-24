import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/l10n_x.dart';
import '../domain/meal_draft.dart';
import '../domain/quantity.dart';

String unitLabel(AppLocalizations l10n, QuantityUnit unit) => switch (unit) {
  QuantityUnit.gram => l10n.unitGram,
  QuantityUnit.milliliter => l10n.unitMilliliter,
  QuantityUnit.piece => l10n.unitPiece,
  QuantityUnit.portion => l10n.unitPortion,
};

/// A quantity field with a unit selector. Reports the weight in grams, or null
/// while the entry is invalid. Pieces and portions are offered only when the
/// food defines them.
class WeightInput extends StatefulWidget {
  const WeightInput({
    required this.initialGrams,
    required this.onChanged,
    this.units,
    this.autofocus = false,
    this.fieldKey = const Key('weightField'),
    super.key,
  });

  final double initialGrams;
  final FoodUnits? units;
  final bool autofocus;
  final Key fieldKey;

  /// Called with the grams (valid) or null (invalid entry).
  final ValueChanged<double?> onChanged;

  @override
  State<WeightInput> createState() => _WeightInputState();
}

class _WeightInputState extends State<WeightInput> {
  late final TextEditingController _controller;
  QuantityUnit _unit = QuantityUnit.gram;
  double? _grams;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _grams = widget.initialGrams;
    _controller = TextEditingController(
      text: NutritionFormatter('en').weight(widget.initialGrams),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<QuantityUnit> get _available => Quantity.availableUnits(
    gramsPerPiece: widget.units?.gramsPerPiece,
    gramsPerPortion: widget.units?.gramsPerPortion,
  );

  void _recompute() {
    final amount = parseNumber(_controller.text);
    final grams = amount == null
        ? null
        : Quantity.toGrams(
            amount,
            _unit,
            densityGPerMl: widget.units?.densityGPerMl,
            gramsPerPiece: widget.units?.gramsPerPiece,
            gramsPerPortion: widget.units?.gramsPerPortion,
          );
    final valid = Quantity.isValidWeight(grams);
    setState(() {
      _touched = true;
      _grams = valid ? grams : null;
    });
    widget.onChanged(valid ? grams : null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final showError = _touched && _grams == null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: widget.fieldKey,
            controller: _controller,
            autofocus: widget.autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.itemWeightLabel,
              errorText: showError ? l10n.errWeightRange : null,
              helperText:
                  !showError && _unit != QuantityUnit.gram && _grams != null
                  ? l10n.weightInGrams(fmt.weight(_grams!))
                  : null,
            ),
            onChanged: (_) => _recompute(),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<QuantityUnit>(
          key: const Key('unitDropdown'),
          value: _unit,
          items: [
            for (final u in _available)
              DropdownMenuItem(value: u, child: Text(unitLabel(l10n, u))),
          ],
          onChanged: (u) {
            if (u == null) return;
            _unit = u;
            _recompute();
          },
        ),
      ],
    );
  }
}
