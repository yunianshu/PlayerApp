# -*- coding: utf-8 -*-
p = 'lib/pages/course_page.dart'
s = open(p, encoding='utf-8').read()

old_body_head = """            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GradientProgress(
                value: _elapsedSeconds / _course.total.inSeconds,
              ),
            ),
            const Spacer(),
            _stepRing(c),"""
new_body_head = """            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GradientProgress(
                value: _elapsedSeconds / _course.total.inSeconds,
              ),
            ),
            if (_hasImage) ..._fullscreenStage(c) else ..._classicStage(c),"""
assert old_body_head in s, 'body head anchor missing'
s = s.replace(old_body_head, new_body_head)

old_mid = """            const Spacer(),
            _stepRing(c),
            const SizedBox(height: 28),
            // 动作演示画面（Keep 同款"每步有画面"体验，原生火柴人动画）
            // + 肌群图示（Keep 动作详情的发力高亮方案，矢量自绘）。
            // 空间不足时按比例收缩，小屏不溢出。
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    // 有自制示意图（assets/exercises/{动作}.png）用图，
                    // 缺失时回退火柴人动画。
                    child: Image.asset(
                      _step.anim.assetName,
                      width: 150,
                      height: 150,
                      fit: BoxFit.contain,
                      errorBuilder: (_, e, st) =>
                          ExerciseFigure(anim: _step.anim, size: 150),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MuscleDiagram(
                            primary: _step.primaryMuscles,
                            secondary: _step.secondaryMuscles,
                            height: 128,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _muscleLegend(c),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _step.name.tr,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _step.tip.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ),
            const Spacer(),
            Row("""
new_mid = """            const Spacer(),
            _controls(c),
            const SizedBox(height: 12),
            if (_paused)
              Text('已暂停'.tr, style: TextStyle(fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  /// 回退布局：环形倒计时 + 火柴人 + 肌群图（无示意图时）。
  List<Widget> _classicStage(AppPalette c) => [
            const Spacer(),
            _stepRing(c),
            const SizedBox(height: 28),
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ExerciseFigure(anim: _step.anim, size: 150),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MuscleDiagram(
                            primary: _step.primaryMuscles,
                            secondary: _step.secondaryMuscles,
                            height: 128,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _muscleLegend(c),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _step.name.tr,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _step.tip.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ),
            const Spacer(),
          ];

  /// 全屏演示布局（Keep 式）：示意图铺满 + 底部渐变叠层显示名称/要点/倒计时。
  List<Widget> _fullscreenStage(AppPalette c) => [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _step.anim.assetName,
                    fit: BoxFit.contain,
                    errorBuilder: (_, e, st) =>
                        ExerciseFigure(anim: _step.anim, size: 150),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 44, 20, 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              scaleAlpha(c.bg, 0),
                              scaleAlpha(c.bg, 0.85),
                              c.bg,
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _step.name.tr,
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: c.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _step.tip.tr,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  '$_remaining',
                                  style: TextStyle(
                                    fontSize: 46,
                                    fontWeight: FontWeight.bold,
                                    color: c.accent,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _muscleLegend(c),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ];

  /// 播放控制条（两种布局共用）。
  Widget _controls(AppPalette c) {
    return Row("""
assert old_mid in s, 'mid anchor missing'
s = s.replace(old_mid, new_mid)

old_tail = """                CircleBtn(
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
            ),
            const SizedBox(height: 12),
            if (_paused)
              Text('已暂停'.tr, style: TextStyle(fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
"""
new_tail = """                CircleBtn(
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
"""
assert old_tail in s, 'tail anchor missing'
s = s.replace(old_tail, new_tail)
open(p, 'w', encoding='utf-8').write(s)
print('layout ok')
