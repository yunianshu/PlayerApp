import 'package:shared_preferences/shared_preferences.dart';

import '../models/run_record.dart';
import '../core/calendar.dart';
import '../core/i18n.dart';

/// 徽章上下文：从全部记录派生的统计快照。
class BadgeContext {
  final double totalKm;
  final int totalSeconds;
  final List<RunRecord> runs;
  final int streakDays;

  const BadgeContext({
    required this.totalKm,
    required this.totalSeconds,
    required this.runs,
    required this.streakDays,
  });

  bool get hasRun => runs.isNotEmpty;
  double get maxSingleKm => runs.fold(
    0,
    (m, r) => r.distanceKm > m ? r.distanceKm : m,
  );
  bool get hasMorningRun => runs.any((r) => r.start.hour >= 5 && r.start.hour < 8);
  bool get hasNightRun =>
      runs.any((r) => r.start.hour >= 21 || r.start.hour < 5);
}

/// 徽章定义。name/desc 为中文原文，展示时经 `.tr` 翻译。
class BadgeDef {
  final String id;
  final String name;
  final String desc;
  final String icon;

  const BadgeDef({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
  });

  bool unlocked(BadgeContext c) => switch (id) {
    'first_run' => c.hasRun,
    'single_5' => c.maxSingleKm >= 5,
    'single_10' => c.maxSingleKm >= 10,
    'half_marathon' => c.maxSingleKm >= 21.0975,
    'full_marathon' => c.maxSingleKm >= 42.195,
    'total_50' => c.totalKm >= 50,
    'total_100' => c.totalKm >= 100,
    'total_500' => c.totalKm >= 500,
    'total_1000' => c.totalKm >= 1000,
    'streak_3' => c.streakDays >= 3,
    'streak_7' => c.streakDays >= 7,
    'streak_21' => c.streakDays >= 21,
    'time_10h' => c.totalSeconds >= 10 * 3600,
    'time_50h' => c.totalSeconds >= 50 * 3600,
    'early_bird' => c.hasMorningRun,
    'night_owl' => c.hasNightRun,
    _ => false,
  };
}

/// 全部徽章（16 枚）：单次距离 / 累计里程 / 连续打卡 / 累计时长 / 时段。
const List<BadgeDef> badgeDefs = [
  BadgeDef(
    id: 'first_run',
    name: '首跑完成',
    desc: '完成你的第一次跑步',
    icon: 'flag',
  ),
  BadgeDef(
    id: 'single_5',
    name: '首个 5 公里',
    desc: '单次跑步达到 5 公里',
    icon: 'directions_run',
  ),
  BadgeDef(
    id: 'single_10',
    name: '十公里突破',
    desc: '单次跑步达到 10 公里',
    icon: 'emoji_events',
  ),
  BadgeDef(
    id: 'half_marathon',
    name: '半马挑战',
    desc: '单次跑步达到 21.0975 公里',
    icon: 'workspace_premium',
  ),
  BadgeDef(
    id: 'full_marathon',
    name: '全马挑战',
    desc: '单次跑步达到 42.195 公里',
    icon: 'military_tech',
  ),
  BadgeDef(
    id: 'total_50',
    name: '累计 50 公里',
    desc: '累计里程达到 50 公里',
    icon: 'route',
  ),
  BadgeDef(
    id: 'total_100',
    name: '百公里俱乐部',
    desc: '累计里程达到 100 公里',
    icon: 'military_tech',
  ),
  BadgeDef(
    id: 'total_500',
    name: '五百公里',
    desc: '累计里程达到 500 公里',
    icon: 'emoji_events',
  ),
  BadgeDef(
    id: 'total_1000',
    name: '千公里传奇',
    desc: '累计里程达到 1000 公里',
    icon: 'workspace_premium',
  ),
  BadgeDef(
    id: 'streak_3',
    name: '三日连续',
    desc: '连续 3 天跑步',
    icon: 'local_fire_department',
  ),
  BadgeDef(
    id: 'streak_7',
    name: '七日连续',
    desc: '连续 7 天跑步',
    icon: 'local_fire_department',
  ),
  BadgeDef(
    id: 'streak_21',
    name: '廿一日坚持',
    desc: '连续 21 天跑步',
    icon: 'local_fire_department',
  ),
  BadgeDef(
    id: 'time_10h',
    name: '运动十小时',
    desc: '累计运动时长达到 10 小时',
    icon: 'timer',
  ),
  BadgeDef(
    id: 'time_50h',
    name: '运动五十小时',
    desc: '累计运动时长达到 50 小时',
    icon: 'timer',
  ),
  BadgeDef(
    id: 'early_bird',
    name: '晨型跑者',
    desc: '完成一次清晨（5–8 点）跑步',
    icon: 'wb_twilight',
  ),
  BadgeDef(
    id: 'night_owl',
    name: '星夜跑者',
    desc: '完成一次深夜（21 点后）跑步',
    icon: 'nights_stay',
  ),
];

BadgeDef? badgeById(String id) {
  for (final b in badgeDefs) {
    if (b.id == id) return b;
  }
  return null;
}

/// 从全部记录构建徽章上下文。
BadgeContext badgeContext(List<RunRecord> runs, {DateTime? now}) {
  final totalKm = runs.fold<double>(0, (a, r) => a + r.distanceKm);
  final totalSeconds = runs.fold<int>(0, (a, r) => a + r.durationS);
  return BadgeContext(
    totalKm: totalKm,
    totalSeconds: totalSeconds,
    runs: runs,
    streakDays: computeStreak(runs, now: now),
  );
}

/// 解锁的徽章 id 集合。
Set<String> unlockedBadges(BadgeContext context) {
  return {
    for (final b in badgeDefs)
      if (b.unlocked(context)) b.id,
  };
}

/// 连续打卡天数：从今天（无记录则从昨天）向前数连续有记录的自然日。
/// 日期运算走 [Calendar]，避免 24 小时误差。
int computeStreak(List<RunRecord> runs, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = <DateTime>{
    for (final r in runs) Calendar.day(r.start),
  };
  if (days.isEmpty) return 0;
  var cursor = Calendar.day(n);
  if (!days.contains(cursor)) {
    cursor = Calendar.addDays(cursor, -1);
    if (!days.contains(cursor)) return 0;
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = Calendar.addDays(cursor, -1);
  }
  return streak;
}

/// 徽章名（已翻译）。
String badgeName(BadgeDef def) => def.name.tr;
String badgeDesc(BadgeDef def) => def.desc.tr;

const _unlockedKey = 'unlocked_badges';

/// 持久化的已解锁徽章集合；偏好不可用时返回空集（弹窗最多多弹一次，无害）。
Future<Set<String>> loadStoredUnlocked() async {
  try {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_unlockedKey) ?? const <String>[]).toSet();
  } on Object {
    return <String>{};
  }
}

Future<void> storeUnlocked(Set<String> ids) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_unlockedKey, ids.toList());
  } on Object {
    // 持久化失败：下次启动可能重复弹一次解锁弹窗，可接受。
  }
}
