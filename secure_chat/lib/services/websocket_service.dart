// lib/services/websocket_service.dart
//
// WebSocket Service dengan ketahanan jaringan tinggi:
//
//  1. EXPONENTIAL BACKOFF RECONNECT
//     Saat terputus, coba sambung ulang dengan delay yang semakin panjang:
//     attempt: 0   1   2   3    4    5+
//     delay:   1s  2s  4s  8s  16s  30s  (capped, dengan ±25% jitter)
//     Reset ke attempt 0 jika koneksi berhasil stabil selama 30 detik.
//
//  2. HEARTBEAT / PING-PONG
//     Timer 20s mengirim '__ping__' ke server.
//     Watchdog dari 10s: jika tidak ada '__pong__' → koneksi zombie → reconnect.
//
//  3. PROXY SUPPORT
//     Jika ProxyConfig aktif, socket dibangun via NetworkProxyService
//     (SOCKS5 RFC 1928 atau HTTP CONNECT) lalu di-upgrade ke WS dengan
//     IOWebSocketChannel.fromSocket().
//
//  4. CONNECTION STATE STREAM
//     UI bisa subscribe ke [connectionStateStream] untuk menampilkan
//     indikator koneksi secara real-time.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/message.dart';
import '../models/proxy_config.dart';
import 'network_proxy_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Konfigurasi konstanta
// ─────────────────────────────────────────────────────────────────────────────

/// Sequence delay backoff dalam detik. Capped di nilai terakhir.
const List<int> _kBackoffDelays = [1, 2, 4, 8, 16, 30];

/// Seberapa lama koneksi harus stabil sebelum backoff counter di-reset.
const Duration _kStableThreshold = Duration(seconds: 30);

/// Interval heartbeat ping ke server.
const Duration _kHeartbeatInterval = Duration(seconds: 20);

/// Timeout menunggu pong. Jika lewat ini, koneksi dianggap zombie.
const Duration _kPongTimeout = Duration(seconds: 10);

/// Sentinel string untuk ping/pong.
const String _kPingPayload = '__ping__';
const String _kPongPayload = '__pong__';

// ─────────────────────────────────────────────────────────────────────────────
// Enum status koneksi
// ─────────────────────────────────────────────────────────────────────────────

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

// ─────────────────────────────────────────────────────────────────────────────
// WebSocketService
// ─────────────────────────────────────────────────────────────────────────────

class WebSocketService {
  final NetworkProxyService _proxyService;

  WebSocketService(this._proxyService);

  // ── Internal state ────────────────────────────────────────────────────────

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;

  /// URL WebSocket yang sedang digunakan (untuk reconnect).
  String? _currentUrl;

  /// Konfigurasi proxy yang digunakan saat ini.
  ProxyConfig _proxyConfig = ProxyConfig.direct;

  /// Nomor percobaan reconnect saat ini (indeks ke _kBackoffDelays).
  int _attempt = 0;

  /// Waktu koneksi pertama kali berhasil (untuk deteksi stabilitas).
  DateTime? _connectedAt;

  /// Timer untuk delay exponential backoff.
  Timer? _reconnectTimer;

  /// Timer heartbeat (ping keluar setiap _kHeartbeatInterval).
  Timer? _heartbeatTimer;

  /// Timer watchdog pong (dibuat sesaat setelah ping, cancel jika pong datang).
  Timer? _pongWatchdog;

  /// True jika pong terakhir sudah diterima.
  bool _pongReceived = false;

  /// Apakah [dispose()] sudah dipanggil.
  bool _disposed = false;

  // ── Streams ────────────────────────────────────────────────────────────────

  final _messageController = StreamController<Message>.broadcast();
  Stream<Message> get messageStream => _messageController.stream;

  final _stateController =
      StreamController<WsConnectionState>.broadcast();
  Stream<WsConnectionState> get connectionStateStream =>
      _stateController.stream;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get currentState => _state;

  bool get isConnected => _state == WsConnectionState.connected;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Mulai koneksi WebSocket ke [url] menggunakan [proxyConfig] yang diberikan.
  ///
  /// Aman dipanggil berkali-kali — panggilan berikutnya akan menggantikan
  /// koneksi yang ada.
  Future<void> connect(String url, {ProxyConfig? proxyConfig}) async {
    if (_disposed) return;

    _currentUrl = url;
    _proxyConfig = proxyConfig ?? ProxyConfig.direct;
    _attempt = 0;

    await _doConnect();
  }

  /// Kirim pesan ke server.
  void sendMessage(String text) {
    if (_channel != null && isConnected) {
      _channel!.sink.add(text);
    } else {
      debugPrint('[WS] Cannot send — not connected');
    }
  }

  /// Perbarui konfigurasi proxy dan reconnect.
  Future<void> updateProxy(ProxyConfig config) async {
    _proxyConfig = config;
    if (_currentUrl != null) {
      _cleanup();
      _attempt = 0;
      await _doConnect();
    }
  }

  /// Tutup semua koneksi dan hentikan timer.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _cleanup();
    _messageController.close();
    _stateController.close();
  }

  // ── Core connection logic ──────────────────────────────────────────────────

  Future<void> _doConnect() async {
    if (_disposed || _currentUrl == null) return;

    _setState(
      _attempt == 0
          ? WsConnectionState.connecting
          : WsConnectionState.reconnecting,
    );

    final url = _currentUrl!;
    final uri = Uri.parse(url);
    final wsHost = uri.host;
    final wsPort = uri.hasPort
        ? uri.port
        : (uri.scheme == 'wss' ? 443 : 80);

    debugPrint(
      '[WS] Connecting (attempt $_attempt) → $url'
      '${_proxyConfig.isEnabled ? " via ${_proxyConfig.type.name.toUpperCase()} ${_proxyConfig.host}:${_proxyConfig.port}" : ""}',
    );

    try {
      WebSocketChannel channel;

      if (_proxyConfig.isEnabled) {
        // ── Proxy path ─────────────────────────────────────────────────────
        // Build tunneled socket, then connect WebSocket over it.
        final tunnelSocket = await _proxyService.buildSocket(
          targetHost: wsHost,
          targetPort: wsPort,
          config: _proxyConfig,
        );

        // Upgrade the tunnel socket to WebSocket by running the HTTP
        // Upgrade handshake manually then wrapping as IOWebSocketChannel.
        final wsFuture = _upgradeSocketToWebSocket(
          socket: tunnelSocket,
          host: wsHost,
          path: uri.path.isEmpty ? '/' : uri.path,
        );
        channel = IOWebSocketChannel(wsFuture);
      } else {
        // ── Direct path ───────────────────────────────────────────────────
        channel = WebSocketChannel.connect(uri);
      }

      // Wait for the handshake to complete (throws on error)
      await channel.ready;

      _channel = channel;
      _connectedAt = DateTime.now();
      _setState(WsConnectionState.connected);
      debugPrint('[WS] Connected ✓');

      // Start heartbeat
      _startHeartbeat();

      // Subscribe to messages
      _channelSub = channel.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  // ── Message handling ───────────────────────────────────────────────────────

  void _onMessage(dynamic data) {
    final text = data.toString();

    // Handle pong heartbeat response
    if (text == _kPongPayload) {
      _pongReceived = true;
      _pongWatchdog?.cancel();
      _pongWatchdog = null;
      return;
    }

    // Handle ping from server (respond with pong)
    if (text == _kPingPayload) {
      _channel?.sink.add(_kPongPayload);
      return;
    }

    // Real message — forward to stream
    _messageController.add(
      Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionId: 'ws_incoming',
        text: text,
        senderId: 'SC',
        timestamp: DateTime.now(),
      ),
    );
  }

  void _onError(Object error) {
    debugPrint('[WS] Stream error: $error');
    _scheduleReconnect();
  }

  void _onDone() {
    if (_disposed) return;
    debugPrint('[WS] Connection closed by server');
    _scheduleReconnect();
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_kHeartbeatInterval, (_) => _sendPing());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongWatchdog?.cancel();
    _pongWatchdog = null;
  }

  void _sendPing() {
    if (!isConnected) return;

    _pongReceived = false;
    _channel?.sink.add(_kPingPayload);

    // Watchdog: if no pong within 10s, consider connection zombie
    _pongWatchdog = Timer(_kPongTimeout, () {
      if (!_pongReceived && !_disposed) {
        debugPrint('[WS] Pong timeout — zombie connection detected, reconnecting');
        _scheduleReconnect();
      }
    });
  }

  // ── Reconnect with exponential backoff + jitter ────────────────────────────

  void _scheduleReconnect() {
    if (_disposed) return;

    _cleanup();
    _setState(WsConnectionState.reconnecting);

    // Reset backoff if previous connection was stable
    final now = DateTime.now();
    if (_connectedAt != null &&
        now.difference(_connectedAt!) >= _kStableThreshold) {
      _attempt = 0;
      debugPrint('[WS] Connection was stable — backoff reset');
    }

    final baseDelay = _kBackoffDelays[_attempt.clamp(0, _kBackoffDelays.length - 1)];

    // Add ±25% jitter to prevent thundering herd when many clients reconnect
    final jitter = (baseDelay * 0.25 * Random().nextDouble() *
        (Random().nextBool() ? 1 : -1));
    final delay = Duration(
      milliseconds: max(500, ((baseDelay + jitter) * 1000).round()),
    );

    if (_attempt < _kBackoffDelays.length - 1) _attempt++;

    debugPrint('[WS] Reconnecting in ${delay.inMilliseconds}ms '
        '(attempt $_attempt, base ${baseDelay}s)');

    _reconnectTimer = Timer(delay, _doConnect);
  }

  // ── Cleanup helpers ────────────────────────────────────────────────────────

  void _cleanup() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _channelSub?.cancel();
    _channelSub = null;

    _channel?.sink.close();
    _channel = null;

    if (!_disposed) _setState(WsConnectionState.disconnected);
  }

  void _setState(WsConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _upgradeSocketToWebSocket — manual WS Upgrade handshake (RFC 6455)
//
// Mengirim HTTP GET Upgrade request secara manual ke atas TCP socket yang
// sudah di-tunnel (dari SOCKS5/HTTP CONNECT proxy), lalu mem-validasi response
// 101 Switching Protocols, lalu menyerahkan socket ke WebSocket.fromUpgradedSocket().
//
// Ini adalah satu-satunya cara yang benar untuk melakukan WS-over-proxy di
// dart:io, karena WebSocket.connect() tidak mendukung pre-built socket.
// ─────────────────────────────────────────────────────────────────────────────

Future<WebSocket> _upgradeSocketToWebSocket({
  required Socket socket,
  required String host,
  required String path,
}) async {
  // Generate random 16-byte Sec-WebSocket-Key (Base64)
  final keyBytes = List.generate(16, (_) => Random().nextInt(256));
  final key = base64Encode(keyBytes);

  // Send HTTP Upgrade request (RFC 6455 §4.1)
  final request = [
    'GET $path HTTP/1.1',
    'Host: $host',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: $key',
    'Sec-WebSocket-Version: 13',
    '',
    '',
  ].join('\r\n');

  socket.write(request);
  await socket.flush();

  // Read response line by line until we get a blank line
  final buffer = StringBuffer();
  final bytes = <int>[];

  await for (final chunk in socket.timeout(const Duration(seconds: 15))) {
    bytes.addAll(chunk);
    // Check for end of headers (double CRLF)
    final s = String.fromCharCodes(bytes);
    if (s.contains('\r\n\r\n')) {
      buffer.write(s.substring(0, s.indexOf('\r\n\r\n')));
      break;
    }
  }

  final statusLine = buffer.toString().split('\r\n').first;
  if (!statusLine.contains('101')) {
    throw ProxyException('WebSocket upgrade failed: $statusLine');
  }

  // Hand off socket to dart:io WebSocket (serverSide:false = client masking)
  return WebSocket.fromUpgradedSocket(socket, serverSide: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final proxyService = ref.watch(networkProxyServiceProvider);
  final service = WebSocketService(proxyService);
  ref.onDispose(service.dispose);
  return service;
});


