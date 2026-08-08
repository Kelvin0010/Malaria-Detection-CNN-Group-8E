import 'package:flutter/material.dart';
import 'main_layout.dart';
import 'firebase_service.dart';
import 'state.dart';

// App primary blue – matches main.dart theme
const _kPrimary = Color(0xFF4A64FE);
const _kPrimaryLight = Color(0xFF7C8DFF);

// ─────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const _SignInPage();
}

// ─────────────────────────────────────────────────────────────
// Shared Google Sign-In logic
// ─────────────────────────────────────────────────────────────

mixin _GoogleSignInMixin<T extends StatefulWidget> on State<T> {
  final FirebaseService _firebaseService = FirebaseService();
  bool isLoading = false;

  Future<void> handleGoogleSignIn() async {
    setState(() => isLoading = true);
    try {
      final credential = await _firebaseService.signInWithGoogle();

      if (credential == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      if (!mounted) return;
      final userProfile = await _firebaseService.getUserProfile();

      if (mounted) {
        AppState.profileNotifier.value = ProfileData(
          name: userProfile?['name'] ?? 'User',
          title: userProfile?['title'] ?? 'Diagnostic Specialist',
          imagePath: userProfile?['imagePath'] as String?,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainLayout()),
        );
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign-in failed: ${_friendlyError(e)}'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
        setState(() => isLoading = false);
      }
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('network')) return 'Network error. Check your connection.';
    if (msg.contains('canceled') || msg.contains('cancelled')) return 'Sign-in was canceled.';
    // Return actual error message so root cause is clear
    return msg.replaceAll('Exception:', '').replaceAll('PlatformException', '').trim();
  }
}

// ─────────────────────────────────────────────────────────────
// Blue curved header – mirrors the dashboard hero
// ─────────────────────────────────────────────────────────────

class _BlueHeader extends StatelessWidget {
  /// Extra height only used on sign-in (no back button)
  final bool tall;
  final Widget? leading;

  const _BlueHeader({this.tall = false, this.leading});

  @override
  Widget build(BuildContext context) {
    final double height = tall ? 260 : 220;

    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPrimary, _kPrimaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Back button (sign-up only)
            if (leading != null)
              Positioned(top: 4, left: 4, child: leading!),

            // Logo + title
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset('assets/app_icon.png',
                          width: 72, height: 72, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'MalariaGuard',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI-Powered Diagnostic Assistant',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Google Sign-In / Sign-Up button
// ─────────────────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;

  const _GoogleButton({
    required this.isLoading,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 2,
          shadowColor: _kPrimary.withValues(alpha: 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: _kPrimary),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.network(
                    'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                    height: 22,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.g_mobiledata,
                            size: 26, color: Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// "Google accounts only" info chip
// ─────────────────────────────────────────────────────────────

class _GoogleOnlyBanner extends StatelessWidget {
  const _GoogleOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.18)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: _kPrimary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only Google accounts are accepted on this platform.',
              style: TextStyle(
                fontSize: 12.5,
                color: _kPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Divider row
// ─────────────────────────────────────────────────────────────

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Secure & Verified',
            style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Feature bullet row (Sign-Up page)
// ─────────────────────────────────────────────────────────────

class _FeatureBullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _FeatureBullet({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIGN IN PAGE
// ─────────────────────────────────────────────────────────────

class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> with _GoogleSignInMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Blue curved header ──
            const _BlueHeader(tall: true),

            const SizedBox(height: 32),

            // ── White content card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimary.withValues(alpha: 0.07),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome Back',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to your MalariaGuard account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Google-only notice
                    const _GoogleOnlyBanner(),
                    const SizedBox(height: 24),

                    // Google Sign-In button
                    _GoogleButton(
                      isLoading: isLoading,
                      onPressed: handleGoogleSignIn,
                      label: 'Sign in with Google',
                    ),

                    const SizedBox(height: 24),
                    const _OrDivider(),
                    const SizedBox(height: 20),

                    // Navigate to Sign Up
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13.5),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const _SignUpPage()),
                          ),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              decoration: TextDecoration.underline,
                              decorationColor: _kPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SIGN UP PAGE
// ─────────────────────────────────────────────────────────────

class _SignUpPage extends StatefulWidget {
  const _SignUpPage();

  @override
  State<_SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<_SignUpPage> with _GoogleSignInMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Blue curved header with back button ──
            _BlueHeader(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            const SizedBox(height: 28),

            // ── White content card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimary.withValues(alpha: 0.07),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Join MalariaGuard with your Google account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 13.5),
                    ),
                    const SizedBox(height: 24),

                    // Google-only notice
                    const _GoogleOnlyBanner(),
                    const SizedBox(height: 20),

                    // Feature bullets
                    _FeatureBullet(
                      icon: Icons.security,
                      text: 'Secure sign-up — no password needed',
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 10),
                    const _FeatureBullet(
                      icon: Icons.cloud_done_outlined,
                      text: 'Scan history synced across devices',
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(height: 10),
                    const _FeatureBullet(
                      icon: Icons.analytics_outlined,
                      text: 'AI-powered malaria diagnostics',
                      color: Color(0xFFFF9100),
                    ),
                    const SizedBox(height: 24),

                    // Google Sign-Up button
                    _GoogleButton(
                      isLoading: isLoading,
                      onPressed: handleGoogleSignIn,
                      label: 'Sign up with Google',
                    ),

                    const SizedBox(height: 24),
                    const _OrDivider(),
                    const SizedBox(height: 20),

                    // Navigate back to Sign In
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13.5),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              decoration: TextDecoration.underline,
                              decorationColor: _kPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
