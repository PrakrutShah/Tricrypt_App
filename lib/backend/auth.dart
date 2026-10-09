import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Error thrown when attempt limit has been reached on a file.
class TooManyAttemptsException implements Exception {
  final String fileId;
  final int attemptCount;

  const TooManyAttemptsException({
    required this.fileId,
    required this.attemptCount,
  });

  @override
  String toString() =>
      'TooManyAttemptsException: File $fileId is locked after $attemptCount failed attempts. Recovery seed required.';
}

/// Authentication, Key Recovery, and Brute-Force Protection Engine.
class TriCryptAuth {
  // Standard BIP-39 English word subset for 12-word seed phrases
  static const List<String> _wordList = [
    'abandon', 'ability', 'able', 'about', 'above', 'absent', 'absorb', 'abstract',
    'absurd', 'abuse', 'access', 'accident', 'account', 'accuse', 'achieve', 'acid',
    'acoustic', 'acquire', 'across', 'act', 'action', 'actor', 'actress', 'actual',
    'adapt', 'add', 'addict', 'address', 'adjust', 'admit', 'adult', 'advance',
    'advice', 'aerobic', 'affair', 'afford', 'afraid', 'again', 'age', 'agent',
    'agree', 'ahead', 'aim', 'air', 'airport', 'aisle', 'alarm', 'album',
    'alcohol', 'alert', 'alien', 'all', 'alley', 'allow', 'almost', 'alone',
    'alpha', 'already', 'also', 'alter', 'always', 'amateur', 'amazing', 'among',
    'amount', 'amused', 'analyst', 'anchor', 'ancient', 'anger', 'angle', 'angry',
    'animal', 'ankle', 'announce', 'annual', 'another', 'answer', 'antenna', 'antique',
    'anxiety', 'any', 'apart', 'apology', 'appear', 'apple', 'approve', 'april',
    'arch', 'arctic', 'area', 'arena', 'argue', 'arm', 'armed', 'armor',
    'army', 'around', 'arrange', 'arrest', 'arrive', 'arrow', 'art', 'artefact',
    'artist', 'artwork', 'ask', 'aspect', 'assault', 'asset', 'assist', 'assume',
    'asthma', 'athlete', 'atom', 'attack', 'attend', 'attitude', 'attract', 'auction',
    'audit', 'august', 'aunt', 'author', 'auto', 'autumn', 'average', 'avocado',
    'avoid', 'awake', 'aware', 'away', 'awesome', 'awful', 'awkward', 'axis',
    'baby', 'bachelor', 'bacon', 'badge', 'bag', 'balance', 'balcony', 'ball',
    'bamboo', 'banana', 'banner', 'bar', 'barely', 'bargain', 'barrel', 'base',
    'basic', 'basket', 'battle', 'beach', 'bean', 'beauty', 'because', 'become',
    'beef', 'before', 'begin', 'behave', 'behind', 'believe', 'below', 'belt',
    'bench', 'benefit', 'best', 'betray', 'better', 'between', 'beyond', 'bicycle',
    'bid', 'bike', 'bind', 'biology', 'bird', 'birth', 'bitter', 'black',
    'blade', 'blame', 'blanket', 'blast', 'bleak', 'bless', 'blind', 'blood',
    'blossom', 'blouse', 'blue', 'blur', 'blush', 'board', 'boat', 'body',
    'boil', 'bomb', 'bone', 'bonus', 'book', 'boost', 'border', 'boring',
    'borrow', 'boss', 'bottom', 'bounce', 'box', 'boy', 'bracket', 'brain',
    'brand', 'brass', 'brave', 'bread', 'breeze', 'brick', 'bridge', 'brief',
    'bright', 'bring', 'brisk', 'broccoli', 'broken', 'bronze', 'broom', 'brother',
    'brown', 'brush', 'bubble', 'buddy', 'budget', 'buffalo', 'build', 'bulb',
    'bulk', 'bullet', 'bundle', 'bunker', 'burden', 'burger', 'burst', 'bus',
    'business', 'busy', 'butter', 'buyer', 'buzz', 'cabbage', 'cabin', 'cable',
    'cactus', 'cage', 'cake', 'call', 'calm', 'camera', 'camp', 'can',
    'canal', 'cancel', 'candy', 'cannon', 'canoe', 'canvas', 'canyon', 'capable'
  ];

  // In-memory per-file attempt counters (fileId -> count)
  static final Map<String, int> _attemptCounters = {};
  static final Map<String, DateTime> _lockoutUntil = {};

  /// Generates a 12-word BIP39-style mnemonic recovery seed.
  static List<String> generateRecoverySeed() {
    final random = Random.secure();
    final words = <String>[];
    for (int i = 0; i < 12; i++) {
      final index = random.nextInt(_wordList.length);
      words.add(_wordList[index]);
    }
    return words;
  }

  /// Derives the 32-byte device-independent RecoveryKey from a 12-word seed phrase:
  /// RecoveryKey = PBKDF2(seedPhrase, salt="tricrypt-recovery", iterations=200000)
  static Future<Uint8List> deriveKeyFromRecovery(
    List<String> seedWords, {
    String salt = 'tricrypt-recovery',
  }) async {
    final mnemonic = seedWords.join(' ');
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 200000,
      bits: 256,
    );
    final derived = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(mnemonic)),
      nonce: Uint8List.fromList(utf8.encode(salt)),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// Checks brute-force backoff schedule before an attempt.
  /// Throws [TooManyAttemptsException] if attempts >= 10.
  /// Throws [Exception] with wait duration if within an exponential delay backoff.
  static Future<void> checkAttemptAllowed(String fileId) async {
    final attempts = _attemptCounters[fileId] ?? 0;

    if (attempts >= 10) {
      throw TooManyAttemptsException(fileId: fileId, attemptCount: attempts);
    }

    final lockout = _lockoutUntil[fileId];
    if (lockout != null && DateTime.now().isBefore(lockout)) {
      final waitSeconds = lockout.difference(DateTime.now()).inSeconds + 1;
      throw Exception('Backoff in effect: Please wait $waitSeconds seconds before retrying.');
    }
  }

  /// Records a failed attempt and computes the exponential backoff delay:
  /// Attempts 1–3: 0s
  /// Attempts 4+: 2^(attempt - 3) seconds (2s, 4s, 8s, 16s, 32s, 64s)
  /// Attempt 10: hard lockout
  static void recordFailedAttempt(String fileId) {
    final current = (_attemptCounters[fileId] ?? 0) + 1;
    _attemptCounters[fileId] = current;

    if (current >= 10) {
      return;
    }

    if (current >= 4) {
      final backoffSeconds = pow(2, current - 3).toInt();
      _lockoutUntil[fileId] = DateTime.now().add(Duration(seconds: backoffSeconds));
    }
  }

  /// Resets the attempt counter on successful unlock.
  static void recordSuccess(String fileId) {
    _attemptCounters.remove(fileId);
    _lockoutUntil.remove(fileId);
  }

  /// Resets the counter using the recovery key.
  static void resetWithRecovery(String fileId) {
    _attemptCounters.remove(fileId);
    _lockoutUntil.remove(fileId);
  }
}
