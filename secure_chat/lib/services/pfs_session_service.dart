// lib/services/pfs_session_service.dart
//
// Perfect Forward Secrecy (PFS) Session Service untuk Chimera.
//
// Arsitektur:
//   • Setiap sesi chat memiliki objek [PfsSession] sendiri
//   • Tiap PfsSession menyimpan Map<epoch, sessionKey> di MEMORY SAJA
//   • Setiap N menit (kRotationInterval), ephemeral key baru dibuat,
//     session key baru diderivasi, dan session key lama dihapus
//   • Saat sesi berakhir (expireSession), semua kunci di-zero-wipe dari memory
//
// JAMINAN PFS:
//   Jika identity key peer bocor di masa depan:
//   → ephemeral private key sudah tidak ada di memory (dihapus setelah rotasi)
//   → session key TIDAK bisa diderivasi ulang (ECDH-nya sudah tidak mungkin)
//   → pesan-pesan dari epoch yang sudah lewat TIDAK bisa didekripsi

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crypto_isolate_tasks.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Konstanta konfigurasi PFS
// ─────────────────────────────────────────────────────────────────────────────

/// Interval rotasi session key secara otomatis.
/// Setiap epoch berlangsung selama durasi ini.
const Duration kPfsRotationInterval = Duration(minutes: 5);

/// Jumlah maksimum epoch lama yang disimpan di memory untuk dekripsi.
///
/// Nilai 5 berarti user bisa mendekripsi pesan dari 5 epoch terakhir (25 menit).
/// Setelah melewati batas ini, epoch paling lama akan di-wipe dari memory.
/// Trade-off: lebih besar = lebih banyak RAM, lebih kecil = pesan lama tidak bisa dibaca.
const int kMaxHistoryEpochs = 5;

// ─────────────────────────────────────────────────────────────────────────────
// PfsEpochKey — satu entri riwayat epoch
// ─────────────────────────────────────────────────────────────────────────────

class PfsEpochKey {
  final int epochIndex;
  final Uint8List sessionKeyBytes;
  final DateTime createdAt;

  PfsEpochKey({
    required this.epochIndex,
    required this.sessionKeyBytes,
    required this.createdAt,
  });

  /// Zero-wipe bytes sebelum dibuang — mencegah analisis memory forensik.
  void wipe() {
    // Isi dengan nol sebelum GC mengambil alih
    for (int i = 0; i < sessionKeyBytes.length; i++) {
      sessionKeyBytes[i] = 0;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PfsSession — state satu sesi chat
// ─────────────────────────────────────────────────────────────────────────────

class PfsSession {
  final String sessionId;
  final Uint8List peerIdentityPublicKeyBytes;

  int _currentEpoch = 0;
  int get currentEpoch => _currentEpoch;

  /// Riwayat session key per epoch.
  /// Key: epochIndex, Value: PfsEpochKey
  final Map<int, PfsEpochKey> _epochKeys = {};

  /// Timer rotasi otomatis
  Timer? _rotationTimer;

  /// Callback dipanggil saat rotasi berhasil (untuk logging/UI)
  final void Function(int newEpoch)? onRotation;

  PfsSession({
    required this.sessionId,
    required this.peerIdentityPublicKeyBytes,
    this.onRotation,
  });

  /// Ambil session key untuk epoch tertentu.
  /// Mengembalikan null jika epoch sudah di-wipe dari history.
  Uint8List? getKeyForEpoch(int epoch) => _epochKeys[epoch]?.sessionKeyBytes;

  /// Tambah session key untuk epoch baru dan mulai timer rotasi.
  void _setKeyForEpoch(int epoch, Uint8List keyBytes) {
    _epochKeys[epoch] = PfsEpochKey(
      epochIndex: epoch,
      sessionKeyBytes: keyBytes,
      createdAt: DateTime.now(),
    );
    _pruneOldEpochs();
  }

  /// Hapus epoch-epoch lama melebihi batas [kMaxHistoryEpochs].
  void _pruneOldEpochs() {
    if (_epochKeys.length <= kMaxHistoryEpochs) return;

    // Urutkan dan hapus epoch paling lama
    final sortedEpochs = _epochKeys.keys.toList()..sort();
    final toRemove = sortedEpochs.take(_epochKeys.length - kMaxHistoryEpochs);
    for (final epoch in toRemove) {
      _epochKeys[epoch]?.wipe();
      _epochKeys.remove(epoch);
      // ignore: avoid_print
      print('[PFS] Session $sessionId: epoch $epoch key wiped from memory (pruned)');
    }
  }

  /// Mulai timer rotasi otomatis.
  void startRotationTimer(Future<void> Function() rotateCallback) {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(kPfsRotationInterval, (_) async {
      await rotateCallback();
    });
  }

  /// Hentikan timer dan zero-wipe semua session key dari memory.
  void expire() {
    _rotationTimer?.cancel();
    _rotationTimer = null;

    for (final entry in _epochKeys.values) {
      entry.wipe();
    }
    _epochKeys.clear();

    // ignore: avoid_print
    print('[PFS] Session $sessionId: ALL epoch keys wiped (session expired)');
  }

  /// Setter untuk epoch baru (dipanggil oleh PfsSessionService saat rotasi)
  void _advanceEpoch(int newEpoch, Uint8List newKeyBytes) {
    // Wipe epoch sebelumnya jika sudah melebihi batas history
    _currentEpoch = newEpoch;
    _setKeyForEpoch(newEpoch, newKeyBytes);
    onRotation?.call(newEpoch);
    // ignore: avoid_print
    print('[PFS] Session $sessionId: rotating key epoch ${newEpoch - 1} → $newEpoch');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PfsEncryptedPacket — format wire untuk pesan terenkripsi
// ─────────────────────────────────────────────────────────────────────────────

/// Representasi pesan terenkripsi PFS yang siap dikirim via WebSocket.
///
/// Format JSON: `{"epoch": 3, "data": "<base64-EncryptResult.toBytes()>"}`
class PfsEncryptedPacket {
  final int epoch;
  final Uint8List ciphertextBytes;

  PfsEncryptedPacket({required this.epoch, required this.ciphertextBytes});

  /// Serialize ke JSON string untuk dikirim via WebSocket.
  String toJson() => jsonEncode({
        'epoch': epoch,
        'data': base64Encode(ciphertextBytes),
      });

  /// Deserialize dari JSON string yang diterima via WebSocket.
  static PfsEncryptedPacket? fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return PfsEncryptedPacket(
        epoch: map['epoch'] as int,
        ciphertextBytes: base64Decode(map['data'] as String),
      );
    } catch (_) {
      return null; // Bukan format PFS packet
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PfsSessionService
// ─────────────────────────────────────────────────────────────────────────────

class PfsSessionService {
  // Map dari sessionId → PfsSession (aktif di memory)
  final Map<String, PfsSession> _sessions = {};

  PfsSessionService();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Inisialisasi sesi PFS baru untuk sessionId tertentu.
  ///
  /// [sessionId] — ID unik sesi (biasanya chatId dari database)
  /// [peerIdentityPublicKeyBytes] — public key identitas peer (X25519, 32 bytes)
  ///
  /// Langkah:
  ///   1. Generate ephemeral X25519 keypair (epoch 0)
  ///   2. Derive session key dari ECDH(ephemeral_local, peer_identity)
  ///   3. Mulai timer rotasi otomatis (setiap kPfsRotationInterval)
  Future<void> initSession({
    required String sessionId,
    required Uint8List peerIdentityPublicKeyBytes,
  }) async {
    // Expire sesi lama jika ada
    expireSession(sessionId);

    final session = PfsSession(
      sessionId: sessionId,
      peerIdentityPublicKeyBytes: peerIdentityPublicKeyBytes,
    );
    _sessions[sessionId] = session;

    // Derive session key epoch 0
    await _deriveAndSetKey(session, epochIndex: 0);

    // Mulai timer rotasi otomatis
    session.startRotationTimer(() => rotateKey(sessionId));

    // ignore: avoid_print
    print('[PFS] Session $sessionId: initialized (epoch 0)');
  }

  /// Rotasi manual — generate ephemeral key baru dan derive session key baru.
  ///
  /// Dipanggil oleh timer otomatis atau bisa dipanggil manual
  /// (misalnya saat mendeteksi anomali jaringan).
  Future<void> rotateKey(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    final newEpoch = session.currentEpoch + 1;
    await _deriveAndSetKey(session, epochIndex: newEpoch);
  }

  /// Enkripsi plaintext menggunakan session key epoch saat ini.
  ///
  /// Packet ini dapat dikonversi ke JSON dengan `PfsEncryptedPacket.toJson()`.
  Future<PfsEncryptedPacket> encryptForSession(
    String sessionId,
    String plaintext,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError(
        '[PFS] Session $sessionId belum diinisialisasi. '
        'Panggil initSession() terlebih dahulu.',
      );
    }

    final currentEpoch = session.currentEpoch;
    final sessionKey = session.getKeyForEpoch(currentEpoch);
    if (sessionKey == null) {
      throw StateError(
        '[PFS] Session key untuk epoch $currentEpoch tidak ditemukan.',
      );
    }

    final payload = PfsEncryptPayload(
      plaintext: plaintext,
      sessionKeyBytes: sessionKey,
      epochIndex: currentEpoch,
    );

    // ✅ BERAT → Worker Isolate
    final result = await Isolate.run(() => pfsEncryptInIsolate(payload));

    return PfsEncryptedPacket(
      epoch: currentEpoch,
      ciphertextBytes: result.toBytes(),
    );
  }

  /// Dekripsi pesan dari [PfsEncryptedPacket] menggunakan session key epoch yg sesuai.
  ///
  /// Jika epoch dari packet sudah di-wipe dari history (melebihi kMaxHistoryEpochs),
  /// akan melempar [StateError] — pesan tersebut tidak bisa didekripsi lagi.
  Future<String> decryptFromPacket(
    String sessionId,
    PfsEncryptedPacket packet,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('[PFS] Session $sessionId tidak ditemukan.');
    }

    final sessionKey = session.getKeyForEpoch(packet.epoch);
    if (sessionKey == null) {
      throw StateError(
        '[PFS] Epoch ${packet.epoch} sudah di-wipe dari memory. '
        'Pesan ini tidak dapat didekripsi (ini adalah fitur PFS, bukan bug).',
      );
    }

    final payload = PfsDecryptPayload(
      encryptedBytes: packet.ciphertextBytes,
      sessionKeyBytes: sessionKey,
      epochIndex: packet.epoch,
    );

    // ✅ BERAT → Worker Isolate
    return await Isolate.run(() => pfsDecryptInIsolate(payload));
  }

  /// Hapus sesi dan zero-wipe semua session key dari memory.
  ///
  /// Dipanggil saat:
  ///   - User meninggalkan chat room (dispose)
  ///   - Logout
  ///   - RASP mendeteksi ancaman
  void expireSession(String sessionId) {
    final session = _sessions.remove(sessionId);
    session?.expire();
  }

  /// Hapus SEMUA sesi aktif (wipe total).
  ///
  /// Dipanggil oleh SecurityLockdownScreen saat threat kritikal terdeteksi.
  void expireAllSessions() {
    for (final session in _sessions.values) {
      session.expire();
    }
    _sessions.clear();
    // ignore: avoid_print
    print('[PFS] ALL sessions expired and wiped.');
  }

  /// Cek apakah sesi dengan sessionId sudah terinisialisasi.
  bool hasSession(String sessionId) => _sessions.containsKey(sessionId);

  /// Epoch aktif saat ini untuk sessionId tertentu. -1 jika sesi tidak ada.
  int currentEpoch(String sessionId) =>
      _sessions[sessionId]?.currentEpoch ?? -1;

  // ── Private ────────────────────────────────────────────────────────────────

  /// Generate ephemeral keypair baru dan derive session key untuk epochIndex.
  Future<void> _deriveAndSetKey(PfsSession session, {required int epochIndex}) async {
    // 1. Generate ephemeral keypair BARU di Worker Isolate
    //    (tidak disimpan ke disk — hanya ada di memory selama proses ini)
    final ephemeralKeyBytes = await Isolate.run(generateKeyPairInIsolate);

    // 2. Derive session key via ECDH(ephemeral_local, peer_identity) + HKDF
    final payload = DeriveSessionKeyPayload(
      ephemeralPrivateKeyBytes: ephemeralKeyBytes.privateKeyBytes,
      peerPublicKeyBytes: session.peerIdentityPublicKeyBytes,
      epochIndex: epochIndex,
    );
    final sessionKeyBytes = await Isolate.run(
      () => deriveSessionKeyInIsolate(payload),
    );

    // 3. Simpan session key ke map epoch (aman di memory, tidak ke disk)
    session._advanceEpoch(epochIndex, sessionKeyBytes);

    // 4. Zero-wipe ephemeral private key dari memory — setelah ini,
    //    session key TIDAK BISA diderivasi ulang (inilah PFS)
    for (int i = 0; i < ephemeralKeyBytes.privateKeyBytes.length; i++) {
      ephemeralKeyBytes.privateKeyBytes[i] = 0;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────

final pfsSessionServiceProvider = Provider<PfsSessionService>((ref) {
  final service = PfsSessionService();

  // Expire semua sesi saat provider di-dispose (logout/app restart)
  ref.onDispose(service.expireAllSessions);

  return service;
});
