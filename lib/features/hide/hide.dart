import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
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

enum HideScreenState { idle, processing, done }

class QueueFileItem {
  final File secretFile;
  final String filename;
  final bool isImage;
  final String extension;
  final int sizeBytes;
  double progress;
  bool isCompleted;
  File? outputFile;
  int? dbId;
  String? error;

  QueueFileItem({
    required this.secretFile,
    required this.filename,
    required this.isImage,
    required this.extension,
    required this.sizeBytes,
    this.progress = 0.0,
    this.isCompleted = false,
    this.outputFile,
    this.dbId,
    this.error,
  });
}

class HideScreen extends StatefulWidget {
  final VoidCallback? onGoHome;

  const HideScreen({super.key, this.onGoHome});

  @override
  State<HideScreen> createState() => _HideScreenState();
}

class _HideScreenState extends State<HideScreen>
    with SingleTickerProviderStateMixin {
  File? _coverImage;
  int _coverCapacityBytes = 0;
  bool _isLoadingCapacity = false;

  final List<File> _secretFiles = [];
  int _totalSecretSizeBytes = 0;

  // 2 independent toggles
  bool _biometricOn = false;
  bool _passkeyOn = false;
  bool _hasBiometricsEnrolled = false;

  HideScreenState _state = HideScreenState.idle;
  final List<QueueFileItem> _queueItems = [];
  String? _errorMessage;

  final ImagePicker _imagePicker = ImagePicker();
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

  bool _isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(ext);
  }

  String _getFileExtension(String path) {
    if (!path.contains('.')) return 'FILE';
    return path.split('.').last.toUpperCase();
  }

  bool get _isOverCapacity =>
      _coverImage != null &&
      _secretFiles.isNotEmpty &&
      _coverCapacityBytes > 0 &&
      _totalSecretSizeBytes > _coverCapacityBytes;

  bool get _hasAnyToggleOn => _biometricOn || _passkeyOn;

  bool get _canShowHideButton =>
      _coverImage != null &&
      _secretFiles.isNotEmpty &&
      !_isOverCapacity &&
      _hasAnyToggleOn &&
      _state == HideScreenState.idle;

  void _updateButtonAnimation() {
    if (_canShowHideButton) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  Future<void> _showPickCoverModal() async {
    if (_state == HideScreenState.processing) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              top: BorderSide(color: AppColors.accentCyan, width: 1.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SELECT COVER IMAGE',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.accentCyan),
                title: const Text('Photo Gallery', style: TextStyle(fontFamily: AppTheme.fontMonospace, color: AppColors.textWhite)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickCover(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.accentCyan),
                title: const Text('Camera', style: TextStyle(fontFamily: AppTheme.fontMonospace, color: AppColors.textWhite)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickCover(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickCover(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(source: source);
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
    } catch (_) {
      if (mounted) {
        await TriCryptPermissionDialog.show(
          context,
          permissionName: 'Camera / Photo Library',
          description: 'TriCrypt requires permission to pick a cover image.',
          icon: Icons.camera_alt_outlined,
        );
      }
    }
  }

  Future<void> _pickSecretFiles() async {
    if (_state == HideScreenState.processing) return;

    try {
      final List<PlatformFile> pickedFiles = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (pickedFiles.isNotEmpty) {
        final List<File> newlySelected = [];
        final int currentCount = _secretFiles.length;

        for (final platformFile in pickedFiles) {
          if (platformFile.path != null) {
            newlySelected.add(File(platformFile.path!));
          }
        }

        if (currentCount + newlySelected.length > 10) {
          setState(() {
            _errorMessage = AppStrings.maxSelectionsError;
          });
          final allowedCount = 10 - currentCount;
          if (allowedCount > 0) {
            _appendSecrets(newlySelected.take(allowedCount).toList());
          }
        } else {
          setState(() => _errorMessage = null);
          _appendSecrets(newlySelected);
        }
      }
    } catch (_) {}
  }

  void _appendSecrets(List<File> files) {
    int addedBytes = 0;
    for (final f in files) {
      try {
        addedBytes += f.lengthSync();
      } catch (_) {
        addedBytes += 1024 * 300;
      }
    }

    setState(() {
      _secretFiles.addAll(files);
      _totalSecretSizeBytes += addedBytes;
    });
    _updateButtonAnimation();
  }

  void _removeSecretFile(int index) {
    if (_state == HideScreenState.processing) return;
    final file = _secretFiles[index];
    int size = 0;
    try {
      size = file.lengthSync();
    } catch (_) {
      size = 1024 * 300;
    }

    setState(() {
      _secretFiles.removeAt(index);
      _totalSecretSizeBytes = (_totalSecretSizeBytes - size).clamp(0, double.infinity).toInt();
      _errorMessage = null;
    });
    _updateButtonAnimation();
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

  Future<void> _startHideWorkflow() async {
    if (!_canShowHideButton) return;

    // Silent capacity re-check before processing starts per prompt Section 7
    final recheckedCapacity = await TriCryptStubs.getCoverCapacity(_coverImage!);
    if (_totalSecretSizeBytes > recheckedCapacity) {
      setState(() {
        _coverCapacityBytes = recheckedCapacity;
        _errorMessage = AppStrings.overCapacityError(
          _formatBytes(_totalSecretSizeBytes),
          _formatBytes(recheckedCapacity),
        );
      });
      return;
    }

    String passkeyVal = '';

    // Step 1: If Passkey on: dialog with Passkey + Confirm Passkey
    if (_passkeyOn) {
      final pKey = await _showPasskeyDialog();
      if (pKey == null) return; // Cancelled
      passkeyVal = pKey;
    }

    // Step 2: If Biometric on: biometric prompt
    if (_biometricOn) {
      final bioSuccess = await _biometricService.authenticate(
        reason: 'Authenticate to encrypt and hide your secret files',
      );
      if (!bioSuccess) {
        setState(() {
          _errorMessage = 'Biometric authentication was not completed.';
        });
        return;
      }
    }

    // Both on -> HKDF combined credential
    String combinedCred = '';
    String encryptionType = '';
    if (_biometricOn && _passkeyOn) {
      combinedCred = 'both:pk:$passkeyVal:bio:authenticated';
      encryptionType = 'both';
    } else if (_passkeyOn) {
      combinedCred = 'pk:$passkeyVal';
      encryptionType = 'passkey';
    } else {
      combinedCred = 'bio:authenticated';
      encryptionType = 'biometric';
    }

    // Setup queue items
    _queueItems.clear();
    for (final sf in _secretFiles) {
      final fname = sf.path.split(Platform.pathSeparator).last;
      int size = 0;
      try {
        size = sf.lengthSync();
      } catch (_) {
        size = 1024 * 300;
      }

      _queueItems.add(
        QueueFileItem(
          secretFile: sf,
          filename: fname,
          isImage: _isImageFile(sf.path),
          extension: _getFileExtension(sf.path),
          sizeBytes: size,
        ),
      );
    }

    setState(() {
      _state = HideScreenState.processing;
      _errorMessage = null;
    });

    try {
      await TriCryptStubs.encodeImage(
        _coverImage!,
        _secretFiles,
        combinedCred,
        (fileIndex, progress) {
          if (mounted && fileIndex < _queueItems.length) {
            setState(() {
              _queueItems[fileIndex].progress = progress;
            });
          }
        },
        onFileEncoded: (fileIndex, outFile) async {
          if (fileIndex < _queueItems.length) {
            final filename = outFile.path.split(Platform.pathSeparator).last;
            final dbId = await _albumDb.insertItem(
              AlbumItem(
                filename: filename,
                filepath: outFile.path,
                type: 'encoded',
                encryptionType: encryptionType,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                thumbnailPath: _coverImage!.path,
              ),
            );

            await _secureStore.saveFileCredential('$dbId', combinedCred);

            if (mounted) {
              setState(() {
                _queueItems[fileIndex].isCompleted = true;
                _queueItems[fileIndex].outputFile = outFile;
                _queueItems[fileIndex].dbId = dbId;
              });
            }
          }
        },
      );

      if (mounted) {
        setState(() {
          _state = HideScreenState.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Operation failed: $e';
          _state = HideScreenState.idle;
        });
      }
    }
  }

  Future<void> _saveOutputToGallery(File file) async {
    try {
      await Gal.putImage(file.path);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to gallery'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _downloadAll() async {
    int savedCount = 0;
    for (final item in _queueItems) {
      if (item.outputFile != null) {
        try {
          await Gal.putImage(item.outputFile!.path);
          savedCount++;
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $savedCount files to gallery'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openPreview(File file) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => PreviewScreen(imageFile: file),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _resetToIdle() {
    setState(() {
      _state = HideScreenState.idle;
      _coverImage = null;
      _coverCapacityBytes = 0;
      _secretFiles.clear();
      _totalSecretSizeBytes = 0;
      _queueItems.clear();
      _errorMessage = null;
      _biometricOn = false;
      _passkeyOn = false;
    });
    _updateButtonAnimation();
  }

  Future<bool> _handleCancelCheck() async {
    if (_state != HideScreenState.processing) {
      _resetToIdle();
      return true;
    }

    final bool? shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.errorRed),
        ),
        title: const Text(
          'Cancel Processing?',
          style: TextStyle(
            fontFamily: AppTheme.fontMonospace,
            color: AppColors.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Encoding is currently running. Leaving will abort the remaining files in the queue.',
          style: TextStyle(
            fontFamily: AppTheme.fontMonospace,
            color: AppColors.textGrey,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CONTINUE', style: TextStyle(color: AppColors.accentCyan)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CANCEL OPERATION', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );

    if (shouldCancel == true) {
      _resetToIdle();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SecurityOverlayWrapper(
      isSensitiveScreen: true,
      child: PopScope(
        canPop: _state != HideScreenState.processing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleCancelCheck();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title: "Hide". No back arrow.
                  const GradientTitle(
                    text: 'Hide',
                    fontSize: 28,
                  ),

                  const SizedBox(height: 20),

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
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],

                  if (_state == HideScreenState.idle) ...[
                    // COVER IMAGE: One square upload box (1:1), "+" icon centered, label above.
                    const Text(
                      'COVER IMAGE',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentCyan,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Center(
                      child: BracketBox(
                        width: 170,
                        height: 170,
                        cornerColor: AppColors.accentCyan,
                        cornerLength: 20,
                        strokeWidth: 2,
                        backgroundColor: const Color(0x12FFFFFF),
                        hasGlow: _coverImage != null,
                        onTap: _showPickCoverModal,
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
                                        padding: const EdgeInsets.all(4),
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
                                    Icons.add,
                                    color: AppColors.accentCyan,
                                    size: 44,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Select Cover Image',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
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

                    // Capacity line directly below the cover box
                    if (_coverImage != null) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: _isLoadingCapacity
                            ? const Text(
                                'Computing capacity...',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMonospace,
                                  fontSize: 11,
                                  color: AppColors.textGrey,
                                ),
                              )
                            : Text(
                                _secretFiles.isEmpty
                                    ? 'Capacity: ${_formatBytes(_coverCapacityBytes)}'
                                    : 'Capacity: ${_formatBytes(_coverCapacityBytes)} · Using ${_formatBytes(_totalSecretSizeBytes)}',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMonospace,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _isOverCapacity
                                      ? AppColors.errorRed
                                      : AppColors.accentCyan,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // SECRET FILES: separate multi-select picker below, label "SECRET FILES (1–10)"
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          AppStrings.secretFiles,
                          style: TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentCyan,
                            letterSpacing: 1.5,
                          ),
                        ),
                        if (_secretFiles.isNotEmpty)
                          Text(
                            '${_secretFiles.length} of 10 selected',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontMonospace,
                              fontSize: 11,
                              color: AppColors.textGrey,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Secret files selector & horizontal thumbnail strip
                    if (_secretFiles.isEmpty)
                      BracketBox(
                        width: double.infinity,
                        height: 90,
                        cornerColor: AppColors.accentCyan,
                        cornerLength: 16,
                        strokeWidth: 1.5,
                        backgroundColor: const Color(0x12FFFFFF),
                        onTap: _pickSecretFiles,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add_circle_outline, color: AppColors.accentCyan, size: 28),
                            SizedBox(width: 12),
                            Text(
                              'Add Secret Files (Photo, PDF, Doc...)',
                              style: TextStyle(
                                fontFamily: AppTheme.fontMonospace,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textWhite,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _secretFiles.length < 10
                              ? _secretFiles.length + 1
                              : _secretFiles.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (ctx, index) {
                            if (index == _secretFiles.length) {
                              // Add more box
                              return GestureDetector(
                                onTap: _pickSecretFiles,
                                child: BracketBox(
                                  width: 80,
                                  height: 100,
                                  cornerLength: 12,
                                  strokeWidth: 1.5,
                                  backgroundColor: const Color(0x12FFFFFF),
                                  child: const Center(
                                    child: Icon(Icons.add, color: AppColors.accentCyan, size: 28),
                                  ),
                                ),
                              );
                            }

                            final file = _secretFiles[index];
                            final isImg = _isImageFile(file.path);
                            final ext = _getFileExtension(file.path);

                            return BracketBox(
                              width: 80,
                              height: 100,
                              cornerLength: 12,
                              strokeWidth: 1.5,
                              padding: EdgeInsets.zero,
                              backgroundColor: AppColors.card,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (isImg)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.file(file, fit: BoxFit.cover),
                                    )
                                  else
                                    Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.insert_drive_file_outlined,
                                            color: AppColors.accentCyan,
                                            size: 32,
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentCyan.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              ext,
                                              style: const TextStyle(
                                                fontFamily: AppTheme.fontMonospace,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.accentCyan,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => _removeSecretFile(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.black87,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: AppColors.errorRed,
                                          size: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (_isOverCapacity) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.overCapacityError(
                            _formatBytes(_totalSecretSizeBytes),
                            _formatBytes(_coverCapacityBytes),
                          ),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 11,
                            color: AppColors.errorRed,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),

                    // 2 INDEPENDENT TOGGLES: BIOMETRIC and PASSKEY
                    CustomToggle(
                      label: AppStrings.biometric,
                      value: _biometricOn,
                      isEnabled: _hasBiometricsEnrolled,
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
                      label: AppStrings.passkey,
                      value: _passkeyOn,
                      onChanged: (val) {
                        setState(() => _passkeyOn = val);
                        _updateButtonAnimation();
                      },
                    ),

                    const SizedBox(height: 28),

                    // HIDE BUTTON: Fades/slides in only when criteria met
                    SizeTransition(
                      sizeFactor: _slideFadeAnim,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(
                        opacity: _slideFadeAnim,
                        child: PrimaryButton(
                          text: AppStrings.hideButton,
                          icon: Icons.lock,
                          onPressed: _canShowHideButton ? _startHideWorkflow : null,
                        ),
                      ),
                    ),
                  ] else ...[
                    // Processing / Done State: QUEUE LIST
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _state == HideScreenState.processing
                              ? 'PROCESSING QUEUE (${_queueItems.where((q) => q.isCompleted).length}/${_queueItems.length})'
                              : 'ENCRYPTION COMPLETED',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentCyan,
                            letterSpacing: 1.5,
                          ),
                        ),
                        if (_state == HideScreenState.processing)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentCyan,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _queueItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (ctx, index) {
                        final item = _queueItems[index];

                        return BracketBox(
                          cornerLength: 12,
                          strokeWidth: 1.5,
                          padding: const EdgeInsets.all(12),
                          backgroundColor: AppColors.card,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Thumbnail
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: item.isImage
                                          ? Image.file(item.secretFile, fit: BoxFit.cover)
                                          : Container(
                                              color: AppColors.accentCyan.withValues(alpha: 0.15),
                                              child: Center(
                                                child: Text(
                                                  item.extension,
                                                  style: const TextStyle(
                                                    fontFamily: AppTheme.fontMonospace,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.accentCyan,
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Filename & Size
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.filename,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontMonospace,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textWhite,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _formatBytes(item.sizeBytes),
                                          style: const TextStyle(
                                            fontFamily: AppTheme.fontMonospace,
                                            fontSize: 10,
                                            color: AppColors.textGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Completion Check or Percent
                                  if (item.isCompleted)
                                    const Icon(Icons.check_circle, color: AppColors.accentCyan, size: 20)
                                  else
                                    Text(
                                      '${(item.progress * 100).toInt()}%',
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontMonospace,
                                        fontSize: 11,
                                        color: AppColors.accentCyan,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Determinate progress bar
                              LinearProgressIndicator(
                                value: item.progress,
                                backgroundColor: const Color(0xFF222222),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  item.isCompleted ? AppColors.accentCyan : AppColors.accentCyan.withValues(alpha: 0.8),
                                ),
                                minHeight: 4,
                              ),

                              // Per-row Download & View actions when hits 100%
                              if (item.isCompleted && item.outputFile != null) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: PrimaryButton(
                                        text: 'DOWNLOAD',
                                        height: 36,
                                        icon: Icons.download_outlined,
                                        onPressed: () => _saveOutputToGallery(item.outputFile!),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: PrimaryButton(
                                        text: 'VIEW',
                                        height: 36,
                                        icon: Icons.visibility_outlined,
                                        borderColor: AppColors.accentCyan,
                                        onPressed: () => _openPreview(item.outputFile!),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // "Download all" button once every row is done
                    if (_state == HideScreenState.done) ...[
                      PrimaryButton(
                        text: 'DOWNLOAD ALL',
                        icon: Icons.download_for_offline_outlined,
                        onPressed: _downloadAll,
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _resetToIdle,
                          child: const Text(
                            'HIDE MORE FILES',
                            style: TextStyle(
                              fontFamily: AppTheme.fontMonospace,
                              fontSize: 12,
                              color: AppColors.accentCyan,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
