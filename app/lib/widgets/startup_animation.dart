import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// 旧版两秒开场的矢量版本：图标 → 轨迹与跑者 → 品牌文字 → 回到主题底色。
/// 三种风格直接引用 AppPalette，不另存一套颜色或依赖带固定底色的视频。
/// [progress] 也可用于确定性截帧，确保预览和真正启动时使用完全相同的画面。
class StartupAnimationFrame extends StatelessWidget {
  const StartupAnimationFrame({
    super.key,
    required this.palette,
    required this.progress,
  });

  final AppPalette palette;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final frame = progress.clamp(0.0, 1.0) * 60;
    final fade = 1 - _segment(frame, 48, 59);
    final titleIn = Curves.easeOutCubic.transform(_segment(frame, 24, 42));
    final subtitleIn = Curves.easeOutCubic.transform(_segment(frame, 30, 45));
    final p = palette;
    return Semantics(
      label: '跑迹 RunTrail',
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: const ValueKey('startup-background'),
          decoration: BoxDecoration(color: p.bg, gradient: bgGradient(p)),
          child: ClipRect(
            child: FittedBox(
              // 保留完整构图；横屏、平板及不同长宽比不裁掉品牌文字。
              fit: BoxFit.contain,
              child: SizedBox(
                width: 1080,
                height: 1920,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _StartupPainter(palette: p, frame: frame),
                      ),
                    ),
                    Positioned(
                      top: 1080 + 90 * (1 - titleIn),
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: fade * titleIn,
                        child: Text(
                          '跑迹',
                          textAlign: TextAlign.center,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontFamily: 'Noto Sans SC',
                            fontSize: 132,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 12,
                            color: p.textPrimary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 1260,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: fade * subtitleIn,
                        child: Column(
                          children: [
                            Text(
                              'RunTrail',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontFamily: p.isEditorial
                                    ? 'Playfair Display'
                                    : p.isDark
                                    ? 'Barlow Condensed'
                                    : 'Inter',
                                fontSize: p.isLight ? 44 : 56,
                                fontWeight: p.isLight
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                fontStyle: p.isDark
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                letterSpacing: p.isEditorial ? 4 : 10,
                                // 荧光绿只做图形点缀，米纸上的文字保持墨色对比。
                                color: p.isEditorial ? p.textPrimary : p.accent,
                                height: 1.2,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 46),
                            Text(
                              '记录每一步'.tr,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontFamily: 'Noto Sans SC',
                                fontSize: 30,
                                fontWeight: FontWeight.w400,
                                color: p.textMuted,
                                letterSpacing: 6,
                                height: 1.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _segment(double frame, double start, double end) =>
    ((frame - start) / (end - start)).clamp(0.0, 1.0);

class _StartupPainter extends CustomPainter {
  const _StartupPainter({required this.palette, required this.frame});

  final AppPalette palette;
  final double frame;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final iconOut = _segment(frame, 8, 18);
    if (iconOut < 1) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = scaleAlpha(Colors.white, 1 - iconOut),
      );
      canvas.save();
      canvas.translate(540, 960);
      canvas.scale(1 - 0.45 * iconOut);
      canvas.translate(-96, -96);
      _paintLogo(canvas);
      canvas.restore();
      canvas.restore();
    }
    if (frame < 10 || frame >= 59) return;
    final fade = 1 - _segment(frame, 48, 59);
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = scaleAlpha(Colors.white, fade),
    );
    final path = Path()
      ..moveTo(-40, 1500)
      ..quadraticBezierTo(420, 1300, 620, 900)
      ..quadraticBezierTo(820, 500, 900, 260);
    final progress = _segment(frame, 12, 42);
    final metric = path.computeMetrics().first;
    final trail = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      trail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [p.accent2, p.accent],
        ).createShader(const Rect.fromLTWH(0, 260, 1080, 1240)),
    );
    if (progress >= 0.99) {
      canvas.drawCircle(const Offset(900, 260), 18, Paint()..color = p.accent);
    }
    final runnerIn = Curves.easeOutCubic.transform(_segment(frame, 14, 36));
    canvas.save();
    canvas.translate(-320 + 790 * runnerIn, 520 - 100 * runnerIn);
    _paintRunner(canvas, p.isEditorial ? p.textPrimary : p.accent);
    canvas.restore();
    canvas.restore();
  }

  void _paintLogo(Canvas canvas) {
    final p = palette;
    const rect = Rect.fromLTWH(0, 0, 192, 192);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(32)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p.isEditorial
              ? [p.textPrimary, p.textPrimary]
              : [p.accent, p.accent2],
        ).createShader(rect),
    );
    final ink = p.isEditorial ? p.accent : p.onAccent;
    final trail = Path()
      ..moveTo(74, 127)
      ..cubicTo(136, 116, 117, 105, 94, 94)
      ..cubicTo(70, 82, 96, 75, 116, 73);
    canvas.drawPath(
      trail,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(62, 129), 6, Paint()..color = ink);
    final pin = Path()
      ..moveTo(128, 77)
      ..cubicTo(128, 77, 118, 67, 121, 62)
      ..cubicTo(124, 53, 137, 56, 136, 64)
      ..cubicTo(136, 69, 128, 77, 128, 77);
    canvas.drawPath(pin, Paint()..color = ink);
    canvas.drawCircle(
      const Offset(128, 63),
      2.8,
      Paint()..color = p.isEditorial ? p.textPrimary : p.accent,
    );
  }

  void _paintRunner(Canvas canvas, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(120, 52), 26, Paint()..color = color);
    canvas.drawLine(const Offset(120, 86), const Offset(120, 158), paint);
    for (final joints in const [
      [Offset(120, 104), Offset(70, 128), Offset(62, 106)],
      [Offset(120, 104), Offset(168, 92), Offset(196, 74)],
      [Offset(120, 158), Offset(76, 196), Offset(58, 240)],
      [Offset(120, 158), Offset(164, 190), Offset(150, 238)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(joints[0].dx, joints[0].dy)
          ..lineTo(joints[1].dx, joints[1].dy)
          ..lineTo(joints[2].dx, joints[2].dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StartupPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.frame != frame;
}
