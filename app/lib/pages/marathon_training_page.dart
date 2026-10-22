import 'package:flutter/material.dart';
import '../services/marathon_training_service.dart';

class MarathonTrainingPage extends StatefulWidget {
  const MarathonTrainingPage({super.key});
  @override
  State<MarathonTrainingPage> createState() => _MarathonTrainingPageState();
}
class _MarathonTrainingPageState extends State<MarathonTrainingPage> {
  late Future<List<TrainingTask>> _tasks;
  Set<String> _done = {};
  @override void initState() {
    super.initState();
    _tasks = MarathonTrainingService.load();
    MarathonTrainingService.completed().then((v) { if (mounted) setState(() => _done = v); });
  }
  String _pace(int? s) {
    if (s == null) return '';
    return "${s ~/ 60}′${(s % 60).toString().padLeft(2, '0')}″";
  }
  @override Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return Scaffold(
      appBar: AppBar(title: const Text('2027 厦门马拉松训练计划')),
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
                ]),
              );
              final t = tasks[index - 1], isToday = t.date == today;
              return Card(
                child: CheckboxListTile(
                  value: _done.contains(t.date),
                  title: Text('${t.date}  ${t.title}${isToday ? " · 今天" : ""}'),
                  subtitle: Text(
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
