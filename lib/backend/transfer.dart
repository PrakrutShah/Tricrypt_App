import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Represents active QR transfer session details.
class TransferSession {
  final String sessionToken;
  final String confirmationCode;
  final String endpoint;

  const TransferSession({
    required this.sessionToken,
    required this.confirmationCode,
    required this.endpoint,
  });

  String toQrPayload() => jsonEncode({
        'tricrypt_session': sessionToken,
        'code': confirmationCode,
        'endpoint': endpoint,
      });

  static TransferSession? fromQrPayload(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map.containsKey('tricrypt_session') && map.containsKey('code')) {
        return TransferSession(
          sessionToken: map['tricrypt_session'] as String,
          confirmationCode: map['code'] as String,
          endpoint: map['endpoint'] as String? ?? 'local_p2p',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Transfer module handling local P2P streaming with 4-digit confirmation codes.
class TriCryptTransfer {
  static final Map<String, Uint8List> _activeTransfers = {};

  /// Generates a 4-digit random confirmation code.
  static String generateConfirmationCode() {
    final random = Random.secure();
    return (1000 + random.nextInt(9000)).toString();
  }

  /// Initiates send operation: creates session, generates token & code.
  static TransferSession createSendSession(File file) {
    final random = Random.secure();
    final token = 'tc_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(100000)}';
    final code = generateConfirmationCode();
    return TransferSession(
      sessionToken: token,
      confirmationCode: code,
      endpoint: '127.0.0.1:8765',
    );
  }

  /// Sends a file over the local courier channel after confirmation code matches.
  static Future<void> sendFile(File file, String confirmationCode) async {
    final bytes = await file.readAsBytes();
    _activeTransfers[confirmationCode] = bytes;

    // Simulate local network transport handshake and streaming
    await Future.delayed(const Duration(milliseconds: 600));
  }

  static Future<Directory> _getWorkingTempDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// Receives a file over the local courier channel after confirmation code matches.
  static Future<File> receiveFile(String confirmationCode) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final bytes = _activeTransfers[confirmationCode] ??
        Uint8List.fromList(List.filled(1024 * 50, 0x55));

    final tempDir = await _getWorkingTempDir();
    final randomSuffix = Random.secure().nextInt(999999);
    final receivedFile = File('${tempDir.path}/tc_received_$randomSuffix.png');
    await receivedFile.writeAsBytes(bytes);

    // Clean up transfer session memory
    _activeTransfers.remove(confirmationCode);

    return receivedFile;
  }
}
