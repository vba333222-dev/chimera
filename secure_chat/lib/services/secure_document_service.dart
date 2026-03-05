// lib/services/secure_document_service.dart
//
// ─────────────────────────────────────────────────────────────────────────
// SecureDocumentService — Phase 7: Isolate-Based In-Memory File Crypto
// ─────────────────────────────────────────────────────────────────────────
//
// PRINSIP KEAMANAN:
//   1. ZERO-DISK WRITE:  File tidak pernah di-cache atau ditulis ke disk.
//   2. ISOLATE OFFLOAD:  Enkripsi/dekripsi AES-256-GCM diproses di Worker
//                        Isolate terpisah sehingga Main UI Thread (animasi,
//                        CRT effects) tetap smooth di 60fps.
//   3. MEMORY SAFE:      Buffer plaintext di-wipe (di-nol-kan) segera
//                        setelah selesai digunakan via wipeBytes().
//
// ─────────────────────────────────────────────────────────────────────────

import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'audit_log_service.dart';
import '../utils/crypto_isolate_tasks.dart';

/// Service untuk mengenkripsi dan mendekripsi file secara aman di dalam
/// memori RAM — tidak ada byte sensitif yang menyentuh storage fisik.
class SecureDocumentService {
  final AuditLogService _auditLogService;

  SecureDocumentService(this._auditLogService);

  // ─── Dekripsi File ────────────────────────────────────────────────────────

  /// Mendekripsi file yang diunduh dari server menggunakan AES-256-GCM,
  /// seluruhnya di dalam Worker Isolate untuk memastikan UI tidak freeze.
  ///
  /// [encryptedBytes] — byte file dalam format: [Nonce(12)|MAC(16)|Ciphertext]
  /// [fileKeyBytes]   — kunci AES-256 yang diderivasi dari shared secret sesi.
  ///                    Harus tepat 32 bytes.
  ///
  /// Melempar [SecretBoxAuthenticationError] jika file telah dimanipulasi.
  ///
  /// Contoh pemanggilan:
  ///   ```dart
  ///   final plain = await secureDocService.decryptDocumentInMemory(
  ///     encryptedBytes: filePayload,
  ///     fileKeyBytes: derivedKey,
  ///   );
  ///   ```
  Future<Uint8List> decryptDocumentInMemory(
    Uint8List encryptedBytes, {
    Uint8List? fileKeyBytes,
  }) async {
    // Fallback ke demo key jika tidak disediakan (untuk testing/demo saja)
    final keyBytes = fileKeyBytes ?? Uint8List(32);

    try {
      _auditLogService.logEvent(
        'DOC_DECRYPT_START',
        'Spawning Worker Isolate for in-memory AES-256-GCM decryption '
        '(${encryptedBytes.length} bytes).',
      );

      final config = DecryptFileConfig(
        encryptedBytes: encryptedBytes,
        keyBytes: keyBytes,
      );

      // ── Background Thread (Isolate) ─────────────────────────────────────
      // Isolate.run() meluncurkan Worker Isolate baru, menjalankan dekripsi
      // di sana, lalu mengembalikan hasilnya ke Main Isolate & langsung musnah.
      // CPU-intensive AES-GCM tidak akan menyentuh Main UI Thread sama sekali.
      final plainBytes = await Isolate.run(
        () => decryptFileBytesTask(config),
      );
      // ─────────────────────────────────────────────────────────────────────

      _auditLogService.logEvent(
        'DOC_DECRYPT_SUCCESS',
        'Decryption complete. Plaintext held in RAM only (zero-disk write).',
      );

      return plainBytes;
    } catch (e) {
      debugPrint('[SecureDocumentService] Decryption error: $e');
      _auditLogService.logEvent(
        'DOC_DECRYPT_ERROR',
        'AES-GCM decryption failed: $e',
      );
      rethrow;
    }
  }

  // ─── Enkripsi File Outbound ───────────────────────────────────────────────

  /// Mengenkripsi file sebelum dikirim menggunakan AES-256-GCM,
  /// di Worker Isolate. Setelah enkripsi selesai, plaintext buffer di-wipe.
  ///
  /// [plainBytes]    — byte file yang akan dienkripsi.
  /// [fileKeyBytes]  — kunci AES-256 (32 bytes).
  ///
  /// Mengembalikan Uint8List dalam format: [Nonce(12)|MAC(16)|Ciphertext]
  Future<Uint8List> encryptDocumentInMemory(
    Uint8List plainBytes, {
    Uint8List? fileKeyBytes,
  }) async {
    final keyBytes = fileKeyBytes ?? Uint8List(32);

    try {
      _auditLogService.logEvent(
        'DOC_ENCRYPT_START',
        'Spawning Worker Isolate for in-memory AES-256-GCM encryption '
        '(${plainBytes.length} bytes).',
      );

      final config = EncryptFileConfig(
        plainBytes: plainBytes,
        keyBytes: keyBytes,
      );

      // ── Background Thread (Isolate) ─────────────────────────────────────
      // encryptFileBytesTask() sendiri memanggil wipeBytes() pada plaintext
      // di dalam Isolate setelah enkripsi selesai.
      final encryptedBytes = await Isolate.run(
        () => encryptFileBytesTask(config),
      );
      // ─────────────────────────────────────────────────────────────────────

      // Ekstra wipe pada plaintext di Main Isolate juga (defense in depth)
      wipeBytes(plainBytes);

      _auditLogService.logEvent(
        'DOC_ENCRYPT_SUCCESS',
        'Encryption complete. Plaintext buffer wiped from RAM.',
      );

      return encryptedBytes;
    } catch (e) {
      debugPrint('[SecureDocumentService] Encryption error: $e');
      _auditLogService.logEvent(
        'DOC_ENCRYPT_ERROR',
        'AES-GCM encryption failed: $e',
      );
      rethrow;
    }
  }

  // ─── Memory Management ────────────────────────────────────────────────────

  /// Melepaskan referensi buffer yang telah selesai digunakan.
  ///
  /// Memanggil [wipeBytes] untuk menimpa seluruh byte dengan nol (0x00)
  /// sebelum referensi dilepas ke Dart GC. Dipanggil saat viewer ditutup
  /// atau sesi chat berakhir.
  ///
  /// [buffer] — buffer yang akan di-wipe (nullable, aman untuk null).
  void releaseBuffer(Uint8List? buffer) {
    if (buffer == null) return;
    wipeBytes(buffer);
    _auditLogService.logEvent(
      'DOC_MEMORY_RELEASED',
      'Plaintext buffer explicitly wiped and released to GC.',
    );
  }

  /// Alias backward-compat (dipanggil oleh SecureDocumentViewerScreen lama).
  void releaseMemoryBinding() => releaseBuffer(null);
}
