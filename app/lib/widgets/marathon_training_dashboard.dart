import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/marathon_training_service.dart';
import 'training_completion_toggle.dart';
import 'training_month_calendar.dart';

/// A session-first training view. All workout content remains available, including
/// on narrow screens and with large text; motion is only a response to input.
class MarathonTrainingDashboard extends StatefulWidget {
  const MarathonTrainingDashboard({
    super.key,
    required this.tasks,
    required this.completed,
    required this.runsByDate,
    required this.feedback,
    required this.reminderEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    required this.onComplete,
    required this.onFeedback,
    required this.onAiReview,
    required this.onAiSettings,
    required this.onSuggestAdjustments,
    required this.onReminderChanged,
    required this.onReminderTime,
    this.aiBusy = false,
    this.reminderBusy = false,
    this.usesDailySummary = false,
    this.now,
  });

  final List<TrainingTask> tasks;
  final Set<String> completed;
  final Map<String, double> runsByDate;
  final Map<String, Map<String, int>> feedback;
  final bool reminderEnabled;
  final int reminderHour, reminderMinute;
  final Future<void> Function(TrainingTask task, bool completed) onComplete;
  final ValueChanged<TrainingTask> onFeedback;
  final VoidCallback onAiReview, onAiSettings, onSuggestAdjustments;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onReminderTime;
  final bool aiBusy, reminderBusy, usesDailySummary;
  final DateTime? now;

  @override
  State<MarathonTrainingDashboard> createState() =>
      _MarathonTrainingDashboardState();
}

class _MarathonTrainingDashboardState extends State<MarathonTrainingDashboard> {
  String? _selectedDate;
  int _calendarReset = 0;
  final Set<String> _expandedDates = {};
  final Set<String> _savingDates = {};
  bool _initializedTodayExpansion = false;

  DateTime get _now => widget.now ?? DateTime.now();
  String get _today => _dateKey(_now);
  Duration get _motion => MediaQuery.of(context).disableAnimations
      ? Duration.zero
      : const Duration(milliseconds: 240);

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static DateTime _day(String date) => DateTime.parse(date);
  static DateTime _monday(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);
  static String _km(double km) =>
      km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1);
  static String _pace(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  static String _weekday(DateTime date) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1];

  List<TrainingTask> get _sortedTasks =>
      [...widget.tasks]..sort((a, b) => a.date.compareTo(b.date));

  TrainingTask _selected(List<TrainingTask> tasks) {
    return tasks.firstWhere(
      (task) => task.date == _selectedDate,
      orElse: () => tasks.firstWhere(
        (task) => task.date.compareTo(_today) >= 0,
        orElse: () => tasks.last,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeTodayExpansion();
  }

  @override
  void didUpdateWidget(covariant MarathonTrainingDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initializeTodayExpansion();
  }

  // Apply the default only once, after tasks arrive. Later rebuilds, theme
  // changes, completion saves and navigation must preserve the user's choice.
  void _initializeTodayExpansion() {
    if (_initializedTodayExpansion || widget.tasks.isEmpty) return;
    _initializedTodayExpansion = true;
    if (widget.tasks.any((task) => task.date == _today)) {
      _expandedDates.add(_today);
    }
  }

  void _select(TrainingTask task) {
    setState(() => _selectedDate = task.date);
  }

  Future<void> _complete(TrainingTask task) async {
    if (_savingDates.isNotEmpty) return;
    setState(() => _savingDates.add(task.date));
    try {
      await widget.onComplete(task, !widget.completed.contains(task.date));
    } finally {
      if (mounted) setState(() => _savingDates.remove(task.date));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final tasks = _sortedTasks;
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '暂无训练任务，请先选择或导入训练计划。',
            style: appTextStyle(p, height: 1.6),
          ),
        ),
      );
    }
    final selected = _selected(tasks);
    final monday = _monday(_day(selected.date));
    final weekTasks = tasks
        .where((task) => _monday(_day(task.date)) == monday)
        .toList();
    final completed = tasks
        .where((task) => widget.completed.contains(task.date))
        .length;
    final completedWeek = weekTasks
        .where((task) => widget.completed.contains(task.date))
        .length;
    final todayTask = tasks.where((task) => task.date == _today).firstOrNull;

    return ListView(
      key: const ValueKey('training-dashboard-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _planHeader(p, tasks, completed),
        const SizedBox(height: 22),
        AnimatedSize(
          key: const ValueKey('training-primary-session'),
          duration: _motion,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: _motion,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _sessionCard(p, selected),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          key: const ValueKey('training-schedule-navigation'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                '训练日程',
                style: appTextStyle(
                  p,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (todayTask != null)
              TextButton.icon(
                key: const ValueKey('training-return-today'),
                onPressed: () {
                  setState(() {
                    _selectedDate = todayTask.date;
                    _calendarReset++;
                  });
                },
                icon: const Icon(Icons.today_outlined, size: 16),
                label: const Text('回到今天'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TrainingMonthCalendar(
          resetRevision: _calendarReset,
          tasks: tasks,
          completed: widget.completed,
          selectedDate: selected.date,
          today: _today,
          onSelect: _select,
        ),
        const SizedBox(height: 24),
        _coachPanel(p),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                '本周一览',
                style: appTextStyle(
                  p,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$completedWeek / ${weekTasks.length} 已完成',
              style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '点选一天查看详情，完成后再勾选。',
          style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
        ),
        const SizedBox(height: 14),
        ...weekTasks.map(
          (task) => _weekRow(p, task, task.date == selected.date),
        ),
        const SizedBox(height: 20),
        _reminderPanel(p),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.health_and_safety_outlined,
              size: 16,
              color: p.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '疼痛持续或加重时停止训练。未完成的公里数不补跑，调整计划前会再次确认。',
                style: appTextStyle(
                  p,
                  fontSize: 12,
                  color: p.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _planHeader(AppPalette p, List<TrainingTask> tasks, int completed) {
    final race = tasks.where((task) => task.type == 'RACE').lastOrNull;
    final raceDate = race == null ? null : _day(race.date);
    final days = raceDate
        ?.difference(DateTime(_now.year, _now.month, _now.day))
        .inDays;
    final progress = completed / tasks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '厦门马拉松',
                    style: appTextStyle(
                      p,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    raceDate == null
                        ? '循序渐进，稳稳向前'
                        : '${raceDate.year}.${raceDate.month.toString().padLeft(2, '0')}.${raceDate.day.toString().padLeft(2, '0')}  比赛日',
                    style: appTextStyle(
                      p,
                      fontSize: 13,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (days != null && days >= 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$days', style: displayNumberStyle(p, size: 40)),
                  const SizedBox(height: 5),
                  Text(
                    '天后出发',
                    style: appTextStyle(
                      p,
                      fontSize: 11,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                '备赛进度',
                style: appTextStyle(
                  p,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$completed / ${tasks.length} 天',
              style: appTextStyle(p, fontSize: 12, color: p.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 9),
        TweenAnimationBuilder<double>(
          duration: _motion,
          curve: Curves.easeOutCubic,
          tween: Tween(end: progress),
          builder: (context, value, child) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 5,
              color: p.isEditorial ? p.textPrimary : p.accent,
              backgroundColor: p.stroke,
              semanticsLabel: '训练计划完成进度，已完成 $completed / ${tasks.length} 天',
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          '目标先按 5 小时 15 分评估',
          style: appTextStyle(p, fontSize: 11, color: p.textSecondary),
        ),
      ],
    );
  }

  Widget _sessionCard(AppPalette p, TrainingTask task) {
    final date = _day(task.date);
    final done = widget.completed.contains(task.date);
    final recorded = widget.runsByDate[task.date];
    final saving = _savingDates.contains(task.date);
    final hero = p.isDark ? p.surface2 : p.inverseSurface;
    final ink = p.onInverse;
    final pace = task.easyPace == null
        ? null
        : '${_pace(task.easyPace!)}${task.slowPace == null ? '' : '–${_pace(task.slowPace!)}'}';
    return Container(
      key: ValueKey('training-session-${task.date}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: hero,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${task.date == _today ? '今日训练' : '训练安排'}  /  ${date.month}月${date.day}日 ${_weekday(date)}',
                        style: appTextStyle(
                          p,
                          fontSize: 12,
                          color: scaleAlpha(ink, .75),
                        ),
                      ),
                    ),
                    if (done)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: p.isLight ? p.ringA : p.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 17),
                Text(
                  task.title,
                  style: appTextStyle(
                    p,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 30,
                  runSpacing: 18,
                  children: [
                    if (task.isRun)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _km(task.km),
                            style: TextStyle(
                              fontFamily: 'Barlow Condensed',
                              fontSize: 60,
                              fontWeight: FontWeight.w700,
                              height: .95,
                              color: ink,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'km',
                            style: appTextStyle(
                              p,
                              fontSize: 15,
                              color: scaleAlpha(ink, .75),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.spa_outlined,
                            size: 30,
                            color: p.isLight ? p.ringA : p.accent,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '恢复 / 力量',
                            style: appTextStyle(
                              p,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                    if (pace != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '建议配速 / km',
                            style: appTextStyle(
                              p,
                              fontSize: 11,
                              color: scaleAlpha(ink, .65),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            pace,
                            style: appTextStyle(
                              p,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 17, color: p.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      '训练说明',
                      style: appTextStyle(
                        p,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  task.notes.isEmpty ? '按计划完成训练，并根据身体状态及时调整。' : task.notes,
                  key: ValueKey('training-full-notes-${task.date}'),
                  style: appTextStyle(
                    p,
                    fontSize: 14,
                    height: 1.7,
                    color: p.textSecondary,
                  ),
                ),
                if (recorded != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '已记录 ${recorded.toStringAsFixed(2)} km${done ? '，已确认完成' : '，待你确认完成'}',
                      style: appTextStyle(p, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: ValueKey('training-complete-${task.date}'),
                    onPressed: _savingDates.isNotEmpty
                        ? null
                        : () => _complete(task),
                    style: FilledButton.styleFrom(
                      backgroundColor: done ? p.surface2 : p.accent,
                      foregroundColor: done
                          ? p.textPrimary
                          : (p.isDark ? p.bg : p.onAccent),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    icon: AnimatedSwitcher(
                      duration: _motion,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        saving
                            ? Icons.hourglass_top_rounded
                            : done
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        key: ValueKey('$done-$saving'),
                        size: 20,
                      ),
                    ),
                    label: Text(
                      saving
                          ? '正在保存…'
                          : done
                          ? '已完成 · 点击撤销'
                          : '标记为已完成',
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Center(
                  child: TextButton.icon(
                    onPressed: () => widget.onFeedback(task),
                    icon: Icon(
                      widget.feedback.containsKey(task.date)
                          ? Icons.health_and_safety
                          : Icons.monitor_heart_outlined,
                      size: 18,
                    ),
                    label: Text(
                      widget.feedback.containsKey(task.date)
                          ? '查看 / 更新训练反馈'
                          : '记录疼痛与疲劳',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coachPanel(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.stroke),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 21,
                  color: p.isEditorial ? p.textPrimary : p.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 训练教练',
                      style: appTextStyle(
                        p,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '结合跑量与恢复，审慎调整',
                      style: appTextStyle(
                        p,
                        fontSize: 12,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('training-ai-settings'),
                tooltip: '配置 AI API',
                onPressed: widget.aiBusy ? null : widget.onAiSettings,
                icon: const Icon(Icons.tune_rounded, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: widget.aiBusy ? null : widget.onAiReview,
                icon: Icon(
                  widget.aiBusy
                      ? Icons.hourglass_top_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                ),
                label: Text(widget.aiBusy ? '分析中…' : 'AI 教练分析'),
              ),
              TextButton.icon(
                onPressed: widget.onSuggestAdjustments,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('评估未来 7 天'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '分析前确认发送内容；建议仅供参考。',
            style: appTextStyle(
              p,
              fontSize: 11,
              height: 1.5,
              color: p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekRow(AppPalette p, TrainingTask task, bool selected) {
    final done = widget.completed.contains(task.date);
    final expanded = _expandedDates.contains(task.date);
    final date = _day(task.date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: _motion,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? p.accentSoft : p.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? p.accentStroke : p.stroke),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              InkWell(
                key: ValueKey('training-week-row-${task.date}'),
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => setState(() {
                  _selectedDate = task.date;
                  if (expanded) {
                    _expandedDates.remove(task.date);
                  } else {
                    _expandedDates.add(task.date);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 42,
                        child: Column(
                          children: [
                            Text(
                              _weekday(date),
                              style: appTextStyle(
                                p,
                                fontSize: 10,
                                color: p.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${date.day}',
                              style: appTextStyle(
                                p,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: appTextStyle(
                                p,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${task.isRun ? '${_km(task.km)} km' : '恢复 / 力量'}${task.date == _today ? ' · 今天' : ''}${done ? ' · 已完成' : ''}',
                              style: appTextStyle(
                                p,
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: expanded ? .5 : 0,
                        duration: _motion,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: p.textSecondary,
                        ),
                      ),
                      TrainingCompletionToggle(
                        key: ValueKey('training-week-complete-${task.date}'),
                        value: done,
                        label: '${task.date} ${task.title}完成状态',
                        palette: p,
                        busy: _savingDates.contains(task.date),
                        onPressed: _savingDates.isNotEmpty
                            ? null
                            : () => _complete(task),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: _motion,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        key: ValueKey('training-week-details-${task.date}'),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Divider(color: p.stroke, height: 1),
                            const SizedBox(height: 12),
                            if (task.easyPace != null) ...[
                              Text(
                                '配速 ${_pace(task.easyPace!)}${task.slowPace == null ? '' : '–${_pace(task.slowPace!)}'}/km',
                                style: appTextStyle(
                                  p,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                            ],
                            Text(
                              task.notes.isEmpty ? '按计划训练，注意身体反馈。' : task.notes,
                              style: appTextStyle(
                                p,
                                fontSize: 13,
                                color: p.textSecondary,
                                height: 1.7,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => widget.onFeedback(task),
                                icon: const Icon(
                                  Icons.monitor_heart_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  widget.feedback.containsKey(task.date)
                                      ? '更新训练反馈'
                                      : '记录训练反馈',
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reminderPanel(AppPalette p) {
    final time =
        '${widget.reminderHour.toString().padLeft(2, '0')}:${widget.reminderMinute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 8),
      decoration: BoxDecoration(
        border: Border.all(color: p.stroke),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: p.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '每日训练提醒',
                  style: appTextStyle(p, fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: widget.reminderEnabled,
                onChanged: widget.reminderBusy
                    ? null
                    : widget.onReminderChanged,
              ),
            ],
          ),
          if (widget.usesDailySummary)
            Padding(
              padding: const EdgeInsets.only(left: 34, right: 6, bottom: 4),
              child: Text(
                '每日提醒打开今日计划，至本期计划结束',
                style: appTextStyle(
                  p,
                  fontSize: 12,
                  height: 1.5,
                  color: p.textSecondary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: TextButton.icon(
              onPressed: widget.reminderBusy ? null : widget.onReminderTime,
              icon: const Icon(Icons.schedule_rounded, size: 16),
              label: Text('$time  更改时间'),
            ),
          ),
        ],
      ),
    );
  }
}
