#!/usr/bin/env python3
"""Génère tokens.css et flutter/app_tokens.dart depuis tokens.json et tokens-dark.json.
    python3 gen_tokens.py
Ne modifier que les JSON ; relancer après chaque changement (replica-brand compris)."""
import json, re

light = json.load(open('tokens.json', encoding='utf-8'))
dark = json.load(open('tokens-dark.json', encoding='utf-8'))

def camel(n):
    p = n.split('-'); return p[0] + ''.join(x.title() for x in p[1:])

def dart_color(v):
    m = re.match(r'rgba\((\d+),(\d+),(\d+),([\d.]+)\)', v)
    if m:
        r, g, b, a = int(m[1]), int(m[2]), int(m[3]), float(m[4])
        return 'Color(0x%02X%02X%02X%02X)' % (round(a * 255), r, g, b)
    return 'Color(0xFF%s)' % v.lstrip('#').upper()

# CSS
css = ['/* Généré par gen_tokens.py : ne pas modifier à la main */', ':root {']
for k, v in light['color'].items(): css.append(f'  --color-{k}: {v};')
css.append(f'  --font-sans: {light["font"]["sans"]};')
for k, v in light['type'].items():
    css.append(f'  --text-{k}: {v["size"]}px/{v["line"]}px;  --weight-{k}: {v["weight"]};')
for i, v in enumerate(light['space']): css.append(f'  --space-{i}: {v}px;')
for k, v in light['radius'].items(): css.append(f'  --radius-{k}: {v}px;')
for k, v in light['shadow'].items(): css.append(f'  --shadow-{k}: {v};')
for k, v in light['motion'].items(): css.append(f'  --motion-{k}: {v};')
css.append('}')
css.append('@media (prefers-color-scheme: dark) {\n  :root {')
for k, v in dark['color'].items(): css.append(f'    --color-{k}: {v};')
css.append('  }\n}')
css.append('[data-theme="dark"] {')
for k, v in dark['color'].items(): css.append(f'  --color-{k}: {v};')
css.append('}')
open('tokens.css', 'w', encoding='utf-8').write('\n'.join(css) + '\n')

# Dart
d = ['// Généré par gen_tokens.py : ne pas modifier à la main.', "import 'package:flutter/material.dart';", '']
for name, src in (('light', light), ('dark', dark)):
    d.append(f'class AppColors{name.title()} {{')
    for k, v in src['color'].items(): d.append(f'  static const {camel(k)} = {dart_color(v)};')
    d.append('}\n')
d.append('/// Rôles de couleur, lus par Theme.of(context).extension de type AppPalette.')
d.append('@immutable\nclass AppPalette extends ThemeExtension<AppPalette> {')
keys = list(light['color'].keys())
d.append('  const AppPalette({' + ', '.join(f'required this.{camel(k)}' for k in keys) + '});')
for k in keys: d.append(f'  final Color {camel(k)};')
for name in ('light', 'dark'):
    d.append(f'  static const {name} = AppPalette(' + ', '.join(f'{camel(k)}: AppColors{name.title()}.{camel(k)}' for k in keys) + ');')
d.append('  @override\n  AppPalette copyWith() => this;')
d.append('  @override\n  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {')
d.append('    if (other is! AppPalette) return this;')
d.append('    return AppPalette(' + ', '.join(f'{camel(k)}: Color.lerp({camel(k)}, other.{camel(k)}, t)!' for k in keys) + ');\n  }\n}\n')
d.append('class AppSpace {')
for i, v in enumerate(light['space']): d.append(f'  static const double s{i} = {v};')
d.append('}\n')
d.append('class AppRadius {')
for k, v in light['radius'].items(): d.append(f'  static const double {k} = {v};')
d.append('}\n')
d.append('class AppSize {')
for k, v in light['size'].items():
    if isinstance(v, int): d.append(f'  static const double {camel(k)} = {v};')
d.append('}\n')
d.append('class AppText {')
for k, v in light['type'].items():
    d.append(f"  static const {camel(k)} = TextStyle(fontSize: {v['size']}, height: {v['line']/v['size']:.4f}, fontWeight: FontWeight.w{v['weight']}, fontFeatures: [FontFeature.tabularFigures()]);")
d.append('}')
open('flutter/app_tokens.dart', 'w', encoding='utf-8').write('\n'.join(d) + '\n')
print('ok')
