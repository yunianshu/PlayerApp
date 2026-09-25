import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/run_draft.dart';

void main() {
  test('RunDraft 序列化回环', () {
    final start = DateTime(2026, 9, 25, 7, 30);
    final draft = RunDraft(
      start: start,
      elapsedMs: 1234567,
      distanceM: 2345.6,
      climbM: 45.2,
      points: [
        RunPoint(lat: 39.0, lng: 116.0, altitude: 10, time: start),
        RunPoint(
          lat: 39.001,
          lng: 116.001,
          altitude: 15.5,
          time: start.add(const Duration(seconds: 30)),
        ),
      ],
    );

    final restored = RunDraft.fromMap(draft.toMap());
    expect(restored, isNotNull);
    expect(restored!.start, start);
    expect(restored.elapsedMs, 1234567);
    expect(restored.distanceM, closeTo(2345.6, 1e-9));
    expect(restored.climbM, closeTo(45.2, 1e-9));
    expect(restored.points.length, 2);
    expect(restored.points[1].lat, closeTo(39.001, 1e-9));
    expect(restored.points[1].altitude, 15.5);
    expect(restored.points[1].time, start.add(const Duration(seconds: 30)));
  });

  test('非法/残缺数据返回 null 而不抛异常', () {
    expect(RunDraft.fromMap({}), isNull);
    expect(RunDraft.fromMap({'points': 'not-a-list'}), isNull);
    expect(RunDraft.fromMap({'points': [[1, 2, 3]]}), isNull); // 行长度不足
    expect(RunDraft.fromMap({'points': []}), isNull);
  });
}
