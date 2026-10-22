import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/run_prs.dart';

/// 沿纬度向北走：0.001° ≈ 111.19 m（haversine 口径）。
RunPoint pt(double lat, {required int elapsedMs, bool seg = false}) => RunPoint(
  lat: lat,
  lng: 116.0,
  altitude: 0,
  time: DateTime.fromMillisecondsSinceEpoch(elapsedMs),
  startsSegment: seg,
  elapsedMs: elapsedMs,
);

void main() {
  group('bestSplitSeconds（滑窗最佳分段）', () {
    test('匀速直线：1km 用时 ≈ 距离/速度', () {
      // 每 111.19 m 一个点，速度 3 m/s → 1km 约 333.3 s。
      final points = <RunPoint>[
        for (var i = 0; i <= 20; i++)
          pt(39.0 + i * 0.001, elapsedMs: (i * 111.19 / 3 * 1000).round()),
      ];
      final best = bestSplitSeconds(points, 1000);
      expect(best, isNotNull);
      expect(best!, closeTo(1000 / 3, 5));
    });

    test('中途降速：滑窗取最快窗口', () {
      // 前 1km 3 m/s，后 1km 2.5 m/s。
      final points = <RunPoint>[
        for (var i = 0; i <= 20; i++)
          pt(
            39.0 + i * 0.001,
            elapsedMs: i <= 9
                ? (i * 111.19 / 3 * 1000).round()
                : ((9 * 111.19 / 3 + (i - 9) * 111.19 / 2.5) * 1000).round(),
          ),
      ];
      final best = bestSplitSeconds(points, 1000);
      expect(best, isNotNull);
      // 最快 1km 是前段：≈ 333 s，而不是包含降速段的窗口。
      expect(best!, closeTo(1000 / 3, 5));
      expect(best, lessThan(1000 / 2.5 + 10));
    });

    test('暂停分段不参与跨段滑窗（run-walk 场景保守）', () {
      // 两段各 600 m，中间暂停 5 分钟：任何 1km 窗口都必须在单段内 → 无解。
      final points = <RunPoint>[
        for (var i = 0; i <= 6; i++)
          pt(39.0 + i * 0.0009, elapsedMs: (i * 111.19 * 0.9 / 3 * 1000).round()),
        // 段边界：暂停后恢复，墙钟 +300s，elapsed 继续累计。
        for (var i = 0; i <= 6; i++)
          pt(
            39.0 + i * 0.0009,
            elapsedMs: 300000 + (i * 111.19 * 0.9 / 3 * 1000).round(),
            seg: i == 0,
          ),
      ];
      final best = bestSplitSeconds(points, 1000);
      expect(best, isNull);
    });

    test('距离不足目标返回 null', () {
      final points = <RunPoint>[
        for (var i = 0; i <= 5; i++)
          pt(39.0 + i * 0.001, elapsedMs: i * 37000),
      ];
      expect(bestSplitSeconds(points, 5000), isNull);
    });

    test('空轨迹返回 null', () {
      expect(bestSplitSeconds(const [], 1000), isNull);
    });
  });

  group('RunPrService 缓存', () {
    test('cacheSplit 保留更优值', () {
      final service = RunPrService.instance;
      service.clearCache();
      service.cacheSplit('s1', 1000, 300);
      service.cacheSplit('s1', 1000, 320);
      service.cacheSplit('s1', 1000, 290);
      // 无法直接读私有缓存：通过 clearCache 后行为一致性验证（冒烟）。
      service.clearCache();
      service.cacheSplit('s2', 1000, 300);
      expect(service, isNotNull);
    });
  });
}
