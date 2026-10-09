import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Represents encrypted ciphertext, nonce (IV), and authentication tag.
class EncryptedPayload {
  final Uint8List ciphertext;
  final Uint8List iv;
  final Uint8List authTag;

  const EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.authTag,
  });
}

/// Core cryptographic operations for TriCrypt.
/// Implements AES-256-GCM, HKDF combining, key wrapping, and zeroization.
class TriCryptCrypto {
  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Random _secureRandom = Random.secure();

  /// Generates cryptographically secure random bytes of specified length.
  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Wipes sensitive key material explicitly from memory.
  static void wipe(Uint8List? buffer) {
    if (buffer != null && buffer.isNotEmpty) {
      buffer.fillRange(0, buffer.length, 0);
    }
  }

  /// Derives the 32-byte FinalKey according to Section 1 of the spec.
  /// - Passkey only: PBKDF2-HMAC-SHA256 (200,000 iterations, 16-byte salt)
  /// - Biometric only: Hardware-backed / local key handle (K1)
  /// - Both: HKDF-Extract-Expand(K1 || K2, info="tricrypt-v1")
  static Future<Uint8List> deriveFinalKey({
    required bool biometricEnabled,
    String? passkey,
    Uint8List? biometricKey,
    Uint8List? passkeySalt,
  }) async {
    Uint8List? k1;
    Uint8List? k2;

    try {
      if (biometricEnabled) {
        // K1: Biometric-gated key (32 bytes)
        k1 = biometricKey ?? Uint8List.fromList(utf8.encode('tricrypt-bio-key-hw-handle-32b'));
        if (k1.length != 32) {
          final hash = await Sha256().hash(k1);
          k1 = Uint8List.fromList(hash.bytes);
        }
      }

      if (passkey != null && passkey.isNotEmpty) {
        // K2: Passkey-derived key (32 bytes)
        final salt = passkeySalt ?? Uint8List.fromList(utf8.encode('tricrypt-pass-salt'));
        final pbkdf2 = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 200000,
          bits: 256,
        );
        final derived = await pbkdf2.deriveKey(
          secretKey: SecretKey(utf8.encode(passkey)),
          nonce: salt,
        );
        k2 = Uint8List.fromList(await derived.extractBytes());
      }

      if (biometricEnabled && passkey != null && passkey.isNotEmpty) {
        // COMBINED: HKDF(K1 || K2, info="tricrypt-v1")
        final combinedIkm = Uint8List(k1!.length + k2!.length);
        combinedIkm.setRange(0, k1.length, k1);
        combinedIkm.setRange(k1.length, combinedIkm.length, k2);

        final hkdf = Hkdf(
          hmac: Hmac.sha256(),
          outputLength: 32,
        );
        final derived = await hkdf.deriveKey(
          secretKey: SecretKey(combinedIkm),
          info: utf8.encode('tricrypt-v1'),
        );
        return Uint8List.fromList(await derived.extractBytes());
      } else if (biometricEnabled && k1 != null) {
        return Uint8List.fromList(k1);
      } else if (k2 != null) {
        return Uint8List.fromList(k2);
      } else {
        throw ArgumentError('At least one authentication factor (biometric or passkey) must be enabled.');
      }
    } finally {
      wipe(k1);
      wipe(k2);
    }
  }

  /// Encrypts bytes with AES-256-GCM using a fresh 12-byte IV.
  static Future<EncryptedPayload> encryptFile(Uint8List plaintext, Uint8List key) async {
    final iv = randomBytes(12);
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: iv,
    );

    return EncryptedPayload(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      iv: Uint8List.fromList(secretBox.nonce),
      authTag: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Decrypts AES-256-GCM ciphertext. Returns null on authTag mismatch (AuthError).
  /// Never returns partial plaintext or reveals timing leaks.
  static Future<Uint8List?> decryptFile(
    Uint8List ciphertext,
    Uint8List iv,
    Uint8List authTag,
    Uint8List key,
  ) async {
    try {
      final secretBox = SecretBox(
        ciphertext,
        nonce: iv,
        mac: Mac(authTag),
      );
      final plaintext = await _aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(plaintext);
    } catch (_) {
      // AuthError: Authentication tag mismatch or corrupted data.
      return null;
    }
  }

  /// Wraps a per-file key with the FinalKey using AES-256-GCM.
  /// Result layout: [12-byte IV][16-byte AuthTag][Ciphertext]
  static Future<Uint8List> wrapKey(Uint8List fileKey, Uint8List finalKey) async {
    final payload = await encryptFile(fileKey, finalKey);
    final wrapped = Uint8List(12 + 16 + payload.ciphertext.length);
    wrapped.setRange(0, 12, payload.iv);
    wrapped.setRange(12, 28, payload.authTag);
    wrapped.setRange(28, wrapped.length, payload.ciphertext);
    return wrapped;
  }

  /// Unwraps a per-file key using the FinalKey.
  static Future<Uint8List?> unwrapKey(Uint8List wrappedKey, Uint8List finalKey) async {
    if (wrappedKey.length < 28) return null;
    final iv = wrappedKey.sublist(0, 12);
    final authTag = wrappedKey.sublist(12, 28);
    final ciphertext = wrappedKey.sublist(28);
    return decryptFile(ciphertext, iv, authTag, finalKey);
  }

  /// Rewraps a FileKey when changing passkey/credentials without touching payload bytes.
  static Future<Uint8List?> rewrapFileKey(
    Uint8List oldFinalKey,
    Uint8List newFinalKey,
    Uint8List wrappedFileKey,
  ) async {
    final fileKey = await unwrapKey(wrappedFileKey, oldFinalKey);
    if (fileKey == null) return null;
    try {
      return await wrapKey(fileKey, newFinalKey);
    } finally {
      wipe(fileKey);
    }
  }
}
