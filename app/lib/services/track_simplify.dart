import 'dart:math' as math;

import '../models/run_record.dart';
import 'run_math.dart';

/// 轨迹抽稀（Douglas–Peucker），只用于绘制与分享图，存储保持原始点。
/// 分段边界（暂停/恢复）两侧端点始终保留，段与段之间不会连线。
List<RunPoint> simplifyTrack(
  List<RunPoint> points, {
  double toleranceM = 3,
  int maxPoints = 600,
}) {
  if (points.length <= 3) return List.of(points);
  final kept = _simplifySegment(points, 0, points.length - 1, toleranceM);
  if (kept.length > maxPoints) {
    return _thinUniformly(kept, maxPoints);
  }
  return kept;
}

/// 经典 DP：递归保留距弦线超过容差的点。
List<RunPoint> _simplifySegment(
  List<RunPoint> points,
  int start,
  int end,
  double toleranceM,
) {
  if (end - start < 2) return points.sublist(start, end + 1);
  // 分段边界：前段终点与后段起点必须都保留，且各段独立简化。
  for (var i = start + 1; i < end; i++) {
    if (points[i].startsSegment) {
      return [
        ..._simplifySegment(points, start, i, toleranceM),
        ..._simplifySegment(points, i, end, toleranceM),
      ];
    }
  }
  var maxDist = -1.0;
  var maxIdx = -1;
  final a = points[start], b = points[end];
  for (var i = start + 1; i < end; i++) {
    final d = _perpendicularDistanceM(points[i], a, b);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }
  if (maxDist > toleranceM && maxIdx > 0) {
    final left = _simplifySegment(points, start, maxIdx, toleranceM);
    final right = _simplifySegment(points, maxIdx, end, toleranceM);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [points[start], points[end]];
}

/// 点到弦线的近似垂直距离（米）：以弦中点为原点的等距圆柱投影。
double _perpendicularDistanceM(RunPoint p, RunPoint a, RunPoint b) {
  final lat0 = (a.lat + b.lat) / 2;
  final kx = 111320.0 * math.cos(lat0 * math.pi / 180);
  const ky = 110540.0;
  final ax = (a.lng - p.lng) * kx, ay = (a.lat - p.lat) * ky;
  final bx = (b.lng - p.lng) * kx, by = (b.lat - p.lat) * ky;
  final dx = bx - ax, dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  if (lenSq <= 0) return RunMath.haversineM(p.lat, p.lng, a.lat, a.lng);
  var t = -(ax * dx + ay * dy) / lenSq;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt(cx * cx + cy * cy);
}

/// 仍超上限时均匀抽稀（保留分段边界与首尾）。
List<RunPoint> _thinUniformly(List<RunPoint> points, int maxPoints) {
  final step = points.length / maxPoints;
  final result = <RunPoint>[points.first];
  var nextIndex = step;
  for (var i = 1; i < points.length - 1; i++) {
    if (points[i].startsSegment || i >= nextIndex) {
      result.add(points[i]);
      nextIndex += step;
    }
  }
  result.add(points.last);
  return result;
}
