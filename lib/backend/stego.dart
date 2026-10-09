import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;

/// Errors that can occur during steganography extraction.
enum StegoError {
  notTriCryptImage,
  unsupportedVersion,
  corruptedHeader,
  payloadExtractionFailed,
}

/// Extracted metadata and ciphertext payload from a stego image.
class ExtractedPayload {
  final Uint8List ciphertext;
  final Uint8List iv;
  final Uint8List authTag;
  final Uint8List wrappedFileKey;
  final String filename;
  final String mimeType;
  final String encryptionType; // "passkey", "biometric", "both"

  const ExtractedPayload({
    required this.ciphertext,
    required this.iv,
    required this.authTag,
    required this.wrappedFileKey,
    required this.filename,
    required this.mimeType,
    required this.encryptionType,
  });
}

/// Steganography Engine implementing adaptive, PRNG-scattered embedding
/// and capacity calculation over DCT/pixel blocks with "TCv1" format header.
class TriCryptStego {
  static const List<int> magicBytes = [0x54, 0x43, 0x76, 0x31]; // "TCv1"
  static const int currentVersion = 1;

  // Number of fixed pixels reserved at the beginning for the unencrypted header:
  // 6 bytes = 48 bits. With 4 bits per pixel (2 in Red, 2 in Green), exactly 12 pixels.
  static const int fixedHeaderBytes = 6;
  static const int fixedHeaderPixels = 12;

  /// Calculates usable capacity in bytes for a cover image.
  /// Deducts 5% reserved space for metadata header (IV, authTag, filename, etc.).
  static int getCoverCapacity(Uint8List coverImageBytes) {
    try {
      final image = img.decodeImage(coverImageBytes);
      if (image == null) {
        final fallback = (coverImageBytes.length * 0.25).toInt();
        return (fallback * 0.95).toInt();
      }

      final int width = image.width;
      final int height = image.height;
      final int numChannels = image.numChannels >= 3 ? 3 : image.numChannels;

      // Approximately 2 usable bits per channel per pixel
      final int totalUsableBits = width * height * numChannels * 2;
      final int totalUsableBytes = totalUsableBits ~/ 8;

      // Reserve 5% for metadata (IV, authTag, filename, MIME type, version header)
      final int capacityAfterReserve = (totalUsableBytes * 0.95).toInt();
      return capacityAfterReserve > 0 ? capacityAfterReserve : 0;
    } catch (_) {
      return (coverImageBytes.length * 0.20).toInt();
    }
  }

  /// Derives a 32-bit integer seed from FinalKey using HKDF for deterministic scattering.
  static Future<int> _deriveScatterSeed(Uint8List finalKey) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 4,
    );
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(finalKey),
      info: utf8.encode('embed-order'),
    );
    final seedBytes = await derived.extractBytes();
    final byteData = ByteData.sublistView(Uint8List.fromList(seedBytes));
    return byteData.getUint32(0);
  }

  /// Serializes the container stream:
  /// Bytes 0..5 (fixed): [magic: 4B][version: 1B][encType: 1B]
  /// Bytes 6..end (scattered): [wrappedKeyLen: 2B][wrappedKey][payloadLen: 4B][iv: 12B][authTag: 16B]
  ///                           [mimeLen: 1B][mimeType][fileLen: 2B][filename][payload]
  static Uint8List _buildContainerStream({
    required Uint8List ciphertext,
    required Uint8List iv,
    required Uint8List authTag,
    required Uint8List wrappedFileKey,
    required String filename,
    required String mimeType,
    required String encryptionType,
  }) {
    final encTypeByte = encryptionType == 'passkey'
        ? 0
        : (encryptionType == 'biometric' ? 1 : 2);

    final mimeBytes = utf8.encode(mimeType);
    final filenameBytes = utf8.encode(filename);

    final totalSize = 4 + 1 + 1 +
        2 + wrappedFileKey.length +
        4 + 12 + 16 +
        1 + mimeBytes.length +
        2 + filenameBytes.length +
        ciphertext.length;

    final buffer = Uint8List(totalSize);
    final bd = ByteData.sublistView(buffer);
    int offset = 0;

    // Fixed Header: "TCv1" + version (0x01) + encType (0, 1, or 2)
    buffer.setRange(offset, offset + 4, magicBytes);
    offset += 4;
    buffer[offset] = currentVersion;
    offset += 1;
    buffer[offset] = encTypeByte;
    offset += 1;

    // Remaining Data (scattered by FinalKey):
    bd.setUint16(offset, wrappedFileKey.length);
    offset += 2;
    buffer.setRange(offset, offset + wrappedFileKey.length, wrappedFileKey);
    offset += wrappedFileKey.length;

    bd.setUint32(offset, ciphertext.length);
    offset += 4;

    buffer.setRange(offset, offset + 12, iv);
    offset += 12;

    buffer.setRange(offset, offset + 16, authTag);
    offset += 16;

    buffer[offset] = mimeBytes.length;
    offset += 1;
    buffer.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;

    bd.setUint16(offset, filenameBytes.length);
    offset += 2;
    buffer.setRange(offset, offset + filenameBytes.length, filenameBytes);
    offset += filenameBytes.length;

    buffer.setRange(offset, offset + ciphertext.length, ciphertext);
    offset += ciphertext.length;

    return buffer;
  }

  /// Embeds the encrypted payload into cover image bytes.
  /// First 6 bytes are written to fixed pixels 0..11.
  /// Remaining bytes are scattered using PRNG seeded by FinalKey.
  /// Output is ALWAYS a lossless PNG image.
  static Future<Uint8List> embed({
    required Uint8List coverImageBytes,
    required Uint8List ciphertext,
    required Uint8List iv,
    required Uint8List authTag,
    required Uint8List wrappedFileKey,
    required String filename,
    required String mimeType,
    required String encryptionType,
    required Uint8List finalKey,
  }) async {
    final image = img.decodeImage(coverImageBytes);
    if (image == null) {
      throw ArgumentError('Unable to decode cover image.');
    }

    final containerData = _buildContainerStream(
      ciphertext: ciphertext,
      iv: iv,
      authTag: authTag,
      wrappedFileKey: wrappedFileKey,
      filename: filename,
      mimeType: mimeType,
      encryptionType: encryptionType,
    );

    final int totalPixels = image.width * image.height;
    if (totalPixels <= fixedHeaderPixels) {
      throw ArgumentError('Cover image is too small.');
    }

    final int remainingBytes = containerData.length - fixedHeaderBytes;
    final int requiredBits = remainingBytes * 8;
    final int requiredPixels = (requiredBits + 3) ~/ 4;

    if (fixedHeaderPixels + requiredPixels > totalPixels) {
      throw ArgumentError(
        'Cover image capacity is insufficient for the encrypted payload and header.',
      );
    }

    // 1. Embed fixed header (first 6 bytes) into first 12 pixels sequentially
    int headerByteIdx = 0;
    int headerBitIdx = 0;

    for (int p = 0; p < fixedHeaderPixels && headerByteIdx < fixedHeaderBytes; p++) {
      final x = p % image.width;
      final y = p ~/ image.width;
      final pixel = image.getPixel(x, y);

      int r = pixel.r.toInt();
      int g = pixel.g.toInt();

      // Red channel: 2 bits
      final b0 = (containerData[headerByteIdx] >> (7 - headerBitIdx)) & 1;
      headerBitIdx++;
      if (headerBitIdx == 8) {
        headerBitIdx = 0;
        headerByteIdx++;
      }

      int b1 = 0;
      if (headerByteIdx < fixedHeaderBytes) {
        b1 = (containerData[headerByteIdx] >> (7 - headerBitIdx)) & 1;
        headerBitIdx++;
        if (headerBitIdx == 8) {
          headerBitIdx = 0;
          headerByteIdx++;
        }
      }
      r = (r & ~0x03) | (b0 << 1) | b1;

      // Green channel: 2 bits
      int b2 = 0;
      if (headerByteIdx < fixedHeaderBytes) {
        b2 = (containerData[headerByteIdx] >> (7 - headerBitIdx)) & 1;
        headerBitIdx++;
        if (headerBitIdx == 8) {
          headerBitIdx = 0;
          headerByteIdx++;
        }
      }

      int b3 = 0;
      if (headerByteIdx < fixedHeaderBytes) {
        b3 = (containerData[headerByteIdx] >> (7 - headerBitIdx)) & 1;
        headerBitIdx++;
        if (headerBitIdx == 8) {
          headerBitIdx = 0;
          headerByteIdx++;
        }
      }
      g = (g & ~0x03) | (b2 << 1) | b3;

      image.setPixelRgba(x, y, r, g, pixel.b.toInt(), pixel.a.toInt());
    }

    // 2. Embed remaining data into scattered pixels (starting at index 12)
    final seed = await _deriveScatterSeed(finalKey);
    final prng = _SimplePRNG(seed);
    final int scatterPixelCount = totalPixels - fixedHeaderPixels;
    final permutation = _generatePermutation(scatterPixelCount, prng);

    int dataByteIdx = fixedHeaderBytes;
    int dataBitIdx = 0;

    for (int i = 0; i < scatterPixelCount && dataByteIdx < containerData.length; i++) {
      final actualPixelIdx = fixedHeaderPixels + permutation[i];
      final x = actualPixelIdx % image.width;
      final y = actualPixelIdx ~/ image.width;
      final pixel = image.getPixel(x, y);

      int r = pixel.r.toInt();
      int g = pixel.g.toInt();

      // Red channel: 2 bits
      if (dataByteIdx < containerData.length) {
        final b0 = (containerData[dataByteIdx] >> (7 - dataBitIdx)) & 1;
        dataBitIdx++;
        if (dataBitIdx == 8) {
          dataBitIdx = 0;
          dataByteIdx++;
        }

        int b1 = 0;
        if (dataByteIdx < containerData.length) {
          b1 = (containerData[dataByteIdx] >> (7 - dataBitIdx)) & 1;
          dataBitIdx++;
          if (dataBitIdx == 8) {
            dataBitIdx = 0;
            dataByteIdx++;
          }
        }
        r = (r & ~0x03) | (b0 << 1) | b1;
      }

      // Green channel: 2 bits
      if (dataByteIdx < containerData.length) {
        final b2 = (containerData[dataByteIdx] >> (7 - dataBitIdx)) & 1;
        dataBitIdx++;
        if (dataBitIdx == 8) {
          dataBitIdx = 0;
          dataByteIdx++;
        }

        int b3 = 0;
        if (dataByteIdx < containerData.length) {
          b3 = (containerData[dataByteIdx] >> (7 - dataBitIdx)) & 1;
          dataBitIdx++;
          if (dataBitIdx == 8) {
            dataBitIdx = 0;
            dataByteIdx++;
          }
        }
        g = (g & ~0x03) | (b2 << 1) | b3;
      }

      image.setPixelRgba(x, y, r, g, pixel.b.toInt(), pixel.a.toInt());
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Quickly inspects whether an image is a TriCrypt container and returns its encryption type.
  /// Reads only the first 12 pixels without requiring the key.
  static Future<String?> inspectEncryptionType(Uint8List stegoImageBytes) async {
    try {
      final image = img.decodeImage(stegoImageBytes);
      if (image == null || (image.width * image.height) < fixedHeaderPixels) {
        return null;
      }

      final header = _readFixedHeader(image);
      if (header == null) return null;

      final int encType = header[5];
      return encType == 0 ? 'passkey' : (encType == 1 ? 'biometric' : 'both');
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _readFixedHeader(img.Image image) {
    final bytes = Uint8List(fixedHeaderBytes);
    int byteIdx = 0;
    int bitIdx = 0;
    int currentByte = 0;

    for (int p = 0; p < fixedHeaderPixels && byteIdx < fixedHeaderBytes; p++) {
      final x = p % image.width;
      final y = p ~/ image.width;
      final pixel = image.getPixel(x, y);

      final r = pixel.r.toInt();
      final g = pixel.g.toInt();

      final bits = [(r >> 1) & 1, r & 1, (g >> 1) & 1, g & 1];
      for (final b in bits) {
        currentByte = (currentByte << 1) | b;
        bitIdx++;
        if (bitIdx == 8) {
          bytes[byteIdx++] = currentByte;
          bitIdx = 0;
          currentByte = 0;
          if (byteIdx >= fixedHeaderBytes) break;
        }
      }
    }

    if (bytes[0] == magicBytes[0] &&
        bytes[1] == magicBytes[1] &&
        bytes[2] == magicBytes[2] &&
        bytes[3] == magicBytes[3]) {
      return bytes;
    }
    return null;
  }

  /// Extracts the TriCrypt container from stego image bytes using the FinalKey.
  static Future<dynamic> extract({
    required Uint8List stegoImageBytes,
    required Uint8List finalKey,
  }) async {
    final image = img.decodeImage(stegoImageBytes);
    if (image == null || (image.width * image.height) < fixedHeaderPixels) {
      return StegoError.notTriCryptImage;
    }

    // 1. Read fixed header
    final header = _readFixedHeader(image);
    if (header == null) {
      return StegoError.notTriCryptImage;
    }

    final int version = header[4];
    if (version != currentVersion) {
      return StegoError.unsupportedVersion;
    }

    final int encTypeByte = header[5];
    final String encryptionType = encTypeByte == 0
        ? 'passkey'
        : (encTypeByte == 1 ? 'biometric' : 'both');

    // 2. Read scattered data
    final totalPixels = image.width * image.height;
    final scatterPixelCount = totalPixels - fixedHeaderPixels;
    final seed = await _deriveScatterSeed(finalKey);
    final prng = _SimplePRNG(seed);
    final permutation = _generatePermutation(scatterPixelCount, prng);

    // Initial inspection buffer to read wrappedKeyLen and payloadLen
    final inspectBytes = Uint8List(1024);
    int extractedByteIdx = 0;
    int currentBitIdx = 0;
    int currentByteVal = 0;

    void addBit(int bit) {
      currentByteVal = (currentByteVal << 1) | (bit & 1);
      currentBitIdx++;
      if (currentBitIdx == 8) {
        if (extractedByteIdx < inspectBytes.length) {
          inspectBytes[extractedByteIdx] = currentByteVal;
          extractedByteIdx++;
        }
        currentBitIdx = 0;
        currentByteVal = 0;
      }
    }

    int px = 0;
    while (px < scatterPixelCount && extractedByteIdx < 40) {
      final actualIdx = fixedHeaderPixels + permutation[px];
      final x = actualIdx % image.width;
      final y = actualIdx ~/ image.width;
      final pixel = image.getPixel(x, y);

      final r = pixel.r.toInt();
      final g = pixel.g.toInt();

      addBit((r >> 1) & 1);
      addBit(r & 1);
      addBit((g >> 1) & 1);
      addBit(g & 1);
      px++;
    }

    try {
      final bd = ByteData.sublistView(inspectBytes);
      final int wrappedKeyLen = bd.getUint16(0);
      final int payloadLenOffset = 2 + wrappedKeyLen;

      // Extract more if needed to reach payload length
      while (px < scatterPixelCount && extractedByteIdx < payloadLenOffset + 4) {
        final actualIdx = fixedHeaderPixels + permutation[px];
        final x = actualIdx % image.width;
        final y = actualIdx ~/ image.width;
        final pixel = image.getPixel(x, y);

        addBit((pixel.r.toInt() >> 1) & 1);
        addBit(pixel.r.toInt() & 1);
        addBit((pixel.g.toInt() >> 1) & 1);
        addBit(pixel.g.toInt() & 1);
        px++;
      }

      final int payloadLen = bd.getUint32(payloadLenOffset);
      final int estimatedTotal = payloadLenOffset + 4 + 12 + 16 + 1 + 256 + 2 + 512 + payloadLen;

      final streamBuffer = Uint8List(estimatedTotal);
      streamBuffer.setRange(0, extractedByteIdx, inspectBytes.sublist(0, extractedByteIdx));

      int streamByteIdx = extractedByteIdx;
      currentBitIdx = 0;
      currentByteVal = 0;

      void addStreamBit(int bit) {
        currentByteVal = (currentByteVal << 1) | (bit & 1);
        currentBitIdx++;
        if (currentBitIdx == 8) {
          if (streamByteIdx < streamBuffer.length) {
            streamBuffer[streamByteIdx] = currentByteVal;
            streamByteIdx++;
          }
          currentBitIdx = 0;
          currentByteVal = 0;
        }
      }

      while (px < scatterPixelCount && streamByteIdx < streamBuffer.length) {
        final actualIdx = fixedHeaderPixels + permutation[px];
        final x = actualIdx % image.width;
        final y = actualIdx ~/ image.width;
        final pixel = image.getPixel(x, y);

        addStreamBit((pixel.r.toInt() >> 1) & 1);
        addStreamBit(pixel.r.toInt() & 1);
        addStreamBit((pixel.g.toInt() >> 1) & 1);
        addStreamBit(pixel.g.toInt() & 1);
        px++;
      }

      final streamBd = ByteData.sublistView(streamBuffer);
      int offset = 0;
      final wKeyLen = streamBd.getUint16(offset);
      offset += 2;

      final wrappedFileKey = streamBuffer.sublist(offset, offset + wKeyLen);
      offset += wKeyLen;

      final pLen = streamBd.getUint32(offset);
      offset += 4;

      final iv = streamBuffer.sublist(offset, offset + 12);
      offset += 12;

      final authTag = streamBuffer.sublist(offset, offset + 16);
      offset += 16;

      final mimeLen = streamBuffer[offset];
      offset += 1;
      final mimeType = utf8.decode(streamBuffer.sublist(offset, offset + mimeLen));
      offset += mimeLen;

      final fileLen = streamBd.getUint16(offset);
      offset += 2;
      final filename = utf8.decode(streamBuffer.sublist(offset, offset + fileLen));
      offset += fileLen;

      final ciphertext = streamBuffer.sublist(offset, offset + pLen);

      return ExtractedPayload(
        ciphertext: ciphertext,
        iv: iv,
        authTag: authTag,
        wrappedFileKey: wrappedFileKey,
        filename: filename,
        mimeType: mimeType,
        encryptionType: encryptionType,
      );
    } catch (_) {
      return StegoError.corruptedHeader;
    }
  }

  static List<int> _generatePermutation(int count, _SimplePRNG prng) {
    final list = List<int>.generate(count, (i) => i);
    for (int i = count - 1; i > 0; i--) {
      final j = prng.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
    return list;
  }
}

class _SimplePRNG {
  int _state;

  _SimplePRNG(int seed) : _state = seed == 0 ? 0x12345678 : seed;

  int nextUint32() {
    int x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= (x >> 17) & 0xFFFFFFFF;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  int nextInt(int max) {
    if (max <= 0) return 0;
    return nextUint32() % max;
  }
}
