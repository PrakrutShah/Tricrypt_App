import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/album_db.dart';
import '../preview/preview.dart';

enum GalleryFilter { all, encrypted, decoded }

class GalleryScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const GalleryScreen({super.key, this.onBackToHome});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final AlbumDb _albumDb = AlbumDb();
  GalleryFilter _currentFilter = GalleryFilter.all;
  List<AlbumItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _albumDb.onDbChanged.listen((_) {
      if (mounted) _loadItems();
    });
  }

  Future<void> _loadItems() async {
    try {
      List<AlbumItem> items;
      switch (_currentFilter) {
        case GalleryFilter.all:
          items = await _albumDb.getAllItems();
          break;
        case GalleryFilter.encrypted:
          items = await _albumDb.getEncryptedItems();
          break;
        case GalleryFilter.decoded:
          items = await _albumDb.getDecodedItems();
          break;
      }
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _items = [];
          _isLoading = false;
        });
      }
    }
  }

  void _onFilterChanged(GalleryFilter filter) {
    setState(() {
      _currentFilter = filter;
      _isLoading = true;
    });
    _loadItems();
  }

  Future<void> _confirmDelete(AlbumItem item) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.errorRed),
        ),
        title: const Text(
          'Delete Image?',
          style: TextStyle(
            fontFamily: AppTheme.fontMonospace,
            color: AppColors.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will remove "${item.filename}" from your TriCrypt index and local storage.',
          style: const TextStyle(
            fontFamily: AppTheme.fontMonospace,
            color: AppColors.textGrey,
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.accentCyan)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('DELETE', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );

    if (shouldDelete == true && item.id != null) {
      try {
        final f = File(item.filepath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
      await _albumDb.deleteItem(item.id!);
      _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item deleted.')),
        );
      }
    }
  }

  void _openPreview(AlbumItem item) {
    final file = File(item.filepath);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
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
                    text: 'Gallery',
                    fontSize: 28,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  _buildFilterTab('All', GalleryFilter.all),
                  const SizedBox(width: 8),
                  _buildFilterTab('Encrypted', GalleryFilter.encrypted),
                  const SizedBox(width: 8),
                  _buildFilterTab('Decoded', GalleryFilter.decoded),
                ],
              ),
              const SizedBox(height: 20),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accentCyan,
                          strokeWidth: 2,
                        ),
                      )
                    : _items.isEmpty
                        ? _buildEmptyState()
                        : _buildItemGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, GalleryFilter filter) {
    final isSelected = _currentFilter == filter;
    return GestureDetector(
      onTap: () => _onFilterChanged(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentCyan.withValues(alpha: 0.15)
              : const Color(0x0CFFFFFF),
          border: Border.all(
            color: isSelected ? AppColors.accentCyan : AppColors.cardBorder,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: AppTheme.fontMonospace,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.accentCyan : AppColors.textGrey,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card,
              border: Border.all(color: AppColors.cardBorder, width: 1),
            ),
            child: const Icon(
              Icons.collections_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No files',
            style: TextStyle(
              fontFamily: AppTheme.fontMonospace,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textWhite,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hide or decode an image to see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontMonospace,
              fontSize: 12,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemGrid() {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.85,
      ),
      itemCount: _items.length,
      itemBuilder: (ctx, index) {
        final item = _items[index];
        final file = File(item.filepath);
        final thumbFile = File(item.thumbnailPath);

        return GestureDetector(
          onTap: () => _openPreview(item),
          onLongPress: () => _confirmDelete(item),
          child: BracketBox(
            cornerLength: 14,
            strokeWidth: 1.5,
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.card,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    thumbFile.existsSync() ? thumbFile : file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: AppColors.accentCyan,
                        size: 40,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    item.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMonospace,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textWhite,
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: item.isEncrypted
                            ? AppColors.accentCyan
                            : AppColors.successGreen,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      item.isEncrypted ? Icons.lock : Icons.lock_open,
                      size: 13,
                      color: item.isEncrypted
                          ? AppColors.accentCyan
                          : AppColors.successGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
