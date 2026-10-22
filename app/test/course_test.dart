import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/prefs.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/pages/course_page.dart';
import 'package:runtrail/services/courses.dart';
import 'package:runtrail/widgets/exercise_video.dart';

Widget wrap(Widget child) => ChangeNotifierProvider(
  create: (_) => ThemeController(),
  child: MaterialApp(home: child),
);

/// 2 步 × 1 秒的迷你课程，供 widget 测试快速推进。
const _miniCourse = AssistCourse(
  title: '测试课程',
  steps: [
    CourseStep(
      name: '动作一',
      tip: '要点一',
      seconds: 1,
      icon: Icons.timer,
      anim: ExerciseAnim.jogInPlace,
    ),
    CourseStep(
      name: '动作二',
      tip: '要点二',
      seconds: 1,
      icon: Icons.timer,
      anim: ExerciseAnim.breathing,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Prefs.instance.voiceEnabled = false;
  });

  group('课程数据', () {
    test('热身课程：6 个动作，总时长合理', () {
      expect(warmupCourse.steps, hasLength(6));
      expect(
        warmupCourse.steps.every((s) => s.seconds > 0 && s.tip.isNotEmpty),
        isTrue,
      );
      // 200 秒左右（3 分钟档），既有效又不拖沓。
      expect(warmupCourse.total.inMinutes, greaterThanOrEqualTo(3));
      expect(warmupCourse.total.inMinutes, lessThan(5));
    });

    test('每个动作都标注了主发力肌群', () {
      final all = [...warmupCourse.steps, ...stretchCourse.steps];
      expect(all, isNotEmpty);
      expect(
        all.every((s) => s.primaryMuscles.isNotEmpty),
        isTrue,
        reason: '肌群图示依赖主发力标注',
      );
    });

    test('拉伸课程：7 个动作，总时长合理', () {
      expect(stretchCourse.steps, hasLength(7));
      expect(
        stretchCourse.steps.every((s) => s.seconds > 0 && s.tip.isNotEmpty),
        isTrue,
      );
      expect(stretchCourse.total.inMinutes, greaterThanOrEqualTo(5));
      expect(stretchCourse.total.inMinutes, lessThan(8));
    });
  });

  group('课程播放页', () {
    testWidgets('逐步推进并完成课程', (tester) async {
      await tester.pumpWidget(
        wrap(CoursePage(course: _miniCourse, finishedTitle: '测试完成！')),
      );
      // 首节展示动作名与剩余秒数。
      expect(find.text('动作一'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      // 1 秒后进入第二节。
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('动作二'), findsOneWidget);

      // 再 1 秒后完成，出现完成标题与按钮。
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('测试完成！'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });

    testWidgets('点完成返回 true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => CoursePage(
                      course: _miniCourse,
                      finishedTitle: '测试完成！',
                    ),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      // 快进两步完成课程。
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('暂停时不推进', (tester) async {
      await tester.pumpWidget(
        wrap(CoursePage(course: _miniCourse, finishedTitle: '测试完成！')),
      );
      // 点击中间的暂停按钮（播放/暂停是唯一 FilledButton 风格 IconButton）。
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('已暂停'), findsOneWidget);
      // 仍在第一节。
      expect(find.text('动作一'), findsOneWidget);
    });

    testWidgets('跳到下一节', (tester) async {
      await tester.pumpWidget(
        wrap(CoursePage(course: _miniCourse, finishedTitle: '测试完成！')),
      );
      await tester.tap(find.byIcon(Icons.skip_next));
      await tester.pump();
      expect(find.text('动作二'), findsOneWidget);
    });

    testWidgets('暂停/继续有语音播报文案', (tester) async {
      await tester.pumpWidget(
        wrap(CoursePage(course: _miniCourse, finishedTitle: '测试完成！')),
      );
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(find.text('已暂停'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(find.text('已暂停'), findsNothing);
    });
  });

  group('课程整点播报决策 courseAnnouncement', () {
    test('双侧动作半程提示换边', () {
      expect(
        courseAnnouncement(remaining: 30, seconds: 60, twoSided: true),
        '换边',
      );
    });

    test('长单侧动作半程提示时间过半', () {
      expect(
        courseAnnouncement(remaining: 20, seconds: 40, twoSided: false),
        isNull,
      );
      expect(
        courseAnnouncement(remaining: 22, seconds: 45, twoSided: false),
        '时间过半',
      );
    });

    test('倒计时 10 秒与 5 秒', () {
      expect(
        courseAnnouncement(remaining: 10, seconds: 30, twoSided: false),
        '还剩10秒',
      );
      expect(
        courseAnnouncement(remaining: 5, seconds: 30, twoSided: false),
        '还剩5秒',
      );
      // 半程与倒计时撞点时只播换边，不叠加倒计时。
      expect(
        courseAnnouncement(remaining: 10, seconds: 20, twoSided: true),
        '换边',
      );
      // 短动作不播倒计时。
      expect(
        courseAnnouncement(remaining: 10, seconds: 10, twoSided: false),
        isNull,
      );
    });

    test('拉伸课程单侧动作已标记 twoSided', () {
      final sided = stretchCourse.steps.where((s) => s.twoSided).map((s) => s.name);
      expect(sided, containsAll(<String>['大腿前侧拉伸', '小腿拉伸', '髋屈肌拉伸']));
      expect(sided, isNot(contains('深呼吸放松')));
    });
  });
}
