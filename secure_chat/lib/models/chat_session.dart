import 'message.dart';

class ChatSession {
  final String id;
  final String title;
  final String targetFingerprint;
  final DateTime createdAt;
  final List<Message> messages;
  final bool isActive; // E2EE session active status

  const ChatSession({
    required this.id,
    required this.title,
    required this.targetFingerprint,
    required this.createdAt,
    this.messages = const [],
    this.isActive = true,
  });

  ChatSession copyWith({
    String? id,
    String? title,
    String? targetFingerprint,
    DateTime? createdAt,
    List<Message>? messages,
    bool? isActive,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      targetFingerprint: targetFingerprint ?? this.targetFingerprint,
      createdAt: createdAt ?? this.createdAt,
      messages: messages ?? this.messages,
      isActive: isActive ?? this.isActive,
    );
  }
}
