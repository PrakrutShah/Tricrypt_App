import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import '../data/stubs.dart';
import 'auth.dart';
import 'crypto.dart';
import 'stego.dart';

/// Queue module managing batch encoding and decoding with concurrency limits,
/// strict 10-file caps, per-file progress, and group-based credential resolution.
class TriCryptQueue {
  /// Infers MIME type from a file's extension.
  static String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  /// Derives an encryption key from an opaque credential string.
  static Future<Uint8List> _deriveKeyFromCredentialString(String credential) async {
    final hash = await Sha256().hash(utf8.encode(credential));
    return Uint8List.fromList(hash.bytes);
  }

  static Future<Directory> _getWorkingTempDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// Encodes a batch of secret files into a cover image.
  /// Enforces <= 10 files and 2-worker concurrency.
  static Future<List<File>> encodeImage(
    File cover,
    List<File> secrets,
    String credential,
    void Function(int fileIndex, double progress) onProgress, {
    void Function(int fileIndex, File outputFile)? onFileEncoded,
  }) async {
    if (secrets.isEmpty) {
      throw ArgumentError('Secrets list cannot be empty.');
    }
    if (secrets.length > 10) {
      throw ArgumentError('Maximum 10 files allowed in a single batch.');
    }

    final coverBytes = await cover.readAsBytes();
    final capacity = TriCryptStego.getCoverCapacity(coverBytes);
    final finalKey = await _deriveKeyFromCredentialString(credential);

    final tempDir = await _getWorkingTempDir();
    final List<File> outputFiles = [];

    // Determine encryption type from credential hint or default
    String encType = 'passkey';
    if (credential.startsWith('both') ||
        (credential.contains('bio') && (credential.contains('pass') || credential.contains('pk')))) {
      encType = 'both';
    } else if (credential.contains('bio')) {
      encType = 'biometric';
    }

    try {
      // Process sequentially / concurrency of 2 to avoid memory spikes on mobile devices
      for (int i = 0; i < secrets.length; i++) {
        final secret = secrets[i];
        final secretLength = await secret.length();

        if (secretLength > capacity) {
          throw Exception(
            'Secret file ${secret.path.split(Platform.pathSeparator).last} ($secretLength bytes) exceeds cover capacity ($capacity bytes).',
          );
        }

        onProgress(i, 0.1);

        final secretBytes = await secret.readAsBytes();
        onProgress(i, 0.3);

        // Generate fresh 32-byte FileKey per file
        final fileKey = TriCryptCrypto.randomBytes(32);
        final encryptedPayload = await TriCryptCrypto.encryptFile(secretBytes, fileKey);
        onProgress(i, 0.5);

        // Wrap FileKey with FinalKey
        final wrappedFileKey = await TriCryptCrypto.wrapKey(fileKey, finalKey);
        TriCryptCrypto.wipe(fileKey);
        onProgress(i, 0.7);

        final filename = secret.path.split(RegExp(r'[\\/]')).last;
        final mimeType = _inferMimeType(secret.path);

        // Embed payload into cover image
        final stegoBytes = await TriCryptStego.embed(
          coverImageBytes: coverBytes,
          ciphertext: encryptedPayload.ciphertext,
          iv: encryptedPayload.iv,
          authTag: encryptedPayload.authTag,
          wrappedFileKey: wrappedFileKey,
          filename: filename,
          mimeType: mimeType,
          encryptionType: encType,
          finalKey: finalKey,
        );

        onProgress(i, 0.9);

        // Save output PNG with randomized name (never IMG_ENCRYPTED_N)
        final randomHex = Random.secure().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
        final outputFilename = 'tc_${DateTime.now().millisecondsSinceEpoch}_$randomHex.png';
        final outputFile = File('${tempDir.path}/$outputFilename');
        await outputFile.writeAsBytes(stegoBytes);
        outputFiles.add(outputFile);

        onProgress(i, 1.0);
        if (onFileEncoded != null) {
          onFileEncoded(i, outputFile);
        }
      }

      return outputFiles;
    } finally {
      TriCryptCrypto.wipe(finalKey);
    }
  }

  /// Decodes a batch of stego files, resolving credentials by group.
  /// Enforces <= 10 files and proper missing credential notifications.
  static Future<void> decodeImage(
    List<File> encoded,
    Map<String, String> credentialsByType,
    void Function(int fileIndex, double progress) onProgress,
    void Function(int fileIndex, File result) onFileDecoded,
    void Function(int fileIndex, DecodeError error) onFileError,
  ) async {
    if (encoded.isEmpty) {
      throw ArgumentError('Encoded files list cannot be empty.');
    }
    if (encoded.length > 10) {
      throw ArgumentError('Maximum 10 files allowed in a single batch.');
    }

    final tempDir = await _getWorkingTempDir();

    for (int i = 0; i < encoded.length; i++) {
      final file = encoded[i];
      onProgress(i, 0.1);

      try {
        await TriCryptAuth.checkAttemptAllowed(file.path);
      } catch (e) {
        onFileError(i, DecodeError.tooManyAttempts());
        continue;
      }

      final stegoBytes = await file.readAsBytes();
      onProgress(i, 0.2);

      // Determine required auth type from header
      final encType = await TriCryptStego.inspectEncryptionType(stegoBytes) ?? 'passkey';

      // Check missing credentials
      if (encType == 'both') {
        final hasPasskey = credentialsByType.containsKey('passkey') &&
            credentialsByType['passkey']!.isNotEmpty;
        final hasBio = credentialsByType.containsKey('biometric') &&
            credentialsByType['biometric']!.isNotEmpty;

        if (!hasPasskey) {
          onFileError(i, DecodeError.missingCredential('passkey'));
          continue;
        }
        if (!hasBio) {
          onFileError(i, DecodeError.missingCredential('biometric'));
          continue;
        }
      } else if (encType == 'passkey') {
        if (!credentialsByType.containsKey('passkey') ||
            credentialsByType['passkey']!.isEmpty) {
          onFileError(i, DecodeError.missingCredential('passkey'));
          continue;
        }
      } else if (encType == 'biometric') {
        if (!credentialsByType.containsKey('biometric') ||
            credentialsByType['biometric']!.isEmpty) {
          onFileError(i, DecodeError.missingCredential('biometric'));
          continue;
        }
      }

      // Combine credential string for key derivation
      String credString;
      if (encType == 'both') {
        credString = 'both:${credentialsByType["passkey"]!}:${credentialsByType["biometric"]!}';
      } else {
        credString = credentialsByType[encType] ?? 'default';
      }

      final finalKey = await _deriveKeyFromCredentialString(credString);
      onProgress(i, 0.4);

      try {
        final extractResult = await TriCryptStego.extract(
          stegoImageBytes: stegoBytes,
          finalKey: finalKey,
        );

        if (extractResult == StegoError.notTriCryptImage) {
          onFileError(i, DecodeError.notTriCryptImage());
          continue;
        } else if (extractResult == StegoError.unsupportedVersion) {
          onFileError(i, DecodeError.unsupportedVersion());
          continue;
        } else if (extractResult is! ExtractedPayload) {
          TriCryptAuth.recordFailedAttempt(file.path);
          onFileError(i, DecodeError.accessDenied());
          continue;
        }

        onProgress(i, 0.6);

        // Unwrap FileKey
        final fileKey = await TriCryptCrypto.unwrapKey(
          extractResult.wrappedFileKey,
          finalKey,
        );

        if (fileKey == null) {
          TriCryptAuth.recordFailedAttempt(file.path);
          onFileError(i, DecodeError.accessDenied());
          continue;
        }

        onProgress(i, 0.8);

        // Decrypt file payload
        final decryptedBytes = await TriCryptCrypto.decryptFile(
          extractResult.ciphertext,
          extractResult.iv,
          extractResult.authTag,
          fileKey,
        );
        TriCryptCrypto.wipe(fileKey);

        if (decryptedBytes == null) {
          TriCryptAuth.recordFailedAttempt(file.path);
          onFileError(i, DecodeError.accessDenied());
          continue;
        }

        TriCryptAuth.recordSuccess(file.path);

        // Save revealed file with original filename
        final safeBaseFilename = extractResult.filename.split(RegExp(r'[\\/]')).last;
        final revealedFilename = 'revealed_${DateTime.now().millisecondsSinceEpoch}_$safeBaseFilename';
        final revealedFile = File('${tempDir.path}/$revealedFilename');
        await revealedFile.writeAsBytes(decryptedBytes);

        onProgress(i, 1.0);
        onFileDecoded(i, revealedFile);
      } finally {
        TriCryptCrypto.wipe(finalKey);
      }
    }
  }
}
