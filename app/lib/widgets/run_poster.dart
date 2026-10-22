import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../models/run_record.dart';
import '../pages/home_page.dart' show formatRunTime;
import 'route_painter.dart';

/// 分享海报：跟随当前主题配色（浅色/暗色/编辑风各得其所）。
/// 完成页与详情页共用预览，并通过 RepaintBoundary 导出图片。
class RunPoster extends StatelessWidget {
  final RunRecord record;
  final List<RunPoint> points;

  const RunPoster({super.key, required this.record, required this.points});

  static const size = Size(340, 640);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = record;
    final displayFont = c.isEditorial ? 'Playfair Display' : null;
    final displayFontFallback = c.isEditorial ? const ['Noto Sans SC'] : null;
    return Container(
      width: size.width,
      height: size.height,
      color: c.bg,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '跑迹 RunTrail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: displayFont,
                    fontFamilyFallback: displayFontFallback,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatRunTime(r.start),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ),
            ],
          ),
          if (r.displayTitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.displayTitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: r.isManual ? 0 : 210,
            decoration: BoxDecoration(
              gradient: mapGradient(c),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: c.stroke),
            ),
            child: r.isManual
                ? null
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: CustomPaint(
                      painter: RoutePainter(points, strokeWidth: 3, palette: c),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                r.distanceKm.toStringAsFixed(2),
                style: TextStyle(
                  fontFamily: displayFont,
                  fontFamilyFallback: displayFontFallback,
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  // 编辑风荧光绿在米底对比不足（1.29），大数字用墨色。
                  color: c.isEditorial ? c.textPrimary : c.accent,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'km',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _metric(
                  c,
                  Icons.speed_outlined,
                  '平均配速'.tr,
                  formatPace(r.avgPaceSecPerKm),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric(
                  c,
                  Icons.timer_outlined,
                  '时长'.tr,
                  formatDuration(Duration(seconds: r.durationS)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metric(
                  c,
                  Icons.local_fire_department_outlined,
                  '卡路里'.tr,
                  '${r.calories} kcal',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric(
                  c,
                  Icons.terrain_outlined,
                  '累计爬升'.tr,
                  '${r.climbM.round()} m',
                ),
              ),
            ],
          ),
          const Spacer(),
          Divider(height: 1, color: c.divider),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '记录每一步'.tr,
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.directions_run, size: 13, color: c.onAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(AppPalette c, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: c.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
