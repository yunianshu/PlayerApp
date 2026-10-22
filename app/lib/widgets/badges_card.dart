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
                Icon(Icons.emoji_events_outlined, size: 22, color: c.accent),
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

/// 新徽章解锁弹窗：显示本次新解锁的徽章，一次性列出。
Future<void> showBadgeUnlockDialog(
  BuildContext context,
  List<BadgeDef> badges,
) {
  final c = context.readColors;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Row(
        children: [
          Icon(Icons.emoji_events_rounded, color: c.accent, size: 22),
          const SizedBox(width: 8),
          Text(
            '恭喜解锁新徽章'.tr,
            style: TextStyle(fontSize: 17, color: c.textPrimary),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final b in badges)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_iconOfStatic(b.icon), size: 16, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      badgeName(b),
                      style: TextStyle(fontSize: 13, color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('好'.tr, style: TextStyle(color: c.accent)),
        ),
      ],
    ),
  );
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
