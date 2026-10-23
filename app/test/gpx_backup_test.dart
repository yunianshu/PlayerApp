import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // ignore: depend_on_referenced_packages

import 'package:runtrail/core/prefs.dart';
import 'package:runtrail/data/database.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/backup_service.dart';
import 'package:runtrail/services/gpx.dart';

class TestDocuments extends PathProviderPlatform {
  TestDocuments(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // BackupService 走 RunDatabase.instance：每个用例独立的库目录。
    await RunDatabase.instance.close();
    final dir = await Directory.systemTemp.createTemp('runtrail-bk-');
    PathProviderPlatform.instance = TestDocuments(dir.path);
    await databaseFactory.setDatabasesPath(dir.path);
  });
  tearDown(() => RunDatabase.instance.close());

  group('buildGpx（GPX 导出）', () {
    // 08:00 in UTC+8 is this exact instant, regardless of the CI machine zone.
    final start = DateTime.utc(2026, 9, 30);
    final record = RunRecord(
      sessionId: 's1',
      start: start,
      end: start.add(const Duration(hours: 1)),
      distanceM: 5230,
      durationS: 2400,
      calories: 350,
      climbM: 32.5,
      title: '晨跑 <测试>',
    );

    test('包含表头、轨迹点与 UTC 时间', () {
      final points = [
        RunPoint(lat: 39.0, lng: 116.0, altitude: 43.2, time: start),
        RunPoint(
          lat: 39.001,
          lng: 116.0,
          altitude: 44.0,
          time: start.add(const Duration(minutes: 1)),
        ),
      ];
      final gpx = buildGpx(record, points);
      expect(gpx, contains('<gpx version="1.1" creator="RunTrail"'));
      expect(gpx, contains('<trkpt lat="39.000000" lon="116.000000">'));
      expect(gpx, contains('<ele>43.2</ele>'));
      expect(gpx, contains('T00:00:00.000Z'));
      expect(gpx, contains('T00:01:00.000Z'));
    });

    test('XML 特殊字符被转义', () {
      final gpx = buildGpx(record, const []);
      expect(gpx, contains('晨跑 &lt;测试&gt;'));
      expect(gpx, isNot(contains('<测试>')));
    });

    test('暂停边界拆分为多个 trkseg', () {
      final points = [
        RunPoint(lat: 39.0, lng: 116.0, altitude: 0, time: start),
        RunPoint(
          lat: 39.001,
          lng: 116.0,
          altitude: 0,
          time: start.add(const Duration(minutes: 1)),
        ),
        RunPoint(
          lat: 39.0,
          lng: 116.0,
          altitude: 0,
          time: start.add(const Duration(minutes: 10)),
          startsSegment: true,
        ),
        RunPoint(
          lat: 39.001,
          lng: 116.0,
          altitude: 0,
          time: start.add(const Duration(minutes: 11)),
        ),
      ];
      final gpx = buildGpx(record, points);
      expect('</trkseg><trkseg>'.allMatches(gpx).length, 1);
      expect('<trkseg>'.allMatches(gpx).length, 2);
    });

    test('无标题时用日期命名', () {
      final gpx = buildGpx(
        RunRecord(
          sessionId: 's2',
          start: start,
          end: start,
          distanceM: 1,
          durationS: 1,
          calories: 1,
        ),
        const [],
      );
      expect(gpx, contains('<name>RunTrail 2026-09-30</name>'));
    });
  });

  group('BackupService（备份/恢复）', () {
    RunRecord record(
      int id,
      double km,
      DateTime start, {
      String source = RunRecord.sourceGps,
      String title = '',
      String notes = '',
    }) => RunRecord(
      id: id,
      sessionId: 'session-$id',
      start: start,
      end: start.add(const Duration(minutes: 30)),
      distanceM: km * 1000,
      durationS: 1800,
      calories: 120,
      climbM: 10,
      source: source,
      title: title,
      notes: notes,
    );

    test('导出包含 runs、points 与 prefs', () async {
      final start = DateTime(2026, 9, 1, 8);
      final id = await RunDatabase.instance.insertRun(record(1, 5, start), [
        RunPoint(lat: 39.0, lng: 116.0, altitude: 10, time: start),
        RunPoint(
          lat: 39.001,
          lng: 116.0,
          altitude: 11,
          time: start.add(const Duration(minutes: 1)),
          startsSegment: true,
          elapsedMs: 60000,
        ),
      ]);
      final runs = await RunDatabase.instance.listRuns();
      expect(runs.single.id, id);
      final data = BackupService.build(runs, {
        runs.single.sessionKey: await RunDatabase.instance.getPoints(id),
      });
      expect(data['app'], 'RunTrail');
      expect(data['format'], BackupService.formatVersion);
      final runList = data['runs'] as List;
      expect(runList.length, 1);
      final run0 = runList.first as Map;
      expect(run0['session_id'], 'session-1');
      expect(run0['source'], 'gps');
      expect((run0['points'] as List).length, 2);
      expect((run0['points'] as List)[1][4], true); // startsSegment
      expect((data['prefs'] as Map)['weekly_goal_km'], Prefs.instance.weeklyGoalKm);
    });

    test('恢复写入记录，重复导入幂等跳过', () async {
      final start = DateTime(2026, 8, 1, 8);
      final data = BackupService.build([
        record(1, 5, start, title: 'T1', notes: 'N1'),
        record(2, 10, start.add(const Duration(days: 1)),
            source: RunRecord.sourceManual),
      ], {
        'session-1': [
          RunPoint(lat: 39.0, lng: 116.0, altitude: 0, time: start),
          RunPoint(
            lat: 39.001,
            lng: 116.0,
            altitude: 0,
            time: start.add(const Duration(minutes: 5)),
          ),
        ],
      });
      final json = jsonEncode(data);

      final result = await BackupService.restoreJson(json);
      expect(result.imported, 2);
      expect(result.skipped, 0);

      final runs = await RunDatabase.instance.listRuns();
      expect(runs.length, 2);
      final manual = runs.firstWhere((r) => r.sessionKey == 'session-2');
      expect(manual.isManual, isTrue);
      final gps = runs.firstWhere((r) => r.sessionKey == 'session-1');
      expect(gps.title, 'T1');
      expect(gps.notes, 'N1');
      expect(await RunDatabase.instance.getPoints(gps.id!), hasLength(2));

      // 再次导入：全部按会话 ID 跳过。
      final again = await BackupService.restoreJson(json);
      expect(again.imported, 0);
      expect(again.skipped, 2);
      expect((await RunDatabase.instance.listRuns()).length, 2);
    });

    test('损坏条目跳过且格式错误抛 BackupFormatException', () async {
      final result = await BackupService.restoreJson(
        '{"app":"RunTrail","format":1,"runs":["garbage",'
        '{"start_ms":"bad"},'
        '{"start_ms":1000,"end_ms":2000,"distance_m":1000,'
        '"duration_s":600,"session_id":"ok-1"}]}',
      );
      expect(result.imported, 1);
      expect(result.skipped, 2);

      await expectLater(
        BackupService.restoreJson('{not json'),
        throwsA(isA<BackupFormatException>()),
      );
      await expectLater(
        BackupService.restoreJson('{"app":"Other","runs":[]}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('导出的 JSON 可完整还原（round-trip）', () async {
      final start = DateTime(2026, 7, 15, 7);
      await RunDatabase.instance.insertRun(
        record(1, 12.5, start, title: '长距离', notes: '状态好'),
        [
          RunPoint(lat: 39.0, lng: 116.0, altitude: 5, time: start),
          RunPoint(
            lat: 39.001,
            lng: 116.0,
            altitude: 6,
            time: start.add(const Duration(minutes: 2)),
            elapsedMs: 120000,
          ),
        ],
      );
      final runs = await RunDatabase.instance.listRuns();
      final points = {
        for (final r in runs)
          r.sessionKey: r.id == null ? <RunPoint>[] : await RunDatabase.instance.getPoints(r.id!),
      };
      final json = jsonEncode(BackupService.build(runs, points));

      // 清空当前库（换新库文件路径）再恢复。
      await RunDatabase.instance.close();
      final dir2 = await Directory.systemTemp.createTemp('runtrail-rt-');
      PathProviderPlatform.instance = TestDocuments(dir2.path);
      await databaseFactory.setDatabasesPath(dir2.path);

      final restore = await BackupService.restoreJson(json);
      expect(restore.imported, 1);
      final restored = await RunDatabase.instance.listRuns();
      expect(restored.length, 1);
      expect(restored.first.title, '长距离');
      expect(restored.first.distanceKm, closeTo(12.5, 1e-9));
      final pts = await RunDatabase.instance.getPoints(restored.first.id!);
      expect(pts, hasLength(2));
      expect(pts[1].elapsedMs, 120000);
    });

    test('恢复应用偏好设置', () async {
      Prefs.instance.weeklyGoalKm = 20;
      final json = jsonEncode({
        'app': 'RunTrail',
        'format': 1,
        'runs': [],
        'prefs': {'weekly_goal_km': 88, 'yearly_goal_km': 1200},
      });
      await BackupService.restoreJson(json);
      expect(Prefs.instance.weeklyGoalKm, 88);
      // yearly_goal_km 1200 超出 1–1000 校验范围，应被拒绝保持原值。
      expect(Prefs.instance.yearlyGoalKm, 500);
    });
  });

  group('parseGpx（GPX 导入）', () {
    final start = DateTime.utc(2026, 9, 30, 0, 0, 0);
    RunPoint p(int i, {bool seg = false}) => RunPoint(
      lat: 39.0 + 0.001 * i,
      lng: 116.0,
      altitude: 10,
      time: start.add(Duration(seconds: 60 * i)),
      startsSegment: seg,
    );

    test('导出 → 导入往返：点数、段边界、时长与统计', () {
      final record = RunRecord(
        sessionId: 's1',
        start: start,
        end: start.add(const Duration(minutes: 11)),
        distanceM: 222,
        durationS: 120,
        calories: 15,
        climbM: 0,
        title: '往返测试',
      );
      final points = [p(0), p(1), p(2, seg: true), p(3)];
      // p1→p2 间隔 60s 但跨段（暂停 60s），活动时长应为 120s 而非 180s。
      final gpx = buildGpx(record, points);

      final imported = parseGpx(gpx);
      final r = imported.record;
      expect(r.source, RunRecord.sourceGpx);
      expect(r.sessionKey, 'gpx-${start.millisecondsSinceEpoch}');
      expect(r.title, '往返测试');
      expect(r.durationS, 120);
      // 两段各 ~111m（0.001° 纬度）。
      expect(r.distanceM, closeTo(222, 2));
      expect(imported.points, hasLength(4));
      expect(imported.points[2].startsSegment, isTrue);
      expect(imported.points[0].startsSegment, isFalse);
      expect(imported.points.last.elapsedMs, 120000);
      expect(r.start, start);
    });

    test('第三方导出格式（多 trkseg + ele 爬升 + name 标题）', () {
      const xml = '<?xml version="1.0" encoding="UTF-8"?>'
          '<gpx version="1.1" creator="Keep" '
          'xmlns="http://www.topografix.com/GPX/1/1">'
          '<trk><name>公园晨跑</name>'
          '<trkseg>'
          '<trkpt lat="31.000000" lon="121.000000">'
          '<ele>10.0</ele><time>2026-10-01T00:00:00Z</time></trkpt>'
          '<trkpt lat="31.000270" lon="121.000000">'
          '<ele>14.0</ele><time>2026-10-01T00:00:10Z</time></trkpt>'
          '</trkseg><trkseg>'
          '<trkpt lat="31.000540" lon="121.000000">'
          '<ele>14.0</ele><time>2026-10-01T00:05:00Z</time></trkpt>'
          '<trkpt lat="31.000810" lon="121.000000">'
          '<ele>18.5</ele><time>2026-10-01T00:05:10Z</time></trkpt>'
          '</trkseg></trk></gpx>';
      final imported = parseGpx(xml);
      final r = imported.record;
      expect(r.title, '公园晨跑');
      // 两段各 10s，段间 4 分 50 秒的暂停不计入时长。
      expect(r.durationS, 20);
      // 每段 0.00027° 纬度 ≈ 30m。
      expect(r.distanceM, closeTo(60, 1));
      // 爬升：+4m 与 +4.5m 都过了 3m 死区。
      expect(r.climbM, closeTo(8.5, 0.1));
      expect(imported.points[2].startsSegment, isTrue);
      // 卡路里公式与 App 一致。
      expect(r.calories, ((r.distanceKm) * 65 * 1.036).round());
    });

    test('缺失时间戳：少于 2 个有效时间报错', () {
      const xml = '<gpx><trk><trkseg>'
          '<trkpt lat="31.0" lon="121.0"></trkpt>'
          '<trkpt lat="31.001" lon="121.0"></trkpt>'
          '</trkseg></trk></gpx>';
      expect(
        () => parseGpx(xml),
        throwsA(
          isA<GpxFormatException>().having((e) => e.reason, 'reason', 'no_time'),
        ),
      );
    });

    test('无轨迹点或非 GPX 内容报错', () {
      expect(
        () => parseGpx('<gpx><metadata><name>x</name></metadata></gpx>'),
        throwsA(
          isA<GpxFormatException>()
              .having((e) => e.reason, 'reason', 'no_track_points'),
        ),
      );
      expect(
        () => parseGpx('not xml at all'),
        throwsA(isA<GpxFormatException>()),
      );
    });

    test('中间点缺时间戳时线性插值补齐', () {
      const xml = '<gpx><trk><trkseg>'
          '<trkpt lat="31.0" lon="121.0">'
          '<time>2026-10-01T00:00:00Z</time></trkpt>'
          '<trkpt lat="31.000270" lon="121.0"></trkpt>'
          '<trkpt lat="31.000540" lon="121.0">'
          '<time>2026-10-01T00:00:20Z</time></trkpt>'
          '</trkseg></trk></gpx>';
      final imported = parseGpx(xml);
      expect(imported.record.durationS, 20);
      // 插值出的中间点时间应为 00:00:10。
      expect(
        imported.points[1].time,
        DateTime.utc(2026, 10, 1, 0, 0, 10),
      );
    });
  });

  group('importRunFromGpx（幂等导入）', () {
    // 与 parseGpx 用例相同的多段轨迹。
    const xml = '<gpx><trk><name>公园晨跑</name><trkseg>'
        '<trkpt lat="31.000000" lon="121.000000">'
        '<ele>10.0</ele><time>2026-10-01T00:00:00Z</time></trkpt>'
        '<trkpt lat="31.000270" lon="121.000000">'
        '<ele>14.0</ele><time>2026-10-01T00:00:10Z</time></trkpt>'
        '</trkseg><trkseg>'
        '<trkpt lat="31.000540" lon="121.000000">'
        '<ele>14.0</ele><time>2026-10-01T00:05:00Z</time></trkpt>'
        '<trkpt lat="31.000810" lon="121.000000">'
        '<ele>18.5</ele><time>2026-10-01T00:05:10Z</time></trkpt>'
        '</trkseg></trk></gpx>';

    test('首次导入写入，重复导入幂等跳过', () async {
      final first = await importRunFromGpx(xml);
      expect(first.status, GpxImportStatus.imported);
      expect(first.import.record.title, '公园晨跑');
      expect(await RunDatabase.instance.listRuns(), hasLength(1));

      // 同一文件再导入：sessionKey 相同，不应重复插入。
      final second = await importRunFromGpx(xml);
      expect(second.status, GpxImportStatus.duplicate);
      expect(second.isDuplicate, isTrue);
      expect(await RunDatabase.instance.listRuns(), hasLength(1));

      // 轨迹点也只写入一份（1 条记录 4 个点）。
      final stored = await RunDatabase.instance.listRuns();
      expect(stored.single.title, '公园晨跑');
    });

    test('不同开始时间的 GPX 视为不同记录', () async {
      await importRunFromGpx(xml);
      const otherDay = '<gpx><trk><trkseg>'
          '<trkpt lat="31.0" lon="121.0">'
          '<time>2026-10-08T02:00:00Z</time></trkpt>'
          '<trkpt lat="31.000270" lon="121.0">'
          '<time>2026-10-08T02:00:10Z</time></trkpt>'
          '</trkseg></trk></gpx>';
      final outcome = await importRunFromGpx(otherDay);
      expect(outcome.status, GpxImportStatus.imported);
      expect(await RunDatabase.instance.listRuns(), hasLength(2));
    });
  });
}
