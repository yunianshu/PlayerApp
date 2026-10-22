import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/services/tracking_policies.dart';

void main() {
  group('AutoPauseDetector（自动暂停判定）', () {
    test('连续低速达到阈值触发暂停', () {
      final d = AutoPauseDetector(stillSeconds: 10);
      expect(d.feed(0.3, 3), AutoPauseEvent.none);
      expect(d.feed(0.2, 3), AutoPauseEvent.none); // 累计 6s
      expect(d.feed(0.3, 3), AutoPauseEvent.none); // 累计 9s
      expect(d.feed(0.1, 3), AutoPauseEvent.shouldPause); // 累计 12s
      expect(d.isPaused, isTrue);
    });

    test('中途恢复移动会清零低速累计', () {
      final d = AutoPauseDetector(stillSeconds: 10);
      expect(d.feed(0.3, 8), AutoPauseEvent.none);
      expect(d.feed(2.0, 1), AutoPauseEvent.none); // 移动打断
      expect(d.feed(0.3, 8), AutoPauseEvent.none); // 重新累计 8s
      expect(d.feed(0.3, 2), AutoPauseEvent.shouldPause); // 10s
    });

    test('暂停后持续移动达到阈值触发恢复', () {
      final d = AutoPauseDetector(resumeSeconds: 3, resumeDistanceM: 4);
      d.feed(0.3, 10); // 暂停
      expect(d.feed(1.5, 2), AutoPauseEvent.none); // 2s
      expect(d.feed(0.4, 5), AutoPauseEvent.none); // 又停下，清零
      expect(d.feed(1.5, 2), AutoPauseEvent.none); // 2s
      expect(d.feed(1.8, 1), AutoPauseEvent.shouldResume); // 3s 且 4.8m
      expect(d.isPaused, isFalse);
    });

    test('静止 GPS 漂移不触发恢复：速度够但位移不足', () {
      // 原地漂移偶可产生 2 m/s 的点对速度，但短窗口累计位移很小。
      final d = AutoPauseDetector(); // 默认 5s / 10m
      d.feed(0.3, 10); // 暂停
      expect(d.feed(2.0, 2), AutoPauseEvent.none); // 4m
      expect(d.feed(2.0, 2), AutoPauseEvent.none); // 累计 4s/8m
      expect(d.feed(1.8, 1), AutoPauseEvent.none); // 5s 达标但 9.8m 未到
      expect(d.isPaused, isTrue);
    });

    test('漂移中途变慢会清零恢复累计', () {
      final d = AutoPauseDetector();
      d.feed(0.3, 10); // 暂停
      expect(d.feed(2.0, 2), AutoPauseEvent.none); // 2s
      expect(d.feed(0.4, 3), AutoPauseEvent.none); // 变慢：清零
      expect(d.feed(2.0, 2), AutoPauseEvent.none); // 重新累计 2s
      expect(d.isPaused, isTrue);
    });

    test('真实起跑：持续高速且位移达标才恢复', () {
      final d = AutoPauseDetector();
      d.feed(0.3, 10); // 暂停
      for (var i = 0; i < 4; i++) {
        expect(d.feed(2.5, 1), AutoPauseEvent.none); // 逐秒累计
      }
      expect(d.feed(2.5, 1), AutoPauseEvent.shouldResume); // 5s 且 12.5m
      expect(d.isPaused, isFalse);
    });

    test('迟滞：低于恢复阈值不算移动', () {
      final d = AutoPauseDetector(
        stillSeconds: 10,
        resumeSeconds: 3,
        stillSpeedMps: 0.5,
        resumeSpeedMps: 1.2,
      );
      d.feed(0.3, 10); // 暂停
      // 0.9 m/s 介于 still 与 resume 之间：不算移动也不算静止累计。
      expect(d.feed(0.9, 10), AutoPauseEvent.none);
      expect(d.isPaused, isTrue);
    });

    test('非有限速度与非法间隔被忽略', () {
      final d = AutoPauseDetector(stillSeconds: 2);
      expect(d.feed(double.nan, 1), AutoPauseEvent.none);
      expect(d.feed(0.3, 0), AutoPauseEvent.none);
      expect(d.feed(0.3, -1), AutoPauseEvent.none);
      expect(d.feed(0.3, 2), AutoPauseEvent.shouldPause);
    });

    test('reset 回到初始状态', () {
      final d = AutoPauseDetector(stillSeconds: 2);
      expect(d.feed(0.3, 1), AutoPauseEvent.none);
      d.reset();
      expect(d.feed(0.3, 1), AutoPauseEvent.none);
      expect(d.feed(0.3, 1), AutoPauseEvent.shouldPause);
    });
  });

  group('PaceTargetEvaluator（目标配速提醒）', () {
    PaceTargetEvaluator build() => PaceTargetEvaluator(
      targetSecPerKm: 300,
      toleranceSec: 20,
      confirmSeconds: 15,
      coolDownSeconds: 90,
    );

    test('在容差内不提示', () {
      final e = build();
      for (var i = 0; i < 20; i++) {
        expect(e.feed(305, 1), isNull);
      }
      expect(e.deviation, isNull);
    });

    test('持续偏慢达到确认时长后提示一次', () {
      final e = build();
      expect(e.feed(340, 1), isNull); // 偏离开始
      for (var i = 0; i < 14; i++) {
        expect(e.feed(340, 1), isNull, reason: '第 ${i + 2} 秒');
      }
      expect(e.feed(340, 1), PaceDeviation.tooSlow); // 累计 15 秒
      expect(e.deviation, PaceDeviation.tooSlow);
      // 冷却期内不再提示。
      expect(e.feed(340, 1), isNull);
      expect(e.feed(340, 60), isNull);
      expect(e.feed(340, 30), PaceDeviation.tooSlow); // 冷却结束
    });

    test('回到目标附近清除偏离状态', () {
      final e = build();
      expect(e.feed(340, 10), isNull);
      expect(e.deviation, PaceDeviation.tooSlow);
      expect(e.feed(305, 5), isNull);
      expect(e.deviation, isNull);
      // 重新偏离需要重新确认。
      expect(e.feed(340, 10), isNull);
    });

    test('配速数据不足（null）清除状态', () {
      final e = build();
      expect(e.feed(340, 10), isNull);
      expect(e.feed(null, 5), isNull);
      expect(e.deviation, isNull);
    });

    test('偏快方向识别', () {
      final e = build();
      expect(e.feed(250, 1), isNull);
      for (var i = 0; i < 14; i++) {
        e.feed(250, 1);
      }
      expect(e.feed(250, 1), PaceDeviation.tooFast);
    });

    test('reset 清空一切', () {
      final e = build();
      e.feed(340, 20);
      e.reset();
      expect(e.deviation, isNull);
      expect(e.feed(340, 5), isNull);
    });
  });

  group('parsePaceInput（目标配速输入）', () {
    test('m:ss 格式', () {
      expect(parsePaceInput('5:30'), 330);
      expect(parsePaceInput('0:59'), 59);
    });

    test('纯分钟（小数）', () {
      expect(parsePaceInput('5.5'), 330);
      expect(parsePaceInput('6'), 360);
    });

    test('非法输入返回 null', () {
      expect(parsePaceInput(''), isNull);
      expect(parsePaceInput('abc'), isNull);
      expect(parsePaceInput('5:75'), isNull);
      expect(parsePaceInput('-1:00'), isNull);
      expect(parsePaceInput('0'), isNull);
    });
  });

  group('parseDurationInput（手动补录时长）', () {
    test('m:ss 与 h:mm:ss', () {
      expect(parseDurationInput('30:00'), 1800);
      expect(parseDurationInput('1:05:00'), 3900);
      expect(parseDurationInput('0:45'), 45);
    });

    test('纯数字按分钟', () {
      expect(parseDurationInput('90'), 5400);
      expect(parseDurationInput('0.5'), 30);
    });

    test('非法输入返回 null', () {
      expect(parseDurationInput(''), isNull);
      expect(parseDurationInput('0'), isNull);
      expect(parseDurationInput('30:75'), isNull);
      expect(parseDurationInput('1:2:3:4'), isNull);
      expect(parseDurationInput('a:30'), isNull);
      expect(parseDurationInput('-5:00'), isNull);
    });
  });

  group('paceAlertText（配速提醒播报）', () {
    test('中文播报当前配速与目标', () {
      expect(
        paceAlertText(
          deviation: PaceDeviation.tooSlow,
          paceSecPerKm: 340,
          targetSecPerKm: 310,
          english: false,
        ),
        '当前配速5分40秒，慢于目标5分10秒',
      );
      expect(
        paceAlertText(
          deviation: PaceDeviation.tooFast,
          paceSecPerKm: 250,
          targetSecPerKm: 300,
          english: false,
        ),
        '当前配速4分10秒，快于目标5分00秒',
      );
    });

    test('英文播报', () {
      expect(
        paceAlertText(
          deviation: PaceDeviation.tooFast,
          paceSecPerKm: 250,
          targetSecPerKm: 300,
          english: true,
        ),
        'Current pace 4 minutes 10 seconds, faster than target 5 minutes 0 seconds',
      );
    });

    test('秒位四舍五入带 60 进位（299.7 → 5分00秒）', () {
      expect(
        paceAlertText(
          deviation: PaceDeviation.tooSlow,
          paceSecPerKm: 299.7,
          targetSecPerKm: 300,
          english: false,
        ),
        '当前配速5分00秒，慢于目标5分00秒',
      );
    });

    test('实时配速缺失时只报方向与目标', () {
      expect(
        paceAlertText(
          deviation: PaceDeviation.tooSlow,
          paceSecPerKm: null,
          targetSecPerKm: 310,
          english: false,
        ),
        '慢于目标5分10秒',
      );
      expect(
        paceAlertText(
          deviation: PaceDeviation.tooSlow,
          paceSecPerKm: null,
          targetSecPerKm: 310,
          english: true,
        ),
        'slower than target 5 minutes 10 seconds',
      );
    });
  });

  group('formatPaceInput', () {
    test('秒转 m:ss', () {
      expect(formatPaceInput(330), '5:30');
      expect(formatPaceInput(300), '5:00');
      expect(formatPaceInput(65.4), '1:05');
    });
  });
}
