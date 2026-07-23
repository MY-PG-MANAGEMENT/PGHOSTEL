import 'package:flutter/material.dart';

import 'page_transitions.dart';

/// Purple + White palette for the tenant experience (Material Design 3).
/// Kept separate from [PgColors] so the tenant app can carry its own brand
/// (#6C5CE7) without affecting the owner/admin theme.
abstract final class TenantColors {
  static const primary = Color(0xFF6C5CE7); // brand purple
  static const primaryDark = Color(0xFF4B3FC4);
  static const primarySoft = Color(0xFFEEEBFF); // tinted surface / chips
  static const accent = Color(0xFF8B7CF6);
  static const scaffold = Color(0xFFF7F6FD);
  static const surface = Colors.white;
  static const ink = Color(0xFF1A1730);
  static const textSecondary = Color(0xFF6B6880);
  static const textTertiary = Color(0xFFA09DB4);
  static const border = Color(0xFFEBE9F5);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF2563EB);
}

/// A theme wrapper applied around the tenant subtree so tenant screens render
/// in the purple MD3 look regardless of the global app theme.
ThemeData buildTenantTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: TenantColors.primary,
    primary: TenantColors.primary,
    surface: TenantColors.surface,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TenantColors.scaffold,
    fontFamily: 'Roboto',
    pageTransitionsTheme: smoothPageTransitionsTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: TenantColors.scaffold,
      foregroundColor: TenantColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: TenantColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: TenantColors.primary.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: TenantColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: TenantColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: TenantColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: TenantColors.primary, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TenantColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(120, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
