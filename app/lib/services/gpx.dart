import '../models/run_record.dart';
import '../data/database.dart';
import 'run_math.dart';

/// GPX 1.1 导出：仅含轨迹点的记录可导出。
/// 暂停产生的段边界会拆成多个 `trkseg`，段与段之间不连线。
String buildGpx(RunRecord run, List<RunPoint> points) {
  final name = _escape(_titleOf(run));
  final buf = StringBuffer();
  buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  buf.writeln(
    '<gpx version="1.1" creator="RunTrail" '
    'xmlns="http://www.topografix.com/GPX/1/1">',
  );
  buf.writeln('<metadata><name>$name</name></metadata>');
  buf.writeln('<trk>');
  buf.write('<name>$name</name>');
  if (points.isNotEmpty) {
    buf.write('<trkseg>');
    for (var i = 0; i < points.length; i++) {
      if (i > 0 && points[i].startsSegment) {
        buf.write('</trkseg><trkseg>');
      }
      buf.write(_trkpt(points[i]));
    }
    buf.write('</trkseg>');
  }
  buf.write('</trk>');
  buf.write('</gpx>');
  return buf.toString();
}

String _titleOf(RunRecord run) {
  final title = run.displayTitle;
  if (title.isNotEmpty) return title;
  return 'RunTrail ${run.start.toIso8601String().substring(0, 10)}';
}

String _trkpt(RunPoint p) {
  final lat = p.lat.toStringAsFixed(6);
  final lon = p.lng.toStringAsFixed(6);
  final ele = p.altitude.toStringAsFixed(1);
  final time = p.time.toUtc().toIso8601String();
  return '<trkpt lat="$lat" lon="$lon"><ele>$ele</ele><time>$time</time></trkpt>';
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// GPX 导入结果：一条完整的跑步记录 + 重建的轨迹点。
class GpxImport {
  final RunRecord record;
  final List<RunPoint> points;
  const GpxImport({required this.record, required this.points});
}

/// GPX 内容不合法（非 XML / 无轨迹点 / 缺时间信息）。
class GpxFormatException implements Exception {
  final String reason;
  const GpxFormatException(this.reason);
}

class _RawPt {
  final double lat;
  final double lng;
  final double altitude;
  DateTime? time;
  final bool startsSegment;
  _RawPt(this.lat, this.lng, this.altitude, this.time, this.startsSegment);
}

/// 解析 GPX 1.1 文件内容（Keep / Strava / Garmin 等平台导出）为一条跑步记录。
///
/// - 文件里的全部 `<trk>`/`<trkseg>` 合并为一次跑步；每个后续段的首点标记
///   `startsSegment`（与 App 自身暂停语义一致，地图上不连线）。
/// - 距离用与实时记录相同的口径重算：haversine + 最小段距 2.5m +
///   12m/s 跳点过滤；时长为各段内时间跨度的合计（段间间隙视为暂停剔除）。
/// - 爬升用锚点法累计正向海拔变化（3m 死区，与实时记录一致）。
/// - 卡路里按 App 统一公式（km × 65 × 1.036）推导。
/// - 会话 ID 固定为 `gpx-<开始时间毫秒>`，重复导入同一文件幂等跳过。
GpxImport parseGpx(String xml) {
  // GPX 结构固定（trkpt 的 lat/lon 是属性、ele/time 是子元素），
  // 按文档序扫描标签即可，不引入 XML 解析依赖。
  final points = <_RawPt>[];
  var sawFirstPoint = false;
  var pendingSegmentStart = false;
  for (final m in RegExp(r'<trkseg\b|<trkpt\b[^>]*>').allMatches(xml)) {
    final tag = m.group(0)!;
    if (tag.startsWith('<trkseg')) {
      pendingSegmentStart = true;
      continue;
    }
    final lat = double.tryParse(
      RegExp(r'\blat="([^"]+)"').firstMatch(tag)?.group(1) ?? '',
    );
    final lng = double.tryParse(
      RegExp(r'\blon="([^"]+)"').firstMatch(tag)?.group(1) ?? '',
    );
    if (lat == null || lng == null) continue;
    final double ele;
    DateTime? time;
    if (tag.endsWith('/>')) {
      ele = 0; // 自闭合点没有子元素。
    } else {
      final bodyEnd = xml.indexOf('</trkpt>', m.end);
      final body = xml.substring(m.end, bodyEnd < 0 ? m.end : bodyEnd);
      ele =
          double.tryParse(
            RegExp(r'<ele>\s*([^<]+?)\s*</ele>').firstMatch(body)?.group(1) ??
                '',
          ) ??
          0;
      final timeRaw =
          RegExp(r'<time>\s*([^<]+?)\s*</time>').firstMatch(body)?.group(1);
      time = timeRaw == null ? null : DateTime.tryParse(timeRaw);
    }
    points.add(
      _RawPt(lat, lng, ele, time, sawFirstPoint && pendingSegmentStart),
    );
    sawFirstPoint = true;
    pendingSegmentStart = false;
  }
  if (points.length < 2) throw const GpxFormatException('no_track_points');

  // 缺时间戳的点在相邻有时间点之间线性插值（首尾缺失就近取斜率外推）。
  _interpolateTimes(points);
  // 有效时间不足 2 个（无法推算时长/先后）按格式错误处理。
  if (points.where((p) => p.time != null).length < 2) {
    throw const GpxFormatException('no_time');
  }

  const minSegM = 2.5;
  const jumpSpeed = 12.0;
  var distanceM = 0.0;
  var activeMs = 0;
  var climbM = 0.0;
  double? climbAnchor;
  var elapsedMs = 0;
  final built = <RunPoint>[];
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    var thisElapsed = elapsedMs;
    var newSegment = p.startsSegment;
    if (i > 0 && !p.startsSegment) {
      final prev = points[i - 1];
      final dt = p.time!.difference(prev.time!).inMilliseconds;
      if (dt > 0) {
        activeMs += dt;
        elapsedMs += dt;
        thisElapsed = elapsedMs;
      }
      final d = RunMath.haversineM(prev.lat, prev.lng, p.lat, p.lng);
      if (d >= minSegM && dt > 0 && d / (dt / 1000) < jumpSpeed) {
        distanceM += d;
      }
    } else {
      newSegment = true;
    }
    // 爬升锚点法：段首重置锚点；正向满 3m 累计，负向满 3m 仅重置。
    final anchor = newSegment ? null : climbAnchor;
    if (anchor == null) {
      climbAnchor = p.altitude;
    } else {
      final change = p.altitude - anchor;
      if (change >= 3.0) {
        climbM += change;
        climbAnchor = p.altitude;
      } else if (change <= -3.0) {
        climbAnchor = p.altitude;
      }
    }
    built.add(
      RunPoint(
        lat: p.lat,
        lng: p.lng,
        altitude: p.altitude,
        time: p.time!,
        startsSegment: i > 0 && p.startsSegment,
        elapsedMs: thisElapsed,
      ),
    );
  }

  final timed = points.where((p) => p.time != null).map((p) => p.time!).toList();
  final start = timed.first;
  final end = timed.last;
  if (!end.isAfter(start)) throw const GpxFormatException('no_time');
  final durationS = (activeMs / 1000).round().clamp(1, 1 << 30);
  final km = distanceM / 1000;
  // 标题取文档里第一个 <name>（本 App 导出在 metadata，其他平台多在 trk）。
  final title =
      RegExp(r'<name>\s*([^<]+?)\s*</name>').firstMatch(xml)?.group(1)?.trim() ??
      '';

  final record = RunRecord(
    sessionId: 'gpx-${start.millisecondsSinceEpoch}',
    start: start,
    end: end,
    distanceM: distanceM,
    durationS: durationS,
    calories: (km * 65 * 1.036).round(),
    climbM: climbM,
    source: RunRecord.sourceGpx,
    title: title,
    notes: '',
  );
  return GpxImport(record: record, points: built);
}

/// 原地插值补齐缺失时间。GPX 的时间都是 UTC ISO 字符串，正常导出全有；
/// 个别工具会丢中间点的时间戳，用前后最近有效时间线性内插。
void _interpolateTimes(List<_RawPt> pts) {
  final valid = <int>[
    for (var i = 0; i < pts.length; i++)
      if (pts[i].time != null) i,
  ];
  if (valid.length < 2) return; // 少于两个有效时间：交由上层按 no_time 报错。
  int slopeBetween(int a, int b) =>
      b > a
          ? ((pts[b].time!.millisecondsSinceEpoch -
                      pts[a].time!.millisecondsSinceEpoch) /
                  (b - a))
              .round()
          : 1000;
  for (var i = 0; i < pts.length; i++) {
    if (pts[i].time != null) continue;
    int? prev;
    int? next;
    for (final v in valid) {
      if (v < i) prev = v;
      if (v > i && next == null) next = v;
    }
    final int stepMs;
    final int anchorIdx;
    if (prev != null && next != null) {
      stepMs = slopeBetween(prev, next);
      anchorIdx = prev;
    } else if (prev != null) {
      anchorIdx = prev;
      stepMs = valid.length > 1
          ? slopeBetween(valid[valid.length - 2], valid[valid.length - 1])
          : 1000;
    } else {
      anchorIdx = next!;
      stepMs = valid.length > 1 ? slopeBetween(valid[0], valid[1]) : 1000;
      // 尾部锚点在前方：外推时步长取负。
    }
    final sign = prev != null ? 1 : -1;
    // GPX 时间都是 UTC：插值结果保持 UTC 标志，避免本地时区偏移。
    pts[i].time = DateTime.fromMillisecondsSinceEpoch(
      pts[anchorIdx].time!.millisecondsSinceEpoch +
          sign * (i - anchorIdx).abs() * stepMs,
      isUtc: true,
    );
  }
}

/// GPX 导入结果：imported = 本次新写入；duplicate = sessionKey 已存在，未写入。
enum GpxImportStatus { imported, duplicate }

class GpxImportOutcome {
  final GpxImportStatus status;
  final GpxImport import;
  const GpxImportOutcome(this.status, this.import);
  bool get isDuplicate => status == GpxImportStatus.duplicate;
}

/// 解析 GPX 并写入数据库。sessionId 按开始时间生成，同一文件重复导入
/// 只会插入一次（duplicate），保证幂等。
Future<GpxImportOutcome> importRunFromGpx(
  String xml, {
  RunDatabase? db,
}) async {
  final database = db ?? RunDatabase.instance;
  final gpx = parseGpx(xml);
  if (await database.hasSession(gpx.record.sessionKey)) {
    return GpxImportOutcome(GpxImportStatus.duplicate, gpx);
  }
  await database.insertRun(gpx.record, gpx.points);
  return GpxImportOutcome(GpxImportStatus.imported, gpx);
}
