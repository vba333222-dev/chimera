// lib/main.dart
//
// Entry point Chimera Secure Terminal.
//
// Urutan inisialisasi yang KRITIS (urutan ini tidak boleh diubah):
//   1. WidgetsFlutterBinding.ensureInitialized() — wajib sebelum Talsec
//   2. ProviderContainer dibuat lebih awal (sebelum runApp) untuk
//      mengakses SecurityThreatNotifier dari RaspService
//   3. RaspService.initialize() — freeRASP mulai memantau ancaman
//   4. runApp() dengan ProviderScope yang memakai container yang sudah ada

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/providers.dart';
import 'screens/biometric_login_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_room_screen.dart';
import 'screens/device_verification_screen.dart';
import 'screens/pin_setup_screen.dart';
import 'screens/secure_document_viewer_screen.dart';
import 'screens/security_lockdown_screen.dart';
import 'screens/audit_log_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/pixel_grid_background.dart';
import 'widgets/scanline_overlay.dart';

void main() async {
  // WAJIB: Inisialisasi binding Flutter sebelum memanggil Talsec
  WidgetsFlutterBinding.ensureInitialized();

  // Buat ProviderContainer lebih awal agar RaspService bisa mengakses
  // SecurityThreatNotifier (Riverpod provider) sebelum runApp()
  final container = ProviderContainer();

  // Inisialisasi RASP sebelum apapun ditampilkan ke user
  final raspService = RaspService(
    container.read(securityThreatProvider.notifier),
    container.read(auditLogServiceProvider),
  );
  await raspService.initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SecureChatApp(),
    ),
  );
}

class SecureChatApp extends ConsumerStatefulWidget {
  const SecureChatApp({super.key});

  @override
  ConsumerState<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends ConsumerState<SecureChatApp>
    with WidgetsBindingObserver {
  DateTime? _pausedTime;
  final int _timeoutSeconds = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Jalankan background worker pembersihan pesan otomatis
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ephemeralCleanupServiceProvider).startSweeping();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Hentikan background worker
    ref.read(ephemeralCleanupServiceProvider).stopSweeping();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedTime ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final backgroundDuration = DateTime.now().difference(_pausedTime!);
        if (backgroundDuration.inSeconds >= _timeoutSeconds) {
          // Kunci app jika sudah di-background lebih dari 30 detik
          _router.go('/login');
        }
      }
      _pausedTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── RASP Guard ──────────────────────────────────────────────────────────
    // Pantau SecurityThreatState secara reaktif.
    // Jika ada ancaman kritikal, SELURUH app tree diganti dengan LockdownScreen.
    // Tidak ada cara untuk widget lain di-render sampai app di-restart.
    final threatState = ref.watch(securityThreatProvider);

    if (threatState.hasCriticalThreat) {
      // Tampilkan lockdown screen langsung, membungkus theme agar tetap
      // terlihat konsisten (background hitam dengan overlay merah)
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: SecurityLockdownScreen(
          threat: threatState.activeCriticalThreat!,
        ),
      );
    }
    // ── Normal App Flow ─────────────────────────────────────────────────────

    return MaterialApp.router(
      title: 'Secure Terminal Chat',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      builder: (context, child) {
        return PixelGridBackground(
          child: ScanlineOverlay(
            child: child ?? const SizedBox(),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Router
// ─────────────────────────────────────────────────────────────────────────────

final GoRouter _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const BiometricLoginScreen(),
    ),
    GoRoute(
      path: '/pin-setup',
      builder: (context, state) => const PinSetupScreen(),
    ),
    GoRoute(
      path: '/device-verify',
      builder: (context, state) => const DeviceVerificationScreen(),
    ),
    GoRoute(
      path: '/audit',
      builder: (context, state) => const AuditLogScreen(),
    ),
    GoRoute(
      path: '/chats',
      builder: (context, state) => const ChatListScreen(),
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'] ?? 'Unknown';
        final title = state.uri.queryParameters['title'] ?? 'Sec_Channel';
        return ChatRoomScreen(chatId: id, chatTitle: title);
      },
    ),
    GoRoute(
      path: '/viewer',
      builder: (context, state) {
        final isPdf = state.uri.queryParameters['isPdf'] == 'true';
        final memoryBytes = state.extra as Uint8List?;
        
        if (memoryBytes == null) {
          return const Scaffold(body: Center(child: Text('NO DATA', style: TextStyle(color: Colors.red))));
        }

        return SecureDocumentViewerScreen(
          memoryBytes: memoryBytes,
          isPdf: isPdf,
        );
      },
    ),
  ],
);
