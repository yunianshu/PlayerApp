import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/services/tracking_policies.dart';

void main() {
  test('落后目标：换算为落后米数', () {
    // 目标 5:00/km，跑了 330 秒只前进 1000 米；
    // 按目标应完成 330/300*1000 = 1100 米 → 落后 100 米。
    final diff = paceTargetDiffMeters(
      targetSecPerKm: 300,
      elapsedSeconds: 330,
      distanceM: 1000,
    );
    expect(diff, closeTo(-100, 0.001));
  });

  test('领先目标：换算为领先米数', () {
    // 目标 5:00/km，300 秒跑了 1100 米 → 按目标应 1000 米 → 领先 100 米。
    final diff = paceTargetDiffMeters(
      targetSecPerKm: 300,
      elapsedSeconds: 300,
      distanceM: 1100,
    );
    expect(diff, closeTo(100, 0.001));
  });

  test('正好按目标配速：差值为 0', () {
    final diff = paceTargetDiffMeters(
      targetSecPerKm: 360,
      elapsedSeconds: 720,
      distanceM: 2000,
    );
    expect(diff, closeTo(0, 0.001));
  });

  test('数据不足返回 null', () {
    expect(
      paceTargetDiffMeters(targetSecPerKm: 0, elapsedSeconds: 100, distanceM: 1000),
      isNull,
    );
    expect(
      paceTargetDiffMeters(targetSecPerKm: 300, elapsedSeconds: 0, distanceM: 1000),
      isNull,
    );
    expect(
      paceTargetDiffMeters(targetSecPerKm: 300, elapsedSeconds: 100, distanceM: 0),
      isNull,
    );
  });
}
