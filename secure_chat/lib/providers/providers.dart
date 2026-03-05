import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../models/proxy_config.dart';
import '../services/audit_database_service.dart';
import '../services/audit_log_service.dart';
import '../services/chat_database_service.dart';
import '../services/encryption_service.dart';
import '../services/ephemeral_cleanup_service.dart';
import '../services/handshake_repository.dart';
import '../services/network_proxy_service.dart';
import '../services/pin_service.dart';
import '../services/rasp_service.dart';
import '../services/secure_document_service.dart';
import '../services/self_destruct_service.dart';
import '../services/ssl_pinning_service.dart';
import '../services/x3dh_service.dart';

export '../models/chat_session.dart';
export '../models/message.dart';
export '../models/proxy_config.dart';

export '../services/chat_database_service.dart';
export '../services/encryption_service.dart';
export '../services/handshake_repository.dart';
export '../services/network_proxy_service.dart';
export '../services/offline_queue_service.dart';
export '../services/pfs_session_service.dart';
export '../services/pin_service.dart';
export '../services/rasp_service.dart';
export '../services/self_destruct_service.dart';
export '../services/ssl_pinning_service.dart';
export '../services/websocket_service.dart';
export '../services/access_control_service.dart';
export '../services/x3dh_service.dart';

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

final pinServiceProvider = Provider<PinService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return PinService(storage);
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
    ref.invalidate(chatDatabaseProvider);
    ref.invalidate(vaultModeProvider);
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
    ref.read(auditLogServiceProvider).logEvent('PROXY_CONFIG_CHANGED', 'User updated proxy settings to type ${config.type.name}');
  }

  Future<void> clear() async {
    state = ProxyConfig.direct;
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _key);
    ref.read(auditLogServiceProvider).logEvent('PROXY_CONFIG_CLEARED', 'User cleared proxy settings');
  }
}

final proxyConfigProvider =
    NotifierProvider<ProxyConfigNotifier, ProxyConfig>(
  ProxyConfigNotifier.new,
);

final securityThreatProvider =
    NotifierProvider<SecurityThreatNotifier, SecurityThreatState>(
  SecurityThreatNotifier.new,
);

final networkProxyServiceProvider = Provider<NetworkProxyService>((ref) {
  final auditService = ref.watch(auditLogServiceProvider);
  return NetworkProxyService(auditService);
});

/// SSL Certificate Pinning service — mencegah serangan MITM pada WSS.
/// Default: PERMISSIVE (dev). Ganti ke STRICT saat distribusi production.
final sslPinningServiceProvider = Provider<SslPinningService>((ref) {
  return SslPinningService(
    // PRODUCTION: ganti ke SslPinningMode.strict dan isi kPinnedCertFingerprints
    mode: SslPinningMode.permissive,
  );
});


final raspServiceProvider = Provider<RaspService>((ref) {
  final notif = ref.watch(securityThreatProvider.notifier);
  final auditService = ref.watch(auditLogServiceProvider);
  return RaspService(notif, auditService);
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return EncryptionService(secureStorage);
});


// ----------------------------------------------------------------------
// Vault Mode Provider (Plausible Deniability Architecture)
// ----------------------------------------------------------------------
enum VaultMode { real, decoy }

class VaultModeNotifier extends Notifier<VaultMode> {
  @override
  VaultMode build() => VaultMode.real;
  
  void setMode(VaultMode mode) => state = mode;
}

final vaultModeProvider = NotifierProvider<VaultModeNotifier, VaultMode>(VaultModeNotifier.new);

final chatDatabaseServiceProvider = Provider<ChatDatabaseService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final vaultMode = ref.watch(vaultModeProvider);
  return ChatDatabaseService(secureStorage, vaultMode);
});

final auditDatabaseServiceProvider = Provider<AuditDatabaseService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return AuditDatabaseService(secureStorage);
});

final auditLogServiceProvider = Provider<AuditLogService>((ref) {
  final auditDbService = ref.read(auditDatabaseServiceProvider);
  final vaultMode = ref.watch(vaultModeProvider);
  return AuditLogService(auditDbService, vaultMode);
});

// ----------------------------------------------------------------------
// User Identity Provider (Phase 6 DLP Mock)
// ----------------------------------------------------------------------
class UserIdentity {
  final String id;
  final String email;

  const UserIdentity({required this.id, required this.email});
}

final currentUserIdentityProvider = Provider<UserIdentity>((ref) {
  // Data mock identitas pengguna yang sedang melakukan pembacaan dokumen
  return const UserIdentity(id: 'CHMR-992', email: 'agent01@instansi.gov');
});

final selfDestructServiceProvider = Provider<SelfDestructService>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final dbService = ref.watch(chatDatabaseServiceProvider);
  final auditService = ref.watch(auditLogServiceProvider);
  return SelfDestructService(secureStorage, dbService, auditService);
});

final websocketConfigProvider = Provider<String>((ref) {
  // Misalnya dari SecureStorage / env
  return "ws://127.0.0.1:8080/ws"; 
});

final secureDocumentServiceProvider = Provider<SecureDocumentService>((ref) {
  final auditService = ref.watch(auditLogServiceProvider);
  return SecureDocumentService(auditService);
});

final ephemeralCleanupServiceProvider = Provider<EphemeralCleanupService>((ref) {
  final dbService = ref.read(chatDatabaseServiceProvider);
  final auditLogService = ref.read(auditLogServiceProvider);
  
  return EphemeralCleanupService(dbService, auditLogService);
});

// ----------------------------------------------------------------------
// Phase 8: X3DH Handshake Providers
// ----------------------------------------------------------------------

/// Repository untuk operasi prekey (mockable server layer).
final handshakeRepositoryProvider = Provider<HandshakeRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return HandshakeRepository(storage);
});

/// Service X3DH: generate/publish prekeys, initiate/complete handshake.
final x3dhServiceProvider = Provider<X3dhService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final repository = ref.watch(handshakeRepositoryProvider);
  return X3dhService(storage, repository);
});

