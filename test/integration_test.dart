import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tricrypt_app/backend/stego.dart';
import 'package:tricrypt_app/data/stubs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File coverFile;
  late File secretFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tricrypt_e2e_');

    // Create a 200x200 RGB cover image
    final coverImage = img.Image(width: 200, height: 200);
    img.fill(coverImage, color: img.ColorRgb8(80, 120, 160));
    final coverBytes = Uint8List.fromList(img.encodePng(coverImage));
    coverFile = File('${tempDir.path}/cover.png');
    await coverFile.writeAsBytes(coverBytes);

    // Create a secret document file
    secretFile = File('${tempDir.path}/confidential_report.txt');
    await secretFile.writeAsString('Top secret payload data embedded via TriCrypt 2026!');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('End-to-End: Hide -> Inspect Header -> Reveal with Both Credentials', () async {
    const passkey = 'SecurePasskey123#';
    const combinedCred = 'both:pk:$passkey:bio:authenticated';

    // 1. Live capacity calculation
    final capacity = await TriCryptStubs.getCoverCapacity(coverFile);
    expect(capacity, greaterThan(1000));

    // 2. Encode image
    File? encodedOutputFile;
    final outputFiles = await TriCryptStubs.encodeImage(
      coverFile,
      [secretFile],
      combinedCred,
      (idx, progress) {},
      onFileEncoded: (idx, outFile) {
        encodedOutputFile = outFile;
      },
    );

    expect(outputFiles, isNotEmpty);
    final stegoFile = encodedOutputFile ?? outputFiles.first;
    expect(await stegoFile.exists(), isTrue);

    // 3. Header inspection matches 'both'
    final stegoBytes = await stegoFile.readAsBytes();
    final headerType = await TriCryptStego.inspectEncryptionType(stegoBytes);
    expect(headerType, equals('both'));

    // 4. Decode with matching credentials
    File? decodedResultFile;
    DecodeError? decodeError;

    await TriCryptStubs.decodeImage(
      [stegoFile],
      {
        'passkey': 'pk:$passkey',
        'biometric': 'bio:authenticated',
      },
      (idx, progress) {},
      (idx, result) {
        decodedResultFile = result;
      },
      (idx, error) {
        decodeError = error;
      },
    );

    expect(decodeError, isNull);
    expect(decodedResultFile, isNotNull);
    expect(await decodedResultFile!.exists(), isTrue);

    final decodedText = await decodedResultFile!.readAsString();
    expect(decodedText, equals('Top secret payload data embedded via TriCrypt 2026!'));
  });

  test('End-to-End: Wrong Passkey triggers Access Denied', () async {
    const passkey = 'CorrectPass123!';
    const combinedCred = 'pk:$passkey';

    final outputFiles = await TriCryptStubs.encodeImage(
      coverFile,
      [secretFile],
      combinedCred,
      (idx, progress) {},
    );

    final stegoFile = outputFiles.first;

    DecodeError? decodeError;
    await TriCryptStubs.decodeImage(
      [stegoFile],
      {'passkey': 'pk:WrongPasskey999#'},
      (idx, progress) {},
      (idx, result) {},
      (idx, error) {
        decodeError = error;
      },
    );

    expect(decodeError, isNotNull);
    expect(decodeError!.kind, equals(DecodeErrorKind.accessDenied));
  });

  test('End-to-End: Clean cover image triggers Not TriCrypt Image', () async {
    DecodeError? decodeError;
    await TriCryptStubs.decodeImage(
      [coverFile],
      {'passkey': 'pk:AnyPasskey!'},
      (idx, progress) {},
      (idx, result) {},
      (idx, error) {
        decodeError = error;
      },
    );

    expect(decodeError, isNotNull);
    expect(decodeError!.kind, equals(DecodeErrorKind.notTriCryptImage));
  });

  test('End-to-End: P2P transfer send and receive handshake', () async {
    const confirmationCode = '4829';
    await TriCryptStubs.sendFile(coverFile, confirmationCode);

    final received = await TriCryptStubs.receiveFile(confirmationCode);
    expect(await received.exists(), isTrue);
  });
}
