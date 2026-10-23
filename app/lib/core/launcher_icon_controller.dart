import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/launcher_icon_service.dart';
import 'theme_controller.dart';

/// Small persistence seam also lets tests model SharedPreferences' write-through
/// cache: its cache changes before the platform write can fail.
class LauncherIconPreferences {
  Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    return prefs.getBool(LauncherIconController.preferenceKey) ?? false;
  }

  Future<bool> save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setBool(LauncherIconController.preferenceKey, value);
  }
}

/// Serializes launcher changes, including theme changes during an in-flight call.
/// A failed icon change never rolls back the app's own theme.
class LauncherIconController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const preferenceKey = 'launcher_icon_follows_theme';
  final ThemeController theme;
  final LauncherIconService service;
  final LauncherIconPreferences preferences;
  bool loaded = false;
  bool supported = false;
  bool enabled = false;
  bool busy = false;
  String? error;
  bool _desiredEnabled = false;
  bool _preferenceNeedsRepair = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void>? _pending;
  String? _appliedStyle;
  late AppThemeStyle _observedStyle;

  LauncherIconController(
    this.theme, {
    LauncherIconService? service,
    LauncherIconPreferences? preferences,
  }) : service = service ?? LauncherIconService(),
       preferences = preferences ?? LauncherIconPreferences() {
    _observedStyle = theme.effectiveStyle;
    theme.addListener(_themeChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> load() async {
    if (loaded) return;
    try {
      enabled = await preferences.read();
    } on Object {
      enabled = false;
    }
    supported = await service.isSupported();
    if (_disposed) return;
    _desiredEnabled = enabled;
    loaded = true;
    _notify();
    if (supported) await _sync();
  }

  Future<bool> setEnabled(bool value) async {
    if (!loaded || !supported || _disposed) return false;
    _desiredEnabled = value;
    await _sync();
    return !_disposed && enabled == value && error == null;
  }

  void _themeChanged() {
    final style = theme.effectiveStyle;
    if (_observedStyle == style) return;
    _observedStyle = style;
    if (loaded && supported && _desiredEnabled) unawaited(_sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A timed theme may have crossed the day/night boundary while suspended.
    if (state == AppLifecycleState.resumed && loaded && supported) {
      _observedStyle = theme.effectiveStyle;
      _appliedStyle = null; // Reconcile with the actual native component state.
      unawaited(_sync());
    }
  }

  Future<void> _sync() {
    _revision++;
    if (_pending != null) return _pending!;
    final completion = Completer<void>();
    _pending = completion.future;
    // Set the guard before any notification can cause a reentrant request.
    scheduleMicrotask(() async {
      try {
        await _drain();
        _pending = null;
        busy = false;
        _notify();
        completion.complete();
      } on Object catch (error, stack) {
        _pending = null;
        busy = false;
        _notify();
        completion.completeError(error, stack);
      }
    });
    return completion.future;
  }

  Future<void> _drain() async {
    busy = true;
    error = null;
    _notify();
    var processed = -1;
    while (!_disposed && processed != _revision) {
      processed = _revision;
      final nextEnabled = _desiredEnabled;
      final nextStyle = nextEnabled ? theme.effectiveStyle.name : 'default';
      final previousEnabled = enabled;
      final previousStyle = _appliedStyle;
      var preferenceWriteAttempted = false;
      try {
        if (_appliedStyle != nextStyle) await service.setIcon(nextStyle);
        if (_disposed) break;
        if (nextEnabled != enabled || _preferenceNeedsRepair) {
          preferenceWriteAttempted = true;
          final saved = await preferences.save(nextEnabled);
          if (!saved) throw StateError('Unable to save launcher preference');
          _preferenceNeedsRepair = false;
        }
        enabled = nextEnabled;
        _appliedStyle = nextStyle;
        error = null;
      } on Object {
        // Restore the previous native state when preference persistence fails,
        // and reconcile any partial native failure. Native also rolls back.
        var restored = true;
        if (preferenceWriteAttempted) {
          try {
            // Restore cache AND durable state, not only the UI/native icon.
            restored = await preferences.save(previousEnabled);
          } on Object {
            restored = false;
          }
          _preferenceNeedsRepair = !restored;
        }
        try {
          await service.setIcon(
            previousStyle ??
                (previousEnabled ? theme.effectiveStyle.name : 'default'),
          );
        } on Object {
          // Do not claim a restored icon when the OS rejected the rollback.
          _appliedStyle = null;
          restored = false;
        }
        error = restored
            ? '桌面图标设置失败，已保留原设置；应用主题不受影响。'
            : '桌面图标状态未能确认，请返回应用后重试；应用主题不受影响。';
        if (processed == _revision) _desiredEnabled = enabled;
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    theme.removeListener(_themeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
