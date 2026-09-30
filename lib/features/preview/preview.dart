import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/widgets.dart';
import '../barcode/barcode.dart';

class PreviewScreen extends StatelessWidget {
  final File imageFile;

  const PreviewScreen({super.key, required this.imageFile});

  void _saveToGallery(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved to gallery'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareViaQr(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => BarcodeScreen(preselectedImage: imageFile),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filename = imageFile.path.split(Platform.pathSeparator).last;

    return SecurityOverlayWrapper(
      isSensitiveScreen: true,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const GradientTitle(
            text: AppStrings.previewTitle,
            fontSize: 22,
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.file(
                      imageFile,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 64,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(
                    top: BorderSide(color: AppColors.cardBorder, width: 1),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MonospaceDisplay',
                        fontSize: 12,
                        color: AppColors.textWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            text: 'DOWNLOAD',
                            icon: Icons.download_outlined,
                            onPressed: () => _saveToGallery(context),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: PrimaryButton(
                            text: 'SHARE VIA QR',
                            icon: Icons.qr_code,
                            borderColor: AppColors.accentCyan.withValues(alpha: 0.7),
                            onPressed: () => _shareViaQr(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
