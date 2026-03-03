import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_room_screen.dart';
import 'screens/biometric_login_screen.dart';
import 'screens/device_verification_screen.dart';
import 'widgets/scanline_overlay.dart';
import 'widgets/pixel_grid_background.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: SecureChatApp()));
}

class SecureChatApp extends StatefulWidget {
  const SecureChatApp({super.key});

  @override
  State<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends State<SecureChatApp> with WidgetsBindingObserver {
  DateTime? _pausedTime;
  final int _timeoutSeconds = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pausedTime ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final backgroundDuration = DateTime.now().difference(_pausedTime!);
        if (backgroundDuration.inSeconds >= _timeoutSeconds) {
          // Lock the app if backgrounded for more than 30s
          _router.go('/login');
        }
      }
      _pausedTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
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

final GoRouter _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const BiometricLoginScreen(),
    ),
    GoRoute(
      path: '/device-verify',
      builder: (context, state) => const DeviceVerificationScreen(),
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
  ],
);
