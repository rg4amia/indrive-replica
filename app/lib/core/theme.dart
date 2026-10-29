import 'package:flutter/material.dart';
import 'app_tokens.dart';

ThemeData appTheme(Brightness b) {
  final palette = b == Brightness.light ? AppPalette.light : AppPalette.dark;
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    scaffoldBackgroundColor: palette.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: palette.accent, brightness: b).copyWith(
      surface: palette.bg,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      error: palette.danger,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: palette.bg),
    extensions: [palette],
  );
}

AppPalette pal(BuildContext c) => Theme.of(c).extension<AppPalette>()!;
