import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// 主题模式：自动 / 强制白天 / 强制夜间 / 编辑风。
enum AppThemeMode { auto, light, dark, editorial }

/// 实际生效的视觉风格（Material 只认 light/dark，editorial 映射到 light 基线）。
enum AppThemeStyle { light, dark, editorial }

class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';

  AppThemeMode mode = AppThemeMode.auto;

  /// auto 模式下每分钟检查一次昼夜切换，跨过 6/19 点时自动换肤。
  Timer? _autoTimer;
  AppThemeStyle? _lastAutoStyle;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_key);
    mode = AppThemeMode.values.firstWhere(
      (m) => m.name == v,
      orElse: () => AppThemeMode.auto,
    );
    _syncAutoTimer();
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode m) async {
    mode = m;
    _syncAutoTimer();
    notifyListeners();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, m.name);
  }

  void _syncAutoTimer() {
    if (mode != AppThemeMode.auto) {
      _autoTimer?.cancel();
      _autoTimer = null;
      _lastAutoStyle = null;
      return;
    }
    _lastAutoStyle = effectiveStyle;
    _autoTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      final style = effectiveStyle;
      if (style != _lastAutoStyle) {
        _lastAutoStyle = style;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  /// 当前实际生效的视觉风格。
  AppThemeStyle get effectiveStyle {
    switch (mode) {
      case AppThemeMode.light:
        return AppThemeStyle.light;
      case AppThemeMode.dark:
        return AppThemeStyle.dark;
      case AppThemeMode.editorial:
        return AppThemeStyle.editorial;
      case AppThemeMode.auto:
        final h = DateTime.now().hour;
        return (h >= 6 && h < 19) ? AppThemeStyle.light : AppThemeStyle.dark;
    }
  }

  /// 当前实际生效的调色板。
  AppPalette get effectivePalette => switch (effectiveStyle) {
    AppThemeStyle.dark => AppPalette.dark,
    AppThemeStyle.editorial => AppPalette.editorial,
    _ => AppPalette.light,
  };

  /// 交给 MaterialApp 的模式（editorial 也映射到 light 基线）。
  ThemeMode get materialThemeMode =>
      effectiveStyle == AppThemeStyle.dark ? ThemeMode.dark : ThemeMode.light;

  bool get isEditorial => effectiveStyle == AppThemeStyle.editorial;
}

/// 快捷访问当前调色板。
extension ThemeControllerPalette on ThemeController {
  AppPalette get palette => effectivePalette;
}
