import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/services/badges.dart';
import 'package:runtrail/widgets/badges_card.dart';

BadgeDef def(String id) => badgeById(id)!;

/// 弹窗用固定时长推进：氛围层循环动画永不静止，不能用 pumpAndSettle。
Future<void> openDialog(
  WidgetTester tester, {
  required List<BadgeDef> badges,
}) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  showBadgeUnlockDialog(pageContext, badges);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('单枚勋章：动画播完定格在完成态，点按钮关闭', (tester) async {
    await openDialog(tester, badges: [def('first_run')]);
    expect(find.text('恭喜解锁新徽章'), findsOneWidget);
    expect(find.text('首跑完成'), findsOneWidget);
    expect(find.text('完成你的第一次跑步'), findsOneWidget);
    expect(find.text('收下勋章'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    // 入场播完定格：文案保持可见，无异常。
    expect(find.text('首跑完成'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('收下勋章'));
    // 先 pump 启动退场过渡，再推进时长完成移除。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('恭喜解锁新徽章'), findsNothing);
  });

  testWidgets('一次解锁多枚：首枚大勋章，其余进小列表', (tester) async {
    await openDialog(
      tester,
      badges: [def('single_10'), def('total_50'), def('streak_3')],
    );
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('十公里突破'), findsOneWidget);
    expect(find.text('累计 50 公里'), findsOneWidget);
    expect(find.text('三日连续'), findsOneWidget);
    // 描述只展示首枚主勋章的。
    expect(find.text('单次跑步达到 10 公里'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三套主题都能渲染（换肤不重建弹窗状态）', (tester) async {
    final controller = ThemeController();
    late BuildContext pageContext;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => controller,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    showBadgeUnlockDialog(pageContext, [def('first_run')]);
    await tester.pump(const Duration(milliseconds: 200));
    for (final mode in AppThemeMode.values) {
      await controller.setMode(mode);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });
}
