import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/calendar.dart';
import '../core/i18n.dart';
import '../widgets/load_error_page.dart';
import '../data/database.dart';
import '../services/app_data.dart';
import '../services/run_prs.dart';
import '../widgets/common.dart';

/// 数据统计：周/月/年切换 + 汇总卡 + 运动日历热力图 + 周趋势 + 个人纪录 + 月度对比。
/// 汇总/热力图/趋势均走 SQL 聚合查询，不再全量加载记录。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _segment = 1; // 0=周 1=月 2=年
  (double, int, int, double, double?)? _range;
  Map<DateTime, double> _days = const {};
  List<double> _trend = const [];
  int _streakDays = 0;
  double? _monthKm;
  double? _prevMonthKm;
  RunPrs? _prs;
  bool _loading = true;
  bool _loadError = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
    AppData.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() => _load();

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loadError = false;
      _loading = true;
    });
    try {
      final db = RunDatabase.instance;
      final now = DateTime.now();
      final today = Calendar.day(now);
      final monday = Calendar.monday(today);
      final (start, end) = switch (_segment) {
        0 => (monday, Calendar.addDays(monday, 7)),
        1 => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
        _ => (DateTime(now.year, 1), DateTime(now.year + 1, 1)),
      };
      // 热力图（28 天，周日结尾）与 8 周趋势共用一次区间查询。
      final sunday = Calendar.addDays(today, 7 - today.weekday);
      final heatmapStart = Calendar.addDays(sunday, -27);
      final trendStart = Calendar.addDays(monday, -49);
      final combinedStart = trendStart.isBefore(heatmapStart)
          ? trendStart
          : heatmapStart;
      final combinedEnd = Calendar.addDays(monday, 7);
      final monthIndex = now.month - 1;
      final results = await Future.wait([
        db.rangeStats(start, end),
        db.kmByDay(combinedStart, combinedEnd),
        db.kmByDay(Calendar.addDays(today, -400), combinedEnd),
        monthIndex > 0
            ? db.monthlyKm(now.year)
            : db
                  .monthlyKm(now.year)
                  .then(
                    (cur) => db
                        .monthlyKm(now.year - 1)
                        .then((prev) => [...cur, prev.last]),
                  ),
        RunPrService.instance.compute(),
      ]);
      if (!mounted || version != _loadVersion) return;
      final days = results[1] as Map<DateTime, double>;
      final longDays = results[2] as Map<DateTime, double>;
      final prevKm = monthIndex > 0
          ? (results[3] as List<double>)[monthIndex - 1]
          : (results[3] as List<double>)[12 - 1];
      setState(() {
        _range = results[0] as (double, int, int, double, double?);
        _days = days;
        _trend = _weeklyBuckets(days, monday);
        _streakDays = _streakFrom(longDays, today);
        _monthKm = (results[3] as List<double>)[monthIndex];
        _prevMonthKm = prevKm;
        _prs = results[4] as RunPrs;
        _loading = false;
      });
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loadError = true;
          _loading = false;
        });
      }
    }
  }

  /// 按自然周聚合 8 周的每日里程（最旧在前，当前周最后）。
  List<double> _weeklyBuckets(Map<DateTime, double> days, DateTime thisMonday) {
    final weeks = List<double>.filled(8, 0);
    for (final entry in days.entries) {
      final offset = Calendar.daysBetween(entry.key, thisMonday);
      if (offset < -49 || offset > 6) continue;
      final idx = 7 + (offset / 7).floor();
      if (idx >= 0 && idx < 8) weeks[idx] += entry.value;
    }
    return weeks;
  }

  /// 从今天（无记录则从昨天）向前数连续有里程的天数。
  int _streakFrom(Map<DateTime, double> days, DateTime today) {
    var cursor = today;
    if ((days[cursor] ?? 0) <= 0) {
      cursor = Calendar.addDays(cursor, -1);
      if ((days[cursor] ?? 0) <= 0) return 0;
    }
    var streak = 0;
    while ((days[cursor] ?? 0) > 0) {
      streak++;
      cursor = Calendar.addDays(cursor, -1);
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    if (_loadError) return LoadErrorPage(onRetry: _load);
    final c = context.colors;
    final range = _range;
    final km = range?.$1 ?? 0;
    final secs = range?.$2 ?? 0;
    final avgPace = km > 0.05 ? secs / km : 0.0;
    final climb = range?.$4 ?? 0;
    final count = range?.$3 ?? 0;
    final title = switch (_segment) {
      0 => '本周'.tr,
      1 => '本月'.tr,
      _ => '今年'.tr,
    };

    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          top: false,
          bottom: false,
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                )
              : ListView(
                  physics: dampedPhysics,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    MediaQuery.of(context).padding.top + 8,
                    20,
                    tabScrollBottomPadding(context),
                  ),
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.isEditorial) ...[
                          Text('STATS', style: kickerStyle(c)),
                          const SizedBox(height: 2),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '数据统计'.tr,
                              style: TextStyle(
                                fontFamily: c.isEditorial
                                    ? 'Playfair Display'
                                    : null,
                                fontFamilyFallback: c.isEditorial
                                    ? const ['Noto Sans SC']
                                    : null,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: c.textPrimary,
                              ),
                            ),
                            _segmentSwitch(c),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _hero(c, title, km, secs, avgPace, count),
                    const SizedBox(height: 12),
                    _calendarCard(c),
                    const SizedBox(height: 12),
                    _weeklyTrend(c),
                    const SizedBox(height: 12),
                    _prCard(c),
                    const SizedBox(height: 12),
                    _monthCompareCard(c),
                    const SizedBox(height: 12),
                    _paceRow(c, range?.$5, avgPace, climb),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _segmentSwitch(AppPalette c) {
    final editorial = c.isEditorial;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: editorial ? Colors.transparent : c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: editorial ? Border.all(color: c.stroke) : null,
      ),
      child: Row(
        children: [
          for (final (i, t) in ['周', '月', '年'].indexed)
            GestureDetector(
              onTap: () => setState(() => _segment = i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _segment == i
                      ? (editorial ? c.inverseSurface : c.accent)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  t.tr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _segment == i
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: _segment == i
                        ? (editorial ? c.onInverse : c.onAccent)
                        : c.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hero(
    AppPalette c,
    String title,
    double km,
    int secs,
    double avgPace,
    int count,
  ) {
    final editorial = c.isEditorial;
    // 编辑风：深色反转卡（墨底 + 荧光绿大数字）。
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: editorial
          ? BoxDecoration(
              color: c.inverseSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            )
          : BoxDecoration(
              gradient: heroGradient(c),
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: [
                BoxShadow(
                  color: c.glow,
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                  spreadRadius: -6,
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$title${'汇总'.tr}',
                style: TextStyle(
                  fontSize: 12,
                  color: editorial ? c.onInverse : c.onAccent2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                km.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: editorial ? 'Playfair Display' : null,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: editorial ? c.onInverseAccent : c.onAccent,
                  height: 1,
                  letterSpacing: editorial ? 0 : -1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '公里'.tr,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: editorial ? c.onInverse : c.onAccent2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _heroStat(c, '次数'.tr, '$count'),
              const SizedBox(width: 10),
              _heroStat(c, '时长'.tr, formatDuration(Duration(seconds: secs))),
              const SizedBox(width: 10),
              _heroStat(c, '平均配速'.tr, formatPace(avgPace)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(AppPalette c, String label, String value) {
    final editorial = c.isEditorial;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: editorial
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: scaleAlpha(c.onInverse, 0.25)),
              )
            : BoxDecoration(
                color: c.heroChip,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: editorial ? c.onInverse : c.onAccent,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: editorial ? c.onInverse : c.onAccent2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 运动日历热力图：最近 4 周（28 天），颜色深浅表示当天里程。
  Widget _calendarCard(AppPalette c) {
    final now = DateTime.now();
    final today = Calendar.day(now);
    final sunday = Calendar.addDays(today, 7 - today.weekday);
    final start = Calendar.addDays(sunday, -27);

    var activeDays = 0;
    for (var i = 0; i < 28; i++) {
      if ((_days[Calendar.addDays(start, i)] ?? 0) > 0) activeDays++;
    }
    var maxKm = 0.0;
    for (final v in _days.values) {
      if (v > maxKm) maxKm = v;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '运动日历'.tr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              Row(
                children: [
                  if (_streakDays > 1) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        LocaleController.instance.isEnglish
                            ? '$_streakDays-day streak'
                            : '连续 $_streakDays 天',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '$activeDays/28 ${'天'.tr}',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in ['一', '二', '三', '四', '五', '六', '日'])
                SizedBox(
                  width: 28,
                  child: Text(
                    d.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: c.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var w = 0; w < 4; w++) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 0; d < 7; d++)
                  _calCell(c, Calendar.addDays(start, w * 7 + d), maxKm, today),
              ],
            ),
            if (w < 3) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _calCell(AppPalette c, DateTime day, double maxKm, DateTime today) {
    final km = _days[day] ?? 0;
    final future = day.isAfter(today);
    final ratio = maxKm > 0 ? km / maxKm : 0.0;
    final Color bg;
    if (future || km <= 0) {
      bg = c.surface2;
    } else if (ratio >= 0.8) {
      bg = c.accent;
    } else if (ratio >= 0.45) {
      bg = c.calMid;
    } else {
      bg = c.calLow;
    }
    final Color fg;
    if (future || km <= 0) {
      fg = c.textMuted;
    } else if (ratio >= 0.8) {
      fg = c.onAccent;
    } else {
      fg = c.textPrimary;
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: day == today ? Border.all(color: c.accent, width: 1.5) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  /// 近 8 周里程柱状图。
  Widget _weeklyTrend(AppPalette c) {
    final weeks = <(String, double)>[];
    final today = Calendar.day(DateTime.now());
    final thisMonday = Calendar.monday(today);
    for (var i = 7; i >= 0; i--) {
      final monday = Calendar.addDays(thisMonday, -i * 7);
      final km = _trend.length == 8 ? _trend[7 - i] : 0.0;
      weeks.add((
        LocaleController.instance.isEnglish
            ? '${enMonthAbbr[monday.month - 1]} ${monday.day}'
            : '${monday.month}/${monday.day}',
        km,
      ));
    }
    final maxKm = weeks.map((w) => w.$2).fold(0.01, (a, b) => a > b ? a : b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '近 8 周里程'.tr,
                style: TextStyle(
                  fontSize: 14,
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
                    'km',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, (label, km)) in weeks.indexed)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: km <= 0
                                ? 4.0
                                : (km / maxKm * 78).clamp(8, 78).toDouble(),
                          ),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          builder: (_, h, child) => Container(
                            width: 16,
                            height: h,
                            decoration: BoxDecoration(
                              // 原型：柱体统一色，仅本周用主题色高亮。
                              color: km <= 0
                                  ? c.surface2
                                  : i == 7
                                  ? c.accent
                                  : scaleAlpha(c.barColor, 0.45),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 8,
                              color: i == 7 ? c.accent : c.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 个人纪录：最快 1/5/10 公里 + 最长单次 + 最长时长。
  Widget _prCard(AppPalette c) {
    final prs = _prs;
    final hasAny =
        prs != null &&
        (prs.best1kmSec != null ||
            prs.best5kmSec != null ||
            prs.best10kmSec != null ||
            prs.longestRun != null);
    final longestKm = prs?.longestRun?.distanceKm;
    final longestSec = prs?.longestDurationRun?.durationS;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '个人纪录'.tr,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _prItem(c, '最快 1 公里'.tr, prs?.best1kmSec, isPace: true),
              const SizedBox(width: 10),
              _prItem(c, '最快 5 公里'.tr, prs?.best5kmSec, isPace: true),
              const SizedBox(width: 10),
              _prItem(c, '最快 10 公里'.tr, prs?.best10kmSec, isPace: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _prBox(
                  c,
                  Icons.route_outlined,
                  '最长单次'.tr,
                  longestKm == null
                      ? '--'
                      : '${longestKm.toStringAsFixed(2)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _prBox(
                  c,
                  Icons.timer_outlined,
                  '最长时长'.tr,
                  longestSec == null
                      ? '--'
                      : formatDuration(Duration(seconds: longestSec)),
                ),
              ),
            ],
          ),
          if (!hasAny) ...[
            const SizedBox(height: 10),
            Text(
              '暂无足够数据'.tr,
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _prItem(
    AppPalette c,
    String label,
    double? paceSec, {
    required bool isPace,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: c.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              paceSec == null ? '--' : formatPace(paceSec),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prBox(AppPalette c, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: c.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 本月 vs 上月里程对比。
  Widget _monthCompareCard(AppPalette c) {
    final cur = _monthKm;
    final prev = _prevMonthKm;
    String deltaText;
    Color deltaColor;
    if (cur == null || prev == null) {
      deltaText = '暂无足够数据'.tr;
      deltaColor = c.textMuted;
    } else if (prev <= 0.05) {
      deltaText = cur > 0.05 ? '↑ ${cur.toStringAsFixed(1)} km' : '—';
      deltaColor = cur > 0.05 ? c.accent : c.textMuted;
    } else {
      final pct = ((cur - prev) / prev * 100).round();
      deltaText = pct >= 0 ? '↑ $pct%' : '↓ ${-pct}%';
      deltaColor = pct >= 0 ? c.accent : c.textMuted;
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconLabel(Icons.compare_arrows_rounded, '本月对比'.tr, size: 12),
              const Spacer(),
              Text(
                deltaText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: deltaColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${'本月'.tr} ${(_monthKm ?? 0).toStringAsFixed(1)} km · '
            '${'上月'.tr} ${(_prevMonthKm ?? 0).toStringAsFixed(1)} km',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _paceRow(
    AppPalette c,
    double? bestPace,
    double avgPace,
    double climb,
  ) {
    return Row(
      children: [
        _paceStat(
          c,
          Icons.speed_outlined,
          '平均配速'.tr,
          formatPace(avgPace),
          '当前范围'.tr,
        ),
        const SizedBox(width: 10),
        _paceStat(
          c,
          Icons.workspace_premium_outlined,
          '最快配速'.tr,
          bestPace == null ? '--' : formatPace(bestPace),
          '单次最佳'.tr,
        ),
        const SizedBox(width: 10),
        _paceStat(
          c,
          Icons.terrain_outlined,
          '累计爬升'.tr,
          '${climb.round()} m',
          '当前范围'.tr,
        ),
      ],
    );
  }

  Widget _paceStat(
    AppPalette c,
    IconData icon,
    String label,
    String value,
    String sub,
  ) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        radius: AppRadius.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconLabel(icon, label, size: 12),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 9, color: c.textMuted)),
          ],
        ),
      ),
    );
  }
}
