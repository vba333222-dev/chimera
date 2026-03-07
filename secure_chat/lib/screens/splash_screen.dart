// lib/screens/splash_screen.dart
//
// Splash screen visual-only — TIDAK ada navigasi di sini.
// Navigasi dikelola oleh SecureChatApp._showSplash via setState().
// Widget ini hanya bertanggung jawab untuk render animasi.

import 'dart:async';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _entryCtrl.forward();
    if (!mounted) return;
    _glowCtrl.repeat(reverse: true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _blinkCtrl.repeat();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _glowCtrl.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gunakan Container hitam penuh — menutupi seluruh layar sebagai overlay
    return Container(
      color: Colors.black,
      child: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _entryCtrl,
            curve: Curves.easeOut,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge([_glowCtrl, _blinkCtrl]),
              builder: (context, _) => CustomPaint(
                size: const Size(260, 260),
                painter: _ShieldPainter(
                  glowIntensity: _glowCtrl.value,
                  cursorVisible: _blinkCtrl.value < 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter — Neon Shield + Terminal Symbol
// ─────────────────────────────────────────────────────────────────────────────

class _ShieldPainter extends CustomPainter {
  final double glowIntensity;
  final bool cursorVisible;

  const _ShieldPainter({
    required this.glowIntensity,
    required this.cursorVisible,
  });

  static const Color _green = Color(0xFF22FF55);

  Path _buildShieldPath(Size sz) {
    final w = sz.width;
    final h = sz.height;
    return Path()
      ..moveTo(w * 0.50, h * 0.04)
      ..lineTo(w * 0.09, h * 0.21)
      ..cubicTo(w * 0.07, h * 0.52, w * 0.14, h * 0.68, w * 0.50, h * 0.95)
      ..cubicTo(w * 0.86, h * 0.68, w * 0.93, h * 0.52, w * 0.91, h * 0.21)
      ..lineTo(w * 0.50, h * 0.04)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shield = _buildShieldPath(size);

    // Shield outer glow (animated intensity)
    canvas.drawPath(
      shield,
      Paint()
        ..color = _green.withValues(alpha: 0.25 + glowIntensity * 0.30)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          14 + glowIntensity * 18,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeJoin = StrokeJoin.round,
    );

    // Shield crisp stroke
    canvas.drawPath(
      shield,
      Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Terminal ">" chevron
    final cx = size.width * 0.37;
    final cy = size.height * 0.52;
    final arm = size.width * 0.16;

    final chevron = Path()
      ..moveTo(cx - arm * 0.5, cy - arm)
      ..lineTo(cx + arm * 0.5, cy)
      ..lineTo(cx - arm * 0.5, cy + arm);

    // Chevron glow
    canvas.drawPath(
      chevron,
      Paint()
        ..color = _green.withValues(alpha: 0.35 + glowIntensity * 0.25)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          8 + glowIntensity * 8,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = StrokeCap.round,
    );

    // Chevron crisp
    canvas.drawPath(
      chevron,
      Paint()
        ..color = _green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = StrokeCap.round,
    );

    // Cursor "_" (blinking)
    if (cursorVisible) {
      final x1 = cx + arm * 0.75;
      final x2 = cx + arm * 1.85;
      final y = cy + arm * 0.18;

      // Glow
      canvas.drawLine(
        Offset(x1, y),
        Offset(x2, y),
        Paint()
          ..color = _green.withValues(alpha: 0.40 + glowIntensity * 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round,
      );

      // Crisp
      canvas.drawLine(
        Offset(x1, y),
        Offset(x2, y),
        Paint()
          ..color = _green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.glowIntensity != glowIntensity || old.cursorVisible != cursorVisible;
}
