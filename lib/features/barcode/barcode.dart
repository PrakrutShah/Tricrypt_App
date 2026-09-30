import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/stubs.dart';
import 'scanner.dart';

enum BarcodeShareState {
  selecting,
  waitingForScan,
  confirmCode,
  transferring,
  sent,
}

class BarcodeScreen extends StatefulWidget {
  final File? preselectedImage;
  final VoidCallback? onBackToHome;

  const BarcodeScreen({
    super.key,
    this.preselectedImage,
    this.onBackToHome,
  });

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  File? _selectedImage;
  BarcodeShareState _state = BarcodeShareState.selecting;
  String? _errorMessage;
  String _confirmationCode = '';
  double _transferProgress = 0.0;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedImage = widget.preselectedImage;
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
          _errorMessage = null;
        });
      }
    } catch (_) {
      await TriCryptPermissionDialog.show(
        context,
        permissionName: 'Photo Library',
        description: 'TriCrypt requires access to select an image for QR transfer.',
        icon: Icons.photo_library_outlined,
      );
    }
  }

  void _generateCode() {
    if (_selectedImage == null) {
      setState(() {
        _errorMessage = 'Select an image first';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _state = BarcodeShareState.waitingForScan;
      _confirmationCode = (1000 + Random().nextInt(9000)).toString();
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _state == BarcodeShareState.waitingForScan) {
        setState(() {
          _state = BarcodeShareState.confirmCode;
        });
      }
    });
  }

  Future<void> _confirmTransfer() async {
    setState(() {
      _state = BarcodeShareState.transferring;
      _transferProgress = 0.0;
    });

    for (int step = 1; step <= 10; step++) {
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        setState(() {
          _transferProgress = step / 10.0;
        });
      }
    }

    await TriCryptStubs.sendFile(_selectedImage!, _confirmationCode);

    if (mounted) {
      setState(() {
        _state = BarcodeShareState.sent;
      });
    }
  }

  void _rejectTransfer() {
    setState(() {
      _state = BarcodeShareState.selecting;
      _errorMessage = 'Transfer aborted by user';
    });
  }

  void _openScanner() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ScannerScreen(),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    text: 'Barcode',
                    fontSize: 28,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              const Text(
                AppStrings.selectImageToShare,
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 24),

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

              Center(
                child: _buildMainBox(),
              ),

              const SizedBox(height: 32),

              if (_state == BarcodeShareState.selecting) ...[
                PrimaryButton(
                  text: AppStrings.generateCode,
                  onPressed: _generateCode,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  text: AppStrings.scanToReceive,
                  icon: Icons.qr_code_scanner,
                  borderColor: AppColors.accentCyan.withValues(alpha: 0.6),
                  textColor: AppColors.accentCyan,
                  onPressed: _openScanner,
                ),
              ] else if (_state == BarcodeShareState.waitingForScan) ...[
                PrimaryButton(
                  text: 'CANCEL',
                  borderColor: AppColors.textGrey,
                  textColor: AppColors.textGrey,
                  onPressed: () {
                    setState(() {
                      _state = BarcodeShareState.selecting;
                    });
                  },
                ),
              ] else if (_state == BarcodeShareState.confirmCode) ...[
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        text: 'REJECT',
                        borderColor: AppColors.errorRed,
                        textColor: AppColors.errorRed,
                        onPressed: _rejectTransfer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: PrimaryButton(
                        text: 'CONFIRM',
                        onPressed: _confirmTransfer,
                      ),
                    ),
                  ],
                ),
              ] else if (_state == BarcodeShareState.sent) ...[
                PrimaryButton(
                  text: 'SHARE ANOTHER FILE',
                  onPressed: () {
                    setState(() {
                      _state = BarcodeShareState.selecting;
                      _selectedImage = null;
                      _errorMessage = null;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainBox() {
    switch (_state) {
      case BarcodeShareState.selecting:
        return BracketBox(
          width: 260,
          height: 195,
          cornerLength: 20,
          strokeWidth: 2,
          backgroundColor: const Color(0x12FFFFFF),
          hasGlow: _selectedImage != null,
          onTap: _pickImage,
          child: _selectedImage != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedImage = null),
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
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, color: AppColors.accentCyan, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      'Choose file to send',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
        );

      case BarcodeShareState.waitingForScan:
        final qrPayload = 'TRICRYPT:${_confirmationCode}:${_selectedImage?.path.split(Platform.pathSeparator).last}';
        return BracketBox(
          width: 260,
          height: 260,
          cornerLength: 20,
          backgroundColor: AppColors.card,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 160.0,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentCyan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.waitingForScan,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMonospace,
                      fontSize: 11,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case BarcodeShareState.confirmCode:
        return BracketBox(
          width: 260,
          height: 200,
          cornerLength: 20,
          backgroundColor: AppColors.card,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'DEVICE CONNECTED',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _confirmationCode,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textWhite,
                  letterSpacing: 6.0,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppStrings.matchCodePrompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 11,
                    color: AppColors.textGrey,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );

      case BarcodeShareState.transferring:
        return BracketBox(
          width: 260,
          height: 180,
          cornerLength: 20,
          backgroundColor: AppColors.card,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'TRANSFERRING...',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LinearProgressIndicator(
                  value: _transferProgress,
                  backgroundColor: const Color(0xFF222222),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${(_transferProgress * 100).toInt()}%',
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        );

      case BarcodeShareState.sent:
        return BracketBox(
          width: 260,
          height: 180,
          cornerLength: 20,
          backgroundColor: AppColors.card,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.accentCyan,
                size: 56,
              ),
              const SizedBox(height: 14),
              const Text(
                'TRANSFER COMPLETE',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textWhite,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'File sent safely to destination.',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        );
    }
  }
}
