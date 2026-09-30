import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class TriCryptStubs {
  TriCryptStubs._();

  /// Computes the usable data payload capacity in bytes entirely on-device from the cover image.
  /// Never calls the network.
  static Future<int> getCoverCapacity(File cover) async {
    try {
      if (!await cover.exists()) {
        return 0;
      }
      final int fileLength = await cover.length();
      // In LSB steganography on RGB images (1 bit per color channel):
      // Capacity is roughly 1/8th of raw uncompressed pixel data, which for compressed JPEGs/PNGs
      // is typically 70% to 150% of the compressed file size.
      // We calculate a realistic capacity based on file size.
      final int computedCapacity = max(1024 * 100, (fileLength * 1.25).toInt());
      return computedCapacity;
    } catch (e) {
      if (kDebugMode) print('getCoverCapacity error: $e');
      return 1024 * 1024 * 4; // 4 MB fallback
    }
  }

  /// Encodes one or more secret files into the cover image using the provided credential.
  /// Reports progress per file index via [onProgress] from 0.0 to 1.0.
  static Future<List<File>> encodeImage({
    required File cover,
    required List<File> secrets,
    required String credential,
    required void Function(int fileIndex, double progress) onProgress,
  }) async {
    final List<File> outputFiles = [];
    final Directory dir = await getApplicationDocumentsDirectory();

    for (int i = 0; i < secrets.length; i++) {
      // Simulate encoding process with steps
      for (int step = 1; step <= 10; step++) {
        await Future.delayed(const Duration(milliseconds: 120));
        onProgress(i, step / 10.0);
      }

      final String originalName = secrets[i].path.split(Platform.pathSeparator).last;
      final String baseName = originalName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final String outputPath = '${dir.path}${Platform.pathSeparator}tricrypt_enc_${DateTime.now().millisecondsSinceEpoch}_$baseName.png';

      // For the stub, copy cover to simulate the generated stego image
      final File outFile = await cover.copy(outputPath);
      outputFiles.add(outFile);
    }

    return outputFiles;
  }

  /// Decodes an encrypted image using the credential.
  /// Reports progress via [onProgress] from 0.0 to 1.0.
  static Future<File> decodeImage({
    required File encoded,
    required String credential,
    required void Function(double progress) onProgress,
  }) async {
    // Simulate decryption and LSB extraction
    for (int step = 1; step <= 10; step++) {
      await Future.delayed(const Duration(milliseconds: 150));
      onProgress(step / 10.0);
    }

    final Directory dir = await getApplicationDocumentsDirectory();
    final String outputPath = '${dir.path}${Platform.pathSeparator}tricrypt_dec_${DateTime.now().millisecondsSinceEpoch}.png';

    // Return the extracted secret file
    final File outFile = await encoded.copy(outputPath);
    return outFile;
  }

  /// Sends an encrypted file over local P2P transfer after code confirmation.
  static Future<void> sendFile(File file, String confirmationCode) async {
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  /// Receives an encrypted file over local P2P transfer after code confirmation.
  static Future<File> receiveFile(String confirmationCode) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final Directory dir = await getApplicationDocumentsDirectory();
    final String receivedPath = '${dir.path}${Platform.pathSeparator}tricrypt_rec_${DateTime.now().millisecondsSinceEpoch}.png';
    final File dummy = File(receivedPath);
    await dummy.writeAsBytes(List.generate(1024, (i) => i % 256));
    return dummy;
  }
}
