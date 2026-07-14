import 'package:flutter/material.dart';

/// Central light/dark theme definitions.
///
/// Kept as a single source of truth so future screens don't hardcode
/// colors/typography. Touch targets follow Material's 48x48 minimum and
/// color pairs are chosen from [ColorScheme] to keep contrast ratios
/// accessible (AGENTS.md accessibility convention).
abstract final class AppTheme {
  static const double minTouchTargetSize = 48;

  static ThemeData light() => _themeFrom(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5AAC),
          brightness: Brightness.light,
        ),
      );

  static ThemeData dark() => _themeFrom(
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5AAC),
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _themeFrom(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTargetSize),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTargetSize, minTouchTargetSize),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouchTargetSize, minTouchTargetSize),
        ),
      ),
    );
  }
}
