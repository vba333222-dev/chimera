import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:pdfx/pdfx.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/dynamic_watermark_overlay.dart';
import '../widgets/pixel_grid_background.dart';
import '../widgets/scanline_overlay.dart';

class SecureDocumentViewerScreen extends ConsumerStatefulWidget {
  /// Byte Array mentah dari dokumen terdekripsi di RAM
  final Uint8List memoryBytes;
  /// Apakah file bertipe PDF (jika false akan di-treat sebagai gambar)
  final bool isPdf;

  const SecureDocumentViewerScreen({
    super.key,
    required this.memoryBytes,
    required this.isPdf,
  });

  @override
  ConsumerState<SecureDocumentViewerScreen> createState() =>
      _SecureDocumentViewerScreenState();
}

class _SecureDocumentViewerScreenState extends ConsumerState<SecureDocumentViewerScreen> {
  bool _isDisposing = false;
  late final String _timestamp;
  PdfController? _pdfController;

  @override
  void initState() {
    super.initState();
    _initScreenProtection();
    _timestamp = DateTime.now().toUtc().toIso8601String();
    
    if (widget.isPdf) {
      _pdfController = PdfController(
        document: PdfDocument.openData(widget.memoryBytes),
      );
    }
  }

  Future<void> _initScreenProtection() async {
    // Mematikan platform screenshot & screen recording (jika didukung OS)
    await ScreenProtector.preventScreenshotOn();
    await ScreenProtector.protectDataLeakageWithBlur();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _disposeScreenProtection();
    _pdfController?.dispose();
    _releaseMemoryBinding();
    super.dispose();
  }

  Future<void> _disposeScreenProtection() async {
    await ScreenProtector.preventScreenshotOff();
    await ScreenProtector.protectDataLeakageWithBlurOff();
  }

  /// Trigger pembersihan memory binding ke SecureDocumentService.
  /// Secara eksplisit memanggil wipeBytes() pada buffer plaintext
  /// sehingga bytes tidak tertinggal di heap (anti-RAM scraping).
  void _releaseMemoryBinding() {
    // releaseBuffer() memanggil wipeBytes() yang menimpa byte dengan 0x00
    ref.read(secureDocumentServiceProvider).releaseBuffer(widget.memoryBytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_isDisposing) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final currentUser = ref.watch(currentUserIdentityProvider);

    final Scaffold contentScaffold = Scaffold(
      backgroundColor: Colors.transparent, // Background will be handled by PixelGridBackground
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.terminalBg,
            border: Border(bottom: BorderSide(color: AppTheme.terminalBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                   Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, size: 20, color: AppTheme.accentGreen),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('//SECURE_VIEWER', style: TextStyle(color: AppTheme.accentGreen, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.info_outline, color: AppTheme.accentGreen),
                    tooltip: 'Confidential Document',
                    onPressed: () {
                       ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('File is sandboxed. It will be shredded upon exit.', style: TextStyle(fontFamily: 'IBM Plex Mono')),
                          backgroundColor: AppTheme.warningRed,
                        ),
                      );
                    },
                  )
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Lapis Bawah: Penampil Media (Murni RAM)
          Positioned.fill(
            child: widget.isPdf && _pdfController != null
                ? PdfView(
                    controller: _pdfController!,
                    scrollDirection: Axis.vertical,
                  )
                : InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Center(
                      child: Image.memory(
                        widget.memoryBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );

    // Bungkus Scaffold utama dengan DynamicWatermarkOverlay, Scanline, dan PixelGrid
    return PixelGridBackground(
      child: ScanlineOverlay(
        child: DynamicWatermarkOverlay(
          userId: currentUser.id,
          userEmail: currentUser.email,
          timestamp: _timestamp,
          child: contentScaffold,
        ),
      ),
    );
  }
}
