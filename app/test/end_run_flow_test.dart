
// 长按结束流程：总结页 alreadySaved 直接呈现已保存态（结束即保存，无二次确认）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/prefs.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/pages/course_page.dart';
import 'package:runtrail/pages/summary_page.dart';

RunRecord _run() => RunRecord(
  start: DateTime(2026, 10, 1, 7),
  end: DateTime(2026, 10, 1, 7, 30),
  distanceM: 5000,
  durationS: 1800,
  calories: 280,
);

Widget wrap(Widget child) => ChangeNotifierProvider(
  create: (_) => ThemeController(),
  child: MaterialApp(home: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 关闭语音：避免总结页完成播报触发 TTS 初始化超时定时器挂起测试。
    Prefs.instance.voiceEnabled = false;
  });

  testWidgets('alreadySaved=true 显示已保存且无保存按钮交互', (tester) async {
    await tester.pumpWidget(
      wrap(SummaryPage.fromTracker(_run(), const [], alreadySaved: true)),
    );
    await tester.pump();
    expect(find.text('已保存 ✓'), findsOneWidget);
    expect(find.text('保存记录'), findsNothing);
  });

  testWidgets('默认（手动流程）仍显示保存记录按钮', (tester) async {
    await tester.pumpWidget(wrap(SummaryPage.fromTracker(_run(), const [])));
    await tester.pump();
    expect(find.text('保存记录'), findsOneWidget);
  });

  testWidgets('跑完（≥1公里）主动弹拉伸询问，可进入拉伸课程', (tester) async {
    await tester.pumpWidget(
      wrap(SummaryPage.fromTracker(_run(), const [], alreadySaved: true)),
    );
    await tester.pump();
    expect(find.text('跑后拉伸？'), findsOneWidget);
    await tester.tap(find.text('开始拉伸'));
    // 课程页有循环播放的视频，不能用 pumpAndSettle，用显式 pump。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 进入拉伸课程播放页（课程标题在 AppBar）。
    expect(find.text('跑后拉伸'), findsWidgets);
    expect(find.byType(CoursePage), findsOneWidget);
  });

  testWidgets('短于 1 公里不弹拉伸询问', (tester) async {
    final short = RunRecord(
      start: DateTime(2026, 10, 1, 7),
      end: DateTime(2026, 10, 1, 7, 5),
      distanceM: 400,
      durationS: 300,
      calories: 30,
    );
    await tester.pumpWidget(
      wrap(SummaryPage.fromTracker(short, const [], alreadySaved: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('跑后拉伸？'), findsNothing);
  });
}

// 暂停/继续立即播报（flush），不再排队导致"听不到"。
// 放在同一文件：共用 SummaryPage/主题包装与 Prefs 环境。
