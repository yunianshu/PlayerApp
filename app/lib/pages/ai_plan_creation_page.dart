import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/ai_plan_design.dart';

import '../services/ai_coach_settings.dart';
import '../services/ai_plan_generator.dart';
import '../services/training_plan_catalog.dart';
import '../widgets/app_toast.dart';
import 'ai_coach_settings_page.dart';

typedef PlanGenerationAction = Future<AiPlanDraft> Function(
  GenericTrainingRequest request,
  AiCoachSettings settings,
);

/// Generation is explicit and only a confirmed draft is persisted. It never
/// activates a new plan or modifies an existing plan's reminders or history.
class AiPlanCreationPage extends StatefulWidget {
  const AiPlanCreationPage({
    super.key,
    this.now,
    this.loadSettings,
    this.generate,
    this.saveDraft,
  });
  final DateTime? now;
  final Future<AiCoachSettings> Function()? loadSettings;
  final PlanGenerationAction? generate;
  final Future<void> Function(Map<String, dynamic>)? saveDraft;

  @override
  State<AiPlanCreationPage> createState() => _AiPlanCreationPageState();
}

class _AiPlanCreationPageState extends State<AiPlanCreationPage> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  int _step = 0;
  final _name = TextEditingController();
  final _weekly = TextEditingController();
  final _longest = TextEditingController();
  final _tenKm = TextEditingController();
  final _goalHours = TextEditingController();
  final _goalMinutes = TextEditingController();
  final _weekdays = <int>{2, 4, 7};
  late final DateTime _start;
  DateTime? _race;
  bool _timeGoal = false;
  String _recovery = 'good';
  bool _busy = false;
  bool _saving = false;
  int _generation = 0;
  AiPlanDraft? _draft;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _generation++;
    for (final controller in [
      _name,
      _weekly,
      _longest,
      _tenKm,
      _goalHours,
      _goalMinutes,
    ]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String? _number(String? value, {bool optional = false}) {
    if (optional && (value ?? '').trim().isEmpty) return null;
    final n = double.tryParse(value ?? '');
    return n == null || !n.isFinite || n < 0 ? '请输入有效的非负数字' : null;
  }

  Future<void> _pickRace() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _race ?? _start.add(const Duration(days: 112)),
      firstDate: _start.add(const Duration(days: 28)),
      lastDate: _start.add(const Duration(days: 365)),
      helpText: '选择马拉松比赛日期',
      builder: (ctx, child) =>
          Theme(data: PlanDesign.theme(context), child: child!),
    );
    if (date != null && mounted) setState(() => _race = date);
  }

  Future<void> _generate() async {
    if (_busy || _saving || !_form.currentState!.validate()) return;
    if (_race == null) {
      showAppToast(context, '请选择比赛日期');
      return;
    }
    GenericTrainingRequest request;
    try {
      final hours = _goalHours.text.trim().isEmpty
          ? 0
          : int.tryParse(_goalHours.text);
      final minutes = _goalMinutes.text.trim().isEmpty
          ? 0
          : int.tryParse(_goalMinutes.text);
      if (_timeGoal && (hours == null || minutes == null)) {
        throw const FormatException('目标时间必须使用整数小时和分钟');
      }
      if (_timeGoal &&
          ((hours ?? 0) < 0 ||
              (minutes ?? 0) < 0 ||
              (minutes ?? 0) > 59 ||
              (hours ?? 0) * 60 + (minutes ?? 0) == 0)) {
        throw const FormatException('目标时间请填写有效小时和 0–59 分钟');
      }
      request = GenericTrainingRequest(
        raceName: _name.text.trim(),
        startDate: _start,
        raceDate: _race!,
        goalMinutes: _timeGoal ? (hours ?? 0) * 60 + (minutes ?? 0) : null,
        weeklyKm: double.parse(_weekly.text),
        longestRunKm: double.parse(_longest.text),
        recent10kMinutes: _tenKm.text.trim().isEmpty
            ? null
            : double.parse(_tenKm.text),
        trainingWeekdays: Set<int>.of(_weekdays),
        recovery: _recovery,
      );
      request.validate();
    } catch (error) {
      showAppToast(context, error.toString());
      return;
    }
    setState(() => _busy = true);
    final generation = ++_generation;
    try {
      var settings =
          await (widget.loadSettings?.call() ??
              AiCoachSettingsStore.instance.load());
      if (!mounted || generation != _generation) return;
      if (!settings.ready) {
        final configure = await showDialog<bool>(
          context: context,
          builder: (ctx) => Theme(
            data: PlanDesign.theme(context),
            child: AlertDialog(
              title: const Text('先配置 AI 服务'),
              content: const Text('新建计划需要模型服务地址、模型和 API Key。未配置时不会发送训练信息。'),
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
          ),
        );
        if (configure != true || !mounted || generation != _generation) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const AiCoachSettingsPage()),
        );
        settings =
            await (widget.loadSettings?.call() ??
                AiCoachSettingsStore.instance.load());
        if (!mounted || generation != _generation || !settings.ready) return;
      }
      final config = settings.config!;
      final consent = await showDialog<bool>(
        context: context,
        builder: (ctx) => Theme(
          data: PlanDesign.theme(context),
          child: AlertDialog(
            title: const Text('确认发送并生成计划'),
            content: SingleChildScrollView(
              child: Text(
                '服务地址：${config.endpoint}\n模型：${config.model}\n\n'
                '将发送你填写的赛事名称、开始和比赛日期、目标成绩、近期周跑量、最长跑距、10 公里成绩（若填写）、可训练日和恢复状态。API Key 也会发送到该地址用于认证。\n\n'
                '不发送 GPS 轨迹、姓名或其他训练记录。恢复状态属于健康相关信息，请仅向你信任的服务商发送；服务商可能收取费用。\n\n'
                'AI 计划需通过本地规则校验并由你确认后保存，不保证完赛或成绩，不替代医生或教练建议。',
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
      if (consent != true || !mounted || generation != _generation) return;
      final draft =
          await (widget.generate?.call(request, settings) ??
              AiPlanGenerator.generate(
                request: request,
                config: config,
                apiKey: settings.apiKey!,
              ));
      if (!mounted || generation != _generation) return;
      final currentSettings =
          await (widget.loadSettings?.call() ??
              AiCoachSettingsStore.instance.load());
      if (!mounted || generation != _generation) return;
      if (currentSettings.config?.endpoint != config.endpoint ||
          currentSettings.config?.model != config.model ||
          currentSettings.apiKey != settings.apiKey) {
        throw StateError('AI 服务配置已变化，请重新确认并生成计划');
      }
      setState(() => _draft = draft);
      _scrollToTop();
    } catch (error) {
      if (mounted && generation == _generation) {
        showAppToast(context, '计划生成失败，未保存或更改原计划：$error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await (widget.saveDraft?.call(_draft!.plan) ??
          TrainingPlanCatalog.addDraft(_draft!.plan));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showAppToast(context, '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  AppPalette get _p => PlanDesign.of(context).palette;

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 240);

  Widget _hero(String eyebrow, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: PlanHero(eyebrow: eyebrow, title: title, subtitle: subtitle),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: _p.surface2,
    labelStyle: TextStyle(color: _p.textSecondary),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: _p.stroke),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: _p.stroke),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(
        color: _p.isEditorial ? _p.textPrimary : _p.accent,
        width: 2,
      ),
    ),
  );

  Widget _field(
    String key,
    String label,
    TextEditingController controller, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: Key(key),
      controller: controller,
      style: TextStyle(
        fontFamily: 'Noto Sans SC',
        fontSize: key == 'plan-weekly' ? 42 : 24,
        fontWeight: FontWeight.w600,
        color: _p.textPrimary,
      ),
      decoration: _decoration(label).copyWith(
        filled: false,
        border: UnderlineInputBorder(borderSide: BorderSide(color: _p.stroke)),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _p.stroke),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) => _number(value, optional: optional),
    ),
  );

  Widget _responsivePair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 480 &&
          MediaQuery.textScalerOf(context).scale(16) < 25;
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: first),
                const SizedBox(width: 14),
                Expanded(child: second),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, second],
            );
    },
  );

  void _nextStep() {
    if (!_form.currentState!.validate()) return;
    if (_step == 0 && _race == null) {
      showAppToast(context, '请选择比赛日期');
      return;
    }
    if (_step == 0 && _timeGoal) {
      final h = int.tryParse(_goalHours.text.isEmpty ? '0' : _goalHours.text);
      final m = int.tryParse(
        _goalMinutes.text.isEmpty ? '0' : _goalMinutes.text,
      );
      if (h == null ||
          m == null ||
          h < 0 ||
          m < 0 ||
          m > 59 ||
          h * 60 + m < 120 ||
          h * 60 + m > 600) {
        showAppToast(context, '目标成绩请填写 2–10 小时内的有效用时');
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step++);
    _scrollToTop();
  }

  void _previousStep() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step--);
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Noto Sans SC',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.35,
            color: _p.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: _p.textSecondary, height: 1.5)),
      ],
    ),
  );

  Widget _inputs() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(
            3,
            (index) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: index == _step
                    ? (_p.isEditorial ? _p.accent : _p.accentSoft)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${index + 1}  ${const ['目标赛事', '当前能力', '训练节奏'][index]}',
                style: TextStyle(
                  fontFamily: 'Noto Sans SC',
                  fontWeight: index == _step
                      ? FontWeight.w700
                      : FontWeight.normal,
                  color: index == _step ? _p.textPrimary : _p.textSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle(
          const ['下一场，跑向哪里？', '先从你现在的\n跑步基础出发。', '把训练放进\n你的生活节奏。'][_step],
          const [
            '选择赛事与目标，能力会在下一步单独评估。',
            '填最近 4 周的真实情况，而不是理想状态。',
            '选择通常有时间训练的日期，其他日期留给恢复。',
          ][_step],
        ),
        if (_step > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                Icon(Icons.flag_outlined, size: 18, color: _p.textSecondary),
                Text(
                  _name.text,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _p.textPrimary,
                  ),
                ),
                Text(_date(_race!), style: TextStyle(color: _p.textSecondary)),
              ],
            ),
          ),
        if (_step == 0) ..._raceFields(),
        if (_step == 1) ..._abilityFields(),
        if (_step == 2) ..._rhythmFields(),
      ],
    ),
  );

  List<Widget> _raceFields() => [
    TextFormField(
      key: const Key('plan-name'),
      controller: _name,
      maxLength: 80,
      decoration: _decoration('赛事名称'),
      validator: (v) => (v ?? '').trim().isEmpty ? '请输入赛事名称' : null,
    ),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      key: const Key('plan-race-date'),
      onPressed: _pickRace,
      icon: const Icon(Icons.calendar_month_rounded),
      label: Text(_race == null ? '选择比赛日期' : _date(_race!)),
    ),
    const SizedBox(height: 8),
    Text(
      '从 ${_date(_start)} 开始 · 28–365 天备赛范围',
      style: TextStyle(color: _p.textSecondary),
    ),
    const SizedBox(height: 18),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _goalChoice(false, '以完赛为目标', Icons.flag_outlined),
        _goalChoice(true, '设置目标成绩', Icons.timer_outlined),
      ],
    ),
    AnimatedSize(
      duration: _motion,
      alignment: Alignment.topCenter,
      child: _timeGoal
          ? Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _responsivePair(
                _field('plan-goal-hours', '目标小时', _goalHours),
                _field('plan-goal-minutes', '剩余分钟', _goalMinutes),
              ),
            )
          : const SizedBox(height: 10),
    ),
    Text(
      '目标是规划依据，不代表对成绩或完赛的承诺。',
      style: TextStyle(color: _p.textSecondary, height: 1.5),
    ),
  ];
  List<Widget> _abilityFields() => [
    _responsivePair(
      _field('plan-weekly', '平均周跑量 · km', _weekly),
      _field('plan-longest', '最长单次跑距 · km', _longest),
    ),
    _field('plan-ten-km', '近期 10 km 用时 · 分钟（可选）', _tenKm, optional: true),
    DropdownButtonFormField<String>(
      key: const Key('plan-recovery'),
      initialValue: _recovery,
      isExpanded: true,
      decoration: _decoration('当前恢复情况'),
      items: const [
        DropdownMenuItem(value: 'good', child: Text('恢复良好')),
        DropdownMenuItem(value: 'tired', child: Text('疲劳偏高')),
        DropdownMenuItem(value: 'pain', child: Text('有疼痛或伤病')),
      ],
      onChanged: (v) => setState(() => _recovery = v!),
    ),
    const SizedBox(height: 12),
    Text(
      _recovery == 'pain'
          ? '疼痛或伤病期间不自动生成跑步处方，请先评估恢复状况。'
          : _recovery == 'tired'
          ? '疲劳偏高时会降低起始负荷，优先安排恢复。'
          : '不确定配速也没关系，计划可采用体感强度指导。',
      style: TextStyle(
        color: _recovery == 'pain' ? _p.danger : _p.textSecondary,
        height: 1.5,
      ),
    ),
  ];
  List<Widget> _rhythmFields() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        final day = index + 1;
        return FilterChip(
          backgroundColor: _p.surface,
          selectedColor: Color.alphaBlend(
            (_p.isEditorial ? _p.textPrimary : _p.accent).withValues(
              alpha: .12,
            ),
            _p.surface,
          ),
          side: BorderSide(color: _p.stroke),
          checkmarkColor: _p.textPrimary,
          labelStyle: TextStyle(
            color: _p.textPrimary,
            fontFamily: 'Noto Sans SC',
          ),
          surfaceTintColor: Colors.transparent,
          label: Text(const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][index]),
          selected: _weekdays.contains(day),
          onSelected: (selected) => setState(() {
            selected ? _weekdays.add(day) : _weekdays.remove(day);
          }),
        );
      }),
    ),
    const SizedBox(height: 14),
    Text(
      '已选 ${_weekdays.length} 天 / 周 · 比赛日单独安排',
      style: TextStyle(color: _p.textSecondary),
    ),

    const SizedBox(height: 24),
    _notice(
      '发送前由你确认',
      'AI 将结合赛事目标、近期训练和恢复情况规划每日安排。下一步会先列出接收服务与发送的数据，未经同意不会发送。',
      Icons.lock_outline,
    ),
  ];
  Widget _goalChoice(bool value, String label, IconData icon) => ChoiceChip(
    selected: _timeGoal == value,
    showCheckmark: false,
    onSelected: (_) => setState(() => _timeGoal = value),
    backgroundColor: _p.surface,
    selectedColor: Color.alphaBlend(
      (_p.isEditorial ? _p.textPrimary : _p.accent).withValues(alpha: .12),
      _p.surface,
    ),
    side: BorderSide(color: _p.stroke),
    surfaceTintColor: Colors.transparent,
    avatar: Icon(icon, size: 18, color: _p.textPrimary),
    label: Text(
      label,
      style: TextStyle(color: _p.textPrimary, fontFamily: 'Noto Sans SC'),
    ),
  );

  Widget _notice(String title, String body, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _p.surface2,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: _p.stroke),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _p.textPrimary),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, color: _p.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(body, style: TextStyle(color: _p.textSecondary, height: 1.5)),
      ],
    ),
  );

  Widget _preview() {
    final draft = _draft!;
    final tasks = (draft.plan['tasks'] as List).cast<Map<String, dynamic>>();
    final weeks = <List<Map<String, dynamic>>>[
      for (var i = 0; i < tasks.length; i += 7)
        tasks.sublist(i, (i + 7).clamp(0, tasks.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AI 计划预览 · 尚未保存',
          style: TextStyle(color: _p.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Text(
          '${draft.plan['name']}',
          style: TextStyle(
            fontFamily: 'Noto Sans SC',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _p.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '比赛日期 ${draft.plan['raceDate']} · 共 ${tasks.length} 天逐日安排',
          style: TextStyle(color: _p.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        _reviewPair(
          _reviewMetric('你设定的目标', _goal(draft.plan['goalMinutes'])),
          _reviewMetric('首周跑量', '${_weeklyKm(weeks.first)} km'),
        ),
        const SizedBox(height: 12),
        Text(
          'AI 建议目标：${_goal(draft.plan['recommendedGoalMinutes'], recommendation: true)}',
          style: TextStyle(color: _p.textSecondary, height: 1.5),
        ),
        _rule(),
        Text(
          '每周跑量，一眼看清',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _p.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '共 ${weeks.length} 周 · 按计划起点每 7 天汇总，不含比赛跑量',
          style: TextStyle(color: _p.textSecondary, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 12),
        _weeklyChart(weeks),
        const SizedBox(height: 6),
        Text(
          '可横向滑动查看各周。图表表示计划跑量，不代表能力达标。',
          style: TextStyle(color: _p.textSecondary, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 18),
        if (draft.warnings.isNotEmpty)
          _notice(
            '请先阅读 · 风险与边界',
            draft.warnings
                .asMap()
                .entries
                .map((e) => '${e.key + 1}. ${e.value}')
                .join('\n\n'),
            Icons.info_outline,
          ),
        _rule(),
        Text(
          '从第一周开始',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _p.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        _week(weeks.first, 0),
        if (weeks.length > 1) ...[
          const SizedBox(height: 16),
          Text(
            '接下来的安排',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _p.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 1; i < weeks.length; i++) _week(weeks[i], i),
        ],
        _rule(),
        Text(
          '为什么这样安排',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _p.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          draft.summary,
          style: TextStyle(color: _p.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 18),
        const SizedBox(height: 14),
        _notice(
          '只新增，不覆盖',
          '确认保存只新增计划，不会切换当前计划或覆盖厦马记录。',
          Icons.verified_user_outlined,
        ),
      ],
    );
  }

  Widget _reviewPair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, c) {
      return c.maxWidth >= 340 &&
              MediaQuery.textScalerOf(context).scale(16) < 24
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: first),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: second),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 12), second],
            );
    },
  );
  Widget _reviewMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: _p.textSecondary, fontSize: 12)),
      const SizedBox(height: 6),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'Noto Sans SC',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: _p.textPrimary,
        ),
      ),
    ],
  );
  Widget _rule() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Divider(height: 1, color: _p.stroke),
  );
  Widget _week(List<Map<String, dynamic>> days, int index) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: _p.stroke)),
    ),
    child: ExpansionTile(
      key: Key('plan-week-$index'),
      initiallyExpanded: index == 0,
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      textColor: _p.textPrimary,
      collapsedTextColor: _p.textPrimary,
      iconColor: _p.textSecondary,
      collapsedIconColor: _p.textSecondary,
      title: Text(
        '第 ${index + 1} 周 · ${_weeklyKm(days)} km',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${days.first['date']} — ${days.last['date']}',
        style: TextStyle(color: _p.textSecondary),
      ),
      children: [for (final day in days) _dayCard(day)],
    ),
  );
  Widget _weeklyChart(List<List<Map<String, dynamic>>> weeks) {
    final sums = weeks
        .map(
          (days) => days
              .where((t) => t['type'] != 'RACE')
              .fold<double>(0, (sum, t) => sum + (t['km'] as num).toDouble()),
        )
        .toList();
    final maximum = sums.fold<double>(1, (a, b) => a > b ? a : b);
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return SizedBox(
      height: 156 + 36 * scale,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < sums.length; i++)
              Semantics(
                label: '第 ${i + 1} 周，${sums[i].toStringAsFixed(1)} 公里',
                excludeSemantics: true,
                child: Container(
                  width: 48 * scale,
                  margin: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        sums[i].toStringAsFixed(1),
                        style: TextStyle(fontSize: 11, color: _p.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: _motion,
                        height: 100 * sums[i] / maximum + 2,
                        width: 24,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? (_p.isEditorial ? _p.textPrimary : _p.accent)
                              : _p.accentSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: 12, color: _p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _weeklyKm(List<Map<String, dynamic>> days) => days
      .fold<double>(0, (sum, t) => sum + (t['km'] as num).toDouble())
      .toStringAsFixed(1);
  Widget _dayCard(Map<String, dynamic> t) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _p.surface2,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${t['date']} · ${_sessionLabel(t['type'] as String)}',
          style: TextStyle(fontWeight: FontWeight.w700, color: _p.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          '${t['title']} · ${t['km']} km',
          style: TextStyle(color: _p.textPrimary),
        ),
        if (t['easyPace'] is int && t['slowPace'] is int)
          Text(
            '配速 ${_pace(t['easyPace'] as int)}–${_pace(t['slowPace'] as int)} /km',
            style: TextStyle(color: _p.textSecondary),
          ),
        const SizedBox(height: 4),
        Text(
          t['notes'] as String? ?? '',
          style: TextStyle(color: _p.textSecondary, height: 1.5),
        ),
      ],
    ),
  );

  String _goal(dynamic minutes, {bool recommendation = false}) => minutes is int
      ? '${minutes ~/ 60} 小时 ${minutes % 60} 分钟（非成绩承诺）'
      : recommendation
      ? '暂不设成绩，需结合训练再评估'
      : '完成比赛，不设成绩目标';

  String _sessionLabel(String type) => switch (type.toUpperCase()) {
    'REST' => '恢复休息',
    'EASY' => '轻松跑',
    'LONG' => '长距离跑',
    'TEMPO' => '节奏跑',
    'INTERVAL' => '间歇跑',
    'STRENGTH' => '力量训练',
    'RACE' => '比赛日',
    _ => '训练',
  };

  String _pace(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Theme(
    data: PlanDesign.theme(context),
    child: PopScope(
      canPop: _busy || _draft != null || _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy && _draft == null && _step > 0) _previousStep();
      },
      child: Scaffold(
        backgroundColor: _p.bg,
        appBar: AppBar(
          title: Text(_draft == null ? '新建训练计划' : '审阅训练计划'),
          leading: !_busy && _draft == null && _step > 0
              ? IconButton(
                  onPressed: _previousStep,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '上一步',
                )
              : null,
        ),
        bottomNavigationBar: _busy
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  decoration: BoxDecoration(
                    color: _p.bg,
                    border: Border(top: BorderSide(color: _p.stroke)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_draft != null) ...[
                        FilledButton(
                          key: const Key('plan-save'),
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? '保存中…' : '确认保存计划'),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() => _draft = null);
                                  _scrollToTop();
                                },
                          child: const Text('返回修改，不保存'),
                        ),
                      ] else ...[
                        FilledButton(
                          key: Key(_step == 2 ? 'plan-generate' : 'plan-next'),
                          onPressed: _step == 2 ? _generate : _nextStep,
                          child: Text(
                            _step == 0
                                ? '下一步：评估当前能力'
                                : _step == 1
                                ? '下一步：安排训练日'
                                : 'AI 生成计划',
                          ),
                        ),
                        if (_step > 0)
                          TextButton(
                            key: const Key('plan-back'),
                            onPressed: _previousStep,
                            child: const Text('上一步'),
                          ),
                        if (_step == 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '发送给 AI 前，会先说明服务和数据范围',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
        body: SafeArea(
          child: _busy
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _hero('BUILDING YOUR PLAN', '正在规划下一程', '正在生成并校验计划…'),
                      if (!MediaQuery.disableAnimationsOf(context))
                        const LinearProgressIndicator(),
                      const SizedBox(height: 20),
                      _notice(
                        '日期 → 负荷 → 恢复',
                        '逐项检查每日安排与训练边界。只有通过校验的结果才会进入预览。',
                        Icons.fact_check_outlined,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => setState(() {
                          _generation++;
                          _busy = false;
                        }),
                        child: const Text('取消等待'),
                      ),
                      Text(
                        '取消后不会保存迟到结果；已发送的服务请求可能仍会计费。',
                        style: TextStyle(color: _p.textSecondary),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [_draft == null ? _inputs() : _preview()],
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}
