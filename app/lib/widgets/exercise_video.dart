import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/diagnostics.dart';

/// 课程动作的演示媒体标识：决定加载 assets/videos/{动作}.mp4 真人视频，
/// 以及缺失时回退的 assets/exercises/{动作}.png 示意图。
enum ExerciseAnim {
  jogInPlace, // 原地慢跑：双腿交替小幅摆动
  ankleCircle, // 踝关节环绕：单脚画圈
  jumpingJack, // 开合跳：四肢开合
  lungeTwist, // 弓步转体
  highKnees, // 高抬腿：快速交替、膝盖抬高
  hamstringSwing, // 腿后侧动态拉伸：直腿前摆
  quadStretch, // 大腿前侧拉伸：单腿站立手拉脚
  hamstringStretch, // 大腿后侧拉伸：直腿体前屈
  calfStretch, // 小腿拉伸：弓步压腿
  gluteStretch, // 臀部拉伸：站姿脚踝搭膝
  hipFlexorStretch, // 髋屈肌拉伸：弓步下压
  itBandStretch, // 大腿外侧拉伸：前腿交叉俯身
  breathing, // 深呼吸：胸腔起伏
}

/// 枚举名转蛇形命名（highKnees → high_knees）。
String _snakeCase(Enum value) {
  final raw = value.toString().split('.').last;
  return raw.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );
}

/// 视频资源路径扩展。
extension ExerciseAnimVideo on ExerciseAnim {
  String get videoAsset => 'assets/videos/${_snakeCase(this)}.mp4';
}

/// 动作对应的示意图资源路径（assets/exercises/ 下放入同名 png 即自动启用，
/// 作为视频缺失或加载失败时的回退画面）。
extension ExerciseAnimAsset on ExerciseAnim {
  String get assetName => 'assets/exercises/${_snakeCase(this)}.png';
}

/// 动作真人演示视频（Keep 同款课程体验）：assets/videos/{动作}.mp4
/// 循环静音播放；初始化失败或超时（无文件/平台插件挂起/解码失败）回退到
/// 调用方传入的示意图，任何阶段都不留黑屏占位。
class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({
    super.key,
    required this.anim,
    required this.fallbackImage,
  });

  final ExerciseAnim anim;
  final Widget fallbackImage;

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;
  /// 首帧已确认（播放进度真正前进过）。在此之前一直显示示意图，
  /// 防止个别设备"初始化成功但解码不出帧"时把示意图换成黑屏。
  bool _frameConfirmed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant ExerciseVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 步骤推进时 State 会被复用：动作变了必须换控制器，否则一直播上一节。
    if (oldWidget.anim != widget.anim) {
      final stale = _controller;
      setState(() {
        _controller = null;
        _failed = false;
        _frameConfirmed = false;
      });
      unawaited(stale?.dispose());
      _init();
    }
  }

  Future<void> _init() async {
    final anim = widget.anim;
    final controller = VideoPlayerController.asset(anim.videoAsset);
    try {
      // 超时保护：部分平台插件初始化挂起而非抛错，会让占位永远黑屏。
      await controller.initialize().timeout(const Duration(seconds: 6));
      if (!mounted || widget.anim != anim) {
        await controller.dispose();
        return;
      }
      controller.setLooping(true);
      // 示范视频本身无声；静音避免占用音频焦点（不压低跑步时的音乐/播报）。
      await controller.setVolume(0);
      await controller.play();
      // 首帧探针：个别设备 initialize 成功但解码器始终不出帧（渲染为黑），
      // 播放进度会一直停在 0。等待最多 8 秒，进度仍未前进就按失败回退示意图。
      var advanced = false;
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted || widget.anim != anim) {
          await controller.dispose();
          return;
        }
        if (controller.value.position > const Duration(milliseconds: 100)) {
          advanced = true;
          break;
        }
      }
      if (!advanced) {
        await controller.dispose();
        unawaited(
          Diagnostics.logError(
            'ExerciseVideo stalled at first frame (${anim.name}, '
            '${Platform.operatingSystem})',
            StateError('position never advanced after play()'),
            null,
          ),
        );
        if (mounted && widget.anim == anim) setState(() => _failed = true);
        return;
      }
      if (!mounted || widget.anim != anim) {
        await controller.dispose();
        return;
      }
      setState(() {
        _frameConfirmed = true;
        _controller = controller;
      });
    } on Object catch (error, stack) {
      await controller.dispose();
      // 关键诊断：视频回退的原因（无文件/插件异常/解码失败/超时）。
      unawaited(
        Diagnostics.logError(
          'ExerciseVideo init failed (${anim.name})',
          error,
          stack,
        ),
      );
      if (mounted && widget.anim == anim) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final videoReady = !_failed &&
        _frameConfirmed &&
        controller != null &&
        controller.value.isInitialized &&
        controller.value.size != Size.zero;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 示意图常驻底层：加载中/失败/首帧未确认时都显示它，
        // 确认后只切透明度、不卸载子树——运行中换树曾在 ohos 上
        // 触发整帧布局断言风暴，页面直接黑屏。
        Opacity(
          opacity: videoReady ? 0 : 1,
          child: widget.fallbackImage,
        ),
        // 视频按原始比例居中（contain）：竖屏下方形/横版视频完整可见；
        // 不做 cover 裁剪（会把全身动作裁成中段一条），也不用
        // FittedBox/OverflowBox（无界约束会让 ohos 裸 Texture 得到无限尺寸）。
        if (videoReady)
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
      ],
    );
  }
}
