import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/run_record.dart';

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
    return _opening ??= _open().then((d) {
      _db = d;
      _opening = null;
      return d;
    });
  }

  Future<Database> _open() async {
    final path = databaseName == inMemoryDatabasePath
        ? databaseName
        : join(await getDatabasesPath(), databaseName);
    return openDatabase(
      path,
      version: 1,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE runs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_ms INTEGER NOT NULL,
            end_ms INTEGER NOT NULL,
            distance_m REAL NOT NULL,
            duration_s INTEGER NOT NULL,
            calories INTEGER NOT NULL,
            climb_m REAL NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE points(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            altitude REAL NOT NULL DEFAULT 0,
            time_ms INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_points_run ON points(run_id)');
      },
    );
  }

  Future<int> insertRun(RunRecord run, List<RunPoint> points) async {
    final d = await db;
    // runs 与 points 同事务写入，避免中途失败留下无轨迹的空记录。
    return d.transaction((txn) async {
      final id = await txn.insert('runs', run.toMap());
      final batch = txn.batch();
      for (final p in points) {
        batch.insert('points', p.toMap(id));
      }
      await batch.commit(noResult: true);
      return id;
    });
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
    final rows = await d.query(
      'runs',
      orderBy: 'start_ms DESC',
      limit: limit,
    );
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

  /// 最近 7 天每天里程（周一为一周起点），用于首页柱状图。
  Future<List<double>> weeklyKm({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final weekday = today.weekday; // Mon=1..Sun=7
    final monday = today.subtract(Duration(days: weekday - 1));
    final d = await db;
    final rows = await d.query(
      'runs',
      columns: ['start_ms', 'distance_m'],
      where: 'start_ms >= ?',
      whereArgs: [monday.millisecondsSinceEpoch],
    );
    // 在 Dart 侧按自然日分桶，避免 SQL 整除在夏令时切换日偏移一天。
    final km = List<double>.filled(7, 0);
    for (final row in rows) {
      final start = DateTime.fromMillisecondsSinceEpoch(row['start_ms'] as int);
      final day = DateTime(start.year, start.month, start.day);
      final idx = day.difference(monday).inDays;
      if (idx >= 0 && idx < 7) {
        km[idx] += (row['distance_m'] as num).toDouble() / 1000;
      }
    }
    return km;
  }

  /// 本周里程、时长、次数（首页英雄卡）。
  Future<(double km, int seconds, int count)> weekStats() async {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final d = await db;
    final r = await d.rawQuery(
      'SELECT COALESCE(SUM(distance_m),0) d, COALESCE(SUM(duration_s),0) t, COUNT(*) c '
      'FROM runs WHERE start_ms >= ?',
      [monday.millisecondsSinceEpoch],
    );
    final row = r.first;
    return (
      (row['d'] as num).toDouble() / 1000,
      row['t'] as int,
      row['c'] as int,
    );
  }

  Future close() async {
    final d = _db;
    _db = null;
    _opening = null;
    await d?.close();
  }
}