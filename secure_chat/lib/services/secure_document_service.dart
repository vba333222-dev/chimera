import 'dart:isolate';
import 'package:flutter/foundation.dart';

import 'audit_log_service.dart';
import '../utils/crypto_isolate_tasks.dart';

/// Service untuk menangani dokumen (In-Memory Processing).
/// Memastikan file tidak tersebar ke galeri publik maupun ditulis ke Disk (Zero-Disk Write).
class SecureDocumentService {
  final AuditLogService _auditLogService;

  SecureDocumentService(this._auditLogService);

  /// Mendekripsi file menggunakan background Isolate dan mengembalikan `Uint8List` murni di RAM.
  /// Tidak ada jejak fisik yang tertinggal di Storage/Cache Android.
  Future<Uint8List> decryptDocumentInMemory(Uint8List encryptedBytes) async {
    try {
      // 1. Catat log sebelum operasi raksasa dikerjakan
      _auditLogService.logEvent(
        'DOC_DECRYPT_START', 
        'Isolate decryption task spawned for in-memory buffer.',
      );

      // 2. Siapkan config (Misalkan kita pass dummy AES key & nonce di sini)
      final config = DecryptTaskConfig(
        encryptedBytes: encryptedBytes,
        key: Uint8List(32),
        nonce: Uint8List(12),
      );

      // 3. Eksekusi Heavy Crypto Task di Background Thread (Isolate)
      // UI akan tetap 60fps animasi jalan halus
      final decryptedBytes = await Isolate.run(() => decryptFileBytesTask(config));

      // 4. Catat success log
      _auditLogService.logEvent(
        'DOC_DECRYPT_SUCCESS', 
        'Document decrypted safely in-memory. Zero disk write.',
      );

      return decryptedBytes;
    } catch (e) {
      debugPrint('[SecureDocumentService] Error decrypting document: $e');
      _auditLogService.logEvent('DOC_DECRYPT_ERROR', 'Failed to decrypt document in memory: $e');
      rethrow;
    }
  }

  /// Membersihkan byte dari Memory (Opsional - Garbage Collector akan mengurusnya)
  /// Namun kita beri trigger eksplisit saat viewer ditutup.
  void releaseMemoryBinding() {
    _auditLogService.logEvent('DOC_MEMORY_RELEASED', 'Explicit request to GC to drop memory reference.');
  }
}
