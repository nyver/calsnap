import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../shared/l10n_x.dart';
import '../../meal/ui/meal_draft_notifier.dart';
import '../../recognition/ui/analysis_controller.dart';
import '../../recognition/ui/analysis_screen.dart';
import '../data/gateways.dart';

/// In-app camera with flash, lens switch, gallery import and a preview with
/// "Retake" and "Analyze". Permission is requested here, at the point of use.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({this.startWithGallery = false, super.key});

  /// Opens the gallery picker right away (from the "Choose from gallery" action).
  final bool startWithGallery;

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
      setState(() {
        _photoPath = file.path;
        _photoIsOurs = true;
      });
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
    setState(() {
      _photoPath = path;
      _photoIsOurs = false;
    });
  }

  void _retake() {
    _deleteOwnedPhoto();
    setState(() {
      _photoPath = null;
      _photoIsOurs = false;
    });
    if (_controller == null && _access == CameraAccess.granted) {
      unawaited(_openCamera());
    }
  }

  Future<void> _analyze() async {
    final path = _photoPath;
    if (path == null) return;
    final exit = await context.push<AnalysisExit>(
      Routes.analysis,
      extra: AnalysisSource(path: path),
    );
    if (!mounted) return;
    if (exit == AnalysisExit.tryAnother) _retake();
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
        title: Text(_photoPath == null ? l10n.captureTitle : l10n.previewTitle),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _photoPath != null
            ? _Preview(
                path: _photoPath!,
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
        onManual: _manual,
      );
    }

    final controller = _controller;
    if (_cameraFailed ||
        controller == null ||
        !controller.value.isInitialized) {
      if (_cameraFailed) {
        return _CameraUnavailable(
          onGallery: _pickFromGallery,
          onManual: _manual,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = context.l10n;
    return Column(
      children: [
        Expanded(child: Center(child: CameraPreview(controller))),
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
    required this.onRetake,
    required this.onAnalyze,
  });

  final String path;
  final VoidCallback onRetake;
  final VoidCallback onAnalyze;

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
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onRetake,
                  child: Text(l10n.retake),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  key: const Key('analyze'),
                  onPressed: onAnalyze,
                  child: Text(l10n.analyze),
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
  final VoidCallback onManual;

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
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Explanation(
      icon: Icons.videocam_off_outlined,
      title: l10n.captureTitle,
      body: l10n.cameraUnavailable,
      actions: [
        FilledButton(onPressed: onGallery, child: Text(l10n.chooseFromGallery)),
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
