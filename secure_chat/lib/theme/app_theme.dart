import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color terminalBg = Color(0xFF0B0F0C);
  static const Color terminalCard = Color(0xFF141A17);
  static const Color terminalBorder = Color(0xFF2A3430);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentGreenBright = Color(0xFF3AFF72);
  static const Color warningRed = Color(0xFFE53935);
  static const Color warningAmber = Color(0xFFFFC857);
  static const Color terminalText = Color(0xFFC0C5C3);
  static const Color terminalDim = Color(0xFF23302a);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: terminalBg,
      primaryColor: accentGreen,
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        secondary: accentGreenBright,
        surface: terminalCard,
        background: terminalBg,
        error: warningRed,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: Colors.white,
        onBackground: Colors.white,
        onError: Colors.white,
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.ibmPlexMono(color: terminalText, fontSize: 16),
        bodyMedium: GoogleFonts.ibmPlexMono(color: terminalText, fontSize: 14),
        bodySmall: GoogleFonts.ibmPlexMono(color: terminalText, fontSize: 12),
        labelLarge: GoogleFonts.ibmPlexMono(color: terminalText, fontSize: 14, fontWeight: FontWeight.bold),
        labelMedium: GoogleFonts.ibmPlexMono(color: terminalText, fontSize: 12, fontWeight: FontWeight.bold),
        labelSmall: GoogleFonts.ibmPlexMono(color: terminalText, fontSize: 10, fontWeight: FontWeight.w500),
        titleLarge: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        titleMedium: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        titleSmall: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: terminalBg.withOpacity(0.95),
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: terminalText),
        titleTextStyle: GoogleFonts.jetBrainsMono(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      iconTheme: const IconThemeData(
        color: accentGreen,
      ),
    );
  }

  // Common BoxShadows
  static List<BoxShadow> get glowGreen => [
        BoxShadow(
          color: accentGreen.withOpacity(0.1),
          blurRadius: 10,
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get glowRed => [
        BoxShadow(
          color: warningRed.withOpacity(0.3),
          blurRadius: 15,
          spreadRadius: 0,
        ),
      ];
}
