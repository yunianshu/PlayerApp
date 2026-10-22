import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // ignore: depend_on_referenced_packages

import 'package:runtrail/core/calendar.dart';
import 'package:runtrail/data/database.dart';
import 'package:runtrail/models/run_record.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  var counter = 0;

  String uniqueName() =>
      'runtrail_v3_${DateTime.now().microsecondsSinceEpoch}_${counter++}.db';

  RunRecord run(
    int seq,
    double km,
    DateTime start, {
    int seconds = 1800,
    double climb = 10,
    String source = RunRecord.sourceGps,
    String title = '',
    String notes = '',
  }) => RunRecord(
    sessionId: 'session-$seq',
    start: start,
    end: start.add(Duration(seconds: seconds)),
    distanceM: km * 1000,
    durationS: seconds,
    calories: 120,
    climbM: climb,
    source: source,
    title: title,
    notes: notes,
  );

  group('v3 新库', () {
    late RunDatabase db;
    setUp(() => db = RunDatabase(name: uniqueName()));
    tearDown(() => db.close());

    test('手动补录记录保存与读回', () async {
      final start = DateTime(2026, 9, 1, 8);
      await db.insertRun(
        run(1, 3, start,
            source: RunRecord.sourceManual,
            title: '跑步机',
            notes: '坡度 1%'),
        const [],
      );
      final runs = await db.listRuns();
      expect(runs.single.isManual, isTrue);
      expect(runs.single.title, '跑步机');
      expect(runs.single.notes, '坡度 1%');
      expect(runs.single.distanceKm, 3.0);
      expect(await db.getPoints(runs.single.id!), isEmpty);
    });

    test('updateMeta 更新标题与备注', () async {
      final start = DateTime(2026, 9, 2, 8);
      final id = await db.insertRun(run(1, 5, start), const []);
      await db.updateMeta(id, title: '新标题', notes: '新备注');
      final updated = await db.getRun(id);
      expect(updated!.title, '新标题');
      expect(updated.notes, '新备注');
      // 只改其中一个字段时另一个保持不变。
      await db.updateMeta(id, notes: '只改备注');
      final again = await db.getRun(id);
      expect(again!.title, '新标题');
      expect(again.notes, '只改备注');
    });

    test('hasSession 会话存在性判断', () async {
      final start = DateTime(2026, 9, 3, 8);
      await db.insertRun(run(1, 5, start), const []);
      expect(await db.hasSession('session-1'), isTrue);
      expect(await db.hasSession('session-999'), isFalse);
    });
  });

  group('SQL 聚合查询', () {
    late RunDatabase db;
    setUp(() => db = RunDatabase(name: uniqueName()));
    tearDown(() => db.close());

    test('rangeStats 汇总区间内的里程/时长/次数/爬升/最佳均配', () async {
      final base = DateTime(2026, 9, 10, 8);
      // 5km/30min（均配 360 s/km）、10km/50min（300 s/km）、区外 3km。
      await db.insertRun(run(1, 5, base), const []);
      await db.insertRun(
        run(2, 10, base.add(const Duration(days: 1)), seconds: 3000),
        const [],
      );
      await db.insertRun(run(3, 3, DateTime(2026, 8, 1, 8)), const []);

      final (km, secs, count, climb, bestPace) = await db.rangeStats(
        DateTime(2026, 9),
        DateTime(2026, 10),
      );
      expect(km, closeTo(15, 1e-9));
      expect(secs, 4800);
      expect(count, 2);
      expect(climb, 20);
      expect(bestPace!, closeTo(300, 1e-9));
    });

    test('rangeStats 空区间返回零值且最佳均配为 null', () async {
      final r = await db.rangeStats(DateTime(2026, 1), DateTime(2026, 2));
      expect(r.$1, 0);
      expect(r.$2, 0);
      expect(r.$3, 0);
      expect(r.$5, isNull);
    });

    test('kmByDay 按自然日分桶', () async {
      final base = DateTime(2026, 9, 15);
      await db.insertRun(run(1, 2, base.add(const Duration(hours: 7))), const []);
      await db.insertRun(run(2, 3, base.add(const Duration(hours: 20))), const []);
      await db.insertRun(
        run(3, 4, base.add(const Duration(days: 1))),
        const [],
      );
      final days = await db.kmByDay(
        base.subtract(const Duration(days: 1)),
        base.add(const Duration(days: 2)),
      );
      expect(days[Calendar.day(base)], closeTo(5, 1e-9));
      expect(days[Calendar.addDays(base, 1)], closeTo(4, 1e-9));
      expect(days.length, 2);
    });

    test('monthlyKm 返回 12 个月的公里数', () async {
      final db2 = db;
      await db2.insertRun(run(1, 5, DateTime(2026, 3, 1, 8)), const []);
      await db2.insertRun(run(2, 7, DateTime(2026, 3, 20, 8)), const []);
      await db2.insertRun(run(3, 2, DateTime(2025, 3, 20, 8)), const []);
      final km = await db2.monthlyKm(2026);
      expect(km.length, 12);
      expect(km[2], closeTo(12, 1e-9));
      expect(km[0], 0);
      // 其他年份的数据不计入。
      final kmPrev = await db2.monthlyKm(2025);
      expect(kmPrev[2], closeTo(2, 1e-9));
    });

    test('weeklyKm 兼容旧签名（7 天列表）', () async {
      final now = DateTime.now();
      final monday = Calendar.monday(Calendar.day(now));
      await db.insertRun(run(1, 6, monday.add(const Duration(hours: 8))), const []);
      final km = await db.weeklyKm();
      expect(km.length, 7);
      expect(km.fold<double>(0, (a, b) => a + b), closeTo(6, 1e-9));
    });

    test('weekStats 返回三元组（首页英雄卡兼容）', () async {
      final now = DateTime.now();
      final monday = Calendar.monday(Calendar.day(now));
      await db.insertRun(run(1, 4, monday.add(const Duration(hours: 8))), const []);
      final (km, secs, count) = await db.weekStats();
      expect(km, closeTo(4, 1e-9));
      expect(secs, 1800);
      expect(count, 1);
    });
  });

  group('v2 → v3 自动迁移', () {
    test('旧库打开后新增 source/title/notes 且旧数据标记为 gps', () async {
      final dir = await getDatabasesPath();
      final name = 'migrate_${DateTime.now().microsecondsSinceEpoch}.db';
      final path = p.join(dir, name);

      // 手工搭建 v2 结构（无 source/title/notes）并写入一条旧记录。
      final v2 = await openDatabase(path, version: 2, onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE runs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT UNIQUE,
            start_ms INTEGER NOT NULL,
            end_ms INTEGER NOT NULL,
            distance_m REAL NOT NULL,
            duration_s INTEGER NOT NULL,
            calories INTEGER NOT NULL,
            climb_m REAL NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            altitude REAL NOT NULL DEFAULT 0,
            time_ms INTEGER NOT NULL,
            starts_segment INTEGER NOT NULL DEFAULT 0,
            elapsed_ms INTEGER
          )''');
        await d.execute('CREATE INDEX idx_points_run ON points(run_id)');
      });
      final start = DateTime(2026, 5, 1, 8);
      final oldId = await v2.insert('runs', {
        'session_id': 'old-1',
        'start_ms': start.millisecondsSinceEpoch,
        'end_ms': start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
        'distance_m': 4200.0,
        'duration_s': 1800,
        'calories': 150,
        'climb_m': 12.0,
      });
      await v2.insert('points', {
        'run_id': oldId,
        'lat': 39.0,
        'lng': 116.0,
        'altitude': 10.0,
        'time_ms': start.millisecondsSinceEpoch,
        'starts_segment': 0,
        'elapsed_ms': null,
      });
      await v2.close();

      final db = RunDatabase(name: name);
      addTearDown(db.close);
      final runs = await db.listRuns();
      expect(runs, hasLength(1));
      expect(runs.single.source, RunRecord.sourceGps);
      expect(runs.single.title, '');
      expect(runs.single.notes, '');
      expect(runs.single.distanceKm, closeTo(4.2, 1e-9));
      expect(await db.getPoints(runs.single.id!), hasLength(1));

      // 迁移后可以继续写入带新字段的记录。
      final newId = await db.insertRun(
        run(2, 2, start.add(const Duration(days: 1)),
            source: RunRecord.sourceManual),
        const [],
      );
      expect(newId, greaterThan(oldId));
    });
  });
}
