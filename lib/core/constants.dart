import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Theme Colors
  static const Color background = Color(0xFF0A0A0A);
  static const Color card = Color(0xFF121212);
  static const Color cardBorder = Color(0xFF1E1E1E);
  static const Color cardHover = Color(0xFF1A1A1A);

  // Accents
  static const Color accentCyan = Color(0xFF4DFFEA);
  static const Color accentCyanGlow = Color(0x334DFFEA);
  static const Color cyanDim = Color(0xFF268B80);
  
  // Status Colors
  static const Color errorRed = Color(0xFFFF4D4D);
  static const Color errorRedGlow = Color(0x33FF4D4D);
  static const Color successGreen = Color(0xFF4DFF88);

  // Text Colors
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFF555555);

  // Gradient Colors for Monospace Display Titles (Peach / Coral)
  static const List<Color> titleGradient = [
    Color(0xFFFFB39A),
    Color(0xFFFF7A7A),
    Color(0xFFFF9E7A),
  ];
}

class AppStrings {
  AppStrings._();

  static const String appName = 'TriCrypt';
  static const String appTagline = 'Your files stay on your device, always.';

  // Titles
  static const String loginTitle = 'Login';
  static const String signUpTitle = 'Sign Up';
  static const String hideTitle = 'Hide';
  static const String viewTitle = 'View';
  static const String galleryTitle = 'Gallery';
  static const String barcodeTitle = 'Barcode';
  static const String scannerTitle = 'Scanner';
  static const String previewTitle = 'Preview';

  // Auth
  static const String rememberMe = 'Remember me!';
  static const String signIn = 'SIGN IN';
  static const String signUp = 'SIGN UP';
  static const String createAccount = 'Create account';
  static const String alreadyHaveAccount = 'Already have an account? Sign In';
  static const String noAccount = "Don't have an account? Sign Up";
  static const String offlineLoginError = 'Internet required to sign in.';
  static const String offlineSignUpError = 'Internet required to sign up.';

  // Hide Screen
  static const String coverImage = 'COVER IMAGE';
  static const String secretFiles = 'SECRET FILES (1 or more)';
  static const String biometric = 'BIOMETRIC';
  static const String passkey = 'PASSKEY';
  static const String hideButton = 'HIDE';
  static const String noBiometricsEnrolled = 'No fingerprint or Face ID enrolled';

  // View Screen
  static const String encodedImage = 'ENCODED IMAGE';
  static const String revealButton = 'REVEAL';
  static const String accessDenied = 'Access Denied';
  static const String noHiddenData = 'This image has no hidden data.';

  // Gallery Screen
  static const String noItemsYet = 'No items yet.';
  static const String noItemsSubtext = 'Hide or reveal an image to see it here.';

  // Barcode
  static const String selectImageToShare = 'SELECT IMAGE TO SHARE';
  static const String generateCode = 'GENERATE CODE';
  static const String scanToReceive = 'SCAN TO RECEIVE';
  static const String waitingForScan = 'Waiting for scan...';
  static const String matchCodePrompt = 'Ask the other device to confirm this code matches.';
}

class SupabaseConfig {
  SupabaseConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xyzcompany.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'public-anon-key-placeholder',
  );

  static bool get isConfigured =>
      supabaseUrl != 'https://xyzcompany.supabase.co' &&
      supabaseAnonKey != 'public-anon-key-placeholder';
}
