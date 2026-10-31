import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/app_toast.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../services/background_service.dart';
import '../services/run_prs.dart';
import '../services/run_storage.dart';
import '../services/run_tracker.dart';
import '../services/tts_service.dart';
import '../services/run_feedback_diagnostics.dart';
import '../services/tracking_policies.dart';
import '../widgets/common.dart';
import '../widgets/run_finish_overlay.dart';
import '../widgets/route_painter.dart';
import 'summary_page.dart';

/// 跑步进行中：轨迹 + 实时距离/时长/配速/卡路里 + 暂停/停止/锁屏。
/// 支持：每公里语音播报、低速自动暂停、目标配速提醒。
class RunningPage extends StatefulWidget {
  const RunningPage({super.key});

  static Route<void> route() => MaterialPageRoute(
    builder: (_) => const RunningPage(),
    fullscreenDialog: true,
  );

  @override
  State<RunningPage> createState() => _RunningPageState();
}

class _RunningPageState extends State<RunningPage> with WidgetsBindingObserver {
  bool _locked = false;
  bool _ending = false;

  /// 长按结束后的全屏结束动画：展示期间拦截交互，进总结页时随页面移除。
  bool _finishing = false;
  late final RunTracker _tracker;
  Timer? _paceTimer;
  PaceTargetEvaluator? _paceEvaluator;
  PaceDeviation? _paceDeviation;
  double? _best1kmSec;
  double? _longestDistanceM;
  bool _longestAnnounced = false;
  bool _halfMarathonAnnounced = false;
  bool _fullMarathonAnnounced = false;
  DateTime? _lastGpsVoiceAt;

  /// 上次自动暂停/恢复通知时间：临界抖动造成的短周期翻转只切状态、
  /// 不再震动和播报（反复播报会在鸿蒙上不断抢占音频焦点打断音乐）。
  static const _autoPauseNotifyGap = Duration(seconds: 45);
  DateTime? _lastAutoPauseNotifyAt;
  String? _recordBanner;
  Timer? _recordBannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RunFeedbackDiagnostics.event('running_page', 'opened', {
      'autoPauseEnabled': Prefs.instance.autoPauseEnabled,
      'targetPaceEnabled': Prefs.instance.paceTargetSecPerKm > 0,
      'voiceEnabled': Prefs.instance.voiceEnabled,
    });
    _tracker = context.read<RunTracker>();
    _tracker.onInterval = _announceInterval;
    _tracker.onAutoPause = _onAutoPause;
    _tracker.onGpsStatus = _onGpsStatus;
    if (Prefs.instance.voiceEnabled) {
      unawaited(TtsService.ensureInitialized());
      unawaited(_loadPersonalRecords());
    }
    unawaited(_checkNotificationPermission());
    if (Prefs.instance.paceTargetSecPerKm > 0) {
      _paceEvaluator = PaceTargetEvaluator(
        targetSecPerKm: Prefs.instance.paceTargetSecPerKm,
      );
      _paceTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _feedPaceTarget(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    RunFeedbackDiagnostics.event('running_page', 'lifecycle', {
      'state': state.name,
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RunFeedbackDiagnostics.event('running_page', 'closed');
    _paceTimer?.cancel();
    _recordBannerTimer?.cancel();
    _tracker.onInterval = null;
    _tracker.onAutoPause = null;
    _tracker.onGpsStatus = null;
    super.dispose();
  }

  /// 通知权限引导：Android 13+ 未授予时锁屏看不到实时成绩，
  /// 提示一次并给出跳设置的入口。
  Future<void> _checkNotificationPermission() async {
    try {
      final granted = await BackgroundService.hasNotificationPermission();
      if (granted || !mounted) return;
      showAppToast(
        context,
        '未授予通知权限，锁屏将看不到实时成绩'.tr,
        duration: const Duration(seconds: 8),
        actionLabel: '去开启'.tr,
        onAction: () => unawaited(BackgroundService.openNotificationSettings()),
      );
    } on Object {
      // 引导失败不影响跑步。
    }
  }

  /// 载入个人纪录（开跑前的历史最好成绩），供破纪录播报比对。
  Future<void> _loadPersonalRecords() async {
    try {
      final prs = await RunPrService.instance.compute();
      if (!mounted) return;
      _best1kmSec = prs.best1kmSec;
      _longestDistanceM = prs.longestRun?.distanceM;
    } on Object {
      // 纪录读取失败只影响破纪录播报，不影响跑步。
    }
  }

  void _announceInterval(
    int unitIndex,
    int intervalM,
    int splitSeconds,
    int totalSeconds,
    int km,
    int? kmSplitSeconds,
  ) {
    if (!mounted) return;
    RunFeedbackDiagnostics.event('distance_milestone', 'reached', {
      'voiceEnabled': Prefs.instance.voiceEnabled,
      'explicitHaptic': false,
    });
    final en = LocaleController.instance.isEnglish;
    final result = kmAnnouncementText(
      english: en,
      sayDistance: Prefs.instance.voiceDistance,
      sayTime: Prefs.instance.voiceTime,
      sayPace: Prefs.instance.voicePace,
      unitIndex: unitIndex,
      intervalM: intervalM,
      splitSeconds: splitSeconds,
      totalSeconds: totalSeconds,
      km: km,
      kmSplitSeconds: kmSplitSeconds,
      best1kmSec: _best1kmSec,
      longestDistanceM: _longestDistanceM,
      currentDistanceM: _tracker.distanceM,
      longestAlreadyAnnounced: _longestAnnounced,
      halfMarathonAnnounced: _halfMarathonAnnounced,
      fullMarathonAnnounced: _fullMarathonAnnounced,
    );
    if (result.newBest1km && kmSplitSeconds != null) {
      _best1kmSec = kmSplitSeconds.toDouble();
    }
    if (result.newLongest) _longestAnnounced = true;
    if (result.newHalf) _halfMarathonAnnounced = true;
    if (result.newFull) {
      _halfMarathonAnnounced = true;
      _fullMarathonAnnounced = true;
    }
    _showRecordBanner(result, en);
    // 语音关闭时横幅仍显示，只有口播被跳过。
    if (!Prefs.instance.voiceEnabled) return;
    if (result.text != null) {
      unawaited(TtsService.speak(result.text!));
    }
  }

  /// 破纪录/里程碑横幅（Keep 同款 trophy 反馈）：4 秒后自动消失。
  void _showRecordBanner(
    ({
      String? text,
      bool newBest1km,
      bool newLongest,
      bool newHalf,
      bool newFull,
    })
    result,
    bool en,
  ) {
    final String? banner;
    if (result.newFull) {
      banner = en ? 'Full marathon distance done!' : '完成全马距离！';
    } else if (result.newHalf) {
      banner = en ? 'Half marathon distance done!' : '完成半马距离！';
    } else if (result.newBest1km) {
      banner = en ? 'New fastest kilometer!' : '刷新一公里最快纪录！';
    } else if (result.newLongest) {
      banner = en ? 'New longest run!' : '刷新最长跑步距离纪录！';
    } else {
      banner = null;
    }
    if (banner == null) return;
    _recordBannerTimer?.cancel();
    _recordBannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _recordBanner = null);
    });
    setState(() => _recordBanner = banner);
  }

  /// GPS 丢失/恢复播报（Keep 同款能力）；30 秒内不重复，防信号抖动刷屏。
  /// 时钟取自 tracker（可注入），测试可控。
  void _onGpsStatus(bool lost) {
    if (!mounted || !Prefs.instance.voiceEnabled) return;
    final now = _tracker.currentTime();
    final last = _lastGpsVoiceAt;
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastGpsVoiceAt = now;
    unawaited(
      TtsService.speak(
        lost
            ? (LocaleController.instance.isEnglish
                  ? 'GPS signal lost'
                  : 'GPS信号丢失')
            : (LocaleController.instance.isEnglish
                  ? 'GPS signal restored'
                  : 'GPS信号恢复'),
      ),
    );
  }

  void _onAutoPause(bool paused) {
    // 短周期内的第二次翻转（判据抖动）静默处理：状态照常切换，
    // 只是震一遍+播一遍的打扰频率被限制在 45 秒至多一次。
    final now = DateTime.now();
    final lastNotify = _lastAutoPauseNotifyAt;
    if (lastNotify != null &&
        now.difference(lastNotify) < _autoPauseNotifyGap) {
      RunFeedbackDiagnostics.event(
        paused ? 'auto_pause' : 'auto_resume',
        'suppressed',
        {'reason': 'feedback_cooldown'},
      );
      return;
    }
    _lastAutoPauseNotifyAt = now;
    unawaited(
      RunFeedbackDiagnostics.haptic(
        paused ? 'auto_pause' : 'auto_resume',
        HapticFeedback.mediumImpact,
        fields: {'autoPauseEnabled': Prefs.instance.autoPauseEnabled},
      ),
    );
    if (!mounted || !Prefs.instance.voiceEnabled) return;
    // flush 立即播：暂停/恢复是即时状态变化，排队等上一条会让人以为没播。
    unawaited(
      TtsService.speak(
        paused ? '已自动暂停，继续跑动即可恢复'.tr : '已自动恢复，加油！'.tr,
        flush: true,
      ),
    );
  }

  /// 手动暂停/继续与自动暂停一样播报语音，并申请音频焦点压低其他应用音量。
  void _togglePause(RunTracker t) {
    final resuming = t.state == RunState.paused;
    unawaited(
      RunFeedbackDiagnostics.haptic(
        resuming ? 'manual_resume' : 'manual_pause',
        HapticFeedback.mediumImpact,
      ),
    );
    resuming ? t.resume() : t.pause();
    if (!mounted || !Prefs.instance.voiceEnabled) return;
    // flush 立即播（同上）。
    unawaited(
      TtsService.speak(resuming ? '继续跑步，加油！'.tr : '已暂停'.tr, flush: true),
    );
  }

  void _feedPaceTarget() {
    final evaluator = _paceEvaluator;
    if (evaluator == null || !mounted) return;
    // 未配置目标配速不报快慢：运行中目标被关闭时立即停报并撤横幅。
    if (Prefs.instance.paceTargetSecPerKm <= 0) {
      _paceTimer?.cancel();
      _paceTimer = null;
      _paceEvaluator = null;
      if (_paceDeviation != null) {
        setState(() => _paceDeviation = null);
      }
      return;
    }
    final tracker = _tracker;
    if (tracker.state != RunState.running) return;
    final pace = tracker.currentPace;
    final alert = evaluator.feed(pace, 1);
    if (alert != null) {
      unawaited(
        RunFeedbackDiagnostics.haptic(
          'pace_target',
          HapticFeedback.heavyImpact,
          fields: {'targetPaceEnabled': Prefs.instance.paceTargetSecPerKm > 0},
        ),
      );
      if (Prefs.instance.voiceEnabled) {
        unawaited(
          TtsService.speak(
            paceAlertText(
              deviation: alert,
              paceSecPerKm: pace,
              targetSecPerKm: Prefs.instance.paceTargetSecPerKm,
              english: LocaleController.instance.isEnglish,
            ),
          ),
        );
      }
    }
    if (evaluator.deviation != _paceDeviation) {
      setState(() => _paceDeviation = evaluator.deviation);
    }
  }

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
                                '跑步中'.tr,
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
                          const Spacer(),
                        Flexible(child: _gpsChip(c, t)),
                      ],
                    ),
                  ),
                  if (t.autoPaused)
                    _banner(
                      c,
                      Icons.pause_circle_outline,
                      '已自动暂停 · 跑动后会自动继续'.tr,
                      c.textSecondary,
                    ),
                  if (_recordBanner != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        transitionBuilder: (child, anim) => SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0, -0.6),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Container(
                          key: ValueKey(_recordBanner),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: c.chipBg,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: c.accent),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.emoji_events_rounded,
                                size: 15,
                                color: c.accent,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _recordBanner!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_paceDeviation != null && !t.autoPaused)
                    _paceDiffBanner(c, t),
                  if (t.backgroundError || t.storageError)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        t.storageError
                            ? '草稿保存失败，请检查存储并及时保存记录'.tr
                            : '后台定位启动失败，请保持应用在前台记录'.tr,
                        style: TextStyle(color: c.danger, fontSize: 12),
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
            if (_finishing) const RunFinishOverlay(),
          ],
        ),
      ),
    );
  }

  /// 目标配速偏差横幅（Keep 同款"米数化"交互）：把配速差换算成
  /// 领先/落后目标的米数，大字号直读；配速数值作为次级信息。
  Widget _paceDiffBanner(AppPalette c, RunTracker t) {
    final slow = _paceDeviation == PaceDeviation.tooSlow;
    final color = slow ? c.danger : c.accent;
    final en = LocaleController.instance.isEnglish;
    final diff = paceTargetDiffMeters(
      targetSecPerKm: Prefs.instance.paceTargetSecPerKm,
      elapsedSeconds: t.elapsed.inSeconds.toDouble(),
      distanceM: t.distanceM,
    );
    final String main;
    if (diff == null) {
      main = slow ? '慢于目标'.tr : '快于目标'.tr;
    } else {
      final ahead = diff >= 0;
      final meters = diff.abs().round();
      main = en
          ? '${ahead ? 'ahead' : 'behind'} $meters m'
          : '${ahead ? '快' : '慢'}$meters米';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.chipBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.stroke),
        ),
        child: Row(
          children: [
            Icon(
              slow ? Icons.south_east_rounded : Icons.north_east_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: main,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${'配速'.tr} ${formatPace(t.currentPace)}',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(AppPalette c, IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.chipBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.stroke),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: c.textPrimary),
              ),
            ),
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
      RunState.paused when t.autoPaused => (
        Icons.pause_circle_outline,
        '已自动暂停'.tr,
      ),
      RunState.paused => (Icons.pause_circle_outline, '已暂停'.tr),
      _ when t.gpsError => (Icons.satellite_alt, 'GPS 不可用'.tr),
      _ when t.poorAccuracy => (Icons.gps_not_fixed, '精度不足，请开启精确定位'.tr),
      _ when !t.hasFix => (Icons.satellite_alt, '搜索 GPS…'.tr),
      _ => (Icons.satellite_alt, 'GPS 记录中'.tr),
    };
    final color = t.gpsError ? c.danger : c.accent;
    // 搜索中：卫星图标呼吸脉冲，降低等待焦虑（Keep 同款交互）。
    final searching = !t.gpsError && !t.poorAccuracy && !t.hasFix;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.chipBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (searching)
            PulsingIcon(icon, size: 12, color: color)
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: c.textPrimary),
            ),
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
          '公里'.tr,
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
            label: '时长'.tr,
            value: formatDuration(t.elapsed),
          ),
          const SizedBox(width: 10),
          MetricTile(
            icon: Icons.speed_outlined,
            label: '当前配速'.tr,
            value: formatPace(t.currentPace),
          ),
          const SizedBox(width: 10),
          MetricTile(
            icon: Icons.local_fire_department_outlined,
            label: '卡路里'.tr,
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
            unawaited(
              RunFeedbackDiagnostics.haptic(
                'screen_lock',
                HapticFeedback.lightImpact,
              ),
            );
            setState(() => _locked = true);
          },
        ),
        const SizedBox(width: 28),
        _roundButton(
          c,
          size: 84,
          // 编辑风：荧光绿实心圆（无论暂停与否）；其余主题维持原逻辑。
          color: c.isEditorial ? c.accent : (paused ? c.accent : c.textPrimary),
          icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          iconColor: c.isEditorial ? c.onAccent : (paused ? c.onAccent : c.bg),
          onTap: () => _togglePause(t),
        ),
        const SizedBox(width: 28),
        _roundButton(
          c,
          size: 54,
          color: c.isEditorial ? Colors.transparent : c.dangerSoft,
          border: Border.all(color: c.dangerStroke),
          icon: Icons.stop_rounded,
          iconColor: c.danger,
          // 长按结束并自动保存（与应用内"长按解锁"同一手势习惯）；
          // 轻点只提示，防误触。
          onTap: () {
            showAppToast(context, '长按按钮结束并保存'.tr);
          },
          onLongPress: () => _endRun(t),
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
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
                  '已锁定，防止误触'.tr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '长按下方按钮解锁'.tr,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const SizedBox(height: 28),
                GestureDetector(
                  onLongPress: () {
                    unawaited(
                      RunFeedbackDiagnostics.haptic(
                        'screen_unlock',
                        HapticFeedback.lightImpact,
                      ),
                    );
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
                      '长按解锁'.tr,
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

  /// 长按结束：先浮现结束动画，同时停止记录并直接保存（不再二次确认），
  /// 动画完整播一遍后再进总结页，进入时已是已保存态。
  Future<void> _endRun(RunTracker t) async {
    if (_ending) return;
    _ending = true;
    try {
      unawaited(
        RunFeedbackDiagnostics.haptic(
          'manual_end',
          HapticFeedback.mediumImpact,
        ),
      );
      // 长按是刻意手势，动画立即给"已结束"的确定性反馈，不等异步停止完成。
      setState(() => _finishing = true);
      final animStart = DateTime.now();
      final record = await t.stop();
      if (!mounted) return;
      if (record == null) {
        // 轨迹太短，视为放弃
        setState(() => _finishing = false);
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }
      // 结束即保存：失败时退回总结页手动保存，不丢数据。
      var saved = false;
      try {
        await RunStorage.save(record, t.points);
        saved = true;
      } on Object {
        if (mounted) {
          showAppToast(context, '自动保存失败，请在下一页手动保存'.tr);
        }
      }
      // 保存再快也让动画完整播一遍，避免对勾没落笔就切页。
      const minShow = Duration(milliseconds: 1600);
      final shown = DateTime.now().difference(animStart);
      if (shown < minShow) await Future<void>.delayed(minShow - shown);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SummaryPage.fromTracker(record, t.points, alreadySaved: saved),
        ),
      );
    } catch (_) {
      if (mounted) {
        // 回滚动画让用户可以重试长按。
        setState(() => _finishing = false);
        showAppToast(context, '结束记录失败，请重试'.tr);
      }
    } finally {
      _ending = false;
    }
  }
}
