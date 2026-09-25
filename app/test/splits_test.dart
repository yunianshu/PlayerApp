import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/pages/summary_page.dart' show splitsOf;

RunPoint _pt(double lat, double lng, int seconds) => RunPoint(
  lat: lat,
  lng: lng,
  altitude: 0,
  time: DateTime(2026, 9, 25, 8, 0, 0).add(Duration(seconds: seconds)),
);

void main() {
  test('不足两个点返回空', () {
    expect(splitsOf(const []), isEmpty);
    expect(splitsOf([_pt(39.0, 116.0, 0)]), isEmpty);
  });

  test('按每公里切段', () {
    // 纬度 0.009 度 ≈ 1km；每公里跑 6 分钟。
    final pts = <RunPoint>[
      _pt(39.0, 116.0, 0),
      _pt(39.009, 116.0, 360),
      _pt(39.018, 116.0, 720),
      _pt(39.020, 116.0, 800), // 不足一公里的尾巴不计
    ];
    final splits = splitsOf(pts);
    expect(splits.length, 2);
    expect(splits[0].$1, 1);
    expect(splits[1].$1, 2);
    expect(splits[0].$2, closeTo(360, 5));
  });

  test('单点重复（零距离）不产生分段', () {
    final pts = <RunPoint>[
      _pt(39.0, 116.0, 0),
      _pt(39.0, 116.0, 600),
    ];
    expect(splitsOf(pts), isEmpty);
  });
}
