import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/badges.dart';

RunRecord run(double km, DateTime start, {int seconds = 1800}) => RunRecord(
  start: start,
  end: start.add(Duration(seconds: seconds)),
  distanceM: km * 1000,
  durationS: seconds,
  calories: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final now = DateTime(2026, 9, 30, 10);

  group('computeStreak（连续打卡）', () {
    test('今天有记录：从今天倒数', () {
      final runs = [
        run(3, DateTime(2026, 9, 30, 8)),
        run(3, DateTime(2026, 9, 29, 8)),
        run(3, DateTime(2026, 9, 28, 8)),
      ];
      expect(computeStreak(runs, now: now), 3);
    });

    test('今天没跑但昨天跑了：从昨天倒数（当天还有机会）', () {
      final runs = [
        run(3, DateTime(2026, 9, 29, 8)),
        run(3, DateTime(2026, 9, 28, 8)),
      ];
      expect(computeStreak(runs, now: now), 2);
    });

    test('断档后只数最近连续段', () {
      final runs = [
        run(3, DateTime(2026, 9, 30, 8)),
        run(3, DateTime(2026, 9, 29, 8)),
        // 9-26、9-25 的旧连续段。
        run(3, DateTime(2026, 9, 26, 8)),
        run(3, DateTime(2026, 9, 25, 8)),
      ];
      expect(computeStreak(runs, now: now), 2);
    });

    test('一天多条记录只算一天', () {
      final runs = [
        run(3, DateTime(2026, 9, 30, 7)),
        run(3, DateTime(2026, 9, 30, 20)),
      ];
      expect(computeStreak(runs, now: now), 1);
    });

    test('无记录为 0', () {
      expect(computeStreak(const [], now: now), 0);
    });
  });

  group('unlockedBadges（徽章解锁）', () {
    test('空数据只差晨跑夜跑等全部未解锁', () {
      final unlocked = unlockedBadges(
        const BadgeContext(
          totalKm: 0,
          totalSeconds: 0,
          runs: [],
          streakDays: 0,
        ),
      );
      expect(unlocked, isEmpty);
    });

    test('累计里程与单次距离分别判定', () {
      final runs = [run(6, DateTime(2026, 9, 30, 7))];
      final unlocked = unlockedBadges(badgeContext(runs, now: now));
      expect(unlocked, containsAll(['first_run', 'single_5']));
      expect(unlocked, isNot(contains('single_10')));
      expect(unlocked, isNot(contains('total_50')));
      // 清晨 7 点 → 晨型跑者。
      expect(unlocked, contains('early_bird'));
      expect(unlocked, isNot(contains('night_owl')));
    });

    test('半马按单次距离判定（21.0975 km）', () {
      final runs = [
        run(15, DateTime(2026, 9, 1, 8)),
        run(15, DateTime(2026, 9, 2, 8)),
        run(21.5, DateTime(2026, 9, 3, 23)),
      ];
      final unlocked = unlockedBadges(badgeContext(runs, now: now));
      expect(unlocked, contains('half_marathon'));
      expect(unlocked, contains('night_owl')); // 23 点
      expect(unlocked, contains('total_50')); // 51.5 km
      expect(unlocked, isNot(contains('full_marathon')));
    });

    test('连续打卡与累计时长徽章', () {
      final runs = [
        for (var i = 0; i < 7; i++)
          run(
            5,
            DateTime(2026, 9, 30 - i, 8),
            seconds: 2 * 3600,
          ),
      ];
      final unlocked = unlockedBadges(badgeContext(runs, now: now));
      expect(unlocked, containsAll(['streak_3', 'streak_7', 'time_10h']));
      expect(unlocked, isNot(contains('time_50h')));
    });

    test('badgeContext 派生正确', () {
      final context = badgeContext([
        run(10, DateTime(2026, 9, 29, 8), seconds: 3600),
        run(5, DateTime(2026, 9, 30, 8), seconds: 1800),
      ], now: now);
      expect(context.totalKm, 15);
      expect(context.totalSeconds, 5400);
      expect(context.maxSingleKm, 10);
      expect(context.streakDays, 2);
    });

    test('badgeById 覆盖全部定义', () {
      for (final def in badgeDefs) {
        expect(badgeById(def.id), same(def));
      }
      expect(badgeById('nope'), isNull);
    });
  });

  group('loadStoredUnlocked / storeUnlocked（持久化）', () {
    test('存取往返', () async {
      expect(await loadStoredUnlocked(), isEmpty);
      await storeUnlocked({'first_run', 'total_50'});
      expect(await loadStoredUnlocked(), {'first_run', 'total_50'});
      await storeUnlocked({'single_10'});
      expect(await loadStoredUnlocked(), {'single_10'});
    });
  });
}
