import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 肌群枚举（覆盖跑迹课程的 13 个动作）。
enum MuscleGroup {
  quads, // 股四头肌（大腿前侧）
  hamstrings, // 腘绳肌（大腿后侧）
  calves, // 小腿（腓肠肌）
  glutes, // 臀大肌
  hipFlexors, // 髋屈肌
  core, // 核心/腹部
  back, // 背部（背阔/竖脊）
  shoulders, // 三角肌（肩）
}

/// 肌群图示（借鉴 Keep 动作详情的"人体轮廓 + 发力高亮"图层方案，
/// 原生矢量自绘）：正面与背面两个剪影并排，主发力深红、辅助浅红。
class MuscleDiagram extends StatelessWidget {
  const MuscleDiagram({
    super.key,
    required this.primary,
    required this.secondary,
    this.height = 130,
  });

  final Set<MuscleGroup> primary;
  final Set<MuscleGroup> secondary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secColor = Color.lerp(c.danger, c.surface, 0.2)!;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: Size(height * 0.42, height),
            painter: _BodyPainter(
              back: false,
              primary: primary,
              secondary: secondary,
              body: c.surface2,
              primaryColor: c.danger,
              secondaryColor: secColor,
            ),
          ),
          const SizedBox(width: 10),
          CustomPaint(
            size: Size(height * 0.42, height),
            painter: _BodyPainter(
              back: true,
              primary: primary,
              secondary: secondary,
              body: c.surface2,
              primaryColor: c.danger,
              secondaryColor: secColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 示意人体：坐标盒 42x100（y 向下），x 以 21 为中线。
class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.back,
    required this.primary,
    required this.secondary,
    required this.body,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final bool back;
  final Set<MuscleGroup> primary;
  final Set<MuscleGroup> secondary;
  final Color body;
  final Color primaryColor;
  final Color secondaryColor;

  static const _mid = 21.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 100; // 缩放：纵向铺满。
    Offset p(double x, double y) => Offset(x * s, y * s);

    final bodyPaint = Paint()
      ..color = body
      ..style = PaintingStyle.fill;
    Paint muscle(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    Color? regionColor(MuscleGroup g) =>
        primary.contains(g) ? primaryColor
        : secondary.contains(g) ? secondaryColor
        : null;

    void capsule(Offset a, Offset b, double width, Paint paint) {
      canvas.drawLine(a, b, paint..strokeWidth = width * s..strokeCap = StrokeCap.round);
    }

    void oval(Offset center, double rx, double ry, Paint paint) {
      canvas.drawOval(Rect.fromCenter(center: center, width: rx * 2 * s, height: ry * 2 * s), paint);
    }

    // —— 剪影 ——
    // 头
    oval(p(_mid, 8), 7, 8, bodyPaint);
    capsule(p(_mid, 14), p(_mid, 20), 4, bodyPaint); // 颈
    // 躯干（肩到髋的胶囊）
    capsule(p(_mid, 24), p(_mid, 55), 20, bodyPaint);
    // 手臂
    capsule(p(_mid - 10, 26), p(_mid - 15, 56), 5.5, bodyPaint);
    capsule(p(_mid + 10, 26), p(_mid + 15, 56), 5.5, bodyPaint);
    // 腿（大腿+小腿）
    capsule(p(_mid - 5, 55), p(_mid - 6, 78), 8, bodyPaint);
    capsule(p(_mid + 5, 55), p(_mid + 6, 78), 8, bodyPaint);
    capsule(p(_mid - 6, 78), p(_mid - 7, 96), 6, bodyPaint);
    capsule(p(_mid + 6, 78), p(_mid + 7, 96), 6, bodyPaint);

    // —— 肌群高亮（按视图归属绘制）——
    final shoulderC = regionColor(MuscleGroup.shoulders);
    if (shoulderC != null) {
      final m = muscle(shoulderC);
      oval(p(_mid - 10, 27), 3.4, 3.4, m);
      oval(p(_mid + 10, 27), 3.4, 3.4, m);
    }

    if (!back) {
      final coreC = regionColor(MuscleGroup.core);
      if (coreC != null) {
        oval(p(_mid, 40), 6.5, 9.5, muscle(coreC));
      }
      final hipC = regionColor(MuscleGroup.hipFlexors);
      if (hipC != null) {
        final m = muscle(hipC);
        oval(p(_mid - 4.5, 53), 2.8, 3.6, m);
        oval(p(_mid + 4.5, 53), 2.8, 3.6, m);
      }
      final quadC = regionColor(MuscleGroup.quads);
      if (quadC != null) {
        final m = muscle(quadC);
        capsule(p(_mid - 5, 58), p(_mid - 5.8, 76), 5.4, m);
        capsule(p(_mid + 5, 58), p(_mid + 5.8, 76), 5.4, m);
      }
    } else {
      final backC = regionColor(MuscleGroup.back);
      if (backC != null) {
        oval(p(_mid, 35), 7.2, 9.5, muscle(backC));
      }
      final gluteC = regionColor(MuscleGroup.glutes);
      if (gluteC != null) {
        final m = muscle(gluteC);
        oval(p(_mid - 4.6, 55.5), 3.6, 3.8, m);
        oval(p(_mid + 4.6, 55.5), 3.6, 3.8, m);
      }
      final hamC = regionColor(MuscleGroup.hamstrings);
      if (hamC != null) {
        final m = muscle(hamC);
        capsule(p(_mid - 5, 59), p(_mid - 5.8, 76), 5.4, m);
        capsule(p(_mid + 5, 59), p(_mid + 5.8, 76), 5.4, m);
      }
      final calfC = regionColor(MuscleGroup.calves);
      if (calfC != null) {
        final m = muscle(calfC);
        capsule(p(_mid - 6, 80), p(_mid - 6.7, 93), 4.4, m);
        capsule(p(_mid + 6, 80), p(_mid + 6.7, 93), 4.4, m);
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.back != back ||
      old.primary != primary ||
      old.secondary != secondary ||
      old.primaryColor != primaryColor;
}
