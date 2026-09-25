import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../services/run_math.dart';
import '../widgets/common.dart';
import '../widgets/route_painter.dart';

/// 每公里分段配速（秒/公里），由轨迹点计算。
List<(int, double)> splitsOf(List<RunPoint> pts) {
  if (pts.length < 2) return const [];
  final result = <(int, double)>[];
  double seg = 0;
  DateTime segStart = pts.first.time;
  int kmIdx = 1;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final d = RunMath.haversineM(a.lat, a.lng, b.lat, b.lng);
    seg += d;
    if (seg >= 1000) {
      final secs = b.time.difference(segStart).inMilliseconds / 1000;
      result.add((kmIdx++, secs));
      seg = 0;
      segStart = b.time;
    }
  }
  return result;
}

/// 跑步完成总结：成绩 + 分段配速 + 保存/分享。
class SummaryPage extends StatefulWidget {
  final RunRecord record;
  final List<RunPoint> points;

  const SummaryPage.fromTracker(this.record, this.points, {super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _saved = false;
  List<(int, double)>? _splitsCache;

  List<(int, double)> get _splits =>
      _splitsCache ??= splitsOf(widget.points);

  Future<void> _save() async {
    try {
      await RunDatabase.instance.insertRun(widget.record, widget.points);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
      return;
    }
    AppData.instance.bump();
    if (!mounted) return;
    setState(() => _saved = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _share() async {
    final r = widget.record;
    try {
      await Share.share(
        '🏃 跑步完成！\n'
        '距离：${r.distanceKm.toStringAsFixed(2)} km\n'
        '时长：${formatDuration(Duration(seconds: r.durationS))}\n'
        '配速：${formatPace(r.avgPaceSecPerKm)}/km\n'
        '消耗：${r.calories} kcal\n'
        '—— 来自 跑迹 RunTrail',
        subject: '跑迹 RunTrail',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享未完成')),
      );
    }
  }

  /// 放弃确认：按钮与系统返回手势共用，防止误触丢掉整条记录。
  Future<void> _confirmDiscard() async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '放弃这条记录？',
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Text(
          '轨迹数据将一并删除，无法恢复。',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('放弃', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.record;
    final splits = _splits;
    final fastest = splits.isEmpty
        ? null
        : splits.reduce((a, b) => a.$2 < b.$2 ? a : b).$2;
    return PopScope(
      // 系统返回手势先弹确认，避免误触丢弃未保存的记录。
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: dampedPhysics,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const SizedBox(height: 8),
            // 入场：奖杯缩放淡入。
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(
                scale: v,
                child: Opacity(opacity: v.clamp(0, 1), child: child),
              ),
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    // 编辑风：荧光绿实心圆；其余主题：渐变 + 辉光。
                    gradient: c.isEditorial ? null : accentGradient(c),
                    color: c.isEditorial ? c.accent : null,
                    shape: BoxShape.circle,
                    boxShadow: c.isEditorial
                        ? null
                        : [
                            BoxShadow(
                              color: c.glow,
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 30,
                    color: c.onAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Column(
                children: [
                  if (c.isEditorial) ...[
                    Text('DONE', style: kickerStyle(c)),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    '跑步完成！',
                    style: TextStyle(
                      fontFamily: c.isEditorial ? 'Playfair Display' : null,
                      fontFamilyFallback: c.isEditorial
                          ? const ['Noto Sans SC']
                          : null,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '今天 ${_hhmm(r.start)} · ${_runKind(r.start)}',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 190,
              decoration: BoxDecoration(
                gradient: mapGradient(c),
                borderRadius: BorderRadius.circular(22),
              ),
              child: CustomPaint(
                painter: RoutePainter(
                  widget.points,
                  strokeWidth: 3.5,
                  palette: c,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _distanceCard(c, r),
            const SizedBox(height: 12),
            Row(
              children: [
                MetricTile(
                  icon: Icons.timer_outlined,
                  label: '时长',
                  value: formatDuration(Duration(seconds: r.durationS)),
                ),
                const SizedBox(width: 10),
                MetricTile(
                  icon: Icons.speed_outlined,
                  label: '平均配速',
                  value: formatPace(r.avgPaceSecPerKm),
                ),
                const SizedBox(width: 10),
                MetricTile(
                  icon: Icons.local_fire_department_outlined,
                  label: '卡路里',
                  value: '${r.calories}',
                ),
              ],
            ),
            if (splits.isNotEmpty) ...[
              const SizedBox(height: 12),
              _splitsCard(c, splits, fastest),
            ],
            const SizedBox(height: 18),
            PrimaryButton(
              label: _saved ? '已保存 ✓' : '保存记录',
              onTap: _saved ? null : _save,
            ),
            const SizedBox(height: 10),
            GhostButton('分享成绩单', icon: Icons.ios_share, onTap: _share),
            const SizedBox(height: 10),
            GhostButton(
              '放弃这条记录',
              color: c.danger,
              onTap: _confirmDiscard,
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _distanceCard(AppPalette c, RunRecord r) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r.distanceKm.toStringAsFixed(2),
                    style: TextStyle(
                      fontFamily: c.isEditorial ? 'Playfair Display' : null,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: c.accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '公里',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '跑步距离',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
            ],
          ),
          Icon(Icons.route_outlined, size: 24, color: c.textMuted),
        ],
      ),
    );
  }

  Widget _splitsCard(
    AppPalette c,
    List<(int, double)> splits,
    double? fastest,
  ) {
    final maxPace = splits.map((s) => s.$2).fold(0.0, (a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '分段配速',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              if (fastest != null)
                Text(
                  '最快 ${formatPace(fastest)}',
                  style: TextStyle(fontSize: 11, color: c.accent),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (idx, secs) in splits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$idx km',
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: SizedBox(
                        height: 10,
                        child: Stack(
                          children: [
                            Container(color: c.surface2),
                            FractionallySizedBox(
                              widthFactor: (secs / maxPace).clamp(0.2, 1),
                              child: Container(
                                color: secs == fastest
                                    ? c.accent
                                    : c.accentDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      formatPace(secs),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _runKind(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return '晨跑';
  if (h >= 11 && h < 14) return '午间跑';
  if (h >= 14 && h < 18) return '午后跑';
  if (h >= 18 && h < 22) return '夜跑';
  return '凌晨跑';
}
