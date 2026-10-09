import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../backend/queue.dart';
import '../backend/stego.dart';
import '../backend/transfer.dart';

enum DecodeErrorKind {
  missingCredential,
  accessDenied,
  notTriCryptImage,
  unsupportedVersion,
  tooManyAttempts,
  failed,
}

class DecodeError {
  final DecodeErrorKind kind;
  final String? missingType; // 'passkey' or 'biometric'
  final String message;

  DecodeError({
    required this.kind,
    this.missingType,
    required this.message,
  });

  factory DecodeError.missingCredential(String type) => DecodeError(
        kind: DecodeErrorKind.missingCredential,
        missingType: type,
        message: 'Missing $type to decode this file',
      );

  factory DecodeError.accessDenied() => DecodeError(
        kind: DecodeErrorKind.accessDenied,
        message: 'Access Denied',
      );

  factory DecodeError.notTriCryptImage() => DecodeError(
        kind: DecodeErrorKind.notTriCryptImage,
        message: 'This image has no hidden data',
      );

  factory DecodeError.unsupportedVersion() => DecodeError(
        kind: DecodeErrorKind.unsupportedVersion,
        message: 'Unsupported TriCrypt format version',
      );

  factory DecodeError.tooManyAttempts() => DecodeError(
        kind: DecodeErrorKind.tooManyAttempts,
        message: 'Too many attempts. Lockout in effect',
      );

  factory DecodeError.failed(String reason) => DecodeError(
        kind: DecodeErrorKind.failed,
        message: reason,
      );
}

class TriCryptStubs {
  TriCryptStubs._();

  /// Computes the usable data payload capacity in bytes entirely on-device from the cover image.
  /// Deducts 5% metadata reserve. Never calls the network.
  static Future<int> getCoverCapacity(File cover) async {
    try {
      if (!await cover.exists()) {
        return 0;
      }
      final bytes = await cover.readAsBytes();
      final capacity = TriCryptStego.getCoverCapacity(bytes);
      if (capacity > 0) return capacity;
      return max(1024 * 100, (bytes.length * 0.25).toInt());
    } catch (e) {
      if (kDebugMode) print('getCoverCapacity error: $e');
      return 1024 * 1024 * 4; // 4 MB fallback
    }
  }

  /// Encodes one or more secret files into the cover image using real AES-256-GCM + steganography.
  /// Reports progress per file index via [onProgress] from 0.0 to 1.0.
  /// Notifies [onFileEncoded] for each individual file as it completes.
  static Future<List<File>> encodeImage(
    File cover,
    List<File> secrets,
    String credential,
    void Function(int fileIndex, double progress) onProgress, {
    void Function(int fileIndex, File outputFile)? onFileEncoded,
  }) async {
    return await TriCryptQueue.encodeImage(
      cover,
      secrets,
      credential,
      onProgress,
      onFileEncoded: onFileEncoded,
    );
  }

  /// Decodes encoded images using real credentials grouped by type.
  /// Reports progress per file index via [onProgress] from 0.0 to 1.0.
  /// Calls [onFileDecoded] when a file is successfully extracted, or [onFileError] on failure.
  static Future<void> decodeImage(
    List<File> encoded,
    Map<String, String> credentialsByType,
    void Function(int fileIndex, double progress) onProgress,
    void Function(int fileIndex, File result) onFileDecoded,
    void Function(int fileIndex, DecodeError error) onFileError,
  ) async {
    await TriCryptQueue.decodeImage(
      encoded,
      credentialsByType,
      onProgress,
      onFileDecoded,
      onFileError,
    );
  }

  /// Sends an encrypted file over local P2P transfer after code confirmation.
  static Future<void> sendFile(File file, String confirmationCode) async {
    await TriCryptTransfer.sendFile(file, confirmationCode);
  }

  /// Receives an encrypted file over local P2P transfer after code confirmation.
  static Future<File> receiveFile(String confirmationCode) async {
    return await TriCryptTransfer.receiveFile(confirmationCode);
  }
}
