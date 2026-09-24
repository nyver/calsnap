import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../shared/l10n_x.dart';

/// Builds the live camera view that reports every barcode it reads. A seam for
/// tests: the real view needs a camera.
typedef BarcodeScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

final barcodeScannerBuilderProvider = Provider<BarcodeScannerBuilder>(
  (ref) =>
      (context, onCode) => CameraBarcodeScanner(onCode: onCode),
);

/// The camera view (`mobile_scanner`, on-device recognition). Only the retail
/// formats are read: EAN-13, EAN-8 and UPC-A.
class CameraBarcodeScanner extends StatefulWidget {
  const CameraBarcodeScanner({required this.onCode, super.key});

  final ValueChanged<String> onCode;

  @override
  State<CameraBarcodeScanner> createState() => _CameraBarcodeScannerState();
}

class _CameraBarcodeScannerState extends State<CameraBarcodeScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null) {
                widget.onCode(value);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.scanCameraError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        // A frame to aim with: retail barcodes are wide and short.
        IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: AspectRatio(
                aspectRatio: 2.4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            key: const Key('scanTorch'),
            tooltip: l10n.scanTorch,
            color: Colors.white,
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ),
      ],
    );
  }
}
