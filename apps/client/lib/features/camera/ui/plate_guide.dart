import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/l10n_x.dart';

/// The viewfinder guide: a dashed plate outline and a one-line instruction.
/// Purely visual; it never blocks the shutter.
class PlateGuide extends StatelessWidget {
  const PlateGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              key: const Key('plateGuideOutline'),
              painter: _OutlinePainter(),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    l10n.plateGuideHint,
                    key: const Key('plateGuideHint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) * 0.38;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dashes = 36;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
    // A cross-hair dot: the camera should point at the middle of the plate.
    canvas.drawCircle(center, 3, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) => false;
}
