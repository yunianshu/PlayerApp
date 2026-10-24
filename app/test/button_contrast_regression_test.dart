import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/widgets/ai_plan_design.dart';
import 'package:runtrail/widgets/common.dart';

// Unlike a list of theoretical palette pairs, inspect the actual rendered
// controls: this catches an explicit TextStyle overriding the button theme.
double ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

Color renderedText(WidgetTester tester, String label) {
  final rich = tester.widget<RichText>(
    find.descendant(of: find.text(label), matching: find.byType(RichText)),
  );
  return (rich.text as TextSpan).style!.color!;
}

void main() {
  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.editorial,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('real button gallery $mode at 320px scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = ThemeController()..mode = mode;
        addTearDown(controller.dispose);
        final p = controller.effectivePalette;
        final output = Platform.environment['BUTTON_PREVIEW_DIR'];
        if (output != null) {
          for (final family in ['Ahem', 'Roboto', 'Noto Sans SC']) {
            await (FontLoader(family)..addFont(
                  rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'),
                ))
                .load();
          }
        }
        final key = GlobalKey();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: controller,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: buildTheme(controller.effectiveStyle),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Scaffold(
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PrimaryButton(
                              label: '保存并分享训练成果',
                              icon: Icons.save,
                              onTap: () {},
                            ),
                            const SizedBox(height: 8),
                            const PrimaryButton(
                              label: '保存中，暂不可操作',
                              icon: Icons.hourglass_top,
                            ),
                            GhostButton(
                              '分享完整训练安排',
                              icon: Icons.share,
                              onTap: () {},
                            ),
                            FilledButton(
                              onPressed: () {},
                              child: const Text(
                                '全局主按钮',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const FilledButton(
                              onPressed: null,
                              child: Text('禁用主按钮'),
                            ),
                            FilledButton.tonal(
                              onPressed: () {},
                              child: const Text('柔色按钮'),
                            ),
                            ElevatedButton(
                              onPressed: () {},
                              child: const Text('浮起按钮'),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('边框按钮'),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: Text(
                                '纸面强调操作',
                                style: TextStyle(color: p.actionForeground),
                              ),
                            ),
                            TextButton(
                              onPressed: () {},
                              child: Text(
                                '删除记录',
                                style: TextStyle(color: p.danger),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.refresh),
                                ),
                                const IconButton(
                                  onPressed: null,
                                  icon: Icon(Icons.refresh),
                                ),
                              ],
                            ),
                            Theme(
                              data: PlanDesign.theme(context),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () {},
                                    icon: const Icon(Icons.check),
                                    label: const Text(
                                      '确认 AI 训练计划',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: null,
                                    icon: Icon(Icons.hourglass_top),
                                    label: Text('正在保存计划'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () {},
                                    child: const Text('测试连接'),
                                  ),
                                  FilterChip(
                                    label: const Text('已选训练日'),
                                    selected: true,
                                    onSelected: (_) {},
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final primaryFg = renderedText(tester, '保存并分享训练成果');
        if (p.isEditorial) {
          expect(primaryFg, p.onInverse);
          expect(ratio(primaryFg, p.inverseSurface), greaterThanOrEqualTo(4.5));
        } else {
          for (final darken in [.25, .4]) {
            expect(
              ratio(primaryFg, Color.lerp(p.accent, Colors.black, darken)!),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        final primaryIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(PrimaryButton).first,
            matching: find.byType(Icon),
          ),
        );
        expect(primaryIcon.color, primaryFg);
        final scheme = buildTheme(controller.effectiveStyle).colorScheme;
        expect(
          ratio(renderedText(tester, '全局主按钮'), scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ratio(renderedText(tester, '纸面强调操作'), p.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ratio(renderedText(tester, '删除记录'), p.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ratio(renderedText(tester, '确认 AI 训练计划'), scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(renderedText(tester, '保存中，暂不可操作'), p.textMuted);
        if (output != null) {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final screenshot = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await screenshot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory(output).createSync(recursive: true);
              File('$output/buttons-${mode.name}-$scale.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
            } finally {
              screenshot.dispose();
            }
          });
        }
      });
    }
  }
}
