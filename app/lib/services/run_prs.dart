import '../data/database.dart';
import '../models/run_record.dart';
import 'run_math.dart';

/// 个人纪录（PR）：最快 1/5/10 公里（由轨迹点滑窗计算）+ 最长单次。
class RunPrs {
  final double? best1kmSec;
  final double? best5kmSec;
  final double? best10kmSec;
  final RunRecord? longestRun;
  final RunRecord? longestDurationRun;

  const RunPrs({
    this.best1kmSec,
    this.best5kmSec,
    this.best10kmSec,
    this.longestRun,
    this.longestDurationRun,
  });
}

/// PR 计算服务：按会话缓存单条轨迹的滑窗结果（保存后的记录不可变）。
class RunPrService {
  RunPrService._();
  static final RunPrService instance = RunPrService._();

  final Map<String, double> _best1 = {};
  final Map<String, double> _best5 = {};
  final Map<String, double> _best10 = {};

  /// 清空缓存（测试用）。
  void clearCache() {
    _best1.clear();
    _best5.clear();
    _best10.clear();
  }

  Future<RunPrs> compute() async {
    final db = RunDatabase.instance;
    final runs = await db.listRuns();
    RunRecord? longest;
    RunRecord? longestDuration;
    for (final r in runs) {
      if (longest == null || r.distanceM > longest.distanceM) longest = r;
      if (longestDuration == null || r.durationS > longestDuration.durationS) {
        longestDuration = r;
      }
    }
    double? b1 = await _aggregate(runs, 1000, _best1);
    double? b5 = await _aggregate(runs, 5000, _best5);
    double? b10 = await _aggregate(runs, 10000, _best10);
    return RunPrs(
      best1kmSec: b1,
      best5kmSec: b5,
      best10kmSec: b10,
      longestRun: longest,
      longestDurationRun: longestDuration,
    );
  }

  Future<double?> _aggregate(
    List<RunRecord> runs,
    double targetM,
    Map<String, double> cache,
  ) async {
    double? best;
    for (final r in runs) {
      // 手动补录没有轨迹；不足目标距离的记录不可能包含目标滑窗。
      if (r.isManual || r.distanceM < targetM || r.id == null) continue;
      final cached = cache[r.sessionKey];
      final value =
          cached ?? await _bestSplitOfRun(r.id!, r.sessionKey, targetM);
      if (value == null) continue;
      cache[r.sessionKey] = value;
      if (best == null || value < best) best = value;
    }
    return best;
  }

  Future<double?> _bestSplitOfRun(
    int runId,
    String sessionKey,
    double targetM,
  ) async {
    final points = await RunDatabase.instance.getPoints(runId);
    final best = bestSplitSeconds(points, targetM);
    if (best == null) return null;
    return best;
  }

  void cacheSplit(String sessionKey, double targetM, double seconds) {
    final cache = targetM == 1000
        ? _best1
        : targetM == 5000
        ? _best5
        : _best10;
    final existing = cache[sessionKey];
    if (existing == null || seconds < existing) cache[sessionKey] = seconds;
  }
}

/// 单条轨迹内覆盖 [targetM] 米的最短用时（秒）。
/// 分段（暂停边界）内部做双指针滑窗；跨段包含暂停用时，不参与计算。
/// 旧记录（无 elapsed_ms）回退壁钟时间，暂停会被计入——对旧数据尽力而为。
double? bestSplitSeconds(List<RunPoint> points, double targetM) {
  double? best;
  var segment = <RunPoint>[];
  void flush() {
    if (segment.length >= 2) {
      final value = _bestSplitInSegment(segment, targetM);
      final currentBest = best;
      if (value != null && (currentBest == null || value < currentBest)) {
        best = value;
      }
    }
    segment = <RunPoint>[];
  }

  for (final p in points) {
    if (p.startsSegment && segment.isNotEmpty) flush();
    segment.add(p);
  }
  flush();
  return best;
}

double? _bestSplitInSegment(List<RunPoint> segment, double targetM) {
  // 累计距离与累计用时（秒）。
  final cumDist = List<double>.filled(segment.length, 0);
  final cumTime = List<double>.filled(segment.length, 0);
  final hasElapsed = segment.every((p) => p.elapsedMs != null);
  for (var i = 1; i < segment.length; i++) {
    final a = segment[i - 1], b = segment[i];
    final d = RunMath.haversineM(a.lat, a.lng, b.lat, b.lng);
    final ms = hasElapsed
        ? (b.elapsedMs! - a.elapsedMs!)
        : b.time.difference(a.time).inMilliseconds;
    if (d < 0 || ms < 0) return null;
    cumDist[i] = cumDist[i - 1] + d;
    cumTime[i] = cumTime[i - 1] + ms / 1000;
  }
  if (cumDist.last < targetM) return null;
  double? best;
  var j = 0;
  for (var i = 1; i < segment.length; i++) {
    while (j < i && cumDist[i] - cumDist[j] >= targetM) {
      final seconds = cumTime[i] - cumTime[j];
      if (seconds > 0 && (best == null || seconds < best)) best = seconds;
      j++;
    }
  }
  return best;
}
