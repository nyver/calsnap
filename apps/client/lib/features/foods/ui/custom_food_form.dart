import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/domain/nutrition.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/l10n_x.dart';
import '../domain/food.dart';

/// The form for a custom product: a name, nutrition per 100 g and an optional
/// serving. It creates the product and pops with the [Food].
///
/// It is also the confirmation step of a label scan: [prefill] carries what
/// the photo showed and what to double-check, and nothing is saved until the
/// user taps Create. Values the photo did not show stay empty.
class CustomFoodForm extends ConsumerStatefulWidget {
  const CustomFoodForm({
    required this.initialName,
    this.prefill,
    this.barcode,
    this.onFillFromLabel,
    super.key,
  });

  final String initialName;
  final CustomFoodPrefill? prefill;

  /// The barcode to store with the product, so a later scan finds it locally.
  final String? barcode;

  /// Reads a nutrition label and returns its values; null hides the button.
  final Future<CustomFoodPrefill?> Function()? onFillFromLabel;

  @override
  ConsumerState<CustomFoodForm> createState() => _CustomFoodFormState();
}

class _CustomFoodFormState extends ConsumerState<CustomFoodForm> {
  late final _name = TextEditingController(
    text: widget.prefill?.name ?? widget.initialName,
  );
  late final _kcal = TextEditingController(text: _show(widget.prefill?.kcal));
  late final _protein = TextEditingController(
    text: widget.prefill == null ? '0' : _show(widget.prefill?.protein),
  );
  late final _fat = TextEditingController(
    text: widget.prefill == null ? '0' : _show(widget.prefill?.fat),
  );
  late final _carbs = TextEditingController(
    text: widget.prefill == null ? '0' : _show(widget.prefill?.carbs),
  );
  late final _serving = TextEditingController(
    text: _show(widget.prefill?.servingSizeG),
  );
  late List<String> _notes = widget.prefill?.notes ?? const [];
  bool _busy = false;

  static String _show(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.round().toString() : v.toString();
  }

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _fat, _carbs, _serving]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _servingTyped => _serving.text.trim().isNotEmpty;

  /// Null while a number is missing or unreadable; the button stays disabled.
  CustomFoodInput? get _input {
    final kcal = parseNumber(_kcal.text);
    final p = parseNumber(_protein.text);
    final f = parseNumber(_fat.text);
    final c = parseNumber(_carbs.text);
    if (kcal == null || p == null || f == null || c == null) return null;
    final serving = _servingTyped ? parseNumber(_serving.text) : null;
    if (_servingTyped && serving == null) return null;
    return CustomFoodInput(
      name: _name.text,
      per100: Nutrition(kcal: kcal, protein: p, fat: f, carbs: c),
      servingSizeG: serving,
      barcode: widget.barcode,
    );
  }

  Future<void> _submit() async {
    final input = _input;
    if (input == null || input.validate() != null || _busy) return;
    setState(() => _busy = true);
    final food = await ref.read(foodRepositoryProvider).createCustom(input);
    if (mounted) Navigator.pop(context, food);
  }

  Future<void> _fillFromLabel() async {
    final read = await widget.onFillFromLabel!();
    if (read == null || !mounted) return;
    setState(() {
      if (_name.text.trim().isEmpty && read.name != null) {
        _name.text = read.name!;
      }
      _kcal.text = _show(read.kcal);
      _protein.text = _show(read.protein);
      _fat.text = _show(read.fat);
      _carbs.text = _show(read.carbs);
      _serving.text = _show(read.servingSizeG);
      _notes = read.notes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final input = _input;
    // Field errors only for values that are there and wrong; a missing value
    // just keeps the button disabled.
    final problem = input?.validate();
    final name = _name.text.trim();
    Widget field(
      Key key,
      TextEditingController c,
      String label, {
      String? error,
    }) => TextField(
      key: key,
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: (_) => setState(() {}),
    );
    final macroError = problem == CustomFoodProblem.macros
        ? l10n.errMacro100
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.customProductTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (widget.onFillFromLabel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('customFillFromLabel'),
                onPressed: _fillFromLabel,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(l10n.labelFillButton),
              ),
            ),
          if (_notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('customNotes'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final note in _notes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        note,
                        style: TextStyle(color: scheme.onTertiaryContainer),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('customNameField'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.itemNameLabel,
              errorText: name.isNotEmpty && name.length > 100
                  ? l10n.errNameRequired
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.barcode != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.customBarcode(widget.barcode!),
                key: const Key('customBarcode'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          field(
            const Key('customKcalField'),
            _kcal,
            l10n.kcalPer100Label,
            error: problem == CustomFoodProblem.kcal ? l10n.errKcal900 : null,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: field(
                  const Key('customProteinField'),
                  _protein,
                  l10n.proteinLabel,
                  error: macroError,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: field(
                  const Key('customFatField'),
                  _fat,
                  l10n.fatLabel,
                  error: macroError,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: field(
                  const Key('customCarbsField'),
                  _carbs,
                  l10n.carbsLabel,
                  error: macroError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          field(
            const Key('customServingField'),
            _serving,
            l10n.customServingLabel,
            error: problem == CustomFoodProblem.serving
                ? l10n.errServing
                : null,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('customCreate'),
              onPressed: input != null && problem == null && !_busy
                  ? _submit
                  : null,
              child: Text(l10n.create),
            ),
          ),
        ],
      ),
    );
  }
}
