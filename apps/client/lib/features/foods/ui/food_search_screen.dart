import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/domain/nutrition.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/l10n_x.dart';
import '../../barcode/ui/barcode_providers.dart';
import '../domain/food.dart';

/// Local food search with a "create custom product" form. Pops with the chosen
/// [Food]. Works offline: everything is answered from the local cache.
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key});

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Food> _results = const [];
  bool _loaded = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(query));
  }

  Future<void> _search(String query) async {
    final request = ++_request;
    final results = await ref.read(foodRepositoryProvider).search(query);
    // Ignore answers to outdated queries.
    if (!mounted || request != _request) return;
    setState(() {
      _results = results;
      _loaded = true;
    });
  }

  Future<void> _createCustom() async {
    final food = await showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _CustomFoodForm(initialName: _controller.text.trim()),
      ),
    );
    if (food != null && mounted) context.pop(food);
  }

  Future<void> _scan() async {
    final food = await context.push<Food>(Routes.scan);
    if (food != null && mounted) context.pop(food);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final languageCode = ref.watch(effectiveLanguageCodeProvider);
    final canScan = ref.watch(barcodeSupportedProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.searchFoodsTitle),
        actions: [
          if (canScan)
            IconButton(
              key: const Key('scanBarcode'),
              tooltip: l10n.scanBarcode,
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _scan,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('foodSearchField'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _onChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('createCustomProduct'),
                onPressed: _createCustom,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(l10n.createCustomProduct),
              ),
            ),
          ),
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? Center(
                    child: Text(l10n.noResults, key: const Key('noResults')),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final food = _results[index];
                      return ListTile(
                        key: Key('food-${food.id}'),
                        title: Text(food.displayName(languageCode)),
                        subtitle: Text(
                          '${l10n.totalKcal(fmt.kcal(food.per100.kcal))} / 100 ${l10n.gramsUnit}'
                          ' · ${l10n.proteinLabel} ${fmt.macro(food.per100.protein)}'
                          ' · ${l10n.fatLabel} ${fmt.macro(food.per100.fat)}'
                          ' · ${l10n.carbsLabel} ${fmt.macro(food.per100.carbs)}',
                        ),
                        onTap: () => context.pop(food),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomFoodForm extends ConsumerStatefulWidget {
  const _CustomFoodForm({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_CustomFoodForm> createState() => _CustomFoodFormState();
}

class _CustomFoodFormState extends ConsumerState<_CustomFoodForm> {
  late final _name = TextEditingController(text: widget.initialName);
  final _kcal = TextEditingController();
  final _protein = TextEditingController(text: '0');
  final _fat = TextEditingController(text: '0');
  final _carbs = TextEditingController(text: '0');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _fat, _carbs]) {
      c.dispose();
    }
    super.dispose();
  }

  CustomFoodInput? get _input {
    final kcal = parseNumber(_kcal.text);
    final p = parseNumber(_protein.text);
    final f = parseNumber(_fat.text);
    final c = parseNumber(_carbs.text);
    if (kcal == null || p == null || f == null || c == null) return null;
    return CustomFoodInput(
      name: _name.text,
      per100: Nutrition(kcal: kcal, protein: p, fat: f, carbs: c),
    );
  }

  CustomFoodProblem? get _problem {
    final input = _input;
    if (input == null) {
      // Some number is missing: report name problems first, then numbers.
      if (_name.text.trim().isEmpty || _name.text.trim().length > 100) {
        return CustomFoodProblem.name;
      }
      return CustomFoodProblem.macros;
    }
    return input.validate();
  }

  Future<void> _submit() async {
    final input = _input;
    if (input == null || input.validate() != null || _busy) return;
    setState(() => _busy = true);
    final food = await ref.read(foodRepositoryProvider).createCustom(input);
    if (mounted) Navigator.pop(context, food);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final problem = _problem;
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
          const SizedBox(height: 16),
          TextField(
            key: const Key('customNameField'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.itemNameLabel,
              errorText:
                  problem == CustomFoodProblem.name && _name.text.isNotEmpty
                  ? l10n.errNameRequired
                  : null,
            ),
            onChanged: (_) => setState(() {}),
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('customCreate'),
              onPressed: problem == null && !_busy ? _submit : null,
              child: Text(l10n.create),
            ),
          ),
        ],
      ),
    );
  }
}
