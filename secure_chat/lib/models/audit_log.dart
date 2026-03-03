import 'dart:convert';
import 'package:crypto/crypto.dart';

class AuditLog {
  final String id;
  final DateTime timestamp;
  final String action;
  final String details;
  final String previousHash;
  final String currentHash;

  const AuditLog({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.details,
    required this.previousHash,
    required this.currentHash,
  });

  /// Factory untuk membuat AuditLog baru. Secara otomatis akan menghitung hash 
  /// dari elemen struktural (previousHash + iso8601 + action + details).
  factory AuditLog.create({
    required String action,
    required String details,
    required String previousHash,
  }) {
    final now = DateTime.now().toUtc();
    final id = now.millisecondsSinceEpoch.toString();
    
    // Pembuatan string data untuk konsistensi hash
    final dataString = '$previousHash|${now.toIso8601String()}|$action|$details';
    final currentHash = sha256.convert(utf8.encode(dataString)).toString();

    return AuditLog(
      id: id,
      timestamp: now,
      action: action,
      details: details,
      previousHash: previousHash,
      currentHash: currentHash,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'action': action,
      'details': details,
      'previousHash': previousHash,
      'currentHash': currentHash,
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      action: map['action'] as String,
      details: map['details'] as String,
      previousHash: map['previousHash'] as String,
      currentHash: map['currentHash'] as String,
    );
  }

  /// Memverifikasi integritas log record ini (apakah hash-nya valid).
  bool verifyIntegrity() {
    final dataString = '$previousHash|${timestamp.toIso8601String()}|$action|$details';
    final computedHash = sha256.convert(utf8.encode(dataString)).toString();
    return computedHash == currentHash;
  }
}
