import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/marathon_training_service.dart';
import 'common.dart';

/// A full-month board of readable daily training cards. One horizontal viewport
/// keeps weekday columns aligned across every week, including on phones.
class TrainingMonthCalendar extends StatefulWidget {
  const TrainingMonthCalendar({
    super.key,
    required this.tasks,
    required this.completed,
    required this.selectedDate,
    required this.today,
    required this.onSelect,
    this.resetRevision = 0,
    this.onToday,
  });

  final VoidCallback? onToday;
  final int resetRevision;
  final List<TrainingTask> tasks;
  final Set<String> completed;
  final String selectedDate, today;
  final ValueChanged<TrainingTask> onSelect;

  @override
  State<TrainingMonthCalendar> createState() => _TrainingMonthCalendarState();
}

class _TrainingMonthCalendarState extends State<TrainingMonthCalendar>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late DateTime _month;
  final ScrollController _horizontal = ScrollController();
  bool _needsPosition = true;

  static DateTime _monthOf(String date) {
    final value = DateTime.parse(date);
    return DateTime(value.year, value.month);
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _km(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
  static String _pace(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    _month = _monthOf(widget.selectedDate);
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrainingMonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.resetRevision != widget.resetRevision) {
      final newMonth = _monthOf(widget.selectedDate);
      // Selecting a visible card should not pull the board away from the user's
      // chosen scroll position. Only external month/reset changes reposition it.
      _needsPosition =
          _month != newMonth || oldWidget.resetRevision != widget.resetRevision;
      _month = newMonth;
    }
    final dates = widget.tasks.map((e) => e.date).toList()..sort();
    if (dates.isNotEmpty &&
        (_month.isBefore(_monthOf(dates.first)) ||
            _month.isAfter(_monthOf(dates.last)))) {
      _month = _monthOf(widget.selectedDate);
      _needsPosition = true;
    }
  }

  void _changeMonth(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _needsPosition = true;
  });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.colors;
    if (widget.tasks.isEmpty) {
      return const AppCard(child: Text('暂无训练安排'));
    }
    final byDate = {for (final task in widget.tasks) task.date: task};
    final dates = byDate.keys.toList()..sort();
    final monthTasks = widget.tasks
        .where((t) => _monthOf(t.date) == _month)
        .toList();
    final km = monthTasks.fold<double>(0, (sum, t) => sum + t.km);
    final done = monthTasks
        .where((t) => widget.completed.contains(t.date))
        .length;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = _month.weekday - 1;
    final rows = ((offset + days) / 7).ceil();
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return AppCard(
      key: const ValueKey('training-month-calendar'),
      padding: EdgeInsets.all(landscape ? 6 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const ValueKey('training-schedule-navigation'),
            children: [
              IconButton(
                key: const ValueKey('training-month-previous'),
                tooltip: '上个月',
                onPressed: _month.isAfter(_monthOf(dates.first))
                    ? () => _changeMonth(-1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${_month.year}年${_month.month}月',
                  key: const ValueKey('training-calendar-month'),
                  textAlign: TextAlign.center,
                  style: appTextStyle(
                    p,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('training-month-next'),
                tooltip: '下个月',
                onPressed: _month.isBefore(_monthOf(dates.last))
                    ? () => _changeMonth(1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              if (widget.onToday != null)
                IconButton(
                  key: const ValueKey('training-return-today'),
                  tooltip: '回到今天',
                  onPressed: widget.onToday,
                  icon: const Icon(Icons.today_outlined),
                ),
            ],
          ),
          if (!landscape)
            Text(
              '计划 ${_km(km)} km · 已完成 $done/${monthTasks.length} 天',
              textAlign: TextAlign.center,
              style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
            ),
          SizedBox(height: landscape ? 2 : 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  MediaQuery.orientationOf(context) == Orientation.landscape &&
                  constraints.maxWidth < 1300;
              final cardWidth = compact
                  ? (constraints.maxWidth - 6 * 8) / 7
                  : math.max(
                      180.0 * math.max(1.0, scale * .82),
                      (constraints.maxWidth - 6 * 8) / 7,
                    );
              final boardWidth = cardWidth * 7 + 6 * 8;
              final scrolls = boardWidth > constraints.maxWidth + 1;
              final cardHeight =
                  (compact ? 60.0 : 244.0) * math.max(1.0, scale);
              if (_needsPosition) {
                _needsPosition = false;
                final focus = _monthOf(widget.selectedDate) == _month
                    ? DateTime.parse(widget.selectedDate)
                    : monthTasks.isNotEmpty
                    ? DateTime.parse(monthTasks.first.date)
                    : _month;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_horizontal.hasClients) return;
                  _horizontal.jumpTo(
                    ((focus.weekday - 1) * (cardWidth + 8)).clamp(
                      0.0,
                      _horizontal.position.maxScrollExtent,
                    ),
                  );
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (scrolls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(Icons.swipe_rounded, color: p.accent, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '左右滑动查看周一至周日 · 点击卡片查看完整安排',
                              key: const ValueKey(
                                'training-calendar-scroll-hint',
                              ),
                              style: appTextStyle(
                                p,
                                fontSize: 11,
                                color: p.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: scrolls,
                    child: SingleChildScrollView(
                      key: const ValueKey('training-calendar-board'),
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: boardWidth,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                for (var col = 0; col < 7; col++) ...[
                                  if (col > 0) const SizedBox(width: 8),
                                  SizedBox(
                                    width: cardWidth,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        bottom: compact ? 4 : 10,
                                      ),
                                      child: Text(
                                        _weekdays[col],
                                        textAlign: TextAlign.center,
                                        style: appTextStyle(
                                          p,
                                          fontSize: 12,
                                          color: p.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            for (var row = 0; row < rows; row++) ...[
                              if (row > 0) const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var col = 0; col < 7; col++) ...[
                                    if (col > 0) const SizedBox(width: 8),
                                    SizedBox(
                                      width: cardWidth,
                                      height:
                                          List.generate(
                                            7,
                                            (c) => row * 7 + c - offset + 1,
                                          ).any(
                                            (d) =>
                                                d >= 1 &&
                                                d <= days &&
                                                byDate.containsKey(
                                                  _key(
                                                    DateTime(
                                                      _month.year,
                                                      _month.month,
                                                      d,
                                                    ),
                                                  ),
                                                ),
                                          )
                                          ? cardHeight
                                          : (compact ? 60.0 : 136.0) *
                                                math.max(1.0, scale),
                                      child: _cell(
                                        p,
                                        row * 7 + col - offset + 1,
                                        days,
                                        byDate,
                                        duration,
                                        compact: compact,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _legend(p, '跑步训练', Icons.directions_run_rounded, p.accent),
              _legend(p, '休息恢复', Icons.spa_outlined, p.textSecondary),
              _legend(p, '已完成', Icons.check_circle_outline_rounded, p.accent),
            ],
          ),
          if (landscape)
            Text(
              '计划 ${_km(km)} km · 已完成 $done/${monthTasks.length} 天',
              style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
            ),
          const SizedBox(height: 10),
          Text(
            '今天突出显示，选中卡片有外框。过往未勾选仅表示未记录完成。',
            style: appTextStyle(
              p,
              fontSize: 10,
              color: p.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(AppPalette p, String text, IconData icon, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(text, style: appTextStyle(p, fontSize: 11, color: p.textSecondary)),
    ],
  );

  String _type(TrainingTask task) => switch (task.type) {
    'REST' => '休息恢复',
    'EASY' => '轻松跑',
    'LONG' => '长距离',
    'TEMPO' => '节奏跑',
    'INTERVAL' => '间歇训练',
    'RACE' => '比赛日',
    'RECOVERY' => '恢复跑',
    'STEADY' => '稳定跑',
    'HILL' => '坡道训练',
    'STRENGTH' => '力量训练',
    'CROSS' => '交叉训练',
    _ => task.isRun ? '跑步训练' : '训练安排',
  };

  Widget _cell(
    AppPalette p,
    int day,
    int count,
    Map<String, TrainingTask> tasks,
    Duration duration, {
    bool compact = false,
  }) {
    if (day < 1 || day > count) return const SizedBox.shrink();
    final dateValue = DateTime(_month.year, _month.month, day);
    final date = _key(dateValue);
    final task = tasks[date];
    final done = task != null && widget.completed.contains(date);
    final rest = task?.type == 'REST';
    final today = date == widget.today;
    final selected = date == widget.selectedDate;
    final status = task == null
        ? '无训练安排'
        : done
        ? '已完成'
        : rest
        ? '休息'
        : date.compareTo(widget.today) < 0
        ? '未记录完成'
        : '待训练';
    final accent = rest || task == null ? p.textSecondary : p.accent;
    final textAccent = p.isEditorial ? p.textPrimary : accent;
    final keySession =
        task != null &&
        const {'LONG', 'TEMPO', 'INTERVAL', 'RACE', 'HILL'}.contains(task.type);
    final pillText = keySession ? p.onAccent : textAccent;
    final background = task == null
        ? p.surface2
        : rest
        ? p.surface
        : Color.alphaBlend(
            p.accent.withValues(alpha: p.isDark ? .09 : .055),
            p.surface,
          );
    final border = selected
        ? p.textPrimary
        : today
        ? p.accent
        : task == null
        ? p.stroke
        : accent.withValues(alpha: .25);
    final pace = task?.easyPace;
    return Semantics(
      key: ValueKey('training-calendar-semantics-$date'),
      label:
          '$date${today ? ' 今天' : ''} $status${task == null ? '' : ' ${task.title} ${task.km}公里'}',
      button: task != null,
      enabled: task != null,
      selected: selected,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('training-day-$date'),
          onTap: task == null ? null : () => widget.onSelect(task),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: duration,
            padding: EdgeInsets.all(compact ? 5 : 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: border,
                width: selected || today ? 2 : 1,
              ),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$day',
                              style: appTextStyle(
                                p,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (task != null &&
                              MediaQuery.textScalerOf(context).scale(14) <= 20)
                            Icon(
                              done
                                  ? Icons.check_circle_rounded
                                  : rest
                                  ? Icons.spa_outlined
                                  : Icons.directions_run_rounded,
                              size: 16,
                              color: accent,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          task == null ? '无安排' : _type(task),
                          maxLines: 2,
                          style: appTextStyle(
                            p,
                            fontSize: 12,
                            color: textAccent,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_month.month}月$day日',
                              style: appTextStyle(
                                p,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: task == null
                                    ? p.textMuted
                                    : p.textPrimary,
                              ),
                            ),
                          ),
                          if (today)
                            Text(
                              '今天',
                              style: appTextStyle(
                                p,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: textAccent,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        _weekdays[dateValue.weekday - 1],
                        style: appTextStyle(
                          p,
                          fontSize: 10,
                          color: p.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: task == null || rest
                              ? p.surface2
                              : keySession
                              ? p.accent
                              : p.accentSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              task == null
                                  ? Icons.event_busy_outlined
                                  : rest
                                  ? Icons.spa_outlined
                                  : task.type == 'RACE'
                                  ? Icons.flag_outlined
                                  : task.type == 'STRENGTH'
                                  ? Icons.fitness_center_rounded
                                  : Icons.directions_run_rounded,
                              size: 13,
                              color: pillText,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                task == null ? '无安排' : _type(task),
                                style: appTextStyle(
                                  p,
                                  fontSize: 11,
                                  color: pillText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (task == null) ...[
                        const Spacer(),
                      ] else ...[
                        if (task.title != _type(task) && !rest)
                          Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: appTextStyle(
                              p,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (task.isRun)
                          Text(
                            '${_km(task.km)} km',
                            style: appTextStyle(
                              p,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: textAccent,
                            ),
                          )
                        else
                          Text(
                            rest ? '恢复日' : '非跑步训练',
                            style: appTextStyle(
                              p,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (task.isRun && pace != null)
                          Text(
                            '${_pace(pace)}${task.slowPace == null ? '' : '–${_pace(task.slowPace!)}'} /km',
                            style: appTextStyle(
                              p,
                              fontSize: 11,
                              color: p.textSecondary,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          task.notes.isEmpty ? '点击查看训练说明与反馈' : task.notes,
                          maxLines: 2,
                          style: appTextStyle(
                            p,
                            fontSize: 10,
                            color: p.textMuted,
                          ),
                        ),
                        const Spacer(),
                      ],
                      Row(
                        children: [
                          Icon(
                            done
                                ? Icons.check_circle_rounded
                                : task == null
                                ? Icons.horizontal_rule_rounded
                                : rest
                                ? Icons.spa_outlined
                                : Icons.schedule_rounded,
                            size: 13,
                            color: done ? p.accent : p.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              status,
                              style: appTextStyle(
                                p,
                                fontSize: 11,
                                color: done ? textAccent : p.textSecondary,
                                fontWeight: done
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (selected && task != null)
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 13,
                              color: p.textPrimary,
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
