import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/track_simplify.dart';

RunPoint pt(double lat, double lng, {bool seg = false}) => RunPoint(
  lat: lat,
  lng: lng,
  altitude: 0,
  time: DateTime.fromMillisecondsSinceEpoch((lat * 1e6).round()),
  startsSegment: seg,
);

void main() {
  group('simplifyTrack（Douglas–Peucker 抽稀）', () {
    test('共线点收敛为两端点', () {
      final points = [
        for (var i = 0; i <= 100; i++) pt(39.0 + i * 0.0001, 116.0),
      ];
      final simplified = simplifyTrack(points);
      expect(simplified.length, 2);
      expect(simplified.first.lat, points.first.lat);
      expect(simplified.last.lat, points.last.lat);
    });

    test('拐点被保留', () {
      final points = [
        pt(39.0, 116.0),
        for (var i = 1; i < 50; i++) pt(39.0 + i * 0.0001, 116.0),
        // 直行后突然向西拐 500 米再直行。
        for (var i = 1; i <= 50; i++)
          pt(39.0 + 50 * 0.0001, 116.0 - i * 0.0005),
      ];
      final simplified = simplifyTrack(points, toleranceM: 3);
      expect(simplified.length, greaterThanOrEqualTo(3));
      // 拐点必须在结果中（它偏离弦线约 500 米）。
      expect(
        simplified.any((p) => (p.lat - 39.0050).abs() < 1e-9),
        isTrue,
      );
    });

    test('分段边界始终保留且不跨段连线', () {
      final points = [
        for (var i = 0; i < 20; i++) pt(39.0 + i * 0.0001, 116.0),
        // 暂停后从原点重新开始的第二段。
        for (var i = 0; i < 20; i++)
          pt(39.0 + i * 0.0001, 116.0, seg: i == 0),
      ];
      final simplified = simplifyTrack(points);
      // 每段的端点都在：至少 4 个（两段 × 首尾）。
      expect(simplified.length, greaterThanOrEqualTo(4));
      expect(simplified.first.startsSegment, isFalse);
      // 第 21 个点（第二段起点）必须保留。
      final segStart = points[20];
      expect(simplified.contains(segStart), isTrue);
    });

    test('短轨迹原样返回', () {
      final points = [pt(39.0, 116.0), pt(39.001, 116.0)];
      final simplified = simplifyTrack(points);
      expect(identical(simplified, points), isFalse);
      expect(simplified.length, 2);
    });

    test('超出上限后均匀抽稀且仍保留分段边界', () {
      final points = <RunPoint>[
        for (var i = 0; i < 2000; i++) pt(39.0 + i * 1e-7, 116.0),
        for (var i = 0; i < 2000; i++)
          pt(39.0002 + i * 1e-7, 116.0, seg: i == 0),
      ];
      final simplified = simplifyTrack(points, toleranceM: 0.01, maxPoints: 100);
      expect(simplified.length, lessThanOrEqualTo(110));
      expect(simplified.first, points.first);
      expect(simplified.last, points.last);
      expect(simplified.contains(points[2000]), isTrue);
    });
  });
}
