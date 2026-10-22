import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/calendar.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../services/badges.dart';
import '../services/run_draft.dart';
import '../services/run_storage.dart';
import '../widgets/badges_card.dart';
import '../widgets/load_error_page.dart';
import '../widgets/common.dart';
import 'detail_page.dart';
import 'manual_entry_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onAvatarTap;
  final VoidCallback? onSeeAllTap;

  const HomePage({super.key, this.onAvatarTap, this.onSeeAllTap});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  (double, int, int)? _week;
  List<double>? _weekKm;
  List<RunRecord>? _recent;
  double _weeklyGoal = 20;
  RunDraft? _draft;
  bool _draftBusy = false;
  bool _loadError = false;
  int _loadVersion = 0;
  bool _unlockCheckBusy = false;

  @override
  void initState() {
    super.initState();
    load();
    AppData.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() => load();

  /// 安全进度：目标非法（0/负）或结果非有限值时返回 0，避免 NaN 传入环/进度条。
  double _safeRatio(double v, double goal) {
    if (goal <= 0 || !goal.isFinite || !v.isFinite) return 0;
    return (v / goal).clamp(0.0, 1.0);
  }

  Future<void> load() async {
    final version = ++_loadVersion;
    setState(() => _loadError = false);
    try {
      final db = RunDatabase.instance;
      // 并行查询，缩短首屏数据等待。
      final results = await Future.wait([
        Prefs.instance.load(),
        db.weekStats(),
        db.weeklyKm(),
        db.listRuns(limit: 3),
        RunDraft.load(),
        db.listRuns(),
      ]);
      final draft = results[4] as RunDraft?;
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _week = results[1] as (double, int, int);
        _weekKm = results[2] as List<double>;
        _recent = results[3] as List<RunRecord>;
        _weeklyGoal = Prefs.instance.weeklyGoalKm;
        _draft = draft != null && draft.recoverable ? draft : null;
      });
      // 全部记录用于徽章解锁检测（不阻塞首屏渲染）。
      unawaited(_checkBadgeUnlocks(results[5] as List<RunRecord>));
    } catch (_) {
      if (mounted && version == _loadVersion) setState(() => _loadError = true);
    }
  }

  /// 徽章解锁检测：新解锁的徽章弹一次庆祝弹窗并持久化。
  Future<void> _checkBadgeUnlocks(List<RunRecord> all) async {
    if (_unlockCheckBusy) return;
    _unlockCheckBusy = true;
    try {
      final badges = badgeContext(all);
      final current = unlockedBadges(badges);
      if (current.isEmpty) return;
      final stored = await loadStoredUnlocked();
      final fresh =
          current
              .difference(stored)
              .map(badgeById)
              .whereType<BadgeDef>()
              .toList()
            ..sort(
              (a, b) => badgeDefs.indexOf(a).compareTo(badgeDefs.indexOf(b)),
            );
      if (fresh.isEmpty) return;
      await storeUnlocked(current);
      if (!mounted) return;
      await showBadgeUnlockDialog(context, fresh);
    } on Object {
      // 解锁检测失败不影响首页功能。
    } finally {
      _unlockCheckBusy = false;
    }
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null || _draftBusy) return;
    setState(() => _draftBusy = true);
    try {
      await RunStorage.save(draft.record, draft.points);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败，请重试'.tr)));
    } finally {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  Future<void> _discardDraft() async {
    final draft = _draft;
    if (draft == null || _draftBusy) return;
    setState(() => _draftBusy = true);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('放弃未完成的记录？'.tr),
          content: Text('这条轨迹数据将被删除，无法恢复。'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('放弃'.tr),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await RunStorage.discard(draft.sessionKey);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('放弃失败，请重试'.tr)));
      }
    } finally {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  Future<void> _openManualEntry() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ManualEntryPage()));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    if (_loadError) return LoadErrorPage(onRetry: load);
    final c = context.colors;
    final week = _week;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          // 顶部避让随列表一起滚动，避免状态栏下方出现固定裁切边缘。
          top: false,
          bottom: false,
          child: ListView(
            // 底部留出悬浮标签栏高度，阻尼回弹滚动。
            physics: dampedPhysics,
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 8,
              20,
              110,
            ),
            children: [
              _header(c),
              const SizedBox(height: 16),
              if (_draft != null) ...[
                _draftCard(c),
                const SizedBox(height: 16),
              ],
              if (week != null) _heroCard(c, week.$1, week.$2, week.$3),
              const SizedBox(height: 12),
              _manualEntryCard(c),
              const SizedBox(height: 12),
              if (_weekKm != null) _weekChart(c, _weekKm!),
              const SizedBox(height: 16),
              _recentSection(c),
            ],
          ),
        ),
      ),
    );
  }

  /// 手动补录入口（跑步机、忘带手机等无轨迹场景）。
  Widget _manualEntryCard(AppPalette c) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: _openManualEntry,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit_note_rounded, size: 18, color: c.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '手动补录'.tr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _header(AppPalette c) {
    final hour = DateTime.now().hour;
    final greet = hour < 11
        ? '早上好'.tr
        : hour < 14
        ? '中午好'.tr
        : hour < 19
        ? '下午好'.tr
        : '晚上好'.tr;
    final editorial = c.isEditorial;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (editorial) ...[
                Text('RUN', style: kickerStyle(c)),
                const SizedBox(height: 2),
              ],
              Text(
                '$greet${'，'.tr}${'跑者'.tr}',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                '跑迹 RunTrail',
                style: TextStyle(
                  fontFamily: editorial ? 'Playfair Display' : null,
                  fontFamilyFallback: editorial ? const ['Noto Sans SC'] : null,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onAvatarTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: editorial ? Colors.transparent : c.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: c.stroke),
            ),
            child: Icon(Icons.person_outline, size: 20, color: c.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _heroCard(AppPalette c, double km, int seconds, int count) {
    final editorial = c.isEditorial;
    final isDark = c.isDark;
    final Decoration heroDecoration;
    if (editorial) {
      heroDecoration = BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.stroke),
      );
    } else if (isDark) {
      // 夜间：深色卡 + 描边（高燃运动风），圆角与其余卡片统一。
      heroDecoration = BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.stroke),
      );
    } else {
      // 白天：靛蓝→天蓝三色渐变。
      heroDecoration = BoxDecoration(
        gradient: heroGradient(c),
        borderRadius: BorderRadius.circular(AppRadius.md),
      );
    }
    final Widget card = Container(
      padding: const EdgeInsets.all(20),
      decoration: heroDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (editorial)
                Text('WEEK · ${'本周里程'.tr}', style: kickerStyle(c, size: 11))
              else if (isDark)
                Text(
                  '本周里程'.tr,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: c.accentDeep,
                  ),
                )
              else
                Text(
                  '本周里程'.tr,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: c.onAccent2,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: !editorial && !isDark
                      ? c.heroChip
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: editorial ? Border.all(color: c.stroke) : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      size: 12,
                      color: isDark
                          ? c.textMuted
                          : editorial
                          ? c.textSecondary
                          : c.onAccent2,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${'目标'.tr} ${Prefs.formatGoal(_weeklyGoal)} km',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? c.accentDeep
                            : editorial
                            ? c.textSecondary
                            : c.onAccent2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  km.toStringAsFixed(1),
                  style: TextStyle(
                    fontFamily: editorial
                        ? 'Playfair Display'
                        : isDark
                        ? 'Barlow Condensed'
                        : null,
                    fontSize: editorial ? 52 : (isDark ? 80 : 64),
                    fontWeight: FontWeight.bold,
                    fontStyle: !editorial && isDark ? FontStyle.italic : null,
                    letterSpacing: editorial ? 0 : (isDark ? 0 : -2),
                    color: editorial
                        ? c.textPrimary
                        : isDark
                        ? c.accent
                        : Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'km',
                    style: TextStyle(
                      fontFamily: !editorial && isDark
                          ? 'Barlow Condensed'
                          : null,
                      fontSize: editorial ? 17 : (isDark ? 22 : 17),
                      fontWeight: FontWeight.w600,
                      color: editorial
                          ? c.textSecondary
                          : isDark
                          ? c.textPrimary
                          : c.onAccent2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 白天：进度条隐藏，用环形指标；夜间/编辑风：进度条。
          if (!isDark)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GradientProgress(
                value: _safeRatio(km, _weeklyGoal),
                trackColor: c.progressTrack,
                fillColor: editorial ? null : c.onAccent,
              ),
            ),
          if (isDark)
            Row(
              children: [
                _darkMini(
                  c,
                  Icons.timer_outlined,
                  '时长'.tr,
                  formatDuration(Duration(seconds: seconds)),
                ),
                _darkMini(c, Icons.directions_run, '次数'.tr, '$count ${'次'.tr}'),
                _darkMini(
                  c,
                  Icons.local_fire_department_outlined,
                  '消耗'.tr,
                  '${(km * 65 * 1.036).round()} kcal',
                ),
              ],
            )
          else if (!editorial)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RingMetric(
                  progress: _safeRatio(km, _weeklyGoal),
                  value: '${(_safeRatio(km, _weeklyGoal) * 100).round()}%',
                  label: '周目标'.tr,
                  ringColor: Colors.white,
                  trackColor: scaleAlpha(Colors.white, 0.22),
                ),
                RingMetric(
                  progress: _safeRatio(seconds.toDouble(), 3600),
                  value: formatDuration(Duration(seconds: seconds)),
                  label: '时长'.tr,
                  ringColor: c.ringA,
                  trackColor: scaleAlpha(Colors.white, 0.14),
                ),
                RingMetric(
                  // 卡路里目标跟随周目标（每公里约 67 kcal），不再固定 1200。
                  progress: _safeRatio(km * 65 * 1.036, _weeklyGoal * 67),
                  value: '${(km * 65 * 1.036).round()}',
                  label: '千卡'.tr,
                  ringColor: c.ringB,
                  trackColor: scaleAlpha(Colors.white, 0.14),
                ),
              ],
            )
          else
            Row(
              children: [
                _mini(
                  c,
                  Icons.timer_outlined,
                  '时长'.tr,
                  formatDuration(Duration(seconds: seconds)),
                ),
                const SizedBox(width: 10),
                _mini(c, Icons.directions_run, '次数'.tr, '$count ${'次'.tr}'),
                const SizedBox(width: 10),
                _mini(
                  c,
                  Icons.local_fire_department_outlined,
                  '消耗'.tr,
                  '${(km * 65 * 1.036).round()} kcal',
                ),
              ],
            ),
        ],
      ),
    );
    // 白天：右上角装饰圆弧（原型 Hero Top Right Arc，溢出部分裁切）。
    // 半透明圆弧叠画在卡片之上——若垫在卡片下面会被不透明渐变底盖住。
    if (!editorial && !isDark) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            card,
            Positioned(
              top: -92,
              right: -52,
              child: Container(
                width: 200,
                height: 200,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x45C1B8FF), Color(0x33B7D4F0)],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return card;
  }

  /// 上次跑步未正常结束（进程被杀）时显示的恢复卡。
  Widget _draftCard(AppPalette c) {
    final draft = _draft!;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.restore_rounded, size: 18, color: c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '有一次未保存的跑步'.tr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(draft.distanceM / 1000).toStringAsFixed(2)} km · '
                  '${formatDuration(Duration(milliseconds: draft.elapsedMs))}',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _draftBusy ? null : _discardDraft,
            child: Text(
              '放弃'.tr,
              style: TextStyle(fontSize: 12, color: c.danger),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: _draftBusy ? null : _saveDraft,
            child: Text('保存'.tr, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 夜间 Hero 迷你统计：图标 + 标签一行、数值一行（无边框盒子）。
  Widget _darkMini(AppPalette c, IconData icon, String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: c.textMuted),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 10, color: c.textMuted)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(AppPalette c, IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: c.isEditorial
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: c.stroke),
              )
            : BoxDecoration(
                color: c.heroChip,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: c.isEditorial ? c.textSecondary : c.onAccent2,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: c.isEditorial ? c.textSecondary : c.onAccent2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.isEditorial ? c.textPrimary : c.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _days = ['一', '二', '三', '四', '五', '六', '日'];

  Widget _weekChart(AppPalette c, List<double> km) {
    final maxKm = km.fold(0.01, math.max);
    final todayIdx = DateTime.now().weekday - 1;
    final isDark = c.isDark;
    final barRadius = isDark ? 4.0 : 6.0;
    return AppCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '本周活动'.tr,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '公里'.tr,
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, v) in km.indexed)
                Column(
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: v <= 0
                            ? 5.0
                            : (v / maxKm * 76).clamp(10, 76).toDouble(),
                      ),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (_, h, child) => Container(
                        width: 18,
                        height: h,
                        decoration: BoxDecoration(
                          // 原型：柱体统一色（白天 #8B89E8 / 夜间 #FF8F6E），
                          // 仅编辑风高亮当日柱为荧光绿。
                          color: v <= 0
                              ? c.surface2
                              : c.isEditorial && i == todayIdx
                              ? c.accent
                              : c.barColor,
                          borderRadius: BorderRadius.circular(barRadius),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _days[i].tr,
                      style: TextStyle(
                        fontSize: 10,
                        color: i == todayIdx ? c.accent : c.textMuted,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recentSection(AppPalette c) {
    final runs = _recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '最近跑步'.tr,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            InkWell(
              onTap: widget.onSeeAllTap,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '全部'.tr,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: c.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (runs == null)
          Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          )
        else if (runs.isEmpty)
          AppCard(
            child: Center(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.directions_run, size: 36, color: c.textMuted),
                  const SizedBox(height: 10),
                  Text(
                    '还没有跑步记录\n点击下方按钮开始第一次跑步吧'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            radius: AppRadius.md,
            child: Column(
              children: [
                for (final (i, r) in runs.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.divider),
                  _runRow(c, r),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _runRow(AppPalette c, RunRecord r) {
    final editorial = c.isEditorial;
    final title = r.displayTitle;
    return InkWell(
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => DetailPage(record: r))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // 编辑风：3px 荧光绿圆点；其余主题：圆形图标底。
            if (editorial)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 17),
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  r.isManual ? Icons.edit_note_rounded : _dayIcon(r.start),
                  size: 17,
                  color: c.accent,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? formatRunTime(r.start) : title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${'配速'.tr} ${formatPace(r.avgPaceSecPerKm)}  ·  ${formatDuration(Duration(seconds: r.durationS))}',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              '${r.distanceKm.toStringAsFixed(2)} km',
              style: TextStyle(
                fontFamily: editorial ? 'Playfair Display' : null,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _dayIcon(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 8) return Icons.wb_twilight;
  if (h >= 8 && h < 17) return Icons.wb_sunny_outlined;
  if (h >= 17 && h < 20) return Icons.nights_stay_outlined;
  return Icons.dark_mode_outlined;
}

String formatRunTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = Calendar.daysBetween(today, day);
  final hh =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return '${'今天'.tr} $hh';
  if (diff == 1) return '${'昨天'.tr} $hh';
  if (LocaleController.instance.isEnglish) {
    return '${enMonthAbbr[t.month - 1]} ${t.day}, $hh';
  }
  return '${t.month}月${t.day}日 $hh';
}
