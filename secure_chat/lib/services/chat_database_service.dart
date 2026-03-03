// lib/services/chat_database_service.dart
//
// Layanan database lokal terenkripsi untuk Chimera menggunakan SQLCipher.
//
// Arsitektur Keamanan:
//   - Database dienkripsi menggunakan SQLCipher (AES-256-CBC)
//   - Kunci enkripsi database (DBK) dibuat secara acak (32 bytes) saat
//     instalasi pertama menggunakan Dart crypto-secure RNG.
//   - DBK disimpan di FlutterSecureStorage (Android Keystore / iOS Keychain).
//   - Hanya kunci (DBK) yang disimpan di Secure Storage, bukan data itu sendiri.
//   - Pemisahan ini memastikan: jika file DB dicuri, data tetap terlindungi
//     karena penyerang tidak punya DBK.
//
// Schema Database:
//   ┌────────────────────────────────────────┐
//   │  TABLE: chat_sessions                  │
//   │  id TEXT PK                            │
//   │  title TEXT                            │
//   │  target_fingerprint TEXT               │
//   │  peer_public_key_b64 TEXT (nullable)   │
//   │  created_at_ms INTEGER                 │
//   │  last_message_at_ms INTEGER (nullable) │
//   │  is_active INTEGER (0/1)               │
//   └────────────────────────────────────────┘
//   ┌────────────────────────────────────────┐
//   │  TABLE: messages                       │
//   │  id TEXT PK                            │
//   │  session_id TEXT FK → chat_sessions.id │
//   │  text TEXT                             │
//   │  sender_id TEXT                        │
//   │  timestamp_ms INTEGER                  │
//   │  is_encrypted INTEGER (0/1)            │
//   │  is_terminal_command INTEGER (0/1)     │
//   │  status INTEGER (0:pending, 1:sent, 2:failed) │
//   │  expires_at_ms INTEGER (nullable)      │
//   └────────────────────────────────────────┘

import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/chat_session.dart';
import '../models/message.dart';
import '../providers/providers.dart';
import '../utils/decoy_data_seeder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _dbName = 'chimera_vault.db';
const _dbKeyStorageKey = 'chimera_db_encryption_key';
const _dbVersion = 3; // Bumped to 3 for expires_at_ms

// ─────────────────────────────────────────────────────────────────────────────
// ChatDatabaseService
// ─────────────────────────────────────────────────────────────────────────────

class ChatDatabaseService {
  final FlutterSecureStorage _secureStorage;
  final VaultMode _vaultMode;

  Database? _db;

  ChatDatabaseService(this._secureStorage, this._vaultMode);

  // ───────────────────────────────────────────────────────────────────────────
  // Initialization & Lifecycle
  // ───────────────────────────────────────────────────────────────────────────

  /// Inisialisasi database terenkripsi.
  ///
  /// Urutan operasi:
  ///   1. Ambil atau buat Database Key (DBK) dari FlutterSecureStorage.
  ///   2. Buka database SQLCipher menggunakan DBK sebagai password.
  ///   3. Jalankan migrasi schema jika diperlukan.
  Future<void> initialize() async {
    if (_db != null && _db!.isOpen) return;

    final password = await _getOrCreateDatabaseKey();
    final dbPath = await _getDatabasePath();

    _db = await openDatabase(
      dbPath,
      password: password,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      // Pastikan foreign key enforcement aktif
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );

    if (_vaultMode == VaultMode.decoy) {
      await DecoyDataSeeder.seedIfNeeded(_db!);
    }
  }

  /// Tutup koneksi database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Hapus seluruh database dari disk (gunakan saat full wipe/logout).
  /// Kunci di SecureStorage juga akan dihapus.
  Future<void> destroyDatabase() async {
    await close();
    final dbPath = await _getDatabasePath();
    await deleteDatabase(dbPath);
    await _secureStorage.delete(key: _getStorageKey());
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ChatSession CRUD
  // ───────────────────────────────────────────────────────────────────────────

  /// Menyimpan ChatSession baru ke database.
  Future<void> insertSession(ChatSession session) async {
    await _ensureOpen();
    await _db!.insert(
      'chat_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mengambil semua ChatSession, diurutkan dari yang paling baru.
  Future<List<ChatSession>> getAllSessions() async {
    await _ensureOpen();
    final maps = await _db!.query(
      'chat_sessions',
      orderBy: 'last_message_at_ms DESC, created_at_ms DESC',
    );
    return maps.map(ChatSession.fromMap).toList();
  }

  /// Mengambil satu ChatSession berdasarkan ID.
  Future<ChatSession?> getSessionById(String id) async {
    await _ensureOpen();
    final maps = await _db!.query(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ChatSession.fromMap(maps.first);
  }

  /// Memperbarui data ChatSession (misalnya, lastMessageAt).
  Future<void> updateSession(ChatSession session) async {
    await _ensureOpen();
    await _db!.update(
      'chat_sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// Menghapus ChatSession beserta semua Message-nya (CASCADE).
  Future<void> deleteSession(String sessionId) async {
    await _ensureOpen();
    // Foreign key ON DELETE CASCADE akan otomatis hapus messages terkait.
    await _db!.delete(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Message CRUD
  // ───────────────────────────────────────────────────────────────────────────

  /// Menyimpan satu Message baru ke database.
  /// Secara otomatis memperbarui [lastMessageAt] pada session induk.
  Future<void> insertMessage(Message message) async {
    await _ensureOpen();

    await _db!.transaction((txn) async {
      // 1. Simpan message
      await txn.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // 2. Perbarui last_message_at di session induk
      await txn.rawUpdate(
        '''
        UPDATE chat_sessions
        SET last_message_at_ms = ?
        WHERE id = ?
        ''',
        [message.timestamp.millisecondsSinceEpoch, message.sessionId],
      );
    });
  }

  /// Menyimpan banyak Message sekaligus (batch insert).
  /// Lebih efisien daripada memanggil [insertMessage] berulang kali.
  Future<void> insertMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    await _ensureOpen();

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final msg in messages) {
        batch.insert(
          'messages',
          msg.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);

      // Perbarui last_message_at dengan pesan terakhir dalam batch
      final latestMsg = messages.reduce(
        (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
      );
      await txn.rawUpdate(
        '''
        UPDATE chat_sessions
        SET last_message_at_ms = ?
        WHERE id = ?
        ''',
        [latestMsg.timestamp.millisecondsSinceEpoch, latestMsg.sessionId],
      );
    });
  }

  /// Mengambil semua Message untuk suatu session, diurutkan dari yang terlama.
  Future<List<Message>> getMessagesForSession(String sessionId) async {
    await _ensureOpen();
    final maps = await _db!.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp_ms ASC',
    );
    return maps.map(Message.fromMap).toList();
  }

  /// Mengambil N pesan terakhir dari suatu session (untuk paging/preview).
  Future<List<Message>> getRecentMessages(
    String sessionId, {
    int limit = 50,
  }) async {
    await _ensureOpen();
    final maps = await _db!.rawQuery(
      '''
      SELECT * FROM messages
      WHERE session_id = ?
      ORDER BY timestamp_ms DESC
      LIMIT ?
      ''',
      [sessionId, limit],
    );
    // Balik list agar urutan chronological (terlama dulu)
    return maps.map(Message.fromMap).toList().reversed.toList();
  }

  /// Menghapus satu Message berdasarkan ID.
  Future<void> deleteMessage(String messageId) async {
    await _ensureOpen();
    await _db!.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Menghapus semua pesan dari suatu session (tanpa menghapus session-nya).
  Future<void> clearMessagesForSession(String sessionId) async {
    await _ensureOpen();
    await _db!.delete(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Mengambil semua pesan yang masih berstatus pending.
  Future<List<Message>> getPendingMessages() async {
    await _ensureOpen();
    final maps = await _db!.query(
      'messages',
      where: 'status = ?',
      whereArgs: [MessageStatus.pending.index],
      orderBy: 'timestamp_ms ASC', // Pastikan dikirim berurutan
    );
    return maps.map(Message.fromMap).toList();
  }

  /// Memperbarui status pengiriman suatu pesan.
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    await _ensureOpen();
    await _db!.update(
      'messages',
      {'status': status.index},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Key Management (Private)
  // ───────────────────────────────────────────────────────────────────────────

  /// Mengambil kunci enkripsi dari SecureStorage, atau membuat yang baru
  /// jika ini adalah instalasi pertama.
  ///
  /// Kunci dibuat menggunakan [Random.secure()] — Cryptographically Secure
  /// Pseudo-Random Number Generator (CSPRNG) bawaan Dart.
  Future<String> _getOrCreateDatabaseKey() async {
    final storageKey = _getStorageKey();
    final existingKey = await _secureStorage.read(key: storageKey);
    if (existingKey != null) return existingKey;

    // Instalasi pertama: generate 32-byte (256-bit) random key
    final newKey = _generateSecureKey(32);
    await _secureStorage.write(
      key: storageKey,
      value: newKey,
    );
    return newKey;
  }

  /// Menghasilkan string kunci acak yang aman secara kriptografis.
  /// [length] adalah jumlah bytes yang akan di-generate (output akan berupa
  /// Base64 URL-safe string dari bytes tersebut).
  String _generateSecureKey(int length) {
    final rng = Random.secure();
    final bytes = List<int>.generate(length, (_) => rng.nextInt(256));
    // Gunakan Base64 URL-safe (tanpa padding '=') agar kompatibel sebagai
    // password string di SQLCipher
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers (Private)
  // ───────────────────────────────────────────────────────────────────────────

  Future<String> _getDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    final dbName = _vaultMode == VaultMode.decoy ? 'chimera_decoy.db' : _dbName;
    return p.join(databasesPath, dbName);
  }

  String _getStorageKey() {
    return _vaultMode == VaultMode.decoy ? '${_dbKeyStorageKey}_decoy' : _dbKeyStorageKey;
  }

  /// Memastikan database sudah diinisialisasi sebelum operasi apapun.
  Future<void> _ensureOpen() async {
    if (_db == null || !_db!.isOpen) {
      await initialize();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Schema Migration (Private)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await _createSchema(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrasi versi 1 -> 2: Tambahkan kolom 'status' ke tabel messages.
    // Nilai default 1 (sent) agar pesan lama tidak dikirim ulang.
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE messages
        ADD COLUMN status INTEGER NOT NULL DEFAULT 1
      ''');
    }
    // Migrasi versi 2 -> 3: Tambahkan kolom 'expires_at_ms'
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE messages
        ADD COLUMN expires_at_ms INTEGER
      ''');
    }
  }

  Future<void> _createSchema(Database db) async {
    // Tabel untuk menyimpan sesi obrolan
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions (
        id                  TEXT PRIMARY KEY,
        title               TEXT NOT NULL,
        target_fingerprint  TEXT NOT NULL,
        peer_public_key_b64 TEXT,
        created_at_ms       INTEGER NOT NULL,
        last_message_at_ms  INTEGER,
        is_active           INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Tabel untuk menyimpan pesan individual
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id                  TEXT PRIMARY KEY,
        session_id          TEXT NOT NULL,
        text                TEXT NOT NULL,
        sender_id           TEXT NOT NULL,
        timestamp_ms        INTEGER NOT NULL,
        is_encrypted        INTEGER NOT NULL DEFAULT 1,
        is_terminal_command INTEGER NOT NULL DEFAULT 0,
        status              INTEGER NOT NULL DEFAULT 1,
        expires_at_ms       INTEGER,
        FOREIGN KEY (session_id)
          REFERENCES chat_sessions (id)
          ON DELETE CASCADE
      )
    ''');

    // Index untuk mempercepat query mengambil pesan per session
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_session_id
      ON messages (session_id, timestamp_ms ASC)
    ''');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk instance [ChatDatabaseService].
///
/// Menggunakan [AsyncNotifierProvider] bukan [Provider] karena inisialisasi
/// database bersifat asinkron (perlu membuka file, verify key, dll).
final chatDatabaseProvider = AsyncNotifierProvider<_ChatDatabaseNotifier, ChatDatabaseService>(
  _ChatDatabaseNotifier.new,
);

class _ChatDatabaseNotifier extends AsyncNotifier<ChatDatabaseService> {
  @override
  Future<ChatDatabaseService> build() async {
    final storage = ref.watch(secureStorageProvider);
    final vaultMode = ref.watch(vaultModeProvider);
    final service = ChatDatabaseService(storage, vaultMode);
    await service.initialize();

    // Tutup database saat provider di-dispose (misalnya saat app di-restart)
    ref.onDispose(service.close);

    return service;
  }
}

/// Provider convenience untuk mengakses [ChatDatabaseService] yang sudah siap.
/// Gunakan `.when()` di UI untuk menangani loading/error state.
///
/// Contoh penggunaan di widget:
/// ```dart
/// final dbAsync = ref.watch(chatDatabaseProvider);
/// dbAsync.when(
///   data: (db) => ...,
///   loading: () => CircularProgressIndicator(),
///   error: (e, st) => Text('DB Error: $e'),
/// );
/// ```
final chatSessionsProvider = FutureProvider<List<ChatSession>>((ref) async {
  final db = await ref.watch(chatDatabaseProvider.future);
  return db.getAllSessions();
});
