import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../services/courses.dart';
import '../services/tts_service.dart';
import '../widgets/common.dart';
import '../widgets/exercise_video.dart';

/// 协助课程播放页：按步骤自动推进的引导训练（跑前热身 / 跑后拉伸）。
/// 每步开始口播动作名称（尊重语音开关），完成页返回 true；
/// 中途退出返回 false/null，由调用方决定后续流程。
class CoursePage extends StatefulWidget {
  const CoursePage({
    super.key,
    required this.course,
    required this.finishedTitle,
  });

  final AssistCourse course;
  final String finishedTitle;

  static Route<bool> route(AssistCourse course, String finishedTitle) =>
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) =>
            CoursePage(course: course, finishedTitle: finishedTitle),
      );

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  int _index = 0;
  int _remaining = 0;
  bool _paused = false;
  bool _finished = false;
  Timer? _ticker;
  bool _spokenCurrentStep = false;

  /// 当前步骤是否有演示媒体：视频/图片用全屏演示 + 下方信息条，
  /// 无媒体时用动作图标占位。
  bool _hasVideo = false;
  bool _hasImage = false;

  AssistCourse get _course => widget.course;

  CourseStep get _step => _course.steps[_index];

  int get _elapsedSeconds =>
      _course.steps.take(_index).fold(0, (sum, s) => sum + s.seconds) +
      (_step.seconds - _remaining);

  @override
  void initState() {
    super.initState();
    _remaining = _step.seconds;
    _startTicker();
    _probeImage();
    if (Prefs.instance.voiceEnabled) {
      unawaited(TtsService.ensureInitialized());
      // 课程开场白 + 第一节引导（Keep 式全程语音）；TTS 未就绪时由
      // speak 内部等待，队列顺序保留。
      _speak(
        '欢迎来到${_course.title}，'
        '共${_course.steps.length}个动作，约${_course.total.inMinutes}分钟',
      );
      _speakStep();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_paused || _finished) return;
    if (_remaining > 1) {
      setState(() => _remaining--);
      // 整点播报：换边 / 时间过半 / 倒计时（决策在纯函数里，便于测试）。
      final announcement = courseAnnouncement(
        remaining: _remaining,
        seconds: _step.seconds,
        twoSided: _step.twoSided,
      );
      if (announcement != null) _speak(announcement.tr);
      return;
    }
    // 本节结束：震动反馈并推进到下一节（或收尾）。
    HapticFeedback.mediumImpact();
    if (_index + 1 < _course.steps.length) {
      _goTo(_index + 1);
    } else {
      _finish();
    }
  }

  void _goTo(int index) {
    setState(() {
      _index = index;
      _remaining = _course.steps[index].seconds;
      _spokenCurrentStep = false;
      _paused = false;
    });
    _probeImage();
    _startTicker();
    _speakStep();
  }

  void _finish() {
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    setState(() => _finished = true);
    _speakFinish();
  }

  /// 探测当前步骤的演示媒体（视频优先，其次图片；决定全屏/回退布局）。
  Future<void> _probeImage() async {
    final anim = _course.steps[_index].anim;
    var video = false;
    var image = false;
    try {
      await rootBundle.load(anim.videoAsset);
      video = true;
    } on Object {
      try {
        await rootBundle.load(anim.assetName);
        image = true;
      } on Object {
        // 都没有：用动作图标占位。
      }
    }
    if (mounted && !_finished) {
      setState(() {
        _hasVideo = video;
        _hasImage = image;
      });
    }
  }

  /// 每节开始口播动作名 + 动作要点；第一节带"第一个动作"引导，
  /// 之后带"下一个动作"预告（排队接续，不打断上一条）。
  void _speakStep() {
    if (_spokenCurrentStep || !mounted) return;
    _spokenCurrentStep = true;
    if (!Prefs.instance.voiceEnabled) return;
    final lead = _index == 0 ? '第一个动作' : '下一个动作';
    unawaited(TtsService.speak('$lead，${_step.name.tr}，${_step.tip.tr}'));
  }

  /// 语音播报统一入口（尊重语音开关）。
  void _speak(String text) {
    if (!Prefs.instance.voiceEnabled) return;
    unawaited(TtsService.speak(text));
  }

  void _speakFinish() {
    if (!Prefs.instance.voiceEnabled) return;
    unawaited(TtsService.speak(widget.finishedTitle.tr));
  }

  Future<void> _confirmQuit() async {
    if (_finished) {
      Navigator.of(context).pop(false);
      return;
    }
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('结束课程？'.tr),
        content: Text('剩余动作将不再继续'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('继续课程'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('结束'.tr),
          ),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_finished) return _buildFinished(c);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _confirmQuit,
        ),
        title: Text(
          _course.title.tr,
          style: TextStyle(fontSize: 16, color: c.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(
                    '${_index + 1}/${_course.steps.length} · ${_step.name.tr}',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    LocaleController.instance.isEnglish
                        ? 'about ${_course.total.inMinutes} min'
                        : '全程约${_course.total.inMinutes}分钟',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GradientProgress(
                value: _elapsedSeconds / _course.total.inSeconds,
              ),
            ),
            ..._fullscreenStage(c),
            // Expanded 媒体区占满剩余空间，信息条自然贴底。
            _controls(c),
            const SizedBox(height: 12),
            if (_paused)
              Text(
                '已暂停'.tr,
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  /// 全屏演示布局（Keep 式）：真人视频/示意图铺满可用区域（cover 按宽填充），
  /// 名称、要点、倒计时在媒体下方独立信息条（左对齐），不遮挡演示画面。
  List<Widget> _fullscreenStage(AppPalette c) => [
    Expanded(
      child: _hasVideo
          ? ExerciseVideo(
              anim: _step.anim,
              fallbackImage: _fallbackImage(c),
            )
          : _hasImage
              ? _fallbackImage(c)
              : _mediaPlaceholder(c),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _step.name.tr,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _step.tip.tr,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '$_remaining',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: c.accent,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: _muscleLegend(c),
      ),
    ),
  ];

  /// 示意图（视频缺失/失败时的回退画面），再缺失则用动作图标占位。
  Widget _fallbackImage(AppPalette c) => Image.asset(
    _step.anim.assetName,
    fit: BoxFit.cover,
    errorBuilder: (_, e, st) => _mediaPlaceholder(c),
  );

  /// 无任何演示媒体时的占位画面：柔和底色 + 动作图标。
  Widget _mediaPlaceholder(AppPalette c) => Container(
    color: c.surface,
    alignment: Alignment.center,
    child: Icon(_step.icon, size: 72, color: c.textMuted),
  );

  /// 播放控制条（两种布局共用）。
  Widget _controls(AppPalette c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleBtn(
          _index == 0 ? Icons.first_page : Icons.skip_previous,
          size: 46,
          onTap: _index == 0 ? null : () => _goTo(_index - 1),
        ),
        const SizedBox(width: 26),
        Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent),
          child: IconButton(
            iconSize: 34,
            color: c.onAccent,
            onPressed: () {
              setState(() => _paused = !_paused);
              _speak(_paused ? '已暂停'.tr : '继续课程'.tr);
            },
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          ),
        ),
        const SizedBox(width: 26),
        CircleBtn(
          Icons.skip_next,
          size: 46,
          onTap: () {
            if (_index + 1 < _course.steps.length) {
              _goTo(_index + 1);
            } else {
              _finish();
            }
          },
        ),
      ],
    );
  }

  /// 肌群图例：● 主发力 ● 辅助。
  Widget _muscleLegend(AppPalette c) {
    final secColor = Color.lerp(c.danger, c.surface, 0.2)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text('主发力'.tr, style: TextStyle(fontSize: 9, color: c.textSecondary)),
        const SizedBox(width: 8),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: secColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text('辅助'.tr, style: TextStyle(fontSize: 9, color: c.textSecondary)),
      ],
    );
  }

  Widget _buildFinished(AppPalette c) {
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scaleAlpha(c.accent, 0.14),
                  ),
                  child: Icon(
                    Icons.self_improvement,
                    size: 46,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.finishedTitle.tr,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  LocaleController.instance.isEnglish
                      ? '${_course.steps.length} moves · ${_course.total.inMinutes} min'
                      : '共${_course.steps.length}个动作 · 约${_course.total.inMinutes}分钟',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
                const SizedBox(height: 32),
                PrimaryButton(
                  label: '完成'.tr,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
