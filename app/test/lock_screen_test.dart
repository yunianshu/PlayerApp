import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/services/tracking_policies.dart';

void main() {
  test('锁屏文案：距离 + 配速 + 用时', () {
    final text = lockScreenStatsText(
      distanceM: 3420,
      elapsedSeconds: 1132,
      paceSecPerKm: 331,
      english: false,
    );
    expect(text, "3.42 公里 · 5:31 /公里 · 18:52");
  });

  test('锁屏文案：配速数据不足时省略配速段', () {
    final text = lockScreenStatsText(
      distanceM: 80,
      elapsedSeconds: 65,
      paceSecPerKm: null,
      english: false,
    );
    expect(text, '0.08 公里 · 1:05');
  });

  test('锁屏文案：超过一小时带小时位', () {
    final text = lockScreenStatsText(
      distanceM: 15200,
      elapsedSeconds: 4810,
      paceSecPerKm: 316,
      english: false,
    );
    expect(text, "15.20 公里 · 5:16 /公里 · 1:20:10");
  });

  test('锁屏文案英文形态', () {
    final text = lockScreenStatsText(
      distanceM: 3420,
      elapsedSeconds: 1132,
      paceSecPerKm: 331,
      english: true,
    );
    expect(text, "3.42 km · 5:31 /km · 18:52");
  });
}
