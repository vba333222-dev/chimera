class Message {
  final String id;
  final String text;
  final String senderId;
  final DateTime timestamp;
  final bool isEncrypted; // Represents E2EE status
  final bool isTerminalCommand; // Special flag for system messages

  const Message({
    required this.id,
    required this.text,
    required this.senderId,
    required this.timestamp,
    this.isEncrypted = true,
    this.isTerminalCommand = false,
  });

  // For demonstration, easily copy a message
  Message copyWith({
    String? id,
    String? text,
    String? senderId,
    DateTime? timestamp,
    bool? isEncrypted,
    bool? isTerminalCommand,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      senderId: senderId ?? this.senderId,
      timestamp: timestamp ?? this.timestamp,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      isTerminalCommand: isTerminalCommand ?? this.isTerminalCommand,
    );
  }
}
