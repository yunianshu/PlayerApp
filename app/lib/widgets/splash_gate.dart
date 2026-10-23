import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'startup_animation.dart';

/// 一次性的品牌过渡。直接使用已恢复的主题，不等待视频解码或平台通道。
/// 首页始终保留在相同的 Stack 位置预热，动画结束不会重建首页状态。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  Timer? _fallbackTimer;
  bool _started = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _done = !widget.enabled;
    _animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish();
          });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done) return;
    // 尊重系统“减少动态效果”，不播放、也不额外等待两秒。
    if (MediaQuery.of(context).disableAnimations) {
      _animation.stop();
      _fallbackTimer?.cancel();
      _done = true;
      return;
    }
    if (_started) return;
    _started = true;
    _fallbackTimer = Timer(const Duration(milliseconds: 2600), _finish);
    _animation.forward();
  }

  @override
  void didUpdateWidget(SplashGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _finish();
    // 同一次启动期间切换主题或重建父节点，不重新播放。
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台返回不重播/继续过期的开场；初始化工作仍由首页自己管理。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _finish();
    }
  }

  void _finish() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (!mounted || _done) return;
    _animation.stop();
    setState(() => _done = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallbackTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: !_done,
          child: ExcludeFocus(
            excluding: !_done,
            child: AbsorbPointer(absorbing: !_done, child: widget.child),
          ),
        ),
        if (!_done)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) => StartupAnimationFrame(
                palette: context.colors,
                progress: _animation.value,
              ),
            ),
          ),
      ],
    );
  }
}
