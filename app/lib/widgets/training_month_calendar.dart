import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/marathon_training_service.dart';
import 'common.dart';

/// Uses the statistics activity calendar's seven-column circular date language.
/// Completion comes only from plan check-ins, never inferred from a past date.
class TrainingMonthCalendar extends StatefulWidget {
  const TrainingMonthCalendar({
    super.key,
    required this.tasks,
    required this.completed,
    required this.selectedDate,
    required this.today,
    required this.onSelect,
    this.resetRevision = 0,
  });

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
  static DateTime _monthOf(String date) {
    final value = DateTime.parse(date);
    return DateTime(value.year, value.month);
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _month = _monthOf(widget.selectedDate);
  }

  @override
  void didUpdateWidget(covariant TrainingMonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.resetRevision != widget.resetRevision) {
      _month = _monthOf(widget.selectedDate);
    }
    final dates = widget.tasks.map((e) => e.date).toList()..sort();
    if (dates.isNotEmpty &&
        (_month.isBefore(_monthOf(dates.first)) ||
            _month.isAfter(_monthOf(dates.last)))) {
      _month = _monthOf(widget.selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.colors;
    final byDate = {for (final task in widget.tasks) task.date: task};
    final dates = byDate.keys.toList()..sort();
    final first = _monthOf(dates.first);
    final last = _monthOf(dates.last);
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
    return AppCard(
      key: const ValueKey('training-month-calendar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('training-month-previous'),
                tooltip: '上个月',
                onPressed: _month.isAfter(first)
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      )
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('training-month-next'),
                tooltip: '下个月',
                onPressed: _month.isBefore(last)
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      )
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Text(
            '计划 ${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1)} km · 已完成 $done/${monthTasks.length} 天',
            textAlign: TextAlign.center,
            style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: appTextStyle(p, fontSize: 11, color: p.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(
                      p,
                      row * 7 + col - offset + 1,
                      days,
                      byDate,
                      duration,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _legend(p, '已完成', Icons.check_rounded, p.accent),
              _legend(p, '待训练', Icons.circle, p.calMid),
              _legend(p, '休息', Icons.horizontal_rule_rounded, p.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '描边为今天 · 外圈为选中日期\n灰色日期无安排，过往未勾选不代表漏练。',
            textAlign: TextAlign.center,
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

  Widget _legend(AppPalette p, String label, IconData icon, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: appTextStyle(p, fontSize: 11, color: p.textSecondary)),
    ],
  );

  Widget _cell(
    AppPalette p,
    int day,
    int count,
    Map<String, TrainingTask> tasks,
    Duration duration,
  ) {
    if (day < 1 || day > count) return const SizedBox(height: 64);
    final date = _key(DateTime(_month.year, _month.month, day));
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
    final bg = done
        ? p.accent
        : task == null || rest
        ? p.surface2
        : p.calLow;
    final fg = done
        ? p.onAccent
        : task == null
        ? p.textMuted
        : p.textPrimary;
    return Semantics(
      key: ValueKey('training-calendar-semantics-$date'),
      label:
          '$date${today ? ' 今天' : ''} $status${task == null ? '' : ' ${task.title} ${task.km}公里'}',
      button: task != null,
      enabled: task != null,
      selected: selected,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('training-day-$date'),
        onTap: task == null ? null : () => widget.onSelect(task),
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth - 2, 40.0);
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? p.textPrimary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: AnimatedContainer(
                      duration: duration,
                      width: math.max(0, size - 7),
                      height: math.max(0, size - 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        border: today
                            ? Border.all(
                                color: done ? p.textPrimary : p.accent,
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Text(
                        '$day',
                        style: appTextStyle(
                          p,
                          fontSize: 11,
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 14,
                    child: task == null
                        ? null
                        : Icon(
                            done
                                ? Icons.check_rounded
                                : rest
                                ? Icons.horizontal_rule_rounded
                                : Icons.circle,
                            size: done || rest ? 12 : 4,
                            color: done
                                ? p.accent
                                : rest
                                ? p.textSecondary
                                : p.calMid,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
