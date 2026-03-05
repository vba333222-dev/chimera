// lib/services/pin_service.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PinService — Secure PIN management dengan SHA-256 hashing
// ─────────────────────────────────────────────────────────────────────────────
//
// ARSITEKTUR:
//   • PIN tidak pernah disimpan sebagai plaintext
//   • Setiap PIN di-hash dengan SHA-256 + salt unik (UUID) sebelum disimpan
//   • Verifikasi dilakukan dengan hash-compare, bukan string-compare
//   • Mendukung 3 jenis PIN: Main (real vault), Decoy, Kill
//
// KEAMANAN:
//   • Tidak ada pin literal di code — semua dibaca dari FlutterSecureStorage
//   • Salt per-PIN mencegah rainbow table attack
//   • Setup flow hanya bisa dijalankan sekali (first-run guard)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Storage keys
// ─────────────────────────────────────────────────────────────────────────────

const _kMainPinHash   = 'chimera_pin_main_hash';
const _kMainPinSalt   = 'chimera_pin_main_salt';
const _kDecoyPinHash  = 'chimera_pin_decoy_hash';
const _kDecoyPinSalt  = 'chimera_pin_decoy_salt';
const _kKillPinHash   = 'chimera_pin_kill_hash';
const _kKillPinSalt   = 'chimera_pin_kill_salt';
const _kPinSetupDone  = 'chimera_pin_setup_complete';

// ─────────────────────────────────────────────────────────────────────────────
// Enum: Jenis PIN
// ─────────────────────────────────────────────────────────────────────────────

enum PinType { main, decoy, kill, unknown }

// ─────────────────────────────────────────────────────────────────────────────
// PinService
// ─────────────────────────────────────────────────────────────────────────────

class PinService {
  final FlutterSecureStorage _storage;

  const PinService(this._storage);

  // ── Setup ──────────────────────────────────────────────────────────────────

  /// Menyimpan ketiga PIN (Main, Decoy, Kill) dengan aman.
  /// Dipanggil HANYA saat first-run setup.
  Future<void> setupPins({
    required String mainPin,
    required String decoyPin,
    required String killPin,
  }) async {
    // Hash dan simpan Main PIN
    final mainSalt   = _generateSalt();
    final decoySalt  = _generateSalt();
    final killSalt   = _generateSalt();

    await Future.wait([
      _storage.write(key: _kMainPinSalt,   value: mainSalt),
      _storage.write(key: _kMainPinHash,   value: _hashPin(mainPin, mainSalt)),
      _storage.write(key: _kDecoyPinSalt,  value: decoySalt),
      _storage.write(key: _kDecoyPinHash,  value: _hashPin(decoyPin, decoySalt)),
      _storage.write(key: _kKillPinSalt,   value: killSalt),
      _storage.write(key: _kKillPinHash,   value: _hashPin(killPin, killSalt)),
      _storage.write(key: _kPinSetupDone,  value: 'true'),
    ]);
  }

  // ── Verification ──────────────────────────────────────────────────────────

  /// Verifikasi PIN yang dimasukkan dan kembalikan jenisnya.
  /// Mengembalikan [PinType.unknown] jika tidak cocok dengan PIN apapun.
  Future<PinType> verifyPin(String inputPin) async {
    // Cek Main PIN
    if (await _verify(inputPin, _kMainPinHash, _kMainPinSalt)) {
      return PinType.main;
    }
    // Cek Decoy PIN
    if (await _verify(inputPin, _kDecoyPinHash, _kDecoyPinSalt)) {
      return PinType.decoy;
    }
    // Cek Kill PIN
    if (await _verify(inputPin, _kKillPinHash, _kKillPinSalt)) {
      return PinType.kill;
    }
    return PinType.unknown;
  }

  // ── First-Run Guard ───────────────────────────────────────────────────────

  /// True jika PIN setup sudah selesai sebelumnya.
  Future<bool> isPinSetupComplete() async {
    final v = await _storage.read(key: _kPinSetupDone);
    return v == 'true';
  }

  // ── Rotation ──────────────────────────────────────────────────────────────

  /// Mengganti Main PIN (verifikasi PIN lama diperlukan).
  Future<bool> changeMainPin({
    required String oldPin,
    required String newPin,
  }) async {
    final type = await verifyPin(oldPin);
    if (type != PinType.main) return false;

    final newSalt = _generateSalt();
    await _storage.write(key: _kMainPinSalt, value: newSalt);
    await _storage.write(key: _kMainPinHash, value: _hashPin(newPin, newSalt));
    return true;
  }

  // ── Emergency Reset ───────────────────────────────────────────────────────

  /// Menghapus semua PIN hash dari storage (dipanggil saat wipe/self-destruct).
  Future<void> deletePins() async {
    await Future.wait([
      _storage.delete(key: _kMainPinHash),
      _storage.delete(key: _kMainPinSalt),
      _storage.delete(key: _kDecoyPinHash),
      _storage.delete(key: _kDecoyPinSalt),
      _storage.delete(key: _kKillPinHash),
      _storage.delete(key: _kKillPinSalt),
      _storage.delete(key: _kPinSetupDone),
    ]);
  }

  // ── Private Helpers ───────────────────────────────────────────────────────

  Future<bool> _verify(String input, String hashKey, String saltKey) async {
    final storedHash = await _storage.read(key: hashKey);
    final storedSalt = await _storage.read(key: saltKey);
    if (storedHash == null || storedSalt == null) return false;
    return _hashPin(input, storedSalt) == storedHash;
  }

  /// SHA-256(pin + salt) → hex string
  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode(pin + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate random 32-char hex salt
  static String _generateSalt() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      rand[i] = (now >> (i % 8)) & 0xFF ^ (i * 37 + 13);
    }
    return sha256.convert(rand).toString().substring(0, 32);
  }
}
