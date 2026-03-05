// lib/services/x3dh_service.dart
//
// ─────────────────────────────────────────────────────────────────────────
// X3dhService — Phase 8: Extended Triple Diffie-Hellman (X3DH) Protocol
// ─────────────────────────────────────────────────────────────────────────
//
// PROTOKOL X3DH (Signal Protocol):
//
//   Alice (Sender) ingin memulai sesi E2EE dengan Bob (Receiver).
//   Bob sudah mempublikasikan Prekey Bundle-nya ke server.
//
//   SENDER (Alice):
//     1. Ambil Bundle Bob dari server: [IK_B, SPK_B, OPK_B]
//     2. Generate Ephemeral Key (EK_A) sekali pakai
//     3. Hitung 4 ECDH:
//          DH1 = ECDH(IK_A_private, SPK_B_public)
//          DH2 = ECDH(EK_A_private, IK_B_public)
//          DH3 = ECDH(EK_A_private, SPK_B_public)
//          DH4 = ECDH(EK_A_private, OPK_B_public)  [opsional, jika ada OPK]
//     4. SharedSecret = HKDF(DH1 || DH2 || DH3 || DH4)
//     5. Kirim awal sesi: [IK_A_public, EK_A_public, SPK_B_id, OPK_B_id]
//
//   RECEIVER (Bob):
//     1. Terima pesan awal dari Alice: [IK_A_pub, EK_A_pub, SPK_id, OPK_id]
//     2. Load SPK_B dan OPK_B private keys dari SecureStorage
//     3. Hitung 4 ECDH yang sama (Bob punya private di sisi lain):
//          DH1 = ECDH(SPK_B_private, IK_A_public)
//          DH2 = ECDH(IK_B_private, EK_A_public)
//          DH3 = ECDH(SPK_B_private, EK_A_public)
//          DH4 = ECDH(OPK_B_private, EK_A_public)
//     4. SharedSecret = HKDF(DH1 || DH2 || DH3 || DH4) → IDENTIK dengan Alice
//
//   Hasil: kedua pihak mendapat shared secret 32 bytes yang identik,
//   tanpa server pernah melihat private key siapapun.
//   SharedSecret ini lalu diserahkan ke PfsSessionService.initSession().
//
// ─────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'handshake_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Storage key constants
// ─────────────────────────────────────────────────────────────────────────────

const _kIkPrivKey  = 'chimera_x3dh_ik_private';
const _kIkPubKey   = 'chimera_x3dh_ik_public';
const _kSpkPrivKey = 'chimera_x3dh_spk_private';
const _kSpkPubKey  = 'chimera_x3dh_spk_public';
const _kSpkId      = 'chimera_x3dh_spk_id';
const _kOpkPrivPrefix = 'chimera_x3dh_opk_private_';
const _kOpkPubPrefix  = 'chimera_x3dh_opk_public_';
const _kOpkCounter = 'chimera_x3dh_opk_counter';
const _kMyUserId   = 'chimera_x3dh_my_userid';

/// Berapa OPK yang di-pre-generate saat publish pertama.
const int _kInitialOPKCount = 5;

// ─────────────────────────────────────────────────────────────────────────────
// Data model: SenderHandshakeInfo
// ─────────────────────────────────────────────────────────────────────────────

/// Data yang dikirim oleh SENDER kepada RECEIVER via pesan pembuka sesi.
/// Receiver butuh ini untuk mereplikasi ECDH dan mendapat shared secret yang sama.
class SenderHandshakeInfo {
  /// Public Identity Key pengirim (IK_A).
  final Uint8List identityKeyPublicBytes;

  /// Public Ephemeral Key pengirim (EK_A), sekali pakai untuk sesi ini.
  final Uint8List ephemeralKeyPublicBytes;

  /// ID SPK Bob yang digunakan pengirim (untuk Bob tahu harus pakai SPK private mana).
  final int signedPreKeyId;

  /// ID OPK Bob yang dikonsumsi (null jika tidak ada OPK tersedia saat inisiasi).
  final int? oneTimePreKeyId;

  const SenderHandshakeInfo({
    required this.identityKeyPublicBytes,
    required this.ephemeralKeyPublicBytes,
    required this.signedPreKeyId,
    this.oneTimePreKeyId,
  });

  Map<String, dynamic> toJson() => {
        'ikA': base64Encode(identityKeyPublicBytes),
        'ekA': base64Encode(ephemeralKeyPublicBytes),
        'spkId': signedPreKeyId,
        if (oneTimePreKeyId != null) 'opkId': oneTimePreKeyId,
      };

  factory SenderHandshakeInfo.fromJson(Map<String, dynamic> json) =>
      SenderHandshakeInfo(
        identityKeyPublicBytes: base64Decode(json['ikA'] as String),
        ephemeralKeyPublicBytes: base64Decode(json['ekA'] as String),
        signedPreKeyId: json['spkId'] as int,
        oneTimePreKeyId: json['opkId'] as int?,
      );
}

/// Hasil dari X3DH: shared secret dan info untuk bootstrapping sesi PFS.
class X3dhResult {
  /// 32-byte shared secret yang identik di sender dan receiver.
  final Uint8List sharedSecretBytes;

  /// Identity Key public sender (untuk disimpan oleh receiver sebagai peer key PFS).
  final Uint8List senderIdentityPublicBytes;

  /// Info handshake yang harus dikirim sender ke receiver untuk sesi bootstrap.
  /// Null di sisi receiver (mereka sudah punya semua info).
  final SenderHandshakeInfo? handshakeInfo;

  const X3dhResult({
    required this.sharedSecretBytes,
    required this.senderIdentityPublicBytes,
    this.handshakeInfo,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// X3dhService
// ─────────────────────────────────────────────────────────────────────────────

/// Layanan yang mengimplementasikan protokol X3DH penuh.
///
/// Bergantung pada [HandshakeRepository] sebagai abstraksi server,
/// dan [FlutterSecureStorage] untuk menyimpan private keys secara aman.
class X3dhService {
  final FlutterSecureStorage _storage;
  final HandshakeRepository _repository;

  const X3dhService(this._storage, this._repository);

  // ── Setup: Generate & Publish Prekeys ─────────────────────────────────────

  /// Membuat Identity Key (IK), Signed PreKey (SPK), dan beberapa
  /// One-Time PreKeys (OPK), lalu mempublikasikan bundle ke server.
  ///
  /// Dipanggil satu kali saat pertama login atau saat rotasi SPK.
  /// Aman dipanggil berkali-kali — akan skip jika IK sudah ada.
  Future<void> generateAndPublishPreKeys({
    required String userId,
    bool forceRegenerate = false,
  }) async {
    // Simpan userId
    await _storage.write(key: _kMyUserId, value: userId);

    // Cek apakah IK sudah ada
    final existingIk = await _storage.read(key: _kIkPrivKey);
    if (existingIk != null && !forceRegenerate) {
      // ignore: avoid_print
      print('[X3DH] Prekeys sudah ada untuk user $userId, skip generate.');
      return;
    }

    // ignore: avoid_print
    print('[X3DH] Generating prekey bundle untuk user $userId...');

    final x25519 = X25519();

    // 1. Identity Key (IK) — persisten
    final ikPair = await Isolate.run(() => x25519.newKeyPair());
    final ikPrivBytes = Uint8List.fromList(await ikPair.extractPrivateKeyBytes());
    final ikPubBytes  = Uint8List.fromList((await ikPair.extractPublicKey()).bytes);

    // 2. Signed PreKey (SPK) — dirotasi mingguan
    final spkId = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Unix timestamp sebagai ID
    final spkPair = await Isolate.run(() => x25519.newKeyPair());
    final spkPrivBytes = Uint8List.fromList(await spkPair.extractPrivateKeyBytes());
    final spkPubBytes  = Uint8List.fromList((await spkPair.extractPublicKey()).bytes);

    // 3. One-Time PreKeys (OPK) — satu pakai, 5 pregenerated
    int opkCounter = 0;
    final opkPublicKeysList = <({int id, Uint8List pub})>[];

    for (int i = 0; i < _kInitialOPKCount; i++) {
      final opkId = opkCounter++;
      final opkPair = await Isolate.run(() => x25519.newKeyPair());
      final opkPriv = Uint8List.fromList(await opkPair.extractPrivateKeyBytes());
      final opkPub  = Uint8List.fromList((await opkPair.extractPublicKey()).bytes);

      // Simpan private OPK ke SecureStorage
      await _storage.write(
        key: '$_kOpkPrivPrefix$opkId',
        value: base64Encode(opkPriv),
      );
      await _storage.write(
        key: '$_kOpkPubPrefix$opkId',
        value: base64Encode(opkPub),
      );
      opkPublicKeysList.add((id: opkId, pub: opkPub));
    }

    // Simpan ke SecureStorage
    await Future.wait([
      _storage.write(key: _kIkPrivKey,  value: base64Encode(ikPrivBytes)),
      _storage.write(key: _kIkPubKey,   value: base64Encode(ikPubBytes)),
      _storage.write(key: _kSpkPrivKey, value: base64Encode(spkPrivBytes)),
      _storage.write(key: _kSpkPubKey,  value: base64Encode(spkPubBytes)),
      _storage.write(key: _kSpkId,      value: spkId.toString()),
      _storage.write(key: _kOpkCounter, value: opkCounter.toString()),
    ]);

    // Publikasikan bundle (satu OPK yang pertama tersedia ke server)
    final firstOpk = opkPublicKeysList.first;
    final bundle = PreKeyBundle(
      userId: userId,
      identityKeyPublicBytes: ikPubBytes,
      signedPreKeyPublicBytes: spkPubBytes,
      signedPreKeyId: spkId,
      oneTimePreKeyPublicBytes: firstOpk.pub,
      oneTimePreKeyId: firstOpk.id,
    );

    await _repository.publishPreKeyBundle(bundle);

    // ignore: avoid_print
    print('[X3DH] Prekey bundle published: IK=${_hex(ikPubBytes)}, SPK_id=$spkId, OPKs=${opkPublicKeysList.length}');
  }

  // ── Sender: Inisiasi X3DH ─────────────────────────────────────────────────

  /// Sebagai SENDER: mengambil bundle peer, melakukan X3DH, menghasilkan
  /// `X3dhResult` dengan shared secret dan `SenderHandshakeInfo` untuk
  /// dikirim ke receiver via WebSocket / server.
  ///
  /// [peerUserId] — User ID peer yang ingin dihubungi.
  Future<X3dhResult> initiateSenderX3DH(String peerUserId) async {
    // 1. Ambil bundle peer
    final peerBundle = await _repository.fetchPreKeyBundle(peerUserId);
    if (peerBundle == null) {
      // Fallback: jika peer belum publish prekeys (demo), gunakan test vector
      // ignore: avoid_print
      print('[X3DH] WARN: Prekey bundle peer $peerUserId tidak ditemukan. '
            'Menggunakan demo keys (replace dengan real handshake di produksi).');
      return _buildDemoResult(peerUserId);
    }

    // 2. Load Identity Key (IK_A) kita
    final ikPriv = await _storage.read(key: _kIkPrivKey);
    final ikPub  = await _storage.read(key: _kIkPubKey);
    if (ikPriv == null || ikPub == null) {
      throw StateError('[X3DH] Identity keys tidak ditemukan. '
          'Panggil generateAndPublishPreKeys() terlebih dahulu.');
    }
    final ikAPrivBytes = base64Decode(ikPriv);
    final ikAPubBytes  = base64Decode(ikPub);

    // 3. Generate Ephemeral Key (EK_A) — hanya untuk sesi ini
    final x25519 = X25519();
    final ekPair = await Isolate.run(() => x25519.newKeyPair());
    final ekAPrivBytes = Uint8List.fromList(await ekPair.extractPrivateKeyBytes());
    final ekAPubBytes  = Uint8List.fromList((await ekPair.extractPublicKey()).bytes);

    // 4. Hitung 4 ECDH
    final sharedSecret = await _computeX3dhSecret(
      localIKPriv: ikAPrivBytes,
      localEKPriv: ekAPrivBytes,
      remoteIKPub:  peerBundle.identityKeyPublicBytes,
      remoteSPKPub: peerBundle.signedPreKeyPublicBytes,
      remoteOPKPub: peerBundle.oneTimePreKeyPublicBytes,
    );

    // 5. Konsumsi OPK peer (remove dari server — mock: write ulang tanpa OPK)
    if (peerBundle.oneTimePreKeyPublicBytes != null) {
      await _repository.consumeOneTimePreKey(peerUserId);
    }

    // 6. Zero-wipe ephemeral private key setelah ECDH — tidak perlu lagi
    ekAPrivBytes.fillRange(0, ekAPrivBytes.length, 0);

    // ignore: avoid_print
    print('[X3DH] Sender shared secret derived: ${_hex(sharedSecret)}');

    return X3dhResult(
      sharedSecretBytes: sharedSecret,
      senderIdentityPublicBytes: ikAPubBytes,
      handshakeInfo: SenderHandshakeInfo(
        identityKeyPublicBytes: ikAPubBytes,
        ephemeralKeyPublicBytes: ekAPubBytes,
        signedPreKeyId: peerBundle.signedPreKeyId,
        oneTimePreKeyId: peerBundle.oneTimePreKeyId,
      ),
    );
  }

  // ── Receiver: Complete X3DH ───────────────────────────────────────────────

  /// Sebagai RECEIVER: diberikan `SenderHandshakeInfo` dari sender
  /// (diterima via WebSocket), mereplikasi X3DH, menghasilkan shared secret
  /// yang identik dengan sender.
  ///
  /// Dipanggil saat menerima pesan pembuka sesi baru dari peer.
  Future<X3dhResult> completeReceiverX3DH(
      SenderHandshakeInfo senderInfo) async {
    // 1. Load IK_B private key
    final ikPriv = await _storage.read(key: _kIkPrivKey);
    final ikPub  = await _storage.read(key: _kIkPubKey);
    if (ikPriv == null || ikPub == null) {
      throw StateError('[X3DH] Identity keys tidak ditemukan.');
    }
    final ikBPrivBytes = base64Decode(ikPriv);

    // 2. Load SPK_B private key berdasarkan spkId dari sender
    final spkPriv = await _storage.read(key: _kSpkPrivKey);
    if (spkPriv == null) {
      throw StateError('[X3DH] Signed PreKey tidak ditemukan.');
    }
    final spkBPrivBytes = base64Decode(spkPriv);

    // 3. Load OPK_B private key jika digunakan
    Uint8List? opkBPrivBytes;
    if (senderInfo.oneTimePreKeyId != null) {
      final opkPrivStr = await _storage.read(
        key: '$_kOpkPrivPrefix${senderInfo.oneTimePreKeyId}',
      );
      if (opkPrivStr != null) {
        opkBPrivBytes = base64Decode(opkPrivStr);
        // Hapus OPK private key setelah digunakan (one-time!)
        await _storage.delete(
          key: '$_kOpkPrivPrefix${senderInfo.oneTimePreKeyId}',
        );
        await _storage.delete(
          key: '$_kOpkPubPrefix${senderInfo.oneTimePreKeyId}',
        );
      }
    }

    // 4. Hitung 4 ECDH (peran dibalik dibanding sender)
    final sharedSecret = await _computeReceiverX3dhSecret(
      localIKPriv:    ikBPrivBytes,
      localSPKPriv:   spkBPrivBytes,
      localOPKPriv:   opkBPrivBytes,
      remoteSenderIKPub: senderInfo.identityKeyPublicBytes,
      remoteSenderEKPub: senderInfo.ephemeralKeyPublicBytes,
    );

    // ignore: avoid_print
    print('[X3DH] Receiver shared secret derived: ${_hex(sharedSecret)}');

    return X3dhResult(
      sharedSecretBytes: sharedSecret,
      senderIdentityPublicBytes: senderInfo.identityKeyPublicBytes,
    );
  }

  // ── Private ECDH helpers ──────────────────────────────────────────────────

  /// Menghitung X3DH shared secret dari sisi SENDER.
  /// DH1 || DH2 || DH3 || [DH4] → HKDF → 32-byte secret.
  Future<Uint8List> _computeX3dhSecret({
    required Uint8List localIKPriv,
    required Uint8List localEKPriv,
    required Uint8List remoteIKPub,
    required Uint8List remoteSPKPub,
    Uint8List? remoteOPKPub,
  }) async {
    final x25519 = X25519();

    // DH1 = ECDH(IK_A, SPK_B)
    final dh1 = await _ecdh(x25519, localIKPriv, remoteSPKPub);
    // DH2 = ECDH(EK_A, IK_B)
    final dh2 = await _ecdh(x25519, localEKPriv, remoteIKPub);
    // DH3 = ECDH(EK_A, SPK_B)
    final dh3 = await _ecdh(x25519, localEKPriv, remoteSPKPub);

    final dhConcat = BytesBuilder()
      ..add(dh1)
      ..add(dh2)
      ..add(dh3);

    // DH4 = ECDH(EK_A, OPK_B) [opsional]
    if (remoteOPKPub != null) {
      final dh4 = await _ecdh(x25519, localEKPriv, remoteOPKPub);
      dhConcat.add(dh4);
    }

    return _hkdfDerive(dhConcat.toBytes());
  }

  /// Menghitung X3DH shared secret dari sisi RECEIVER.
  Future<Uint8List> _computeReceiverX3dhSecret({
    required Uint8List localIKPriv,
    required Uint8List localSPKPriv,
    Uint8List? localOPKPriv,
    required Uint8List remoteSenderIKPub,
    required Uint8List remoteSenderEKPub,
  }) async {
    final x25519 = X25519();

    // DH1 = ECDH(SPK_B, IK_A)  [mirror of sender DH1]
    final dh1 = await _ecdh(x25519, localSPKPriv, remoteSenderIKPub);
    // DH2 = ECDH(IK_B, EK_A)   [mirror of sender DH2]
    final dh2 = await _ecdh(x25519, localIKPriv, remoteSenderEKPub);
    // DH3 = ECDH(SPK_B, EK_A)  [mirror of sender DH3]
    final dh3 = await _ecdh(x25519, localSPKPriv, remoteSenderEKPub);

    final dhConcat = BytesBuilder()
      ..add(dh1)
      ..add(dh2)
      ..add(dh3);

    // DH4 = ECDH(OPK_B, EK_A) [opsional, jika OPK digunakan]
    if (localOPKPriv != null) {
      final dh4 = await _ecdh(x25519, localOPKPriv, remoteSenderEKPub);
      dhConcat.add(dh4);
    }

    return _hkdfDerive(dhConcat.toBytes());
  }

  /// Satu ECDH X25519: localPriv × remotePub → shared bytes.
  Future<Uint8List> _ecdh(
    X25519 algo,
    Uint8List localPrivBytes,
    Uint8List remotePubBytes,
  ) async {
    final keyPair = SimpleKeyPairData(
      localPrivBytes,
      publicKey: SimplePublicKey(remotePubBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final remotePub = SimplePublicKey(remotePubBytes, type: KeyPairType.x25519);
    final shared = await algo.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remotePub,
    );
    return Uint8List.fromList(await shared.extractBytes());
  }

  /// HKDF derivasi 32 bytes dari concatenated DH output.
  Future<Uint8List> _hkdfDerive(List<int> ikm) async {
    final hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKeyData(ikm),
      info: 'chimera-x3dh-v1'.codeUnits,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  // ── Demo fallback ─────────────────────────────────────────────────────────

  /// Demo result saat peer belum punya prekeys di server.
  /// Menggunakan IK lokal sebagai placeholder peer key (tidak aman di produksi).
  Future<X3dhResult> _buildDemoResult(String peerUserId) async {
    final ikPub = await _storage.read(key: _kIkPubKey);
    final demoKey = ikPub != null
        ? base64Decode(ikPub)
        : Uint8List(32); // fallback 32-byte nol
    return X3dhResult(
      sharedSecretBytes: demoKey,
      senderIdentityPublicBytes: demoKey,
    );
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Mendapatkan userId lokal yang tersimpan.
  Future<String?> getLocalUserId() => _storage.read(key: _kMyUserId);

  /// Mendapatkan Identity Key Public bytes lokal (untuk dikirim ke peer).
  Future<Uint8List?> getLocalIdentityPublicKey() async {
    final v = await _storage.read(key: _kIkPubKey);
    return v != null ? base64Decode(v) : null;
  }

  /// Hex encoding singkat untuk logging (8 chars pertama).
  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 16);
}
