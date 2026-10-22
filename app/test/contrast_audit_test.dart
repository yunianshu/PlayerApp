// 对比度审计：三主题下所有按钮/文字组合按 WCAG 计算对比度并断言达标。
// 正文文字（<18pt 非粗体）≥4.5:1；图形/大字 ≥3:1。
// 新增 UI 用色时把组合加进 _pairs，防止回归（用户曾反馈分享按钮看不清）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/core/theme.dart';

double _lum(Color c) {
  double ch(double v) {
    v /= 255;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use
  final r = c.red.toDouble();
  // ignore: deprecated_member_use
  final g = c.green.toDouble();
  // ignore: deprecated_member_use
  final b = c.blue.toDouble();
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
}

double contrast(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 主按钮渐变两端（accent 各加深 22%/40%，见 PrimaryButton 实现）。
Color buttonGradientStart(AppPalette c) =>
    Color.lerp(c.accent, Colors.black, 0.25)!;
Color buttonGradientEnd(AppPalette c) =>
    Color.lerp(c.accent, Colors.black, 0.40)!;

/// 底栏未选中 tab 颜色（编辑风为墨底上的柔化米白，见 main._tab）。
Color navInactive(AppPalette c) => c.isEditorial
    ? Color.lerp(c.onInverse, c.inverseSurface, 0.45)!
    : c.textMuted;

/// 海报/总结页距离大数字颜色（42–56px 粗体按大字 3:1；编辑风荧光绿
/// 在米底不足 3:1，改用墨色，见 run_poster / summary_page）。
Color bigNumber(AppPalette c) => c.isEditorial ? c.textPrimary : c.accent;

List<(String, Color, Color, double)> _pairs(AppPalette c) => [
  ('主按钮文字/渐变起点', c.onAccent, buttonGradientStart(c), 4.5),
  ('主按钮文字/渐变终点', c.onAccent, buttonGradientEnd(c), 4.5),
  ('主按钮(编辑风)', c.onInverse, c.inverseSurface, 4.5),
  ('次级按钮(分享等)', c.textPrimary, c.surface, 4.5),
  ('次级按钮(编辑风)', c.textPrimary, c.bg, 4.5),
  ('危险按钮(放弃)', c.danger, c.surface, 4.5),
  ('圆形按钮图标', c.textPrimary, c.surface, 3.0),
  ('底栏未选中', navInactive(c), c.tabbarBg, 4.5),
  ('底栏选中', c.accent, c.tabbarBg, 4.5),
  ('列表行值文字', c.textSecondary, c.surface, 4.5),
  ('chip 主文字', c.textPrimary, c.chipBg, 4.5),
  ('chip 次要文字', c.textSecondary, c.chipBg, 4.5),
  ('课程简介', c.textSecondary, c.surface, 4.5),
  ('课程元信息', c.textMuted, c.surface, 3.0),
  ('对话框强调按钮', c.isEditorial ? c.textPrimary : c.accent, c.surface, 4.5),
  ('页面正文', c.textPrimary, c.bg, 4.5),
  ('页面次要文字', c.textSecondary, c.bg, 4.5),
  ('海报/总结页大数字', bigNumber(c), c.bg, 3.0),
  ('肌群图示主发力(红)', c.danger, c.surface2, 3.0),
  ('肌群图示辅助(浅红)', Color.lerp(c.danger, c.surface, 0.2)!, c.surface2, 3.0),
];

void main() {
  for (final entry in {
    'light': AppPalette.light,
    'dark': AppPalette.dark,
    'editorial': AppPalette.editorial,
  }.entries) {
    test('${entry.key} 主题全部组合达标', () {
      for (final (label, fg, bg, min) in _pairs(entry.value)) {
        final ratio = contrast(fg, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(min),
          reason:
              '${entry.key} | $label 对比度 ${ratio.toStringAsFixed(2)} '
              '< $min（前景 ${fg.toARGB32().toRadixString(16)} / '
              '背景 ${bg.toARGB32().toRadixString(16)}）',
        );
      }
    });
  }
}
