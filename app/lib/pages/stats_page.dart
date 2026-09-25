import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../widgets/common.dart';

/// 数据统计：周/月/年切换 + 汇总卡 + 运动日历热力图 + 周趋势 + 配速统计。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int _segment = 1; // 0=周 1=月 2=年
  List<RunRecord> _all = const [];
  bool _loading = true;

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
    // 本地个人应用，全量加载避免超过固定条数后旧数据静默丢失。
    final runs = await RunDatabase.instance.listRuns();
    if (!mounted) return;
    setState(() {
      _all = runs;
      _loading = false;
    });
  }

  /// 当前时间段内的记录。
  List<RunRecord> get _scoped {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_segment == 0) {
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return _all.where((r) => !r.start.isBefore(monday)).toList();
    }
    if (_segment == 1) {
      return _all
          .where((r) => r.start.year == now.year && r.start.month == now.month)
          .toList();
    }
    return _all.where((r) => r.start.year == now.year).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runs = _scoped;
    final km = runs.fold<double>(0, (a, r) => a + r.distanceKm);
    final secs = runs.fold<int>(0, (a, r) => a + r.durationS);
    final avgPace = km > 0.05 ? secs / km : 0.0;
    final climb = runs.fold<double>(0, (a, r) => a + r.climbM);
    final title = switch (_segment) {
      0 => '本周',
      1 => '本月',
      _ => '今年',
    };

    return Scaffold(
      body: Backdrop(
        child: SafeArea(
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
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
                      '数据统计',
                      style: TextStyle(
                        fontFamily: c.isEditorial ? 'Playfair Display' : null,
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
            _hero(c, title, km, secs, avgPace, runs.length),
            const SizedBox(height: 12),
            _calendarCard(c),
            const SizedBox(height: 12),
            _weeklyTrend(c),
            const SizedBox(height: 12),
            _paceRow(c, runs, avgPace, climb),
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
        borderRadius: BorderRadius.circular(14),
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
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  t,
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
              borderRadius: BorderRadius.circular(22),
            )
          : BoxDecoration(
              gradient: heroGradient(c),
              borderRadius: BorderRadius.circular(22),
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
                '$title汇总',
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
                  '公里',
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
              _heroStat(c, '次数', '$count'),
              const SizedBox(width: 10),
              _heroStat(c, '时长', formatDuration(Duration(seconds: secs))),
              const SizedBox(width: 10),
              _heroStat(c, '均配', formatPace(avgPace.toDouble())),
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
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: scaleAlpha(c.onInverse, 0.25),
                ),
              )
            : BoxDecoration(
                color: c.heroChip,
                borderRadius: BorderRadius.circular(13),
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
    final today = DateTime(now.year, now.month, now.day);
    // 以本周日结尾，向前 27 天
    final sunday = today.add(Duration(days: 7 - today.weekday));
    final start = sunday.subtract(const Duration(days: 27));

    final kmByDay = <DateTime, double>{};
    for (final r in _all) {
      final d = DateTime(r.start.year, r.start.month, r.start.day);
      kmByDay[d] = (kmByDay[d] ?? 0) + r.distanceKm;
    }
    // 活动天数只统计日历覆盖的 28 天，而非全部历史。
    var activeDays = 0;
    for (var i = 0; i < 28; i++) {
      final day = start.add(Duration(days: i));
      if ((kmByDay[day] ?? 0) > 0) activeDays++;
    }
    final maxKm = kmByDay.values.fold(0.0, (a, b) => a > b ? a : b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '运动日历',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              Text(
                '$activeDays/28 天',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
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
                    d,
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
                  _calCell(
                    c,
                    start.add(Duration(days: w * 7 + d)),
                    kmByDay,
                    maxKm,
                    today,
                  ),
              ],
            ),
            if (w < 3) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _calCell(
    AppPalette c,
    DateTime day,
    Map<DateTime, double> kmByDay,
    double maxKm,
    DateTime today,
  ) {
    final km = kmByDay[day] ?? 0;
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final weeks = <(String, double)>[];
    for (var i = 7; i >= 0; i--) {
      final monday = thisMonday.subtract(Duration(days: i * 7));
      final nextMonday = monday.add(const Duration(days: 7));
      final km = _all
          .where(
            (r) => !r.start.isBefore(monday) && r.start.isBefore(nextMonday),
          )
          .fold<double>(0, (a, r) => a + r.distanceKm);
      weeks.add(('${monday.month}/${monday.day}', km));
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
                '近 8 周里程',
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
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: km <= 0 ? 4.0 : (km / maxKm * 78).clamp(8, 78).toDouble(),
                        ),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        builder: (_, h, __) => Container(
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
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 8,
                          color: i == 7 ? c.accent : c.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paceRow(
    AppPalette c,
    List<RunRecord> runs,
    double avgPace,
    double climb,
  ) {
    double? best;
    for (final r in runs) {
      final p = r.avgPaceSecPerKm;
      if (p > 0 && (best == null || p < best)) best = p;
    }
    return Row(
      children: [
        _paceStat(c, Icons.speed_outlined, '平均配速', formatPace(avgPace), '当前范围'),
        const SizedBox(width: 10),
        _paceStat(
          c,
          Icons.workspace_premium_outlined,
          '最快配速',
          best == null ? '--' : formatPace(best),
          '单次最佳',
        ),
        const SizedBox(width: 10),
        _paceStat(
          c,
          Icons.terrain_outlined,
          '累计爬升',
          '${climb.round()} m',
          '当前范围',
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
        radius: 18,
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
