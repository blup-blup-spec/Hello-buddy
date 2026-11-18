import 'package:flutter/material.dart';

/// Hello Buddy Neo-Graphic Design System — Committed 5-Ink Palette
class BuddyColors {
  BuddyColors._();

  /// Carbon Obsidian — deepest pitch chassis ink
  static const Color carbon = Color(0xFF0F1015);

  /// Bone White — editorial matte canvas
  static const Color bone = Color(0xFFF3F2EE);

  /// Solid Pitch — structural borders, drop shadows
  static const Color pitch = Color(0xFF000000);

  /// Acid Celadon Lime — sole interactive accent ink
  static const Color lime = Color(0xFFD2F858);

  /// Muted Smoke — secondary labels, timestamps
  static const Color smoke = Color(0xFF7C7B89);

  /// Alert Coral — urgent deadlines, error states
  static const Color coral = Color(0xFFFF5E5B);

  /// Surface container shades
  static const Color surfaceDim = Color(0xFF08080B);
  static const Color surfaceContainer = Color(0xFF181922);
  static const Color surfaceContainerHigh = Color(0xFF22232E);
  static const Color surfaceContainerHighest = Color(0xFF2D2E3C);

  /// On-lime text (dark text on lime backgrounds)
  static const Color onLime = Color(0xFF0B0D03);
}

/// Brutalist box decoration builders
class BuddyDecorations {
  BuddyDecorations._();

  /// Standard card: 2px solid pitch, 4px flat drop shadow, rounded 20px
  static BoxDecoration card({
    Color fill = BuddyColors.bone,
    double radius = 20,
  }) {
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: BuddyColors.pitch, width: 2),
      boxShadow: const [
        BoxShadow(
          color: BuddyColors.pitch,
          offset: Offset(0, 4),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ],
    );
  }

  /// Small shadow variant
  static BoxDecoration cardSmall({
    Color fill = BuddyColors.bone,
    double radius = 16,
  }) {
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: BuddyColors.pitch, width: 2),
      boxShadow: const [
        BoxShadow(
          color: BuddyColors.pitch,
          offset: Offset(0, 2),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ],
    );
  }

  /// Pill button
  static BoxDecoration pill({
    Color fill = BuddyColors.lime,
    double radius = 999,
  }) {
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: BuddyColors.pitch, width: 2),
      boxShadow: const [
        BoxShadow(
          color: BuddyColors.pitch,
          offset: Offset(0, 4),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ],
    );
  }

  /// Ghost pill (dashed look via solid thin border)
  static BoxDecoration ghostPill({
    Color fill = Colors.transparent,
    double radius = 999,
  }) {
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: BuddyColors.pitch, width: 1.5),
    );
  }

  /// Input field decoration
  static BoxDecoration inputField({double radius = 999}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: BuddyColors.pitch, width: 2),
      boxShadow: const [
        BoxShadow(
          color: BuddyColors.pitch,
          offset: Offset(0, 4),
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ],
    );
  }
}
