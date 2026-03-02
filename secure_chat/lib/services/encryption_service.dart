import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class EncryptionService {
  final FlutterSecureStorage _storage;
  static const String _privateKeyStorageKey = 'chimera_private_key_x25519';
  static const String _publicKeyStorageKey = 'chimera_public_key_x25519';

  EncryptionService(this._storage);

  /// Generates an X25519 key pair for ECDH key agreement.
  /// X25519 is currently widely recommended for secure E2EE chat applications.
  Future<SimpleKeyPair> generateKeyPair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    
    // Extract raw bytes
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;

    // Save to secure local storage (Base64 encoded)
    await _storage.write(
      key: _privateKeyStorageKey,
      value: base64Encode(privateKeyBytes),
    );
    await _storage.write(
      key: _publicKeyStorageKey,
      value: base64Encode(publicKeyBytes),
    );

    return keyPair;
  }

  /// Retrieves the locally stored KeyPair if it exists.
  Future<SimpleKeyPair?> getLocalKeyPair() async {
    final privKeyB64 = await _storage.read(key: _privateKeyStorageKey);
    final pubKeyB64 = await _storage.read(key: _publicKeyStorageKey);

    if (privKeyB64 == null || pubKeyB64 == null) {
      return null;
    }

    try {
      final privateKeyBytes = base64Decode(privKeyB64);
      final publicKeyBytes = base64Decode(pubKeyB64);

      return SimpleKeyPairData(
        privateKeyBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    } catch (e) {
      // In case of parsing error, return null to force regeneration
      return null;
    }
  }

  /// Fetches existing keys, or generates new ones if not found.
  Future<SimpleKeyPair> getOrGenerateKeyPair() async {
    final existingParams = await getLocalKeyPair();
    if (existingParams != null) {
      return existingParams;
    }
    return await generateKeyPair();
  }

  /// Deletes cryptographic material from storage (e.g., on logout or threat detection)
  Future<void> clearKeys() async {
    await _storage.delete(key: _privateKeyStorageKey);
    await _storage.delete(key: _publicKeyStorageKey);
  }
}

// ----------------------------------------------------------------------
// Providers
// ----------------------------------------------------------------------

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return EncryptionService(storage);
});

// A future provider to easily access the key pair asynchronously
final keyPairProvider = FutureProvider<SimpleKeyPair>((ref) async {
  final service = ref.watch(encryptionServiceProvider);
  return await service.getOrGenerateKeyPair();
});
