import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tricrypt_app/backend/auth.dart';
import 'package:tricrypt_app/backend/crypto.dart';
import 'package:tricrypt_app/backend/stego.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TriCrypt Crypto Module Tests', () {
    test('HKDF combine determinism and isolation', () async {
      final key1 = await TriCryptCrypto.deriveFinalKey(
        biometricEnabled: true,
        passkey: 'SecretPassword123!',
      );
      final key2 = await TriCryptCrypto.deriveFinalKey(
        biometricEnabled: true,
        passkey: 'SecretPassword123!',
      );
      final keyDifferentPasskey = await TriCryptCrypto.deriveFinalKey(
        biometricEnabled: true,
        passkey: 'DifferentPassword456#',
      );

      expect(key1.length, equals(32));
      expect(key1, equals(key2));
      expect(key1, isNot(equals(keyDifferentPasskey)));
    });

    test('AES-256-GCM encrypt and decrypt round trip', () async {
      final key = TriCryptCrypto.randomBytes(32);
      final plaintext = Uint8List.fromList(utf8.encode('Top Secret Classified TriCrypt Data 2026'));

      final encrypted = await TriCryptCrypto.encryptFile(plaintext, key);
      expect(encrypted.ciphertext.length, equals(plaintext.length));
      expect(encrypted.iv.length, equals(12));
      expect(encrypted.authTag.length, equals(16));

      final decrypted = await TriCryptCrypto.decryptFile(
        encrypted.ciphertext,
        encrypted.iv,
        encrypted.authTag,
        key,
      );

      expect(decrypted, isNotNull);
      expect(utf8.decode(decrypted!), equals('Top Secret Classified TriCrypt Data 2026'));

      // AuthTag mismatch returns null (AuthError)
      final corruptedTag = Uint8List.fromList(encrypted.authTag);
      corruptedTag[0] ^= 0xFF;
      final corruptedDecrypted = await TriCryptCrypto.decryptFile(
        encrypted.ciphertext,
        encrypted.iv,
        corruptedTag,
        key,
      );
      expect(corruptedDecrypted, isNull);
    });

    test('Key wrapping and re-wrapping test', () async {
      final fileKey = TriCryptCrypto.randomBytes(32);
      final oldFinalKey = TriCryptCrypto.randomBytes(32);
      final newFinalKey = TriCryptCrypto.randomBytes(32);

      final wrappedKey = await TriCryptCrypto.wrapKey(fileKey, oldFinalKey);
      final unwrappedKey = await TriCryptCrypto.unwrapKey(wrappedKey, oldFinalKey);
      expect(unwrappedKey, equals(fileKey));

      // Rewrap under newFinalKey without accessing payload
      final rewrappedKey = await TriCryptCrypto.rewrapFileKey(oldFinalKey, newFinalKey, wrappedKey);
      expect(rewrappedKey, isNotNull);

      final unwrappedWithNewKey = await TriCryptCrypto.unwrapKey(rewrappedKey!, newFinalKey);
      expect(unwrappedWithNewKey, equals(fileKey));
    });
  });

  group('TriCrypt Steganography Module Tests', () {
    test('Capacity calculation on image bytes', () {
      // Create a test 200x200 RGB image
      final testImage = img.Image(width: 200, height: 200);
      img.fill(testImage, color: img.ColorRgb8(120, 150, 180));
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final capacity = TriCryptStego.getCoverCapacity(pngBytes);
      expect(capacity, greaterThan(0));
    });

    test('Embed and extract round trip with zero data loss', () async {
      final testImage = img.Image(width: 150, height: 150);
      img.fill(testImage, color: img.ColorRgb8(100, 100, 100));
      final coverBytes = Uint8List.fromList(img.encodePng(testImage));

      final finalKey = TriCryptCrypto.randomBytes(32);
      final fileKey = TriCryptCrypto.randomBytes(32);
      final secretBytes = Uint8List.fromList(utf8.encode('Hidden confidential text'));
      final encrypted = await TriCryptCrypto.encryptFile(secretBytes, fileKey);
      final wrappedKey = await TriCryptCrypto.wrapKey(fileKey, finalKey);

      final stegoBytes = await TriCryptStego.embed(
        coverImageBytes: coverBytes,
        ciphertext: encrypted.ciphertext,
        iv: encrypted.iv,
        authTag: encrypted.authTag,
        wrappedFileKey: wrappedKey,
        filename: 'secret.txt',
        mimeType: 'text/plain',
        encryptionType: 'both',
        finalKey: finalKey,
      );

      expect(stegoBytes, isNotEmpty);

      // Extract
      final extracted = await TriCryptStego.extract(
        stegoImageBytes: stegoBytes,
        finalKey: finalKey,
      );

      expect(extracted, isA<ExtractedPayload>());
      final payload = extracted as ExtractedPayload;
      expect(payload.filename, equals('secret.txt'));
      expect(payload.mimeType, equals('text/plain'));
      expect(payload.encryptionType, equals('both'));
      expect(payload.ciphertext, equals(encrypted.ciphertext));

      // Decrypt extracted file
      final unwrappedFileKey = await TriCryptCrypto.unwrapKey(payload.wrappedFileKey, finalKey);
      expect(unwrappedFileKey, equals(fileKey));

      final decrypted = await TriCryptCrypto.decryptFile(
        payload.ciphertext,
        payload.iv,
        payload.authTag,
        unwrappedFileKey!,
      );
      expect(utf8.decode(decrypted!), equals('Hidden confidential text'));
    });
  });

  group('TriCrypt Auth & Recovery Module Tests', () {
    test('12-word recovery seed generation and derivation', () async {
      final seedWords = TriCryptAuth.generateRecoverySeed();
      expect(seedWords.length, equals(12));

      final recoveryKey1 = await TriCryptAuth.deriveKeyFromRecovery(seedWords);
      final recoveryKey2 = await TriCryptAuth.deriveKeyFromRecovery(seedWords);

      expect(recoveryKey1.length, equals(32));
      expect(recoveryKey1, equals(recoveryKey2));
    });

    test('Brute force attempt tracking and lockout', () async {
      const fileId = 'test_file_lockout_1';
      TriCryptAuth.recordSuccess(fileId); // ensure clean

      await expectLater(TriCryptAuth.checkAttemptAllowed(fileId), completes);

      for (int i = 1; i <= 10; i++) {
        TriCryptAuth.recordFailedAttempt(fileId);
      }

      expect(
        () => TriCryptAuth.checkAttemptAllowed(fileId),
        throwsA(isA<TooManyAttemptsException>()),
      );

      // Recovery reset unlocks file
      TriCryptAuth.resetWithRecovery(fileId);
      await expectLater(TriCryptAuth.checkAttemptAllowed(fileId), completes);
    });
  });
}
