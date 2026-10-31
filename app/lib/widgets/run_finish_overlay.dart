import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// 跑步结束过渡动画（长按结束后的全屏反馈）：
/// 底色浮现 → 徽章弹入 + 涟漪扩散 → 圆环描画一周 → 对勾落笔 → 文案浮现。
/// 纯 CustomPainter + 单一 AnimationController 实现，三套主题共用 AppPalette，
/// 不引入 Lottie/视频资源；播完定格在完成态，等待总结页 pushReplacement 接管。
class RunFinishOverlay extends StatefulWidget {
  const RunFinishOverlay({super.key});

  @override
  State<RunFinishOverlay> createState() => _RunFinishOverlayState();
}

class _RunFinishOverlayState extends State<RunFinishOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      // 拦截一切点击：结束流程进行中不允许再碰暂停/锁屏。
      child: GestureDetector(
        onTap: () {},
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _controller,
            curve: const Interval(0, 0.18, curve: Curves.easeOut),
          ),
          child: ColoredBox(
            color: scaleAlpha(c.bg, 0.95),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => CustomPaint(
                      painter: _FinishBadgePainter(c, _controller.value),
                      size: const Size(132, 132),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _fadeSlide(
                    0.52,
                    0.7,
                    Text(
                      '跑步结束'.tr,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _fadeSlide(
                    0.66,
                    0.84,
                    Text(
                      '正在生成运动记录…'.tr,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 区间淡入 + 轻微上移：标题与副标题依次浮现。
  Widget _fadeSlide(double start, double end, Widget child) {
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 徽章绘制：涟漪两道、主环一周、对勾一段，全部由 [t]（0..1）驱动。
class _FinishBadgePainter extends CustomPainter {
  _FinishBadgePainter(this.p, this.t);

  final AppPalette p;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.32;
    double seg(double start, double end) =>
        ((t - start) / (end - start)).clamp(0.0, 1.0);

    // 整组徽章轻微弹入，避免生硬出现。
    final popIn = Curves.easeOutBack.transform(seg(0.02, 0.22));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(popIn);
    canvas.translate(-center.dx, -center.dy);

    // 涟漪：两道先后从环外扩散并淡出（夜间主题的 glow 为透明色时自然不可见）。
    const ripples = [(0.1, 0.55), (0.3, 0.75)];
    for (final (start, end) in ripples) {
      final rp = seg(start, end);
      if (rp <= 0 || rp >= 1) continue;
      canvas.drawCircle(
        center,
        r * (1 + 0.9 * rp),
        Paint()..color = scaleAlpha(p.accent, 0.35 * (1 - rp)),
      );
    }

    // 主环：从顶部顺时针描画一周。
    final ringT = Curves.easeInOutCubic.transform(seg(0.08, 0.5));
    if (ringT > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi / 2,
        2 * math.pi * ringT,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = p.accent,
      );
    }

    // 对勾：环画完后落笔，收束在"完成"的视觉语义上。
    final checkT = Curves.easeOutCubic.transform(seg(0.5, 0.78));
    if (checkT > 0) {
      final check = Path()
        ..moveTo(center.dx - r * 0.44, center.dy + r * 0.04)
        ..lineTo(center.dx - r * 0.1, center.dy + r * 0.38)
        ..lineTo(center.dx + r * 0.52, center.dy - r * 0.32);
      final metric = check.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = p.accent,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FinishBadgePainter oldDelegate) =>
      oldDelegate.p != p || oldDelegate.t != t;
}
