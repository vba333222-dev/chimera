import 'dart:async';
import 'package:flutter/foundation.dart';

import 'chat_database_service.dart';
import 'audit_log_service.dart';

/// Service yang berjalan di background untuk terus memantau timestamp "expires_at".
/// Ini menjamin bahwa Ephemeral Messages / View-Once Media dihapus otomatis
/// begitu umurnya melebihi batas, tanpa mempedulikan apakah user sedang
/// melihat UI chat tersebut atau tidak.
class EphemeralCleanupService {
  final ChatDatabaseService _dbService;
  final AuditLogService _auditLogService;

  Timer? _sweepTimer;

  EphemeralCleanupService(this._dbService, this._auditLogService);

  /// Memulai siklus pembersihan secara konstan setiap [interval].
  void startSweeping({Duration interval = const Duration(seconds: 10)}) {
    if (_sweepTimer != null && _sweepTimer!.isActive) {
      return;
    }

    debugPrint('[EphemeralCleanupService] Sweeper activated. Interval: ${interval.inSeconds}s');

    _sweepTimer = Timer.periodic(interval, (_) async {
      await _performSweep();
    });
  }

  void stopSweeping() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    debugPrint('[EphemeralCleanupService] Sweeper deactivated.');
  }

  Future<void> _performSweep() async {
    try {
      // Dapatkan semua sesi
      final sessions = await _dbService.getAllSessions();
      int totalShredded = 0;

      for (var session in sessions) {
        // Tarik semua pesan dalam sesi ini
        final messages = await _dbService.getMessagesForSession(session.id);
        
        final now = DateTime.now().toUtc();

        for (var msg in messages) {
          if (msg.expiresAt != null && msg.expiresAt!.isBefore(now)) {
            // Lacak apakah lampiran ada. Karena kita sekarang menggunakan In-Memory Injected Data, 
            // kita tidak lagi men-shred file dari file-system (sudah zero-disk-write).
            // Data Byte array di RAM (di-cache oleh `SecureDocumentService` atau dibuang dari tree State).
            // Cukup menghapus index history dari Chat Database agar tidak pernah bisa di-render lagi.

            // Hapus di SQLCipher 
            await _dbService.deleteMessage(msg.id);
            totalShredded++;
          }
        }
      }

      if (totalShredded > 0) {
        _auditLogService.logEvent(
          'EPHEMERAL_SWEEP', 
          '$totalShredded expired messages successfully annihilated.',
        );
      }
    } catch (e) {
      debugPrint('[EphemeralCleanupService] Sweeping error: $e');
      _auditLogService.logEvent(
        'EPHEMERAL_SWEEP_ERROR', 
        'Database vacuum failed during ephemeral sweep: $e',
      );
    }
  }
}
