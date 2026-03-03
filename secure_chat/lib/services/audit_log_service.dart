import 'dart:developer' as developer;

import '../models/audit_log.dart';
import '../providers/providers.dart';
import 'audit_database_service.dart';

class AuditLogService {
  final AuditDatabaseService _auditDb;
  final VaultMode _vaultMode;

  AuditLogService(this._auditDb, this._vaultMode);

  /// Mencatat event baru ke dalam Audit Database dengan konsep Hash-Chained.
  /// Membaca currentHash log terakhir untuk ditautkan sebagai previousHash.
  Future<void> logEvent(String action, String details) async {
    // Hard-Stop: Decoy mode is an isolated zone, do not pollute real audit logs
    if (_vaultMode == VaultMode.decoy) return;
    
    try {
      final lastLog = await _auditDb.getLastLog();
      
      // Jika database kosong, gunakan "GENESIS" sebagai awal rantai hash.
      final String prevHash = lastLog?.currentHash ?? 'GENESIS';

      // Factory akan mengkalkulasi payload string dan otomatis meng-hash
      final newLog = AuditLog.create(
        action: action,
        details: details,
        previousHash: prevHash,
      );

      await _auditDb.insertLog(newLog);
    } catch (e) {
      // ignore: avoid_print
      print('[AUDIT_ERROR] Failed to write secure log: $e');
    }
  }

  /// Memvalidasi seluruh rekam jejak Audit Database dari awal hingga akhir
  /// - Menguji integritas individual hash masing-masing records.
  /// - Menguji kohesi rantai persambungan baris `previousHash` == `currentHash` sebelum.
  Future<bool> verifyChain() async {
    try {
      final logs = await _auditDb.getAllLogsAscending();
      if (logs.isEmpty) {
        developer.log('[AUDIT] No logs to verify. Empty chain is valid.');
        return true;
      }

      String expectedPrevHash = 'GENESIS';

      for (var log in logs) {
        // 1. Verifikasi konektor antar node (blockchain principle)
        if (log.previousHash != expectedPrevHash) {
          developer.log('[AUDIT_BREACH] Broken chain link at log: ${log.id}. '
              'Expected: $expectedPrevHash, Found: ${log.previousHash}');
          return false;
        }

        // 2. Verifikasi hash internal field untuk membuktikan payload tidak di-tamper
        if (!log.verifyIntegrity()) {
          developer.log('[AUDIT_BREACH] Data tampering detected at log payload: ${log.id}.');
          return false;
        }

        expectedPrevHash = log.currentHash;
      }

      developer.log('[AUDIT_SECURE] Hash chain verified successfully. 100% VALID. Nodes: ${logs.length}');
      return true;
    } catch (e) {
      developer.log('[AUDIT_ERROR] Verification process crashed: $e');
      return false;
    }
  }

  Future<void> destructDatabase() async {
     await _auditDb.deletePhysically();
  }
}
