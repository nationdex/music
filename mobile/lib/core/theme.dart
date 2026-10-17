/// ThemeData for Adi Music: the web build's Material 3 tokens, M PLUS Rounded 1c,
/// and its type scale (site/assets/uno.config.js).
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'palette.dart';

const fontFamily = 'MPlusRounded1c';

TextStyle _style(double size, double line, double spacing, FontWeight weight) =>
    TextStyle(fontFamily: fontFamily, fontSize: size, height: line / size, letterSpacing: spacing, fontWeight: weight);

/// Type scale from the web build, in logical pixels.
final TextTheme adiTextTheme = TextTheme(
  displayLarge: _style(57, 64, -0.25, FontWeight.w400),
  displayMedium: _style(45, 52, 0, FontWeight.w400),
  displaySmall: _style(36, 44, 0, FontWeight.w400),
  headlineLarge: _style(32, 40, 0, FontWeight.w700),
  headlineMedium: _style(28, 36, 0, FontWeight.w700),
  headlineSmall: _style(24, 32, 0, FontWeight.w700),
  titleLarge: _style(22, 28, 0, FontWeight.w500),
  titleMedium: _style(16, 24, 0.15, FontWeight.w500),
  titleSmall: _style(14, 20, 0.1, FontWeight.w500),
  bodyLarge: _style(16, 24, 0.15, FontWeight.w400),
  bodyMedium: _style(14, 20, 0.25, FontWeight.w400),
  bodySmall: _style(12, 16, 0.4, FontWeight.w400),
  labelLarge: _style(14, 20, 0.1, FontWeight.w500),
  labelMedium: _style(12, 16, 0.5, FontWeight.w500),
  labelSmall: _style(11, 16, 0.5, FontWeight.w500),
);

/// Matches `.interactable`, `.filled-button` and friends: 40 px high, fully rounded.
const _buttonShape = StadiumBorder();
const _buttonSize = Size(0, 40);
const _buttonPadding = EdgeInsets.symmetric(horizontal: 24);

ThemeData buildTheme(Brightness brightness, {Color? accent}) {
  final scheme = buildColorScheme(brightness, accent: accent);
  final text = adiTextTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    fontFamily: fontFamily,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: text.bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurface),
      labelType: NavigationRailLabelType.none,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: _buttonSize,
        padding: _buttonPadding,
        shape: _buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: _buttonSize,
        padding: _buttonPadding,
        shape: _buttonShape,
        textStyle: text.labelLarge,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: _buttonSize,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: _buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1, thickness: 1),
    sliderTheme: SliderThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.primary.withValues(alpha: 0.24),
      thumbColor: scheme.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.secondaryContainer,
        selectedForegroundColor: scheme.onSecondaryContainer,
        textStyle: text.labelLarge,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
