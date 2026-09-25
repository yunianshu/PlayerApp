import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/run_record.dart';
import '../core/theme.dart';

/// 在"地图"背景上绘制 GPS 轨迹（自动适配边界，保持经纬度比例）。
/// 颜色跟随当前主题：白天浅色网格 + 靛蓝轨迹，夜间深色网格 + 珊瑚轨迹。
class RoutePainter extends CustomPainter {
  final List<RunPoint> points;
  final double strokeWidth;
  final AppPalette palette;

  RoutePainter(
    this.points, {
    this.strokeWidth = 4,
    this.palette = AppPalette.light,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 背景网格（模拟地图道路）
    final gridPaint = Paint()
      ..color = palette.mapLine
      ..strokeWidth = 1.5;
    const step = 56.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = step / 2; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (points.length < 2) return;

    // 经纬度 → 画布坐标（留边距，等比缩放）
    double minLat = points.first.lat, maxLat = minLat;
    double minLng = points.first.lng, maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    const pad = 28.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    final spanLat = (maxLat - minLat).abs().clamp(1e-5, double.infinity);
    final spanLng = (maxLng - minLng).abs().clamp(1e-5, double.infinity);
    // 经度方向按 cos(平均纬度) 收缩，否则轨迹横向被拉长变形。
    final cosLat = math.max(0.2, math.cos((minLat + maxLat) / 2 * math.pi / 180));
    final scale = math.min(w / (spanLng * cosLat), h / spanLat);
    Offset project(RunPoint p) => Offset(
      pad + (p.lng - minLng) * cosLat * scale + (w - spanLng * cosLat * scale) / 2,
      h - ((p.lat - minLat) * scale + (h - spanLat * scale) / 2) + pad,
    );

    final path = ui.Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(project(p).dx, project(p).dy);
    }

    // 底层描边（深色宽边）+ 主轨迹
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.mapB
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 起点 / 终点
    final start = project(points.first), end = project(points.last);
    canvas.drawCircle(start, 5, Paint()..color = palette.textSecondary);
    canvas.drawCircle(
      start,
      5,
      Paint()
        ..color = palette.mapB
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(end, 7, Paint()..color = palette.accent);
    canvas.drawCircle(
      end,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) {
    // points 是原地增长的可变 List：引用相同但长度变化时（跑步中）需要重绘；
    // 引用不同（详情/总结页换新列表）必然重绘。
    if (!identical(oldDelegate.points, points)) return true;
    if (oldDelegate.points.length != points.length) return true;
    return !identical(oldDelegate.palette, palette);
  }
}
