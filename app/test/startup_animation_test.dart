import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:runtrail/core/i18n.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/widgets/splash_gate.dart';
import 'package:runtrail/widgets/startup_animation.dart';

class _UnavailablePreferences extends InMemorySharedPreferencesStore {
  _UnavailablePreferences({this.waitForever = false}) : super.empty();
  final bool waitForever;

  @override
  Future<Map<String, Object>> getAll() => waitForever
      ? Completer<Map<String, Object>>().future
      : Future.error(PlatformException(code: 'unavailable'));
}

class _HomeProbe extends StatefulWidget {
  const _HomeProbe({required this.onInit, required this.onTap});
  final VoidCallback onInit;
  final VoidCallback onTap;

  @override
  State<_HomeProbe> createState() => _HomeProbeState();
}

class _HomeProbeState extends State<_HomeProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(onPressed: widget.onTap, child: const Text('Home')),
    ),
  );
}

Widget _wrap(
  ThemeController theme, {
  Widget child = const Scaffold(body: Text('Home')),
  bool reducedMotion = false,
  bool enabled = true,
}) => ChangeNotifierProvider.value(
  value: theme,
  child: Builder(
    builder: (context) => MaterialApp(
      theme: buildTheme(context.watch<ThemeController>().effectiveStyle),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: SplashGate(enabled: enabled, child: child),
      ),
    ),
  ),
);

Future<void> _loadFonts() async {
  for (final entry in {
    'Noto Sans SC': ['NotoSansSC-Regular.ttf', 'NotoSansSC-Bold.ttf'],
    'Inter': ['Inter-SemiBold.ttf'],
    'Barlow Condensed': [
      'BarlowCondensed-Bold.ttf',
      'BarlowCondensed-BoldItalic.ttf',
    ],
    'Playfair Display': [
      'PlayfairDisplay-Regular.ttf',
      'PlayfairDisplay-Bold.ttf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.pref = AppLanguage.zh;
  });

  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.editorial,
  ]) {
    testWidgets(
      'saved ${mode.name} appears on first frame and survives relaunch',
      (tester) async {
        final initial = ThemeController();
        await initial.setMode(mode);
        initial.dispose();
        final restored = ThemeController();
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.mode, mode);
        await tester.pumpWidget(_wrap(restored));
        await tester.pump();
        final frame = tester.widget<StartupAnimationFrame>(
          find.byType(StartupAnimationFrame),
        );
        expect(frame.progress, 0);
        expect(frame.palette, same(restored.effectivePalette));
        final background = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('startup-background')),
        );
        expect(
          (background.decoration as BoxDecoration).color,
          restored.effectivePalette.bg,
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(StartupAnimationFrame), findsNothing);
        expect(find.text('Home'), findsOneWidget);
      },
    );
  }

  for (final value in [null, 'removed-theme', 42]) {
    test(
      'missing, unknown or corrupt theme $value falls back safely',
      () async {
        final saved = <String, Object>{};
        if (value != null) saved['theme_mode'] = value;
        SharedPreferences.setMockInitialValues(saved);
        final theme = ThemeController();
        addTearDown(theme.dispose);
        await theme.load();
        expect(theme.mode, AppThemeMode.auto);
        final hour = DateTime.now().hour;
        expect(
          theme.effectiveStyle,
          hour >= 6 && hour < 19 ? AppThemeStyle.light : AppThemeStyle.dark,
        );
      },
    );
  }

  test('preference read error does not fail startup', () async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _UnavailablePreferences();
    final theme = ThemeController();
    addTearDown(theme.dispose);
    await theme.load();
    expect(theme.mode, AppThemeMode.auto);
  });

  testWidgets('preference channel that never replies has bounded fallback', (
    tester,
  ) async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _UnavailablePreferences(
      waitForever: true,
    );
    final theme = ThemeController();
    var completed = false;
    final loading = theme.load().then((_) => completed = true);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(completed, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await loading;
    expect(completed, isTrue);
    expect(theme.mode, AppThemeMode.auto);
    theme.dispose();
  });

  testWidgets(
    'prewarms home once, prevents hidden taps, then keeps home state',
    (tester) async {
      final theme = ThemeController()..mode = AppThemeMode.dark;
      addTearDown(theme.dispose);
      var inits = 0;
      var taps = 0;
      final home = _HomeProbe(onInit: () => inits++, onTap: () => taps++);
      await tester.pumpWidget(_wrap(theme, child: home));
      await tester.pump();
      expect(inits, 1);
      await tester.tap(find.text('Home'), warnIfMissed: false);
      expect(taps, 0);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.text('Home'));
      expect(taps, 1);
      expect(inits, 1);
      await theme.setMode(AppThemeMode.editorial);
      await tester.pumpAndSettle();
      expect(inits, 1);
      expect(find.byType(StartupAnimationFrame), findsNothing);
    },
  );

  testWidgets('theme changes mid-animation update color without replaying', (
    tester,
  ) async {
    final theme = ThemeController()..mode = AppThemeMode.light;
    addTearDown(theme.dispose);
    await tester.pumpWidget(_wrap(theme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    final before = tester
        .widget<StartupAnimationFrame>(find.byType(StartupAnimationFrame))
        .progress;
    await theme.setMode(AppThemeMode.editorial);
    await tester.pump();
    final after = tester.widget<StartupAnimationFrame>(
      find.byType(StartupAnimationFrame),
    );
    expect(after.palette, same(AppPalette.editorial));
    expect(after.progress, before);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(StartupAnimationFrame), findsNothing);
  });

  testWidgets('reduced motion skips animation and delay', (tester) async {
    final theme = ThemeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(_wrap(theme, reducedMotion: true));
    expect(find.byType(StartupAnimationFrame), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('turning on reduced motion during startup removes overlay', (
    tester,
  ) async {
    final theme = ThemeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(_wrap(theme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(_wrap(theme, reducedMotion: true));
    expect(find.byType(StartupAnimationFrame), findsNothing);
  });

  testWidgets('background and resume never restart stale animation', (
    tester,
  ) async {
    final theme = ThemeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(_wrap(theme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(StartupAnimationFrame), findsNothing);
  });

  testWidgets('muted animation ticker still releases home by watchdog', (
    tester,
  ) async {
    final theme = ThemeController()..mode = AppThemeMode.dark;
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: const MaterialApp(
          home: TickerMode(
            enabled: false,
            child: SplashGate(child: Scaffold(body: Text('Home'))),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2599));
    expect(find.byType(StartupAnimationFrame), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(StartupAnimationFrame), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('disabled startup and early disposal do not leave timers', (
    tester,
  ) async {
    final theme = ThemeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(_wrap(theme, enabled: false));
    expect(find.byType(StartupAnimationFrame), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrap(theme));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders all three palettes on narrow, wide and landscape screens',
    (tester) async {
      for (final size in [
        const Size(320, 568),
        const Size(430, 932),
        const Size(932, 430),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final palette in [
          AppPalette.light,
          AppPalette.dark,
          AppPalette.editorial,
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              home: StartupAnimationFrame(palette: palette, progress: 0.72),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  // Explicit opt-in renders actual Flutter frames, not a mockup or separate design.
  // flutter test --no-pub --dart-define=STARTUP_PREVIEWS=true test/startup_animation_test.dart
  if (const bool.fromEnvironment('STARTUP_PREVIEWS')) {
    testWidgets('export actual Flutter startup previews', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _loadFonts();
      for (final entry in {
        'light': AppPalette.light,
        'dark': AppPalette.dark,
        'editorial': AppPalette.editorial,
      }.entries) {
        final directory = Directory('build/startup-previews/${entry.key}')
          ..createSync(recursive: true);
        for (var frame = 0; frame < 60; frame++) {
          await tester.pumpWidget(
            MaterialApp(
              home: RepaintBoundary(
                key: const ValueKey('preview-boundary'),
                child: StartupAnimationFrame(
                  palette: entry.value,
                  progress: frame / 60,
                ),
              ),
            ),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('preview-boundary')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              '${directory.path}/frame-${frame.toString().padLeft(2, '0')}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }
}
