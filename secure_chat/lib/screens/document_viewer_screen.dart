import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/watermark_overlay.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  /// Path absolut file fisik di Temporary Directory
  final String filePath;
  /// Apakah file bertipe PDF (jika false akan di-treat sebagai gambar)
  final bool isPdf;
  /// Data dinamis untuk digambar pada watermark (email petugas/id sesi)
  final String participantId;

  const DocumentViewerScreen({
    super.key,
    required this.filePath,
    required this.isPdf,
    required this.participantId,
  });

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  bool _isDisposing = false;
  late final String _watermarkText;

  @override
  void initState() {
    super.initState();
    _initScreenProtection();
    _generateWatermarkData();
  }

  void _generateWatermarkData() {
    final now = DateTime.now().toUtc().toIso8601String();
    // Identitas user yg SEDANG MEMBACA + Waktu
    _watermarkText = 'CHIMERA: ${widget.participantId} | $now';
  }

  Future<void> _initScreenProtection() async {
    // Mematikan screenshot & merekam layar selama screen ini terbuka
    await ScreenProtector.preventScreenshotOn();
    await ScreenProtector.protectDataLeakageWithBlur();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _disposeScreenProtection();
    _shredStashedFile();
    super.dispose();
  }

  Future<void> _disposeScreenProtection() async {
    await ScreenProtector.preventScreenshotOff();
    await ScreenProtector.protectDataLeakageWithBlurOff();
  }

  /// Trigger pembersihan memory binding ke SecureDocumentService
  void _shredStashedFile() {
    if (!mounted) {
       ref.read(secureDocumentServiceProvider).releaseMemoryBinding();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposing) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SECURE VIEWER', style: TextStyle(color: AppTheme.accentGreen)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: AppTheme.accentGreen),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Confidential Document',
            onPressed: () {
               ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('File is sandboxed. It will be shredded upon exit.'),
                  backgroundColor: AppTheme.warningRed,
                ),
              );
            },
          )
        ],
      ),
      body: Stack(
        children: [
          // Lapis Bawah: Penampil Media
          Positioned.fill(
            child: widget.isPdf 
                ? SfPdfViewer.file(
                    File(widget.filePath),
                    canShowScrollHead: false,
                    enableDoubleTapZooming: true,
                  )
                : InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Center(
                      child: Image.file(
                        File(widget.filePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
          ),
          
          // Lapis Atas: Watermark Overlay (tembus sentuhan)
          Positioned.fill(
            child: WatermarkOverlay(
              watermarkText: _watermarkText,
            ),
          ),
        ],
      ),
    );
  }
}
