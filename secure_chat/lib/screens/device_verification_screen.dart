import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../providers/providers.dart';

class DeviceVerificationScreen extends ConsumerStatefulWidget {
  const DeviceVerificationScreen({super.key});

  @override
  ConsumerState<DeviceVerificationScreen> createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends ConsumerState<DeviceVerificationScreen> {
  final List<String> _logs = [];
  int _progress = 0;
  String _targetFingerprint = 'UNKNOWN';
  Timer? _timer;

  final List<String> _handshakeSteps = [
    'Initializing secure protocol...',
    'Generating 4096-bit RSA keys...',
    'Exchanging public keys with host...',
    'Verifying payload signature...',
    'Validating hardware checksum...',
    'Establishing encrypted tunnel...',
    'Zero-trust verification complete.',
  ];

  @override
  void initState() {
    super.initState();
    _startHandshake();
  }

  void _startHandshake() {
    int step = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (step < _handshakeSteps.length) {
        setState(() {
          _logs.add('[\$] ${_handshakeSteps[step]}');
          _progress = ((step + 1) / _handshakeSteps.length * 100).toInt();
          
          if(step == 4) {
             _targetFingerprint = '8f:2a:9c:11:e4:5d:0b:33:f9:a1:7c:22';
          }
        });
        step++;
      } else {
        timer.cancel();
        // Give it a brief moment before navigating
        Future.delayed(const Duration(milliseconds: 800), () async {
          if (!mounted) return;
          
          try {
            // Context-Aware Access Validation (Geofencing & Time)
            await ref.read(accessControlServiceProvider).verifyAccess();
            
            if (mounted) {
              context.go('/chats');
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: AppTheme.warningRed,
                  duration: const Duration(seconds: 5),
                ),
              );
              // Forbid access, route back to login
              context.go('/auth');
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
                    Container(width: 8, height: 8, color: _progress < 100 ? AppTheme.accentGreen : Colors.greenAccent), // Pulse
                    const SizedBox(width: 12),
                    Text(
                      _progress < 100 ? '>> STATUS: ENCRYPTING_HANDSHAKE_' : '>> STATUS: TUNNEL_SECURED_', 
                      style: const TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)
                    ),
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
                  border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.4)),
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
                    Center(
                      child: Icon(
                        _progress < 100 ? Icons.sync_lock : Icons.lock_outline, 
                        color: AppTheme.accentGreen, 
                        size: 60
                      ),
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
                      children: List.generate(10, (index) {
                        bool isActive = index < (_progress / 10).floor();
                        return Expanded(
                          child: Container(
                            height: 8,
                            margin: EdgeInsets.only(right: index == 9 ? 0 : 4),
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.accentGreen : AppTheme.accentGreen.withValues(alpha: 0.2),
                              boxShadow: isActive ? AppTheme.glowGreen : null,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Handshake', style: TextStyle(color: AppTheme.accentGreen.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                        Text('$_progress%', style: TextStyle(color: AppTheme.accentGreen.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Terminal Logs
              Container(
                width: double.infinity,
                height: 180,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border.all(color: AppTheme.terminalBorder),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Text(
                        _logs[index],
                        style: const TextStyle(
                          color: AppTheme.terminalText,
                          fontSize: 10,
                          fontFamily: 'IBM Plex Mono',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Target Fingerprint
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.terminalCard,
                  border: Border.all(color: _targetFingerprint == 'UNKNOWN' ? AppTheme.terminalBorder : AppTheme.accentGreen.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TARGET_FINGERPRINT_ID', style: TextStyle(color: AppTheme.accentGreen.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                        Icon(Icons.verified_user, color: _targetFingerprint == 'UNKNOWN' ? Colors.grey : AppTheme.accentGreen, size: 14),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_targetFingerprint, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'IBM Plex Mono', letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(_targetFingerprint == 'UNKNOWN' ? 'AWAITING BIND...' : 'CHECKSUM: OK', style: TextStyle(color: AppTheme.accentGreen.withValues(alpha: 0.4), fontSize: 10)),
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
            Opacity(
              opacity: _progress < 100 ? 0.5 : 1.0,
              child: InkWell(
                onTap: () {
                  if (_progress >= 100) context.go('/chats');
                },
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen,
                    boxShadow: _progress < 100 ? null : AppTheme.glowGreen,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_progress < 100 ? Icons.hourglass_empty : Icons.login, color: AppTheme.terminalBg),
                      const SizedBox(width: 12),
                      Text(
                        _progress < 100 ? '[ PROCESSING... ]' : '[ ENTER CHATS ]', 
                        style: const TextStyle(color: AppTheme.terminalBg, fontSize: 16, fontWeight: FontWeight.bold)
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Zero-Trust Architecture Protocol\nDo not close the app during handshake', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.accentGreen.withValues(alpha: 0.4), fontSize: 10, letterSpacing: 2, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
