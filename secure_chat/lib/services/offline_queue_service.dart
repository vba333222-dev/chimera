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
      final pfsService = _ref.read(pfsSessionServiceProvider);
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
          // ── E2EE Re-encryption ─────────────────────────────────────────
          // Sebelum mengirim ulang pesan queue'd saat offline, kita HARUS
          // re-encrypt dengan session key PFS terbaru (bisa sudah di-rotasi).
          //
          // encryptForSession throws StateError jika sesi belum init →
          // artinya ChatRoomScreen belum re-open, skip dan retry nanti.
          String encryptedPayload;
          try {
            final packet = await pfsService.encryptForSession(msg.sessionId, msg.text);
            encryptedPayload = packet.toJson();
          } on StateError catch (e) {
            debugPrint('[OfflineQueue] Sesi ${msg.sessionId} belum aktif: $e. Skip.');
            continue;
          }

          wsService.sendMessage(encryptedPayload);
          
          // Update status menjadi sent
          await db.updateMessageStatus(msg.id, MessageStatus.sent);
          debugPrint('[OfflineQueue] Sent+encrypted pending: ${msg.id}');
          
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
