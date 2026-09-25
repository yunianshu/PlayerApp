import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/run_tracker.dart';
import '../widgets/common.dart';
import '../widgets/route_painter.dart';
import 'summary_page.dart';

/// 跑步进行中：轨迹 + 实时距离/时长/配速/卡路里 + 暂停/停止/锁屏。
class RunningPage extends StatefulWidget {
  const RunningPage({super.key});

  static Route<void> route() => MaterialPageRoute(
    builder: (_) => const RunningPage(),
    fullscreenDialog: true,
  );

  @override
  State<RunningPage> createState() => _RunningPageState();
}

class _RunningPageState extends State<RunningPage> {
  bool _locked = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.watch<RunTracker>();
    return PopScope(
      canPop: t.state == RunState.idle,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: _mapBackground(c, t)),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (c.isEditorial)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('RUN', style: kickerStyle(c)),
                              const SizedBox(height: 2),
                              Text(
                                '跑步中',
                                style: TextStyle(
                                  fontFamily: 'Playfair Display',
                                  fontFamilyFallback: const ['Noto Sans SC'],
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox(width: 100),
                        _gpsChip(c, t),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _distance(c, t),
                        const SizedBox(height: 16),
                        _metrics(c, t),
                      ],
                    ),
                  ),
                  _controls(c, t),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            if (_locked) _lockOverlay(c),
          ],
        ),
      ),
    );
  }

  Widget _mapBackground(AppPalette c, RunTracker t) {
    // 全出血地图：无左右间距，直通屏幕顶部与底部。
    // RepaintBoundary 隔离轨迹重绘：每秒文字刷新不连带重画整条轨迹。
    return Container(
      decoration: BoxDecoration(gradient: mapGradient(c)),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: RoutePainter(t.points, strokeWidth: 4, palette: c),
        ),
      ),
    );
  }

  Widget _gpsChip(AppPalette c, RunTracker t) {
    final (icon, label) = switch (t.state) {
      RunState.paused => (Icons.pause_circle_outline, '已暂停'),
      _ when t.gpsError => (Icons.satellite_alt, 'GPS 不可用'),
      _ when !t.hasFix => (Icons.satellite_alt, '搜索 GPS…'),
      _ => (Icons.satellite_alt, 'GPS 记录中'),
    };
    final color = t.gpsError ? c.danger : c.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.chipBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: c.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _distance(AppPalette c, RunTracker t) {
    return Column(
      children: [
        Text(
          t.km.toStringAsFixed(2),
          style: TextStyle(
            fontFamily: c.isEditorial ? 'Playfair Display' : null,
            fontSize: 62,
            fontWeight: FontWeight.bold,
            letterSpacing: c.isEditorial ? 0 : -2,
            height: 1,
            // 原型：跑步中距离为主色（白天靛蓝 / 夜间珊瑚）。
            color: c.isEditorial ? c.textPrimary : c.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '公里',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _metrics(AppPalette c, RunTracker t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          MetricTile(
            icon: Icons.timer_outlined,
            label: '时长',
            value: formatDuration(t.elapsed),
          ),
          const SizedBox(width: 10),
          MetricTile(
            icon: Icons.speed_outlined,
            label: '当前配速',
            value: formatPace(t.currentPace),
          ),
          const SizedBox(width: 10),
          MetricTile(
            icon: Icons.local_fire_department_outlined,
            label: '卡路里',
            value: '${t.calories}',
          ),
        ],
      ),
    );
  }

  Widget _controls(AppPalette c, RunTracker t) {
    final paused = t.state == RunState.paused;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _roundButton(
          c,
          size: 54,
          color: c.isEditorial ? Colors.transparent : c.surface,
          border: c.isEditorial ? Border.all(color: c.stroke) : null,
          icon: Icons.lock_open_rounded,
          iconColor: c.textSecondary,
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _locked = true);
          },
        ),
        const SizedBox(width: 28),
        _roundButton(
          c,
          size: 84,
          // 编辑风：荧光绿实心圆（无论暂停与否）；其余主题维持原逻辑。
          color: c.isEditorial
              ? c.accent
              : (paused ? c.accent : c.textPrimary),
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          iconColor: c.isEditorial ? c.onAccent : (paused ? c.onAccent : c.bg),
          onTap: () => paused ? t.resume() : t.pause(),
        ),
        const SizedBox(width: 28),
        _roundButton(
          c,
          size: 54,
          color: c.isEditorial ? Colors.transparent : c.dangerSoft,
          border: Border.all(color: c.dangerStroke),
          icon: Icons.stop_rounded,
          iconColor: c.danger,
          onTap: () => _confirmStop(t),
        ),
      ],
    );
  }

  Widget _roundButton(
    AppPalette c, {
    required double size,
    required Color color,
    required IconData icon,
    required Color iconColor,
    Border? border,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border,
          boxShadow: [
            BoxShadow(
              color: c.cardShadow,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.38, color: iconColor),
      ),
    );
  }

  Widget _lockOverlay(AppPalette c) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {}, // 拦截所有点击
        child: Container(
          color: scaleAlpha(c.bg, 0.85),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 40, color: c.accent),
                const SizedBox(height: 14),
                Text(
                  '已锁定，防止误触',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '长按下方按钮解锁',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const SizedBox(height: 28),
                GestureDetector(
                  onLongPress: () {
            HapticFeedback.lightImpact();
            setState(() => _locked = false);
          },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: accentGradient(c),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: c.glow,
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      '长按解锁',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: c.onAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmStop(RunTracker t) async {
    // 跨 async gap 后不再使用 context 取色，先捕获。
    final c = context.colors;
    // 二次确认：防止误触直接结束一次跑步。
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '结束跑步？',
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Text(
          '当前里程 ${t.km.toStringAsFixed(2)} 公里，结束后将进入保存页。',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('继续跑', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('结束', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final record = t.stop();
    if (!mounted) return;
    if (record == null) {
      // 轨迹太短，视为放弃
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SummaryPage.fromTracker(record, t.points),
      ),
    );
  }
}
