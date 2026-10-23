import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/ai_plan_generator.dart';
import '../widgets/ai_plan_design.dart';

/// A review-only route. Returning true is the only action that authorizes the
/// caller to validate the snapshot again and persist its proposed revision.
class AiPlanAdjustmentPage extends StatelessWidget {
  const AiPlanAdjustmentPage({
    super.key,
    required this.draft,
    required this.before,
  });
  final AiPlanDraft draft;
  final List<Map<String, dynamic>> before;

  static String sessionLabel(dynamic type) =>
      const {
        'EASY': '轻松跑',
        'LONG': '长距离',
        'TEMPO': '节奏跑',
        'INTERVAL': '间歇跑',
        'HILL': '坡度训练',
        'REST': '恢复休息',
        'STRENGTH': '力量训练',
        'RACE': '比赛',
      }[type] ??
      '训练';

  static String distance(dynamic value) {
    final km = (value as num).toDouble();
    return km == km.roundToDouble()
        ? km.toInt().toString()
        : km.toStringAsFixed(1);
  }

  static String pace(Map<String, dynamic> task) {
    String part(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return task['easyPace'] is int && task['slowPace'] is int
        ? '${part(task['easyPace'])}–${part(task['slowPace'])} /km'
        : (task['km'] as num) > 0
        ? '按体感，不指定配速'
        : '休息与恢复';
  }

  bool _changed(Map<String, dynamic> old, Map<String, dynamic> next) => [
    'type',
    'title',
    'km',
    'notes',
    'easyPace',
    'slowPace',
  ].any((k) => old[k] != next[k]);

  @override
  Widget build(BuildContext context) => Theme(
    data: PlanDesign.theme(context),
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final p = PlanDesign.of(context).palette;
    final originals = {for (final t in before) t['date']: t};
    final tasks = (draft.plan['tasks'] as List).cast<Map<String, dynamic>>();
    final changes =
        tasks
            .where(
              (t) =>
                  originals[t['date']] != null &&
                  _changed(originals[t['date']]!, t),
            )
            .toList()
          ..sort(
            (a, b) => (a['date'] as String).compareTo(b['date'] as String),
          );
    final weeks = <String, DateTime>{};
    for (final t in changes) {
      final day = DateTime.parse(t['date'] as String);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      weeks[monday.toIso8601String().substring(0, 10)] = monday;
    }
    bool inWeek(Map<String, dynamic> t, DateTime monday) {
      final day = DateTime.parse(t['date'] as String);
      return !day.isBefore(monday) &&
          day.isBefore(monday.add(const Duration(days: 7)));
    }

    final oldRest = before
        .where(
          (t) => t['type'] == 'REST' && weeks.values.any((w) => inWeek(t, w)),
        )
        .length;
    final newRest = tasks
        .where(
          (t) => t['type'] == 'REST' && weeks.values.any((w) => inWeek(t, w)),
        )
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('调整预览')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: const Key('adjustment-review-scroll'),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _tag(context, 'AI 调整建议 · 待你确认', selected: true),
                ),
                const SizedBox(height: 18),
                Text(
                  '把调整，看清楚再决定。',
                  style: appTextStyle(
                    p,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  draft.summary,
                  style: appTextStyle(
                    p,
                    color: p.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${draft.plan['name'] ?? '马拉松训练'} · 共 ${changes.length} 个日期变化',
                  key: const Key('adjustment-change-count'),
                  style: appTextStyle(p, color: p.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 24),
                for (final week in weeks.values) ...[
                  _weekSummary(
                    context,
                    week,
                    before.where((t) => inWeek(t, week)).toList(),
                    tasks.where((t) => inWeek(t, week)).toList(),
                    changes.where((t) => inWeek(t, week)).length,
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 12),
                Text(
                  '具体改了什么',
                  style: appTextStyle(
                    p,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '只列有变化的日期，点击详情查看完整说明。',
                  style: appTextStyle(p, color: p.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (changes.isEmpty)
                  Text(
                    '本次方案没有改变训练安排。',
                    style: appTextStyle(p, color: p.textSecondary),
                  ),
                for (final next in changes) ...[
                  _changeCard(context, originals[next['date']]!, next),
                  const SizedBox(height: 12),
                ],
                if (changes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.spa_outlined,
                        color: p.isEditorial ? p.textPrimary : p.accent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              oldRest == newRest ? '恢复日数量保持不变' : '恢复日安排有变化',
                              style: appTextStyle(
                                p,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '受影响周内，休息日 $oldRest → $newRest 天。具体日期以上方对比为准；这不代表完成了伤病或医学评估。',
                              style: appTextStyle(
                                p,
                                color: p.textSecondary,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Divider(color: p.stroke),
                const SizedBox(height: 12),
                Text(
                  '这些不会改变',
                  style: appTextStyle(p, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in ['已完成记录', '比赛日期', '过去与今天'])
                      _tag(context, label),
                  ],
                ),
                const SizedBox(height: 20),
                PlanNotice(
                  messages: [
                    ...draft.warnings,
                    '仅调整未来未完成安排。取消或返回保留原计划；确认时若训练数据有变化，将要求重新生成。',
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('adjustment-confirm'),
                  onPressed: changes.isEmpty
                      ? null
                      : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    '确认这 ${changes.length} 项调整',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('adjustment-cancel'),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('保留原计划，暂不调整', textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label, {bool selected = false}) {
    final p = PlanDesign.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected && p.isEditorial
            ? p.accent
            : selected
            ? p.accentSoft
            : p.surface2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: selected ? p.accentStroke : p.stroke),
      ),
      child: Text(
        label,
        style: appTextStyle(
          p,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: p.isEditorial
              ? p.textPrimary
              : selected
              ? p.accent
              : p.textSecondary,
        ),
      ),
    );
  }

  Widget _weekSummary(
    BuildContext context,
    DateTime monday,
    List<Map<String, dynamic>> old,
    List<Map<String, dynamic>> next,
    int changedDays,
  ) {
    final p = PlanDesign.of(context).palette;
    final oldKm = old.fold<double>(0, (sum, t) => sum + (t['km'] as num));
    final newKm = next.fold<double>(0, (sum, t) => sum + (t['km'] as num));
    final delta = newKm - oldKm;
    final sunday = monday.add(const Duration(days: 6));
    String date(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return Container(
      key: ValueKey(
        'adjustment-week-${monday.toIso8601String().substring(0, 10)}',
      ),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.stroke),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '周计划跑量 · ${date(monday)}—${date(sunday)}',
            style: appTextStyle(p, color: p.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 18,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: distance(oldKm),
                      style: TextStyle(color: p.textMuted, fontSize: 25),
                    ),
                    TextSpan(
                      text: ' → ',
                      style: TextStyle(color: p.textMuted, fontSize: 20),
                    ),
                    TextSpan(
                      text: distance(newKm),
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 34,
                      ),
                    ),
                    TextSpan(
                      text: ' km',
                      style: TextStyle(color: p.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${delta > 0 ? '+' : ''}${distance(delta)} km',
                    style: appTextStyle(
                      p,
                      color: p.isEditorial ? p.textPrimary : p.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$changedDays 个日期变化',
                    style: appTextStyle(
                      p,
                      color: p.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (old.any((t) => t['type'] == 'RACE') ||
              next.any((t) => t['type'] == 'RACE')) ...[
            const SizedBox(height: 8),
            Text(
              '本周合计含比赛距离。',
              style: appTextStyle(p, fontSize: 11, color: p.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _changeCard(
    BuildContext context,
    Map<String, dynamic> old,
    Map<String, dynamic> next,
  ) {
    final p = PlanDesign.of(context).palette;
    final date = DateTime.parse(next['date'] as String);
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1];
    return Container(
      key: ValueKey('adjustment-day-${next['date']}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                '周$weekday · ${next['date']}',
                style: appTextStyle(p, color: p.textSecondary, fontSize: 12),
              ),
              Text(
                old['type'] == next['type']
                    ? sessionLabel(next['type'])
                    : '${sessionLabel(old['type'])} → ${sessionLabel(next['type'])}',
                style: appTextStyle(
                  p,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${distance(old['km'])} km',
                  style: TextStyle(color: p.textMuted, fontSize: 23),
                ),
                TextSpan(
                  text: '  →  ',
                  style: TextStyle(color: p.textMuted, fontSize: 21),
                ),
                TextSpan(
                  text: '${distance(next['km'])} km',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${next['notes'] ?? ''}',
            style: appTextStyle(
              p,
              color: p.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                    ? AnimationStyle.noAnimation
                    : AnimationStyle(
                        duration: const Duration(milliseconds: 220),
                      ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: Text(
                  '配速与完整对比',
                  style: appTextStyle(p, color: p.textSecondary, fontSize: 12),
                ),
                children: [
                  _version(context, old, proposed: false),
                  const SizedBox(height: 12),
                  _version(context, next, proposed: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _version(
    BuildContext context,
    Map<String, dynamic> task, {
    required bool proposed,
  }) {
    final p = PlanDesign.of(context).palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${proposed ? '建议' : '原安排'} · ${task['title'] ?? sessionLabel(task['type'])}',
            style: appTextStyle(p, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            '${sessionLabel(task['type'])} · ${distance(task['km'])} km · ${pace(task)}',
            style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
          ),
          const SizedBox(height: 5),
          Text(
            '${task['notes'] ?? ''}',
            style: appTextStyle(
              p,
              fontSize: 12,
              color: p.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
