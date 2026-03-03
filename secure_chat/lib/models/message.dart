// lib/models/message.dart

enum MessageStatus { pending, sent, failed }

class Message {
  final String id;
  final String sessionId; // FK ke ChatSession.id
  final String text;
  final String senderId;
  final DateTime timestamp;
  final bool isEncrypted;      // Status E2EE
  final bool isTerminalCommand; // System messages / command output
  final MessageStatus status;   // Status pengiriman (untuk offline queue)
  final DateTime? expiresAt; // TTL Timestamp untuk pesan Ephemeral

  const Message({
    required this.id,
    required this.sessionId,
    required this.text,
    required this.senderId,
    required this.timestamp,
    this.isEncrypted = true,
    this.isTerminalCommand = false,
    this.status = MessageStatus.sent,
    this.expiresAt,
  });

  Message copyWith({
    String? id,
    String? sessionId,
    String? text,
    String? senderId,
    DateTime? timestamp,
    bool? isEncrypted,
    bool? isTerminalCommand,
    MessageStatus? status,
    DateTime? expiresAt,
  }) {
    return Message(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      text: text ?? this.text,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      isTerminalCommand: isTerminalCommand ?? this.isTerminalCommand,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SQLite Serialization
  // ─────────────────────────────────────────────────────────────────────────

  /// Konversi ke Map untuk disimpan ke dalam database SQLCipher.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'text': text,
      'sender_id': senderId,
      // Simpan sebagai Unix timestamp (milliseconds) untuk efisiensi storage.
      'timestamp_ms': timestamp.millisecondsSinceEpoch,
      // SQLite tidak punya tipe BOOLEAN; gunakan 0/1.
      'is_encrypted': isEncrypted ? 1 : 0,
      'is_terminal_command': isTerminalCommand ? 1 : 0,
      'status': status.index,
      'expires_at_ms': expiresAt?.millisecondsSinceEpoch,
    };
  }

  /// Rekonstruksi dari Map yang diambil dari database.
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      text: map['text'] as String,
      senderId: map['sender_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp_ms'] as int),
      isEncrypted: (map['is_encrypted'] as int) == 1,
      isTerminalCommand: (map['is_terminal_command'] as int) == 1,
      // Default to "sent" (1) if status column is missing (e.g. from old DB versions)
      status: map.containsKey('status')
          ? MessageStatus.values[map['status'] as int]
          : MessageStatus.sent,
      expiresAt: map['expires_at_ms'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at_ms'] as int)
          : null,
    );
  }

  @override
  String toString() =>
      'Message(id: $id, sessionId: $sessionId, senderId: $senderId, '
      'timestamp: $timestamp, isEncrypted: $isEncrypted, status: ${status.name}, '
      'expiresAt: $expiresAt)';
}
