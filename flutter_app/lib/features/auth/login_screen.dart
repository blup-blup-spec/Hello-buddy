import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/core/widgets/buddy_cat_mascot.dart';
import 'package:hello_buddy/core/widgets/buddy_widgets.dart';
import 'package:hello_buddy/features/home/student_shell.dart';
import 'package:hello_buddy/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  int _roleIndex = 0; // 0 = Student, 1 = Admin
  bool _obscurePassword = true;
  bool _isRegisterMode = false;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  late AnimationController _entryController;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StudentShell()),
    );
  }

  void _showNotice(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: BuddyTheme.bodyFont(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isError ? Colors.white : BuddyColors.onLime,
          ),
        ),
        backgroundColor: isError ? BuddyColors.coral : BuddyColors.lime,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: BuddyColors.pitch, width: 2),
        ),
      ),
    );
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showNotice('Please enter both email and password.', isError: true);
      return;
    }

    if (password.length < 6) {
      _showNotice('Password must be at least 6 characters.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegisterMode) {
        await _authService.registerWithEmail(email, password);
        _showNotice('Account created successfully! Welcome to Buddy.');
      } else {
        await _authService.signInWithEmail(email, password);
        _showNotice('Welcome back!');
      }

      if (mounted) _navigateToHome();
    } catch (e) {
      _showNotice(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        _showNotice('Signed in as ${user.displayName ?? user.email}!');
        if (mounted) _navigateToHome();
      }
    } catch (e) {
      _showNotice(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGuestEntry() async {
    setState(() => _isLoading = true);
    try {
      await _authService.signInAnonymously();
    } catch (_) {}
    if (mounted) {
      _showNotice('Entered as Guest Student. Syncing with Robot.');
      _navigateToHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: BuddyColors.bone,
      body: Stack(
        children: [
          // Top carbon ink canopy
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              painter: _LoginInkCanopy(),
              size: Size(screenW, 175),
            ),
          ),

          // Scrollable content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 50),

                        // Cat mascot peeking from ink
                        const BuddyCatMascot(size: 120),
                        const SizedBox(height: 18),

                        // Kicker
                        Text(
                          'DESK COMPANION ROBOT',
                          style: BuddyTheme.captionMono(
                            fontSize: 10,
                            color: BuddyColors.smoke,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Display title
                        Text(
                          _isRegisterMode ? 'Join Sanctuary.' : 'Enter Sanctuary.',
                          style: BuddyTheme.displayFont(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: BuddyColors.carbon,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Subline
                        Text(
                          _isRegisterMode
                              ? 'Create an account to pair with your Buddy robot.'
                              : 'Your physical desktop companion is ready to assist.',
                          style: BuddyTheme.bodyFont(
                            fontSize: 13,
                            color: BuddyColors.smoke,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // Two-way role toggle
                        BuddySegmentedControl(
                          labels: const ['🎓 Student / Member', '🛡️ Admin / Faculty'],
                          selectedIndex: _roleIndex,
                          onChanged: (i) => setState(() => _roleIndex = i),
                        ),
                        const SizedBox(height: 18),

                        // Email input
                        BuddyInputField(
                          hint: 'University Email / ID',
                          prefixIcon: Icons.alternate_email_rounded,
                          controller: _emailController,
                        ),
                        const SizedBox(height: 12),

                        // Password input
                        BuddyInputField(
                          hint: 'Password (min 6 chars)',
                          prefixIcon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          controller: _passwordController,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: BuddyColors.smoke,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Mode toggle (Login vs Register)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isRegisterMode
                                  ? 'Already have an account? '
                                  : 'New to Hello Buddy? ',
                              style: BuddyTheme.bodyFont(
                                fontSize: 12,
                                color: BuddyColors.smoke,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _isRegisterMode = !_isRegisterMode),
                              child: Text(
                                _isRegisterMode ? 'Sign In' : 'Create Account',
                                style: BuddyTheme.bodyFont(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: BuddyColors.carbon,
                                ).copyWith(
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Primary CTA
                        SizedBox(
                          width: double.infinity,
                          child: BuddyPillButton(
                            label: _isLoading
                                ? 'Connecting...'
                                : (_isRegisterMode ? 'Create Account →' : 'Enter Sanctuary →'),
                            fill: BuddyColors.lime,
                            textColor: BuddyColors.onLime,
                            onPressed: _isLoading ? null : _handleEmailAuth,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Google OAuth CTA
                        SizedBox(
                          width: double.infinity,
                          child: BuddyPillButton(
                            label: 'Continue with Google',
                            fill: Colors.white,
                            textColor: BuddyColors.carbon,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Direct Guest / Offline bypass
                        GestureDetector(
                          onTap: _isLoading ? null : _handleGuestEntry,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            decoration: BoxDecoration(
                              color: BuddyColors.bone,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: BuddyColors.pitch, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bolt, color: BuddyColors.carbon, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  '⚡ Quick Start (Guest / Direct ESP32)',
                                  style: BuddyTheme.captionMono(
                                    fontSize: 11,
                                    color: BuddyColors.carbon,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fluid carbon ink drip canopy painter
class _LoginInkCanopy extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BuddyColors.carbon
      ..style = PaintingStyle.fill;

    final w = size.width;
    const baseH = 90.0;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, baseH)
      ..cubicTo(
        w * 0.80, baseH + 35,
        w * 0.65, baseH - 18,
        w * 0.50, baseH + 12,
      )
      ..cubicTo(
        w * 0.35, baseH + 38,
        w * 0.15, baseH - 8,
        0, baseH,
      )
      ..close();

    canvas.drawPath(path, paint);

    // Droplets
    final dripPaint = Paint()..color = BuddyColors.carbon;
    canvas.drawCircle(Offset(w * 0.50, baseH + 22), 4, dripPaint);
    canvas.drawCircle(Offset(w * 0.28, baseH + 12), 3, dripPaint);
    canvas.drawCircle(Offset(w * 0.72, baseH + 14), 3, dripPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
