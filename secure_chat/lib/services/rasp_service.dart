// lib/services/rasp_service.dart
//
// Runtime Application Self-Protection (RASP) Service untuk Chimera.
//
// Menggunakan freeRASP SDK v7.5.0 dengan API yang benar:
//   - Talsec.instance.start(config)         — mulai RASP
//   - Talsec.instance.attachListener(cb)    — pasang threat callback
//   - Talsec.instance.attachExecutionStateListener(cb) — callback selesai cek
//
// Ancaman yang Dideteksi:
//   ═══════════════════════════════════════════════════════════════
//   🔴 KRITIKAL (langsung wipe & blokir):
//      - Root / Jailbreak / Privileged Access
//      - Hooking framework (Frida, Xposed, Shadow)
//      - Debugger aktif
//      - Tamper / App Integrity violation (APK dimodifikasi)
//      - Emulator / Simulator
//      - Dev Mode / ADB aktif
//
//   🟡 PERINGATAN (log, tidak blokir):
//      - Passcode tidak diset
//      - Unofficial store
//      - Device binding issue
//      - Secure hardware tidak tersedia
//   ═══════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freerasp/freerasp.dart';

import 'audit_log_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enum dan Data Class untuk ancaman
// ─────────────────────────────────────────────────────────────────────────────

enum ThreatSeverity { critical, warning }

class ThreatType {
  static const remoteKillSwitch = 'REMOTE_KILL_SWITCH';
}

class DetectedThreat {
  final String name;
  final String description;
  final ThreatSeverity severity;
  final DateTime detectedAt;

  const DetectedThreat({
    required this.name,
    required this.description,
    required this.severity,
    required this.detectedAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class SecurityThreatState {
  final DetectedThreat? activeCriticalThreat;
  final List<DetectedThreat> threatLog;
  final bool initialCheckDone;

  const SecurityThreatState({
    this.activeCriticalThreat,
    this.threatLog = const [],
    this.initialCheckDone = false,
  });

  bool get hasCriticalThreat => activeCriticalThreat != null;

  SecurityThreatState copyWith({
    DetectedThreat? activeCriticalThreat,
    List<DetectedThreat>? threatLog,
    bool? initialCheckDone,
  }) {
    return SecurityThreatState(
      activeCriticalThreat: activeCriticalThreat ?? this.activeCriticalThreat,
      threatLog: threatLog ?? this.threatLog,
      initialCheckDone: initialCheckDone ?? this.initialCheckDone,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class SecurityThreatNotifier extends Notifier<SecurityThreatState> {
  @override
  SecurityThreatState build() => const SecurityThreatState();

  void reportCriticalThreat(DetectedThreat threat) {
    state = state.copyWith(
      activeCriticalThreat: threat,
      threatLog: [...state.threatLog, threat],
    );
  }

  void reportWarning(DetectedThreat threat) {
    state = state.copyWith(
      threatLog: [...state.threatLog, threat],
    );
  }

  void reportThreat(String threatName) {
    if (threatName == ThreatType.remoteKillSwitch) {
       reportCriticalThreat(DetectedThreat(
         name: ThreatType.remoteKillSwitch,
         description: 'Admin triggered Remote Kill Switch Protocol. Device wiped.',
         severity: ThreatSeverity.critical,
         detectedAt: DateTime.now()
       ));
    }
  }

  void markInitialCheckDone() {
    state = state.copyWith(initialCheckDone: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RaspService
// ─────────────────────────────────────────────────────────────────────────────

class RaspService {
  final SecurityThreatNotifier _threatNotifier;
  final AuditLogService _auditLogService;

  RaspService(this._threatNotifier, this._auditLogService);

  /// Inisialisasi freeRASP SDK dan pasang listener untuk semua jenis ancaman.
  ///
  /// WAJIB dipanggil setelah [WidgetsFlutterBinding.ensureInitialized()]
  /// dan sebelum [runApp()].
  Future<void> initialize() async {
    // ── Konfigurasi ──────────────────────────────────────────────────────────
    // CATATAN PRODUCTION:
    //   - Isi signingCertHashes dengan SHA-256 Base64 dari signing certificate.
    //   - Set isProd = true sebelum submit ke app store.
    //   - Ganti watcherMail dengan email nyata.
    // ────────────────────────────────────────────────────────────────────────
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: 'com.example.secure_chat',
        signingCertHashes: const [
          // TODO: Ganti dengan hash sertifikat APK rilis (SHA-256 base64)
          // Cara mendapat hash: docs.talsec.app/freerasp/wiki/getting-signing-certificate-hash
          'DUMMY_CERT_HASH_BASE64_FOR_NOW_REPLACE_ME=',
        ],
        supportedStores: const [],
      ),
      watcherMail: 'security@chimera.app',
      isProd: false, // ⚠️ Ganti ke true sebelum production release
    );

    // ── ThreatCallback — API v7.5.0 ──────────────────────────────────────────
    // Nama callback BERBEDA dari versi lama. Gunakan source code sebagai acuan.
    final callback = ThreatCallback(
      // ── KRITIKAL ─────────────────────────────────────────────────────────

      onPrivilegedAccess: () => _critical(
        'ROOT_JAILBREAK',
        'Elevated privilege (root/jailbreak) terdeteksi. Lingkungan tidak aman.',
      ),

      onDebug: () => _critical(
        'DEBUGGER_ATTACHED',
        'Debugger aktif terdeteksi. Sesi dibatalkan paksa.',
      ),

      onHooks: () => _critical(
        'HOOK_FRAMEWORK',
        'Framework hooking (Frida/Xposed/Shadow) terdeteksi.',
      ),

      onAppIntegrity: () => _critical(
        'INTEGRITY_VIOLATION',
        'Integritas APK dikompromikan (signature/hash mismatch).',
      ),

      onSimulator: () => _critical(
        'EMULATOR_DETECTED',
        'Emulator atau simulator terdeteksi. Akses ditolak.',
      ),

      onDevMode: () => _critical(
        'DEVELOPER_MODE',
        'Developer Mode aktif. Tidak diizinkan untuk app ini.',
      ),

      onADBEnabled: () => _critical(
        'ADB_ENABLED',
        'Android Debug Bridge (ADB) aktif. Potensi exfiltration data.',
      ),

      onDeviceBinding: () => _critical(
        'DEVICE_BINDING',
        'Binding perangkat telah dikompromikan atau diubah.',
      ),

      // ── PERINGATAN ────────────────────────────────────────────────────────

      onPasscode: () => _warning(
        'PASSCODE_NOT_SET',
        'Perangkat tidak memiliki kunci layar (PIN/Pattern/Biometric).',
      ),

      onUnofficialStore: () => _warning(
        'UNOFFICIAL_STORE',
        'Aplikasi diinstal dari sumber tidak resmi.',
      ),

      onSecureHardwareNotAvailable: () => _warning(
        'SECURE_HARDWARE_UNAVAILABLE',
        'Hardware keamanan (StrongBox/TEE) tidak tersedia di perangkat ini.',
      ),

      onSystemVPN: () => _warning(
        'SYSTEM_VPN_ACTIVE',
        'VPN sistem aktif terdeteksi.',
      ),

      onObfuscationIssues: () => _warning(
        'OBFUSCATION_ISSUES',
        'Kode aplikasi belum terobfuskasi dengan benar.',
      ),
    );

    // ── Pasang listener ───────────────────────────────────────────────────────
    // attachListener HARUS dipanggil sebelum start() agar tidak ada
    // ancaman yang terlewat pada pengecekan awal.
    await Talsec.instance.attachListener(callback);

    // Pasang listener untuk event "semua pengecekan awal selesai"
    await Talsec.instance.attachExecutionStateListener(
      RaspExecutionStateCallback(
        onAllChecksDone: () {
          _threatNotifier.markInitialCheckDone();
        },
      ),
    );

    // ── Start RASP ────────────────────────────────────────────────────────────
    await Talsec.instance.start(config);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _critical(String name, String description) {
    _auditLogService.logEvent('RASP_CRITICAL_THREAT', '$name: $description');
    _threatNotifier.reportCriticalThreat(
      DetectedThreat(
        name: name,
        description: description,
        severity: ThreatSeverity.critical,
        detectedAt: DateTime.now(),
      ),
    );
  }

  void _warning(String name, String description) {
    _auditLogService.logEvent('RASP_WARNING_THREAT', '$name: $description');
    _threatNotifier.reportWarning(
      DetectedThreat(
        name: name,
        description: description,
        severity: ThreatSeverity.warning,
        detectedAt: DateTime.now(),
      ),
    );
  }

}
