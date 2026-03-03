// lib/services/network_proxy_service.dart
//
// Membangun socket TCP yang sudah melewati tunnel proxy (SOCKS5 atau HTTP CONNECT)
// sehingga WebSocketChannel bisa di-wrap di atasnya via IOWebSocketChannel.fromSocket().
//
// Implementasi menggunakan dart:io murni — tidak ada dependency tambahan.
//
// Referensi protokol:
//   SOCKS5: RFC 1928 (https://tools.ietf.org/html/rfc1928)
//   SOCKS5 UserPass auth: RFC 1929
//   HTTP CONNECT: RFC 7231 §4.3.6

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProxyException
// ─────────────────────────────────────────────────────────────────────────────

class ProxyException implements Exception {
  final String message;
  const ProxyException(this.message);

  @override
  String toString() => 'ProxyException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// NetworkProxyService
// ─────────────────────────────────────────────────────────────────────────────

class NetworkProxyService {
  static const Duration _connectTimeout = Duration(seconds: 15);

  /// Membangun koneksi TCP ke [targetHost]:[targetPort], melewati proxy
  /// yang dikonfigurasi di [config].
  ///
  /// Mengembalikan [Socket] yang sudah membentuk tunnel — caller bisa
  /// langsung wrap dengan `IOWebSocketChannel.fromSocket(socket)`.
  Future<Socket> buildSocket({
    required String targetHost,
    required int targetPort,
    required ProxyConfig config,
  }) async {
    switch (config.type) {
      case ProxyType.none:
        return _directConnect(targetHost, targetPort);
      case ProxyType.socks5:
        return _socks5Connect(
          proxyHost: config.host,
          proxyPort: config.port,
          targetHost: targetHost,
          targetPort: targetPort,
          username: config.username,
          password: config.password,
        );
      case ProxyType.http:
        return _httpConnectTunnel(
          proxyHost: config.host,
          proxyPort: config.port,
          targetHost: targetHost,
          targetPort: targetPort,
          username: config.username,
          password: config.password,
        );
    }
  }

  // ── Mode 1: Direct ─────────────────────────────────────────────────────────

  Future<Socket> _directConnect(String host, int port) async {
    debugPrint('[Proxy] Direct → $host:$port');
    return Socket.connect(host, port, timeout: _connectTimeout);
  }

  // ── Mode 2: SOCKS5 (RFC 1928 + RFC 1929) ──────────────────────────────────
  //
  // Handshake (NoAuth path):
  //   C→S: [05 01 00]           greeting (1 method: NoAuth)
  //   S→C: [05 00]              selected NoAuth
  //   C→S: [05 01 00 03 hlen host pHi pLo]  CONNECT
  //   S→C: [05 00 00 atyp ...]  success
  //
  // Handshake (UserPass path, RFC 1929):
  //   C→S: [05 01 02]           greeting (1 method: UserPass)
  //   S→C: [05 02]              selected UserPass
  //   C→S: [01 ulen u... plen p...]
  //   S→C: [01 00]              auth success
  //   ... then CONNECT as above
  //
  Future<Socket> _socks5Connect({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String? username,
    String? password,
  }) async {
    debugPrint('[Proxy] SOCKS5 via $proxyHost:$proxyPort → $targetHost:$targetPort');

    final socket = await Socket.connect(
      proxyHost, proxyPort,
      timeout: _connectTimeout,
    );

    final reader = _SocketReader(socket);

    try {
      final useAuth = username != null && username.isNotEmpty &&
          password != null && password.isNotEmpty;

      // ─ Step 1: Greeting ───────────────────────────────────────────────────
      socket.add(useAuth
          ? [0x05, 0x02, 0x00, 0x02] // offer NoAuth + UserPass
          : [0x05, 0x01, 0x00]);     // offer NoAuth only
      await socket.flush();

      // ─ Step 2: Method selection ───────────────────────────────────────────
      final greeting = await reader.read(2);
      if (greeting[0] != 0x05) {
        throw ProxyException('SOCKS5: unexpected version ${greeting[0]}');
      }
      final method = greeting[1];
      if (method == 0xFF) {
        throw ProxyException('SOCKS5: no acceptable auth method');
      }

      // ─ Step 3: UserPass auth (RFC 1929) ───────────────────────────────────
      if (method == 0x02) {
        if (!useAuth) {
          throw ProxyException('SOCKS5: server requires auth but none provided');
        }
        final uBytes = utf8.encode(username);
        final pBytes = utf8.encode(password);
        socket.add([0x01, uBytes.length, ...uBytes, pBytes.length, ...pBytes]);
        await socket.flush();

        final authReply = await reader.read(2);
        if (authReply[1] != 0x00) {
          throw ProxyException('SOCKS5: auth failed (code ${authReply[1]})');
        }
      } else if (method != 0x00) {
        throw ProxyException('SOCKS5: unsupported method $method');
      }

      // ─ Step 4: CONNECT request ────────────────────────────────────────────
      // [05 01 00 03 hlen host pHi pLo]
      final hostBytes = utf8.encode(targetHost);
      socket.add([
        0x05, 0x01, 0x00,         // VER CMD RSV
        0x03,                      // ATYP=domain
        hostBytes.length,
        ...hostBytes,
        (targetPort >> 8) & 0xFF, // port high byte
        targetPort & 0xFF,        // port low byte
      ]);
      await socket.flush();

      // ─ Step 5: CONNECT reply ──────────────────────────────────────────────
      final reply = await reader.read(4);
      if (reply[0] != 0x05) throw ProxyException('SOCKS5: reply version mismatch');
      if (reply[1] != 0x00) {
        throw ProxyException('SOCKS5 CONNECT: ${_socks5Error(reply[1])}');
      }

      // Drain bind address (we don't use it)
      final atyp = reply[3];
      if (atyp == 0x01) {
        await reader.read(6);  // IPv4(4) + port(2)
      } else if (atyp == 0x03) {
        final len = (await reader.read(1))[0];
        await reader.read(len + 2); // domain + port
      } else if (atyp == 0x04) {
        await reader.read(18); // IPv6(16) + port(2)
      }

      // Flush reader's cached bytes back to socket's incoming stream
      reader.cancel();
      debugPrint('[Proxy] SOCKS5 tunnel open → $targetHost:$targetPort');
      return socket;
    } catch (e) {
      reader.cancel();
      await socket.close();
      rethrow;
    }
  }

  // ── Mode 3: HTTP CONNECT ──────────────────────────────────────────────────
  //
  // C→S: "CONNECT host:port HTTP/1.1\r\nHost: host:port\r\n\r\n"
  // S→C: "HTTP/1.1 200 Connection established\r\n...\r\n\r\n"
  //
  Future<Socket> _httpConnectTunnel({
    required String proxyHost,
    required int proxyPort,
    required String targetHost,
    required int targetPort,
    String? username,
    String? password,
  }) async {
    debugPrint('[Proxy] HTTP CONNECT via $proxyHost:$proxyPort → $targetHost:$targetPort');

    final socket = await Socket.connect(
      proxyHost, proxyPort,
      timeout: _connectTimeout,
    );

    final reader = _SocketReader(socket);

    try {
      final sb = StringBuffer()
        ..write('CONNECT $targetHost:$targetPort HTTP/1.1\r\n')
        ..write('Host: $targetHost:$targetPort\r\n');

      // Proxy-Authorization: Basic (RFC 7235)
      if (username != null && username.isNotEmpty &&
          password != null && password.isNotEmpty) {
        final creds = base64Encode(utf8.encode('$username:$password'));
        sb.write('Proxy-Authorization: Basic $creds\r\n');
      }
      sb.write('\r\n');

      socket.write(sb.toString());
      await socket.flush();

      // Read status line
      final statusLine = await reader.readLine();
      if (!statusLine.contains('200')) {
        throw ProxyException('HTTP CONNECT failed: $statusLine');
      }

      // Drain headers until blank line
      while (true) {
        final line = await reader.readLine();
        if (line.isEmpty) break;
      }

      reader.cancel();
      debugPrint('[Proxy] HTTP CONNECT tunnel open → $targetHost:$targetPort');
      return socket;
    } catch (e) {
      reader.cancel();
      await socket.close();
      rethrow;
    }
  }

  String _socks5Error(int code) {
    const msgs = {
      0x01: 'General failure',
      0x02: 'Connection not allowed',
      0x03: 'Network unreachable',
      0x04: 'Host unreachable',
      0x05: 'Connection refused',
      0x06: 'TTL expired',
      0x07: 'Command not supported',
      0x08: 'Address type not supported',
    };
    return msgs[code] ?? 'Unknown error (0x${code.toRadixString(16)})';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SocketReader — helper membaca byte dari Socket secara berurutan
//
// PENTING: Setelah selesai handshake, panggil cancel() agar subscriber
// tidak menahan socket, lalu socket dapat digunakan langsung oleh
// WebSocketChannel.
// ─────────────────────────────────────────────────────────────────────────────

class _SocketReader {
  final _buffer = <int>[];
  Completer<void>? _waiter;
  late final StreamSubscription<Uint8List> _sub;
  bool _cancelled = false;

  _SocketReader(Socket socket) {
    _sub = socket.listen(
      (data) {
        _buffer.addAll(data);
        if (_waiter != null && !_waiter!.isCompleted) {
          _waiter!.complete();
          _waiter = null;
        }
      },
      onError: (Object e) {
        if (_waiter != null && !_waiter!.isCompleted) {
          _waiter!.completeError(e);
          _waiter = null;
        }
      },
    );
  }

  Future<List<int>> read(int count) async {
    while (_buffer.length < count) {
      if (_cancelled) throw StateError('_SocketReader cancelled');
      _waiter = Completer<void>();
      await _waiter!.future;
    }
    final result = List<int>.from(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }

  Future<String> readLine() async {
    final chars = <int>[];
    while (true) {
      final byte = (await read(1))[0];
      if (byte == 0x0A) break;      // LF
      if (byte != 0x0D) chars.add(byte); // skip CR
    }
    return String.fromCharCodes(chars);
  }

  /// Hentikan subscription — WAJIB dipanggil setelah handshake selesai
  void cancel() {
    _cancelled = true;
    _sub.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final networkProxyServiceProvider = Provider<NetworkProxyService>((ref) {
  return NetworkProxyService();
});
