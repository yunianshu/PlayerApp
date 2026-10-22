import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../services/tts_service.dart';

/// 运动开始前全屏倒计时：3 -> 2 -> 1 -> GO。
/// 开启语音播报时逐字口播数字，结束播报「开始跑步」。
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
  int _spokenNumber = -1;
  bool _spokenStart = false;
  bool _completed = false;

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
        _completed = true;
        HapticFeedback.heavyImpact();
        _speakStart();
        widget.onComplete();
      }
    });

    _controller.addListener(() {
      final remaining = ((1 - _controller.value) * _totalSeconds).ceil().clamp(
        1,
        _totalSeconds,
      );
      if (remaining != _current) {
        HapticFeedback.mediumImpact();
        setState(() => _current = remaining);
      }
      _speakNumber(_current);
    });

    // TTS 初始化与倒计时并行；就绪后补播当前数字（通常来得及播 3）。
    if (Prefs.instance.voiceEnabled) {
      unawaited(
        TtsService.ensureInitialized().then((_) => _speakNumber(_current)),
      );
    }

    _controller.forward();
  }

  /// 逐字播报数字；同一数字只播一次，打断式覆盖上一条。
  void _speakNumber(int number) {
    if (!mounted || _completed) return;
    if (_spokenNumber == number) return;
    if (!Prefs.instance.voiceEnabled || !TtsService.isReady) return;
    _spokenNumber = number;
    unawaited(TtsService.speak('$number', flush: true));
  }

  void _speakStart() {
    if (_spokenStart) return;
    if (!Prefs.instance.voiceEnabled || !TtsService.isReady) return;
    _spokenStart = true;
    unawaited(TtsService.speak('开始跑步！'.tr, flush: true));
  }

  /// 数字切换动画：圆形揭示 + 缩放淡入（Keep 同款 RevealFrameLayout 交互），
  /// 代替生硬的文本替换。
  Widget _countText(AppPalette c) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => ClipOval(
        clipper: _CircleRevealClipper(anim.value),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 1.25,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        ),
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

/// 圆形揭示裁剪：半径随进度从 0 扩展到覆盖整个 child。
class _CircleRevealClipper extends CustomClipper<Rect> {
  _CircleRevealClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    final radius = math.max(size.width, size.height) / 2 * progress;
    return Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
  }

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
