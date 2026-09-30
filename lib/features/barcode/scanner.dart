import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/album_db.dart';
import '../../data/stubs.dart';
import '../preview/preview.dart';

enum ScannerState {
  scanning,
  confirmCode,
  receiving,
  received,
  error,
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _cameraController = MobileScannerController();
  ScannerState _state = ScannerState.scanning;
  String _confirmationCode = '';
  double _progress = 0.0;
  File? _receivedFile;
  String? _errorMessage;

  final AlbumDb _albumDb = AlbumDb();

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_state != ScannerState.scanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final val = barcode.rawValue;
      if (val != null && val.startsWith('TRICRYPT:')) {
        final parts = val.split(':');
        final code = parts.length > 1 ? parts[1] : '8492';
        setState(() {
          _confirmationCode = code;
          _state = ScannerState.confirmCode;
        });
        break;
      }
    }
  }

  Future<void> _confirmReceive() async {
    setState(() {
      _state = ScannerState.receiving;
      _progress = 0.0;
    });

    for (int step = 1; step <= 10; step++) {
      await Future.delayed(const Duration(milliseconds: 140));
      if (mounted) {
        setState(() => _progress = step / 10.0);
      }
    }

    try {
      final file = await TriCryptStubs.receiveFile(_confirmationCode);
      final filename = file.path.split(Platform.pathSeparator).last;

      await _albumDb.insertItem(
        AlbumItem(
          filename: filename,
          filepath: file.path,
          type: 'received',
          encryptionType: 'passkey',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          thumbnailPath: file.path,
        ),
      );

      if (mounted) {
        setState(() {
          _receivedFile = file;
          _state = ScannerState.received;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = ScannerState.error;
          _errorMessage = 'Transfer failed: $e';
        });
      }
    }
  }

  void _rejectReceive() {
    setState(() {
      _state = ScannerState.scanning;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.accentCyan),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const GradientTitle(
          text: AppStrings.scannerTitle,
          fontSize: 22,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
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

              Expanded(
                child: Center(
                  child: _buildScannerContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerContent() {
    switch (_state) {
      case ScannerState.scanning:
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 280,
                height: 280,
                child: MobileScanner(
                  controller: _cameraController,
                  onDetect: _onDetect,
                  errorBuilder: (ctx, err) {
                    return Container(
                      color: AppColors.card,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off_outlined, color: AppColors.textGrey, size: 40),
                          const SizedBox(height: 8),
                          Text(
                            'Camera preview unavailable',
                            style: TextStyle(
                              fontFamily: AppTheme.fontMonospace,
                              fontSize: 11,
                              color: AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _confirmationCode = '7429';
                                _state = ScannerState.confirmCode;
                              });
                            },
                            child: const Text('Simulate Scan', style: TextStyle(color: AppColors.accentCyan)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            BracketBox(
              width: 280,
              height: 280,
              cornerColor: AppColors.accentCyan,
              cornerLength: 26,
              strokeWidth: 2.5,
              backgroundColor: Colors.transparent,
              hasGlow: true,
              child: const SizedBox.shrink(),
            ),
            Positioned(
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.5)),
                ),
                child: const Text(
                  'Point camera at QR code',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 11,
                    color: AppColors.accentCyan,
                  ),
                ),
              ),
            ),
          ],
        );

      case ScannerState.confirmCode:
        return BracketBox(
          width: 280,
          cornerLength: 22,
          strokeWidth: 2,
          backgroundColor: AppColors.card,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'MATCH CONFIRMATION CODE',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _confirmationCode,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textWhite,
                  letterSpacing: 6.0,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Ensure this 4-digit code matches the sender device before accepting.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      text: 'REJECT',
                      borderColor: AppColors.errorRed,
                      textColor: AppColors.errorRed,
                      onPressed: _rejectReceive,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      text: 'CONFIRM',
                      onPressed: _confirmReceive,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

      case ScannerState.receiving:
        return BracketBox(
          width: 280,
          cornerLength: 22,
          backgroundColor: AppColors.card,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'RECEIVING ENCRYPTED FILE...',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentCyan,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: const Color(0xFF222222),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                minHeight: 6,
              ),
              const SizedBox(height: 10),
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        );

      case ScannerState.received:
        return BracketBox(
          width: 280,
          cornerLength: 22,
          backgroundColor: AppColors.card,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.accentCyan,
                size: 54,
              ),
              const SizedBox(height: 14),
              const Text(
                'FILE RECEIVED',
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textWhite,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The file was added to your Gallery index (still encrypted).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 11,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 22),
              PrimaryButton(
                text: 'OPEN PREVIEW',
                onPressed: () {
                  if (_receivedFile != null) {
                    Navigator.of(context).pushReplacement(
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => PreviewScreen(imageFile: _receivedFile!),
                        transitionsBuilder: (_, animation, __, child) =>
                            FadeTransition(opacity: animation, child: child),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('BACK TO BARCODE', style: TextStyle(color: AppColors.textGrey)),
              ),
            ],
          ),
        );

      case ScannerState.error:
        return BracketBox(
          width: 280,
          cornerLength: 22,
          backgroundColor: AppColors.card,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.errorRed, size: 50),
              const SizedBox(height: 14),
              Text(
                _errorMessage ?? 'Scan error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 12,
                  color: AppColors.errorRed,
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                text: 'TRY AGAIN',
                onPressed: () {
                  setState(() {
                    _state = ScannerState.scanning;
                    _errorMessage = null;
                  });
                },
              ),
            ],
          ),
        );
    }
  }
}
