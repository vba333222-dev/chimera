// lib/services/crypto_isolate_tasks.dart
//
// PENTING: File ini DIDESAIN agar bebas dari dependency Flutter apapun.
// Hanya menggunakan pure Dart + package:cryptography.
// Ini memungkinkan semua fungsi di sini bisa dipanggil via Isolate.run()
// dari main isolate tanpa konflik.

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data class untuk membawa hasil generate key (bytes only, bukan objek Flutter)
// ─────────────────────────────────────────────────────────────────────────────

/// Hasil dari operasi key generation yang bisa di-pass antar Isolate.
/// Menggunakan Uint8List (raw bytes) karena objek cryptography tidak
/// dapat di-serialize secara otomatis oleh Dart Isolate message passing.
class GeneratedKeyPairBytes {
  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;

  const GeneratedKeyPairBytes({
    required this.privateKeyBytes,
    required this.publicKeyBytes,
  });
}

/// Payload untuk operasi enkripsi yang dikirim ke Isolate.
class EncryptPayload {
  final String plaintext;
  final Uint8List sharedSecretBytes; // Derived dari ECDH

  const EncryptPayload({
    required this.plaintext,
    required this.sharedSecretBytes,
  });
}

/// Hasil dari operasi enkripsi.
class EncryptResult {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  const EncryptResult({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  /// Serialize seluruh hasil jadi satu Uint8List untuk transmisi/storage.
  /// Format: [nonceLen (2 bytes)] + [nonce] + [macLen (2 bytes)] + [mac] + [ciphertext]
  Uint8List toBytes() {
    final nonceLen = nonce.length;
    final macLen = mac.length;
    final result = BytesBuilder();

    result.addByte((nonceLen >> 8) & 0xFF);
    result.addByte(nonceLen & 0xFF);
    result.add(nonce);

    result.addByte((macLen >> 8) & 0xFF);
    result.addByte(macLen & 0xFF);
    result.add(mac);

    result.add(ciphertext);
    return result.toBytes();
  }

  /// Deserialize dari bytes yang diproduksi oleh [toBytes()].
  static EncryptResult fromBytes(Uint8List bytes) {
    int offset = 0;

    final nonceLen = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    final nonce = bytes.sublist(offset, offset + nonceLen);
    offset += nonceLen;

    final macLen = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    final mac = bytes.sublist(offset, offset + macLen);
    offset += macLen;

    final ciphertext = bytes.sublist(offset);

    return EncryptResult(nonce: nonce, ciphertext: ciphertext, mac: mac);
  }
}

/// Payload untuk operasi dekripsi.
class DecryptPayload {
  final Uint8List encryptedBytes; // Format dari EncryptResult.toBytes()
  final Uint8List sharedSecretBytes;

  const DecryptPayload({
    required this.encryptedBytes,
    required this.sharedSecretBytes,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Fungsi-fungsi kripto (berjalan di Worker Isolate)
// ─────────────────────────────────────────────────────────────────────────────

/// [ISOLATE TASK] Membuat X25519 KeyPair baru.
/// Mengembalikan raw bytes (Uint8List) agar bisa di-pass antar Isolate.
Future<GeneratedKeyPairBytes> generateKeyPairInIsolate() async {
  final algorithm = X25519();
  final keyPair = await algorithm.newKeyPair();

  final privateKeyBytes = Uint8List.fromList(
    await keyPair.extractPrivateKeyBytes(),
  );
  final publicKey = await keyPair.extractPublicKey();
  final publicKeyBytes = Uint8List.fromList(publicKey.bytes);

  return GeneratedKeyPairBytes(
    privateKeyBytes: privateKeyBytes,
    publicKeyBytes: publicKeyBytes,
  );
}

/// [ISOLATE TASK] Melakukan ECDH Key Agreement (X25519).
/// Mengambil private key user dan public key peer, menghasilkan shared secret.
Future<Uint8List> computeSharedSecretInIsolate({
  required Uint8List localPrivateKeyBytes,
  required Uint8List remotePeerPublicKeyBytes,
}) async {
  final algorithm = X25519();

  final localKeyPair = SimpleKeyPairData(
    localPrivateKeyBytes,
    publicKey: SimplePublicKey(
      // Rekonstruksi public key dari private key untuk X25519
      // X25519 public key bisa diderivasi, tapi kita butuh simpan public key local kita juga.
      // Untuk ECDH, kita hanya butuh private key local + public key peer.
      remotePeerPublicKeyBytes, // placeholder (tidak dipakai di ECDH)
      type: KeyPairType.x25519,
    ),
    type: KeyPairType.x25519,
  );

  final remotePublicKey = SimplePublicKey(
    remotePeerPublicKeyBytes,
    type: KeyPairType.x25519,
  );

  final sharedSecret = await algorithm.sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: remotePublicKey,
  );

  return Uint8List.fromList(await sharedSecret.extractBytes());
}

/// [ISOLATE TASK] Enkripsi pesan dengan AES-256-GCM menggunakan shared secret.
/// Mengambil [EncryptPayload] dan mengembalikan [EncryptResult].
Future<EncryptResult> encryptMessageInIsolate(EncryptPayload payload) async {
  final algorithm = AesGcm.with256bits();

  // Derive 256-bit key dari shared secret menggunakan HKDF
  final hkdf = Hkdf(
    hmac: Hmac(Sha256()),
    outputLength: 32,
  );
  final secretKey = await hkdf.deriveKey(
    secretKey: SecretKeyData(payload.sharedSecretBytes),
    info: List<int>.from('chimera-chat-v1'.codeUnits),
  );

  // Generate nonce acak (12 bytes untuk AES-GCM)
  final nonce = algorithm.newNonce();

  final secretBox = await algorithm.encrypt(
    List<int>.from(payload.plaintext.codeUnits),
    secretKey: secretKey,
    nonce: nonce,
  );

  return EncryptResult(
    nonce: Uint8List.fromList(secretBox.nonce),
    ciphertext: Uint8List.fromList(secretBox.cipherText),
    mac: Uint8List.fromList(secretBox.mac.bytes),
  );
}

/// [ISOLATE TASK] Dekripsi pesan dengan AES-256-GCM.
/// Mengambil [DecryptPayload] dan mengembalikan String plaintext.
Future<String> decryptMessageInIsolate(DecryptPayload payload) async {
  final algorithm = AesGcm.with256bits();

  final encryptResult = EncryptResult.fromBytes(payload.encryptedBytes);

  // Derive key yang sama dari shared secret menggunakan HKDF
  final hkdf = Hkdf(
    hmac: Hmac(Sha256()),
    outputLength: 32,
  );
  final secretKey = await hkdf.deriveKey(
    secretKey: SecretKeyData(payload.sharedSecretBytes),
    info: List<int>.from('chimera-chat-v1'.codeUnits),
  );

  final secretBox = SecretBox(
    encryptResult.ciphertext,
    nonce: encryptResult.nonce,
    mac: Mac(encryptResult.mac),
  );

  final decryptedBytes = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
  );

  return String.fromCharCodes(decryptedBytes);
}

// ─────────────────────────────────────────────────────────────────────────────
// PFS (Perfect Forward Secrecy) — Payload classes & Isolate tasks
//
// Berbeda dari enkripsi reguler di atas yang menggunakan identity keypair,
// PFS menggunakan EPHEMERAL keypair per-sesi/per-rotasi. Tiap epoch
// menghasilkan session key yang independen dan tidak bisa diderivasi ulang
// setelah private key ephemeral dihapus dari memory.
// ─────────────────────────────────────────────────────────────────────────────

/// Payload untuk derivasi session key PFS di Isolate.
///
/// [ephemeralPrivateKeyBytes] — private key ephemeral milik sender (32 bytes, X25519)
/// [peerPublicKeyBytes]      — public key identitas peer (32 bytes, X25519)
/// [epochIndex]              — nomor epoch saat ini (digunakan sebagai HKDF salt)
class DeriveSessionKeyPayload {
  final Uint8List ephemeralPrivateKeyBytes;
  final Uint8List peerPublicKeyBytes;
  final int epochIndex;

  const DeriveSessionKeyPayload({
    required this.ephemeralPrivateKeyBytes,
    required this.peerPublicKeyBytes,
    required this.epochIndex,
  });
}

/// Payload untuk enkripsi PFS di Isolate.
///
/// [plaintext]       — plaintext yang akan dienkripsi
/// [sessionKeyBytes] — session key untuk epoch ini (32 bytes)
/// [epochIndex]      — disertakan dalam HKDF context untuk domain separation
class PfsEncryptPayload {
  final String plaintext;
  final Uint8List sessionKeyBytes;
  final int epochIndex;

  const PfsEncryptPayload({
    required this.plaintext,
    required this.sessionKeyBytes,
    required this.epochIndex,
  });
}

/// Payload untuk dekripsi PFS di Isolate.
///
/// [encryptedBytes]  — output dari [pfsEncryptInIsolate] → [EncryptResult.toBytes()]
/// [sessionKeyBytes] — session key untuk epoch yang sama saat enkripsi
/// [epochIndex]      — harus sama dengan epoch saat enkripsi untuk HKDF context
class PfsDecryptPayload {
  final Uint8List encryptedBytes;
  final Uint8List sessionKeyBytes;
  final int epochIndex;

  const PfsDecryptPayload({
    required this.encryptedBytes,
    required this.sessionKeyBytes,
    required this.epochIndex,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PFS Isolate Functions
// ─────────────────────────────────────────────────────────────────────────────

/// [ISOLATE TASK] Derivasi session key PFS menggunakan ephemeral ECDH + HKDF.
///
/// Proses:
///   1. Rekonstruksi ephemeral KeyPair dari bytes
///   2. Rekonstruksi peer public key dari bytes
///   3. ECDH(ephemeral_local, peer_identity) → raw shared secret
///   4. HKDF dengan info='chimera-pfs-epoch-{N}' → 32-byte session key
///
/// Keunggulan PFS: setelah ephemeralPrivateKeyBytes dihapus dari memory,
/// session key ini TIDAK BISA diderivasi ulang meskipun peer's identity key bocor.
Future<Uint8List> deriveSessionKeyInIsolate(
  DeriveSessionKeyPayload payload,
) async {
  final x25519 = X25519();

  // Rekonstruksi ephemeral keypair.
  // Catatan: public key field di sini tidak dipakai untuk ECDH,
  // tapi SimpleKeyPairData membutuhkan field publicKey sebagai placeholder.
  final ephemeralKeyPair = SimpleKeyPairData(
    payload.ephemeralPrivateKeyBytes,
    publicKey: SimplePublicKey(
      payload.peerPublicKeyBytes, // placeholder — X25519 hanya butuh private key
      type: KeyPairType.x25519,
    ),
    type: KeyPairType.x25519,
  );

  final peerPublicKey = SimplePublicKey(
    payload.peerPublicKeyBytes,
    type: KeyPairType.x25519,
  );

  // ECDH: ephemeral_local × peer_identity → raw shared secret
  final rawSharedSecret = await x25519.sharedSecretKey(
    keyPair: ephemeralKeyPair,
    remotePublicKey: peerPublicKey,
  );
  final rawSharedSecretBytes = await rawSharedSecret.extractBytes();

  // HKDF dengan epoch-specific info string untuk domain separation.
  // Tiap epoch menghasilkan output HKDF yang berbeda secara kriptografis,
  // bahkan jika rawSharedSecret identik (misal jika keypair sama).
  final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  final sessionKey = await hkdf.deriveKey(
    secretKey: SecretKeyData(rawSharedSecretBytes),
    info: 'chimera-pfs-epoch-${payload.epochIndex}'.codeUnits,
  );

  return Uint8List.fromList(await sessionKey.extractBytes());
}

/// [ISOLATE TASK] Enkripsi PFS menggunakan session key epoch saat ini.
///
/// Menggunakan AES-256-GCM. HKDF dijalankan sekali lagi dari session key
/// dengan info epoch untuk memastikan key derivation yang konsisten.
/// Output dalam format [EncryptResult.toBytes()].
Future<EncryptResult> pfsEncryptInIsolate(PfsEncryptPayload payload) async {
  final algorithm = AesGcm.with256bits();

  // Derive AES key dari session key menggunakan HKDF dengan epoch context
  final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  final aesKey = await hkdf.deriveKey(
    secretKey: SecretKeyData(payload.sessionKeyBytes),
    info: 'chimera-pfs-aes-epoch-${payload.epochIndex}'.codeUnits,
  );

  // Nonce baru setiap enkripsi (12 bytes untuk AES-GCM)
  final nonce = algorithm.newNonce();

  final secretBox = await algorithm.encrypt(
    payload.plaintext.codeUnits.toList(),
    secretKey: aesKey,
    nonce: nonce,
  );

  return EncryptResult(
    nonce: Uint8List.fromList(secretBox.nonce),
    ciphertext: Uint8List.fromList(secretBox.cipherText),
    mac: Uint8List.fromList(secretBox.mac.bytes),
  );
}

/// [ISOLATE TASK] Dekripsi PFS menggunakan session key epoch yang sesuai.
///
/// Caller WAJIB memberikan session key dari epoch yang sama saat enkripsi.
/// Jika epochIndex tidak cocok, dekripsi akan gagal karena HKDF info berbeda.
Future<String> pfsDecryptInIsolate(PfsDecryptPayload payload) async {
  final algorithm = AesGcm.with256bits();

  final encryptResult = EncryptResult.fromBytes(payload.encryptedBytes);

  // Derive AES key yang sama dari session key + epoch context
  final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  final aesKey = await hkdf.deriveKey(
    secretKey: SecretKeyData(payload.sessionKeyBytes),
    info: 'chimera-pfs-aes-epoch-${payload.epochIndex}'.codeUnits,
  );

  final secretBox = SecretBox(
    encryptResult.ciphertext,
    nonce: encryptResult.nonce,
    mac: Mac(encryptResult.mac),
  );

  final decryptedBytes = await algorithm.decrypt(secretBox, secretKey: aesKey);
  return String.fromCharCodes(decryptedBytes);
}
