import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 全局滚动阻尼：快速减速 + 回弹。
/// 父级 AlwaysScrollable 保证内容不足一屏时也能拖动，回弹处处生效。
const ScrollPhysics dampedPhysics = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
  decelerationRate: ScrollDecelerationRate.fast,
);

/// Tab 页需在自己的 Scaffold / SafeArea 外调用：HomeShell 的 extendBody
/// 会把实际底栏高度（含外边距和设备安全区）写入这里的 padding.bottom。
/// 不再猜测一个固定高度；独立路由下则只避让系统安全区。
double tabScrollBottomPadding(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 24;

/// 页面背景容器：白天主题套纵向微渐变，其余主题纯色透明。
class Backdrop extends StatelessWidget {
  final Widget child;

  const Backdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gradient = bgGradient(c);
    if (gradient == null) return child;
    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
  }
}

/// 环形进度指标（白天首页 Hero 卡）：36px 圆环 + 数值/标签。
class RingMetric extends StatelessWidget {
  final double progress; // 0..1
  final String value;
  final String label;
  final Color ringColor;
  final Color trackColor;

  const RingMetric({
    super.key,
    required this.progress,
    required this.value,
    required this.label,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: 1,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: trackColor,
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: progress.isFinite ? progress.clamp(0, 1) : 0,
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  color: ringColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: scaleAlpha(Colors.white, 0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 卡片容器（白天白卡 + 柔和投影 / 夜间深色卡 / 编辑风发丝边框无阴影）。
/// [inverse] 为 true 时渲染为深色反转卡片（编辑风的墨底特性卡）。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool inverse;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.md,
    this.inverse = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    final color = inverse ? c.inverseSurface : c.surface;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        // 编辑风：普通卡片用发丝边框、无阴影；反转卡无边框。
        border: editorial && !inverse ? Border.all(color: c.stroke) : null,
        boxShadow: editorial
            ? null
            : [
                BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -8,
                ),
              ],
      ),
      child: child,
    );
  }
}

/// 「图标 + 标签」小行。
class IconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final double size;

  const IconLabel(
    this.icon,
    this.label, {
    super.key,
    this.color,
    this.size = 13,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: color ?? c.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: size - 1.5, color: c.textSecondary),
        ),
      ],
    );
  }
}

/// 居中的数据小卡（图标+标签在上，数值在下）。
/// 编辑风：透明底 + 细边框（浅描边小盒），无阴影。
class MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: editorial ? Colors.transparent : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: editorial ? Border.all(color: c.stroke) : null,
          boxShadow: editorial
              ? null
              : [
                  BoxShadow(
                    color: c.cardShadow,
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                    spreadRadius: -8,
                  ),
                ],
        ),
        child: Column(
          children: [
            IconLabel(icon, label, size: 12),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: editorial ? 'Playfair Display' : null,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor ?? c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 进度条：浅色底 + 主题渐变填充（编辑风为纯色荧光绿 + 发丝轨道）。
class GradientProgress extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color? trackColor;
  final Color? fillColor;

  const GradientProgress({
    super.key,
    required this.value,
    this.height = 8,
    this.trackColor,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: trackColor ?? (editorial ? c.stroke : c.surface2)),
            // 进度变化时平滑过渡；非有限值（如目标为 0 的除法结果）按 0 处理。
            TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: value.isFinite ? value.clamp(0, 1) : 0,
              ),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => FractionallySizedBox(
                widthFactor: v,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: editorial || fillColor != null
                        ? null
                        : accentGradient(c),
                    color: editorial ? c.accent : fillColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主按钮（主题渐变胶囊；编辑风为墨底奶油字实心胶囊）。
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  const PrimaryButton({super.key, required this.label, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    final enabled = onTap != null;
    final foreground = !enabled
        ? c.textMuted
        : (editorial ? c.onInverse : c.onAccent);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          // 渐变两端各加深：亮色端（原 accent/accent2）与白字对比不足
          // （浅色主题 accent2 端 1.76、暗色主题 accent 端 2.82）。
          gradient: editorial || !enabled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(c.accent, Colors.black, 0.25)!,
                    Color.lerp(c.accent, Colors.black, 0.40)!,
                  ],
                ),
          color: !enabled ? c.surface2 : (editorial ? c.inverseSurface : null),
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: editorial || !enabled
              ? null
              : [
                  BoxShadow(
                    color: c.glow,
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: foreground, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 次级按钮（编辑风：透明底 + 发丝边框）。
/// 文字用主文字色保证对比度（次级灰在浅色/编辑风下不足 4.5:1）。
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;

  const GhostButton(this.label, {super.key, this.onTap, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    final fg = onTap == null ? c.textMuted : (color ?? c.textPrimary);
    return Material(
      color: editorial ? Colors.transparent : c.surface,
      shape: editorial
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: c.stroke),
            )
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 17),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆形小按钮（返回/分享等；编辑风：透明底 + 发丝边框）。
class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const CircleBtn(this.icon, {super.key, this.onTap, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: editorial ? Colors.transparent : c.surface,
          shape: BoxShape.circle,
          border: editorial ? Border.all(color: c.stroke) : null,
        ),
        child: Icon(
          icon,
          size: size * 0.5,
          color: onTap == null ? c.textMuted : c.textPrimary,
        ),
      ),
    );
  }
}

/// 呼吸脉冲图标：等待类状态（GPS 搜索等）的动画反馈，
/// 借鉴 Keep 的 rt_home_gps_searching 交互（原生实现，不使用其素材）。
class PulsingIcon extends StatefulWidget {
  const PulsingIcon(this.icon, {super.key, this.size = 12, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  State<PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 1.25).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Icon(widget.icon, size: widget.size, color: widget.color),
      ),
    );
  }
}

/// 完成庆祝粒子（借鉴 Keep 完赛撒花交互，原生实现）：一次性从顶部两侧
/// 喷出彩色纸屑，2.4 秒后自然消失，不遮挡交互。
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    final random = math.Random(7);
    _pieces = List.generate(64, (_) => _ConfettiPiece(random));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAnimating && _controller.isCompleted) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_pieces, _controller.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPiece {
  _ConfettiPiece(math.Random random)
    : startX = random.nextDouble(),
      delay = random.nextDouble() * 0.3,
      speed = 0.5 + random.nextDouble() * 0.6,
      drift = (random.nextDouble() - 0.5) * 0.35,
      size = 4 + random.nextDouble() * 5,
      colorIndex = random.nextInt(5),
      rotation = random.nextDouble() * math.pi;

  final double startX;
  final double delay;
  final double speed;
  final double drift;
  final double size;
  final int colorIndex;
  final double rotation;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_ConfettiPiece> pieces;
  final double t;

  static const _colors = [
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFFFF9F45),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = (t - p.delay) / (1 - p.delay);
      if (local <= 0 || local >= 1) continue;
      // 抛物线下落：先上抛后落，整体淡出。
      final progress = Curves.easeOut.transform(local.clamp(0, 1));
      final fade = (1 - local).clamp(0.0, 1.0);
      final x = (p.startX + p.drift * progress) * size.width;
      final y =
          size.height * 0.15 * p.speed * (1 - progress) +
          size.height * 0.8 * progress * progress * p.speed;
      final paint = Paint()..color = scaleAlpha(_colors[p.colorIndex], fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + progress * 2);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
