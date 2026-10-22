import 'package:flutter/material.dart';
import '../services/marathon_training_service.dart';
import '../services/training_reminder_service.dart';
import '../data/database.dart';

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
  @override void initState() {
    super.initState();
    _tasks = MarathonTrainingService.load();
    MarathonTrainingService.completed().then((v) { if (mounted) setState(() => _done = v); });
    _loadExtras();
  }
  Future<void> _loadExtras() async {
    final enabled = await TrainingReminderService.enabled();
    final time = await TrainingReminderService.time();
    final runs = await RunDatabase.instance.listRuns();
    final km = <String, double>{};
    for (final run in runs) {
      final day = run.start.toLocal().toIso8601String().substring(0, 10);
      km[day] = (km[day] ?? 0) + run.distanceKm;
    }
    if (mounted) setState(() {
      _reminderEnabled = enabled;
      _hour = time.$1;
      _minute = time.$2;
      _runsByDate = km;
    });
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
      if (mounted) setState(() {
        _reminderEnabled = value;
        _hour = hour;
        _minute = minute;
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提醒设置失败：$error')));
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
              if (index == 0) return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('比赛日：2027年1月10日 · 目标先按5小时15分评估',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('已完成 $finished / ${tasks.length} 天 · 疼痛持续或加重时停止训练'),
                  SwitchListTile(
                    title: const Text('每日训练系统提醒（Android）'),
                    subtitle: Text('提醒时间：${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}'),
                    value: _reminderEnabled,
                    onChanged: (v) => _changeReminder(v, _hour, _minute),
                  ),
                ]),
              );
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
                  onChanged: (v) async {
                    try {
                      await MarathonTrainingService.setComplete(t.date, v ?? false);
                      if (mounted) setState(() {
                        if (v == true) { _done.add(t.date); } else { _done.remove(t.date); }
                      });
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('保存失败：$e')));
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
