import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/app_toast.dart';

import '../widgets/run_share_sheet.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../models/run_record.dart';
import '../pages/course_page.dart';
import '../services/courses.dart';
import '../services/track_simplify.dart';
import '../services/run_storage.dart';
import '../services/run_math.dart';
import '../services/tts_service.dart';
import '../widgets/common.dart';
import '../widgets/route_painter.dart';

/// 每公里分段配速（秒/公里），由轨迹点计算。
List<(int, double)> splitsOf(List<RunPoint> pts) {
  if (pts.length < 2) return const [];
  final result = <(int, double)>[];
  double seg = 0, seconds = 0;
  int kmIdx = 1;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    if (b.startsSegment) continue;
    final d = RunMath.haversineM(a.lat, a.lng, b.lat, b.lng);
    final ms = a.elapsedMs != null && b.elapsedMs != null
        ? b.elapsedMs! - a.elapsedMs!
        : b.time.difference(a.time).inMilliseconds;
    if (!d.isFinite || d <= 0 || ms <= 0) continue;
    var remaining = d;
    while (remaining > 1e-8) {
      final needed = 1000 - seg;
      final take = remaining < needed ? remaining : needed;
      seg += take;
      seconds += ms / 1000 * take / d;
      remaining -= take;
      if (seg >= 1000 - 1e-8) {
        result.add((kmIdx++, seconds));
        seg = 0;
        seconds = 0;
      }
    }
  }
  return result;
}

/// 跑步完成总结：成绩 + 分段配速 + 保存/分享。
class SummaryPage extends StatefulWidget {
  final RunRecord record;
  final List<RunPoint> points;

  /// 结束即保存流程（长按结束）传入 true：页面直接呈现已保存态，
  /// 无需再点"保存记录"；分享/拉伸照常可用。
  final bool alreadySaved;

  SummaryPage.fromTracker(
    this.record,
    List<RunPoint> points, {
    super.key,
    this.alreadySaved = false,
  }) : points = List.unmodifiable(points);

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _saved = false;
  bool _saving = false;
  bool _discarding = false;
  List<(int, double)>? _splitsCache;
  List<RunPoint>? _displayCache;

  @override
  void initState() {
    super.initState();
    _saved = widget.alreadySaved;
    _announceCompletion();
    // 跑后主动询问拉伸（Keep 同款引导）：≥1 公里才问，避免短途打扰。
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptStretch());
  }

  /// 拉伸询问弹窗：入口不再只藏在分享按钮下，结束即可见。
  Future<void> _promptStretch() async {
    if (!mounted || widget.record.distanceM < 1000) return;
    final c = context.readColors;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '跑后拉伸？'.tr,
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Text(
          '帮助恢复，减少肌肉酸痛，约5分钟'.tr,
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('暂不'.tr, style: TextStyle(color: c.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('开始拉伸'.tr),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.of(context).push(
        CoursePage.route(stretchCourse, '拉伸完成！'),
      );
    }
  }

  /// 跑完进入总结页播报本次成绩（Keep 同款：Rcomplete 完成播报）。
  void _announceCompletion() {
    if (!Prefs.instance.voiceEnabled) return;
    final r = widget.record;
    final en = LocaleController.instance.isEnglish;
    final minutes = r.durationS ~/ 60;
    final seconds = r.durationS % 60;
    final text = en
        ? 'Run done, ${r.distanceKm.toStringAsFixed(2)} km, '
              '$minutes minutes $seconds seconds'
        : '跑步完成，${r.distanceKm.toStringAsFixed(2)}公里，'
              '用时$minutes分${seconds.toString().padLeft(2, '0')}秒';
    unawaited(TtsService.speak(text));
  }

  List<(int, double)> get _splits => _splitsCache ??= splitsOf(widget.points);

  /// 绘制用抽稀轨迹：长距离总结页海报/地图不再整段重绘卡顿。
  List<RunPoint> get _displayPoints =>
      _displayCache ??= simplifyTrack(widget.points);

  Future<void> _save() async {
    if (_saving || _saved || _discarding) return;
    setState(() => _saving = true);
    try {
      await RunStorage.save(widget.record, widget.points);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '保存失败，请重试'.tr);
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    setState(() => _saved = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _share() =>
      showRunShareSheet(context, record: widget.record, points: _displayPoints);

  /// 放弃确认：按钮与系统返回手势共用，防止误触丢掉整条记录。
  Future<void> _confirmDiscard() async {
    if (_saving || _saved || _discarding) return;
    _discarding = true;
    final c = context.readColors;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.surface,
          title: Text(
            '放弃这条记录？'.tr,
            style: TextStyle(fontSize: 17, color: c.textPrimary),
          ),
          content: Text(
            '轨迹数据将一并删除，无法恢复。'.tr,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消'.tr, style: TextStyle(color: c.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('放弃'.tr, style: TextStyle(color: c.danger)),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        await RunStorage.discard(widget.record.sessionKey);
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (_) {
      if (mounted) {
        showAppToast(context, '放弃失败，请重试'.tr);
      }
    } finally {
      _discarding = false;
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
      // 未保存：返回手势先弹放弃确认，避免误触丢弃记录；
      // 已保存（含长按结束的自动保存）：直接返回。
      canPop: _saved,
      // Flutter 3.22 (HarmonyOS) does not expose onPopInvokedWithResult.
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Backdrop(
          child: SafeArea(
            top: false,
            bottom: false,
            child: ListView(
              physics: dampedPhysics,
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 12,
                20,
                24,
              ),
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
                        '跑步完成！'.tr,
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
                    '${'今天'.tr} ${_hhmm(r.start)} · ${_runKind(r.start).tr}',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    gradient: mapGradient(c),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: CustomPaint(
                    painter: RoutePainter(
                      _displayPoints,
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
                      label: '时长'.tr,
                      value: formatDuration(Duration(seconds: r.durationS)),
                    ),
                    const SizedBox(width: 10),
                    MetricTile(
                      icon: Icons.speed_outlined,
                      label: '平均配速'.tr,
                      value: formatPace(r.avgPaceSecPerKm),
                    ),
                    const SizedBox(width: 10),
                    MetricTile(
                      icon: Icons.local_fire_department_outlined,
                      label: '卡路里'.tr,
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
                  label: _saved
                      ? '已保存 ✓'.tr
                      : _saving
                      ? '保存中…'.tr
                      : '保存记录'.tr,
                  onTap: _saved || _saving ? null : _save,
                ),
                const SizedBox(height: 10),
                GhostButton('分享成绩海报'.tr, icon: Icons.ios_share, onTap: _share),
                const SizedBox(height: 10),
                GhostButton(
                  '跑后拉伸'.tr,
                  icon: Icons.self_improvement,
                  onTap: () => Navigator.of(context).push(
                    CoursePage.route(stretchCourse, '拉伸完成！'),
                  ),
                ),
                const SizedBox(height: 10),
                GhostButton(
                  '放弃这条记录'.tr,
                  color: c.danger,
                  onTap: _saving || _saved ? null : _confirmDiscard,
                ),
              ],
            ),
          ),
            ),
            // 完赛庆祝纸屑（一次性，不挡交互；Keep 完赛撒花同款交互）。
            const Positioned.fill(child: IgnorePointer(child: ConfettiBurst())),
          ],
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
                      // 编辑风荧光绿在米底对比不足，大数字用墨色。
                      color: c.isEditorial ? c.textPrimary : c.accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '公里'.tr,
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
                '跑步距离'.tr,
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
                '分段配速'.tr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              if (fastest != null)
                Text(
                  '${'最快'.tr} ${formatPace(fastest)}',
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
