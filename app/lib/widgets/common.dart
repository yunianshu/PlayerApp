import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 全局滚动阻尼：快速减速 + 回弹。
/// 父级 AlwaysScrollable 保证内容不足一屏时也能拖动，回弹处处生效。
const ScrollPhysics dampedPhysics = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
  decelerationRate: ScrollDecelerationRate.fast,
);

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
                builder: (_, v, __) => CircularProgressIndicator(
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
              style: TextStyle(fontSize: 9, color: scaleAlpha(Colors.white, 0.8)),
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
    this.radius = 22,
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
          borderRadius: BorderRadius.circular(18),
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
              tween: Tween(begin: 0, end: value.isFinite ? value.clamp(0, 1) : 0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => FractionallySizedBox(
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
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: editorial ? null : accentGradient(c),
          color: editorial ? c.inverseSurface : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: editorial
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
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: c.onAccent, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.onAccent,
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
    final fg = color ?? c.textSecondary;
    return Material(
      color: editorial ? Colors.transparent : c.surface,
      shape: editorial
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: c.stroke),
            )
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 17),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
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
        child: Icon(icon, size: size * 0.5, color: c.textPrimary),
      ),
    );
  }
}
