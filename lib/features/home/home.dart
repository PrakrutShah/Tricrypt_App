import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/album_db.dart';
import '../../data/secure_store.dart';
import '../auth/login.dart';
import '../barcode/barcode.dart';
import '../gallery/gallery.dart';
import '../hide/hide.dart';
import '../view/view.dart';

class MainNavScreen extends StatefulWidget {
  final int initialIndex;
  final bool isFirstTimeSignUp;

  const MainNavScreen({
    super.key,
    this.initialIndex = 0,
    this.isFirstTimeSignUp = false,
  });

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  late int _currentIndex;
  int _encryptedBadgeCount = 0;
  final AlbumDb _albumDb = AlbumDb();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _refreshEncryptedCount();
    _albumDb.onDbChanged.listen((_) {
      if (mounted) _refreshEncryptedCount();
    });

    _authService.trySilentRefresh();
  }

  Future<void> _refreshEncryptedCount() async {
    final count = await _albumDb.getEncryptedCount();
    if (mounted) {
      setState(() => _encryptedBadgeCount = count);
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            onNavigateTab: _onTabTapped,
            isFirstTimeSignUp: widget.isFirstTimeSignUp,
          ),
          HideScreen(onBackToHome: () => _onTabTapped(0)),
          ViewScreen(onBackToHome: () => _onTabTapped(0)),
          GalleryScreen(onBackToHome: () => _onTabTapped(0)),
          BarcodeScreen(onBackToHome: () => _onTabTapped(0)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.cardBorder, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: AppColors.background,
          selectedItemColor: AppColors.accentCyan,
          unselectedItemColor: AppColors.textGrey,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              activeIcon: Icon(Icons.shield),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.lock_outline),
              activeIcon: Icon(Icons.lock),
              label: 'Hide',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.lock_open_outlined),
              activeIcon: Icon(Icons.lock_open),
              label: 'View',
            ),
            BottomNavigationBarItem(
              icon: _encryptedBadgeCount > 0
                  ? Badge(
                      label: Text('$_encryptedBadgeCount'),
                      backgroundColor: AppColors.accentCyan,
                      textColor: AppColors.background,
                      child: const Icon(Icons.layers_outlined),
                    )
                  : const Icon(Icons.layers_outlined),
              activeIcon: _encryptedBadgeCount > 0
                  ? Badge(
                      label: Text('$_encryptedBadgeCount'),
                      backgroundColor: AppColors.accentCyan,
                      textColor: AppColors.background,
                      child: const Icon(Icons.layers),
                    )
                  : const Icon(Icons.layers),
              label: 'Gallery',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_2_outlined),
              activeIcon: Icon(Icons.qr_code_2),
              label: 'Barcode',
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex) onNavigateTab;
  final bool isFirstTimeSignUp;

  const HomeScreen({
    super.key,
    required this.onNavigateTab,
    this.isFirstTimeSignUp = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _username = 'User';
  bool _isFirstLogin = true;
  int _encryptedBadgeCount = 0;

  final SecureStore _secureStore = SecureStore();
  final AlbumDb _albumDb = AlbumDb();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _albumDb.onDbChanged.listen((_) {
      if (mounted) _refreshEncryptedCount();
    });
  }

  Future<void> _loadUserData() async {
    final name = await _secureStore.getUsername();
    final first = await _secureStore.isFirstLogin();
    final count = await _albumDb.getEncryptedCount();

    if (mounted) {
      setState(() {
        _username = (name != null && name.isNotEmpty) ? name : 'User';
        _isFirstLogin = first;
        _encryptedBadgeCount = count;
      });
    }
  }

  Future<void> _refreshEncryptedCount() async {
    final count = await _albumDb.getEncryptedCount();
    if (mounted) {
      setState(() => _encryptedBadgeCount = count);
    }
  }

  String _formatDisplayName(String raw) {
    if (raw.trim().isEmpty) return 'User';
    String text = raw.trim();
    // If it's an email, extract the prefix before @
    if (text.contains('@')) {
      text = text.split('@').first;
    }
    // Remove all digits (e.g. phone numbers or numeric suffixes like alex123)
    text = text.replaceAll(RegExp(r'\d+'), '').trim();
    // Replace separators (dots, underscores, hyphens) with space
    text = text.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (text.isEmpty) return 'User';

    // Capitalize each name component (e.g. "prakrut.shah" -> "Prakrut Shah")
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'User';
    return words
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : ''))
        .join(' ');
  }

  String _getGreeting() {
    final displayName = _formatDisplayName(_username);
    if (widget.isFirstTimeSignUp) {
      return 'Welcome, $displayName';
    }
    return 'Welcome back, $displayName';
  }

  void _showProfileMenu() {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.accentCyan.withValues(alpha: 0.2),
                    child: Text(
                      _username.isNotEmpty ? _username[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontMonospace,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentCyan,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _username,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textWhite,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Local Vault User',
                          style: TextStyle(
                            fontFamily: AppTheme.fontMonospace,
                            fontSize: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: AppColors.cardBorder, height: 1),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: AppColors.errorRed),
                title: const Text(
                  'LOGOUT',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.errorRed,
                    letterSpacing: 1.5,
                  ),
                ),
                subtitle: const Text(
                  'Clears active session while keeping encrypted local files.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 10,
                    color: AppColors.textGrey,
                  ),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _authService.logout();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const LoginScreen(),
                      transitionsBuilder: (_, animation, __, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialLetter = _username.isNotEmpty ? _username[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else {
                        Navigator.of(context).pushReplacement(
                          PageRouteBuilder(
                            pageBuilder: (_, __, ___) => const LoginScreen(),
                            transitionsBuilder: (_, animation, __, child) =>
                                FadeTransition(opacity: animation, child: child),
                          ),
                        );
                      }
                    },
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
                  const GradientTitle(
                    text: AppStrings.appName,
                    fontSize: 20,
                  ),
                  GestureDetector(
                    onTap: _showProfileMenu,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.accentCyan.withValues(alpha: 0.25),
                      child: Text(
                        initialLetter,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentCyan,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Text(
                _getGreeting(),
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.appTagline,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 28),

              _buildFeatureCard(
                icon: Icons.visibility_off_outlined,
                title: 'Hide and show',
                description: 'Encrypt files into a cover image, reveal them with your fingerprint.',
                onTap: () => widget.onNavigateTab(1),
              ),

              const SizedBox(height: 14),

              _buildFeatureCard(
                icon: Icons.layers_outlined,
                title: 'Gallery',
                description: 'Encrypted files live in your own device gallery, not on our servers.',
                badgeCount: _encryptedBadgeCount > 0 ? _encryptedBadgeCount : null,
                onTap: () => widget.onNavigateTab(3),
              ),

              const SizedBox(height: 14),

              _buildFeatureCard(
                icon: Icons.qr_code_2_outlined,
                title: 'QR transfer',
                description: 'Send an encrypted file to another device with a scan, no third-party app.',
                onTap: () => widget.onNavigateTab(4),
              ),

              const SizedBox(height: 14),

              _buildFeatureCard(
                icon: Icons.visibility_outlined,
                title: 'Reveal Hidden Data',
                description: 'Decode and extract protected payloads with biometric or passkey verification.',
                onTap: () => widget.onNavigateTab(2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: BracketBox(
        cornerColor: AppColors.accentCyan.withValues(alpha: 0.5),
        cornerLength: 16,
        strokeWidth: 1.5,
        backgroundColor: AppColors.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.accentCyan, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontMonospace,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textWhite,
                        ),
                      ),
                      if (badgeCount != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentCyan,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$badgeCount',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontMonospace,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.background,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMonospace,
                      fontSize: 11,
                      color: AppColors.textGrey,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textGrey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
