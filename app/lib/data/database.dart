import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/run_record.dart';
import '../core/calendar.dart';

/// 纯本地 SQLite 存储，无任何服务器依赖。
class RunDatabase {
  /// [name] 仅测试使用：传内存库路径实现用例间隔离；生产代码统一用 [instance]。
  RunDatabase({String? name}) : databaseName = name ?? 'runtrail.db';

  static final RunDatabase instance = RunDatabase();

  final String databaseName;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get db {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    // 并发首调时复用同一个打开任务，避免重复 openDatabase。
    return _opening ??= _openAndCache();
  }

  Future<Database> _openAndCache() async {
    try {
      return _db = await _open();
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final path = databaseName == inMemoryDatabasePath
        ? databaseName
        : join(await getDatabasesPath(), databaseName);
    return openDatabase(
      path,
      version: 3,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE runs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT UNIQUE,
            start_ms INTEGER NOT NULL,
            end_ms INTEGER NOT NULL,
            distance_m REAL NOT NULL,
            duration_s INTEGER NOT NULL,
            calories INTEGER NOT NULL,
            climb_m REAL NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'gps',
            title TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('''
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
        await db.execute('CREATE INDEX idx_points_run ON points(run_id)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE runs ADD COLUMN session_id TEXT');
          await db.execute(
            'CREATE UNIQUE INDEX idx_runs_session ON runs(session_id)',
          );
          await db.execute(
            'ALTER TABLE points ADD COLUMN starts_segment INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('ALTER TABLE points ADD COLUMN elapsed_ms INTEGER');
        }
        if (oldVersion < 3) {
          // v3：记录来源（gps/手动补录）与可编辑的标题、备注。旧数据均为 gps。
          await db.execute(
            "ALTER TABLE runs ADD COLUMN source TEXT NOT NULL DEFAULT 'gps'",
          );
          await db.execute(
            "ALTER TABLE runs ADD COLUMN title TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE runs ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
  }

  Future<int> insertRun(RunRecord run, List<RunPoint> points) async {
    final d = await db;
    // runs 与 points 同事务写入，避免中途失败留下无轨迹的空记录。
    return d.transaction((txn) async {
      final existing = await txn.query(
        'runs',
        columns: ['id'],
        where: 'session_id = ?',
        whereArgs: [run.sessionKey],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.first['id'] as int;
      final id = await txn.insert('runs', run.toMap());
      final batch = txn.batch();
      for (final p in points) {
        batch.insert('points', p.toMap(id));
      }
      await batch.commit(noResult: true);
      return id;
    });
  }

  /// 会话 ID 是否已存在（备份恢复幂等判断）。
  Future<bool> hasSession(String sessionKey) async {
    final d = await db;
    final rows = await d.query(
      'runs',
      columns: ['id'],
      where: 'session_id = ?',
      whereArgs: [sessionKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 更新记录的标题与备注（详情页编辑）。
  Future<void> updateMeta(int id, {String? title, String? notes}) async {
    final d = await db;
    final map = <String, Object?>{};
    if (title != null) map['title'] = title;
    if (notes != null) map['notes'] = notes;
    if (map.isEmpty) return;
    await d.update('runs', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRun(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('points', where: 'run_id = ?', whereArgs: [id]);
      await txn.delete('runs', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<RunRecord>> listRuns({int? limit}) async {
    final d = await db;
    final rows = await d.query('runs', orderBy: 'start_ms DESC', limit: limit);
    return rows.map(RunRecord.fromMap).toList();
  }

  Future<RunRecord?> getRun(int id) async {
    final d = await db;
    final rows = await d.query(
      'runs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : RunRecord.fromMap(rows.first);
  }

  Future<List<RunPoint>> getPoints(int runId) async {
    final d = await db;
    final rows = await d.query(
      'points',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'time_ms',
    );
    return rows.map(RunPoint.fromMap).toList();
  }

  /// 累计统计（我的页）。
  Future<(double km, int seconds, int count)> totals() async {
    final d = await db;
    final r = await d.rawQuery(
      'SELECT COALESCE(SUM(distance_m),0) d, COALESCE(SUM(duration_s),0) t, COUNT(*) c FROM runs',
    );
    final row = r.first;
    return (
      (row['d'] as num).toDouble() / 1000,
      row['t'] as int,
      row['c'] as int,
    );
  }

  /// 时间段汇总统计（统计页）：总里程/时长/次数/爬升/最佳均配。
  /// 最佳均配取 distance_m > 10 的记录中最小 duration_s/distance_m（秒/公里）。
  Future<(double km, int seconds, int count, double climb, double? bestPace)>
  rangeStats(DateTime startInclusive, DateTime endExclusive) async {
    final d = await db;
    final r = await d.rawQuery(
      'SELECT COALESCE(SUM(distance_m),0) d, COALESCE(SUM(duration_s),0) t, '
      'COUNT(*) c, COALESCE(SUM(climb_m),0) h, '
      'MIN(CASE WHEN distance_m > 10 THEN duration_s * 1000.0 / distance_m END) bp '
      'FROM runs WHERE start_ms >= ? AND start_ms < ?',
      [
        startInclusive.millisecondsSinceEpoch,
        endExclusive.millisecondsSinceEpoch,
      ],
    );
    final row = r.first;
    final bp = row['bp'];
    return (
      (row['d'] as num).toDouble() / 1000,
      row['t'] as int,
      row['c'] as int,
      (row['h'] as num).toDouble(),
      bp is num ? bp.toDouble() : null,
    );
  }

  /// 区间内按自然日的公里数（统计页热力图 / 周趋势复用）。
  /// 在 Dart 侧按自然日分桶，避免 SQL 整除在夏令时切换日偏移一天。
  Future<Map<DateTime, double>> kmByDay(
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    final d = await db;
    final rows = await d.query(
      'runs',
      columns: ['start_ms', 'distance_m'],
      where: 'start_ms >= ? AND start_ms < ?',
      whereArgs: [
        startInclusive.millisecondsSinceEpoch,
        endExclusive.millisecondsSinceEpoch,
      ],
    );
    final result = <DateTime, double>{};
    for (final row in rows) {
      final start = DateTime.fromMillisecondsSinceEpoch(row['start_ms'] as int);
      final day = Calendar.day(start);
      result[day] =
          (result[day] ?? 0) + (row['distance_m'] as num).toDouble() / 1000;
    }
    return result;
  }

  /// 某自然年 12 个月的公里数（月度对比）。
  Future<List<double>> monthlyKm(int year) async {
    final d = await db;
    final rows = await d.query(
      'runs',
      columns: ['start_ms', 'distance_m'],
      where: 'start_ms >= ? AND start_ms < ?',
      whereArgs: [
        DateTime(year, 1).millisecondsSinceEpoch,
        DateTime(year + 1, 1).millisecondsSinceEpoch,
      ],
    );
    final km = List<double>.filled(12, 0);
    for (final row in rows) {
      final start = DateTime.fromMillisecondsSinceEpoch(row['start_ms'] as int);
      if (start.year == year) {
        km[start.month - 1] += (row['distance_m'] as num).toDouble() / 1000;
      }
    }
    return km;
  }

  /// 最近 7 天每天里程（周一为一周起点），用于首页柱状图。
  Future<List<double>> weeklyKm({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final monday = Calendar.monday(n);
    final nextMonday = Calendar.addDays(monday, 7);
    final byDay = await kmByDay(monday, nextMonday);
    final km = List<double>.filled(7, 0);
    for (final entry in byDay.entries) {
      final idx = Calendar.daysBetween(entry.key, monday);
      if (idx >= 0 && idx < 7) km[idx] += entry.value;
    }
    return km;
  }

  /// 本周里程、时长、次数（首页英雄卡）。
  Future<(double km, int seconds, int count)> weekStats({DateTime? now}) async {
    final monday = Calendar.monday(now ?? DateTime.now());
    final (km, secs, count, _, _) = await rangeStats(
      monday,
      Calendar.addDays(monday, 7),
    );
    return (km, secs, count);
  }

  Future<void> close() async {
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        /* Nothing to close after a failed open. */
      }
    }
    final d = _db;
    _db = null;
    _opening = null;
    await d?.close();
  }
}
