import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

export '../services/encryption_service.dart';
export '../services/websocket_service.dart';


// ----------------------------------------------------------------------
// Secure Storage Provider
// ----------------------------------------------------------------------
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
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

class AuthNotifier extends StateNotifier<AuthState> {
  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  AuthNotifier(this._storage, this._auth) : super(const AuthState());

  Future<void> checkBiometric() async {
    state = state.copyWith(status: AuthStatus.authenticating);
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Device does not support biometric authentication.',
        );
        return;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to access Chimera Secure Terminal',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true, // Use biometric authentication if available
        ),
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
    // We can clear stored session or encryption keys here via _storage
    // await _storage.deleteAll();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// ----------------------------------------------------------------------
// Auth Provider
// ----------------------------------------------------------------------
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final localAuth = ref.watch(localAuthProvider);
  return AuthNotifier(storage, localAuth);
});
