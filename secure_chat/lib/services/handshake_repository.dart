// lib/services/handshake_repository.dart
//
// ─────────────────────────────────────────────────────────────────────────
// HandshakeRepository — Phase 8: Mockable Server Layer untuk X3DH Prekeys
// ─────────────────────────────────────────────────────────────────────────
//
// TUJUAN:
//   Mengabstraksi operasi server (publish & fetch prekey bundles) sehingga:
//   • Saat ini: disimulasikan menggunakan FlutterSecureStorage (lokal).
//   • Nanti:    swap implementasi dengan HTTP/REST call ke server instansi
//               tanpa perlu mengubah logika X3dhService sama sekali.
//
// PROTOCOL:
//   X3DH (Extended Triple Diffie-Hellman) membutuhkan setiap user untuk
//   mempublikasi "Prekey Bundle" berisi:
//     - IK  (Identity Key)     — persisten, diderivasi dari keypair utama
//     - SPK (Signed PreKey)    — dirotasi mingguan
//     - OPK (One-Time PreKey)  — satu kali pakai per sesi baru
//
// ─────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

/// Bundle prekey yang dipublikasikan pengguna ke "server".
/// Dalam implementasi nyata, ini dikirim via HTTP POST ke backend API.
class PreKeyBundle {
  /// User ID pemilik bundle ini.
  final String userId;

  /// Identity Key public bytes (X25519, 32 bytes) — persisten.
  final Uint8List identityKeyPublicBytes;

  /// Signed PreKey public bytes (X25519, 32 bytes) — dirotasi mingguan.
  final Uint8List signedPreKeyPublicBytes;

  /// Indeks Signed PreKey (untuk memilih SPK yang benar saat rotasi).
  final int signedPreKeyId;

  /// One-Time PreKey public bytes (X25519, 32 bytes) — dipakai sekali.
  /// Null jika server sudah kehabisan OPK untuk user ini.
  final Uint8List? oneTimePreKeyPublicBytes;

  /// Indeks One-Time PreKey yang diberikan.
  final int? oneTimePreKeyId;

  const PreKeyBundle({
    required this.userId,
    required this.identityKeyPublicBytes,
    required this.signedPreKeyPublicBytes,
    required this.signedPreKeyId,
    this.oneTimePreKeyPublicBytes,
    this.oneTimePreKeyId,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'ik': base64Encode(identityKeyPublicBytes),
        'spk': base64Encode(signedPreKeyPublicBytes),
        'spkId': signedPreKeyId,
        if (oneTimePreKeyPublicBytes != null)
          'opk': base64Encode(oneTimePreKeyPublicBytes!),
        if (oneTimePreKeyId != null) 'opkId': oneTimePreKeyId,
      };

  factory PreKeyBundle.fromJson(Map<String, dynamic> json) => PreKeyBundle(
        userId: json['userId'] as String,
        identityKeyPublicBytes: base64Decode(json['ik'] as String),
        signedPreKeyPublicBytes: base64Decode(json['spk'] as String),
        signedPreKeyId: json['spkId'] as int,
        oneTimePreKeyPublicBytes: json['opk'] != null
            ? base64Decode(json['opk'] as String)
            : null,
        oneTimePreKeyId: json['opkId'] as int?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// HandshakeRepository
// ─────────────────────────────────────────────────────────────────────────────

/// Repository untuk operasi prekey X3DH.
///
/// **Mock Implementation:** Menggunakan `FlutterSecureStorage` sebagai
/// pengganti server. Key storage: `chimera_prekey_<userId>`.
///
/// **Production Swap:** Ganti isi method `publishPreKeyBundle` dan
/// `fetchPreKeyBundle` dengan HTTP call ke endpoint instansi. Interface
/// tetap sama — tidak ada perubahan di X3dhService.
class HandshakeRepository {
  final FlutterSecureStorage _storage;

  static const String _storagePrefix = 'chimera_prekey_';

  const HandshakeRepository(this._storage);

  // ── Publish ───────────────────────────────────────────────────────────────

  /// Mempublikasikan prekey bundle milik [userId] ke server (atau mock storage).
  ///
  /// Dalam produksi: HTTP POST /api/prekeys dengan body `bundle.toJson()`.
  Future<void> publishPreKeyBundle(PreKeyBundle bundle) async {
    final jsonStr = jsonEncode(bundle.toJson());
    await _storage.write(
      key: '$_storagePrefix${bundle.userId}',
      value: jsonStr,
    );
    // [Phase B] Simulasi network latency (misal 500-800ms)
    await Future.delayed(const Duration(milliseconds: 800));
    // ignore: avoid_print
    print('[HandshakeRepo] Prekey bundle published for user: ${bundle.userId}');
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  /// Mengambil prekey bundle milik [userId] dari server (atau mock storage).
  ///
  /// Mengembalikan `null` jika user belum mempublikasikan bundle-nya.
  ///
  /// Dalam produksi: HTTP GET /api/prekeys/{userId}.
  Future<PreKeyBundle?> fetchPreKeyBundle(String userId) async {
    final jsonStr = await _storage.read(key: '$_storagePrefix$userId');
    if (jsonStr == null) return null;

    // [Phase B] Simulasi network latency (misal 500-800ms)
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return PreKeyBundle.fromJson(map);
    } catch (e) {
      // ignore: avoid_print
      print('[HandshakeRepo] Failed to parse prekey bundle for $userId: $e');
      return null;
    }
  }

  // ── Consume OPK ───────────────────────────────────────────────────────────

  /// Menghapus OPK yang sudah dipakai dari storage (simulasi server consume).
  ///
  /// Dalam produksi: server otomatis menandai OPK sebagai "consumed" saat
  /// bundle diberikan ke sender. Method ini hanya untuk mock local.
  Future<void> consumeOneTimePreKey(String userId) async {
    final bundle = await fetchPreKeyBundle(userId);
    if (bundle == null) return;

    // Buat ulang bundle tanpa OPK (sudah dikonsumsi)
    final updatedBundle = PreKeyBundle(
      userId: bundle.userId,
      identityKeyPublicBytes: bundle.identityKeyPublicBytes,
      signedPreKeyPublicBytes: bundle.signedPreKeyPublicBytes,
      signedPreKeyId: bundle.signedPreKeyId,
      // OPK tidak disertakan (sudah dikonsumsi)
    );
    await publishPreKeyBundle(updatedBundle);
    // ignore: avoid_print
    print('[HandshakeRepo] OPK consumed for user: $userId');
  }
}
