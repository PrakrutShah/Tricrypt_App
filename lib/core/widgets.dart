import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';
import 'theme.dart';

// --- GRADIENT TITLE ---
class GradientTitle extends StatelessWidget {
  final String text;
  final double fontSize;
  final TextAlign textAlign;
  final List<Color>? gradientColors;

  const GradientTitle({
    super.key,
    required this.text,
    this.fontSize = 28,
    this.textAlign = TextAlign.start,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: gradientColors ?? AppColors.titleGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontFamily: AppTheme.fontMonospace,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

// --- BRACKET PAINTER & BRACKET BOX ---
enum BracketStyle {
  twoCorners, // Top-left and Bottom-right (as in mockups)
  fourCorners, // All four corners
}

class BracketPainter extends CustomPainter {
  final Color cornerColor;
  final double cornerLength;
  final double strokeWidth;
  final BracketStyle style;
  final bool hasGlow;

  BracketPainter({
    this.cornerColor = AppColors.accentCyan,
    this.cornerLength = 16.0,
    this.strokeWidth = 2.0,
    this.style = BracketStyle.twoCorners,
    this.hasGlow = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = cornerColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final glowPaint = Paint()
      ..color = cornerColor.withValues(alpha: 0.35)
      ..strokeWidth = strokeWidth + 2.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    void drawCorner(double x1, double y1, double x2, double y2, double x3, double y3) {
      final path = Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2)
        ..lineTo(x3, y3);

      if (hasGlow) {
        canvas.drawPath(path, glowPaint);
      }
      canvas.drawPath(path, paint);
    }

    final double len = cornerLength.clamp(4.0, size.shortestSide / 2);

    // Top-Left Corner
    drawCorner(0, len, 0, 0, len, 0);

    // Bottom-Right Corner
    drawCorner(size.width - len, size.height, size.width, size.height, size.width, size.height - len);

    if (style == BracketStyle.fourCorners) {
      // Top-Right Corner
      drawCorner(size.width - len, 0, size.width, 0, size.width, len);
      // Bottom-Left Corner
      drawCorner(0, size.height - len, 0, size.height, len, size.height);
    }
  }

  @override
  bool shouldRepaint(covariant BracketPainter oldDelegate) {
    return oldDelegate.cornerColor != cornerColor ||
        oldDelegate.cornerLength != cornerLength ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.style != style ||
        oldDelegate.hasGlow != hasGlow;
  }
}

class BracketBox extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color cornerColor;
  final double cornerLength;
  final double strokeWidth;
  final BracketStyle style;
  final bool hasGlow;
  final VoidCallback? onTap;

  const BracketBox({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(12),
    this.backgroundColor = const Color(0x12FFFFFF),
    this.cornerColor = AppColors.accentCyan,
    this.cornerLength = 16.0,
    this.strokeWidth = 2.0,
    this.style = BracketStyle.twoCorners,
    this.hasGlow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final boxContent = CustomPaint(
      painter: BracketPainter(
        cornerColor: cornerColor,
        cornerLength: cornerLength,
        strokeWidth: strokeWidth,
        style: style,
        hasGlow: hasGlow,
      ),
      child: Container(
        width: width,
        height: height,
        padding: padding,
        color: backgroundColor,
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        splashColor: AppColors.accentCyanGlow,
        highlightColor: Colors.transparent,
        child: boxContent,
      );
    }

    return boxContent;
  }
}

// --- BRACKET TEXT FIELD ---
class BracketTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  final bool enabled;

  const BracketTextField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.errorText,
    this.onChanged,
    this.hintText,
    this.enabled = true,
  });

  @override
  State<BracketTextField> createState() => _BracketTextFieldState();
}

class _BracketTextFieldState extends State<BracketTextField> {
  bool _obscureText = true;
  String? _internalError;
  bool _isFocused = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (!_focusNode.hasFocus && widget.validator != null) {
        setState(() {
          _internalError = widget.validator!(widget.controller.text);
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayError = widget.errorText ?? _internalError;
    final hasError = displayError != null && displayError.isNotEmpty;

    final cornerColor = hasError
        ? AppColors.errorRed
        : (_isFocused ? AppColors.accentCyan : AppColors.accentCyan.withValues(alpha: 0.7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: const TextStyle(
            fontFamily: AppTheme.fontMonospace,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.accentCyan,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        BracketBox(
          cornerColor: cornerColor,
          cornerLength: 16,
          strokeWidth: 2,
          backgroundColor: const Color(0x14FFFFFF),
          hasGlow: _isFocused,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  obscureText: widget.isPassword ? _obscureText : false,
                  keyboardType: widget.keyboardType,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 14,
                    color: AppColors.textWhite,
                  ),
                  cursorColor: AppColors.accentCyan,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      fontFamily: AppTheme.fontMonospace,
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  onChanged: (val) {
                    if (widget.validator != null) {
                      setState(() {
                        _internalError = widget.validator!(val);
                      });
                    }
                    if (widget.onChanged != null) {
                      widget.onChanged!(val);
                    }
                  },
                ),
              ),
              if (widget.isPassword)
                IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppColors.accentCyan.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            displayError,
            style: const TextStyle(
              fontFamily: AppTheme.fontMonospace,
              fontSize: 11,
              color: AppColors.errorRed,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

// --- PRIMARY BUTTON ---
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color borderColor;
  final Color textColor;
  final double height;
  final bool isFullWidth;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.borderColor = AppColors.accentCyan,
    this.textColor = AppColors.accentCyan,
    this.height = 48,
    this.isFullWidth = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null && !isLoading;
    final effectiveBorderColor = isEnabled ? borderColor : AppColors.textMuted;
    final effectiveTextColor = isEnabled ? textColor : AppColors.textMuted;

    final buttonWidget = Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(
          color: effectiveBorderColor,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: effectiveBorderColor.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled
              ? () {
                  HapticFeedback.lightImpact();
                  onPressed!();
                }
              : null,
          borderRadius: BorderRadius.circular(4),
          splashColor: effectiveBorderColor.withValues(alpha: 0.25),
          highlightColor: effectiveBorderColor.withValues(alpha: 0.1),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(effectiveBorderColor),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: effectiveTextColor),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text.toUpperCase(),
                        style: TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          color: effectiveTextColor,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (isFullWidth) {
      return SizedBox(
        width: double.infinity,
        child: buttonWidget,
      );
    }

    return buttonWidget;
  }
}

// --- CUSTOM TOGGLE ---
class CustomToggle extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isEnabled;

  const CustomToggle({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveEnabled = isEnabled && onChanged != null;
    final labelColor = effectiveEnabled ? AppColors.textWhite : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                  letterSpacing: 1.5,
                ),
              ),
              Switch(
                value: value,
                onChanged: effectiveEnabled
                    ? (val) {
                        HapticFeedback.selectionClick();
                        onChanged!(val);
                      }
                    : null,
                activeColor: AppColors.accentCyan,
                activeTrackColor: AppColors.accentCyan.withValues(alpha: 0.35),
                inactiveThumbColor: AppColors.textGrey,
                inactiveTrackColor: const Color(0xFF222222),
              ),
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontFamily: AppTheme.fontMonospace,
                fontSize: 11,
                color: effectiveEnabled ? AppColors.textGrey : AppColors.errorRed.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- PERMISSION DIALOG ---
enum TriCryptPermissionOption {
  alwaysAllow,
  whileUsingApp,
  onlyOnce,
  denied,
}

class TriCryptPermissionDialog extends StatelessWidget {
  final String permissionName;
  final String description;
  final IconData icon;

  const TriCryptPermissionDialog({
    super.key,
    required this.permissionName,
    required this.description,
    required this.icon,
  });

  static Future<TriCryptPermissionOption?> show(
    BuildContext context, {
    required String permissionName,
    required String description,
    required IconData icon,
  }) {
    return showDialog<TriCryptPermissionOption>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TriCryptPermissionDialog(
        permissionName: permissionName,
        description: description,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: BracketBox(
        cornerColor: AppColors.accentCyan,
        cornerLength: 20,
        strokeWidth: 2,
        backgroundColor: AppColors.card,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accentCyan, width: 1),
                  ),
                  child: Icon(icon, color: AppColors.accentCyan, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PERMISSION REQUIRED',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 10,
                          color: AppColors.accentCyan,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        permissionName,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 16,
                          color: AppColors.textWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: const TextStyle(
                fontFamily: AppTheme.fontMonospace,
                fontSize: 12,
                color: AppColors.textGrey,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _buildOptionButton(
              context,
              label: 'Always Allow',
              option: TriCryptPermissionOption.alwaysAllow,
              isPrimary: true,
            ),
            const SizedBox(height: 8),
            _buildOptionButton(
              context,
              label: 'While using the app',
              option: TriCryptPermissionOption.whileUsingApp,
              isPrimary: false,
            ),
            const SizedBox(height: 8),
            _buildOptionButton(
              context,
              label: 'Only Once',
              option: TriCryptPermissionOption.onlyOnce,
              isPrimary: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required String label,
    required TriCryptPermissionOption option,
    required bool isPrimary,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isPrimary ? AppColors.accentCyan.withValues(alpha: 0.15) : Colors.transparent,
        border: Border.all(
          color: isPrimary ? AppColors.accentCyan : AppColors.cardBorder,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(option),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? AppColors.accentCyan : AppColors.textWhite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- SECURITY OVERLAY ---
class SecurityOverlayWrapper extends StatefulWidget {
  final Widget child;
  final bool isSensitiveScreen;

  const SecurityOverlayWrapper({
    super.key,
    required this.child,
    this.isSensitiveScreen = false,
  });

  @override
  State<SecurityOverlayWrapper> createState() => _SecurityOverlayWrapperState();
}

class _SecurityOverlayWrapperState extends State<SecurityOverlayWrapper>
    with WidgetsBindingObserver {
  bool _isBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.isSensitiveScreen) {
      final shouldMask = state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden;
      if (shouldMask != _isBackgrounded) {
        setState(() {
          _isBackgrounded = shouldMask;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isBackgrounded && widget.isSensitiveScreen)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: AppColors.background.withValues(alpha: 0.92),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: AppColors.accentCyan,
                        size: 52,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'TRICRYPT VAULT PROTECTED',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textWhite,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
