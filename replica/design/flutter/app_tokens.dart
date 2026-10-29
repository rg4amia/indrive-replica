// Généré par gen_tokens.py : ne pas modifier à la main.
import 'package:flutter/material.dart';

class AppColorsLight {
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF5F5F5);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4E4E7);
  static const borderInput = Color(0xFF8A8A90);
  static const text = Color(0xFF141414);
  static const textMuted = Color(0xFF5F5F66);
  static const accent = Color(0xFF2F5BEA);
  static const onAccent = Color(0xFFFFFFFF);
  static const accentSoft = Color(0xFFE8EEFE);
  static const onAccentSoft = Color(0xFF1D3FB0);
  static const danger = Color(0xFFC9302C);
  static const onDanger = Color(0xFFFFFFFF);
  static const dangerSoft = Color(0xFFFDECEB);
  static const success = Color(0xFF1F7A4D);
  static const warning = Color(0xFF8A5A00);
  static const scrim = Color(0x73141414);
}

class AppColorsDark {
  static const bg = Color(0xFF0F0F10);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceRaised = Color(0xFF262628);
  static const border = Color(0xFF3A3A3D);
  static const borderInput = Color(0xFF8E8E93);
  static const text = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFFA1A1A8);
  static const accent = Color(0xFF7C9BFF);
  static const onAccent = Color(0xFF0B1030);
  static const accentSoft = Color(0xFF1C2750);
  static const onAccentSoft = Color(0xFFC7D4FF);
  static const danger = Color(0xFFFF6B66);
  static const onDanger = Color(0xFF2A0605);
  static const dangerSoft = Color(0xFF3A1513);
  static const success = Color(0xFF4CC38A);
  static const warning = Color(0xFFF0B44C);
  static const scrim = Color(0x99000000);
}

/// Rôles de couleur, lus par Theme.of(context).extension de type AppPalette.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.bg, required this.surface, required this.surfaceRaised, required this.border, required this.borderInput, required this.text, required this.textMuted, required this.accent, required this.onAccent, required this.accentSoft, required this.onAccentSoft, required this.danger, required this.onDanger, required this.dangerSoft, required this.success, required this.warning, required this.scrim});
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color borderInput;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color onAccentSoft;
  final Color danger;
  final Color onDanger;
  final Color dangerSoft;
  final Color success;
  final Color warning;
  final Color scrim;
  static const light = AppPalette(bg: AppColorsLight.bg, surface: AppColorsLight.surface, surfaceRaised: AppColorsLight.surfaceRaised, border: AppColorsLight.border, borderInput: AppColorsLight.borderInput, text: AppColorsLight.text, textMuted: AppColorsLight.textMuted, accent: AppColorsLight.accent, onAccent: AppColorsLight.onAccent, accentSoft: AppColorsLight.accentSoft, onAccentSoft: AppColorsLight.onAccentSoft, danger: AppColorsLight.danger, onDanger: AppColorsLight.onDanger, dangerSoft: AppColorsLight.dangerSoft, success: AppColorsLight.success, warning: AppColorsLight.warning, scrim: AppColorsLight.scrim);
  static const dark = AppPalette(bg: AppColorsDark.bg, surface: AppColorsDark.surface, surfaceRaised: AppColorsDark.surfaceRaised, border: AppColorsDark.border, borderInput: AppColorsDark.borderInput, text: AppColorsDark.text, textMuted: AppColorsDark.textMuted, accent: AppColorsDark.accent, onAccent: AppColorsDark.onAccent, accentSoft: AppColorsDark.accentSoft, onAccentSoft: AppColorsDark.onAccentSoft, danger: AppColorsDark.danger, onDanger: AppColorsDark.onDanger, dangerSoft: AppColorsDark.dangerSoft, success: AppColorsDark.success, warning: AppColorsDark.warning, scrim: AppColorsDark.scrim);
  @override
  AppPalette copyWith() => this;
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(bg: Color.lerp(bg, other.bg, t)!, surface: Color.lerp(surface, other.surface, t)!, surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!, border: Color.lerp(border, other.border, t)!, borderInput: Color.lerp(borderInput, other.borderInput, t)!, text: Color.lerp(text, other.text, t)!, textMuted: Color.lerp(textMuted, other.textMuted, t)!, accent: Color.lerp(accent, other.accent, t)!, onAccent: Color.lerp(onAccent, other.onAccent, t)!, accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!, onAccentSoft: Color.lerp(onAccentSoft, other.onAccentSoft, t)!, danger: Color.lerp(danger, other.danger, t)!, onDanger: Color.lerp(onDanger, other.onDanger, t)!, dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!, success: Color.lerp(success, other.success, t)!, warning: Color.lerp(warning, other.warning, t)!, scrim: Color.lerp(scrim, other.scrim, t)!);
  }
}

class AppSpace {
  static const double s0 = 0;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 48;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double sheet = 24;
  static const double pill = 999;
}

class AppSize {
  static const double buttonMd = 48;
  static const double buttonLg = 56;
  static const double tapMin = 48;
  static const double input = 56;
  static const double avatarSm = 40;
  static const double avatarMd = 56;
  static const double mapPin = 40;
}

class AppText {
  static const caption = TextStyle(fontSize: 12, height: 1.3333, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]);
  static const small = TextStyle(fontSize: 14, height: 1.4286, fontWeight: FontWeight.w400, fontFeatures: [FontFeature.tabularFigures()]);
  static const body = TextStyle(fontSize: 16, height: 1.5000, fontWeight: FontWeight.w400, fontFeatures: [FontFeature.tabularFigures()]);
  static const label = TextStyle(fontSize: 16, height: 1.5000, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]);
  static const title = TextStyle(fontSize: 20, height: 1.4000, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);
  static const headline = TextStyle(fontSize: 24, height: 1.2500, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);
  static const price = TextStyle(fontSize: 28, height: 1.2143, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);
  static const display = TextStyle(fontSize: 36, height: 1.1667, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);
}
