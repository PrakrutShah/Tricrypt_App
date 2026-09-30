import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import '../../data/album_db.dart';
import '../../data/secure_store.dart';
import '../../data/stubs.dart';
import '../preview/preview.dart';

enum HideState { idle, processing, done }

class HideScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const HideScreen({super.key, this.onBackToHome});

  @override
  State<HideScreen> createState() => _HideScreenState();
}

class _HideScreenState extends State<HideScreen>
    with SingleTickerProviderStateMixin {
  File? _coverImage;
  int _coverCapacityBytes = 0;
  bool _isLoadingCapacity = false;

  final List<File> _secretImages = [];
  int _totalSecretSizeBytes = 0;

  // Multi-select toggles
  bool _biometricOn = false;
  bool _passwordOn = false;
  bool _passkeyOn = false;
  bool _hasBiometricsEnrolled = false;

  HideState _state = HideState.idle;
  double _encodeProgress = 0.0;
  File? _outputFile;
  String? _errorMessage;

  final ImagePicker _picker = ImagePicker();
  final BiometricService _biometricService = BiometricService();
  final AlbumDb _albumDb = AlbumDb();
  final SecureStore _secureStore = SecureStore();

  late AnimationController _animController;
  late Animation<double> _slideFadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideFadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final enrolled = await _biometricService.hasEnrolledBiometrics();
    if (mounted) {
      setState(() {
        _hasBiometricsEnrolled = enrolled;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  bool get _isOverCapacity =>
      _coverImage != null &&
      _secretImages.isNotEmpty &&
      _coverCapacityBytes > 0 &&
      _totalSecretSizeBytes > _coverCapacityBytes;

  bool get _hasAnyAuthSelected => _biometricOn || _passwordOn || _passkeyOn;

  bool get _canShowHideButton =>
      _coverImage != null &&
      _secretImages.isNotEmpty &&
      !_isOverCapacity &&
      _hasAnyAuthSelected &&
      _state == HideState.idle;

  void _updateButtonAnimation() {
    if (_canShowHideButton) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  Future<void> _pickCoverImage() async {
    if (_state == HideState.processing) return;

    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final file = File(picked.path);
        setState(() {
          _coverImage = file;
          _isLoadingCapacity = true;
          _errorMessage = null;
        });

        final capacity = await TriCryptStubs.getCoverCapacity(file);
        if (mounted) {
          setState(() {
            _coverCapacityBytes = capacity;
            _isLoadingCapacity = false;
          });
          _updateButtonAnimation();
        }
      }
    } catch (_) {}
  }

  Future<void> _pickSecretImages() async {
    if (_state == HideState.processing) return;

    try {
      final List<XFile> pickedList = await _picker.pickMultiImage();
      if (pickedList.isNotEmpty) {
        final newFiles = <File>[];
        int totalBytes = 0;

        for (final xf in pickedList) {
          final f = File(xf.path);
          newFiles.add(f);
          try {
            totalBytes += f.lengthSync();
          } catch (_) {
            totalBytes += 1024 * 350;
          }
        }

        setState(() {
          _secretImages.clear();
          _secretImages.addAll(newFiles);
          _totalSecretSizeBytes = totalBytes;
          _errorMessage = null;
        });
        _updateButtonAnimation();
      }
    } catch (_) {}
  }

  Future<void> _startHideWorkflow() async {
    if (!_canShowHideButton) return;

    String passwordVal = '';
    String passkeyVal = '';

    // Step 1: If Password toggle enabled, capture password first
    if (_passwordOn) {
      final pass = await _showPasswordDialog();
      if (pass == null) return; // User cancelled -> abort sequence
      passwordVal = pass;
    }

    // Step 2: If Passkey toggle enabled, capture passkey next
    if (_passkeyOn) {
      final pKey = await _showPasskeyDialog();
      if (pKey == null) return; // User cancelled -> abort sequence
      passkeyVal = pKey;
    }

    // Step 3: If Biometric toggle enabled, authenticate with biometrics
    if (_biometricOn) {
      final bioSuccess = await _biometricService.authenticate(
        reason: 'Authenticate to encrypt and hide your secret files',
      );
      if (!bioSuccess) {
        setState(() {
          _errorMessage = 'Biometric authentication failed or cancelled.';
        });
        return; // Failed/cancelled -> abort sequence
      }
    }

    // All enabled checks successfully captured! Combine credentials and start progress
    final credentialsList = <String>[];
    if (_passwordOn) credentialsList.add('pwd:$passwordVal');
    if (_passkeyOn) credentialsList.add('pk:$passkeyVal');
    if (_biometricOn) credentialsList.add('bio:authenticated');
    final finalCredential = credentialsList.join(';');

    setState(() {
      _state = HideState.processing;
      _encodeProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final outputFiles = await TriCryptStubs.encodeImage(
        cover: _coverImage!,
        secrets: _secretImages,
        credential: finalCredential,
        onProgress: (fileIndex, progress) {
          if (mounted) {
            setState(() {
              _encodeProgress = progress;
            });
          }
        },
      );

      final out = outputFiles.first;
      final filename = out.path.split(Platform.pathSeparator).last;
      
      final types = <String>[];
      if (_biometricOn) types.add('biometric');
      if (_passwordOn) types.add('password');
      if (_passkeyOn) types.add('passkey');
      final encType = types.join('+');

      final dbId = await _albumDb.insertItem(
        AlbumItem(
          filename: filename,
          filepath: out.path,
          type: 'encoded',
          encryptionType: encType,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          thumbnailPath: _coverImage!.path,
        ),
      );

      await _secureStore.saveFileCredential('$dbId', finalCredential);

      if (mounted) {
        setState(() {
          _outputFile = out;
          _encodeProgress = 1.0;
          _state = HideState.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = HideState.idle;
          _errorMessage = 'Encoding operation failed: $e';
        });
      }
    }
  }

  Future<String?> _showPasswordDialog() async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? passError;
    String? confirmError;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: BracketBox(
                cornerColor: AppColors.accentCyan,
                cornerLength: 20,
                strokeWidth: 2,
                backgroundColor: AppColors.card,
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GradientTitle(
                      text: 'Set Password',
                      fontSize: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter a password to encrypt and lock your secret files.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 20),
                    BracketTextField(
                      label: 'PASSWORD',
                      controller: passwordCtrl,
                      isPassword: true,
                      validator: Validators.validatePassword,
                      errorText: passError,
                      hintText: '••••••••',
                      onChanged: (_) {
                        if (passError != null) {
                          setDialogState(() => passError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    BracketTextField(
                      label: 'CONFIRM PASSWORD',
                      controller: confirmCtrl,
                      isPassword: true,
                      errorText: confirmError,
                      hintText: '••••••••',
                      onChanged: (_) {
                        if (confirmError != null) {
                          setDialogState(() => confirmError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            text: 'CANCEL',
                            borderColor: AppColors.textGrey,
                            textColor: AppColors.textGrey,
                            onPressed: () => Navigator.of(ctx).pop(null),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            text: 'SET',
                            onPressed: () {
                              final pErr = Validators.validatePassword(passwordCtrl.text);
                              final cErr = Validators.validateConfirmPassword(
                                confirmCtrl.text,
                                passwordCtrl.text,
                              );
                              if (pErr != null || cErr != null) {
                                setDialogState(() {
                                  passError = pErr;
                                  confirmError = cErr;
                                });
                                return;
                              }
                              Navigator.of(ctx).pop(passwordCtrl.text);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showPasskeyDialog() async {
    final passkeyCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? passError;
    String? confirmError;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: BracketBox(
                cornerColor: AppColors.accentCyan,
                cornerLength: 20,
                strokeWidth: 2,
                backgroundColor: AppColors.card,
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GradientTitle(
                      text: 'Set Passkey',
                      fontSize: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This passkey will be required to reveal your hidden files.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 20),
                    BracketTextField(
                      label: 'PASSKEY',
                      controller: passkeyCtrl,
                      isPassword: true,
                      validator: Validators.validatePasskey,
                      errorText: passError,
                      hintText: '••••••••',
                      onChanged: (_) {
                        if (passError != null) {
                          setDialogState(() => passError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    BracketTextField(
                      label: 'CONFIRM PASSKEY',
                      controller: confirmCtrl,
                      isPassword: true,
                      errorText: confirmError,
                      hintText: '••••••••',
                      onChanged: (_) {
                        if (confirmError != null) {
                          setDialogState(() => confirmError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            text: 'CANCEL',
                            borderColor: AppColors.textGrey,
                            textColor: AppColors.textGrey,
                            onPressed: () => Navigator.of(ctx).pop(null),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            text: 'SET',
                            onPressed: () {
                              final pErr = Validators.validatePasskey(passkeyCtrl.text);
                              final cErr = Validators.validateConfirmPassword(
                                confirmCtrl.text,
                                passkeyCtrl.text,
                              );
                              if (pErr != null || cErr != null) {
                                setDialogState(() {
                                  passError = pErr;
                                  confirmError = cErr;
                                });
                                return;
                              }
                              Navigator.of(ctx).pop(passkeyCtrl.text);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _saveToGallery(File file) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved to gallery'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openPreview(File file) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PreviewScreen(imageFile: file),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _handleBack() {
    if (_state == HideState.processing) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.errorRed),
          ),
          title: const Text(
            'Cancel Encoding?',
            style: TextStyle(
              fontFamily: AppTheme.fontMonospace,
              color: AppColors.textWhite,
              fontSize: 16,
            ),
          ),
          content: const Text(
            'Encryption is currently in progress. Exiting will cancel the current operation.',
            style: TextStyle(
              fontFamily: AppTheme.fontMonospace,
              color: AppColors.textGrey,
              fontSize: 12,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('CONTINUE', style: TextStyle(color: AppColors.accentCyan)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() => _state = HideState.idle);
                if (widget.onBackToHome != null) {
                  widget.onBackToHome!();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('CANCEL', style: TextStyle(color: AppColors.errorRed)),
            ),
          ],
        ),
      );
    } else {
      if (widget.onBackToHome != null) {
        widget.onBackToHome!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecurityOverlayWrapper(
      isSensitiveScreen: true,
      child: PopScope(
        canPop: _state != HideState.processing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar with Back Arrow
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _handleBack,
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
                      const SizedBox(width: 16),
                      const GradientTitle(
                        text: 'Hide',
                        fontSize: 28,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Permission Denied Inline Message
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.errorRed, width: 1),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 12,
                          color: AppColors.errorRed,
                        ),
                      ),
                    ),
                  ],

                  // HEADINGS ROW: Left and Right slot headings
                  Row(
                    children: const [
                      Expanded(
                        child: Text(
                          'Cover Image',
                          style: TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textWhite,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Secret Image (1 or more)',
                          style: TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textWhite,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // CONNECTED UPLOAD PAIR WITH PLUS IN THE EXACT MIDDLE
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        children: [
                          // LEFT SLOT: COVER IMAGE
                          Expanded(
                            child: BracketBox(
                              height: 160,
                              cornerColor: AppColors.accentCyan,
                              cornerLength: 16,
                              strokeWidth: 2,
                              backgroundColor: const Color(0x12FFFFFF),
                              hasGlow: _coverImage != null,
                              onTap: _state == HideState.idle ? _pickCoverImage : null,
                              child: _coverImage != null
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.file(
                                            _coverImage!,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        if (_state == HideState.idle)
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _coverImage = null;
                                                  _coverCapacityBytes = 0;
                                                });
                                                _updateButtonAnimation();
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black87,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: AppColors.accentCyan,
                                                  size: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: AppColors.accentCyan,
                                          size: 34,
                                        ),
                                        SizedBox(height: 8),
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            'Select Cover Image',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontMonospace,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textWhite,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          // VERY NARROW GAP BETWEEN BOXES (Tightly bridging with the plus icon)
                          const SizedBox(width: 8),

                          // RIGHT SLOT: SECRET IMAGES
                          Expanded(
                            child: BracketBox(
                              height: 160,
                              cornerColor: AppColors.accentCyan,
                              cornerLength: 16,
                              strokeWidth: 2,
                              backgroundColor: const Color(0x12FFFFFF),
                              hasGlow: _secretImages.isNotEmpty,
                              onTap: _state == HideState.idle ? _pickSecretImages : null,
                              child: _secretImages.isNotEmpty
                                  ? _buildSecretImagesThumbnail()
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.add_photo_alternate_outlined,
                                          color: AppColors.accentCyan,
                                          size: 34,
                                        ),
                                        SizedBox(height: 8),
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            'Select Secret Images',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontMonospace,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textWhite,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),

                      // PLUS SYMBOL IN THE EXACT VERTICAL & HORIZONTAL MIDDLE, TIGHT AGAINST BOTH BOXES
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.accentCyan,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentCyan.withValues(alpha: 0.35),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add,
                            color: AppColors.accentCyan,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // CAPACITY & SIZE INFO ROW
                  Row(
                    children: [
                      Expanded(
                        child: _coverImage != null
                            ? (_isLoadingCapacity
                                ? const Text(
                                    'Computing capacity...',
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontMonospace,
                                      fontSize: 10,
                                      color: AppColors.textGrey,
                                    ),
                                  )
                                : Text(
                                    'Cap: ${_formatBytes(_coverCapacityBytes)}',
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontMonospace,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accentCyan,
                                    ),
                                  ))
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _secretImages.isNotEmpty
                            ? Text(
                                _secretImages.length > 1
                                    ? '${_secretImages.length} files (${_formatBytes(_totalSecretSizeBytes)})'
                                    : 'Size: ${_formatBytes(_totalSecretSizeBytes)}',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMonospace,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _isOverCapacity
                                      ? AppColors.errorRed
                                      : AppColors.accentCyan,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),

                  if (_isOverCapacity) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.errorRed, width: 1),
                      ),
                      child: Text(
                        'Secret payload (${_formatBytes(_totalSecretSizeBytes)}) exceeds cover capacity (${_formatBytes(_coverCapacityBytes)}). Please pick a larger cover image.',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 11,
                          color: AppColors.errorRed,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // MULTI-SELECT TOGGLES: Biometric, Password, Passkey
                  CustomToggle(
                    label: AppStrings.biometric,
                    value: _biometricOn,
                    isEnabled: _state == HideState.idle && _hasBiometricsEnrolled,
                    subtitle: !_hasBiometricsEnrolled
                        ? AppStrings.noBiometricsEnrolled
                        : null,
                    onChanged: (val) {
                      setState(() => _biometricOn = val);
                      _updateButtonAnimation();
                    },
                  ),
                  const Divider(color: AppColors.cardBorder, height: 1),
                  CustomToggle(
                    label: 'Password',
                    value: _passwordOn,
                    isEnabled: _state == HideState.idle,
                    onChanged: (val) {
                      setState(() => _passwordOn = val);
                      _updateButtonAnimation();
                    },
                  ),
                  const Divider(color: AppColors.cardBorder, height: 1),
                  CustomToggle(
                    label: AppStrings.passkey,
                    value: _passkeyOn,
                    isEnabled: _state == HideState.idle,
                    onChanged: (val) {
                      setState(() => _passkeyOn = val);
                      _updateButtonAnimation();
                    },
                  ),

                  const SizedBox(height: 28),

                  // HIDE BUTTON appears as soon as at least one toggle is selected
                  if (_state == HideState.idle)
                    SizeTransition(
                      sizeFactor: _slideFadeAnim,
                      child: FadeTransition(
                        opacity: _slideFadeAnim,
                        child: PrimaryButton(
                          text: AppStrings.hideButton,
                          onPressed: _canShowHideButton ? _startHideWorkflow : null,
                        ),
                      ),
                    ),

                  // PROGRESS BAR during Hide workflow
                  if (_state == HideState.processing) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'ENCRYPTING & EMBEDDING SECRET IMAGES...',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentCyan,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _encodeProgress,
                      backgroundColor: const Color(0xFF222222),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_encodeProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],

                  // ONCE COMPLETE: DOWNLOAD AND VIEW BUTTONS SIDE BY SIDE
                  if (_state == HideState.done && _outputFile != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.accentCyan, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.check_circle_outline,
                                color: AppColors.accentCyan,
                                size: 24,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'STEGANOGRAPHY COMPLETED',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMonospace,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentCyan,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Image.file(
                                    _outputFile!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _outputFile!.path.split(Platform.pathSeparator).last,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontMonospace,
                                    fontSize: 12,
                                    color: AppColors.textWhite,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // DOWNLOAD and VIEW buttons side by side
                          Row(
                            children: [
                              Expanded(
                                child: PrimaryButton(
                                  text: 'DOWNLOAD',
                                  icon: Icons.download_outlined,
                                  onPressed: () => _saveToGallery(_outputFile!),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PrimaryButton(
                                  text: 'VIEW',
                                  icon: Icons.visibility_outlined,
                                  borderColor: AppColors.accentCyan,
                                  onPressed: () => _openPreview(_outputFile!),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _state = HideState.idle;
                            _coverImage = null;
                            _secretImages.clear();
                            _totalSecretSizeBytes = 0;
                            _coverCapacityBytes = 0;
                            _outputFile = null;
                            _biometricOn = false;
                            _passwordOn = false;
                            _passkeyOn = false;
                          });
                        },
                        child: const Text(
                          'HIDE ANOTHER FILE',
                          style: TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecretImagesThumbnail() {
    if (_secretImages.length == 1) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(_secretImages[0], fit: BoxFit.cover),
          ),
          if (_state == HideState.idle)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _secretImages.clear();
                    _totalSecretSizeBytes = 0;
                  });
                  _updateButtonAnimation();
                },
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.errorRed,
                    size: 14,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Stacked thumbnail treatment for multiple images
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_secretImages.length > 2)
          Transform.translate(
            offset: const Offset(8, -6),
            child: Transform.rotate(
              angle: 0.08,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 95,
                  height: 95,
                  child: Image.file(_secretImages[2], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        Transform.translate(
          offset: const Offset(-6, -4),
          child: Transform.rotate(
            angle: -0.06,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 100,
                height: 100,
                child: Image.file(_secretImages[1], fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 108,
            height: 108,
            child: Image.file(_secretImages[0], fit: BoxFit.cover),
          ),
        ),
        Positioned(
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentCyan, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers, color: AppColors.accentCyan, size: 12),
                const SizedBox(width: 4),
                Text(
                  '${_secretImages.length} Images',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_state == HideState.idle)
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _secretImages.clear();
                  _totalSecretSizeBytes = 0;
                });
                _updateButtonAnimation();
              },
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: AppColors.errorRed,
                  size: 14,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
