// lib/services/encryption_service.dart
//
// Versi yang telah dioptimasi dengan Dart Isolates untuk Fase 3.
// Semua operasi kriptografi berat dipindahkan ke Worker Isolate
// menggunakan Isolate.run() agar UI thread (termasuk efek CRT/Scanline)
// tetap smooth tanpa lag.

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../providers/providers.dart';
import 'crypto_isolate_tasks.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EncryptionService
// ─────────────────────────────────────────────────────────────────────────────

class EncryptionService {
  final FlutterSecureStorage _storage;

  static const String _privateKeyStorageKey = 'chimera_private_key_x25519';
  static const String _publicKeyStorageKey = 'chimera_public_key_x25519';

  EncryptionService(this._storage);

  // ───────────────────────────────────────────────────────────────────────────
  // Key Management (Storage tetap di Main Isolate — FlutterSecureStorage
  // tidak bisa digunakan di Worker Isolate karena membutuhkan Android context)
  // ───────────────────────────────────────────────────────────────────────────

  /// Membuat X25519 KeyPair baru menggunakan Worker Isolate.
  ///
  /// [Isolate.run()] akan spawn isolate baru, menjalankan [generateKeyPairInIsolate],
  /// mengembalikan hasilnya ke main isolate, lalu isolate tersebut langsung
  /// dibuang (tidak ada overhead persistent isolate).
  Future<SimpleKeyPair> generateKeyPair() async {
    // ✅ OPERASI BERAT → Worker Isolate
    final keyBytes = await Isolate.run(generateKeyPairInIsolate);

    // ✅ STORAGE → Main Isolate (memerlukan Flutter/Android context)
    await _storage.write(
      key: _privateKeyStorageKey,
      value: base64Encode(keyBytes.privateKeyBytes),
    );
    await _storage.write(
      key: _publicKeyStorageKey,
      value: base64Encode(keyBytes.publicKeyBytes),
    );

    // Rekonstruksi SimpleKeyPair dari raw bytes
    return _reconstructKeyPair(keyBytes.privateKeyBytes, keyBytes.publicKeyBytes);
  }

  /// Mengambil KeyPair yang tersimpan dari secure storage.
  Future<SimpleKeyPair?> getLocalKeyPair() async {
    final privKeyB64 = await _storage.read(key: _privateKeyStorageKey);
    final pubKeyB64 = await _storage.read(key: _publicKeyStorageKey);

    if (privKeyB64 == null || pubKeyB64 == null) return null;

    try {
      final privateKeyBytes = base64Decode(privKeyB64);
      final publicKeyBytes = base64Decode(pubKeyB64);
      return _reconstructKeyPair(privateKeyBytes, publicKeyBytes);
    } catch (_) {
      // Jika ada error parsing, paksa regenerasi
      return null;
    }
  }

  /// Mengambil KeyPair yang ada, atau membuat yang baru jika belum ada.
  Future<SimpleKeyPair> getOrGenerateKeyPair() async {
    return await getLocalKeyPair() ?? await generateKeyPair();
  }

  /// Menghapus semua kunci kriptografi dari storage.
  /// Dipanggil saat logout atau threat detection.
  Future<void> clearKeys() async {
    await Future.wait([
      _storage.delete(key: _privateKeyStorageKey),
      _storage.delete(key: _publicKeyStorageKey),
    ]);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ECDH Key Agreement (Worker Isolate)
  // ───────────────────────────────────────────────────────────────────────────

  /// Menghitung shared secret dari private key lokal dan public key peer
  /// menggunakan X25519 ECDH, berjalan di Worker Isolate.
  ///
  /// [peerPublicKeyBytes] adalah public key milik lawan bicara,
  /// biasanya diterima via WebSocket/server.
  Future<Uint8List> computeSharedSecret({
    required SimpleKeyPair localKeyPair,
    required Uint8List peerPublicKeyBytes,
  }) async {
    final privateKeyBytes = await localKeyPair.extractPrivateKeyBytes();

    // ✅ OPERASI BERAT → Worker Isolate
    return await Isolate.run(
      () => computeSharedSecretInIsolate(
        localPrivateKeyBytes: Uint8List.fromList(privateKeyBytes),
        remotePeerPublicKeyBytes: peerPublicKeyBytes,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Enkripsi / Dekripsi (Worker Isolate)
  // ───────────────────────────────────────────────────────────────────────────

  /// Mengenkripsi pesan plaintext menggunakan AES-256-GCM + HKDF,
  /// berjalan di Worker Isolate.
  ///
  /// Mengembalikan [Uint8List] yang berisi nonce + mac + ciphertext
  /// dalam format yang didefinisikan di [EncryptResult.toBytes()].
  Future<Uint8List> encryptMessage({
    required String plaintext,
    required Uint8List sharedSecretBytes,
  }) async {
    final payload = EncryptPayload(
      plaintext: plaintext,
      sharedSecretBytes: sharedSecretBytes,
    );

    // ✅ OPERASI BERAT → Worker Isolate
    final result = await Isolate.run(
      () => encryptMessageInIsolate(payload),
    );

    return result.toBytes();
  }

  /// Mendekripsi pesan yang terenkripsi menggunakan AES-256-GCM + HKDF,
  /// berjalan di Worker Isolate.
  ///
  /// [encryptedBytes] harus dalam format yang diproduksi oleh [encryptMessage].
  Future<String> decryptMessage({
    required Uint8List encryptedBytes,
    required Uint8List sharedSecretBytes,
  }) async {
    final payload = DecryptPayload(
      encryptedBytes: encryptedBytes,
      sharedSecretBytes: sharedSecretBytes,
    );

    // ✅ OPERASI BERAT → Worker Isolate
    return await Isolate.run(
      () => decryptMessageInIsolate(payload),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Private Helpers
  // ───────────────────────────────────────────────────────────────────────────

  /// Merekonstruksi [SimpleKeyPairData] dari raw bytes.
  SimpleKeyPair _reconstructKeyPair(
    List<int> privateKeyBytes,
    List<int> publicKeyBytes,
  ) {
    return SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk instance [EncryptionService].
final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return EncryptionService(storage);
});

/// [FutureProvider] untuk mengakses KeyPair secara asinkron.
/// Secara otomatis akan memuat dari storage atau generate baru jika belum ada.
///
/// Karena menggunakan [Isolate.run()] di balik layar, UI tidak akan freeze
/// meskipun key generation memakan waktu beberapa milidetik.
final keyPairProvider = FutureProvider<SimpleKeyPair>((ref) async {
  final service = ref.watch(encryptionServiceProvider);
  return service.getOrGenerateKeyPair();
});

/// Provider untuk mengakses bytes public key lokal (untuk dikirim ke peer).
/// Bergantung pada [keyPairProvider].
final localPublicKeyBytesProvider = FutureProvider<Uint8List>((ref) async {
  final keyPair = await ref.watch(keyPairProvider.future);
  final publicKey = await keyPair.extractPublicKey();
  return Uint8List.fromList(publicKey.bytes);
});
