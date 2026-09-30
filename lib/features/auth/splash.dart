import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../home/home.dart';
import 'login.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.forward();
    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    final startTime = DateTime.now();

    // Read saved session from secure storage (NO NETWORK CALL)
    final bool hasSession = await AuthService().hasSavedSession();

    // Ensure 1.5s splash animation completes
    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(milliseconds: 1500) - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted) return;

    if (hasSession) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainNavScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(
                    color: AppColors.accentCyan,
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withValues(
                        alpha: 0.35 * _glowAnimation.value,
                      ),
                      blurRadius: 30 * _glowAnimation.value,
                      spreadRadius: 6 * _glowAnimation.value,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.security_outlined,
                    color: AppColors.accentCyan,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppStrings.appName.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textWhite,
                  letterSpacing: 6.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SECURITY VAULT & STEGANOGRAPHY',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentCyan.withValues(alpha: 0.8),
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: child,
            );
          },
        ),
      ),
    );
  }
}
