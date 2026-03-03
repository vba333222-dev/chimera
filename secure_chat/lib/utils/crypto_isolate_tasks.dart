import 'dart:typed_data';

/// Konfigurasi untuk menampung parameter ke dalam Isolate.
/// Isolate membutuhkan semua data dipassing sebagai satu object atau struktur statik.
class DecryptTaskConfig {
  final Uint8List encryptedBytes;
  final Uint8List key;
  final Uint8List nonce;

  DecryptTaskConfig({
    required this.encryptedBytes,
    required this.key,
    required this.nonce,
  });
}

/// Task murni (top-level function) yang akan dieksekusi oleh Isolate.run()
/// Fungsi ini menyingkirkan komputasi berat dari Main UI Thread ke Background Thread (CPU Thread).
Future<Uint8List> decryptFileBytesTask(DecryptTaskConfig config) async {
  // CATATAN: Dalam implementasi riil produksi, gunakan package cryptography 
  // seperti XChaCha20Poly1305 atau AES-GCM di dalam fungsi ini.
  // 
  // DEMO/MOCK IMPLEMENTATION:
  // Karena ini adalah mock dekripsi sandboxing, kita cukup membuat artificial delay 
  // untuk membuktikan isolasi memori berfungsi tanpa membuat UI nge-hang/stutter,
  // lalu kita kembalikan "Plaintext" byte array.
  
  // Simulasi Dekripsi berat yang memakan waktu lama:
  // Jika ini berjalan di main thread, seluruh animasi UI akan berhenti total selama 2 detik.
  // Dengan Isolate, animasi (seperti circular progress) akan tetap mulus (60 fps).
  await Future.delayed(const Duration(milliseconds: 1500)); 

  // Mengembalikan bytes tiruan (Dalam app nyata: hasil dekripsi AES murni)
  // Untuk demo, kita kembalikan bytes dari PDF dummy jika berformat PDF, 
  // atau Image jika berformat Image (nanti dikoordinasikan oleh SecureDocumentService).
  return config.encryptedBytes; 
}
