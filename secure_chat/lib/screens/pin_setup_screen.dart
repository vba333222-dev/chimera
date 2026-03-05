// lib/screens/pin_setup_screen.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PinSetupScreen — First-Run PIN Configuration
// ─────────────────────────────────────────────────────────────────────────────
//
// Muncul HANYA saat pertama kali install (first-run guard).
// User diminta mengatur 3 PIN berbeda:
//   1. PIN Utama (real vault access)
//   2. PIN Decoy (vault palsu — plausible deniability)
//   3. Kill PIN opsional (self-destruct + transisi decoy)
//
// Semua PIN di-hash dengan SHA-256+salt sebelum disimpan ke SecureStorage.
// Tidak ada PIN literal yang tersimpan di code atau disk.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/scrambled_pin_pad.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Setup Steps
// ─────────────────────────────────────────────────────────────────────────────

enum _SetupStep { mainPin, confirmMain, decoyPin, confirmDecoy, killPin, done }

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen>
    with SingleTickerProviderStateMixin {
  _SetupStep _step = _SetupStep.mainPin;
  String _pin = '';
  String _mainPinTemp = '';
  String _decoyPinTemp = '';
  String? _errorMsg;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── PIN Pad Handler ────────────────────────────────────────────────────────

  void _onKeyPress(String key) {
    if (key == 'DEL') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
    } else if (key == 'ENT') {
      _handleEnter();
    } else if (_pin.length < 8) {
      setState(() {
        _pin += key;
        _errorMsg = null;
      });
    }
  }

  Future<void> _handleEnter() async {
    if (_pin.length < 4) {
      setState(() => _errorMsg = 'MINIMUM: 4 DIGITS');
      return;
    }

    switch (_step) {
      case _SetupStep.mainPin:
        setState(() {
          _mainPinTemp = _pin;
          _pin = '';
          _step = _SetupStep.confirmMain;
        });

      case _SetupStep.confirmMain:
        if (_pin != _mainPinTemp) {
          setState(() {
            _errorMsg = 'PIN TIDAK COCOK — ULANGI';
            _pin = '';
          });
          return;
        }
        setState(() { _pin = ''; _step = _SetupStep.decoyPin; });

      case _SetupStep.decoyPin:
        if (_pin == _mainPinTemp) {
          setState(() {
            _errorMsg = 'DECOY PIN HARUS BERBEDA DARI PIN UTAMA';
            _pin = '';
          });
          return;
        }
        setState(() {
          _decoyPinTemp = _pin;
          _pin = '';
          _step = _SetupStep.confirmDecoy;
        });

      case _SetupStep.confirmDecoy:
        if (_pin != _decoyPinTemp) {
          setState(() {
            _errorMsg = 'PIN TIDAK COCOK — ULANGI';
            _pin = '';
          });
          return;
        }
        setState(() { _pin = ''; _step = _SetupStep.killPin; });

      case _SetupStep.killPin:
        // Kill PIN bisa sama dengan skip (kosong = tidak pakai Kill PIN)
        // Jika user tekan ENT tanpa input, skip Kill PIN
        final killPin = _pin.isEmpty ? '${_mainPinTemp}_no_kill' : _pin;

        if (_pin.isNotEmpty && (_pin == _mainPinTemp || _pin == _decoyPinTemp)) {
          setState(() {
            _errorMsg = 'KILL PIN HARUS UNIK';
            _pin = '';
          });
          return;
        }

        // Simpan semua PIN
        await _savePins(killPin: killPin);

      case _SetupStep.done:
        break;
    }
  }

  Future<void> _savePins({required String killPin}) async {
    try {
      final pinService = ref.read(pinServiceProvider);
      await pinService.setupPins(
        mainPin: _mainPinTemp,
        decoyPin: _decoyPinTemp,
        killPin: killPin,
      );

      if (mounted) {
        setState(() => _step = _SetupStep.done);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'SETUP GAGAL: ${e.toString().substring(0, 30)}');
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_step == _SetupStep.done) return _buildDoneScreen();

    return Scaffold(
      backgroundColor: AppTheme.terminalBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 32),

              // Step indicator
              _buildStepIndicator(),
              const SizedBox(height: 24),

              // Prompt
              _buildPrompt(),
              const SizedBox(height: 20),

              // PIN dots
              _buildPinDots(),
              const SizedBox(height: 12),

              // Error
              if (_errorMsg != null)
                Text(
                  '⚠ $_errorMsg',
                  style: const TextStyle(
                    color: AppTheme.warningRed,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontFamily: 'IBM Plex Mono',
                  ),
                ),

              const Spacer(),

              // PIN Pad
              ScrambledPinPad(onKeyPress: _onKeyPress),
              const SizedBox(height: 12),

              // Skip hint for Kill PIN
              if (_step == _SetupStep.killPin)
                Center(
                  child: GestureDetector(
                    onTap: () => _handleEnter(), // ENT with empty = skip
                    child: Text(
                      '[ ENT kosong = lewati Kill PIN ]',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontFamily: 'IBM Plex Mono',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (ctx, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: AppTheme.accentGreen.withValues(alpha: _pulseAnimation.value * 0.15),
            child: const Text(
              '⬡ CHIMERA TERMINAL :: FIRST RUN',
              style: TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 10,
                letterSpacing: 3,
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'KONFIGURASI\nKEAMANAN PIN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final steps = [
      _SetupStep.mainPin,
      _SetupStep.confirmMain,
      _SetupStep.decoyPin,
      _SetupStep.confirmDecoy,
      _SetupStep.killPin,
    ];
    return Row(
      children: steps.asMap().entries.map((entry) {
        final isDone = steps.indexOf(_step) > entry.key;
        final isCurrent = entry.value == _step;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            height: 2,
            color: isDone
                ? AppTheme.accentGreen
                : isCurrent
                    ? AppTheme.accentGreen.withValues(alpha: 0.5)
                    : AppTheme.terminalDim,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrompt() {
    final Map<_SetupStep, List<String>> prompts = {
      _SetupStep.mainPin:      ['PIN UTAMA', 'Untuk akses vault asli anda'],
      _SetupStep.confirmMain:  ['KONFIRMASI PIN UTAMA', 'Masukkan ulang PIN utama anda'],
      _SetupStep.decoyPin:     ['PIN DECOY', 'Untuk membuka vault palsu (plausible deniability)'],
      _SetupStep.confirmDecoy: ['KONFIRMASI PIN DECOY', 'Masukkan ulang PIN decoy anda'],
      _SetupStep.killPin:      ['KILL PIN (Opsional)', 'Trigger penghancuran data darurat'],
    };

    final prompt = prompts[_step] ?? ['', ''];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> ${prompt[0]}',
          style: const TextStyle(
            color: AppTheme.accentGreen,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            fontFamily: 'IBM Plex Mono',
          ),
        ),
        Text(
          prompt[1],
          style: TextStyle(color: Colors.grey[500], fontSize: 12, fontFamily: 'IBM Plex Mono'),
        ),
      ],
    );
  }

  Widget _buildPinDots() {
    return Row(
      children: List.generate(8, (i) {
        final filled = i < _pin.length;
        return Container(
          margin: const EdgeInsets.only(right: 10),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppTheme.accentGreen : Colors.transparent,
            border: Border.all(
              color: filled ? AppTheme.accentGreen : AppTheme.terminalDim,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDoneScreen() {
    return Scaffold(
      backgroundColor: AppTheme.terminalBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, color: AppTheme.accentGreen, size: 64),
            const SizedBox(height: 24),
            const Text(
              'PIN BERHASIL DIKONFIGURASI',
              style: TextStyle(
                color: AppTheme.accentGreen,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                fontFamily: 'IBM Plex Mono',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mengarahkan ke layar login...',
              style: TextStyle(color: Colors.grey[600], fontSize: 11, fontFamily: 'IBM Plex Mono'),
            ),
          ],
        ),
      ),
    );
  }
}
