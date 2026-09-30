import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import '../home/home.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;
  String? _emailError;
  String? _passwordError;

  final AuthService _authService = AuthService();
  final ConnectivityService _connectivity = ConnectivityService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _validateInputs() {
    setState(() {
      _emailError = Validators.validateEmail(_emailController.text);
      _passwordError = Validators.validatePassword(_passwordController.text);
    });
  }

  Future<void> _handleSignUp() async {
    FocusScope.of(context).unfocus();
    _validateInputs();

    if (_emailError != null || _passwordError != null) {
      return;
    }

    final isOnline = await _connectivity.checkOnline();
    if (!isOnline) {
      setState(() {
        _errorMessage = AppStrings.offlineSignUpError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await _authService.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.isSuccess) {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainNavScreen(isFirstTimeSignUp: true),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
        (route) => false,
      );
    } else {
      setState(() {
        _errorMessage = result.errorMessage ?? 'Sign up failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-left back arrow
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accentCyan.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: AppColors.accentCyan,
                    size: 20,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.errorRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.errorRed, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.errorRed, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            color: AppColors.errorRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.errorRed, size: 18),
                        onPressed: () => setState(() => _errorMessage = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],

              if (_infoMessage != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.accentCyan, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.accentCyan, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _infoMessage!,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            color: AppColors.accentCyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              const GradientTitle(
                text: 'Sign Up',
                fontSize: 34,
              ),

              const SizedBox(height: 8),

              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text(
                  'Already have an account? Sign In',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 13,
                    color: AppColors.accentCyan,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accentCyan,
                  ),
                ),
              ),

              const SizedBox(height: 36),

              BracketTextField(
                label: 'EMAIL',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.validateEmail,
                errorText: _emailError,
                hintText: 'name@example.com',
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
              ),

              const SizedBox(height: 20),

              BracketTextField(
                label: 'PASSWORD',
                controller: _passwordController,
                isPassword: true,
                validator: Validators.validatePassword,
                errorText: _passwordError,
                hintText: '••••••••',
                onChanged: (_) {
                  if (_passwordError != null) setState(() => _passwordError = null);
                },
              ),

              const SizedBox(height: 36),

              PrimaryButton(
                text: 'SIGN UP',
                isLoading: _isLoading,
                onPressed: _handleSignUp,
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
