import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';

/// The Buddy cat mascot — vector-drawn with CustomPainter
/// High-contrast white outline over dark backgrounds, lime nose
class BuddyCatMascot extends StatelessWidget {
  final double size;

  const BuddyCatMascot({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: CustomPaint(
        painter: _CatMascotPainter(),
        size: Size(size, size * 0.82),
      ),
    );
  }
}

class _CatMascotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // ---- EARS ----
    final earPaint = Paint()
      ..color = BuddyColors.carbon
      ..style = PaintingStyle.fill;
    final earStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final earInner = Paint()
      ..color = BuddyColors.lime.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    // Left ear
    final leftEar = Path()
      ..moveTo(w * 0.14, h * 0.58)
      ..lineTo(w * 0.27, h * 0.08)
      ..lineTo(w * 0.42, h * 0.45)
      ..close();
    canvas.drawPath(leftEar, earPaint);
    canvas.drawPath(leftEar, earStroke);

    // Left ear inner
    final leftEarInner = Path()
      ..moveTo(w * 0.21, h * 0.48)
      ..lineTo(w * 0.28, h * 0.19)
      ..lineTo(w * 0.37, h * 0.40)
      ..close();
    canvas.drawPath(leftEarInner, earInner);

    // Right ear
    final rightEar = Path()
      ..moveTo(w * 0.86, h * 0.58)
      ..lineTo(w * 0.73, h * 0.08)
      ..lineTo(w * 0.58, h * 0.45)
      ..close();
    canvas.drawPath(rightEar, earPaint);
    canvas.drawPath(rightEar, earStroke);

    // Right ear inner
    final rightEarInner = Path()
      ..moveTo(w * 0.79, h * 0.48)
      ..lineTo(w * 0.72, h * 0.19)
      ..lineTo(w * 0.63, h * 0.40)
      ..close();
    canvas.drawPath(rightEarInner, earInner);

    // ---- HEAD ----
    final headRect = RRect.fromRectAndCorners(
      Rect.fromCenter(center: Offset(cx, h * 0.68), width: w * 0.82, height: h * 0.58),
      topLeft: const Radius.circular(40),
      topRight: const Radius.circular(40),
      bottomLeft: const Radius.circular(50),
      bottomRight: const Radius.circular(50),
    );
    canvas.drawRRect(headRect, earPaint);
    canvas.drawRRect(headRect, earStroke);

    // ---- EYES ----
    final eyeWhite = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final eyeBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final pupil = Paint()
      ..color = BuddyColors.pitch
      ..style = PaintingStyle.fill;
    final glint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Left eye
    final leftEyeCenter = Offset(cx - w * 0.16, h * 0.64);
    canvas.drawCircle(leftEyeCenter, w * 0.135, eyeWhite);
    canvas.drawCircle(leftEyeCenter, w * 0.135, eyeBorder);
    canvas.drawCircle(Offset(leftEyeCenter.dx + 2, leftEyeCenter.dy), w * 0.088, pupil);
    canvas.drawCircle(Offset(leftEyeCenter.dx + 5, leftEyeCenter.dy - 5), w * 0.032, glint);
    canvas.drawCircle(Offset(leftEyeCenter.dx - 3, leftEyeCenter.dy + 5), w * 0.015, glint);

    // Right eye
    final rightEyeCenter = Offset(cx + w * 0.16, h * 0.64);
    canvas.drawCircle(rightEyeCenter, w * 0.135, eyeWhite);
    canvas.drawCircle(rightEyeCenter, w * 0.135, eyeBorder);
    canvas.drawCircle(Offset(rightEyeCenter.dx - 2, rightEyeCenter.dy), w * 0.088, pupil);
    canvas.drawCircle(Offset(rightEyeCenter.dx + 3, rightEyeCenter.dy - 5), w * 0.032, glint);
    canvas.drawCircle(Offset(rightEyeCenter.dx - 5, rightEyeCenter.dy + 5), w * 0.015, glint);

    // ---- NOSE ----
    final nosePaint = Paint()
      ..color = BuddyColors.lime
      ..style = PaintingStyle.fill;
    final nosePath = Path()
      ..moveTo(cx, h * 0.78)
      ..lineTo(cx - w * 0.035, h * 0.72)
      ..lineTo(cx + w * 0.035, h * 0.72)
      ..close();
    canvas.drawPath(nosePath, nosePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mini avatar version of the cat mascot (for headers)
class BuddyCatAvatar extends StatelessWidget {
  final double size;

  const BuddyCatAvatar({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: BuddyColors.carbon,
        shape: BoxShape.circle,
        border: Border.all(color: BuddyColors.pitch, width: 2),
      ),
      child: ClipOval(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: BuddyCatMascot(size: size * 0.85),
        ),
      ),
    );
  }
}
