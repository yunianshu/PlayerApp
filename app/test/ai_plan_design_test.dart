import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/widgets/ai_plan_design.dart';

void main() {
  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.editorial,
  ]) {
    testWidgets('plan design follows $mode at narrow large text size', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ThemeController()..mode = mode;
      addTearDown(controller.dispose);
      late ThemeData scoped;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: buildTheme(controller.effectiveStyle),
            home: Builder(
              builder: (context) {
                scoped = PlanDesign.theme(context);
                return Theme(
                  data: scoped,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true,
                    ),
                    child: Scaffold(
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const PlanHero(
                              eyebrow: 'RACE / 训练计划',
                              title: '为下一场马拉松而跑',
                              subtitle: '从当前的训练基础开始，循序渐进地准备目标比赛。',
                              children: [
                                PlanMetric(
                                  label: '目标日期',
                                  value: '2027.02.12',
                                  icon: Icons.flag_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const PlanSection(
                              eyebrow: '01 / 你的目标',
                              title: '选择比赛',
                              subtitle: '计划会保留已经完成的训练',
                              child: Column(
                                children: [
                                  TextField(
                                    decoration: InputDecoration(
                                      labelText: '比赛名称',
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  PlanNotice(
                                    messages: ['AI 计划仅供训练参考，请根据恢复情况调整。'],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final palette = controller.effectivePalette;
      expect(scoped.colorScheme.onSurface, palette.textPrimary);
      expect(scoped.colorScheme.surfaceContainerHighest, palette.surface2);
      expect(scoped.colorScheme.tertiaryContainer, palette.accentSoft);
      expect(
        scoped.colorScheme.primary,
        palette.isEditorial ? palette.textPrimary : palette.accent,
      );
      // 对话框主题因鸿蒙 3.22 与 3.47 类名冲突暂未注入 ThemeData（见
      // ai_plan_design.dart 注释），这里不再断言 dialogTheme。
      expect(
        scoped.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve({}),
        palette.surface,
      );
      for (final widget in tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      )) {
        expect(widget.duration, Duration.zero);
      }
    });
  }
  testWidgets('scoped theme is safe from an event callback', (tester) async {
    final controller = ThemeController()..mode = AppThemeMode.editorial;
    addTearDown(controller.dispose);
    ThemeData? fromEvent;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  fromEvent = PlanDesign.theme(context);
                },
                child: const Text('打开日历'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开日历'));
    expect(tester.takeException(), isNull);
    expect(fromEvent!.colorScheme.surface, AppPalette.editorial.surface);
  });
  testWidgets('theme works without controller provider', (tester) async {
    late AppPalette palette;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppThemeStyle.editorial),
        home: Builder(
          builder: (context) {
            palette = PlanDesign.of(context).palette;
            return Theme(
              data: PlanDesign.theme(context),
              child: const Scaffold(),
            );
          },
        ),
      ),
    );
    expect(palette, AppPalette.editorial);
    expect(tester.takeException(), isNull);
  });
}
