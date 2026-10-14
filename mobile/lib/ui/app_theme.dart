import 'package:flutter/material.dart';

/// 쉼표, — 무채색의 사색. 모든 화면이 같은 표면과 대비를 사용한다.
abstract final class AppTheme {
  static const pageInset = 16.0;
  static const sectionGap = 24.0;
  static const controlRadius = 12.0;
  static const surfaceRadius = 16.0;
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  /// 색상과 글씨 크기는 유지하며 플랫폼의 기존 기본 글꼴만 복원한다.
  static ThemeData withDefaultFont(ThemeData theme) {
    final defaults = ThemeData(
      useMaterial3: theme.useMaterial3,
      platform: theme.platform,
      colorScheme: theme.colorScheme,
    );
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: defaults.textTheme.bodyMedium!.fontFamily,
      ),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: defaults.primaryTextTheme.bodyMedium!.fontFamily,
      ),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = Color(dark ? 0xFF171717 : 0xFFF6F6F4);
    final surface = Color(dark ? 0xFF242424 : 0xFFFFFFFF);
    final elevated = Color(dark ? 0xFF303030 : 0xFFECECEB);
    final text = Color(dark ? 0xFFF0F0F0 : 0xFF252525);
    final secondary = Color(dark ? 0xFFB0B0B0 : 0xFF626262);
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
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'GowunBatang',
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(surfaceRadius),
      side: BorderSide(color: border),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(controlRadius),
      borderSide: BorderSide(color: border),
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .apply(bodyColor: text, displayColor: text)
          .copyWith(
            bodySmall: base.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.5,
            ),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              color: text,
              height: 1.6,
            ),
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
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: text,
          height: 1.5,
        ),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: text,
          height: 1.6,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        textStyle: base.textTheme.bodyMedium?.copyWith(color: text),
        menuPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondary,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: pageInset,
          vertical: 4,
        ),
        minVerticalPadding: 12,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(text),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? elevated : surface,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
          ),
          textStyle: WidgetStatePropertyAll(base.textTheme.labelLarge),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        labelStyle: base.textTheme.bodySmall?.copyWith(
          color: text,
          height: 1.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(48, 48),
          textStyle: base.textTheme.labelLarge,
        ),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(accent)),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(background),
        side: BorderSide(color: secondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: elevated,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelMedium?.copyWith(color: text),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevated,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: text),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
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
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: accent),
        ),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: text)),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: text),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        textColor: text,
        collapsedTextColor: text,
        iconColor: secondary,
        collapsedIconColor: secondary,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
    );
  }
}
