import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/badges.dart';
import '../widgets/common.dart';

/// 我的页只显示徽章入口与进度，点击后在弹层中查看完整列表。
class BadgesCard extends StatelessWidget {
  final Set<String> unlocked;

  const BadgesCard({super.key, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showAllBadges(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 22,
                  color: c.actionForeground,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '成就徽章'.tr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${unlocked.length}/${badgeDefs.length}',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAllBadges(BuildContext context) {
    final c = context.readColors;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: c.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '成就徽章'.tr,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${unlocked.length}/${badgeDefs.length}',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    IconButton(
                      tooltip: '关闭'.tr,
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, size: 20, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  physics: dampedPhysics,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.76,
                  children: [
                    for (final def in badgeDefs)
                      _badgeCell(c, def, unlocked.contains(def.id)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badgeCell(AppPalette c, BadgeDef def, bool ok) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: ok ? c.accentSoft : c.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: ok ? c.accentStroke : c.stroke),
          ),
          child: Icon(
            _iconOf(def.icon),
            size: 20,
            color: ok ? c.accent : c.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          child: Tooltip(
            message: badgeDesc(def),
            child: Text(
              badgeName(def),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: ok ? c.textPrimary : c.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconOf(String name) => switch (name) {
    'flag' => Icons.flag_outlined,
    'directions_run' => Icons.directions_run,
    'emoji_events' => Icons.emoji_events_outlined,
    'workspace_premium' => Icons.workspace_premium_outlined,
    'military_tech' => Icons.military_tech_outlined,
    'route' => Icons.route_outlined,
    'local_fire_department' => Icons.local_fire_department_outlined,
    'timer' => Icons.timer_outlined,
    'wb_twilight' => Icons.wb_twilight,
    'nights_stay' => Icons.nights_stay_outlined,
    _ => Icons.emoji_events_outlined,
  };
}

/// 新徽章解锁庆祝弹窗：勋章弹入 + 旋转光轨 + 呼吸光晕 + 撒花。
/// 单枚时突出大勋章；一次解锁多枚时首枚做大勋章，其余在下方小列表补齐。
/// 入场动画播完保持定格，氛围层（光轨/光晕）弹窗存续期间持续循环。
Future<void> showBadgeUnlockDialog(
  BuildContext context,
  List<BadgeDef> badges,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _BadgeUnlockDialog(badges: badges),
  );
}

class _BadgeUnlockDialog extends StatefulWidget {
  const _BadgeUnlockDialog({required this.badges});

  final List<BadgeDef> badges;

  @override
  State<_BadgeUnlockDialog> createState() => _BadgeUnlockDialogState();
}

class _BadgeUnlockDialogState extends State<_BadgeUnlockDialog>
    with TickerProviderStateMixin {
  /// 入场：卡片浮现、勋章弹入、文案依次上滑，一次性播完定格。
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  /// 氛围：光轨旋转、光晕与阴影呼吸，循环驱动。
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _entry.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final main = widget.badges.first;
    final rest = widget.badges.length > 1 ? widget.badges.sublist(1) : null;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: _fadeScale(
        0,
        0.32,
        Container(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: c.stroke),
          ),
          child: Stack(
            children: [
              // 撒花铺在卡片内：庆祝语义与内容互不抢戏，不拦截点击。
              const Positioned.fill(child: IgnorePointer(child: ConfettiBurst())),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _medal(c, main),
                  const SizedBox(height: 18),
                  _fadeSlide(
                    0.28,
                    0.52,
                    Text(
                      '恭喜解锁新徽章'.tr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                        color: c.actionForeground,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _fadeSlide(
                    0.36,
                    0.6,
                    Text(
                      badgeName(main),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _fadeSlide(
                    0.44,
                    0.68,
                    Text(
                      badgeDesc(main),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ),
                  if (rest != null) ...[
                    const SizedBox(height: 14),
                    _fadeSlide(0.58, 0.8, _restList(c, rest)),
                  ],
                  const SizedBox(height: 22),
                  _fadeSlide(0.64, 0.86, _claimButton(c)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 主勋章：光晕呼吸 + 虚线光轨旋转（氛围层），本体弹性缩放入场（入场层）。
  Widget _medal(AppPalette c, BadgeDef def) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _ambient]),
      builder: (context, child) {
        final pop = Curves.easeOutBack.transform(
          Interval(0.05, 0.45, curve: Curves.easeOut).transform(_entry.value),
        );
        final breath =
            0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi);
        return Transform.scale(
          scale: pop,
          child: SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scaleAlpha(c.accent, 0.22 + 0.14 * breath),
                        scaleAlpha(c.accent, 0),
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  size: const Size(150, 150),
                  painter: _MedalRingPainter(c, _ambient.value, breath),
                ),
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: accentGradient(c),
                    boxShadow: [
                      BoxShadow(
                        color: scaleAlpha(c.accent, 0.4 * breath),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(
                    _iconOfStatic(def.icon),
                    size: 40,
                    color: c.onAccent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 一次解锁多枚时，首枚之外的徽章收进浅色小列表，避免弹窗无限变高。
  Widget _restList(AppPalette c, List<BadgeDef> rest) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in rest)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _iconOfStatic(b.icon),
                    size: 14,
                    color: c.actionForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      badgeName(b),
                      style: TextStyle(fontSize: 12, color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _claimButton(AppPalette c) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: accentGradient(c),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: c.glow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          '收下勋章'.tr,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: c.onAccent,
          ),
        ),
      ),
    );
  }

  /// 区间淡入 + 上移：文案与按钮依次浮现。
  Widget _fadeSlide(double start, double end, Widget child) {
    final anim = CurvedAnimation(
      parent: _entry,
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

  /// 卡片整体浮现：轻微放大 + 淡入，播完定格在原尺寸。
  Widget _fadeScale(double start, double end, Widget child) {
    final anim = CurvedAnimation(
      parent: _entry,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.scale(scale: 0.92 + 0.08 * anim.value, child: child),
      ),
      child: child,
    );
  }
}

/// 勋章外圈旋转虚线光轨：10 段圆弧随 [turn]（0..1 循环）转动，
/// 亮度随 [glow]（0..1 呼吸）起伏。
class _MedalRingPainter extends CustomPainter {
  _MedalRingPainter(this.p, this.turn, this.glow);

  final AppPalette p;
  final double turn;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = scaleAlpha(p.accent, 0.2 + 0.4 * glow);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn * 2 * math.pi);
    const segments = 10;
    final step = 2 * math.pi / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        i * step,
        step * 0.45,
        false,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MedalRingPainter oldDelegate) =>
      oldDelegate.p != p ||
      oldDelegate.turn != turn ||
      oldDelegate.glow != glow;
}

IconData _iconOfStatic(String name) => switch (name) {
  'flag' => Icons.flag_outlined,
  'directions_run' => Icons.directions_run,
  'emoji_events' => Icons.emoji_events_outlined,
  'workspace_premium' => Icons.workspace_premium_outlined,
  'military_tech' => Icons.military_tech_outlined,
  'route' => Icons.route_outlined,
  'local_fire_department' => Icons.local_fire_department_outlined,
  'timer' => Icons.timer_outlined,
  'wb_twilight' => Icons.wb_twilight,
  'nights_stay' => Icons.nights_stay_outlined,
  _ => Icons.emoji_events_outlined,
};
