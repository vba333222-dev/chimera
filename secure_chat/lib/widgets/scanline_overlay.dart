import 'package:flutter/material.dart';

class ScanlineOverlay extends StatelessWidget {
  final Widget child;

  const ScanlineOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.2),
                ],
                stops: const [0.0, 0.5, 0.5, 1.0],
              ),
            ),
            // Use ShaderMask or repeating gradient, but for simplicity we can use a BoxPainter or repeated image.
            // A more efficient way is to use a CustomPaint
            child: CustomPaint(
              painter: _ScanlinePainter(),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    const double scanlineHeight = 2.0;
    const double scanlineSpacing = 4.0;

    for (double i = 0; i < size.height; i += scanlineSpacing) {
      canvas.drawRect(Rect.fromLTWH(0, i, size.width, scanlineHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
