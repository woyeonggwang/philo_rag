import 'package:flutter/material.dart';

/// 쉼표, — 무채색의 사색. 모든 화면이 같은 표면과 대비를 사용한다.
abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = Color(dark ? 0xFF171717 : 0xFFF6F6F4);
    final surface = Color(dark ? 0xFF242424 : 0xFFFFFFFF);
    final elevated = Color(dark ? 0xFF303030 : 0xFFECECEB);
    final text = Color(dark ? 0xFFF0F0F0 : 0xFF252525);
    final secondary = Color(dark ? 0xFFA3A3A3 : 0xFF737373);
    final border = Color(dark ? 0xFF383838 : 0xFFE2E2E0);
    final accent = Color(dark ? 0xFFD4D4D4 : 0xFF404040);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: background,
      primaryContainer: elevated,
      onPrimaryContainer: text,
      secondary: accent,
      onSecondary: background,
      secondaryContainer: elevated,
      onSecondaryContainer: text,
      tertiary: accent,
      onTertiary: background,
      tertiaryContainer: elevated,
      onTertiaryContainer: text,
      error: text,
      onError: background,
      errorContainer: elevated,
      onErrorContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: elevated,
      surfaceContainerHighest: elevated,
      outline: secondary,
      outlineVariant: border,
      inverseSurface: text,
      onInverseSurface: background,
      inversePrimary: background,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: border),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: border),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text).copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(color: secondary, height: 1.5),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: text, height: 1.6),
      ),
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: secondary),
        labelStyle: TextStyle(color: secondary),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: accent)),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: text)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: text)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        textColor: secondary,
        collapsedTextColor: secondary,
        iconColor: secondary,
        collapsedIconColor: secondary,
      ),
    );
  }
}
