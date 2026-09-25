import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../core/theme.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../services/run_draft.dart';
import '../widgets/common.dart';
import 'detail_page.dart';

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
    if (goal <= 0 || !v.isFinite) return 0;
    return (v / goal).clamp(0.0, 1.0);
  }

  Future<void> load() async {
    final db = RunDatabase.instance;
    // 并行查询，缩短首屏数据等待。
    final results = await Future.wait([
      Prefs.instance.load(),
      db.weekStats(),
      db.weeklyKm(),
      db.listRuns(limit: 3),
      RunDraft.load(),
    ]);
    final draft = results[4] as RunDraft?;
    // 无效草稿（轨迹太短）直接清掉，不打扰用户。
    if (draft != null && (draft.distanceM < 20 || draft.points.length < 2)) {
      unawaited(RunDraft.clear());
    }
    if (!mounted) return;
    setState(() {
      _week = results[1] as (double, int, int);
      _weekKm = results[2] as List<double>;
      _recent = results[3] as List<RunRecord>;
      _weeklyGoal = Prefs.instance.weeklyGoalKm;
      _draft = (draft != null && draft.distanceM >= 20) ? draft : null;
    });
  }

  Future<void> _saveDraft() async {
    final draft = _draft;
    if (draft == null) return;
    final km = draft.distanceM / 1000;
    final record = RunRecord(
      start: draft.start,
      end: draft.points.last.time,
      distanceM: draft.distanceM,
      durationS: (draft.elapsedMs / 1000).round(),
      calories: (km * 65 * 1.036).round(),
      climbM: draft.climbM,
    );
    try {
      await RunDatabase.instance.insertRun(record, draft.points);
      await RunDraft.clear();
      AppData.instance.bump();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  Future<void> _discardDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃未完成的记录？'),
        content: const Text('这条轨迹数据将被删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RunDraft.clear();
    AppData.instance.bump();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final week = _week;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            // 底部留出悬浮标签栏高度，阻尼回弹滚动。
            physics: dampedPhysics,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              _header(c),
              const SizedBox(height: 16),
              if (_draft != null) ...[
                _draftCard(c),
                const SizedBox(height: 16),
              ],
              if (week != null) _heroCard(c, week.$1, week.$2, week.$3),
              const SizedBox(height: 16),
              if (_weekKm != null) _weekChart(c, _weekKm!),
              const SizedBox(height: 16),
              _recentSection(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppPalette c) {
    final hour = DateTime.now().hour;
    final greet = hour < 11
        ? '早上好'
        : hour < 14
            ? '中午好'
            : hour < 19
                ? '下午好'
                : '晚上好';
    final editorial = c.isEditorial;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (editorial) ...[
              Text('RUN', style: kickerStyle(c)),
              const SizedBox(height: 2),
            ],
            Text(
              '$greet，跑者',
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.stroke),
      );
    } else if (isDark) {
      // 夜间：近方角深色卡 + 描边（高燃运动风）。
      heroDecoration = BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.stroke),
      );
    } else {
      // 白天：靛蓝→天蓝三色渐变。
      heroDecoration = BoxDecoration(
        gradient: heroGradient(c),
        borderRadius: BorderRadius.circular(28),
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
                Text('WEEK · 本周里程', style: kickerStyle(c, size: 11))
              else if (isDark)
                Text(
                  '本周里程',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: c.accentDeep,
                  ),
                )
              else
                Text(
                  '本周里程',
                  style: TextStyle(
                      fontSize: 11, letterSpacing: 0.5, color: c.onAccent2),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      !editorial && !isDark ? c.heroChip : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
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
                      '目标 ${_weeklyGoal.toStringAsFixed(0)} km',
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
          Row(
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
                    fontFamily:
                        !editorial && isDark ? 'Barlow Condensed' : null,
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
                _darkMini(c, Icons.timer_outlined, '时长',
                    formatDuration(Duration(seconds: seconds))),
                _darkMini(c, Icons.directions_run, '次数', '$count 次'),
                _darkMini(c, Icons.local_fire_department_outlined, '消耗',
                    '${(km * 65 * 1.036).round()} kcal'),
              ],
            )
          else if (!editorial)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RingMetric(
                  progress: _safeRatio(km, _weeklyGoal),
                  value: '${(_safeRatio(km, _weeklyGoal) * 100).round()}%',
                  label: '周目标',
                  ringColor: Colors.white,
                  trackColor: scaleAlpha(Colors.white, 0.22),
                ),
                RingMetric(
                  progress: _safeRatio(seconds.toDouble(), 3600),
                  value: formatDuration(Duration(seconds: seconds)),
                  label: '时长',
                  ringColor: c.ringA,
                  trackColor: scaleAlpha(Colors.white, 0.14),
                ),
                RingMetric(
                  // 卡路里目标跟随周目标（每公里约 67 kcal），不再固定 1200。
                  progress: _safeRatio(km * 65 * 1.036, _weeklyGoal * 67),
                  value: '${(km * 65 * 1.036).round()}',
                  label: '千卡',
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
                  '时长',
                  formatDuration(Duration(seconds: seconds)),
                ),
                const SizedBox(width: 10),
                _mini(c, Icons.directions_run, '次数', '$count 次'),
                const SizedBox(width: 10),
                _mini(
                  c,
                  Icons.local_fire_department_outlined,
                  '消耗',
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
        borderRadius: BorderRadius.circular(28),
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
                  '有一次未保存的跑步',
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
            onPressed: _discardDraft,
            child: Text('放弃', style: TextStyle(fontSize: 12, color: c.danger)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: _saveDraft,
            child: const Text('保存', style: TextStyle(fontSize: 12)),
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
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: c.textMuted),
                ),
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
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.stroke),
              )
            : BoxDecoration(
                color: c.heroChip,
                borderRadius: BorderRadius.circular(14),
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
                '本周活动',
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
                    '公里',
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
                      tween: Tween(begin: 0, end: v <= 0 ? 5.0 : (v / maxKm * 76).clamp(10, 76).toDouble()),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (_, h, __) => Container(
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
                      _days[i],
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
              '最近跑步',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            InkWell(
              onTap: widget.onSeeAllTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '全部',
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                      ),
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
                    '还没有跑步记录\n点击下方按钮开始第一次跑步吧',
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
            radius: 20,
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
    return InkWell(
      onTap: () => Navigator.of(context)
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
                child: Icon(_dayIcon(r.start), size: 17, color: c.accent),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatRunTime(r.start),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '配速 ${formatPace(r.avgPaceSecPerKm)}  ·  ${formatDuration(Duration(seconds: r.durationS))}',
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
  final diff = today.difference(day).inDays;
  final hh =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return '今天 $hh';
  if (diff == 1) return '昨天 $hh';
  return '${t.month}月${t.day}日 $hh';
}
