import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../models/proxy_config.dart';

export '../models/proxy_config.dart';
export '../services/chat_database_service.dart';
export '../services/encryption_service.dart';
export '../services/network_proxy_service.dart';
export '../services/offline_queue_service.dart';
export '../services/pfs_session_service.dart';
export '../services/rasp_service.dart';
export '../services/websocket_service.dart';


// ----------------------------------------------------------------------
// Secure Storage Provider
// ----------------------------------------------------------------------
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
});

// ----------------------------------------------------------------------
// Local Auth Provider
// ----------------------------------------------------------------------
final localAuthProvider = Provider<LocalAuthentication>((ref) {
  return LocalAuthentication();
});

// ----------------------------------------------------------------------
// Auth State Notifier
// ----------------------------------------------------------------------
enum AuthStatus { initial, authenticating, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;

  const AuthState({this.status = AuthStatus.initial, this.errorMessage});

  AuthState copyWith({AuthStatus? status, String? errorMessage}) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState();
  }

  Future<void> checkBiometric() async {
    state = state.copyWith(status: AuthStatus.authenticating);
    try {
      final auth = ref.read(localAuthProvider);
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Device does not support biometric authentication.',
        );
        return;
      }

      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to access Chimera Secure Terminal',
      );

      if (didAuthenticate) {
        state = state.copyWith(status: AuthStatus.authenticated, errorMessage: null);
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated, errorMessage: 'Authentication failed');
      }
    } catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.deleteAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// ----------------------------------------------------------------------
// Auth Provider
// ----------------------------------------------------------------------
final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ----------------------------------------------------------------------
// Proxy Config Provider
// Manages ProxyConfig state and persists it to encrypted secure storage.
// ----------------------------------------------------------------------
class ProxyConfigNotifier extends Notifier<ProxyConfig> {
  static const _key = 'chimera_proxy_config';

  @override
  ProxyConfig build() {
    // Load from storage asynchronously after first build
    Future.microtask(load);
    return ProxyConfig.direct;
  }

  Future<void> load() async {
    final storage = ref.read(secureStorageProvider);
    final json = await storage.read(key: _key);
    if (json != null) {
      state = ProxyConfig.fromJsonString(json);
    }
  }

  Future<void> save(ProxyConfig config) async {
    state = config;
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _key, value: config.toJsonString());
  }

  Future<void> clear() async {
    state = ProxyConfig.direct;
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _key);
  }
}

final proxyConfigProvider =
    NotifierProvider<ProxyConfigNotifier, ProxyConfig>(
  ProxyConfigNotifier.new,
);
