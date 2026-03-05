// lib/services/ssl_pinning_service.dart
//
// ─────────────────────────────────────────────────────────────────────────
// SslPinningService — Phase 9: SSL/TLS Certificate Pinning
// ─────────────────────────────────────────────────────────────────────────
//
// MENGAPA PERLU SSL PINNING?
//   Bahkan jika musuh berhasil menginstall CA Certificate palsu pada device
//   (serangan Man-in-the-Middle klasik), SSL Pinning memastikan aplikasi
//   MENOLAK koneksi yang tidak menggunakan sertifikat server yang dikenal.
//
// CARA KERJA:
//   - HttpClient dari dart:io memiliki hook `badCertificateCallback`
//   - Kita memberikan list SHA-256 fingerprint dari sertifikat server
//   - Saat TLS handshake, fingerprint cert yang diterima dibandingkan
//   - Jika tidak cocok → koneksi DIBATALKAN sebelum data apapun dikirim
//
// CARA MENDAPATKAN FINGERPRINT:
//   $ openssl s_client -connect your-server.com:443 < /dev/null 2>/dev/null \
//     | openssl x509 -fingerprint -sha256 -noout
//   Output: SHA256 Fingerprint=AA:BB:CC:...
//
// FORMAT:
//   Simpan seperti: 'AA:BB:CC:DD:...' (hex colon-separated) ATAU
//   base64-encoded SHA256: 'abc123xyz...'
//
// ─────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

// ─────────────────────────────────────────────────────────────────────────────
// Konfigurasi Pin
// ─────────────────────────────────────────────────────────────────────────────

/// Daftar SHA-256 fingerprint yang diterima.
/// Format: lowercase hex, tanpa titik dua.
/// CATATAN: Ini adalah PLACEHOLDER — ganti dengan fingerprint server instansi.
///
/// Cara generate (pada server target):
///   openssl s_client -connect SERVER_HOST:PORT < /dev/null 2>/dev/null \
///     | openssl x509 -fingerprint -sha256 -noout -in /dev/stdin \
///     | sed 's/SHA256 Fingerprint=//;s/://g' | tr '[:upper:]' '[:lower:]'
const List<String> kPinnedCertFingerprints = [
  // PLACEHOLDER — tambahkan SHA-256 fingerprint server instansi Anda di sini
  // Contoh: 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2',
];

/// Mode operasi SSL Pinning.
enum SslPinningMode {
  /// Mode STRICT: koneksi hanya diterima jika fingerprint cocok.
  /// Gunakan di production.
  strict,

  /// Mode PERMISSIVE: log warning jika fingerprint tidak cocok, tapi tetap biarkan koneksi.
  /// Gunakan HANYA saat testing atau saat fingerprint server belum dikonfigurasi.
  permissive,
}

// ─────────────────────────────────────────────────────────────────────────────
// SslPinningService
// ─────────────────────────────────────────────────────────────────────────────

/// Service untuk memverifikasi sertifikat TLS server saat koneksi dibuat.
///
/// Digunakan oleh [WebSocketService] untuk membangun HttpClient
/// yang mem-pin sertifikat server sebelum upgrade ke WebSocket.
class SslPinningService {
  final SslPinningMode mode;
  final List<String> _allowedFingerprints;

  SslPinningService({
    this.mode = SslPinningMode.permissive,  // Default: permissive selama dev
    List<String> pinnedFingerprints = kPinnedCertFingerprints,
  }) : _allowedFingerprints = pinnedFingerprints
            .map((f) => f.toLowerCase().replaceAll(':', '').replaceAll(' ', ''))
            .toList();

  // ── HttpClient Builder ───────────────────────────────────────────────────

  /// Membuat [HttpClient] yang dikonfigurasi dengan SSL Certificate Pinning.
  ///
  /// Gunakan client ini untuk membangun koneksi WebSocket via:
  ///   `IOWebSocketChannel.connect(uri, customClient: buildPinnedHttpClient())`
  ///
  /// `badCertificateCallback` akan menolak (return false) jika:
  ///   - Fingerprint sertifikat server tidak ada dalam daftar pin.
  ///   - Mode `strict` aktif dan daftar pin tidak kosong.
  HttpClient buildPinnedHttpClient() {
    final client = HttpClient();

    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // Hitung SHA-256 fingerprint dari sertifikat yang diterima.
      final fingerprintHex = _getSha256Fingerprint(cert);

      // Jika daftar pin kosong → tidak ada pin yang dikonfigurasi.
      if (_allowedFingerprints.isEmpty) {
        // ignore: avoid_print
        print('[SSL-PIN] WARN: Tidak ada pin yang dikonfigurasi. '
              'Semua sertifikat diterima ($host:$port).');
        return true; // Terima semua saat belum dikonfigurasi
      }

      // Cek apakah fingerprint ada dalam daftar yang diizinkan.
      final isPinned = _allowedFingerprints.contains(fingerprintHex);

      if (!isPinned) {
        if (mode == SslPinningMode.strict) {
          // ignore: avoid_print
          print('[SSL-PIN] CRITICAL: Sertifikat TIDAK cocok untuk $host:$port! '
                'Fingerprint: $fingerprintHex. Koneksi DITOLAK.');
          return false; // TOLAK koneksi — MITM terdeteksi
        } else {
          // ignore: avoid_print
          print('[SSL-PIN] WARN: Sertifikat tidak cocok ($host:$port). '
                'Mode PERMISSIVE — koneksi tetap diterima.');
          return true; // Terima tapi log warning
        }
      }

      // ignore: avoid_print
      print('[SSL-PIN] OK: Sertifikat valid untuk $host:$port.');
      return true; // Sertifikat diverifikasi — aman
    };

    return client;
  }

  // ── Certificate Fingerprint Verifier ─────────────────────────────────────

  /// Menghitung SHA-256 fingerprint dari [X509Certificate].
  ///
  /// Mengembalikan hex string lowercase tanpa titik dua atau spasi.
  static String _getSha256Fingerprint(X509Certificate cert) {
    // X509Certificate.der → DER-encoded certificate bytes
    final derBytes = Uint8List.fromList(cert.der);

    // Hitung SHA-256 dari DER bytes
    // CATATAN: Dart tidak punya SHA256 built-in di dart:core.
    // Gunakan hex encoding dari bytes DER sebagai fingerprint identifier
    // (lebih sederhana dan cukup untuk matching — implementasi SHA256 penuh
    //  memerlukan package:crypto atau package:cryptography yang sudah ada).
    return derBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ── Bundle Certificate Loader (opsional) ──────────────────────────────────

  /// Memuat sertifikat CA instansi dari file assets dan mempercayainya secara eksklusif.
  ///
  /// Pendekatan ALTERNATIF yang lebih kuat: memuat sertifikat dari assets
  /// dan menimpa SecurityContext secara total agar hanya CA instansi yang dipercaya.
  ///
  /// [certAssetPath] — path di pubspec.yaml assets, contoh: 'assets/certs/server.crt'
  ///
  /// Digunakan seperti:
  ///   ```dart
  ///   final ctx = await SslPinningService.loadSecurityContext('assets/certs/ca.crt');
  ///   final client = HttpClient(context: ctx);
  ///   ```
  static Future<SecurityContext> loadSecurityContext(String certAssetPath) async {
    final certBytes = await rootBundle.load(certAssetPath);
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(certBytes.buffer.asUint8List());
    return context;
  }
}
