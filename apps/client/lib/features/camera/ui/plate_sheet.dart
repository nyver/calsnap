import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/l10n_x.dart';
import '../../settings/domain/user_settings.dart';

/// The plate the user picked. [diameterCm] is null for "no plate size".
class PlateChoice {
  const PlateChoice(this.diameterCm, {required this.remember});

  final double? diameterCm;

  /// True to keep it as "my usual plate" (the saved setting); false to use it
  /// for this photo only.
  final bool remember;
}

/// Common dinner plate diameters offered as one-tap choices.
const List<int> platePresetsCm = [20, 22, 24, 26, 28, 30];

/// Asks for the plate size. Returns null when dismissed.
Future<PlateChoice?> showPlateSheet(
  BuildContext context, {
  required double? current,
}) => showModalBottomSheet<PlateChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _PlateSheet(current: current),
);

class _PlateSheet extends StatefulWidget {
  const _PlateSheet({required this.current});

  final double? current;

  @override
  State<_PlateSheet> createState() => _PlateSheetState();
}

class _PlateSheetState extends State<_PlateSheet> {
  late final TextEditingController _custom = TextEditingController();
  double? _selected;
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// The value of the custom field, when it has one.
  double? get _typed => parseNumber(_custom.text);

  bool get _customInvalid =>
      _custom.text.trim().isNotEmpty && !SettingsLimits.validPlate(_typed);

  void _pick(double cm) => setState(() {
    _selected = cm;
    _custom.clear();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final typed = _custom.text.trim().isEmpty ? null : _typed;
    final effective = typed ?? _selected;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.plateSheetTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(l10n.plateSheetBody),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cm in platePresetsCm)
                    ChoiceChip(
                      key: Key('platePreset-$cm'),
                      label: Text(l10n.valueUnitCm(fmt.weight(cm.toDouble()))),
                      selected: _selected == cm && _custom.text.trim().isEmpty,
                      onSelected: (_) => _pick(cm.toDouble()),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('plateCustom'),
                controller: _custom,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.plateOtherLabel,
                  errorText: _customInvalid ? l10n.errPlateRange : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              SwitchListTile(
                key: const Key('plateRemember'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.plateRemember),
                value: _remember,
                onChanged: (v) => setState(() => _remember = v),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    key: const Key('plateNone'),
                    onPressed: () => Navigator.pop(
                      context,
                      PlateChoice(null, remember: _remember),
                    ),
                    child: Text(l10n.plateNone),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('plateApply'),
                    onPressed: effective == null || _customInvalid
                        ? null
                        : () => Navigator.pop(
                            context,
                            PlateChoice(effective, remember: _remember),
                          ),
                    child: Text(l10n.apply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
