import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/core/widgets/buddy_cat_mascot.dart';
import 'package:hello_buddy/features/auth/login_screen.dart';
import 'package:hello_buddy/features/home/student_shell.dart';
import 'package:hello_buddy/services/auth_service.dart';
import 'package:hello_buddy/services/permission_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _inkController;
  late AnimationController _catController;
  late AnimationController _textController;
  late AnimationController _pulseController;

  late Animation<double> _inkDrip;
  late Animation<double> _catScale;
  late Animation<double> _catBounce;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _inkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _inkDrip = CurvedAnimation(parent: _inkController, curve: Curves.easeOutCubic);

    _catController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _catScale = CurvedAnimation(parent: _catController, curve: Curves.elasticOut);
    _catBounce = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _catController, curve: Curves.bounceOut),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _textFade = CurvedAnimation(parent: _textController, curve: Curves.easeOut);
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _inkController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _catController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _textController.forward();
    await Future.delayed(const Duration(milliseconds: 1500));

    // Request permissions before navigating
    if (mounted) {
      await PermissionService.showPermissionOnboarding(context);
    }

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      final isSignedIn = AuthService().isSignedIn;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              isSignedIn ? const StudentShell() : const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  void dispose() {
    _inkController.dispose();
    _catController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.bone,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _inkDrip,
            builder: (context, child) {
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CustomPaint(
                  painter: _InkDripPainter(progress: _inkDrip.value),
                  size: Size(MediaQuery.of(context).size.width, 220),
                ),
              );
            },
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _catController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _catScale.value,
                      child: Transform.translate(
                        offset: Offset(0, sin(_catBounce.value * pi) * -8),
                        child: const BuddyCatMascot(size: 140),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        Text(
                          'DESK COMPANION',
                          style: BuddyTheme.captionMono(
                            fontSize: 11,
                            color: BuddyColors.smoke,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Buddy',
                          style: BuddyTheme.displayFont(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: BuddyColors.carbon,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, _) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: BuddyColors.lime
                                        .withValues(alpha: _pulse.value),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: BuddyColors.lime
                                            .withValues(alpha: _pulse.value * 0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pairing with buddy_bot_01...',
                              style: BuddyTheme.bodyFont(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: BuddyColors.smoke,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _inkDrip,
            builder: (context, child) {
              return Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Transform.flip(
                  flipY: true,
                  child: CustomPaint(
                    painter: _InkDripPainter(progress: _inkDrip.value),
                    size: Size(MediaQuery.of(context).size.width, 80),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InkDripPainter extends CustomPainter {
  final double progress;

  _InkDripPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BuddyColors.carbon
      ..style = PaintingStyle.fill;

    final w = size.width;
    final baseH = size.height * 0.55 * progress;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, baseH)
      ..cubicTo(
        w * 0.82, baseH + 40 * progress,
        w * 0.68, baseH - 20 * progress,
        w * 0.50, baseH + 15 * progress,
      )
      ..cubicTo(
        w * 0.35, baseH + 45 * progress,
        w * 0.18, baseH - 10 * progress,
        0, baseH,
      )
      ..close();

    canvas.drawPath(path, paint);

    if (progress > 0.6) {
      final dripAlpha = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
      final dripPaint = Paint()
        ..color = BuddyColors.carbon.withValues(alpha: dripAlpha);

      canvas.drawCircle(Offset(w * 0.50, baseH + 25 * progress), 5 * progress, dripPaint);
      canvas.drawCircle(Offset(w * 0.25, baseH + 10 * progress), 3 * progress, dripPaint);
      canvas.drawCircle(Offset(w * 0.73, baseH + 12 * progress), 3.5 * progress, dripPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkDripPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
