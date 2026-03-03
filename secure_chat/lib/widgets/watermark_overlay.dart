import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WatermarkOverlay extends StatelessWidget {
  /// String utama yang dicetak, ex: UID / Rank / Clearance / Timestamp
  final String watermarkText;
  
  /// Tingkat opasitas. Untuk Dokumen tingkat tinggi ini akan rendah antara 0.05 s/d 0.1
  /// agar isi tidak tertutup tapi masih terekam kamera foto eksternal.
  final double opacity;
  
  /// Warna teks, idealnya menyesuaikan tema
  final Color color;

  const WatermarkOverlay({
    super.key,
    required this.watermarkText,
    this.opacity = 0.08,
    this.color = AppTheme.accentGreen,
  });

  @override
  Widget build(BuildContext context) {
    // Memastikan watermark memanjang penuh tanpa dibatasi touch (tembus pandang input)
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.transparent,
        child: CustomPaint(
          painter: _WatermarkPainter(
            text: watermarkText,
            color: color.withAlpha((opacity * 255).toInt()),
          ),
        ),
      ),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;
  final Color color;

  _WatermarkPainter({required this.text, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
        fontFamily: 'Courier', // Font bergaya intelijen/terminal
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final double textWidth = textPainter.width;
    final double textHeight = textPainter.height;

    // Radius rotasi teks watermark (diagonal 30 derajat ke atas)
    const double angle = -math.pi / 6;

    // Spacing jarak antar "grid" rentetan diagonal teks
    final double xSpacing = textWidth + 80;
    final double ySpacing = textHeight + 150;

    canvas.save();

    // Loop bersarang membentangkan grid tanpa ujung sampai size mentok.
    // Ditarik dari -size.height agar tidak ada area pojok yang lolos dari tinta
    for (double x = -size.height; x < size.width + size.height; x += xSpacing) {
      for (double y = -size.height; y < size.height * 2; y += ySpacing) {
        // Offset tambahan per baris supaya formatnya zig-zag berselang seling grid brick
        final int rowIndex = (y / ySpacing).round();
        final double xOffset = (rowIndex.isEven) ? 0 : (xSpacing / 2);

        canvas.save();
        canvas.translate(x + xOffset, y);
        canvas.rotate(angle);
        textPainter.paint(canvas, const Offset(0, 0));
        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.color != color;
  }
}
