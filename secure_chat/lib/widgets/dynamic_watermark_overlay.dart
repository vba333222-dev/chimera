import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Widget yang membungkus konten sensitif dengan lapisan teks transparan diagonal.
/// Berfungsi sebagai Data Loss Prevention (DLP) untuk melacak jika layar difoto
/// menggunakan kamera eksternal (karena screenshot level OS sudah dicegah).
class DynamicWatermarkOverlay extends StatelessWidget {
  final Widget child;
  final String userId;
  final String userEmail;
  final String timestamp;

  const DynamicWatermarkOverlay({
    super.key,
    required this.child,
    required this.userId,
    required this.userEmail,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Konten utama yang akan dilindungi (berada di lapisan bawah)
        child,
        
        // Lapisan Watermark di atas
        // IgnorePointer sangat penting agar watermark tidak mencegat sentuhan pengguna (touch events).
        IgnorePointer(
          child: CustomPaint(
            painter: _WatermarkPainter(
              text: '[$userId] $userEmail • $timestamp',
            ),
            // Mengambil ukuran penuh dari child
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;

  _WatermarkPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Pengaturan style teks watermark
    // Menggunakan warna terminal (hijau neon) dengan nilai alpha sangat rendah (12%)
    // agar tulisan terbaca saat layar difoto, namun tidak mengaburkan teks dokumen asli.
    final textStyle = GoogleFonts.ibmPlexMono(
      color: AppTheme.accentGreen.withValues(alpha: 0.12),
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5,
    );

    final textSpan = TextSpan(
      text: text,
      style: textStyle,
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // 2. Kalkulasi jarak spasi antar teks (grid gap)
    final double stepX = textPainter.width + 50;
    final double stepY = textPainter.height + 80;

    // 3. Supaya merentang diagonal dengan baik, kita merotasi matrix canvas
    canvas.save();

    // Pindah titik tengah rotasi ke tengah layar, lalu putar -45 derajat
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-45 * math.pi / 180);

    // 4. Bounding box imajiner setelah kanvas diputar
    // Kita kalikan 2 agar menutupi seluruh sudut pinggiran yang kosong saat rotasi
    final double maxExtents = math.max(size.width, size.height) * 2;
    
    // Geser titik mula iterasi jauh ke pojok kiri atas
    canvas.translate(-maxExtents, -maxExtents);

    // 5. Looping 2D untuk menggambar grid pola teks
    for (double y = 0; y < maxExtents * 2; y += stepY) {
      // Membuat pola zig-zag (staggered) agar teks tiap baris tidak sejajar rata persis
      final double offsetX = (y / stepY).floor() % 2 == 0 ? 0 : (stepX / 2);
      
      for (double x = 0; x < maxExtents * 2; x += stepX) {
        textPainter.paint(canvas, Offset(x + offsetX, y));
      }
    }

    // 6. Kembalikan state canvas ke kondisi normal (tanpa rotasi)
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) {
    // Hanya lukis ulang bila teks (identitas/waktu) mengalami perubahan
    return oldDelegate.text != text;
  }
}
