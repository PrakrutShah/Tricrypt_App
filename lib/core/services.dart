import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/secure_store.dart';
import 'constants.dart';

// --- CONNECTIVITY SERVICE ---
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _controller = StreamController<bool>.broadcast();

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _controller.stream;

  Future<void> initialize() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = _checkIfOnline(results);
    } catch (_) {
      _isOnline = true;
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _checkIfOnline(results);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  bool _checkIfOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }

  Future<bool> checkOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = _checkIfOnline(results);
      return _isOnline;
    } catch (_) {
      return _isOnline;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}

// --- BIOMETRIC SERVICE ---
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> canCheckBiometrics() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasEnrolledBiometrics() async {
    try {
      final bool canCheck = await canCheckBiometrics();
      if (!canCheck) return false;
      final List<BiometricType> available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({
    String reason = 'Verify your identity to access TriCrypt secured data',
  }) async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return didAuthenticate;
    } on PlatformException catch (_) {
      try {
        final bool didFallback = await _auth.authenticate(
          localizedReason: reason,
          biometricOnly: false,
          persistAcrossBackgrounding: true,
        );
        return didFallback;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }
}

// --- AUTH SERVICE ---
class AuthResult {
  final bool isSuccess;
  final String? errorMessage;
  final String? userId;
  final String? username;

  AuthResult({
    required this.isSuccess,
    this.errorMessage,
    this.userId,
    this.username,
  });
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SecureStore _secureStore = SecureStore();
  final ConnectivityService _connectivity = ConnectivityService();

  SupabaseClient? get _supabase {
    try {
      if (SupabaseConfig.isConfigured) {
        return Supabase.instance.client;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> hasSavedSession() async {
    final rememberMe = await _secureStore.getRememberMe();
    if (!rememberMe) {
      await _secureStore.clearAuthData();
      return false;
    }
    final session = await _secureStore.getSession();
    return session != null && session.isNotEmpty;
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final isOnline = await _connectivity.checkOnline();
    if (!isOnline) {
      return AuthResult(
        isSuccess: false,
        errorMessage: 'Internet required to sign in.',
      );
    }

    try {
      if (SupabaseConfig.isConfigured && _supabase != null) {
        final AuthResponse res = await _supabase!.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );

        final user = res.user;
        final session = res.session;

        if (user == null || session == null) {
          return AuthResult(
            isSuccess: false,
            errorMessage: 'Invalid email or password.',
          );
        }

        final username = user.userMetadata?['name'] as String? ??
            user.email?.split('@').first ??
            'User';

        await _secureStore.saveSession(
          sessionToken: session.accessToken,
          userId: user.id,
          username: username,
          rememberMe: rememberMe,
        );

        return AuthResult(
          isSuccess: true,
          userId: user.id,
          username: username,
        );
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
        final username = email.split('@').first;
        final mockId = 'user_${DateTime.now().millisecondsSinceEpoch}';

        await _secureStore.saveSession(
          sessionToken: 'mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}',
          userId: mockId,
          username: username,
          rememberMe: rememberMe,
        );

        return AuthResult(
          isSuccess: true,
          userId: mockId,
          username: username,
        );
      }
    } on AuthException catch (e) {
      return AuthResult(isSuccess: false, errorMessage: e.message);
    } catch (e) {
      return AuthResult(
        isSuccess: false,
        errorMessage: 'Sign in failed: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }
  }

  Future<AuthResult> signUp({
    String? name,
    required String email,
    required String password,
  }) async {
    final isOnline = await _connectivity.checkOnline();
    if (!isOnline) {
      return AuthResult(
        isSuccess: false,
        errorMessage: 'Internet required to sign up.',
      );
    }

    final displayName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : email.trim().split('@').first;

    try {
      if (SupabaseConfig.isConfigured && _supabase != null) {
        final AuthResponse res = await _supabase!.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'name': displayName},
        );

        final user = res.user;
        if (user == null) {
          return AuthResult(
            isSuccess: false,
            errorMessage: 'Sign up failed. Please try again.',
          );
        }

        final session = res.session;
        final username = displayName;

        if (session != null) {
          await _secureStore.saveSession(
            sessionToken: session.accessToken,
            userId: user.id,
            username: username,
            rememberMe: true,
          );
        }

        return AuthResult(
          isSuccess: true,
          userId: user.id,
          username: username,
        );
      } else {
        await Future.delayed(const Duration(milliseconds: 600));
        final username = displayName;
        final mockId = 'user_${DateTime.now().millisecondsSinceEpoch}';

        await _secureStore.saveSession(
          sessionToken: 'mock_jwt_token_${DateTime.now().millisecondsSinceEpoch}',
          userId: mockId,
          username: username,
          rememberMe: true,
        );

        return AuthResult(
          isSuccess: true,
          userId: mockId,
          username: username,
        );
      }
    } on AuthException catch (e) {
      return AuthResult(isSuccess: false, errorMessage: e.message);
    } catch (e) {
      return AuthResult(
        isSuccess: false,
        errorMessage: 'Sign up failed: ${e.toString().replaceAll("Exception: ", "")}',
      );
    }
  }

  Future<void> trySilentRefresh() async {
    final isOnline = await _connectivity.checkOnline();
    if (!isOnline) return;

    try {
      if (SupabaseConfig.isConfigured && _supabase != null) {
        final session = _supabase!.auth.currentSession;
        if (session != null) {
          await _supabase!.auth.refreshSession();
        }
      }
    } catch (e) {
      if (kDebugMode) print('Silent refresh failed: $e');
    }
  }

  Future<void> logout() async {
    try {
      if (SupabaseConfig.isConfigured && _supabase != null) {
        await _supabase!.auth.signOut();
      }
    } catch (_) {}
    await _secureStore.clearAuthData();
  }
}
