import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class BkColors {
  static const ink = Color(0xFF2A2E28);
  static const inkSoft = Color(0xFF5C6358);
  static const paper = Color(0xFFF3EFE6);
  static const paperDeep = Color(0xFFE7E0D2);
  static const cream = Color(0xFFF7F3EB);
  static const creamWarm = Color(0xFFEFE8DA);
  static const leaf = Color(0xFF3D5A45);
  static const leafSoft = Color(0xFF6B8F76);
  static const leafHover = Color(0xFF334C3A);
  static const clay = Color(0xFF7A5C3E);
  static const claySoft = Color(0xFFA88762);
  static const mist = Color(0xFFD5DDD4);
  static const accent = Color(0xFFC4784A);
  static const danger = Color(0xFF8B4A3F);
  static const card = Color(0xC7FFFCF6);
  static const leafTint = Color(0x1F3D5A45);
  static const leafBorder = Color(0x1A3D5A45);

  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: leaf,
    onPrimary: cream,
    secondary: clay,
    onSecondary: cream,
    tertiary: accent,
    onTertiary: cream,
    error: danger,
    onError: cream,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: inkSoft,
    outline: Color(0x383D5A45),
    outlineVariant: mist,
    surfaceContainerHighest: paperDeep,
    surfaceContainerHigh: cream,
    inversePrimary: leafSoft,
  );
}

final ThemeData bibliotekaTheme = (() {
  final baseText = GoogleFonts.sourceSans3TextTheme().apply(
    bodyColor: BkColors.ink,
    displayColor: BkColors.ink,
  );
  final textTheme = baseText.copyWith(
    headlineLarge: GoogleFonts.fraunces(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: BkColors.ink,
    ),
    headlineMedium: GoogleFonts.fraunces(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: BkColors.ink,
    ),
    headlineSmall: GoogleFonts.fraunces(
      fontWeight: FontWeight.w600,
      fontSize: 26,
      letterSpacing: -0.4,
      color: BkColors.ink,
    ),
    titleLarge: GoogleFonts.fraunces(
      fontWeight: FontWeight.w600,
      color: BkColors.ink,
    ),
    titleMedium: GoogleFonts.fraunces(
      fontWeight: FontWeight.w600,
      fontSize: 18,
      color: BkColors.ink,
    ),
    titleSmall: GoogleFonts.sourceSans3(
      fontWeight: FontWeight.w600,
      fontSize: 12,
      letterSpacing: 1.4,
      color: BkColors.leaf,
    ),
  );

  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: BkColors.scheme,
    scaffoldBackgroundColor: BkColors.paper,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: BkColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.fraunces(
        fontWeight: FontWeight.w600,
        fontSize: 22,
        color: BkColors.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BkColors.leaf,
        foregroundColor: BkColors.cream,
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.sourceSans3(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BkColors.leaf,
        foregroundColor: BkColors.cream,
        elevation: 0,
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: BkColors.ink,
        side: const BorderSide(color: Color(0x383D5A45)),
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BkColors.leaf,
        textStyle: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: BkColors.leaf),
    ),
    cardTheme: CardThemeData(
      color: BkColors.card,
      elevation: 0,
      shape: cardShape.copyWith(
        side: const BorderSide(color: BkColors.leafBorder),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BkColors.cream;
        return BkColors.mist;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return BkColors.leafSoft;
        return BkColors.paperDeep;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BkColors.leaf,
    ),
    dividerTheme: const DividerThemeData(color: BkColors.leafBorder),
    dialogTheme: DialogThemeData(
      backgroundColor: BkColors.cream,
      shape: cardShape,
    ),
  );
})();
