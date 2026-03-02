import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class DeviceVerificationScreen extends StatelessWidget {
  const DeviceVerificationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Uses AppWrapper pixel grid
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      onPressed: () => context.pop(),
                    ),
                  ),
                  const Text('sys_verify_v2.0', style: TextStyle(color: AppTheme.accentGreen, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.terminalBorder),
                    ),
                    child: const Icon(Icons.terminal, size: 20, color: AppTheme.accentGreen),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Top Status Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border(left: BorderSide(color: AppTheme.accentGreen, width: 4)),
                ),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, color: AppTheme.accentGreen), // Pulse
                    const SizedBox(width: 12),
                    const Text('>> STATUS: SCANNING_HARDWARE_', style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Scanner Graphic
              Container(
                width: 192,
                height: 192,
                decoration: BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border.all(color: AppTheme.accentGreen.withOpacity(0.4)),
                  boxShadow: AppTheme.glowGreen,
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.8,
                        child: Image.network(
                          'https://lh3.googleusercontent.com/aida-public/AB6AXuBFSUWksRGK9j4rwUAq4jvm0LMNgCRxF2sfgbycGNrFFIhAEvLy4yO0wgnOg1ZbWbLc3bVvKnsW4buuglskia8uCtQHLemswwvLhaPY6vd5riPtrq21cHCqhkKaejGEB2J5TWDwj-cRt-PpvdMKUn9OVLnHvxrBtY80B99GfjFuL1X25QL8_kJ6HgXIanlxAZ5a3D0ujzIV5jlBUEdiW15JvD_pYa9GSUlKNUEjLZ8WMJPyv7zmB3m1CsxQbHAOi9iVDCpQCI46y230',
                          fit: BoxFit.cover,
                          color: AppTheme.accentGreen,
                          colorBlendMode: BlendMode.color,
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(Icons.lock_reset, color: AppTheme.accentGreen, size: 60),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Progress Bar
              SizedBox(
                width: 192,
                child: Column(
                  children: [
                    Row(
                      children: List.generate(8, (index) {
                        bool isActive = index < 4;
                        return Expanded(
                          child: Container(
                            height: 8,
                            margin: EdgeInsets.only(right: index == 7 ? 0 : 6),
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.accentGreen : AppTheme.accentGreen.withOpacity(0.2),
                              boxShadow: isActive ? AppTheme.glowGreen : null,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Init', style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                        Text('50%', style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                        Text('Bind', style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Text info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.accentGreen.withOpacity(0.3)),
                ),
                child: Text('ZERO-TRUST PROTOCOL', style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
              const SizedBox(height: 12),
              const Text('DEVICE BINDING', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 12),
              Text(
                '// Establishing end-to-end encrypted channel.\n// Binding account to hardware ID.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.7), fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Target Fingerprint
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border.all(color: AppTheme.accentGreen.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TARGET_FINGERPRINT_ID', style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                        const Icon(Icons.verified_user, color: AppTheme.accentGreen, size: 14),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('8f:2a:9c:11:e4:5d:0b:33:f9:a1:7c:22', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'IBM Plex Mono', letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text('CHECKSUM: OK', style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.4), fontSize: 10)),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.terminalBg,
          border: Border(top: BorderSide(color: AppTheme.terminalBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                context.go('/chats');
              },
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen,
                  boxShadow: AppTheme.glowGreen,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fingerprint, color: AppTheme.terminalBg),
                    SizedBox(width: 12),
                    Text('[ EXECUTE VERIFICATION ]', style: TextStyle(color: AppTheme.terminalBg, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Secure connection required.\nSee Security_Policy.txt', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.accentGreen.withOpacity(0.4), fontSize: 10, letterSpacing: 2, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
