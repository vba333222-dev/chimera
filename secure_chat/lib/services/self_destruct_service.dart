import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';

import '../services/audit_log_service.dart';
import '../services/chat_database_service.dart';

/// Service khusus untuk protokol penghancuran diri (Self-Destruct).
/// 
/// Ketika Duress PIN dimasukkan, service ini akan dipanggil secara latar belakang
/// untuk menghancurkan kunci kriptografi dan metadata SQLite fisik tanpa disadari musuh.
class SelfDestructService {
  final FlutterSecureStorage _secureStorage;
  final ChatDatabaseService _chatDatabaseService;
  final AuditLogService _auditLogService;

  SelfDestructService(this._secureStorage, this._chatDatabaseService, this._auditLogService);

  /// Menjalankan protokol pembumihangusan data secara asinkron tanpa menunda UI.
  Future<void> executeSelfDestruct() async {
    try {
      // 1. Mencegah akses baca/tulis lebih lanjut ke database yang sedang aktif
      await _chatDatabaseService.close();

      // 2. Menghapus file fisik SQLite dari memori perangkat
      final dbPath = await getDatabasesPath();
      final fullPath = join(dbPath, 'chimera_vault.db'); // Sesuai _dbName di ChatDatabaseService
      await deleteDatabase(fullPath);

      // 3. Menghancurkan audit logs
      await _auditLogService.destructDatabase();

      // 4. MENGHAPUS KUNCI SECARA SELEKTIF
      // Kita TIDAK menggunakan _secureStorage.deleteAll() karena itu akan 
      // memusnahkan 'chimera_db_encryption_key_decoy' juga!
      await _secureStorage.delete(key: 'chimera_db_encryption_key');
      await _secureStorage.delete(key: 'chimera_audit_db_key');
      await _secureStorage.delete(key: 'chimera_proxy_config');

      // ignore: avoid_print
      print('[CRITICAL] Self-Destruct Protocol Executed. All data wiped.');
    } catch (e) {
      // Dalam kasus extrem ini, kita telan error agar tidak crash dan penyerang tidak curiga
      // ignore: avoid_print
      print('[CRITICAL_ERROR] Self-Destruct failed: $e');
    }
  }
}
