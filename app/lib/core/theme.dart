import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme_controller.dart';

/// 三套主题调色板：与 design/runtrail.pen 中的主题变量一一对应。
/// light = 白天「清透玻璃风」，dark = 夜间「高燃运动风」，
/// editorial = 「主题一 编辑风」（奶油纸面 + 墨色 + 荧光绿）。
class AppPalette {
  final Color bg, surface, surface2;
  final Color accent, accent2, accentDeep;
  final Color textPrimary, textSecondary, textMuted;
  final Color danger, dangerSoft, dangerStroke;
  final Color stroke, divider, tabbarBg;
  final Color onAccent, onAccent2;
  final Color glow, accentSoft, accentStroke, accentArea;
  final Color mapA, mapB, mapLine, chipBg;
  final Color heroA, heroB, heroChip;
  final Color calMid, calLow, indicator, progressTrack, cardShadow;
  // 编辑风专属：深色反转卡片（墨底 + 奶油/荧光绿文字）。
  final Color inverseSurface, onInverse, onInverseAccent;
  // Hero 卡第三渐变色 / 图表柱色 / Hero 环形指标附加色。
  final Color heroC, barColor, ringA, ringB;

  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.accent,
    required this.accent2,
    required this.accentDeep,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.danger,
    required this.dangerSoft,
    required this.dangerStroke,
    required this.stroke,
    required this.divider,
    required this.tabbarBg,
    required this.onAccent,
    required this.onAccent2,
    required this.glow,
    required this.accentSoft,
    required this.accentStroke,
    required this.accentArea,
    required this.mapA,
    required this.mapB,
    required this.mapLine,
    required this.chipBg,
    required this.heroA,
    required this.heroB,
    required this.heroChip,
    required this.calMid,
    required this.calLow,
    required this.indicator,
    required this.progressTrack,
    required this.cardShadow,
    this.inverseSurface = const Color(0x00000000),
    this.onInverse = const Color(0xFFFFFFFF),
    this.onInverseAccent = const Color(0xFFFFFFFF),
    this.heroC = const Color(0x00000000),
    this.barColor = const Color(0x00000000),
    this.ringA = const Color(0xFF3DD8D0),
    this.ringB = const Color(0xFFFFE066),
  });

  /// 是否为编辑风（发丝边框、无阴影、衬线数字、墨色标签栏）。
  bool get isEditorial => identical(this, editorial);

  /// 是否为夜间「高燃运动风」调色板。
  bool get isDark => identical(this, dark);

  /// 是否为白天「清透玻璃风」调色板。
  bool get isLight => identical(this, light);

  /// 白天：雾白 + 靛蓝紫 + 薄荷青（清透玻璃）
  static const light = AppPalette(
    bg: Color(0xFFEDEFF8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0F2F9),
    accent: Color(0xFF5E5CE6),
    accent2: Color(0xFF3DD8D0),
    accentDeep: Color(0xFF8B89E8),
    textPrimary: Color(0xFF1C1C2E),
    textSecondary: Color(0xFF7A7F94),
    textMuted: Color(0xFFA0A5B8),
    danger: Color(0xFFE8503F),
    dangerSoft: Color(0xFFFBEAE8),
    dangerStroke: Color(0xFFF3C6C0),
    stroke: Color(0xFFE7EAF3),
    divider: Color(0xFFEEF0F6),
    tabbarBg: Color(0xD9FFFFFF),
    onAccent: Color(0xFFFFFFFF),
    onAccent2: Color(0xCCFFFFFF),
    glow: Color(0x555E5CE6),
    accentSoft: Color(0x1F5E5CE6),
    accentStroke: Color(0x445E5CE6),
    accentArea: Color(0x1A5E5CE6),
    mapA: Color(0xFFE9ECF5),
    mapB: Color(0xFFF4F5FA),
    mapLine: Color(0xFFDFE3EE),
    chipBg: Color(0xF2FFFFFF),
    heroA: Color(0xFF6556E8),
    heroB: Color(0xFF786BE7),
    heroC: Color(0xFF4EA9D8),
    heroChip: Color(0x2EFFFFFF),
    calMid: Color(0xFFA5A3EE),
    calLow: Color(0xFFD9DAF5),
    indicator: Color(0xFFC9CEDC),
    progressTrack: Color(0x33FFFFFF),
    cardShadow: Color(0x121C1C2E),
    inverseSurface: Color(0xFF1C1C2E),
    onInverse: Color(0xFFFFFFFF),
    onInverseAccent: Color(0xFF5E5CE6),
    barColor: Color(0xFF8B89E8),
    ringA: Color(0xFF3DD8D0),
    ringB: Color(0xFFFFE066),
  );

  /// 夜间：炭黑 + 珊瑚橙红（高燃运动）
  static const dark = AppPalette(
    bg: Color(0xFF101014),
    surface: Color(0xFF1C1B22),
    surface2: Color(0xFF26252E),
    accent: Color(0xFFFF6B4A),
    accent2: Color(0xFFE8503F),
    accentDeep: Color(0xFFFF8F6E),
    textPrimary: Color(0xFFF5F2EE),
    textSecondary: Color(0xFFA09AA8),
    textMuted: Color(0xFF76707A),
    danger: Color(0xFFFF5A5A),
    dangerSoft: Color(0xFF331616),
    dangerStroke: Color(0x55FF5A5A),
    stroke: Color(0xFF26252E),
    divider: Color(0xFF24232C),
    tabbarBg: Color(0xFF1C1B22),
    onAccent: Color(0xFFFFFFFF),
    onAccent2: Color(0xB3FFFFFF),
    glow: Color(0x55FF6B4A),
    accentSoft: Color(0x26FF6B4A),
    accentStroke: Color(0x55FF6B4A),
    accentArea: Color(0x2EFF6B4A),
    mapA: Color(0xFF1A1921),
    mapB: Color(0xFF121118),
    mapLine: Color(0xFF23222B),
    chipBg: Color(0xE6121118),
    heroA: Color(0xFF1C1B22),
    heroB: Color(0xFF1C1B22),
    heroC: Color(0xFF1C1B22),
    heroChip: Color(0x80121118),
    calMid: Color(0x99FF6B4A),
    calLow: Color(0x55FF6B4A),
    indicator: Color(0xFF2A2833),
    progressTrack: Color(0xFF26252E),
    cardShadow: Color(0x00000000),
    inverseSurface: Color(0xFF26252E),
    onInverse: Color(0xFFF5F2EE),
    onInverseAccent: Color(0xFFFF6B4A),
    barColor: Color(0xFFFF8F6E),
    ringA: Color(0xFF3DD8D0),
    ringB: Color(0xFFFFE066),
  );

  /// 编辑风：奶油纸面 + 墨色 + 荧光绿，发丝边框、无阴影。
  static const editorial = AppPalette(
    bg: Color(0xFFF4F1E8),
    surface: Color(0xFFF4F1E8),
    surface2: Color(0xFFEFEBDD),
    accent: Color(0xFFB8E62E),
    accent2: Color(0xFFB8E62E),
    accentDeep: Color(0xFF8A8878),
    textPrimary: Color(0xFF14150F),
    textSecondary: Color(0xFF8A8878),
    textMuted: Color(0xFFA8A28E),
    danger: Color(0xFFE8503F),
    dangerSoft: Color(0xFFFBEAE8),
    dangerStroke: Color(0xFFF3C6C0),
    stroke: Color(0xFFD8D4C4),
    divider: Color(0xFFE4E0D2),
    tabbarBg: Color(0xFF14150F),
    onAccent: Color(0xFF14150F),
    onAccent2: Color(0xCC14150F),
    glow: Color(0x00000000),
    accentSoft: Color(0x20B8E62E),
    accentStroke: Color(0x55B8E62E),
    accentArea: Color(0x1AB8E62E),
    mapA: Color(0xFFEFEBDD),
    mapB: Color(0xFFE4E0D2),
    mapLine: Color(0xFFD8D4C4),
    chipBg: Color(0xFFF4F1E8),
    heroA: Color(0xFFF4F1E8),
    heroB: Color(0xFFF4F1E8),
    heroChip: Color(0x00000000),
    calMid: Color(0xFFB8E62E),
    calLow: Color(0xFFE4E0D2),
    indicator: Color(0xFFD8D4C4),
    progressTrack: Color(0xFFD8D4C4),
    cardShadow: Color(0x00000000),
    inverseSurface: Color(0xFF14150F),
    onInverse: Color(0xFFF4F1E8),
    onInverseAccent: Color(0xFFB8E62E),
    barColor: Color(0xFF14150F),
    ringA: Color(0xFF14150F),
    ringB: Color(0xFF8A8878),
  );
}

/// 快捷取色：context.colors（跟随 ThemeController，支持三套主题）。
extension PaletteX on BuildContext {
  AppPalette get colors => select<ThemeController, AppPalette>(
    (tc) => tc.effectivePalette,
  );

  /// 当前是否为编辑风。
  bool get isEditorial => read<ThemeController>().isEditorial;
}

LinearGradient accentGradient(AppPalette p) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [p.accent, p.accent2],
);

LinearGradient heroGradient(AppPalette p) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  // 白天主题为三色渐变（靛蓝 → 中间蓝紫 → 天蓝），夜间/编辑风退化为双色。
  colors: [p.heroA, p.heroB, p.heroC],
  stops: p.isEditorial || p.isDark
      ? const [0, 1, 1]
      : const [0, 0.52, 1],
);

/// 页面背景：白天为纵向微渐变，夜间/编辑风为纯色（返回 null 不包渐变）。
LinearGradient? bgGradient(AppPalette p) => p.isLight
    ? const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEDEFF8), Color(0xFFE4E9F5)],
      )
    : null;

RadialGradient mapGradient(AppPalette p) =>
    RadialGradient(colors: [p.mapA, p.mapB]);

ThemeData buildTheme(AppThemeStyle style) {
  final brightness =
      style == AppThemeStyle.dark ? Brightness.dark : Brightness.light;
  final p = switch (style) {
    AppThemeStyle.dark => AppPalette.dark,
    AppThemeStyle.editorial => AppPalette.editorial,
    _ => AppPalette.light,
  };
  final base = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: p.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: p.accent,
      secondary: p.accent,
      surface: p.surface,
      error: p.danger,
    ),
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    dividerColor: p.divider,
    textTheme: base.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
      fontFamily: style == AppThemeStyle.editorial ? 'Noto Sans SC' : null,
    ),
  );
}

// ---------------------------------------------------------------------------
// 编辑风字体辅助：Playfair Display 衬线数字 + Noto Sans SC 中文。
// ---------------------------------------------------------------------------

/// 按 0..1 透明度派生颜色（兼容 ohos-flutter 3.22，不用 withValues）。
Color scaleAlpha(Color c, double a) => c.withAlpha((a * 255).round());

/// 中文/正文基础字体（编辑风用 Noto Sans SC，其余走系统默认）。
TextStyle appTextStyle(
  AppPalette p, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.normal,
  Color? color,
  double letterSpacing = 0,
  double? height,
}) {
  return TextStyle(
    fontFamily: p.isEditorial ? 'Noto Sans SC' : null,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? p.textPrimary,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// 编辑风的大数字：Playfair Display 衬线体；其余主题保持原有粗体。
TextStyle displayNumberStyle(
  AppPalette p, {
  double size = 48,
  Color? color,
  FontWeight weight = FontWeight.bold,
}) {
  if (p.isEditorial) {
    return TextStyle(
      fontFamily: 'Playfair Display',
      fontSize: size,
      fontWeight: weight,
      color: color ?? p.textPrimary,
      height: 1,
    );
  }
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: -2,
    height: 1,
    color: color ?? p.textPrimary,
  );
}

/// 编辑风的英文小标（如 "RUN" / "WEEK" / "KM"）：宽字距大写。
TextStyle kickerStyle(AppPalette p, {Color? color, double size = 9}) {
  return TextStyle(
    fontFamily: p.isEditorial ? 'Inter' : null,
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: 2,
    color: color ?? p.textSecondary,
  );
}

/// 时长 → "1:42:30" / "28:32"
String formatDuration(Duration d) {
  final h = d.inHours,
      m = d.inMinutes.remainder(60),
      s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 配速（秒/公里）→ 5'29" 样式
String formatPace(double? secPerKm) {
  if (secPerKm == null ||
      !secPerKm.isFinite ||
      secPerKm <= 0 ||
      secPerKm > 3600) {
    return "--'--\"";
  }
  // 先整体取整再拆分，避免秒位 59.5+ 四舍五入成 60 显示 "5'60""。
  final total = secPerKm.round();
  final m = total ~/ 60, s = total % 60;
  return "$m'${s.toString().padLeft(2, '0')}\"";
}
