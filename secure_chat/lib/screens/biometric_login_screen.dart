import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/scrambled_pin_pad.dart';

class BiometricLoginScreen extends ConsumerStatefulWidget {
  const BiometricLoginScreen({super.key});

  @override
  ConsumerState<BiometricLoginScreen> createState() => _BiometricLoginScreenState();
}

class _BiometricLoginScreenState extends ConsumerState<BiometricLoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;
  bool _usePinFallback = false;
  String _pin = '';
  final String _correctPin = '1337'; // Dummy PIN for demonstration

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    // Auto-trigger biometric after a short delay for visual effect
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_usePinFallback) {
        _authenticateBiometric();
      }
    });
  }

  Future<void> _authenticateBiometric() async {
    await ref.read(authProvider.notifier).checkBiometric();
    final status = ref.read(authProvider).status;
    
    if (status == AuthStatus.authenticated && mounted) {
      context.go('/device-verify');
    } else if (status == AuthStatus.error && mounted) {
      setState(() {
        _usePinFallback = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric locked/unavailable. Falling back to PIN.'),
          backgroundColor: AppTheme.warningRed,
        ),
      );
      ref.read(auditLogServiceProvider).logEvent(
        'AUTH_FAILURE_BIOMETRIC', 
        'Biometric authentication unavailable or failed completely.',
      );
    }
  }

  void _onPinKeyPress(String key) {
    if (key == 'DEL') {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin = _pin.substring(0, _pin.length - 1);
        });
      }
    } else if (key == 'ENT') {
      if (_pin == _correctPin) {
        ref.read(vaultModeProvider.notifier).setMode(VaultMode.real);
        context.go('/device-verify');
      } else if (_pin == '654321') {
        ref.read(vaultModeProvider.notifier).setMode(VaultMode.decoy);
        context.go('/device-verify');
      } else if (_pin == '9999') {
        // DURESS PIN ENTERED
        // 1. Set duress mode so the next screens show dummy data
        ref.read(duressModeProvider.notifier).enable();
        
        // 2. Trigger self destruct protocol asynchronously
        final destructService = ref.read(selfDestructServiceProvider);
        
        // We log it FIRST before the service obliterates the log database
        ref.read(auditLogServiceProvider).logEvent('DURESS_TRIGGERED', 'Self-destruct mechanism initiated via PIN').then((_) {
          destructService.executeSelfDestruct();
        });

        // 3. Navigate away to make it look like a successful login
        context.go('/device-verify');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ACCESS DENIED. INVALID PIN.'),
            backgroundColor: AppTheme.warningRed,
          ),
        );
        ref.read(auditLogServiceProvider).logEvent('AUTH_FAILURE_PIN', 'Invalid PIN entry attempt');
        setState(() {
          _pin = '';
        });
      }
    } else {
      if (_pin.length < 4) {
        setState(() {
          _pin += key;
        });
      }
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes just in case
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        context.go('/device-verify');
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by AppWrapper
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Access Level: 0',
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.terminal, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  fontFamily: 'IBM Plex Mono'),
                              children: [
                                TextSpan(text: 'SECURE', style: TextStyle(color: Colors.white)),
                                TextSpan(text: '_LINK', style: TextStyle(color: AppTheme.accentGreen)),
                              ],
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          color: AppTheme.accentGreen, // Would normally pulse
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Online',
                          style: TextStyle(
                            color: AppTheme.accentGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const Spacer(),
            
            // Core UI (Scanner or PIN)
            if (_usePinFallback) _buildPinEntry() else _buildBiometricScanner(),
            
            const Spacer(),
            
            // Bottom Action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  if (!_usePinFallback)
                    Container(
                      width: 280,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.terminalBorder),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _usePinFallback = true;
                          });
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.dialpad, color: AppTheme.accentGreen, size: 18),
                            SizedBox(width: 12),
                            Text('USE PIN ENTRY', style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 280,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.terminalBorder),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _usePinFallback = false;
                            _pin = '';
                            _authenticateBiometric();
                          });
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fingerprint, color: AppTheme.accentGreen, size: 18),
                            SizedBox(width: 12),
                            Text('RETRY BIOMETRIC', style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Opacity(
                    opacity: 0.5,
                    child: Column(
                      children: [
                        Container(width: 48, height: 1, color: Colors.grey[700]),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock, size: 14, color: Colors.grey[400]),
                            const SizedBox(width: 8),
                            Text('END-TO-END ENCRYPTED', style: TextStyle(color: Colors.grey[500], fontSize: 10, letterSpacing: 2, fontFamily: 'IBM Plex Mono')),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricScanner() {
    return Column(
      children: [
        GestureDetector(
          onTap: _authenticateBiometric,
          child: Center(
            child: SizedBox(
              width: 256,
              height: 256,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        border: Border.all(color: AppTheme.terminalBorder),
                      ),
                    ),
                  ),
                  const Positioned(top: 0, left: 0, child: _ScannerCorner(isTop: true, isLeft: true)),
                  const Positioned(top: 0, right: 0, child: _ScannerCorner(isTop: true, isLeft: false)),
                  const Positioned(bottom: 0, left: 0, child: _ScannerCorner(isTop: false, isLeft: true)),
                  const Positioned(bottom: 0, right: 0, child: _ScannerCorner(isTop: false, isLeft: false)),
                  const Center(
                    child: Icon(Icons.fingerprint, color: Colors.white, size: 110),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      child: AnimatedBuilder(
                        animation: _scanAnimation,
                        builder: (context, child) {
                          return FractionalTranslation(
                            translation: Offset(0, _scanAnimation.value - 0.5),
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: AppTheme.accentGreen,
                                boxShadow: AppTheme.glowGreen,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: 256,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.only(left: 4),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey[700]!))),
                child: Text('// System Check: Locked', style: TextStyle(color: Colors.grey[500], fontSize: 10, letterSpacing: 2)),
              ),
              const Text('IDENTITY VERIFICATION', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(color: AppTheme.terminalBorder.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Text('\$', style: TextStyle(color: AppTheme.accentGreen)),
                    const SizedBox(width: 8),
                    Text('SCAN_BIOMETRIC', style: TextStyle(color: Colors.grey[300], fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 1)),
                    const SizedBox(width: 4),
                    Container(width: 8, height: 16, color: AppTheme.accentGreen), 
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinEntry() {
    return Column(
      children: [
        const Text('OVR_RIDE_PIN_REQ', style: TextStyle(color: AppTheme.accentGreen, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4)),
        const SizedBox(height: 16),
        // Passcode indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            bool isFilled = index < _pin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isFilled ? AppTheme.accentGreen : Colors.transparent,
                border: Border.all(color: AppTheme.accentGreen, width: 2),
                boxShadow: isFilled ? AppTheme.glowGreen : null,
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        // Scrambled Keypad
        ScrambledPinPad(
          onKeyPress: _onPinKeyPress,
          scrambleOnTouch: true,
        ),
      ],
    );
  }
}

// The _KeypadButton was removed because it is now defined in scrambled_pin_pad.dart 

class _ScannerCorner extends StatelessWidget {
  final bool isTop;
  final bool isLeft;

  const _ScannerCorner({required this.isTop, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? const BorderSide(color: AppTheme.accentGreen, width: 2) : BorderSide.none,
          bottom: !isTop ? const BorderSide(color: AppTheme.accentGreen, width: 2) : BorderSide.none,
          left: isLeft ? const BorderSide(color: AppTheme.accentGreen, width: 2) : BorderSide.none,
          right: !isLeft ? const BorderSide(color: AppTheme.accentGreen, width: 2) : BorderSide.none,
        ),
      ),
    );
  }
}
