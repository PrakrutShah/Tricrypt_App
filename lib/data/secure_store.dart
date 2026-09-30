import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static final SecureStore _instance = SecureStore._internal();
  factory SecureStore() => _instance;
  SecureStore._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _keySession = 'session';
  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';
  static const String _keyRememberMe = 'remember_me';
  static const String _keyFirstLogin = 'first_login';
  static const String _keyBiometricPrompted = 'biometric_prompted';

  Future<void> saveSession({
    required String sessionToken,
    required String userId,
    required String username,
    required bool rememberMe,
  }) async {
    await _storage.write(key: _keySession, value: sessionToken);
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyRememberMe, value: rememberMe.toString());
  }

  Future<String?> getSession() async => await _storage.read(key: _keySession);
  Future<String?> getUserId() async => await _storage.read(key: _keyUserId);
  Future<String?> getUsername() async => await _storage.read(key: _keyUsername);

  Future<bool> getRememberMe() async {
    final val = await _storage.read(key: _keyRememberMe);
    if (val == null) return true; // Default true per prompt
    return val.toLowerCase() == 'true';
  }

  Future<bool> isFirstLogin() async {
    final val = await _storage.read(key: _keyFirstLogin);
    if (val == null) {
      await _storage.write(key: _keyFirstLogin, value: 'false');
      return true;
    }
    return false;
  }

  Future<bool> hasPromptedBiometrics() async {
    final val = await _storage.read(key: _keyBiometricPrompted);
    return val == 'true';
  }

  Future<void> setPromptedBiometrics() async {
    await _storage.write(key: _keyBiometricPrompted, value: 'true');
  }

  Future<void> saveFileCredential(String fileId, String credential) async {
    await _storage.write(key: 'cred_$fileId', value: credential);
  }

  Future<String?> getFileCredential(String fileId) async {
    return await _storage.read(key: 'cred_$fileId');
  }

  Future<void> clearAuthData() async {
    await _storage.delete(key: _keySession);
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyUsername);
    // Keep remember_me or set to true
  }

  Future<void> clearSessionOnLaunchIfRememberMeDisabled() async {
    final rememberMe = await getRememberMe();
    if (!rememberMe) {
      await clearAuthData();
    }
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
