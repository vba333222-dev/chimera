import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<Message> _messageController = StreamController<Message>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  bool get isConnected => _channel != null;

  void connect(String url) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      _channel!.stream.listen(
        (data) {
          // In a real app, this is where we'd decrypt the incoming data
          // For now, we'll just mock it as a new message
          final msg = Message(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: data.toString(), 
            senderId: 'SC', // Mocking incoming from other user
            timestamp: DateTime.now(),
          );
          _messageController.add(msg);
        },
        onError: (error) {
          print('WebSocket Error: $error');
          _reconnect(url);
        },
        onDone: () {
          print('WebSocket Connection Closed');
          _reconnect(url);
        }
      );
    } catch (e) {
      print('Connection failed: $e');
    }
  }

  void sendMessage(String text) {
    if (_channel != null) {
      // In a real app, encryption Service would be called here before sending
      _channel!.sink.add(text);
    } else {
      print('Cannot send message: WebSocket not connected');
    }
  }

  void _reconnect(String url) {
    // Basic reconnect logic
    Future.delayed(const Duration(seconds: 5), () {
      connect(url);
    });
  }

  void dispose() {
    _channel?.sink.close();
    _messageController.close();
  }
}

// ----------------------------------------------------------------------
// Providers
// ----------------------------------------------------------------------

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
