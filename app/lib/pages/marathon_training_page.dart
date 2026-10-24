import '../services/body_weight_service.dart';
import '../widgets/weight_ai_consent.dart';

import 'package:flutter/material.dart';

import '../services/marathon_training_service.dart';
import '../services/training_reminder_service.dart';
import '../data/database.dart';
import '../services/app_data.dart';
import '../services/training_run_results.dart';
import '../services/training_feedback_service.dart';
import '../services/adaptive_training_service.dart';
import '../services/ai_coach_settings.dart';
import '../widgets/app_toast.dart';
import '../widgets/marathon_training_dashboard.dart';
import 'ai_coach_settings_page.dart';
import 'training_plan_share_page.dart';
import '../services/training_plan_export.dart';
import 'ai_plan_creation_page.dart';
import 'ai_plan_adjustment_page.dart';
import '../widgets/ai_plan_design.dart';
import '../services/training_plan_catalog.dart';
import '../services/ai_plan_generator.dart';

import 'dart:convert';

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
  bool _planBusy = false;
  bool _shareBusy = false;
  bool _aiWaiting = false;
  int _aiRequest = 0;
  int _planLoad = 0;
  int _runsLoad = 0;
  String _planId = MarathonTrainingService.id;
  Map<String, dynamic>? _plan;
  bool _reminderBusy = false;
  int _hour = 6;
  int _minute = 0;
  Map<String, double> _runsByDate = {};
  Map<String, Map<String, int>> _feedback = {};
  @override
  void initState() {
    super.initState();
    _tasks = _loadPlan();
    _loadExtras();
    AppData.instance.addListener(_reloadRuns);
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_reloadRuns);
    ++_runsLoad;
    super.dispose();
  }

  Future<void> _reloadRuns() async {
    final load = ++_runsLoad;
    try {
      final km = await _readActualKm();
      if (mounted && load == _runsLoad) setState(() => _runsByDate = km);
    } catch (error) {
      if (mounted && load == _runsLoad) {
        showAppToast(context, '跑步成果刷新失败：$error');
      }
    }
  }

  Future<List<TrainingTask>> _loadPlan() async {
    final load = ++_planLoad;
    final id = await TrainingPlanCatalog.activeId();
    final plan = await TrainingPlanCatalog.plan(id);
    final done = await MarathonTrainingService.completed(planId: id);
    final feedback = await TrainingFeedbackService.all(planId: id);
    final tasks = await AdaptiveTrainingService.effectiveTasks(planId: id);
    if (mounted && load == _planLoad) {
      setState(() {
        _planId = id;
        _plan = plan;
        _done = done;
        _feedback = feedback;
      });
    }
    return tasks;
  }

  Future<void> _sharePlan() async {
    if (_shareBusy || _planBusy || _aiBusy) return;
    setState(() => _shareBusy = true);
    try {
      final load = _tasks;
      final tasks = await load;
      final actual = await _readActualKm();
      if (!mounted || load != _tasks || tasks.isEmpty || _plan == null) return;
      final data = TrainingPlanExportData(
        name: _plan!['name'] as String? ?? '马拉松训练计划',
        raceDate: _plan!['raceDate'] as String? ?? '',
        goal: _plan!['goalMinutes'] is num
            ? '目标：${_plan!['goalMinutes']} 分钟（需结合训练评估）'
            : '目标：${_plan!['goal'] ?? '健康完赛，按恢复情况调整'}',
        createdAt: DateTime.now(),
        tasks: tasks,
        completed: _done,
        results: {
          for (final task in tasks)
            task.date: TrainingRunResults.forTask(
              task,
              actualKm: actual[task.date],
              manuallyCompleted: _done.contains(task.date),
            ),
        },
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TrainingPlanSharePage(
            data: data,
            palette: PlanDesign.of(context, listen: false).palette,
          ),
        ),
      );
    } catch (_) {
      if (mounted) showAppToast(context, '训练计划读取失败，请重试');
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Future<void> _managePlans() async {
    if (_planBusy || _aiBusy || _reminderBusy) return;
    setState(() => _planBusy = true);
    try {
      final plans = await TrainingPlanCatalog.plans();
      if (!mounted) return;
      final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: PlanDesign.of(context, listen: false).palette.surface,
        builder: (ctx) => Theme(
          data: PlanDesign.theme(context),
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * .65,
              child: ListView(
                children: [
                  const ListTile(
                    title: Text('我的训练计划'),
                    subtitle: Text('同一时间只启用一份计划的提醒，切换不会删除记录。'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('添加赛事 · AI 生成计划'),
                    onTap: () => Navigator.pop(ctx, '__create__'),
                  ),
                  ...plans.map(
                    (plan) => ListTile(
                      leading: Icon(
                        plan['id'] == _planId
                            ? Icons.check_circle
                            : Icons.event_note,
                      ),
                      title: Text(plan['name'] as String),
                      subtitle: Text('${plan['raceDate'] ?? ''}'),
                      onTap: () => Navigator.pop(ctx, plan['id'] as String),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == '__create__') {
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const AiPlanCreationPage()),
        );
        if (mounted && saved == true) {
          showAppToast(context, '已保存的计划可在“我的训练计划”中选择启用');
        }
      } else if (choice != _planId) {
        // Cancel old alarms before switching so two plans never remain scheduled.
        final wasEnabled = await TrainingReminderService.enabled();
        final time = await TrainingReminderService.time();
        if (wasEnabled) await TrainingReminderService.configure(enabled: false);
        await TrainingPlanCatalog.activate(choice);
        if (mounted) {
          setState(() {
            _tasks = _loadPlan();
            _reminderEnabled = false;
          });
        }
        if (wasEnabled) {
          try {
            await TrainingReminderService.configure(
              enabled: true,
              hour: time.$1,
              minute: time.$2,
            );
            if (mounted) setState(() => _reminderEnabled = true);
          } catch (error) {
            if (mounted) showAppToast(context, '计划已切换，提醒尚未启用：$error');
          }
        }
      }
    } catch (error) {
      final enabled = await TrainingReminderService.enabled();
      if (mounted) {
        setState(() => _reminderEnabled = enabled);
        showAppToast(context, '计划操作失败：$error');
      }
    } finally {
      if (mounted) setState(() => _planBusy = false);
    }
  }

  Future<void> _loadExtras() async {
    await _reloadRuns();
    try {
      final enabled = await TrainingReminderService.enabled();
      final time = await TrainingReminderService.time();
      if (mounted) {
        setState(() {
          _reminderEnabled = enabled;
          _hour = time.$1;
          _minute = time.$2;
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
    if (_reminderBusy || _planBusy || _aiBusy) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      builder: (_, child) =>
          Theme(data: PlanDesign.theme(context), child: child!),
    );
    if (picked == null || !mounted) return;
    await _changeReminder(true, picked.hour, picked.minute);
  }

  Future<void> _changeReminder(bool value, int hour, int minute) async {
    if (_reminderBusy || _planBusy || _aiBusy) return;
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

  Future<T?> _showPlanDialog<T>({required WidgetBuilder builder}) =>
      showDialog<T>(
        context: context,
        builder: (_) => Theme(
          data: PlanDesign.theme(context),
          child: Builder(builder: builder),
        ),
      );

  Future<void> _openAiSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AiCoachSettingsPage()),
    );
  }

  Future<void> _aiReview() async {
    if (_aiBusy || _planBusy || _reminderBusy) return;
    final request = ++_aiRequest;
    setState(() => _aiBusy = true);
    try {
      var settings = await AiCoachSettingsStore.instance.load();
      if (!mounted) return;
      if (!settings.ready) {
        await _openAiSettings();
        if (!mounted) return;
        settings = await AiCoachSettingsStore.instance.load();
        if (!settings.ready || !mounted) return;
      }
      final planId = _planId;
      final plan = await TrainingPlanCatalog.plan(planId);
      final revision = await TrainingPlanCatalog.revision(planId);
      final completed = await MarathonTrainingService.completed(planId: planId);
      final sourceTasks = await AdaptiveTrainingService.effectiveTasks(
        planId: planId,
      );
      final feedback = await TrainingFeedbackService.all(planId: planId);
      final now = DateTime.now();
      final since = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 27)).toIso8601String().substring(0, 10);
      final runsSnapshot = await RunDatabase.instance.listRuns();
      final runSummary = TrainingRunSummary(runsSnapshot, now);
      final actualSnapshot = TrainingRunResults.aggregate(runsSnapshot);
      final actual = Map<String, double>.fromEntries(
        actualSnapshot.entries.where((e) => e.key.compareTo(since) >= 0),
      );
      final recentFeedback = Map<String, Map<String, int>>.fromEntries(
        feedback.entries.where((e) => e.key.compareTo(since) >= 0),
      );
      final source = <String, dynamic>{
        ...plan,
        'tasks': [
          for (final raw in plan['tasks'] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'km': sourceTasks.firstWhere((t) => t.date == raw['date']).km,
            },
        ],
      };
      final sourceFingerprint = jsonEncode(sourceTasks.map(_taskJson).toList());
      final config = settings.config!;
      BodyWeightSnapshot? weightSnapshot;
      try {
        weightSnapshot = await BodyWeightService.instance.snapshot();
      } catch (_) {
        /* Optional data never blocks generation. */
      }
      final weightSummary = weightSnapshot?.summary(now);
      var includeWeight = false;
      if (!mounted) return;
      final consent = await _showPlanDialog<bool>(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, updateConsent) => AlertDialog(
            title: const Text('AI 调整计划 · 发送确认'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '模型：${config.model}\n接收服务：${config.endpoint}\n\n'
                    '发送当前赛事与训练计划、手动完成状态、按跑步记录核对的距离成果、最近 28 天每日跑量、疼痛和疲劳反馈及建计划时填写的训练状况。'
                    '另发送近 28 天活动次数、距离、有效活动时长、加权平均配速、最长单次距离和记录来源计数；心率未接入、睡眠未记录，不推算。'
                    '不发送 GPS 轨迹。以上信息和 API Key 将传至该服务，可能产生费用。\n\n'
                    '本次可减量或在可训练日内同周调换训练，不补跑、不增加周负荷或提速。预览后确认才保存。建议不保证达成目标，也不代替医疗评估。',
                  ),
                  WeightAiConsent(
                    unavailable: weightSnapshot == null,
                    summary: weightSummary,
                    selected: includeWeight,
                    onChanged: (value) =>
                        updateConsent(() => includeWeight = value),
                  ),
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
                child: const Text('同意发送并生成'),
              ),
            ],
          ),
        ),
      );
      if (consent != true || !mounted) return;
      if (includeWeight &&
          !await BodyWeightService.instance.unchanged(weightSnapshot!)) {
        throw StateError('体重记录已变化，请重新确认生成');
      }
      if (BodyWeightRecord.dateKey(DateTime.now()) !=
              BodyWeightRecord.dateKey(now) ||
          await TrainingPlanCatalog.revision(planId) != revision ||
          !await _completionUnchanged(planId, completed) ||
          jsonEncode(await TrainingFeedbackService.all(planId: planId)) !=
              jsonEncode(feedback) ||
          TrainingRunSummary(
                await RunDatabase.instance.listRuns(),
                now,
              ).fingerprint !=
              runSummary.fingerprint) {
        throw StateError('训练或恢复数据已变化，请重新确认发送');
      }
      if (!mounted || request != _aiRequest) return;
      setState(() => _aiWaiting = true);
      final draft = await AiPlanGenerator.generateAdjustment(
        existingPlan: source,
        now: now,
        completed: completed,
        actualKm: actual,
        feedback: recentFeedback,
        weightSummary: includeWeight ? weightSummary : null,
        runSummary: runSummary,
        config: config,
        apiKey: settings.apiKey!,
      );
      if (!mounted || request != _aiRequest) return;
      if (includeWeight &&
          !await BodyWeightService.instance.unchanged(weightSnapshot!)) {
        throw StateError('体重记录已变化，请重新生成调整');
      }
      if (BodyWeightRecord.dateKey(DateTime.now()) !=
              BodyWeightRecord.dateKey(now) ||
          _planId != planId ||
          await TrainingPlanCatalog.revision(planId) != revision ||
          !await _completionUnchanged(planId, completed) ||
          jsonEncode(await TrainingFeedbackService.all(planId: planId)) !=
              jsonEncode(feedback) ||
          TrainingRunSummary(
                await RunDatabase.instance.listRuns(),
                now,
              ).fingerprint !=
              runSummary.fingerprint) {
        throw StateError('训练或恢复数据已变化，请重新生成调整方案');
      }
      final currentSettings = await AiCoachSettingsStore.instance.load();
      if (currentSettings.config?.endpoint != config.endpoint ||
          currentSettings.config?.model != config.model ||
          currentSettings.apiKey != settings.apiKey) {
        throw StateError('AI 服务设置已变化，请重新生成');
      }
      if (!mounted || request != _aiRequest) return;
      setState(() => _aiWaiting = false);
      final before = {for (final t in sourceTasks) t.date: _taskJson(t)};
      final changes = (draft.plan['tasks'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (t) =>
                jsonEncode(before[t['date']]) !=
                jsonEncode(_taskJson(TrainingTask.fromJson(t))),
          )
          .toList();
      if (changes.isEmpty && draft.adaptationEvidence.isEmpty) {
        showAppToast(context, 'AI 建议维持当前安排，没有需要保存的调整');
        return;
      }
      final approved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AiPlanAdjustmentPage(
            draft: draft,
            before: sourceTasks.map(_taskJson).toList(),
          ),
        ),
      );
      if (approved != true || !mounted) return;
      final fresh = await AdaptiveTrainingService.effectiveTasks(
        planId: planId,
      );
      if (BodyWeightRecord.dateKey(DateTime.now()) !=
              BodyWeightRecord.dateKey(now) ||
          (includeWeight &&
              !await BodyWeightService.instance.unchanged(weightSnapshot!)) ||
          _planId != planId ||
          jsonEncode(fresh.map(_taskJson).toList()) != sourceFingerprint ||
          jsonEncode(await TrainingFeedbackService.all(planId: planId)) !=
              jsonEncode(feedback) ||
          jsonEncode(await _readActualKm()) != jsonEncode(actualSnapshot) ||
          TrainingRunSummary(
                await RunDatabase.instance.listRuns(),
                now,
              ).fingerprint !=
              runSummary.fingerprint) {
        throw StateError('训练数据已变化，请重新生成调整方案');
      }
      await TrainingPlanCatalog.applyFutureRevision(
        planId: planId,
        expectedRevision: revision,
        tasks: (draft.plan['tasks'] as List).cast<Map<String, dynamic>>(),
        now: DateTime.now(),
        completedSnapshot: completed,
        expectedFeedbackSnapshot: feedback,
        reason: draft.summary,
      );
      if (mounted) setState(() => _tasks = _loadPlan());
      if (await TrainingReminderService.enabled()) {
        final time = await TrainingReminderService.time();
        try {
          await TrainingReminderService.configure(
            enabled: true,
            hour: time.$1,
            minute: time.$2,
          );
        } catch (error) {
          if (mounted) showAppToast(context, '计划已保存，但提醒同步失败，请重新设置：$error');
          return;
        }
      }
      if (mounted) showAppToast(context, '已保存 AI 调整方案');
    } catch (error) {
      if (mounted && request == _aiRequest) {
        showAppToast(context, 'AI 调整未完成：$error');
      }
    } finally {
      if (mounted && request == _aiRequest) {
        setState(() {
          _aiBusy = false;
          _aiWaiting = false;
        });
      }
    }
  }

  static Future<bool> _completionUnchanged(
    String planId,
    Set<String> snapshot,
  ) async {
    final current = await MarathonTrainingService.completed(planId: planId);
    return current.length == snapshot.length && current.containsAll(snapshot);
  }

  static Future<Map<String, double>> _readActualKm() async {
    final runs = await RunDatabase.instance.listRuns();
    return TrainingRunResults.aggregate(runs);
  }

  static Map<String, dynamic> _taskJson(TrainingTask t) => {
    'date': t.date,
    'type': t.type,
    'title': t.title,
    'km': t.km,
    'notes': t.notes,
    if (t.easyPace != null) 'easyPace': t.easyPace,
    if (t.slowPace != null) 'slowPace': t.slowPace,
  };

  Future<void> _suggestAdjustments() async {
    if (_aiBusy || _planBusy || _reminderBusy) return;
    setState(() => _aiBusy = true);
    try {
      final actualSnapshot = await _readActualKm();
      final proposal = await AdaptiveTrainingService.suggest(
        now: DateTime.now(),
        actualKm: actualSnapshot,
      );
      if (!mounted) return;
      if (proposal == null) {
        showAppToast(context, '暂无有充分依据的下调建议；缺少跑步记录不等于漏练');
        return;
      }
      final changes = (proposal['changes'] as List)
          .cast<Map<String, dynamic>>();
      final approved = await _showPlanDialog<bool>(
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
        if (jsonEncode(await _readActualKm()) != jsonEncode(actualSnapshot)) {
          throw StateError('跑步记录已变化，请重新生成建议');
        }
        await AdaptiveTrainingService.apply(proposal);
        if (mounted) setState(() => _tasks = _loadPlan());
        if (await TrainingReminderService.enabled()) {
          final time = await TrainingReminderService.time();
          try {
            await TrainingReminderService.configure(
              enabled: true,
              hour: time.$1,
              minute: time.$2,
            );
          } catch (error) {
            if (mounted) showAppToast(context, '计划已保存，但提醒同步失败，请重新设置：$error');
          }
        }
      } catch (e) {
        if (mounted) {
          showAppToast(context, '调整失败：$e');
        }
      }
    } catch (error) {
      if (mounted) showAppToast(context, '本地评估失败：$error');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _recordFeedback(TrainingTask task) async {
    if (_planBusy || _aiBusy) return;
    final owner = _planId;
    final old = _feedback[task.date];
    var pain = old?['pain'] ?? 0;
    var fatigue = old?['fatigue'] ?? 3;
    final submitted = await _showPlanDialog<bool>(
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
        planId: owner,
      );
      if (mounted && owner == _planId) {
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
    if (_planBusy || _aiBusy) return;
    final owner = _planId;
    try {
      await MarathonTrainingService.setComplete(
        task.date,
        value,
        planId: owner,
      );
      if (mounted && owner == _planId) {
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
            tooltip: '分享完整训练计划',
            icon: const Icon(Icons.ios_share),
            onPressed: _shareBusy || _planBusy || _aiBusy ? null : _sharePlan,
          ),
          if (_aiWaiting)
            TextButton(
              onPressed: () {
                setState(() {
                  ++_aiRequest;
                  _aiBusy = false;
                  _aiWaiting = false;
                });
                showAppToast(context, '已取消等待，迟到结果不会保存；已发出的服务请求可能仍计费');
              },
              child: const Text('取消等待'),
            ),
          IconButton(
            tooltip: '我的训练计划 · 添加赛事',
            icon: const Icon(Icons.playlist_add),
            onPressed: _planBusy || _aiBusy || _reminderBusy
                ? null
                : _managePlans,
          ),
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
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.orientationOf(context) == Orientation.landscape
                  ? 1600
                  : 680,
            ),
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
                              _tasks = _loadPlan();
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
                  key: ValueKey(_planId),
                  planName: _plan?['name'] as String? ?? '厦门马拉松',
                  goalSummary: _plan?['goalMinutes'] is num
                      ? '目标：${_plan!['goalMinutes']} 分钟（需结合训练评估）'
                      : (_plan?['goal'] == null
                            ? '目标：健康完赛，按恢复情况调整'
                            : '目标：${_plan!['goal']}'),
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
