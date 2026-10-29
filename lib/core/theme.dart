import 'package:flutter/material.dart';

/// Brand colors from the Lockeye design.
const Color kAccent = Color(0xFF5EEAD4);
const Color kInk = Color(0xFF0C0F17);
const Color kAlert = Color(0xFFFF7A7A);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? kAccent : const Color(0xFF0B7F73),
    onPrimary: dark ? kInk : Colors.white,
    secondary: dark ? kAccent : const Color(0xFF0B7F73),
    onSecondary: dark ? kInk : Colors.white,
    error: dark ? kAlert : const Color(0xFFB3262E),
    onError: dark ? kInk : Colors.white,
    surface: dark ? const Color(0xFF151A26) : Colors.white,
    onSurface: dark ? const Color(0xFFEEF1F8) : const Color(0xFF121724),
    onSurfaceVariant: dark ? const Color(0xFF9AA4BA) : const Color(0xFF5A6478),
    outline: dark ? const Color(0xFF3A4560) : const Color(0xFFC9D0DE),
    outlineVariant: dark ? const Color(0xFF252C3D) : const Color(0xFFDDE2EC),
    surfaceContainerHighest: dark ? const Color(0xFF222A3B) : const Color(0xFFE6EAF2),
  );

  final background = dark ? kInk : const Color(0xFFF4F6FA);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.22 : 0.14),
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: kInk,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAccent,
      foregroundColor: kInk,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? kAccent : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? kInk : scheme.onSurfaceVariant,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
