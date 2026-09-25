import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// 运动开始前全屏倒计时：3 -> 2 -> 1 -> GO。
class CountdownPage extends StatefulWidget {
  final VoidCallback onComplete;

  const CountdownPage({super.key, required this.onComplete});

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 3;
  late final AnimationController _controller;
  late final Animation<double> _progress;
  int _current = _totalSeconds;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _totalSeconds),
    );
    _progress = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onComplete();
      }
    });

    _controller.addListener(() {
      final remaining = (_controller.value * _totalSeconds).ceil().clamp(1, _totalSeconds);
      if (remaining != _current) {
        HapticFeedback.mediumImpact();
        setState(() => _current = remaining);
      }
    });

    _controller.forward();
  }

  /// 数字切换动画：缩放淡入，代替生硬的文本替换。
  Widget _countText(AppPalette c) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween<double>(begin: 1.6, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Text(
        '$_current',
        key: ValueKey<int>(_current),
        style: TextStyle(
          fontSize: 120,
          fontWeight: FontWeight.bold,
          color: c.textPrimary,
          height: 1,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: scaleAlpha(c.bg, 0.94),
      body: Center(
        child: SizedBox(
          width: 220,
          height: 220,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, child) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _progress.value,
                    strokeWidth: 10,
                    backgroundColor: c.surface2,
                    valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                  ),
                  Center(child: child),
                ],
              );
            },
            child: _countText(c),
          ),
        ),
      ),
    );
  }
}
