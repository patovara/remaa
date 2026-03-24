import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'rema_colors.dart';

class RemaTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineLarge: GoogleFonts.spaceGrotesk(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: RemaColors.onSurface,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: RemaColors.onSurface,
      ),
      titleLarge: GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: RemaColors.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: RemaColors.onSurface,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: RemaColors.onSurfaceVariant,
        letterSpacing: 1.2,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: RemaColors.surface,
      textTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: RemaColors.primaryDark,
        onPrimary: Colors.white,
        secondary: RemaColors.onSurfaceVariant,
        onSecondary: Colors.white,
        surface: RemaColors.surface,
        onSurface: RemaColors.onSurface,
        error: RemaColors.error,
        onError: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RemaColors.surfaceHighest,
        border: const UnderlineInputBorder(borderSide: BorderSide.none),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide.none),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: RemaColors.primaryDark, width: 2),
        ),
      ),
      cardTheme: const CardThemeData(
        color: RemaColors.surfaceWhite,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RemaColors.primary,
          foregroundColor: const Color(0xFF694C00),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    );
  }
}
