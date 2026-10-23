// Design-only prototype. Not imported by the app; no network, persistence or AI.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/core/theme.dart';

class CoachConcept extends StatelessWidget {
  const CoachConcept({super.key, required this.p, required this.screen});
  final AppPalette p;
  final int screen;
  Color get ink => p.textPrimary;
  Color get mark => p.isEditorial ? p.textPrimary : p.accent;
  TextStyle style(double size, {bool bold = false, Color? color}) => TextStyle(
    fontFamily: 'Noto Sans SC',
    fontSize: size,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: color ?? ink,
    height: 1.45,
  );
  Widget text(String v, double size, {bool bold = false, Color? color}) => Text(
    v,
    style: style(size, bold: bold, color: color),
  );
  Widget gap([double h = 16]) => SizedBox(height: h);
  Widget line() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Divider(height: 1, color: p.stroke),
  );
  Widget pill(String s, {bool selected = false, IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: selected ? (p.isEditorial ? p.accent : p.accentSoft) : p.surface2,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: selected
            ? (p.isEditorial ? p.accent : p.accentStroke)
            : p.stroke,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: mark),
          const SizedBox(width: 6),
        ],
        text(s, 12, bold: selected, color: selected ? mark : p.textSecondary),
      ],
    ),
  );
  Widget header(String title) => Row(
    children: [
      Icon(Icons.arrow_back_rounded, color: ink, size: 21),
      const SizedBox(width: 16),
      Expanded(child: text(title, 16, bold: true)),
      text('概念稿·示例', 11, color: p.textMuted),
    ],
  );
  Widget label(String left, String right) => Row(
    children: [
      Expanded(child: text(left, 14, bold: true)),
      text(right, 11, color: p.textSecondary),
    ],
  );
  Widget note(String s) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: p.surface2,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: p.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: text(s, 11, color: p.textSecondary)),
      ],
    ),
  );
  Widget metric(String value, String suffix) => RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: p.isEditorial ? 'Playfair Display' : 'Barlow Condensed',
            fontSize: 60,
            fontWeight: FontWeight.w700,
            color: ink,
            height: 1.05,
          ),
        ),
        TextSpan(
          text: '  $suffix',
          style: style(14, color: p.textSecondary),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Noto Sans SC',
      scaffoldBackgroundColor: p.bg,
    ),
    home: RepaintBoundary(
      key: const Key('capture'),
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: SingleChildScrollView(
              child: screen == 0
                  ? ability()
                  : screen == 1
                  ? review()
                  : adjust(),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            decoration: BoxDecoration(
              color: p.bg,
              border: Border(top: BorderSide(color: p.stroke)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: p.isEditorial ? ink : p.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: text(
                      screen == 0
                          ? '下一步：安排训练日'
                          : screen == 1
                          ? '确认采用计划'
                          : '确认这 2 项调整',
                      15,
                      bold: true,
                      color: p.isEditorial
                          ? p.bg
                          : p.isDark
                          ? const Color(0xff101014)
                          : Colors.white,
                    ),
                  ),
                ),
                gap(9),
                text(
                  screen == 0
                      ? '发送给 AI 前，会先说明服务和数据范围'
                      : screen == 1
                      ? '示例数据 · 未调用 AI · 不会保存'
                      : '保留原计划，暂不调整',
                  11,
                  color: p.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget ability() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      header('创建训练计划'),
      gap(26),
      Row(
        children: [
          pill('1  目标赛事', icon: Icons.check_rounded),
          const Spacer(),
          pill('2  当前能力', selected: true),
          const Spacer(),
          text('3  训练节奏', 11, color: p.textMuted),
        ],
      ),
      gap(28),
      text('先从你现在的\n跑步基础出发。', 28, bold: true),
      gap(8),
      text('填最近 4 周的真实情况，而不是理想状态。', 12, color: p.textSecondary),
      gap(24),
      Row(
        children: [
          Icon(Icons.flag_outlined, size: 17, color: mark),
          const SizedBox(width: 8),
          text('杭州马拉松', 13, bold: true),
          const Spacer(),
          text('2027.02.14', 12, color: p.textSecondary),
        ],
      ),
      line(),
      label('平均每周跑多少？', '最近 4 周'),
      gap(12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: metric('32', '公里 / 周')),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: p.stroke),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.edit_outlined, size: 18, color: mark),
          ),
        ],
      ),
      gap(16),
      SizedBox(
        height: 22,
        child: CustomPaint(
          size: const Size(double.infinity, 22),
          painter: RulerPainter(p),
        ),
      ),
      gap(7),
      text('可直接输入数字；没有记录也可以手动填写。', 11, color: p.textMuted),
      line(),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text('最长单次跑距', 12, color: p.textSecondary),
                gap(7),
                text('16.0  km', 24, bold: true),
              ],
            ),
          ),
          Container(width: 1, height: 58, color: p.stroke),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text('近期 10 公里成绩', 12, color: p.textSecondary),
                gap(7),
                text('58 分 30 秒', 23, bold: true),
              ],
            ),
          ),
        ],
      ),
      gap(6),
      text('近 4 周内完成的最长一次跑步', 11, color: p.textMuted),
      line(),
      label('最近恢复得怎么样？', '按真实体感选择'),
      gap(12),
      Row(
        children: [
          pill('恢复良好', selected: true),
          const SizedBox(width: 8),
          pill('有些疲劳'),
          const SizedBox(width: 8),
          pill('疼痛 / 不适'),
        ],
      ),
      gap(16),
      note('目标不会被当成能力。出现疼痛时，不会自动生成跑步负荷计划。'),
      gap(16),
    ],
  );
  Widget review() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      header('计划预览'),
      gap(22),
      Row(
        children: [
          Expanded(child: text('杭州马拉松', 27, bold: true)),
          pill('模拟 AI', selected: true),
        ],
      ),
      gap(5),
      text('2027.02.14  ·  16 周备赛  ·  每周 4 次', 12, color: p.textSecondary),
      gap(18),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text('你设定的目标', 11, color: p.textSecondary),
                gap(3),
                text('5 小时 00 分', 29, bold: true),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              text('首周跑量', 11, color: p.textSecondary),
              gap(3),
              text('28 km', 27, bold: true),
            ],
          ),
        ],
      ),
      line(),
      label('先建立节奏，再逐步推进', '阶段划分仅作视觉示意'),
      gap(13),
      Row(
        children: [
          Expanded(flex: 4, child: phase('基础', p.accentSoft)),
          const SizedBox(width: 3),
          Expanded(
            flex: 9,
            child: phase('循序发展', p.isEditorial ? p.accent : p.accent),
          ),
          const SizedBox(width: 3),
          Expanded(flex: 3, child: phase('减量', p.surface2)),
        ],
      ),
      gap(20),
      label('每周跑量', '峰值 44 km · 不含比赛距离'),
      gap(10),
      SizedBox(
        height: 145,
        child: CustomPaint(
          size: const Size(double.infinity, 145),
          painter: LoadPainter(p),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          text('第 1 周', 10, color: p.textMuted),
          text('第 8 周', 10, color: p.textMuted),
          text('比赛周', 10, color: p.textMuted),
        ],
      ),
      line(),
      label('第一周 · 找回稳定节奏', '10.26 — 11.01'),
      gap(14),
      Row(
        children: List.generate(
          7,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 6 ? 0 : 5),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: [1, 3, 5, 6].contains(i) ? p.surface : p.surface2,
                  border: Border.all(color: i == 6 ? mark : p.stroke),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    text(
                      ['一', '二', '三', '四', '五', '六', '日'][i],
                      10,
                      color: p.textSecondary,
                    ),
                    gap(8),
                    text(
                      ['休', '6', '休', '6', '休', '4', '12'][i],
                      18,
                      bold: true,
                    ),
                    gap(3),
                    text(
                      ['恢复', '轻松', '恢复', '轻松', '恢复', '轻松', '长跑'][i],
                      9,
                      color: p.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      gap(13),
      Row(
        children: [
          Icon(Icons.calendar_month_outlined, color: mark, size: 16),
          const SizedBox(width: 7),
          text('查看完整日程', 12, bold: true, color: mark),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: mark, size: 18),
        ],
      ),
      gap(18),
      note('示意跑量不是训练建议。正式计划需根据基础、恢复与比赛日期校验，不保证完赛或目标成绩。'),
      gap(16),
    ],
  );
  Widget phase(String s, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    color: color,
    child: Center(
      child: text(
        s,
        10,
        bold: true,
        color: color == p.accent && !p.isEditorial
            ? (p.isDark ? const Color(0xff101014) : Colors.white)
            : ink,
      ),
    ),
  );
  Widget adjust() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      header('调整预览'),
      gap(24),
      pill('根据本周进度 · 模拟建议', selected: true),
      gap(14),
      text('下周，先稳住节奏。', 27, bold: true),
      gap(8),
      text(
        '示例反馈：完成跑量偏少，疲劳偏高。\n建议缩短两次训练，不把遗漏跑量补回来。',
        12,
        color: p.textSecondary,
      ),
      gap(24),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: p.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  text('下周跑量', 11, color: p.textSecondary),
                  gap(5),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '36',
                          style: style(25, color: p.textMuted),
                        ),
                        TextSpan(
                          text: ' → ',
                          style: style(20, color: p.textMuted),
                        ),
                        TextSpan(text: '28', style: style(34, bold: true)),
                        TextSpan(
                          text: ' km',
                          style: style(13, color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                text('-8 km', 24, bold: true, color: mark),
                text('2 个训练日变化', 11, color: p.textSecondary),
              ],
            ),
          ],
        ),
      ),
      gap(24),
      label('具体改了什么', '只列有变化的日期'),
      gap(12),
      change('周四 · 11.05', '轻松跑', '8 km', '6 km', '缩短距离，维持轻松强度'),
      gap(12),
      change('周日 · 11.08', '长距离', '18 km', '12 km', '保留长跑节奏，减少单次负荷'),
      gap(22),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.spa_outlined, size: 20, color: mark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text('恢复日继续保留', 14, bold: true),
                gap(4),
                text(
                  '长跑后保留休息日，不加练、不补跑。\n调整不代表已完成伤病或医学评估。',
                  12,
                  color: p.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
      line(),
      label('这些不会改变', ''),
      gap(11),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          pill('已完成记录', icon: Icons.check_rounded),
          pill('比赛日期', icon: Icons.check_rounded),
          pill('过去的训练', icon: Icons.check_rounded),
        ],
      ),
      gap(20),
      note('设计示例，未调用 AI。正式使用时，确认后才应用；数据已变化的方案需要重新生成。'),
      gap(16),
    ],
  );
  Widget change(
    String date,
    String name,
    String from,
    String to,
    String reason,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: p.surface2,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: text(date, 12, color: p.textSecondary)),
            text(name, 12, bold: true),
          ],
        ),
        gap(9),
        Row(
          children: [
            text(from, 21, color: p.textMuted),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Icon(Icons.arrow_right_alt_rounded, color: p.textMuted),
            ),
            text(to, 27, bold: true, color: mark),
          ],
        ),
        gap(6),
        text(reason, 12, color: p.textSecondary),
      ],
    ),
  );
}

class RulerPainter extends CustomPainter {
  RulerPainter(this.p);
  final AppPalette p;
  @override
  void paint(Canvas c, Size s) {
    for (var i = 0; i < 31; i++) {
      final x = i * s.width / 30;
      c.drawLine(
        Offset(x, 0),
        Offset(x, i % 5 == 0 ? 18 : 8),
        Paint()
          ..color = p.stroke
          ..strokeWidth = 1,
      );
    }
    c.drawLine(
      Offset(s.width * .55, 0),
      Offset(s.width * .55, 22),
      Paint()
        ..color = p.isEditorial ? p.textPrimary : p.accent
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class LoadPainter extends CustomPainter {
  LoadPainter(this.p);
  final AppPalette p;
  final values = [
    28,
    30,
    32,
    26,
    34,
    36,
    38,
    30,
    40,
    42,
    44,
    34,
    40,
    30,
    22,
    12,
  ];
  @override
  void paint(Canvas c, Size s) {
    final h = s.height - 12;
    for (var i = 1; i <= 3; i++) {
      final y = h * i / 3;
      c.drawLine(
        Offset(0, y),
        Offset(s.width, y),
        Paint()
          ..color = p.stroke
          ..strokeWidth = 1,
      );
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = 8 + i * (s.width - 16) / 15, y = h - values[i] / 48 * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      final color = p.isEditorial ? p.textPrimary : p.accent;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 5, y, 10, h - y),
          const Radius.circular(3),
        ),
        Paint()
          ..color = color.withValues(
            alpha: i < 4
                ? .22
                : i > 12
                ? .3
                : .75,
          ),
      );
    }
    c.drawPath(
      path,
      Paint()
        ..color = p.isEditorial ? p.textPrimary : p.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

void main() {
  testWidgets('render isolated design concepts only', (tester) async {
    await tester.runAsync(() async {
      final f = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      for (final n in ['Noto Sans SC', 'Roboto', 'Inter']) {
        await (FontLoader(n)..addFont(Future.value(f))).load();
      }
      await (FontLoader('Barlow Condensed')
            ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf')))
          .load();
      await (FontLoader('Playfair Display')
            ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Bold.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final e in {
      'light': AppPalette.light,
      'dark': AppPalette.dark,
      'editorial': AppPalette.editorial,
    }.entries) {
      tester.view.physicalSize = const Size(430, 1000);
      for (var screen = 0; screen < 3; screen++) {
        await tester.pumpWidget(CoachConcept(p: e.value, screen: screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final b = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final im = await b.toImage(pixelRatio: 2);
          final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('/workspace/shared/coach-concept');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/${e.key}-${['ability', 'review', 'adjust'][screen]}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          im.dispose();
        });
      }
      tester.view.physicalSize = const Size(1290, 1000);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: const Key('overview'),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: CoachConcept(p: e.value, screen: i),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final overview = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('overview')),
      );
      await tester.runAsync(() async {
        final im = await overview.toImage(pixelRatio: 1.5);
        final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        await File('/workspace/shared/coach-concept/${e.key}-overview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        im.dispose();
      });
    }
  });
}
