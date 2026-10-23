// Local review capture only; fake key remains masked, no network requests.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/pages/ai_coach_settings_page.dart';
import 'package:runtrail/services/ai_coach_settings.dart';

class _Credentials implements AiCredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    value = data;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  testWidgets('capture actual settings in the three app palettes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      for (final name in ['Noto Sans SC', 'Roboto']) {
        await (FontLoader(name)..addFont(Future.value(data))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in {
      'light': AppPalette.light,
      'dark': AppPalette.dark,
      'editorial': AppPalette.editorial,
    }.entries) {
      // Standalone visual test lives outside the automatic test directory.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final store = AiCoachSettingsStore(credentials: _Credentials());
      await store.save(
        config: const AiCoachConfig(
          endpoint: 'https://api.minimax.cn/v1/chat/completions',
          model: 'MiniMax-M3.1-Flash',
          providerId: 'minimax',
          accessMode: 'tokenPlan',
        ),
        apiKey: 'fake-preview-key-not-a-real-credential',
        persistKey: true,
      );
      final p = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: p.isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: p.bg,
            fontFamily: 'Noto Sans SC',
          ),
          home: RepaintBoundary(
            key: const Key('capture'),
            child: AiCoachSettingsPage(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('/workspace/shared/ai-settings-preview');
        await dir.create(recursive: true);
        await File('${dir.path}/${entry.key}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
  });
}
