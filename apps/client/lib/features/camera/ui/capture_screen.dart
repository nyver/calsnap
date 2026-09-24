import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../shared/l10n_x.dart';
import '../../label/domain/label_reading.dart';
import '../../label/ui/label_reader.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../../recognition/domain/analysis.dart';
import '../../recognition/ui/analysis_controller.dart';
import '../../recognition/ui/analysis_screen.dart';
import '../data/gateways.dart';
import '../data/photo_analyzer.dart';
import '../domain/photo_quality.dart';
import 'photo_quality_banner.dart';
import 'plate_guide.dart';
import 'plate_sheet.dart';

/// What the capture screen is for.
enum CaptureMode {
  /// A photo of the meal (the default).
  meal,

  /// The second, side photo of the meal shown in the result screen.
  side,

  /// A nutrition facts table on a package; pops with the [LabelReading].
  label,
}

/// In-app camera with flash, lens switch, gallery import and a preview with
/// "Retake" and "Analyze". Permission is requested here, at the point of use.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({
    this.startWithGallery = false,
    this.mode = CaptureMode.meal,
    super.key,
  });

  /// Opens the gallery picker right away (from the "Choose from gallery" action).
  final bool startWithGallery;

  /// Side and label captures leave the current draft alone, so there is no
  /// manual entry there and no plate guide.
  final CaptureMode mode;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  CameraAccess? _access;
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  FlashMode _flash = FlashMode.off;
  bool _cameraFailed = false;
  bool _busy = false;

  /// The photo shown in the preview.
  String? _photoPath;

  /// Camera-made files are removed when the screen is left; gallery originals never.
  bool _photoIsOurs = false;

  /// The local checks of the photo in the preview; null until they finish or
  /// when the photo cannot be judged.
  PhotoQuality? _quality;

  /// A plate size chosen for this photo only (see [AnalysisSource]).
  ({double? cm})? _plateOverride;

  /// A label is being read by the backend.
  bool _reading = false;

  /// Why the last label reading failed, shown above the buttons.
  String? _readError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    // Refresh the client tunables opportunistically; failures are ignored.
    unawaited(ref.read(remoteConfigRepositoryProvider).refresh());
    if (widget.startWithGallery) {
      await _pickFromGallery();
      if (!mounted || _photoPath != null) return;
    }
    final gateway = ref.read(permissionGatewayProvider);
    var access = await gateway.cameraStatus();
    if (access == CameraAccess.denied) {
      access = await gateway.requestCamera();
    }
    if (!mounted) return;
    setState(() => _access = access);
    if (access == CameraAccess.granted) await _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'no cameras');
      await _initController(_cameras[_cameraIndex]);
    } on CameraException {
      if (mounted) setState(() => _cameraFailed = true);
    }
  }

  Future<void> _initController(CameraDescription description) async {
    final previous = _controller;
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    await previous?.dispose();
    await controller.initialize();
    await controller.setFlashMode(_flash);
    if (mounted) setState(() => _cameraFailed = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      unawaited(controller.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _photoPath == null) {
      unawaited(_openCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    _deleteOwnedPhoto();
    super.dispose();
  }

  void _deleteOwnedPhoto() {
    final path = _photoPath;
    if (path != null && _photoIsOurs) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      _showPhoto(file.path, ours: true);
    } on CameraException {
      // The shutter failed; the viewfinder stays and the user can try again.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final path = await ref.read(galleryPickerProvider).pick();
    if (!mounted || path == null) return;
    _deleteOwnedPhoto();
    _showPhoto(path, ours: false);
  }

  void _showPhoto(String path, {required bool ours}) {
    setState(() {
      _photoPath = path;
      _photoIsOurs = ours;
      _quality = null;
    });
    unawaited(_assess(path));
  }

  /// Runs the local checks in the background; the preview is usable at once.
  Future<void> _assess(String path) async {
    final check = ref.read(photoQualityProvider);
    final quality = await check(
      path,
      checkPlate: widget.mode == CaptureMode.meal,
    );
    if (!mounted || _photoPath != path) return;
    setState(() => _quality = quality);
  }

  double? get _shownPlate => _plateOverride != null
      ? _plateOverride!.cm
      : ref.read(currentSettingsProvider).plateDiameterCm;

  Future<void> _choosePlate() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showPlateSheet(context, current: _shownPlate);
    if (choice == null || !mounted) return;
    if (!choice.remember) {
      setState(() => _plateOverride = (cm: choice.diameterCm));
      return;
    }
    try {
      final settings = ref.read(currentSettingsProvider);
      await ref
          .read(settingsRepositoryProvider)
          .save(settings.copyWith(plateDiameterCm: () => choice.diameterCm));
      if (mounted) setState(() => _plateOverride = null);
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(l10n.saveFailed)));
    }
  }

  String? _plateLabel(BuildContext context) {
    final l10n = context.l10n;
    final cm = _shownPlate;
    if (cm == null) return null;
    final value = context.fmt.weight(cm);
    return _plateOverride != null
        ? l10n.plateChipOnce(value)
        : l10n.plateChipUsual(value);
  }

  void _retake() {
    _deleteOwnedPhoto();
    setState(() {
      _photoPath = null;
      _photoIsOurs = false;
      _quality = null;
      _readError = null;
    });
    if (_controller == null && _access == CameraAccess.granted) {
      unawaited(_openCamera());
    }
  }

  Future<void> _analyze() async {
    final path = _photoPath;
    if (path == null) return;
    if (widget.mode == CaptureMode.label) {
      await _readLabel(path);
      return;
    }
    final AnalysisSource source;
    if (widget.mode == CaptureMode.side) {
      final draft = ref.read(mealDraftProvider);
      final jpeg = draft?.sourceJpeg;
      if (jpeg == null) return;
      source = AnalysisSource(
        path: path,
        top: PreparedPhoto(jpeg: jpeg, tempFile: draft?.tempPhotoFile),
      );
    } else {
      source = AnalysisSource(path: path, plateOverride: _plateOverride);
    }
    final exit = await context.push<AnalysisExit>(
      Routes.analysis,
      extra: source,
    );
    if (!mounted) return;
    switch (exit) {
      case AnalysisExit.tryAnother:
        _retake();
      case AnalysisExit.refined || AnalysisExit.keepFirst:
        context.pop();
      case AnalysisExit.cancelled || null:
        break;
    }
  }

  /// Has the backend read the label; on success the screen pops with the
  /// reading and the caller shows the confirmation form.
  Future<void> _readLabel(String path) async {
    if (_reading) return;
    final l10n = context.l10n;
    setState(() {
      _reading = true;
      _readError = null;
    });
    String? error;
    try {
      final reading = await ref.read(labelReaderProvider).read(path);
      if (!mounted) return;
      context.pop(reading);
      return;
    } on LabelNotRecognizedException {
      error = l10n.labelNotRecognized;
    } on AnalysisFailure catch (failure) {
      error = analysisFailureMessage(l10n, failure);
    } on Exception {
      error = l10n.errUnknown;
    }
    if (mounted) {
      setState(() {
        _reading = false;
        _readError = error;
      });
    }
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    await _controller?.setFlashMode(next);
    if (mounted) setState(() => _flash = next);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _initController(_cameras[_cameraIndex]);
    } on CameraException {
      if (mounted) setState(() => _cameraFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.mode == CaptureMode.side
              ? l10n.sideCaptureTitle
              : widget.mode == CaptureMode.label
              ? l10n.labelScanTitle
              : _photoPath == null
              ? l10n.captureTitle
              : l10n.previewTitle,
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _photoPath != null
            ? _Preview(
                path: _photoPath!,
                issues: _quality?.issues ?? const [],
                plateLabel: _plateLabel(context),
                showPlate: widget.mode == CaptureMode.meal,
                analyzeText: widget.mode == CaptureMode.label
                    ? l10n.labelRead
                    : l10n.analyze,
                busy: _reading,
                error: _readError,
                onPlate: _choosePlate,
                onRetake: _retake,
                onAnalyze: _analyze,
              )
            : _viewfinder(context),
      ),
    );
  }

  Widget _viewfinder(BuildContext context) {
    final access = _access;
    if (access == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (access != CameraAccess.granted) {
      return _PermissionNeeded(
        permanentlyDenied: access == CameraAccess.permanentlyDenied,
        onOpenSettings: () =>
            ref.read(permissionGatewayProvider).openSettings(),
        onRequest: () async {
          final result = await ref
              .read(permissionGatewayProvider)
              .requestCamera();
          if (!mounted) return;
          setState(() => _access = result);
          if (result == CameraAccess.granted) await _openCamera();
        },
        onGallery: _pickFromGallery,
        onManual: widget.mode == CaptureMode.meal ? _manual : null,
      );
    }

    final controller = _controller;
    if (_cameraFailed ||
        controller == null ||
        !controller.value.isInitialized) {
      if (_cameraFailed) {
        return _CameraUnavailable(
          onGallery: _pickFromGallery,
          onManual: widget.mode == CaptureMode.meal ? _manual : null,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = context.l10n;
    return Column(
      children: [
        if (widget.mode != CaptureMode.meal)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              widget.mode == CaptureMode.label
                  ? l10n.labelHint
                  : l10n.sideCaptureHint,
              key: Key(
                widget.mode == CaptureMode.label
                    ? 'labelCaptureHint'
                    : 'sideCaptureHint',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Center(child: CameraPreview(controller)),
              if (widget.mode == CaptureMode.meal)
                const Positioned.fill(child: PlateGuide()),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                key: const Key('galleryButton'),
                tooltip: l10n.gallery,
                color: Colors.white,
                iconSize: 32,
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: _pickFromGallery,
              ),
              GestureDetector(
                key: const Key('shutter'),
                onTap: _capture,
                child: Semantics(
                  button: true,
                  label: l10n.shutter,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white54, width: 4),
                    ),
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : null,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('flashButton'),
                    tooltip: switch (_flash) {
                      FlashMode.off => l10n.flashOff,
                      FlashMode.auto => l10n.flashAuto,
                      _ => l10n.flashOn,
                    },
                    color: Colors.white,
                    iconSize: 32,
                    icon: Icon(switch (_flash) {
                      FlashMode.off => Icons.flash_off,
                      FlashMode.auto => Icons.flash_auto,
                      _ => Icons.flash_on,
                    }),
                    onPressed: _cycleFlash,
                  ),
                  if (_cameras.length > 1)
                    IconButton(
                      key: const Key('switchCamera'),
                      tooltip: l10n.switchCamera,
                      color: Colors.white,
                      iconSize: 32,
                      icon: const Icon(Icons.cameraswitch_outlined),
                      onPressed: _switchCamera,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _manual() {
    ref.read(mealDraftProvider.notifier).startManual();
    context.pushReplacement(Routes.newMeal);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.path,
    required this.issues,
    required this.plateLabel,
    required this.showPlate,
    required this.analyzeText,
    required this.busy,
    required this.error,
    required this.onPlate,
    required this.onRetake,
    required this.onAnalyze,
  });

  final String path;
  final List<PhotoIssue> issues;

  /// The chip text for the known plate; null when there is none yet.
  final String? plateLabel;
  final bool showPlate;

  /// The label of the main button ("Analyze", or "Read label").
  final String analyzeText;

  /// A request is running: the buttons wait.
  final bool busy;

  /// Why the last request failed, if it did.
  final String? error;
  final VoidCallback onPlate;
  final VoidCallback onRetake;
  final VoidCallback onAnalyze;

  Widget _analyzeChild() => busy
      ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(analyzeText);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Expanded(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Center(
              child: Text(
                l10n.imageUnreadable,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              key: const Key('readError'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        if (issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PhotoQualityBanner(issues: issues),
          ),
        if (showPlate)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                key: const Key('plateChip'),
                avatar: const Icon(Icons.circle_outlined, size: 18),
                label: Text(plateLabel ?? l10n.plateChipAdd),
                onPressed: onPlate,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                // With advice to follow, retaking is the suggested action.
                child: issues.isEmpty
                    ? OutlinedButton(
                        key: const Key('retake'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: busy ? null : onRetake,
                        child: Text(l10n.retake),
                      )
                    : FilledButton(
                        key: const Key('retake'),
                        onPressed: busy ? null : onRetake,
                        child: Text(l10n.retake),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: issues.isEmpty
                    ? FilledButton(
                        key: const Key('analyze'),
                        onPressed: busy ? null : onAnalyze,
                        child: _analyzeChild(),
                      )
                    : OutlinedButton(
                        key: const Key('analyze'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: busy ? null : onAnalyze,
                        child: _analyzeChild(),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionNeeded extends StatelessWidget {
  const _PermissionNeeded({
    required this.permanentlyDenied,
    required this.onOpenSettings,
    required this.onRequest,
    required this.onGallery,
    required this.onManual,
  });

  final bool permanentlyDenied;
  final VoidCallback onOpenSettings;
  final VoidCallback onRequest;
  final VoidCallback onGallery;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Explanation(
      icon: Icons.no_photography_outlined,
      title: l10n.cameraPermissionTitle,
      body: l10n.cameraPermissionBody,
      actions: [
        if (permanentlyDenied)
          FilledButton(
            key: const Key('openSettings'),
            onPressed: onOpenSettings,
            child: Text(l10n.openSettings),
          )
        else
          FilledButton(
            key: const Key('allowCamera'),
            onPressed: onRequest,
            child: Text(l10n.allowCamera),
          ),
        OutlinedButton(
          key: const Key('chooseFromGallery'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
          onPressed: onGallery,
          child: Text(l10n.chooseFromGallery),
        ),
        if (onManual != null)
          OutlinedButton(
            key: const Key('addManuallyFromCapture'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            onPressed: onManual,
            child: Text(l10n.addManually),
          ),
      ],
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.onGallery, required this.onManual});

  final VoidCallback onGallery;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Explanation(
      icon: Icons.videocam_off_outlined,
      title: l10n.captureTitle,
      body: l10n.cameraUnavailable,
      actions: [
        FilledButton(onPressed: onGallery, child: Text(l10n.chooseFromGallery)),
        if (onManual != null)
          OutlinedButton(onPressed: onManual, child: Text(l10n.addManually)),
      ],
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          for (final a in actions) ...[
            SizedBox(width: double.infinity, child: a),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );
}
