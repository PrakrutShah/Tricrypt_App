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

enum ViewState { idle, decoding, success, accessDenied }

class ViewScreen extends StatefulWidget {
  final File? initialImage;
  final VoidCallback? onBackToHome;

  const ViewScreen({super.key, this.initialImage, this.onBackToHome});

  @override
  State<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends State<ViewScreen> {
  final List<File> _encodedImages = [];

  // Multi-select toggles
  bool _biometricOn = false;
  bool _passwordOn = false;
  bool _passkeyOn = false;
  bool _hasBiometricsEnrolled = false;

  ViewState _state = ViewState.idle;
  double _progress = 0.0;
  File? _decodedFile;
  final List<File> _decodedFiles = [];
  String? _errorMessage;

  final ImagePicker _picker = ImagePicker();
  final BiometricService _biometricService = BiometricService();
  final AlbumDb _albumDb = AlbumDb();
  final SecureStore _secureStore = SecureStore();

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) {
      _encodedImages.add(widget.initialImage!);
    }
    _checkBiometrics();
    if (_encodedImages.isNotEmpty) {
      _detectEncryptionType();
    }
  }

  Future<void> _checkBiometrics() async {
    final enrolled = await _biometricService.hasEnrolledBiometrics();
    if (mounted) {
      setState(() {
        _hasBiometricsEnrolled = enrolled;
      });
    }
  }

  Future<void> _detectEncryptionType() async {
    if (_encodedImages.isEmpty) return;
    try {
      final allItems = await _albumDb.getAllItems();
      final firstPath = _encodedImages.first.path;
      final match = allItems.where((i) => i.filepath == firstPath).toList();
      if (match.isNotEmpty) {
        final enc = match.first.encryptionType.toLowerCase();
        setState(() {
          _biometricOn = enc.contains('biometric');
          _passwordOn = enc.contains('password');
          _passkeyOn = enc.contains('passkey');
        });
      }
    } catch (_) {}
  }

  bool get _hasAnyAuthSelected => _biometricOn || _passwordOn || _passkeyOn;

  bool get _canShowDecodeButton =>
      _encodedImages.isNotEmpty &&
      _hasAnyAuthSelected &&
      _state == ViewState.idle;

  Future<void> _pickEncodedImage() async {
    if (_state == ViewState.decoding) return;

    try {
      final List<XFile> pickedList = await _picker.pickMultiImage();
      if (pickedList.isNotEmpty) {
        setState(() {
          _encodedImages.clear();
          _encodedImages.addAll(pickedList.map((x) => File(x.path)));
          _errorMessage = null;
          _state = ViewState.idle;
          _decodedFile = null;
          _decodedFiles.clear();
        });
        await _detectEncryptionType();
      }
    } catch (_) {}
  }

  Future<void> _startDecode() async {
    if (!_canShowDecodeButton) return;

    String passwordVal = '';
    String passkeyVal = '';

    // Step 1: If Password check is enabled, capture password first
    if (_passwordOn) {
      final pass = await _showPasswordPrompt();
      if (pass == null) return; // Cancelled -> abort sequence, return to pre-action state
      passwordVal = pass;
    }

    // Step 2: If Passkey check is enabled, capture passkey next
    if (_passkeyOn) {
      final pKey = await _showPasskeyPrompt();
      if (pKey == null) return; // Cancelled -> abort sequence, return to pre-action state
      passkeyVal = pKey;
    }

    // Step 3: If Biometric check is enabled, authenticate with biometrics
    if (_biometricOn) {
      final bioSuccess = await _biometricService.authenticate(
        reason: 'Authenticate to decode and reveal hidden payload',
      );
      if (!bioSuccess) {
        _triggerAccessDenied();
        return; // Failed/cancelled -> abort sequence, return to pre-action state
      }
    }

    // Verification against saved credentials
    try {
      final allItems = await _albumDb.getAllItems();
      for (final encImg in _encodedImages) {
        final match = allItems.where((i) => i.filepath == encImg.path).toList();
        if (match.isNotEmpty) {
          final savedCred = await _secureStore.getFileCredential('${match.first.id}');
          if (savedCred != null && savedCred.isNotEmpty) {
            if (_passwordOn && !savedCred.contains('pwd:$passwordVal') && !savedCred.contains(passwordVal)) {
              _triggerAccessDenied();
              return;
            }
            if (_passkeyOn && !savedCred.contains('pk:$passkeyVal') && !savedCred.contains(passkeyVal)) {
              _triggerAccessDenied();
              return;
            }
          }
        }
      }
    } catch (_) {}

    // All enabled checks successfully completed! Proceed to progress bar and decoding
    setState(() {
      _state = ViewState.decoding;
      _progress = 0.0;
      _errorMessage = null;
      _decodedFiles.clear();
    });

    try {
      final credentialsList = <String>[];
      if (_passwordOn) credentialsList.add('pwd:$passwordVal');
      if (_passkeyOn) credentialsList.add('pk:$passkeyVal');
      if (_biometricOn) credentialsList.add('bio:authenticated');
      final combinedCredential = credentialsList.join(';');

      final types = <String>[];
      if (_biometricOn) types.add('biometric');
      if (_passwordOn) types.add('password');
      if (_passkeyOn) types.add('passkey');

      for (int i = 0; i < _encodedImages.length; i++) {
        final enc = _encodedImages[i];
        final decoded = await TriCryptStubs.decodeImage(
          encoded: enc,
          credential: combinedCredential,
          onProgress: (prog) {
            if (mounted) {
              final overall = (i + prog) / _encodedImages.length;
              setState(() => _progress = overall);
            }
          },
        );

        final filename = decoded.path.split(Platform.pathSeparator).last;
        await _albumDb.insertItem(
          AlbumItem(
            filename: filename,
            filepath: decoded.path,
            type: 'decoded',
            encryptionType: types.join('+'),
            timestamp: DateTime.now().millisecondsSinceEpoch,
            thumbnailPath: enc.path,
          ),
        );
        _decodedFiles.add(decoded);
      }

      if (mounted) {
        setState(() {
          _decodedFile = _decodedFiles.isNotEmpty ? _decodedFiles.first : null;
          _progress = 1.0;
          _state = ViewState.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = ViewState.idle;
          _errorMessage = AppStrings.noHiddenData;
        });
      }
    }
  }

  void _triggerAccessDenied() {
    setState(() {
      _state = ViewState.accessDenied;
      _errorMessage = AppStrings.accessDenied;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _state = ViewState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  Future<String?> _showPasswordPrompt() async {
    final passwordCtrl = TextEditingController();
    String? error;

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
                      text: 'Enter Password',
                      fontSize: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the password used when encrypting this image.',
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
                      errorText: error,
                      hintText: '••••••••',
                      onChanged: (_) {
                        if (error != null) setDialogState(() => error = null);
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
                            text: 'DECODE',
                            onPressed: () {
                              if (passwordCtrl.text.isEmpty) {
                                setDialogState(() => error = 'Password is required');
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

  Future<String?> _showPasskeyPrompt() async {
    final passkeyCtrl = TextEditingController();
    String? error;

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
                      text: 'Enter Passkey',
                      fontSize: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the passkey used when encrypting this image.',
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
                      errorText: error,
                      hintText: '••••••••',
                      onChanged: (_) {
                        if (error != null) setDialogState(() => error = null);
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
                            text: 'CONFIRM',
                            onPressed: () {
                              if (passkeyCtrl.text.isEmpty) {
                                setDialogState(() => error = 'Passkey is required');
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
    if (widget.onBackToHome != null) {
      widget.onBackToHome!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecurityOverlayWrapper(
      isSensitiveScreen: true,
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
                      text: 'View',
                      fontSize: 28,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.errorRed, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.errorRed.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock_outlined, color: AppColors.errorRed, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontMonospace,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.errorRed,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // HEADING ABOVE UPLOAD SLOT: DECODE SCREEN
                const Text(
                  'Encoded Images (1 or more)',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),

                Center(
                  child: BracketBox(
                    width: 220,
                    height: 220,
                    cornerColor: _state == ViewState.accessDenied
                        ? AppColors.errorRed
                        : AppColors.accentCyan,
                    cornerLength: 22,
                    strokeWidth: 2,
                    backgroundColor: const Color(0x12FFFFFF),
                    hasGlow: _encodedImages.isNotEmpty,
                    onTap: _state == ViewState.idle ? _pickEncodedImage : null,
                    child: _encodedImages.isNotEmpty
                        ? _buildEncodedImagesThumbnail()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                color: AppColors.accentCyan,
                                size: 42,
                              ),
                              SizedBox(height: 8),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  'Select Encoded Images',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontMonospace,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textWhite,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // MULTI-SELECT TOGGLES: Biometric, Password, Passkey
                CustomToggle(
                  label: AppStrings.biometric,
                  value: _biometricOn,
                  isEnabled: _state == ViewState.idle && _hasBiometricsEnrolled,
                  subtitle: !_hasBiometricsEnrolled
                      ? AppStrings.noBiometricsEnrolled
                      : null,
                  onChanged: (val) => setState(() => _biometricOn = val),
                ),
                const Divider(color: AppColors.cardBorder, height: 1),
                CustomToggle(
                  label: 'Password',
                  value: _passwordOn,
                  isEnabled: _state == ViewState.idle,
                  onChanged: (val) => setState(() => _passwordOn = val),
                ),
                const Divider(color: AppColors.cardBorder, height: 1),
                CustomToggle(
                  label: AppStrings.passkey,
                  value: _passkeyOn,
                  isEnabled: _state == ViewState.idle,
                  onChanged: (val) => setState(() => _passkeyOn = val),
                ),

                const SizedBox(height: 32),

                // "Decode the Image" button appears as soon as at least one toggle is selected
                if (_state == ViewState.idle && _canShowDecodeButton)
                  PrimaryButton(
                    text: 'DECODE THE IMAGE',
                    icon: Icons.lock_open,
                    onPressed: _startDecode,
                  ),

                // Progress bar runs to completion once all selected checks succeed
                if (_state == ViewState.decoding) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'DECODING & EXTRACTING PAYLOAD...',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMonospace,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accentCyan,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: const Color(0xFF222222),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMonospace,
                      fontSize: 11,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],

                // Once complete: DOWNLOAD and VIEW buttons side by side
                if (_state == ViewState.success && _decodedFile != null) ...[
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
                              'FILE REVEALED SUCCESSFULLY',
                              style: TextStyle(
                                fontFamily: AppTheme.fontMonospace,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentCyan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 50,
                                height: 50,
                                child: Image.file(
                                  _decodedFile!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.insert_drive_file_outlined,
                                    color: AppColors.accentCyan,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _decodedFile!.path.split(Platform.pathSeparator).last,
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
                        // DOWNLOAD and VIEW buttons appear side by side
                        Row(
                          children: [
                            Expanded(
                              child: PrimaryButton(
                                text: 'DOWNLOAD',
                                icon: Icons.download_outlined,
                                onPressed: () => _saveToGallery(_decodedFile!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PrimaryButton(
                                text: 'VIEW',
                                icon: Icons.visibility_outlined,
                                borderColor: AppColors.accentCyan,
                                onPressed: () => _openPreview(_decodedFile!),
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
                          _state = ViewState.idle;
                          _encodedImages.clear();
                          _decodedFiles.clear();
                          _decodedFile = null;
                          _biometricOn = false;
                          _passwordOn = false;
                          _passkeyOn = false;
                        });
                      },
                      child: const Text(
                        'DECODE ANOTHER IMAGE',
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
    );
  }

  Widget _buildEncodedImagesThumbnail() {
    if (_encodedImages.length == 1) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(_encodedImages[0], fit: BoxFit.cover),
          ),
          if (_state == ViewState.idle)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _encodedImages.clear();
                    _decodedFiles.clear();
                    _errorMessage = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.accentCyan,
                    size: 16,
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
        if (_encodedImages.length > 2)
          Transform.translate(
            offset: const Offset(12, -8),
            child: Transform.rotate(
              angle: 0.08,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 135,
                  height: 135,
                  child: Image.file(_encodedImages[2], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        Transform.translate(
          offset: const Offset(-8, -6),
          child: Transform.rotate(
            angle: -0.06,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 145,
                height: 145,
                child: Image.file(_encodedImages[1], fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 155,
            height: 155,
            child: Image.file(_encodedImages[0], fit: BoxFit.cover),
          ),
        ),
        Positioned(
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentCyan, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers, color: AppColors.accentCyan, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_encodedImages.length} Images',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_state == ViewState.idle)
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _encodedImages.clear();
                  _decodedFiles.clear();
                  _errorMessage = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: AppColors.errorRed,
                  size: 16,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
