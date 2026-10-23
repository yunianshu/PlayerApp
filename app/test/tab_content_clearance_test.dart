import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:runtrail/core/i18n.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/core/launcher_icon_controller.dart';
import 'package:runtrail/pages/home_page.dart';
import 'package:runtrail/pages/profile_page.dart';
import 'package:runtrail/widgets/common.dart';

Future<void> settleScroll(WidgetTester tester) async {
  // Home contains a deliberately looping decorative animation. Wait for the
  // scroll spring, not for all animation frames in the entire page to stop.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets('home and profile clear measured bar in all themes and insets', (
    tester,
  ) async {
    for (final mode in [
      AppThemeMode.light,
      AppThemeMode.dark,
      AppThemeMode.editorial,
    ]) {
      for (final profile in [false, true]) {
        if (Platform.environment.containsKey('TAB_PREVIEW_DIR')) {
          final loader = FontLoader('Noto Sans SC')
            ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
          await loader.load();
        }
        SharedPreferences.setMockInitialValues({});
        final theme = ThemeController()..mode = mode;
        final icons = LauncherIconController(theme);
        addTearDown(icons.dispose);
        addTearDown(theme.dispose);
        tester.view.reset();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        double inset = 48;
        double scale = 1;
        double keyboard = 0;
        Widget wrap() => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: icons),
            ChangeNotifierProvider.value(value: LocaleController.instance),
          ],
          child: MaterialApp(
            theme: buildTheme(theme.effectiveStyle),
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: EdgeInsets.only(bottom: inset),
                    viewPadding: EdgeInsets.only(bottom: inset),
                    viewInsets: EdgeInsets.only(bottom: keyboard),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    extendBody: true,
                    body: profile ? const ProfilePage() : const HomePage(),
                    bottomNavigationBar: SafeArea(
                      top: false,
                      child: Container(
                        key: const ValueKey('bar'),
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        height: 76 * scale,
                        color: Colors.black,
                        child: const Center(
                          child: Text(
                            '首页     课程     开跑     统计     我的',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(wrap());
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        final list = find.byType(ListView).first;
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        Future<void> verify() async {
          for (var i = 0; i < 6; i++) {
            scroll.jumpTo(scroll.maxScrollExtent);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await settleScroll(tester);
          }
          final padding = tester.widget<ListView>(list).padding! as EdgeInsets;
          expect(
            padding.bottom,
            closeTo(keyboard > 0 ? 24 : 76 * scale + 12 + inset + 24, .01),
          );
          final last = profile
              ? find.text('从文件恢复')
              : find.textContaining('还没有跑步记录');
          expect(last, findsOneWidget);
          expect(
            tester.getBottomLeft(last).dy,
            lessThan(tester.getTopLeft(find.byKey(const ValueKey('bar'))).dy),
          );
          expect(last.hitTestable(), findsOneWidget);
          await tester.drag(list, const Offset(0, -180));
          await settleScroll(tester);
          expect(
            tester.getBottomLeft(last).dy,
            lessThan(tester.getTopLeft(find.byKey(const ValueKey('bar'))).dy),
          );
          expect(scroll.isScrollingNotifier.value, isFalse);
          expect(tester.takeException(), isNull);
        }

        await verify();
        if (Platform.environment['TAB_PREVIEW_DIR'] case final String dir) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          final image = (await tester.runAsync(() => boundary.toImage()))!;
          final bytes = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png),
          );
          await tester.runAsync(() async {
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/${mode.name}-${profile ? 'profile' : 'home'}-bottom.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
          image.dispose();
        }
        // React to safe-area/rotation/text changes, not a one-time cached height.
        inset = 0;
        scale = 1.6;
        await tester.pumpWidget(wrap());
        await settleScroll(tester);
        await verify();
        keyboard = 240;
        await tester.pumpWidget(wrap());
        await settleScroll(tester);
        await verify();
        keyboard = 0;
        tester.view.physicalSize = const Size(844, 390);
        await tester.pumpWidget(wrap());
        await settleScroll(tester);
        await verify();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
  testWidgets(
    'standalone page padding is safe area plus breathing room, not tab guess',
    (tester) async {
      double? padding;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: Builder(
            builder: (context) {
              padding = tabScrollBottomPadding(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(padding, 58);
    },
  );
}
