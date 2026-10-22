import 'package:flutter/material.dart';
import '../services/marathon_training_service.dart';
import '../services/training_reminder_service.dart';
import '../data/database.dart';
import '../services/training_feedback_service.dart';
import '../services/adaptive_training_service.dart';
import '../services/ai_training_coach.dart';

class MarathonTrainingPage extends StatefulWidget {
  const MarathonTrainingPage({super.key});
  @override
  State<MarathonTrainingPage> createState() => _MarathonTrainingPageState();
}
class _MarathonTrainingPageState extends State<MarathonTrainingPage> {
  late Future<List<TrainingTask>> _tasks;
  Set<String> _done = {};
  bool _reminderEnabled = false;
  int _hour = 6;
  int _minute = 0;
  Map<String, double> _runsByDate = {};
  Map<String, Map<String, int>> _feedback = {};
  @override void initState() {
    super.initState();
    _tasks = AdaptiveTrainingService.effectiveTasks();
    MarathonTrainingService.completed().then((v) { if (mounted) setState(() => _done = v); });
    _loadExtras();
  }
  Future<void> _loadExtras() async {
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
  }
  Future<void> _settings() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked == null || !mounted) return;
    await _changeReminder(true, picked.hour, picked.minute);
  }
  Future<void> _changeReminder(bool value, int hour, int minute) async {
    try {
      await TrainingReminderService.configure(
        enabled: value, hour: hour, minute: minute);
      if (mounted) {
        setState(() {
        _reminderEnabled = value;
        _hour = hour;
        _minute = minute;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('提醒设置失败：$error')));
      }
    }
  }
  Future<void> _aiReview() async {
    final proposal = await AdaptiveTrainingService.suggest(
      now: DateTime.now(), actualKm: _runsByDate);
    if (!mounted) return;
    if (proposal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无需要下调的训练建议')));
      return;
    }
    final url = TextEditingController();
    final model = TextEditingController();
    final key = TextEditingController();
    final consent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI教练审查'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('仅发送周跑量、恢复评分和拟调整的日期距离。'
                '不会发送GPS轨迹；数据将传至你配置的模型服务。密钥不保存。'),
            TextField(controller: url,
              decoration: const InputDecoration(labelText: 'HTTPS Chat Completions 地址')),
            TextField(controller: model,
              decoration: const InputDecoration(labelText: '模型名称')),
            TextField(controller: key, obscureText: true,
              decoration: const InputDecoration(labelText: '本次请求API密钥')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('同意发送并分析')),
        ],
      ),
    );
    if (consent != true) {
      url.dispose(); model.dispose(); key.dispose();
      return;
    }
    final endpoint = url.text;
    final modelName = model.text;
    final token = key.text;
    url.dispose(); model.dispose(); key.dispose();
    try {
      final response = await AiTrainingCoach.review(
        endpoint: Uri.parse(endpoint), apiKey: token, model: modelName,
        proposal: proposal,
      );
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('AI教练建议（仅供参考）'),
        content: SingleChildScrollView(child: SelectableText(response)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'))],
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI调用失败：$error')));
      }
    }
  }
  Future<void> _suggestAdjustments() async {
    final proposal = await AdaptiveTrainingService.suggest(
      now: DateTime.now(), actualKm: _runsByDate);
    if (!mounted) return;
    if (proposal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前没有需要下调的训练建议')));
      return;
    }
    final changes = (proposal['changes'] as List).cast<Map<String, dynamic>>();
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练调整建议（需确认）'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(proposal['reason'] as String),
            const SizedBox(height: 12),
            ...changes.map((c) => Text(
              '${c['date']}：${c['from']} → ${c['to']} km')),
            const SizedBox(height: 12),
            const Text('未完成的公里数不补跑；原始计划保留。'),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认调整')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await AdaptiveTrainingService.apply(proposal);
      if (await TrainingReminderService.enabled()) {
        final time = await TrainingReminderService.time();
        await TrainingReminderService.configure(
          enabled: true, hour: time.$1, minute: time.$2);
      }
      if (mounted) {
        setState(() {
          _tasks = AdaptiveTrainingService.effectiveTasks();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调整失败：$e')));
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
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('疼痛程度 $pain / 10'),
            Slider(value: pain.toDouble(), min: 0, max: 10, divisions: 10,
                onChanged: (v) => refresh(() => pain = v.round())),
            Text('疲劳程度 $fatigue / 10'),
            Slider(value: fatigue.toDouble(), min: 0, max: 10, divisions: 10,
                onChanged: (v) => refresh(() => fatigue = v.round())),
            Text(TrainingFeedbackService.advisory(pain, fatigue)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (submitted != true) return;
    try {
      await TrainingFeedbackService.save(task.date, pain: pain, fatigue: fatigue);
      if (mounted) {
        setState(() => _feedback[task.date] = {
          'pain': pain, 'fatigue': fatigue,
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('反馈保存失败：$error')));
      }
    }
  }
  String _pace(int? s) {
    if (s == null) return '';
    return "${s ~/ 60}′${(s % 60).toString().padLeft(2, '0')}″";
  }
  @override Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return Scaffold(
      appBar: AppBar(title: const Text('2027 厦门马拉松训练计划'),
        actions: [IconButton(
          tooltip: '设置每日提醒时间',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _settings,
        )]),
      body: FutureBuilder<List<TrainingTask>>(
        future: _tasks,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('读取训练计划失败：${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final tasks = snapshot.data!;
          final finished = tasks.where((t) => _done.contains(t.date)).length;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('比赛日：2027年1月10日 · 目标先按5小时15分评估',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('已完成 $finished / ${tasks.length} 天 · 疼痛持续或加重时停止训练'),
                  OutlinedButton.icon(
                    onPressed: _aiReview,
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('AI教练分析'),
                  ),
                  FilledButton.icon(
                    onPressed: _suggestAdjustments,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('评估并调整未来7天'),
                  ),
                  SwitchListTile(
                    title: const Text('每日训练系统提醒（Android）'),
                    subtitle: Text('提醒时间：${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}'),
                    value: _reminderEnabled,
                    onChanged: (v) => _changeReminder(v, _hour, _minute),
                  ),
                ]),
                );
              }
              final t = tasks[index - 1], isToday = t.date == today;
              return Card(
                child: CheckboxListTile(
                  value: _done.contains(t.date),
                  title: Text('${t.date}  ${t.title}${isToday ? " · 今天" : ""}'),
                  subtitle: Text(
                    '${_runsByDate[t.date] == null ? "" : "当日已记录 ${_runsByDate[t.date]!.toStringAsFixed(2)} km（待确认完成）\\n"}'
                    '${t.isRun ? "${t.km.toStringAsFixed(0)} km" : "恢复/力量"}'
                    '${t.easyPace == null ? "" : " · ${_pace(t.easyPace)}–${_pace(t.slowPace)}/km"}\n${t.notes}',
                  ),
                  isThreeLine: true,
                  secondary: IconButton(
                    tooltip: '记录疼痛和疲劳',
                    icon: Icon(_feedback.containsKey(t.date)
                        ? Icons.health_and_safety : Icons.monitor_heart_outlined),
                    onPressed: () => _recordFeedback(t),
                  ),
                  onChanged: (v) async {
                    try {
                      await MarathonTrainingService.setComplete(t.date, v ?? false);
                      if (mounted) {
                        setState(() {
                          if (v == true) { _done.add(t.date); } else { _done.remove(t.date); }
                        });
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('保存失败：$e')));
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
