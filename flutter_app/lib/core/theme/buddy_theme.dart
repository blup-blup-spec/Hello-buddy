import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hello_buddy/core/theme/buddy_colors.dart';

export 'buddy_colors.dart';

class BuddyTheme {
  BuddyTheme._();

  /// Cabinet Grotesk — Display / Headlines
  static TextStyle displayFont({
    double fontSize = 34,
    FontWeight fontWeight = FontWeight.w800,
    Color color = BuddyColors.pitch,
    double letterSpacing = -1.0,
  }) {
    // Use a comparable font from Google Fonts since Cabinet Grotesk isn't on Google Fonts
    // DM Sans with ExtraBold weight achieves the sharp geometric editorial feel
    return GoogleFonts.dmSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: 1.18,
    );
  }

  /// Satoshi — Body / Captions
  static TextStyle bodyFont({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = BuddyColors.pitch,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: 1.5,
    );
  }

  /// Caption mono style
  static TextStyle captionMono({
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w700,
    Color color = BuddyColors.smoke,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: 1.2,
      height: 1.27,
    );
  }

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: BuddyColors.bone,
      colorScheme: const ColorScheme.light(
        primary: BuddyColors.lime,
        onPrimary: BuddyColors.onLime,
        secondary: BuddyColors.smoke,
        onSecondary: Colors.white,
        surface: BuddyColors.bone,
        onSurface: BuddyColors.pitch,
        error: BuddyColors.coral,
        onError: Colors.white,
      ),
      textTheme: TextTheme(
        displayLarge: displayFont(fontSize: 38, fontWeight: FontWeight.w900),
        displayMedium: displayFont(fontSize: 28, fontWeight: FontWeight.w800),
        displaySmall: displayFont(fontSize: 22, fontWeight: FontWeight.w800),
        headlineMedium: displayFont(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleSmall: bodyFont(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        bodyLarge: bodyFont(fontSize: 16),
        bodyMedium: bodyFont(fontSize: 14),
        bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.2),
        labelSmall: captionMono(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: BuddyColors.carbon,
        foregroundColor: BuddyColors.bone,
        elevation: 0,
        titleTextStyle: displayFont(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: BuddyColors.bone,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: BuddyColors.carbon,
        selectedItemColor: BuddyColors.lime,
        unselectedItemColor: BuddyColors.smoke,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BuddyColors.carbon,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        actionTextColor: BuddyColors.lime,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: BuddyColors.lime, width: 2),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BuddyColors.carbon,
      colorScheme: const ColorScheme.dark(
        primary: BuddyColors.lime,
        onPrimary: BuddyColors.onLime,
        secondary: BuddyColors.smoke,
        surface: BuddyColors.surfaceContainer,
        onSurface: BuddyColors.bone,
        error: BuddyColors.coral,
      ),
    );
  }
}
