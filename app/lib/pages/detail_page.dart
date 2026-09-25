import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../widgets/common.dart';
import '../widgets/route_painter.dart';
import 'home_page.dart' show formatRunTime;
import 'summary_page.dart' show splitsOf;

/// 跑步详情：轨迹 + 六项数据 + 分段配速 + 海拔曲线 + 分享/删除。
class DetailPage extends StatefulWidget {
  final RunRecord record;

  const DetailPage({super.key, required this.record});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  List<RunPoint> _points = const [];
  List<(int, double)> _splits = const [];
  List<double> _elevations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts = await RunDatabase.instance.getPoints(widget.record.id!);
    if (!mounted) return;
    // 派生数据只在加载时算一次，避免每次 build 重复遍历全部轨迹点。
    setState(() {
      _points = pts;
      _splits = splitsOf(pts);
      _elevations = _smoothElevations(pts);
      _loading = false;
    });
  }

  /// GPS 原始海拔噪声大，做 5 点滑动平均让曲线可读。
  static List<double> _smoothElevations(List<RunPoint> pts) {
    if (pts.length < 5) return [for (final p in pts) p.altitude];
    const w = 2; // 半窗宽
    return [
      for (var i = 0; i < pts.length; i++)
        () {
          var sum = 0.0, n = 0;
          for (var j = i - w; j <= i + w; j++) {
            if (j >= 0 && j < pts.length) {
              sum += pts[j].altitude;
              n++;
            }
          }
          return sum / n;
        }(),
    ];
  }

  Future<void> _share() async {
    final r = widget.record;
    try {
      await Share.share(
        '🏃 ${formatRunTime(r.start)} 跑步\n'
        '距离：${r.distanceKm.toStringAsFixed(2)} km\n'
        '时长：${formatDuration(Duration(seconds: r.durationS))}\n'
        '配速：${formatPace(r.avgPaceSecPerKm)}/km\n'
        '消耗：${r.calories} kcal\n'
        '—— 来自 跑迹 RunTrail',
        subject: '跑迹 RunTrail',
      );
    } catch (_) {
      // 分享面板被取消或不可用，静默即可。
    }
  }

  Future<void> _delete() async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '删除这条记录？',
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
            child: Text('删除', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await RunDatabase.instance.deleteRun(widget.record.id!);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请重试')),
      );
      return;
    }
    AppData.instance.bump();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.record;
    final splits = _splits;
    final fastest = splits.isEmpty
        ? null
        : splits.reduce((a, b) => a.$2 < b.$2 ? a : b).$2;
    final elevations = _elevations;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: dampedPhysics,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                CircleBtn(
                  Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Column(
                  children: [
                    Text(
                      '跑步详情',
                      style: TextStyle(
                        fontFamily: c.isEditorial ? 'Playfair Display' : null,
                        fontFamilyFallback: c.isEditorial
                            ? const ['Noto Sans SC']
                            : null,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      formatRunTime(r.start),
                      style: TextStyle(fontSize: 10, color: c.textSecondary),
                    ),
                  ],
                ),
                const Spacer(),
                CircleBtn(Icons.ios_share, onTap: _share),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: mapGradient(c),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: RoutePainter(
                        _points,
                        strokeWidth: 3.5,
                        palette: c,
                      ),
                    ),
                  ),
                  // 轨迹加载中：地图区域给反馈，避免"空白地图"突兀。
                  if (_loading)
                    Positioned.fill(
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 14,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.chipBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.stroke),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.route_outlined, size: 12, color: c.accent),
                          const SizedBox(width: 5),
                          Text(
                            '${r.distanceKm.toStringAsFixed(2)} 公里 · ${(r.durationS / 60).round()} 分钟',
                            style: TextStyle(
                              fontSize: 11,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                _grid(
                  c,
                  Icons.route_outlined,
                  '距离',
                  '${r.distanceKm.toStringAsFixed(2)} km',
                ),
                _grid(
                  c,
                  Icons.timer_outlined,
                  '时长',
                  formatDuration(Duration(seconds: r.durationS)),
                ),
                _grid(
                  c,
                  Icons.speed_outlined,
                  '平均配速',
                  formatPace(r.avgPaceSecPerKm),
                ),
                _grid(
                  c,
                  Icons.local_fire_department_outlined,
                  '卡路里',
                  '${r.calories}',
                ),
                _grid(
                  c,
                  Icons.speed_outlined,
                  '平均速度',
                  r.durationS > 0
                      ? '${(r.distanceKm / (r.durationS / 3600)).toStringAsFixed(1)} km/h'
                      : '—',
                ),
                _grid(
                  c,
                  Icons.terrain_outlined,
                  '累计爬升',
                  '${r.climbM.round()} m',
                ),
              ],
            ),
            if (splits.isNotEmpty) ...[
              const SizedBox(height: 12),
              _paceCard(c, splits, fastest),
            ],
            if (elevations.length > 4) ...[
              const SizedBox(height: 12),
              _elevationCard(c, elevations),
            ],
            const SizedBox(height: 16),
            GhostButton(
              '删除这条记录',
              color: c.danger,
              icon: Icons.delete_outline,
              onTap: _delete,
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _grid(AppPalette c, IconData icon, String label, String value) {
    final editorial = c.isEditorial;
    return Container(
      decoration: editorial
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.stroke),
            )
          : BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                  spreadRadius: -8,
                ),
              ],
            ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconLabel(icon, label, size: 12),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontFamily: editorial ? 'Playfair Display' : null,
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _paceCard(AppPalette c, List<(int, double)> splits, double? fastest) {
    final maxPace = splits.map((s) => s.$2).fold(0.0, (a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '每公里配速',
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
          const SizedBox(height: 14),
          // 长距离（20km+）柱子数量会超出屏宽：横向滚动兜底防溢出。
          SizedBox(
            height: 110,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (idx, secs) in splits)
                        _paceColumn(c, idx, secs, fastest, maxPace),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paceColumn(
    AppPalette c,
    int idx,
    double secs,
    double? fastest,
    double maxPace,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            formatPace(secs),
            style: TextStyle(
              fontSize: 9,
              color: secs == fastest ? c.accent : c.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (secs / maxPace * 66).clamp(12, 66).toDouble()),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (_, h, __) => Container(
              width: 22,
              height: h,
              decoration: BoxDecoration(
                color: secs == fastest ? c.accent : c.accentDeep,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$idx',
            style: TextStyle(fontSize: 10, color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _elevationCard(AppPalette c, List<double> elevations) {
    final min = elevations.reduce((a, b) => a < b ? a : b);
    final max = elevations.reduce((a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '海拔变化',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              Text(
                '${min.round()} – ${max.round()} m',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
              painter: _ElevationPainter(elevations, c),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<double> values;
  final AppPalette palette;

  _ElevationPainter(this.values, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(1.0, double.infinity);
    Offset pt(int i) => Offset(
      i / (values.length - 1) * size.width,
      size.height - 6 - (values[i] - min) / range * (size.height - 16),
    );
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = palette.accentArea);
    canvas.drawPath(
      line,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      old.values != values || old.palette != palette;
}
