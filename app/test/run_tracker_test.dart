import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/services/run_math.dart';

void main() {
  group('settledElapsedMs（暂停结算）', () {
    final start = DateTime(2026, 9, 25, 8, 0, 0);

    test('未暂停：流逝时间即运动时长', () {
      final now = start.add(const Duration(minutes: 30));
      expect(
        RunMath.settledElapsedMs(start: start, totalPausedMs: 0, now: now),
        30 * 60 * 1000,
      );
    });

    test('已结算的历史暂停从累计中扣除', () {
      final now = start.add(const Duration(minutes: 40));
      expect(
        RunMath.settledElapsedMs(
          start: start,
          totalPausedMs: 10 * 60 * 1000,
          now: now,
        ),
        30 * 60 * 1000,
      );
    });

    test('暂停中停止：进行中的暂停也必须被扣除（回归：暂停时长被计入运动时长）', () {
      // 跑 30 分钟，暂停 10 分钟后（尚未 resume）直接 stop。
      final pauseStart = start.add(const Duration(minutes: 30));
      final stopAt = pauseStart.add(const Duration(minutes: 10));
      expect(
        RunMath.settledElapsedMs(
          start: start,
          totalPausedMs: 0,
          pauseStart: pauseStart,
          now: stopAt,
        ),
        30 * 60 * 1000,
        reason: 'stop 时长应只含运动时间，暂停的 10 分钟不应被计入',
      );
    });
  });

  group('haversineM', () {
    test('同一点距离为 0', () {
      expect(RunMath.haversineM(39.9, 116.4, 39.9, 116.4), 0);
    });

    test('已知距离量级正确（北京天安门到王府井约 1.7km）', () {
      final d = RunMath.haversineM(39.9087, 116.3975, 39.9097, 116.4109);
      expect(d, inExclusiveRange(900, 1300));
    });

    test('纬度方向 0.001 度约 111 米', () {
      final d = RunMath.haversineM(39.0, 116.0, 39.001, 116.0);
      expect(d, inExclusiveRange(105, 117));
    });
  });
}
