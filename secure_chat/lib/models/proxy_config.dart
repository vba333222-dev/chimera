// lib/models/proxy_config.dart
//
// Model konfigurasi proxy untuk WebSocket.
// Disimpan terenkripsi di flutter_secure_storage.

import 'dart:convert';

// ─────────────────────────────────────────────────────────────────────────────
// Enum tipe proxy
// ─────────────────────────────────────────────────────────────────────────────

enum ProxyType {
  /// Koneksi langsung — tidak ada proxy.
  none,

  /// SOCKS5 proxy (RFC 1928). Mendukung TCP tunneling.
  /// Digunakan untuk Tor, rotator IP, dll.
  socks5,

  /// HTTP proxy via CONNECT method (RFC 7231).
  /// Server proxy membuka tunnel TCP ke host tujuan.
  http,
}

// ─────────────────────────────────────────────────────────────────────────────
// ProxyConfig
// ─────────────────────────────────────────────────────────────────────────────

class ProxyConfig {
  /// Tipe proxy yang digunakan.
  final ProxyType type;

  /// Hostname atau IP proxy server. Diabaikan jika [type] == none.
  final String host;

  /// Port proxy server. Diabaikan jika [type] == none.
  final int port;

  /// Username untuk autentikasi proxy (opsional).
  final String? username;

  /// Password untuk autentikasi proxy (opsional).
  /// Hanya relevan jika [username] juga diisi.
  final String? password;

  const ProxyConfig({
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  /// Konfigurasi default: koneksi langsung tanpa proxy.
  static const ProxyConfig direct = ProxyConfig(
    type: ProxyType.none,
    host: '',
    port: 0,
  );

  /// Sertakan autentikasi jika username dan password keduanya non-null/non-empty.
  bool get hasAuth =>
      username != null &&
      username!.isNotEmpty &&
      password != null &&
      password!.isNotEmpty;

  /// True jika proxy aktif (type != none).
  bool get isEnabled => type != ProxyType.none;

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'host': host,
        'port': port,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
      };

  factory ProxyConfig.fromJson(Map<String, dynamic> map) {
    final typeName = map['type'] as String? ?? 'none';
    return ProxyConfig(
      type: ProxyType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => ProxyType.none,
      ),
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 0,
      username: map['username'] as String?,
      password: map['password'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static ProxyConfig fromJsonString(String jsonStr) {
    try {
      return ProxyConfig.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
    } catch (_) {
      return ProxyConfig.direct;
    }
  }

  @override
  String toString() {
    if (!isEnabled) return 'ProxyConfig.direct';
    return 'ProxyConfig(${type.name}, $host:$port${hasAuth ? ", auth" : ""})';
  }
}
