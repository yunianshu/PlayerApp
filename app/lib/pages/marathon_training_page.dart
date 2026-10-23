import 'package:flutter/material.dart';

import '../services/marathon_training_service.dart';
import '../services/training_reminder_service.dart';
import '../data/database.dart';
import '../services/training_feedback_service.dart';
import '../services/adaptive_training_service.dart';
import '../services/ai_training_coach.dart';
import '../services/ai_coach_settings.dart';
import '../widgets/app_toast.dart';
import '../widgets/marathon_training_dashboard.dart';
import 'ai_coach_settings_page.dart';

class MarathonTrainingPage extends StatefulWidget {
  const MarathonTrainingPage({super.key});
  @override
  State<MarathonTrainingPage> createState() => _MarathonTrainingPageState();
}

class _MarathonTrainingPageState extends State<MarathonTrainingPage> {
  late Future<List<TrainingTask>> _tasks;
  Set<String> _done = {};
  bool _reminderEnabled = false;
  bool _aiBusy = false;
  bool _reminderBusy = false;
  int _hour = 6;
  int _minute = 0;
  Map<String, double> _runsByDate = {};
  Map<String, Map<String, int>> _feedback = {};
  @override
  void initState() {
    super.initState();
    _tasks = AdaptiveTrainingService.effectiveTasks();
    MarathonTrainingService.completed().then((v) {
      if (mounted) setState(() => _done = v);
    });
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final enabled = await TrainingReminderService.enabled();
      final time = await TrainingReminderService.time();
      final runs = await RunDatabase.instance.listRuns();
      final feedback = await TrainingFeedbackService.all();
      final km = <String, double>{};
      for (final run in runs) {
        final day = run.start.toLocal().toIso8601String().substring(0, 10);
        km[day] = (km[day] ?? 0) + run.distanceKm;
      }
      if (mounted) {
        setState(() {
          _reminderEnabled = enabled;
          _hour = time.$1;
          _minute = time.$2;
          _runsByDate = km;
          _feedback = feedback;
        });
      }
    } catch (error) {
      if (mounted) showAppToast(context, '训练记录或提醒读取失败：$error');
    }
    // Notification delivery must not block loading the user's records/settings.
    try {
      await TrainingReminderService.notifyTodayIfNeeded();
    } catch (error) {
      if (mounted) showAppToast(context, '今日提醒发送失败：$error');
    }
  }

  Future<void> _settings() async {
    if (_reminderBusy) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null || !mounted) return;
    await _changeReminder(true, picked.hour, picked.minute);
  }

  Future<void> _changeReminder(bool value, int hour, int minute) async {
    if (_reminderBusy) return;
    setState(() => _reminderBusy = true);
    try {
      await TrainingReminderService.configure(
        enabled: value,
        hour: hour,
        minute: minute,
      );
      if (mounted) {
        setState(() {
          _reminderEnabled = value;
          _hour = hour;
          _minute = minute;
        });
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, '提醒设置失败：$error');
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  Future<void> _openAiSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AiCoachSettingsPage()),
    );
  }

  Future<void> _aiReview() async {
    if (_aiBusy) return;
    setState(() => _aiBusy = true);
    try {
      // Configure first, even when no downward adjustment is currently needed.
      // The old dialog hid all configuration behind that condition.
      var settings = await AiCoachSettingsStore.instance.load();
      if (!mounted) return;
      if (!settings.ready) {
        final configure = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('先配置 AI 服务'),
            content: const Text('请填写模型服务地址、模型名称和 API Key。配置保存后无需每次重新填写。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去配置'),
              ),
            ],
          ),
        );
        if (configure != true || !mounted) return;
        await _openAiSettings();
        if (!mounted) return;
        settings = await AiCoachSettingsStore.instance.load();
        if (!mounted || !settings.ready) return;
      }
      final proposal = await AdaptiveTrainingService.suggest(
        now: DateTime.now(),
        actualKm: _runsByDate,
      );
      if (!mounted) return;
      if (proposal == null) {
        showAppToast(context, 'AI 已配置，目前没有需要下调的训练方案可供审查');
        return;
      }
      final config = settings.config!;
      final consent = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('AI 教练审查'),
          content: SingleChildScrollView(
            child: Text(
              '模型：${config.model}\n目标地址：${config.endpoint}\n\n'
              '仅发送周跑量、疼痛和疲劳评分，以及拟调整的日期与距离。'
              '不会发送 GPS 轨迹；这些汇总信息和 API Key 将传至上述模型服务。'
              '服务商可能收取调用费用。分析只提供参考，不自动更改训练计划。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('同意发送并分析'),
            ),
          ],
        ),
      );
      if (consent != true || !mounted) return;
      final response = await AiTrainingCoach.review(
        endpoint: config.uri,
        apiKey: settings.apiKey!,
        model: config.model,
        proposal: proposal,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('AI 教练建议（仅供参考）'),
          content: SingleChildScrollView(child: SelectableText(response)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } on AiCoachException catch (error) {
      if (mounted) showAppToast(context, error.message);
    } catch (_) {
      if (mounted) showAppToast(context, 'AI 分析失败，请检查服务设置或稍后重试');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _suggestAdjustments() async {
    final proposal = await AdaptiveTrainingService.suggest(
      now: DateTime.now(),
      actualKm: _runsByDate,
    );
    if (!mounted) return;
    if (proposal == null) {
      showAppToast(context, '目前没有需要下调的训练建议');
      return;
    }
    final changes = (proposal['changes'] as List).cast<Map<String, dynamic>>();
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练调整建议（需确认）'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(proposal['reason'] as String),
              const SizedBox(height: 12),
              ...changes.map(
                (c) => Text('${c['date']}：${c['from']} → ${c['to']} km'),
              ),
              const SizedBox(height: 12),
              const Text('未完成的公里数不补跑；原始计划保留。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认调整'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await AdaptiveTrainingService.apply(proposal);
      if (await TrainingReminderService.enabled()) {
        final time = await TrainingReminderService.time();
        await TrainingReminderService.configure(
          enabled: true,
          hour: time.$1,
          minute: time.$2,
        );
      }
      if (mounted) {
        setState(() {
          _tasks = AdaptiveTrainingService.effectiveTasks();
        });
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '调整失败：$e');
      }
    }
  }

  Future<void> _recordFeedback(TrainingTask task) async {
    final old = _feedback[task.date];
    var pain = old?['pain'] ?? 0;
    var fatigue = old?['fatigue'] ?? 3;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text('${task.date} 训练反馈'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('疼痛程度 $pain / 10'),
              Slider(
                value: pain.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                onChanged: (v) => refresh(() => pain = v.round()),
              ),
              Text('疲劳程度 $fatigue / 10'),
              Slider(
                value: fatigue.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                onChanged: (v) => refresh(() => fatigue = v.round()),
              ),
              Text(TrainingFeedbackService.advisory(pain, fatigue)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;
    try {
      await TrainingFeedbackService.save(
        task.date,
        pain: pain,
        fatigue: fatigue,
      );
      if (mounted) {
        setState(
          () => _feedback[task.date] = {'pain': pain, 'fatigue': fatigue},
        );
      }
    } catch (error) {
      if (mounted) {
        showAppToast(context, '反馈保存失败：$error');
      }
    }
  }

  Future<void> _setComplete(TrainingTask task, bool value) async {
    try {
      await MarathonTrainingService.setComplete(task.date, value);
      if (mounted) {
        setState(() {
          if (value) {
            _done.add(task.date);
          } else {
            _done.remove(task.date);
          }
        });
      }
    } catch (error) {
      if (mounted) showAppToast(context, '保存失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('训练计划'),
        actions: [
          IconButton(
            tooltip: 'AI 服务设置',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _aiBusy ? null : _openAiSettings,
          ),
          IconButton(
            tooltip: '设置每日提醒时间',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _reminderBusy ? null : _settings,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: FutureBuilder<List<TrainingTask>>(
              future: _tasks,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event_busy_outlined, size: 40),
                          const SizedBox(height: 16),
                          const Text('训练计划读取失败，请重试。'),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _tasks = AdaptiveTrainingService.effectiveTasks();
                            }),
                            child: const Text('重新加载'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return MarathonTrainingDashboard(
                  tasks: snapshot.data!,
                  completed: _done,
                  runsByDate: _runsByDate,
                  feedback: _feedback,
                  reminderEnabled: _reminderEnabled,
                  reminderHour: _hour,
                  reminderMinute: _minute,
                  reminderBusy: _reminderBusy,
                  usesDailySummary: TrainingReminderService.usesDailySummary,
                  aiBusy: _aiBusy,
                  onComplete: _setComplete,
                  onFeedback: _recordFeedback,
                  onAiReview: _aiReview,
                  onAiSettings: _openAiSettings,
                  onSuggestAdjustments: _suggestAdjustments,
                  onReminderChanged: (value) =>
                      _changeReminder(value, _hour, _minute),
                  onReminderTime: _settings,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
