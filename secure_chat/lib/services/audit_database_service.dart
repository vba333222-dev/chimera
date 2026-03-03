import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/audit_log.dart';

class AuditDatabaseService {
  static const String _dbName = 'chimera_audit.db';
  static const String _dbKeyStorageKey = 'chimera_audit_db_key';
  static const int _dbVersion = 1;

  final FlutterSecureStorage _secureStorage;
  Database? _db;

  AuditDatabaseService(this._secureStorage);

  Future<void> initialize() async {
    if (_db != null && _db!.isOpen) return;

    final password = await _getOrCreateDatabaseKey();
    final dbPath = await _getDatabasePath();

    _db = await openDatabase(
      dbPath,
      password: password,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<String> _getDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, _dbName);
  }

  Future<String> _getOrCreateDatabaseKey() async {
    String? key = await _secureStorage.read(key: _dbKeyStorageKey);
    if (key == null) {
      final secureRandom = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => secureRandom.nextInt(256));
      key = base64Encode(keyBytes);
      await _secureStorage.write(key: _dbKeyStorageKey, value: key);
    }
    return key;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE audit_logs(
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        previousHash TEXT NOT NULL,
        currentHash TEXT NOT NULL
      )
    ''');
  }

  // ── Database Operations ────────────────────────────────────────────────────

  Future<void> insertLog(AuditLog log) async {
    if (_db == null) await initialize();
    await _db!.insert(
      'audit_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail, // Log tidak boleh ditimpa
    );
  }

  /// Mendapatkan entri log terakhir secara kronologis (paling baru).
  Future<AuditLog?> getLastLog() async {
    if (_db == null) await initialize();
    final maps = await _db!.query(
      'audit_logs',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AuditLog.fromMap(maps.first);
  }

  /// Mendapatkan semua log secara terurut dari yang tertua hingga terbaru.
  /// Ini diperlukan untuk validasi `verifyChain()`.
  Future<List<AuditLog>> getAllLogsAscending() async {
    if (_db == null) await initialize();
    final maps = await _db!.query(
      'audit_logs',
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => AuditLog.fromMap(map)).toList();
  }

  Future<void> deletePhysically() async {
    await close();
    final dbPath = await _getDatabasePath();
    await deleteDatabase(dbPath);
  }
}
