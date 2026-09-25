import 'dart:math' as math;

/// 跑步相关纯计算（无插件依赖，可独立单测）。
class RunMath {
  RunMath._();

  /// 球面两点距离（米）。
  static double haversineM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  /// 运动时长结算（毫秒）：总流逝减去暂停累计；暂停进行中时结算到当前时刻。
  static int settledElapsedMs({
    required DateTime start,
    required int totalPausedMs,
    DateTime? pauseStart,
    required DateTime now,
  }) {
    var paused = totalPausedMs;
    if (pauseStart != null) {
      paused += now.difference(pauseStart).inMilliseconds;
    }
    return now.difference(start).inMilliseconds - paused;
  }
}
