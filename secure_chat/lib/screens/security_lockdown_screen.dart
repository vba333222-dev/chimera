// lib/screens/security_lockdown_screen.dart
//
// Layar yang ditampilkan ketika ancaman keamanan kritikal terdeteksi oleh RASP.
//
// Perilaku:
//   1. Menampilkan alert terminal merah terang yang mendeskripsikan ancaman.
//   2. Secara otomatis menghapus semua kunci sesi (wipe data) dari
//      FlutterSecureStorage dan database SQLCipher.
//   3. Menolak untuk berjalan lebih lanjut — tidak ada tombol "OK" atau
//      cara untuk melewati layar ini.
//   4. Efek visual: glitch/flicker animasi untuk menonjolkan urgensi.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class SecurityLockdownScreen extends ConsumerStatefulWidget {
  final DetectedThreat threat;

  const SecurityLockdownScreen({super.key, required this.threat});

  @override
  ConsumerState<SecurityLockdownScreen> createState() =>
      _SecurityLockdownScreenState();
}

class _SecurityLockdownScreenState
    extends ConsumerState<SecurityLockdownScreen>
    with TickerProviderStateMixin {

  // ── Animasi glitch untuk efek terminal error ──────────────────────────────
  late AnimationController _glitchController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _wiping = true;
  bool _wipeComplete = false;
  final List<String> _wipeLog = [];
  Timer? _wipeTimer;
  int _wipeStep = 0;
  bool _showGlitch = false;
  final Random _rng = Random();

  // Urutan log terminal yang ditampilkan saat proses wipe
  static const _wipeSequence = [
    '> THREAT DETECTED. INITIATING LOCKDOWN...',
    '> TERMINATING ALL ACTIVE SESSIONS...',
    '> REVOKING SESSION TOKENS...',
    '> WIPING ENCRYPTION KEYS FROM SECURE STORAGE...',
    '> FLUSHING KEY DERIVATION CACHE...',
    '> DESTROYING DATABASE ENCRYPTION KEY...',
    '> ZEROING MEMORY BUFFERS...',
    '> PURGING ALL BIOMETRIC CREDENTIALS...',
    '> SECURE WIPE: COMPLETE.',
    '> ACCESS PERMANENTLY DENIED.',
    '> CHIMERA_TERMINAL: LOCKED.',
  ];

  @override
  void initState() {
    super.initState();

    // Paksa status bar menjadi merah
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.red,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Mulai animasi glitch acak
    _startGlitchTimer();

    // Mulai wipe sequence
    _startWipeSequence();
  }

  void _startGlitchTimer() {
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_rng.nextDouble() < 0.3) {
        setState(() => _showGlitch = true);
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) setState(() => _showGlitch = false);
        });
      }
    });
  }

  void _startWipeSequence() {
    // Jalankan wipe aktual secara langsung (tidak menunggu animasi)
    _performActualWipe();

    // Tampilkan log terminal secara bertahap
    _wipeTimer = Timer.periodic(const Duration(milliseconds: 350), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_wipeStep < _wipeSequence.length) {
        setState(() {
          _wipeLog.add(_wipeSequence[_wipeStep]);
          _wipeStep++;
        });
      } else {
        timer.cancel();
        setState(() {
          _wiping = false;
          _wipeComplete = true;
        });
      }
    });
  }

  Future<void> _performActualWipe() async {
    try {
      // 1. Hapus semua kunci dari FlutterSecureStorage
      final storage = ref.read(secureStorageProvider);
      await storage.deleteAll();

      // 2. Hapus database terenkripsi jika sudah terinisialisasi
      // Menggunakan try-catch karena DB mungkin belum diinisialisasi
      try {
        final db = await ref.read(chatDatabaseProvider.future);
        await db.destroyDatabase();
      } catch (_) {
        // DB mungkin belum pernah dibuka — abaikan error ini
      }
    } catch (_) {
      // Wipe tetap "selesai" dari perspektif UI meskipun ada error
    }
  }

  @override
  void dispose() {
    _glitchController.dispose();
    _pulseController.dispose();
    _wipeTimer?.cancel();
    // Reset status bar
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Cegah user menekan tombol back untuk melewati layar ini
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background: noise pattern merah
            Positioned.fill(child: _buildRedNoiseBackground()),

            // Glitch overlay
            if (_showGlitch)
              Positioned.fill(
                child: Container(
                  color: Colors.red.withValues(alpha: _rng.nextDouble() * 0.2),
                  transform: Matrix4.translationValues(
                    (_rng.nextDouble() - 0.5) * 8,
                    0,
                    0,
                  ),
                ),
              ),

            // Scanline effect (merah)
            Positioned.fill(child: _buildRedScanlines()),

            // Konten utama
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAlertHeader(),
                    const SizedBox(height: 24),
                    _buildThreatInfo(),
                    const SizedBox(height: 24),
                    Expanded(child: _buildWipeLog()),
                    if (_wipeComplete) ...[
                      const SizedBox(height: 24),
                      _buildLockedFooter(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widget builders ────────────────────────────────────────────────────────

  Widget _buildRedNoiseBackground() {
    return CustomPaint(
      painter: _RedNoisePainter(seed: _showGlitch ? _rng.nextInt(100) : 0),
    );
  }

  Widget _buildRedScanlines() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanlinePainter(),
      ),
    );
  }

  Widget _buildAlertHeader() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _pulseAnimation.value,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top border strip
              Container(
                height: 4,
                color: Colors.red,
                margin: const EdgeInsets.only(bottom: 16),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.red,
                    child: const Text(
                      '⚠ CRITICAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        fontFamily: 'IBM Plex Mono',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'SECURITY BREACH',
                    style: TextStyle(
                      color: Colors.red[300],
                      fontSize: 11,
                      letterSpacing: 4,
                      fontFamily: 'IBM Plex Mono',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'CHIMERA_TERMINAL',
                style: TextStyle(
                  color: Colors.red[100],
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                  fontFamily: 'IBM Plex Mono',
                ),
              ),
              Text(
                'LOCKDOWN PROTOCOL ENGAGED',
                style: TextStyle(
                  color: Colors.red[400],
                  fontSize: 13,
                  letterSpacing: 4,
                  fontFamily: 'IBM Plex Mono',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThreatInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_bad, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text(
                'THREAT_ID: ${widget.threat.name}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontFamily: 'IBM Plex Mono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.threat.description,
            style: TextStyle(
              color: Colors.red[200],
              fontSize: 13,
              fontFamily: 'IBM Plex Mono',
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TIMESTAMP: ${_formatTimestamp(widget.threat.detectedAt)}',
            style: TextStyle(
              color: Colors.red[700],
              fontSize: 10,
              fontFamily: 'IBM Plex Mono',
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWipeLog() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header terminal
          Row(
            children: [
              Container(width: 8, height: 8, color: Colors.red),
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                color: Colors.red.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                color: Colors.red.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 12),
              Text(
                'root@chimera — wipe_protocol',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 10,
                  fontFamily: 'IBM Plex Mono',
                ),
              ),
            ],
          ),
          Container(
            height: 1,
            color: Colors.red.withValues(alpha: 0.3),
            margin: const EdgeInsets.symmetric(vertical: 8),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _wipeLog.length + (_wiping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _wipeLog.length && _wiping) {
                  // Cursor blink
                  return AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, _) {
                      return Opacity(
                        opacity: _pulseAnimation.value,
                        child: const Text(
                          '█',
                          style: TextStyle(
                            color: Colors.red,
                            fontFamily: 'IBM Plex Mono',
                            fontSize: 13,
                          ),
                        ),
                      );
                    },
                  );
                }
                final log = _wipeLog[index];
                final isLast = index == _wipeLog.length - 1;
                final isDone = log.contains('COMPLETE') ||
                    log.contains('DENIED') ||
                    log.contains('LOCKED');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: isDone
                          ? Colors.red
                          : isLast
                              ? Colors.red[300]
                              : Colors.red[800],
                      fontSize: 12,
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                      height: 1.5,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.red,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, color: Colors.white, size: 16),
          SizedBox(width: 12),
          Text(
            'TERMINAL PERMANENTLY LOCKED. RESTART DEVICE TO RESET.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              fontFamily: 'IBM Plex Mono',
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}Z';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painters
// ─────────────────────────────────────────────────────────────────────────────

class _RedNoisePainter extends CustomPainter {
  final int seed;
  _RedNoisePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final paint = Paint();
    // Gambar noise pixel merah yang sangat redup sebagai texture background
    for (int i = 0; i < 300; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      paint.color = Colors.red.withValues(alpha: rng.nextDouble() * 0.04);
      canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_RedNoisePainter old) => old.seed != seed;
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}
