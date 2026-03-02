import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class BiometricLoginScreen extends StatefulWidget {
  const BiometricLoginScreen({Key? key}) : super(key: key);

  @override
  State<BiometricLoginScreen> createState() => _BiometricLoginScreenState();
}

class _BiometricLoginScreenState extends State<BiometricLoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

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
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          color: AppTheme.accentGreen, // Would normally pulse but leaving simple
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
            
            // Scanner Core
            GestureDetector(
              onTap: () {
                // Mock scanning and auth
                 context.go('/chats');
              },
              child: Center(
                child: SizedBox(
                  width: 256,
                  height: 256,
                  child: Stack(
                    children: [
                      // Inner background
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.02),
                            border: Border.all(color: AppTheme.terminalBorder),
                          ),
                        ),
                      ),
                      // Scanner Corners
                      Positioned(top: 0, left: 0, child: _ScannerCorner(isTop: true, isLeft: true)),
                      Positioned(top: 0, right: 0, child: _ScannerCorner(isTop: true, isLeft: false)),
                      Positioned(bottom: 0, left: 0, child: _ScannerCorner(isTop: false, isLeft: true)),
                      Positioned(bottom: 0, right: 0, child: _ScannerCorner(isTop: false, isLeft: false)),
                      
                      // Fingerprint Icon
                      const Center(
                        child: Icon(
                          Icons.fingerprint,
                          color: Colors.white,
                          size: 110,
                        ),
                      ),

                      // Animated Scanline
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

            // Text prompts
            SizedBox(
              width: 256,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.only(left: 4),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.grey[700]!)),
                    ),
                    child: Text(
                      '// System Check: Locked',
                      style: TextStyle(color: Colors.grey[500], fontSize: 10, letterSpacing: 2),
                    ),
                  ),
                  const Text(
                    'IDENTITY VERIFICATION',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(color: AppTheme.terminalBorder.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Text('\$', style: TextStyle(color: AppTheme.accentGreen)),
                        const SizedBox(width: 8),
                        Text('SCAN_BIOMETRIC', style: TextStyle(color: Colors.grey[300], fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 1)),
                        const SizedBox(width: 4),
                        Container(width: 8, height: 16, color: AppTheme.accentGreen), // Simulated cursor
                      ],
                    ),
                  )
                ],
              ),
            ),
            
            const Spacer(),
            
            // Bottom Action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  Container(
                    width: 280,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: InkWell(
                      onTap: () {
                        context.push('/device-verify');
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
}

class _ScannerCorner extends StatelessWidget {
  final bool isTop;
  final bool isLeft;

  const _ScannerCorner({Key? key, required this.isTop, required this.isLeft}) : super(key: key);

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
