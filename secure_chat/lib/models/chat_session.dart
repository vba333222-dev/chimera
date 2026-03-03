// lib/models/chat_session.dart

import 'message.dart';

class ChatSession {
  final String id;
  final String title;
  final String targetFingerprint;  // Public key fingerprint lawan bicara
  final String? peerPublicKeyB64;  // Public key peer (Base64) untuk ECDH
  final DateTime createdAt;
  final DateTime? lastMessageAt;   // Untuk sorting di chat list
  final List<Message> messages;    // In-memory only; bukan disimpan di tabel ini
  final bool isActive;             // E2EE session active status

  const ChatSession({
    required this.id,
    required this.title,
    required this.targetFingerprint,
    this.peerPublicKeyB64,
    required this.createdAt,
    this.lastMessageAt,
    this.messages = const [],
    this.isActive = true,
  });

  ChatSession copyWith({
    String? id,
    String? title,
    String? targetFingerprint,
    String? peerPublicKeyB64,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    List<Message>? messages,
    bool? isActive,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      targetFingerprint: targetFingerprint ?? this.targetFingerprint,
      peerPublicKeyB64: peerPublicKeyB64 ?? this.peerPublicKeyB64,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messages: messages ?? this.messages,
      isActive: isActive ?? this.isActive,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SQLite Serialization
  // ─────────────────────────────────────────────────────────────────────────

  /// Konversi ke Map untuk disimpan ke dalam database SQLCipher.
  /// Field [messages] tidak disimpan di sini — disimpan di tabel terpisah.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'target_fingerprint': targetFingerprint,
      'peer_public_key_b64': peerPublicKeyB64,
      'created_at_ms': createdAt.millisecondsSinceEpoch,
      'last_message_at_ms': lastMessageAt?.millisecondsSinceEpoch,
      'is_active': isActive ? 1 : 0,
    };
  }

  /// Rekonstruksi dari Map yang diambil dari database.
  /// Field [messages] dikosongkan karena dimuat terpisah via JOIN / query.
  factory ChatSession.fromMap(Map<String, dynamic> map) {
    return ChatSession(
      id: map['id'] as String,
      title: map['title'] as String,
      targetFingerprint: map['target_fingerprint'] as String,
      peerPublicKeyB64: map['peer_public_key_b64'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at_ms'] as int),
      lastMessageAt: map['last_message_at_ms'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_message_at_ms'] as int)
          : null,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  @override
  String toString() =>
      'ChatSession(id: $id, title: $title, isActive: $isActive, '
      'lastMessageAt: $lastMessageAt)';
}
