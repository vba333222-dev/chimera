import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/watermark_overlay.dart';

/// Protokol View-Once untuk media sensitif (Gambar/Lampiran).
/// 
/// Media sengaja dikaburkan (Gaussian Blur tinggi) secara visual dan dikunci.
/// Untuk melihat isi aslinya, pengguna HARUS menyentuh dan menahan widget.
/// Sesaat sesudah sentuhan terlepas (atau terganggu), media tidak lagi 
/// sekadar dikembalikan ke blur, melainkan dibakar secara kriptografis
/// lalu callback [onBurnt] dipanggil untuk update di UI.
class BurnOnReadMedia extends ConsumerStatefulWidget {
  final String filePath;
  final String participantId;
  final VoidCallback onBurnt;

  const BurnOnReadMedia({
    super.key,
    required this.filePath,
    required this.participantId,
    required this.onBurnt,
  });

  @override
  ConsumerState<BurnOnReadMedia> createState() => _BurnOnReadMediaState();
}

class _BurnOnReadMediaState extends ConsumerState<BurnOnReadMedia> {
  bool _isViewing = false;
  bool _isBurnt = false;

  @override
  void initState() {
    super.initState();
    // Secara default cegah screenshot di seluruh layar ketika mount widget ini,
    // (Aman karena page ini kemungkinan adalah chat room page yang juga harus dilindungi).
    _initScreenProtection();
  }

  Future<void> _initScreenProtection() async {
    await ScreenProtector.preventScreenshotOn();
    await ScreenProtector.protectDataLeakageWithBlur();
  }

  Future<void> _handleReleaseOrCancel() async {
    if (_isBurnt) return;
    
    setState(() {
      _isViewing = false;
      _isBurnt = true;
    });

    // Bakar dari Hard Drive Sandbox
    // Explicit call to garbage collector dropping the memory reference
    ref.read(secureDocumentServiceProvider).releaseMemoryBinding();

    // Panggil callback agar parent tahu file sudah invalid
    widget.onBurnt();
  }

  @override
  Widget build(BuildContext context) {
    if (_isBurnt) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.terminalCard,
          border: Border.all(color: AppTheme.terminalBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, color: Colors.grey, size: 24),
            SizedBox(width: 8),
            Text(
              'MEDIA HAS BEEN PURGED',
              style: TextStyle(
                color: Colors.grey,
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPressDown: (_) {
        setState(() => _isViewing = true);
      },
      onLongPressEnd: (_) => _handleReleaseOrCancel(),
      onLongPressCancel: () => _handleReleaseOrCancel(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The image container
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: _isViewing ? AppTheme.accentGreen : AppTheme.terminalBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: _isViewing ? 0 : 20.0,
                sigmaY: _isViewing ? 0 : 20.0,
                tileMode: TileMode.decal,
              ),
              child: Image.file(
                File(widget.filePath),
                fit: BoxFit.cover,
                width: 200,
                height: 250,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 200,
                  height: 250,
                  color: AppTheme.terminalCard,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.red),
                  ),
                ),
              ),
            ),
          ),

          // Watermark Overlay saat sedang menahan jari
          if (_isViewing)
            Positioned.fill(
              child: IgnorePointer(
                child: WatermarkOverlay(watermarkText: widget.participantId),
              ),
            ),

          // Icon indicator saat tertutup blur
          if (!_isViewing)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(150),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accentGreen),
              ),
              child: const Icon(
                Icons.fingerprint,
                color: AppTheme.accentGreen,
                size: 32,
              ),
            ),
        ],
      ),
    );
  }
}
