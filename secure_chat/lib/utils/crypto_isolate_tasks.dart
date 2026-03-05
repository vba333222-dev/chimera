// lib/utils/crypto_isolate_tasks.dart
//
// ─────────────────────────────────────────────────────────────────────────
// FILE CRYPTO ISOLATE TASKS — Phase 7: Performance & Memory-Safe Crypto
// ─────────────────────────────────────────────────────────────────────────
//
// TUJUAN:
//   File ini berisi tugas-tugas kriptografi BERAT yang ditujukan untuk
//   dijalankan di *background* via Isolate.run() agar Main UI Thread
//   (animasi, CRT effects) tidak pernah freeze atau stutter.
//
// CATATAN PENTING:
//   File ini BEBAS dari dependency Flutter. Hanya menggunakan pure Dart
//   + package:cryptography. Ini adalah syarat mutlak agar dapat dipanggil
//   dari Worker Isolate (yang tidak memiliki Flutter Engine context).
//
// FORMAT CIPHERTEXT FILE:
//   [ 12 bytes — AES-GCM Nonce ]
//   [ 16 bytes — GCM Auth Tag (MAC) ]
//   [ N  bytes — Ciphertext ]
//
// ─────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Classes
// ─────────────────────────────────────────────────────────────────────────────

/// Konfigurasi untuk task enkripsi file yang dikirim ke Isolate.
/// Semua field bertipe dasar (Uint8List) agar aman di-pass antar isolate.
class EncryptFileConfig {
  /// Bytes plaintext (konten file asli yang belum dienkripsi).
  final Uint8List plainBytes;

  /// Kunci enkripsi AES-256 (harus tepat 32 bytes).
  final Uint8List keyBytes;

  const EncryptFileConfig({
    required this.plainBytes,
    required this.keyBytes,
  });
}

/// Konfigurasi untuk task dekripsi file yang dikirim ke Isolate.
class DecryptFileConfig {
  /// Bytes ciphertext dalam format [Nonce(12) | MAC(16) | Ciphertext(N)].
  final Uint8List encryptedBytes;

  /// Kunci dekripsi AES-256 (harus tepat 32 bytes).
  final Uint8List keyBytes;

  const DecryptFileConfig({
    required this.encryptedBytes,
    required this.keyBytes,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Konstanta Format
// ─────────────────────────────────────────────────────────────────────────────

const int _kNonceLength = 12; // AES-GCM standard nonce
const int _kMacLength   = 16; // GCM authentication tag (128-bit)

// ─────────────────────────────────────────────────────────────────────────────
// [ISOLATE TASK] Enkripsi File — Dapat dipanggil via Isolate.run()
// ─────────────────────────────────────────────────────────────────────────────

/// Mengenkripsi [config.plainBytes] menggunakan AES-256-GCM.
///
/// Setiap pemanggilan menghasilkan nonce acak yang unik secara kriptografis,
/// sehingga ciphertext yang dihasilkan selalu berbeda meskipun plaintext sama.
///
/// Output format:
///   [12-byte nonce] | [16-byte MAC] | [N-byte ciphertext]
///
/// Dimaksudkan untuk dipanggil via:
///   ```dart
///   final encrypted = await Isolate.run(() => encryptFileBytesTask(config));
///   ```
Future<Uint8List> encryptFileBytesTask(EncryptFileConfig config) async {
  final algorithm = AesGcm.with256bits();

  // Validasi ukuran kunci
  if (config.keyBytes.length != 32) {
    throw ArgumentError(
      '[encryptFileBytesTask] Key harus 32 bytes, '
      'diterima: ${config.keyBytes.length}',
    );
  }

  final secretKey = SecretKeyData(config.keyBytes);

  // Nonce baru yang dihasilkan secara acak + aman secara kriptografis
  final nonce = algorithm.newNonce();

  // Enkripsi — AES-GCM dengan AAD kosong (tidak ada additional data)
  final secretBox = await algorithm.encrypt(
    config.plainBytes,
    secretKey: secretKey,
    nonce: nonce,
  );

  // Serialisasi ke format biner tunggal: [Nonce | MAC | Ciphertext]
  final output = BytesBuilder(copy: false);
  output.add(secretBox.nonce);          // 12 bytes
  output.add(secretBox.mac.bytes);      // 16 bytes
  output.add(secretBox.cipherText);     // N  bytes
  final result = output.toBytes();

  // ─── Memory-Safe Wiping ───────────────────────────────────────────────
  // Nol-kan plaintext buffer setelah enkripsi selesai agar bytes sensitif
  // tidak tertinggal di heap memori (anti-RAM scraping & anti cold-boot).
  wipeBytes(config.plainBytes);
  // ─────────────────────────────────────────────────────────────────────

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// [ISOLATE TASK] Dekripsi File — Dapat dipanggil via Isolate.run()
// ─────────────────────────────────────────────────────────────────────────────

/// Mendekripsi [config.encryptedBytes] menggunakan AES-256-GCM.
///
/// Fungsi ini akan melempar [SecretBoxAuthenticationError] jika MAC/tag
/// autentikasi tidak cocok — indikasi data telah dimanipulasi (*tampered*).
///
/// Input harus dalam format yang dihasilkan oleh [encryptFileBytesTask]:
///   [12-byte nonce] | [16-byte MAC] | [N-byte ciphertext]
///
/// Dimaksudkan untuk dipanggil via:
///   ```dart
///   final plainBytes = await Isolate.run(() => decryptFileBytesTask(config));
///   ```
Future<Uint8List> decryptFileBytesTask(DecryptFileConfig config) async {
  final algorithm = AesGcm.with256bits();

  // Validasi ukuran minimum ciphertext
  if (config.encryptedBytes.length < _kNonceLength + _kMacLength) {
    throw ArgumentError(
      '[decryptFileBytesTask] Data terlalu pendek untuk berisi '
      'nonce + mac: ${config.encryptedBytes.length} bytes',
    );
  }

  if (config.keyBytes.length != 32) {
    throw ArgumentError(
      '[decryptFileBytesTask] Key harus 32 bytes, '
      'diterima: ${config.keyBytes.length}',
    );
  }

  // Parse format biner: [Nonce | MAC | Ciphertext]
  final nonce = config.encryptedBytes.sublist(0, _kNonceLength);
  final mac   = config.encryptedBytes.sublist(_kNonceLength, _kNonceLength + _kMacLength);
  final ciphertext = config.encryptedBytes.sublist(_kNonceLength + _kMacLength);

  final secretKey = SecretKeyData(config.keyBytes);

  final secretBox = SecretBox(
    ciphertext,
    nonce: nonce,
    mac: Mac(mac),
  );

  // Dekripsi + verifikasi MAC — akan melempar exception jika gagal autentikasi
  final plainBytes = await algorithm.decrypt(secretBox, secretKey: secretKey);
  return Uint8List.fromList(plainBytes);
}

// ─────────────────────────────────────────────────────────────────────────────
// Memory-Safe Utilities
// ─────────────────────────────────────────────────────────────────────────────

/// Menimpa setiap byte dalam buffer dengan nilai nol (0x00).
///
/// Dipanggil secara eksplisit setelah operasi kriptografi selesai untuk:
/// 1. Mencegah plaintext tertinggal di heap garbage collector (anti RAM scraping).
/// 2. Meminimalkan jendela waktu serangan cold-boot attack.
/// 3. Mematuhi standar NIST key zeroization (SP 800-57).
///
/// **PENTING:** Fungsi ini hanya efektif selama variabel masih merujuk ke
/// Uint8List yang sama. Karena Dart GC bisa memindahkan objek, ini adalah
/// "best-effort" zero-out yang direkomendasikan di environment managed.
void wipeBytes(Uint8List buffer) {
  buffer.fillRange(0, buffer.length, 0x00);
}

/// Versi null-safe dari [wipeBytes] untuk nullable buffer.
/// Tidak melakukan apa-apa jika buffer adalah `null`.
void wipeBytesIfNotNull(Uint8List? buffer) {
  if (buffer != null) wipeBytes(buffer);
}

// ─────────────────────────────────────────────────────────────────────────────
// Legacy Compat (Dipertahankan untuk backward compatibility dengan
// SecureDocumentService versi lama yang mungkin masih mereferensikan ini)
// ─────────────────────────────────────────────────────────────────────────────

/// Alias tipe lama — dipertahankan agar tidak ada breaking change.
@Deprecated('Gunakan DecryptFileConfig sebagai gantinya.')
typedef DecryptTaskConfig = DecryptFileConfig;
