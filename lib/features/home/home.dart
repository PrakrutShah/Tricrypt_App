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
  // 0: Home, 1: Hide, 2: View, 3: Gallery, 4: Barcode
  late int _currentScreenIndex;
  int _encryptedBadgeCount = 0;
  final AlbumDb _albumDb = AlbumDb();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _currentScreenIndex = widget.initialIndex;
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

  void _onBottomNavTapped(int navIndex) {
    setState(() {
      // navIndex: 0 -> Hide (1), 1 -> View (2), 2 -> Gallery (3), 3 -> Barcode (4)
      _currentScreenIndex = navIndex + 1;
    });
  }

  void _navigateToScreen(int screenIndex) {
    setState(() {
      _currentScreenIndex = screenIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine active bottom nav index (-1 if on Home)
    final int activeNavIndex = _currentScreenIndex == 0 ? -1 : _currentScreenIndex - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentScreenIndex,
        children: [
          HomeScreen(
            onNavigateTab: _navigateToScreen,
            isFirstTimeSignUp: widget.isFirstTimeSignUp,
          ),
          HideScreen(onGoHome: () => _navigateToScreen(0)),
          ViewScreen(onGoHome: () => _navigateToScreen(0)),
          GalleryScreen(onGoHome: () => _navigateToScreen(0)),
          BarcodeScreen(onGoHome: () => _navigateToScreen(0)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: AppColors.cardBorder, width: 1),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            currentIndex: activeNavIndex >= 0 ? activeNavIndex : 0,
            onTap: _onBottomNavTapped,
            backgroundColor: AppColors.background,
            selectedItemColor: activeNavIndex >= 0 ? AppColors.accentCyan : AppColors.textGrey,
            unselectedItemColor: AppColors.textGrey,
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.lock_outline),
                activeIcon: Icon(
                  Icons.lock,
                  color: activeNavIndex == 0 ? AppColors.accentCyan : AppColors.textGrey,
                ),
                label: 'Hide',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.lock_open_outlined),
                activeIcon: Icon(
                  Icons.lock_open,
                  color: activeNavIndex == 1 ? AppColors.accentCyan : AppColors.textGrey,
                ),
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
                        child: Icon(
                          Icons.layers,
                          color: activeNavIndex == 2 ? AppColors.accentCyan : AppColors.textGrey,
                        ),
                      )
                    : Icon(
                        Icons.layers,
                        color: activeNavIndex == 2 ? AppColors.accentCyan : AppColors.textGrey,
                      ),
                label: 'Gallery',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.qr_code_2_outlined),
                activeIcon: Icon(
                  Icons.qr_code_2,
                  color: activeNavIndex == 3 ? AppColors.accentCyan : AppColors.textGrey,
                ),
                label: 'Barcode',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final void Function(int screenIndex) onNavigateTab;
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
    if (text.contains('@')) {
      text = text.split('@').first;
    }
    text = text.replaceAll(RegExp(r'\d+'), '').trim();
    text = text.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    if (text.isEmpty) return 'User';

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'User';
    return words
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : ''))
        .join(' ');
  }

  String _getGreeting() {
    final displayName = _formatDisplayName(_username);
    if (widget.isFirstTimeSignUp || _isFirstLogin) {
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
                      pageBuilder: (_, _, _) => const LoginScreen(),
                      transitionsBuilder: (_, animation, _, child) =>
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
              // Header: logo top-left (tap = Home). Profile avatar circle top-right with initial
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => widget.onNavigateTab(0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.accentCyan.withValues(alpha: 0.7),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: AppColors.accentCyan,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const GradientTitle(
                          text: AppStrings.appName,
                          fontSize: 22,
                        ),
                      ],
                    ),
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
              const Text(
                AppStrings.appTagline,
                style: TextStyle(
                  fontFamily: AppTheme.fontMonospace,
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),

              const SizedBox(height: 28),

              // 4 cards in a 2x2 grid (dark card, cyan border, icon, bold title, description)
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.95,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Hide: eye-slash. "Encrypt one or more files into a cover image." -> Hide
                  _buildGridCard(
                    icon: Icons.visibility_off_outlined,
                    title: 'Hide',
                    description: 'Encrypt one or more files into a cover image.',
                    onTap: () => widget.onNavigateTab(1),
                  ),
                  // View: eye. "Reveal a hidden file with your fingerprint or passkey." -> View
                  _buildGridCard(
                    icon: Icons.visibility_outlined,
                    title: 'View',
                    description: 'Reveal a hidden file with your fingerprint or passkey.',
                    onTap: () => widget.onNavigateTab(2),
                  ),
                  // Gallery: stacked layers with badge count. "Encrypted files live on your device, not on our servers." -> Gallery
                  _buildGridCard(
                    icon: Icons.layers_outlined,
                    title: 'Gallery',
                    description: 'Encrypted files live on your device, not on our servers.',
                    badgeCount: _encryptedBadgeCount > 0 ? _encryptedBadgeCount : null,
                    onTap: () => widget.onNavigateTab(3),
                  ),
                  // Barcode: QR. "Send an encrypted file to another device with a scan." -> Barcode
                  _buildGridCard(
                    icon: Icons.qr_code_2_outlined,
                    title: 'Barcode',
                    description: 'Send an encrypted file to another device with a scan.',
                    onTap: () => widget.onNavigateTab(4),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: BracketBox(
        cornerColor: AppColors.accentCyan.withValues(alpha: 0.6),
        cornerLength: 16,
        strokeWidth: 1.5,
        backgroundColor: AppColors.card,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.accentCyan, size: 24),
                ),
                if (badgeCount != null)
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
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMonospace,
                    fontSize: 10.5,
                    color: AppColors.textGrey,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
