// lib/services/offline_queue_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class OfflineQueueService {
  final Ref _ref;
  bool _isProcessing = false;
  StreamSubscription<WsConnectionState>? _wsStateSub;

  OfflineQueueService(this._ref) {
    _init();
  }

  void _init() {
    // Listen to WebSocket connection state changes
    final wsService = _ref.read(webSocketServiceProvider);
    _wsStateSub = wsService.connectionStateStream.listen((state) {
      if (state == WsConnectionState.connected) {
        // Connection restored, trigger queue processing
        processQueue();
      }
    });

    // Also trigger immediately on init just in case it's already connected
    if (wsService.isConnected) {
      processQueue();
    }
  }

  void dispose() {
    _wsStateSub?.cancel();
  }

  /// Memproses semua pesan yang berstatus 'pending' di database.
  /// Memastikan sinkronisasi agar tidak terjadi pengiriman ganda.
  Future<void> processQueue() async {
    // Hindari eksekusi paralel jika sedang memproses
    if (_isProcessing) return;

    final wsService = _ref.read(webSocketServiceProvider);
    
    // Jangan proses jika tidak terkoneksi
    if (!wsService.isConnected) return;
    
    // Hard-Stop: Decoy mode is an isolated zone
    if (_ref.read(vaultModeProvider) == VaultMode.decoy) return;

    _isProcessing = true;

    try {
      final db = await _ref.read(chatDatabaseProvider.future);
      final pendingMessages = await db.getPendingMessages();

      if (pendingMessages.isNotEmpty) {
        debugPrint(
            '[OfflineQueue] Processing ${pendingMessages.length} pending messages...');
      }

      for (final msg in pendingMessages) {
        // Cek lagi koneksi di tengah pengiriman
        if (!wsService.isConnected) {
          debugPrint('[OfflineQueue] Connection lost while processing queue. Pausing.');
          break;
        }

        try {
          // TODO: Pada aplikasi e2ee penuh, jika isEncrypted == true, kita 
          // perlu mengambil PfsSessionService dan mengenkripsi ulang teks pesan
          // menggunakan session key yang sedang aktif sebelum mengirim.
          // Untuk versi saat ini, kita anggap wsService.sendMessage akan
          // mengirim teks raw atau teks yang sudah di-handle oleh layer lain.
          // Di arsitektur kita, ChatRoomScreen mengirim command raw ke _sendMessage.
          
          wsService.sendMessage(msg.text);
          
          // Asumsikan terkirim jika tidak ada error dari sendMessage / sink
          await db.updateMessageStatus(msg.id, MessageStatus.sent);
          debugPrint('[OfflineQueue] Sent pending message: ${msg.id}');
          
          // Jeda sedikit agar tidak membanjiri server
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('[OfflineQueue] Error sending message ${msg.id}: $e');
          // Update status menjadi failed (atau biarkan pending untuk di-retry)
          await db.updateMessageStatus(msg.id, MessageStatus.failed);
        }
      }
    } catch (e, st) {
      debugPrint('[OfflineQueue] Failed to process queue: $e\n$st');
    } finally {
      _isProcessing = false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────

final offlineQueueServiceProvider = Provider<OfflineQueueService>((ref) {
  final service = OfflineQueueService(ref);
  ref.onDispose(service.dispose);
  return service;
});
