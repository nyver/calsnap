import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../shared/l10n_x.dart';
import '../../camera/data/gateways.dart';
import '../../foods/domain/food.dart';
import '../../label/ui/label_flow.dart';
import '../../label/ui/label_reader.dart';
import '../../meal/domain/meal.dart';
import '../../recognition/domain/analysis.dart';
import '../../recognition/ui/analysis_screen.dart' show analysisFailureMessage;
import '../domain/gtin.dart';
import '../domain/packaged_product.dart';
import 'scanner_view.dart';

/// Scans a product barcode (or takes its digits by hand), looks the product up
/// and pops with the [Food]. The caller asks for the quantity.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

enum _Phase { scanning, looking, found, failed }

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  final _manual = TextEditingController();
  CameraAccess? _access;
  _Phase _phase = _Phase.scanning;
  Food? _food;
  Object? _failure;
  String? _code;
  bool _manualInvalid = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkCamera());
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _checkCamera() async {
    final gateway = ref.read(permissionGatewayProvider);
    var access = await gateway.cameraStatus();
    if (access == CameraAccess.denied) access = await gateway.requestCamera();
    if (mounted) setState(() => _access = access);
  }

  /// A code from the camera. Misreads fail the check digit and are dropped
  /// silently; the camera simply keeps looking.
  void _onCode(String raw) {
    if (_phase != _Phase.scanning) return;
    final code = Gtin.normalize(raw);
    if (code != null) unawaited(_lookup(code));
  }

  void _submitManual() {
    final code = Gtin.normalize(_manual.text);
    if (code == null) {
      setState(() => _manualInvalid = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _manualInvalid = false);
    unawaited(_lookup(code));
  }

  Future<void> _lookup(String code) async {
    setState(() {
      _phase = _Phase.looking;
      _code = code;
    });
    final locale = ref.read(effectiveLanguageCodeProvider);
    try {
      final food = await ref.read(productLookupProvider)(code, locale: locale);
      if (!mounted) return;
      setState(() {
        _food = food;
        _phase = _Phase.found;
      });
    } on ProductNotFoundException catch (e) {
      _fail(e);
    } on AnalysisFailure catch (e) {
      _fail(e);
    } on Exception catch (e) {
      // Anything unexpected is shown as a generic, retryable failure.
      _fail(e);
    }
  }

  void _fail(Object failure) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _phase = _Phase.failed;
    });
  }

  /// The chain for a barcode nobody knows: photograph the nutrition table,
  /// confirm what was read, save it locally under this barcode.
  Future<void> _scanLabel() async {
    final code = _code;
    final reading = await scanLabel(context);
    if (reading == null || !mounted) return;
    final food = await confirmLabelReading(context, reading, barcode: code);
    if (food != null && mounted) context.pop(food);
  }

  void _again() => setState(() {
    _phase = _Phase.scanning;
    _food = null;
    _failure = null;
    _manual.clear();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.scanning => _Scanning(
            access: _access,
            manual: _manual,
            manualInvalid: _manualInvalid,
            onCode: _onCode,
            onSubmit: _submitManual,
            onChanged: () {
              if (_manualInvalid) setState(() => _manualInvalid = false);
            },
            onRequest: _checkCamera,
          ),
          _Phase.looking => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.scanLooking, key: const Key('scanLooking')),
              ],
            ),
          ),
          _Phase.found => _Found(
            food: _food!,
            onAdd: () => context.pop(_food),
            onAgain: _again,
          ),
          _Phase.failed => _Failed(
            failure: _failure,
            onScanLabel: ref.watch(labelReadingSupportedProvider).value ?? false
                ? _scanLabel
                : null,
            onRetry: () {
              final code = _code;
              if (code != null) unawaited(_lookup(code));
            },
            onAgain: _again,
          ),
        },
      ),
    );
  }
}

class _Scanning extends ConsumerWidget {
  const _Scanning({
    required this.access,
    required this.manual,
    required this.manualInvalid,
    required this.onCode,
    required this.onSubmit,
    required this.onChanged,
    required this.onRequest,
  });

  final CameraAccess? access;
  final TextEditingController manual;
  final bool manualInvalid;
  final ValueChanged<String> onCode;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final Widget top;
    if (access == null) {
      top = const Center(child: CircularProgressIndicator());
    } else if (access != CameraAccess.granted) {
      top = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                l10n.scanPermissionBody,
                key: const Key('scanPermission'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              access == CameraAccess.permanentlyDenied
                  ? FilledButton(
                      key: const Key('scanOpenSettings'),
                      onPressed: () =>
                          ref.read(permissionGatewayProvider).openSettings(),
                      child: Text(l10n.openSettings),
                    )
                  : FilledButton(
                      key: const Key('scanAllowCamera'),
                      onPressed: onRequest,
                      child: Text(l10n.allowCamera),
                    ),
            ],
          ),
        ),
      );
    } else {
      top = ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ref.watch(barcodeScannerBuilderProvider)(context, onCode),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Text(
                l10n.scanHint,
                key: const Key('scanHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(child: top),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('scanManualField'),
                  controller: manual,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 14,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSubmit(),
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: l10n.scanManualLabel,
                    counterText: '',
                    errorText: manualInvalid ? l10n.scanManualInvalid : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton(
                  key: const Key('scanManualFind'),
                  onPressed: onSubmit,
                  child: Text(l10n.scanFind),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Found extends ConsumerWidget {
  const _Found({
    required this.food,
    required this.onAdd,
    required this.onAgain,
  });

  final Food food;
  final VoidCallback onAdd;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final fmt = context.fmt;
    final theme = Theme.of(context);
    final n = food.per100;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          key: const Key('scanFound'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  food.name,
                  key: const Key('scanFoundName'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.totalKcal(fmt.kcal(n.kcal))} / 100 ${l10n.gramsUnit}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.proteinLabel} ${fmt.macro(n.protein)}'
                  ' · ${l10n.fatLabel} ${fmt.macro(n.fat)}'
                  ' · ${l10n.carbsLabel} ${fmt.macro(n.carbs)}',
                  key: const Key('scanFoundMacros'),
                ),
                if (food.gramsPerPortion != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.scanServing(fmt.weight(food.gramsPerPortion!)),
                    key: const Key('scanFoundServing'),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  food.source == NutritionSourceName.packaged
                      ? l10n.scanSource
                      : l10n.scanSourceUser,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('scanAdd'),
          onPressed: onAdd,
          child: Text(l10n.addItem),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('scanAgain'),
          onPressed: onAgain,
          child: Text(l10n.scanAnother),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.failure,
    required this.onScanLabel,
    required this.onRetry,
    required this.onAgain,
  });

  final Object? failure;

  /// Offered for an unknown product when the server can read labels.
  final VoidCallback? onScanLabel;
  final VoidCallback onRetry;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final notFound = failure is ProductNotFoundException;
    final failed = failure;
    final message = failed is AnalysisFailure
        ? analysisFailureMessage(l10n, failed)
        : notFound
        ? l10n.scanNotFound
        : l10n.errUnknown;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notFound ? Icons.search_off : Icons.error_outline,
              size: 56,
              color: scheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              key: const Key('scanError'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            if (notFound && onScanLabel != null)
              FilledButton(
                key: const Key('scanLabel'),
                onPressed: onScanLabel,
                child: Text(l10n.scanLabelButton),
              ),
            if (!notFound)
              FilledButton(
                key: const Key('scanRetry'),
                onPressed: onRetry,
                child: Text(l10n.retry),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('scanAgain'),
              onPressed: onAgain,
              child: Text(l10n.scanAnother),
            ),
          ],
        ),
      ),
    );
  }
}
