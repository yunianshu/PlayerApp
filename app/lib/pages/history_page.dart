import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../widgets/common.dart';
import 'detail_page.dart';
import 'home_page.dart' show formatRunTime;

/// 跑步历史：月度汇总（可切换月份）+ 按周分组列表。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<RunRecord>? _runs;
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;

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
    setState(() => _runs = runs);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month += delta;
      if (_month > 12) {
        _month = 1;
        _year++;
      } else if (_month < 1) {
        _month = 12;
        _year--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final runs = _runs;
    final monthRuns = runs
            ?.where((r) => r.start.year == _year && r.start.month == _month)
            .toList() ??
        const <RunRecord>[];
    final monthKm = monthRuns.fold<double>(0, (a, r) => a + r.distanceKm);
    final monthSecs = monthRuns.fold<int>(0, (a, r) => a + r.durationS);
    final isCurrentMonth =
        _year == DateTime.now().year && _month == DateTime.now().month;

    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: dampedPhysics,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.isEditorial) ...[
                    Text('RUN', style: kickerStyle(c)),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '跑步记录',
                        style: TextStyle(
                          fontFamily: c.isEditorial ? 'Playfair Display' : null,
                          fontFamilyFallback:
                              c.isEditorial ? const ['Noto Sans SC'] : null,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                        ),
                      ),
                      _monthSwitcher(c, isCurrentMonth),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _monthCard(c, monthKm, monthSecs, monthRuns.length),
              const SizedBox(height: 16),
              if (runs == null)
                Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                )
              else if (runs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      '暂无跑步记录',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ),
                )
              else
                _groupedList(c, runs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthSwitcher(AppPalette c, bool isCurrentMonth) {
    final editorial = c.isEditorial;
    return Container(
      decoration: BoxDecoration(
        color: editorial ? Colors.transparent : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: editorial ? Border.all(color: c.stroke) : null,
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _arrow(c, Icons.chevron_left_rounded, () => _shiftMonth(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$_month 月',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          _arrow(
            c,
            Icons.chevron_right_rounded,
            isCurrentMonth ? null : () => _shiftMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _arrow(AppPalette c, IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? c.textMuted : c.textPrimary,
        ),
      ),
    );
  }

  Widget _monthCard(AppPalette c, double km, int secs, int count) {
    final editorial = c.isEditorial;
    // 编辑风：深色反转卡（墨底 + 荧光绿大数字）；其余主题：渐变卡。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                  spreadRadius: -8,
                ),
              ],
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_year年$_month月',
                style: TextStyle(
                  fontSize: 12,
                  color: editorial ? c.onInverse : c.onAccent2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${km.toStringAsFixed(1)} 公里',
                style: TextStyle(
                  fontFamily: editorial ? 'Playfair Display' : null,
                  fontFamilyFallback: editorial ? const ['Noto Sans SC'] : null,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: editorial ? c.onInverseAccent : c.onAccent,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _stat(c, '$count', '次数'),
              const SizedBox(width: 18),
              _stat(c, formatDuration(Duration(seconds: secs)), '时长'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(AppPalette c, String v, String label) {
    final editorial = c.isEditorial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          v,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: editorial ? c.onInverse : c.onAccent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: editorial ? c.onInverse : c.onAccent2,
          ),
        ),
      ],
    );
  }

  Widget _groupedList(AppPalette c, List<RunRecord> runs) {
    // 列表跟随顶部选中的月份，避免"切换月份但列表不变"的割裂感。
    final monthRuns = runs
        .where((r) => r.start.year == _year && r.start.month == _month)
        .toList();
    if (monthRuns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '$_year 年 $_month 月没有跑步记录',
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ),
      );
    }
    final now = DateTime.now();
    final isCurrentMonth = _year == now.year && _month == now.month;

    // 当前月沿用本周/上周/更早分组；历史月按月展示单组。
    final List<(String, List<RunRecord>)> groups;
    if (isCurrentMonth) {
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final lastMonday = monday.subtract(const Duration(days: 7));
      groups = [
        ('本周', monthRuns.where((r) => !r.start.isBefore(monday)).toList()),
        (
          '上周',
          monthRuns
              .where(
                (r) =>
                    r.start.isBefore(monday) && !r.start.isBefore(lastMonday),
              )
              .toList(),
        ),
        ('更早', monthRuns.where((r) => r.start.isBefore(lastMonday)).toList()),
      ];
    } else {
      groups = [('$_year 年 $_month 月', monthRuns)];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, list) in groups)
          if (list.isNotEmpty) ...[
            _sectionHead(c, title, list),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              radius: 20,
              child: Column(
                children: [
                  for (final (i, r) in list.indexed) ...[
                    if (i > 0) Divider(height: 1, color: c.divider),
                    _row(c, r),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  Widget _sectionHead(AppPalette c, String title, List<RunRecord> list) {
    final km = list.fold<double>(0, (a, r) => a + r.distanceKm);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          Text(
            '${km.toStringAsFixed(1)} km · ${list.length} 次',
            style: TextStyle(fontSize: 11, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _row(AppPalette c, RunRecord r) {
    final editorial = c.isEditorial;
    return InkWell(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => DetailPage(record: r))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            if (editorial)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              )
            else
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.directions_run, size: 16, color: c.accent),
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
                    '${formatDuration(Duration(seconds: r.durationS))} · ${formatPace(r.avgPaceSecPerKm)}/公里',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  r.distanceKm.toStringAsFixed(2),
                  style: TextStyle(
                    fontFamily: editorial ? 'Playfair Display' : null,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  'km',
                  style: TextStyle(fontSize: 10, color: c.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
