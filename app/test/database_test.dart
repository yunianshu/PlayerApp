import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // ignore: depend_on_referenced_packages

import 'package:runtrail/data/database.dart';
import 'package:runtrail/models/run_record.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // RunDatabase 单例绑定全局 databaseFactory，测试内直接使用。
  group('RunDatabase CRUD', () {
    late RunDatabase db;

    setUp(() {
      // 每个用例独立的库文件。sqflite 默认 singleInstance 会复用同名连接，
      // ':memory:' 在用例间串数据，必须用唯一文件名隔离。
      db = RunDatabase(
        name: 'runtrail_test_${DateTime.now().microsecondsSinceEpoch}.db',
      );
    });

    tearDown(() => db.close());

    test('插入与查询', () async {
      final start = DateTime(2026, 9, 25, 7, 30);
      final record = RunRecord(
        start: start,
        end: start.add(const Duration(minutes: 40)),
        distanceM: 5230,
        durationS: 2400,
        calories: 350,
        climbM: 32.5,
      );
      final points = [
        RunPoint(lat: 39.0, lng: 116.0, altitude: 10, time: start),
        RunPoint(
          lat: 39.001,
          lng: 116.0,
          altitude: 12,
          time: start.add(const Duration(minutes: 1)),
        ),
      ];
      final id = await db.insertRun(record, points);
      expect(id, greaterThan(0));

      final runs = await db.listRuns();
      expect(runs.length, 1);
      expect(runs.first.distanceM, 5230);
      expect(runs.first.climbM, 32.5);

      final loaded = await db.getPoints(id);
      expect(loaded.length, 2);
      expect(loaded.first.altitude, 10);

      final totals = await db.totals();
      expect(totals.$1, closeTo(5.23, 0.001));
      expect(totals.$3, 1);
    });

    test('删除记录同时删除轨迹点', () async {
      final start = DateTime(2026, 9, 25, 7, 30);
      final id = await db.insertRun(
        RunRecord(
          start: start,
          end: start.add(const Duration(minutes: 10)),
          distanceM: 1500,
          durationS: 600,
          calories: 100,
        ),
        [RunPoint(lat: 39.0, lng: 116.0, altitude: 0, time: start)],
      );
      await db.deleteRun(id);
      expect(await db.listRuns(), isEmpty);
      expect(await db.getPoints(id), isEmpty);
    });

    test('并发首调只打开一个连接（回归：db getter 竞态）', () async {
      final results = await Future.wait([
        db.listRuns(),
        db.totals(),
        db.weekStats(),
        db.weeklyKm(),
      ]);
      expect(results, isNotNull);
      expect(await db.listRuns(), isEmpty);
    });

    test('weeklyKm 按自然日分桶', () async {
      final now = DateTime(2026, 9, 25); // 周五
      final wednesday = DateTime(2026, 9, 23, 7, 0);
      await db.insertRun(
        RunRecord(
          start: wednesday,
          end: wednesday.add(const Duration(minutes: 30)),
          distanceM: 3000,
          durationS: 1800,
          calories: 200,
        ),
        const [],
      );
      final km = await db.weeklyKm(now: now);
      expect(km.length, 7);
      expect(km[2], closeTo(3.0, 0.001)); // 周三
      expect(km[4], 0); // 周五
    });
  });
}
