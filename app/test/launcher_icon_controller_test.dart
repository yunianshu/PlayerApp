import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/core/launcher_icon_controller.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/services/launcher_icon_service.dart';

class FakeIcons extends LauncherIconService {
  bool support = true;
  String current = 'default';
  final calls = <String>[];
  String? failStyle;
  Completer<void>? gate;
  int active = 0;
  int maxActive = 0;
  @override
  Future<bool> isSupported() async => support;
  @override
  Future<void> setIcon(String style) async {
    calls.add(style);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      final wait = gate;
      gate = null;
      await wait?.future;
      if (style == failStyle) throw StateError('OS rejected change');
      current = style;
    } finally {
      active--;
    }
  }
}

class FailingPreferences extends LauncherIconPreferences {
  bool value = false;
  int failures = 1;
  int saves = 0;
  @override
  Future<bool> read() async => value;
  @override
  Future<bool> save(bool next) async {
    saves++;
    value = next; // Matches SharedPreferences' write-before-result cache.
    if (failures > 0) {
      failures--;
      return false;
    }
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ThemeController theme;
  late FakeIcons service;
  late LauncherIconController controller;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController()..mode = AppThemeMode.light;
    service = FakeIcons();
    controller = LauncherIconController(theme, service: service);
  });
  tearDown(() {
    controller.dispose();
    theme.dispose();
  });
  test('unsupported stays off, cannot claim success', () async {
    service.support = false;
    await controller.load();
    expect(controller.loaded, isTrue);
    expect(controller.enabled, isFalse);
    expect(controller.supported, isFalse);
    expect(await controller.setEnabled(true), isFalse);
    expect(service.calls, isEmpty);
  });
  test('opt in uses theme and persists; disable restores default', () async {
    await controller.load();
    expect(controller.enabled, isFalse);
    expect(await controller.setEnabled(true), isTrue);
    expect(service.current, 'light');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(LauncherIconController.preferenceKey), isTrue);
    expect(await controller.setEnabled(false), isTrue);
    expect(service.current, 'default');
    expect(prefs.getBool(LauncherIconController.preferenceKey), isFalse);
  });
  test('restart restores persisted opt in using current theme', () async {
    SharedPreferences.setMockInitialValues({
      LauncherIconController.preferenceKey: true,
    });
    theme.mode = AppThemeMode.editorial;
    await controller.load();
    expect(controller.enabled, isTrue);
    expect(service.current, 'editorial');
  });
  test('all themes sync when enabled and stop when disabled', () async {
    await controller.load();
    await controller.setEnabled(true);
    await theme.setMode(AppThemeMode.dark);
    await controller.setEnabled(true);
    expect(service.current, 'dark');
    await theme.setMode(AppThemeMode.editorial);
    await controller.setEnabled(true);
    expect(service.current, 'editorial');
    await controller.setEnabled(false);
    await theme.setMode(AppThemeMode.light);
    expect(service.current, 'default');
  });
  test(
    'failed enable keeps previous preference and icon, not app theme',
    () async {
      await controller.load();
      service.failStyle = 'light';
      expect(await controller.setEnabled(true), isFalse);
      expect(controller.enabled, isFalse);
      expect(controller.error, isNotNull);
      expect(service.current, 'default');
      expect(theme.mode, AppThemeMode.light);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          LauncherIconController.preferenceKey,
        ),
        isNull,
      );
    },
  );
  test('failed disable preserves enabled preference and icon', () async {
    await controller.load();
    await controller.setEnabled(true);
    service.failStyle = 'default';
    expect(await controller.setEnabled(false), isFalse);
    expect(controller.enabled, isTrue);
    expect(service.current, 'light');
  });
  test('rapid toggle requests serialized, latest wins', () async {
    await controller.load();
    final gate = Completer<void>();
    service.gate = gate;
    final on = controller.setEnabled(true);
    final off = controller.setEnabled(false);
    gate.complete();
    await Future.wait([on, off]);
    expect(controller.enabled, isFalse);
    expect(service.current, 'default');
    expect(service.maxActive, 1);
    expect(controller.busy, isFalse);
  });
  test('theme changes during operation converge to newest theme', () async {
    await controller.load();
    final gate = Completer<void>();
    service.gate = gate;
    final on = controller.setEnabled(true);
    await theme.setMode(AppThemeMode.dark);
    await theme.setMode(AppThemeMode.editorial);
    gate.complete();
    await on;
    expect(service.current, 'editorial');
    expect(service.maxActive, 1);
  });
  test('resume reconciles external native state', () async {
    await controller.load();
    await controller.setEnabled(true);
    service.current = 'default';
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await controller.setEnabled(true);
    expect(service.current, 'light');
  });
  test('missing bridge reports unsupported, never fake success', () async {
    final bridge = LauncherIconService();
    expect(await bridge.isSupported(), isFalse);
    expect(bridge.setIcon('light'), throwsA(isA<MissingPluginException>()));
  });
  test(
    'failed preference write restores cache and native icon before restart',
    () async {
      controller.dispose();
      final preferences = FailingPreferences();
      controller = LauncherIconController(
        theme,
        service: service,
        preferences: preferences,
      );
      await controller.load();
      expect(await controller.setEnabled(true), isFalse);
      expect(preferences.value, isFalse);
      expect(controller.enabled, isFalse);
      expect(service.current, 'default');
      controller.dispose();
      controller = LauncherIconController(
        theme,
        service: service,
        preferences: preferences,
      );
      await controller.load();
      expect(controller.enabled, isFalse);
      expect(service.current, 'default');
    },
  );
  test('failed persistence rollback reports uncertainty', () async {
    controller.dispose();
    final preferences = FailingPreferences()..failures = 2;
    controller = LauncherIconController(
      theme,
      service: service,
      preferences: preferences,
    );
    await controller.load();
    expect(await controller.setEnabled(true), isFalse);
    expect(controller.error, contains('未能确认'));
    expect(controller.enabled, isFalse);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await controller.setEnabled(false);
    expect(preferences.saves, 3);
    expect(controller.error, isNull);
  });
  test('listener-triggered requests cannot overlap or be dropped', () async {
    await controller.load();
    var changedDuring = false;
    var changedAfter = false;
    Future<bool>? after;
    controller.addListener(() {
      if (controller.busy && !changedDuring) {
        changedDuring = true;
        unawaited(controller.setEnabled(false));
      } else if (!controller.busy && changedDuring && !changedAfter) {
        changedAfter = true;
        after = controller.setEnabled(true);
      }
    });
    await controller.setEnabled(true);
    await after;
    expect(controller.enabled, isTrue);
    expect(service.current, 'light');
    expect(service.maxActive, 1);
  });
  test('native channel contract', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(LauncherIconService.channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'getSupport' ? true : null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(LauncherIconService.channel, null),
    );
    final bridge = LauncherIconService();
    expect(await bridge.isSupported(), isTrue);
    await bridge.setIcon('editorial');
    expect(calls.last.method, 'setIcon');
    expect(calls.last.arguments, {'style': 'editorial'});
  });
}
