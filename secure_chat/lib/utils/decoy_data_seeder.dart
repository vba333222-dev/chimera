import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_session.dart';
import '../models/message.dart';

/// Utilitas untuk mengisi data tiruan (Decoy Data) ke dalam database saat 
/// VaultMode.decoy baru pertama kali dibuat.
class DecoyDataSeeder {
  static const _uuid = Uuid();

  /// Menjalankan seeding jika tabel `chat_sessions` kosong.
  static Future<void> seedIfNeeded(Database db) async {
    final countMaps = await db.rawQuery('SELECT COUNT(*) as count FROM chat_sessions');
    final count = Sqflite.firstIntValue(countMaps) ?? 0;

    if (count == 0) {
      await _runSeeding(db);
    }
  }

  static Future<void> _runSeeding(Database db) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    
    // ----------------------------------------------------------------------
    // Session 1: Laporan Absensi (Terlihat seperti grup koordinasi HR)
    // ----------------------------------------------------------------------
    final hrSessionId = _uuid.v4();
    final hrSession = ChatSession(
      id: hrSessionId,
      title: 'Laporan Absensi Bulanan',
      targetFingerprint: 'HR-DEPT-993',
      createdAtMs: nowMs - (86400000 * 2), // 2 days ago
      lastMessageAtMs: nowMs - 3600000,    // 1 hour ago
      isActive: true,
    );

    // ----------------------------------------------------------------------
    // Session 2: Jadwal Piket (Grup operasional standar)
    // ----------------------------------------------------------------------
    final opsSessionId = _uuid.v4();
    final opsSession = ChatSession(
      id: opsSessionId,
      title: 'Jadwal Piket Keamanan',
      targetFingerprint: 'OPS-DEPT-402',
      createdAtMs: nowMs - (86400000 * 5), // 5 days ago
      lastMessageAtMs: nowMs - 7200000,    // 2 hours ago
      isActive: true,
    );

    // Sisipkan sesi dalam batch transaction
    await db.transaction((txn) async {
      // Masukkan sesi
      await txn.insert('chat_sessions', hrSession.toMap());
      await txn.insert('chat_sessions', opsSession.toMap());

      // Masukkan pesan untuk Session 1 (HR)
      final hrMessages = [
        Message(
          id: _uuid.v4(),
          sessionId: hrSessionId,
          text: 'Mohon rekap absensi minggu ini dikirimkan sebelum jam 5 sore.',
          senderId: 'HR-Admin',
          timestampMs: nowMs - 86400000,
          status: MessageStatus.sent,
        ),
        Message(
          id: _uuid.v4(),
          sessionId: hrSessionId,
          text: 'Baik, sedang saya susun format Excel-nya.',
          senderId: 'Me',
          timestampMs: nowMs - 82800000,
          status: MessageStatus.sent,
        ),
        Message(
          id: _uuid.v4(),
          sessionId: hrSessionId,
          text: 'Terima kasih, ditunggu updatenya.',
          senderId: 'HR-Admin',
          timestampMs: nowMs - 3600000,
          status: MessageStatus.sent,
        ),
      ];

      for (final msg in hrMessages) {
        await txn.insert('messages', msg.toMap());
      }

      // Masukkan pesan untuk Session 2 (Ops)
      final opsMessages = [
        Message(
          id: _uuid.v4(),
          sessionId: opsSessionId,
          text: 'Jadwal piket untuk regu 3 sudah dirilis di mading.',
          senderId: 'Danru-Ops',
          timestampMs: nowMs - 172800000,
          status: MessageStatus.sent,
        ),
        Message(
          id: _uuid.v4(),
          sessionId: opsSessionId,
          text: 'Siap komandan, jadwal sudah diterima.',
          senderId: 'Me',
          timestampMs: nowMs - 7200000,
          status: MessageStatus.sent,
        ),
      ];

      for (final msg in opsMessages) {
        await txn.insert('messages', msg.toMap());
      }
    });
  }
}
