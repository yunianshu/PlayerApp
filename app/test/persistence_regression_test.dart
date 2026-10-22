import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:runtrail/data/database.dart';
import 'package:runtrail/models/run_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late RunDatabase db;
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('runtrail-migration-');
    db = RunDatabase(name: '${dir.path}/runs.db');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'v1 migration preserves old records and accepts segmented v2 records',
    () async {
      final old = await databaseFactory.openDatabase(
        db.databaseName,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute(
              'CREATE TABLE runs(id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, distance_m REAL NOT NULL, '
              'duration_s INTEGER NOT NULL, calories INTEGER NOT NULL, climb_m REAL NOT NULL DEFAULT 0)',
            );
            await d.execute(
              'CREATE TABLE points(id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE, lat REAL NOT NULL, '
              'lng REAL NOT NULL, altitude REAL NOT NULL DEFAULT 0, time_ms INTEGER NOT NULL)',
            );
            await d.insert('runs', {
              'id': 1,
              'start_ms': 1000,
              'end_ms': 61000,
              'distance_m': 100,
              'duration_s': 60,
              'calories': 7,
            });
            await d.insert('points', {
              'run_id': 1,
              'lat': 1.0,
              'lng': 2.0,
              'time_ms': 1000,
            });
          },
        ),
      );
      await old.close();
      expect((await db.getRun(1))!.distanceM, 100);
      final oldPoint = (await db.getPoints(1)).single;
      expect(oldPoint.startsSegment, isFalse);
      expect(oldPoint.elapsedMs, isNull);
      final time = DateTime(2026, 9, 27);
      final id = await db.insertRun(
        RunRecord(
          sessionId: 'v2-run',
          start: time,
          end: time.add(const Duration(minutes: 1)),
          distanceM: 200,
          durationS: 60,
          calories: 14,
        ),
        [
          RunPoint(
            lat: 1,
            lng: 2,
            altitude: 0,
            time: time,
            startsSegment: true,
            elapsedMs: 45000,
          ),
        ],
      );
      expect((await db.getRun(id))!.sessionId, 'v2-run');
      final newPoint = (await db.getPoints(id)).single;
      expect(newPoint.startsSegment, isTrue);
      expect(newPoint.elapsedMs, 45000);
      expect((await db.listRuns()).length, 2);
    },
  );

  test('concurrent saves of the same session are idempotent', () async {
    final time = DateTime(2026, 9, 27);
    final record = RunRecord(
      sessionId: 'one-session',
      start: time,
      end: time.add(const Duration(minutes: 1)),
      distanceM: 200,
      durationS: 60,
      calories: 14,
    );
    final points = [RunPoint(lat: 1, lng: 2, altitude: 0, time: time)];
    final ids = await Future.wait(
      List.generate(5, (_) => db.insertRun(record, points)),
    );
    expect(ids.toSet().length, 1);
    expect((await db.listRuns()).length, 1);
    expect((await db.getPoints(ids.first)).length, 1);
  });

  test(
    'weekly statistics exclude next week and bucket midnight correctly',
    () async {
      final monday = DateTime(2026, 9, 21);
      for (var i = 0; i < 8; i++) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        await db.insertRun(
          RunRecord(
            start: day,
            end: day,
            distanceM: 1000,
            durationS: 300,
            calories: 70,
          ),
          const [],
        );
      }
      expect(await db.weeklyKm(now: monday), List.filled(7, 1.0));
      expect(await db.weekStats(now: monday), (7.0, 2100, 7));
    },
  );
}
