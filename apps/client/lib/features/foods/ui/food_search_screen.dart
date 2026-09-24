import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/l10n_x.dart';
import '../../barcode/ui/barcode_providers.dart';
import '../../label/ui/label_flow.dart';
import '../../label/ui/label_reader.dart';
import '../domain/food.dart';
import 'custom_food_form.dart';

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

  Future<void> _createCustom({required bool canScanLabel}) async {
    final food = await showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CustomFoodForm(
          initialName: _controller.text.trim(),
          onFillFromLabel: canScanLabel ? () => fillFromLabel(context) : null,
        ),
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
    final canScanLabel =
        ref.watch(labelReadingSupportedProvider).value ?? false;
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
                onPressed: () => _createCustom(canScanLabel: canScanLabel),
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
