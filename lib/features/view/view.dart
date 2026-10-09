import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../backend/stego.dart';
import '../../core/constants.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/album_db.dart';
import '../../data/stubs.dart';
import '../preview/preview.dart';

enum ViewScreenState { idle, processing, done }

enum ItemDecodeStatus {
  pending,
  missingCredential,
  decoding,
  success,
  accessDenied,
  notTriCrypt,
}

class ViewQueueItem {
  final File encodedFile;
  final String filename;
  String encryptionType; // 'biometric', 'passkey', 'both'
  ItemDecodeStatus status;
  double progress;
  File? decodedResult;
  String? missingType; // 'passkey' or 'biometric'
  String? satisfiedCredential;

  ViewQueueItem({
    required this.encodedFile,
    required this.filename,
    this.encryptionType = 'passkey',
    this.status = ItemDecodeStatus.pending,
    this.progress = 0.0,
    this.decodedResult,
    this.missingType,
    this.satisfiedCredential,
  });

  bool get isImageResult {
    if (decodedResult == null) return false;
    final ext = decodedResult!.path.toLowerCase().split('.').last;
    return ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(ext);
  }
}

class ViewScreen extends StatefulWidget {
  final File? initialImage;
  final VoidCallback? onGoHome;

  const ViewScreen({super.key, this.initialImage, this.onGoHome});

  @override
  State<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends State<ViewScreen> {
  final List<File> _encodedImages = [];
  final List<ViewQueueItem> _queueItems = [];

  ViewScreenState _state = ViewScreenState.idle;
  String? _errorMessage;

  final ImagePicker _imagePicker = ImagePicker();
  final BiometricService _biometricService = BiometricService();
  final AlbumDb _albumDb = AlbumDb();
  String? _enteredPasskey;

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) {
      _encodedImages.add(widget.initialImage!);
      _autoGroupByAuthType();
    }
  }

  Future<void> _pickEncodedImages() async {
    if (_state == ViewScreenState.processing) return;

    try {
      final List<XFile> pickedList = await _imagePicker.pickMultiImage();
      if (pickedList.isNotEmpty) {
        final currentCount = _encodedImages.length;
        final newlySelected = pickedList.map((x) => File(x.path)).toList();

        if (currentCount + newlySelected.length > 10) {
          setState(() {
            _errorMessage = AppStrings.maxSelectionsError;
          });
          final allowed = 10 - currentCount;
          if (allowed > 0) {
            _encodedImages.addAll(newlySelected.take(allowed));
          }
        } else {
          setState(() => _errorMessage = null);
          _encodedImages.addAll(newlySelected);
        }

        await _autoGroupByAuthType();
      }
    } catch (_) {}
  }

  void _removeEncodedImage(int index) {
    if (_state == ViewScreenState.processing) return;
    setState(() {
      _encodedImages.removeAt(index);
      _errorMessage = null;
    });
    _autoGroupByAuthType();
  }

  Future<void> _autoGroupByAuthType() async {
    _queueItems.clear();
    final allDbItems = await _albumDb.getAllItems();

    for (final img in _encodedImages) {
      final fname = img.path.split(Platform.pathSeparator).last;
      String encType = 'passkey'; // Default fallback

      try {
        final bytes = await img.readAsBytes();
        final headerType = await TriCryptStego.inspectEncryptionType(bytes);
        if (headerType != null) {
          encType = headerType;
        } else {
          final match = allDbItems.where(
            (i) => i.filepath == img.path || i.filename == fname,
          );
          if (match.isNotEmpty) {
            final rawType = match.first.encryptionType.toLowerCase();
            if (rawType.contains('both')) {
              encType = 'both';
            } else if (rawType.contains('biometric')) {
              encType = 'biometric';
            } else {
              encType = 'passkey';
            }
          }
        }
      } catch (_) {
        // Fallback
      }

      _queueItems.add(
        ViewQueueItem(
          encodedFile: img,
          filename: fname,
          encryptionType: encType,
        ),
      );
    }

    if (mounted) setState(() {});
  }

  Future<String?> _showPasskeyPrompt({String title = 'Enter Passkey'}) async {
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
                    GradientTitle(
                      text: title,
                      fontSize: 22,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the passkey associated with this encrypted image.',
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

  Future<void> _startRevealSequence() async {
    if (_encodedImages.isEmpty) return;

    setState(() {
      _state = ViewScreenState.processing;
      _errorMessage = null;
    });

    // Check which groups are present
    final hasBiometricGroup = _queueItems.any((i) => i.encryptionType == 'biometric');
    final hasPasskeyGroup = _queueItems.any((i) => i.encryptionType == 'passkey');
    final hasBothGroup = _queueItems.any((i) => i.encryptionType == 'both');

    String? passkeyVal;
    bool biometricPassed = false;

    // Sequential group unlocking:
    // 1. Passkey-only group
    if (hasPasskeyGroup) {
      passkeyVal = await _showPasskeyPrompt(title: 'Passkey Required');
      _enteredPasskey = passkeyVal;
      if (passkeyVal == null) {
        // User cancelled passkey prompt for passkey-only group
        for (final item in _queueItems.where((i) => i.encryptionType == 'passkey')) {
          item.status = ItemDecodeStatus.accessDenied;
        }
      }
    }

    // 2. Biometric-only group
    if (hasBiometricGroup) {
      biometricPassed = await _biometricService.authenticate(
        reason: 'Authenticate to reveal biometric-secured images',
      );
      if (!biometricPassed) {
        for (final item in _queueItems.where((i) => i.encryptionType == 'biometric')) {
          item.status = ItemDecodeStatus.accessDenied;
        }
      }
    }

    // 3. Both group (Passkey first, then Biometric)
    if (hasBothGroup) {
      String? bothPasskey = passkeyVal;
      bothPasskey ??= await _showPasskeyPrompt(title: 'Passkey Required');
      _enteredPasskey = bothPasskey;

      bool bothBioPassed = biometricPassed;
      if (bothPasskey != null && !bothBioPassed) {
        bothBioPassed = await _biometricService.authenticate(
          reason: 'Authenticate with fingerprint or Face ID',
        );
      }

      // Handle individual files in Both group
      for (final item in _queueItems.where((i) => i.encryptionType == 'both')) {
        if (bothPasskey == null && !bothBioPassed) {
          item.status = ItemDecodeStatus.missingCredential;
          item.missingType = 'passkey';
        } else if (bothPasskey == null && bothBioPassed) {
          item.status = ItemDecodeStatus.missingCredential;
          item.missingType = 'passkey';
          item.satisfiedCredential = 'bio:authenticated';
        } else if (bothPasskey != null && !bothBioPassed) {
          item.status = ItemDecodeStatus.missingCredential;
          item.missingType = 'biometric';
          item.satisfiedCredential = 'pk:$bothPasskey';
        } else {
          item.satisfiedCredential = 'both:pk:$bothPasskey:bio:authenticated';
        }
      }
    }

    // Process all queue items that have satisfied credentials
    await _processReadyQueueItems();

    if (mounted) {
      setState(() {
        _state = ViewScreenState.done;
      });
    }
  }

  Future<void> _processReadyQueueItems() async {
    for (int idx = 0; idx < _queueItems.length; idx++) {
      final item = _queueItems[idx];
      if (item.status == ItemDecodeStatus.missingCredential ||
          item.status == ItemDecodeStatus.accessDenied) {
        continue;
      }

      setState(() {
        item.status = ItemDecodeStatus.decoding;
        item.progress = 0.0;
      });

      final credentialsByType = <String, String>{};
      if (item.encryptionType == 'biometric') {
        credentialsByType['biometric'] = 'bio:authenticated';
      } else if (item.encryptionType == 'passkey') {
        credentialsByType['passkey'] = 'pk:${_enteredPasskey ?? ""}';
      } else {
        credentialsByType['passkey'] = 'pk:${_enteredPasskey ?? ""}';
        credentialsByType['biometric'] = 'bio:authenticated';
        credentialsByType['both'] = item.satisfiedCredential ??
            'both:pk:${_enteredPasskey ?? ""}:bio:authenticated';
      }

      await TriCryptStubs.decodeImage(
        [item.encodedFile],
        credentialsByType,
        (fileIdx, prog) {
          if (mounted) {
            setState(() {
              item.progress = prog;
            });
          }
        },
        (fileIdx, decodedFile) async {
          final fname = decodedFile.path.split(Platform.pathSeparator).last;
          await _albumDb.insertItem(
            AlbumItem(
              filename: fname,
              filepath: decodedFile.path,
              type: 'decoded',
              encryptionType: item.encryptionType,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              thumbnailPath: item.encodedFile.path,
            ),
          );

          if (mounted) {
            setState(() {
              item.status = ItemDecodeStatus.success;
              item.progress = 1.0;
              item.decodedResult = decodedFile;
            });
          }
        },
        (fileIdx, err) {
          if (mounted) {
            setState(() {
              if (err.kind == DecodeErrorKind.notTriCryptImage) {
                item.status = ItemDecodeStatus.notTriCrypt;
              } else if (err.kind == DecodeErrorKind.missingCredential) {
                item.status = ItemDecodeStatus.missingCredential;
                item.missingType = err.missingType;
              } else {
                item.status = ItemDecodeStatus.accessDenied;
              }
            });
          }
        },
      );
    }
  }

  Future<void> _provideMissingCredential(ViewQueueItem item) async {
    if (item.missingType == 'passkey') {
      final pKey = await _showPasskeyPrompt(title: 'Provide Missing Passkey');
      if (pKey != null) {
        _enteredPasskey = pKey;
        setState(() {
          item.satisfiedCredential = 'both:pk:$pKey:bio:authenticated';
          item.status = ItemDecodeStatus.pending;
        });
        await _processReadyQueueItems();
      }
    } else if (item.missingType == 'biometric') {
      final bioPassed = await _biometricService.authenticate(
        reason: 'Provide missing biometric credential',
      );
      if (bioPassed) {
        setState(() {
          item.satisfiedCredential =
              'both:pk:${_enteredPasskey ?? "pass"}:bio:authenticated';
          item.status = ItemDecodeStatus.pending;
        });
        await _processReadyQueueItems();
      }
    }
  }

  Future<void> _retrySingleItem(ViewQueueItem item) async {
    if (item.encryptionType == 'passkey' || item.encryptionType == 'both') {
      final pKey = await _showPasskeyPrompt(title: 'Retry Passkey');
      if (pKey != null) {
        _enteredPasskey = pKey;
        setState(() {
          item.status = ItemDecodeStatus.pending;
          item.satisfiedCredential = item.encryptionType == 'both'
              ? 'both:pk:$pKey:bio:authenticated'
              : 'pk:$pKey';
        });
        await _processReadyQueueItems();
      }
    } else {
      final bioPassed = await _biometricService.authenticate(
        reason: 'Retry Biometric Authentication',
      );
      if (bioPassed) {
        setState(() {
          item.status = ItemDecodeStatus.pending;
          item.satisfiedCredential = 'bio:auth';
        });
        await _processReadyQueueItems();
      }
    }
  }

  Future<void> _saveDecodedToGallery(File file) async {
    try {
      final ext = file.path.toLowerCase();
      if (ext.endsWith('.png') ||
          ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.webp') ||
          ext.endsWith('.gif')) {
        await Gal.putImage(file.path);
      } else if (ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi')) {
        await Gal.putVideo(file.path);
      }
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

  void _openDecodedFile(File file, bool isImage) {
    if (isImage) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => PreviewScreen(imageFile: file),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } else {
      OpenFilex.open(file.path);
    }
  }

  void _resetToIdle() {
    setState(() {
      _state = ViewScreenState.idle;
      _encodedImages.clear();
      _queueItems.clear();
      _errorMessage = null;
    });
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
                // Title: "View". No back arrow.
                const GradientTitle(
                  text: 'View',
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
                      ),
                    ),
                  ),
                ],

                if (_state == ViewScreenState.idle) ...[
                  // ENCODED IMAGES (1–10) picker header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        AppStrings.encodedImages,
                        style: TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentCyan,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (_encodedImages.isNotEmpty)
                        Text(
                          '${_encodedImages.length} of 10 selected',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Upload slot / Horizontal thumbnail strip
                  if (_encodedImages.isEmpty)
                    BracketBox(
                      width: double.infinity,
                      height: 140,
                      cornerColor: AppColors.accentCyan,
                      cornerLength: 18,
                      strokeWidth: 2,
                      backgroundColor: const Color(0x12FFFFFF),
                      onTap: _pickEncodedImages,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AppColors.accentCyan,
                            size: 42,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Select Encoded Images to Reveal',
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
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _encodedImages.length < 10
                            ? _encodedImages.length + 1
                            : _encodedImages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (ctx, index) {
                          if (index == _encodedImages.length) {
                            return GestureDetector(
                              onTap: _pickEncodedImages,
                              child: BracketBox(
                                width: 90,
                                height: 110,
                                cornerLength: 12,
                                strokeWidth: 1.5,
                                backgroundColor: const Color(0x12FFFFFF),
                                child: const Center(
                                  child: Icon(Icons.add, color: AppColors.accentCyan, size: 28),
                                ),
                              ),
                            );
                          }

                          final file = _encodedImages[index];
                          return BracketBox(
                            width: 90,
                            height: 110,
                            cornerLength: 12,
                            strokeWidth: 1.5,
                            padding: EdgeInsets.zero,
                            backgroundColor: AppColors.card,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.file(file, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removeEncodedImage(index),
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
                  ],

                  const SizedBox(height: 32),

                  // REVEAL BUTTON: Appears once at least one file selected
                  if (_encodedImages.isNotEmpty)
                    PrimaryButton(
                      text: AppStrings.revealButton,
                      icon: Icons.lock_open,
                      onPressed: _startRevealSequence,
                    ),
                ] else ...[
                  // Queue list during Processing and Results
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _state == ViewScreenState.processing
                            ? 'DECODING QUEUE (${_queueItems.where((q) => q.status == ItemDecodeStatus.success).length}/${_queueItems.length})'
                            : 'DECODING COMPLETED',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentCyan,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (_state == ViewScreenState.processing)
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
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, index) {
                      final item = _queueItems[index];

                      return BracketBox(
                        cornerLength: 14,
                        strokeWidth: 1.5,
                        padding: const EdgeInsets.all(12),
                        backgroundColor: AppColors.card,
                        cornerColor: item.status == ItemDecodeStatus.accessDenied ||
                                item.status == ItemDecodeStatus.notTriCrypt
                            ? AppColors.errorRed
                            : AppColors.accentCyan,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Image.file(
                                      item.encodedFile,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
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
                                        'Secured via: ${item.encryptionType.toUpperCase()}',
                                        style: const TextStyle(
                                          fontFamily: AppTheme.fontMonospace,
                                          fontSize: 10,
                                          color: AppColors.textGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.status == ItemDecodeStatus.success)
                                  const Icon(Icons.check_circle, color: AppColors.accentCyan, size: 20)
                                else if (item.status == ItemDecodeStatus.decoding)
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

                            // Progress bar
                            if (item.status == ItemDecodeStatus.decoding ||
                                item.status == ItemDecodeStatus.pending) ...[
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: item.progress,
                                backgroundColor: const Color(0xFF222222),
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                                minHeight: 4,
                              ),
                            ],

                            // Missing-credential state per prompt section 8
                            if (item.status == ItemDecodeStatus.missingCredential) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.errorRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Missing ${item.missingType ?? "credential"} to decode this file',
                                        style: const TextStyle(
                                          fontFamily: AppTheme.fontMonospace,
                                          fontSize: 11,
                                          color: AppColors.errorRed,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _provideMissingCredential(item),
                                      child: const Text(
                                        'Provide it',
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontMonospace,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accentCyan,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Failure (wrong credential): row shows red "Access Denied" + retry
                            if (item.status == ItemDecodeStatus.accessDenied) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    AppStrings.accessDenied,
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontMonospace,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.errorRed,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _retrySingleItem(item),
                                    child: const Text(
                                      'RETRY',
                                      style: TextStyle(
                                        fontFamily: AppTheme.fontMonospace,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.accentCyan,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Not a TriCrypt image
                            if (item.status == ItemDecodeStatus.notTriCrypt) ...[
                              const SizedBox(height: 10),
                              const Text(
                                AppStrings.noHiddenData,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMonospace,
                                  fontSize: 11,
                                  color: AppColors.errorRed,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],

                            // Success: row ends with DOWNLOAD always, and either VIEW (image) or OPEN (non-image)
                            if (item.status == ItemDecodeStatus.success &&
                                item.decodedResult != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: PrimaryButton(
                                      text: 'DOWNLOAD',
                                      height: 36,
                                      icon: Icons.download_outlined,
                                      onPressed: () => _saveDecodedToGallery(item.decodedResult!),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: PrimaryButton(
                                      text: item.isImageResult ? 'VIEW' : 'OPEN',
                                      height: 36,
                                      icon: item.isImageResult
                                          ? Icons.visibility_outlined
                                          : Icons.open_in_new,
                                      borderColor: AppColors.accentCyan,
                                      onPressed: () => _openDecodedFile(
                                        item.decodedResult!,
                                        item.isImageResult,
                                      ),
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

                  if (_state == ViewScreenState.done) ...[
                    Center(
                      child: TextButton(
                        onPressed: _resetToIdle,
                        child: const Text(
                          'DECODE MORE IMAGES',
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
    );
  }
}
