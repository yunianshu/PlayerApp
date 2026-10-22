import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 启动过渡（品牌动画视频）：全屏静音播放一次后进入主界面。
/// 控制器由 main 在 runApp 的同时开始预初始化，这里接收 Future——
/// 就绪前盖一层白底（与原生启动窗口同色，视觉上仍是同一页），
/// 主界面子树在底下持续预热；就绪后播放，播完/失败/超时进主界面。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.controllerFuture});

  final Widget child;

  /// main 传入的预初始化结果；null（无 Future）表示完全跳过动画。
  final Future<VideoPlayerController?>? controllerFuture;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _fallbackTimer;
  bool _done = false; // 启动阶段结束，交还主界面
  bool _released = false;
  VideoPlayerController? _controller; // future 就绪后持有

  @override
  void initState() {
    super.initState();
    final future = widget.controllerFuture;
    if (future == null) {
      _done = true;
      return;
    }
    future.then(_onReady, onError: (_) => _onReady(null));
  }

  /// future 完成：null/未初始化 → 直接结束；否则开始播放。
  void _onReady(VideoPlayerController? controller) {
    if (!mounted) {
      // 页面已卸载（极快热启动等场景）：资源立即释放。
      controller?.dispose();
      return;
    }
    if (controller == null || !controller.value.isInitialized) {
      _finish();
      return;
    }
    setState(() => _controller = controller);
    // 兜底：视频卡住/回调丢失时，按视频时长加余量强制进主界面。
    final duration = controller.value.duration;
    final allowance = duration > Duration.zero
        ? duration + const Duration(milliseconds: 600)
        : const Duration(milliseconds: 3200);
    _fallbackTimer = Timer(allowance, _finish);
    controller.addListener(_onVideoTick);
    unawaited(controller.play());
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null) return;
    final v = controller.value;
    // ohos 适配版 video_player(2.7) 无 isCompleted，用 position>=duration 判断；
    // duration 为 0（元数据未就绪）时会瞬间误判播完，必须排除。
    if (v.duration > Duration.zero && v.position >= v.duration) _finish();
  }

  void _finish() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _releaseController();
    if (!mounted || _done) return;
    setState(() => _done = true);
  }

  /// 播完/卸载时释放控制器，只释放一次。
  void _releaseController() {
    if (_released) return;
    _released = true;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onVideoTick);
    unawaited(controller?.dispose());
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_done) return widget.child;
    // 播完整体移除遮罩，交还主界面；视频首帧即白底，与原生启动页一致。
    // 不用 AnimatedSwitcher：播放态在 build 内切换会让子树一帧内两换，
    // 曾在 ohos 上触发 "RenderBox was not laid out"（子树画而未布局）。
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            // cover 不能用 FittedBox（无界约束 + ohos 裸 Texture = 无限尺寸），
            // 用 LayoutBuilder 算出 cover 尺寸后以有界 SizedBox 撑满。
            child: controller == null || !controller.value.isInitialized
                ? const ColoredBox(color: Colors.white)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final size = controller.value.size;
                      final ar = size.width / size.height;
                      final double w, h;
                      if (ar > constraints.maxWidth / constraints.maxHeight) {
                        h = constraints.maxHeight;
                        w = h * ar;
                      } else {
                        w = constraints.maxWidth;
                        h = w / ar;
                      }
                      return ClipRect(
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          maxHeight: double.infinity,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: w,
                            height: h,
                            child: AspectRatio(
                              aspectRatio: ar,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
