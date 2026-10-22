// Regression coverage for recording, recovery and calculation defects.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'; // ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart'; // ignore: depend_on_referenced_packages
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/run_draft.dart';
import 'package:runtrail/services/run_tracker.dart';
import 'package:runtrail/services/tracking_location_settings.dart';
import 'package:runtrail/pages/summary_page.dart';
import 'package:runtrail/pages/countdown_page.dart';
import 'package:runtrail/widgets/route_painter.dart';

class FakeGeo extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast(sync: true);
  final services = StreamController<ServiceStatus>.broadcast(sync: true);
  bool enabled = true;
  int subscriptions = 0;
  LocationSettings? lastSettings;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Stream<ServiceStatus> getServiceStatusStream() => services.stream;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptions++;
    lastSettings = locationSettings;
    return positions.stream;
  }
}

class OhosRunTracker extends RunTracker {
  OhosRunTracker({super.now});

  @override
  LocationSettings get locationSettings => trackingLocationSettings('ohos');
}

class FakeWake extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
}

class FakePath extends PathProviderPlatform {
  FakePath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class DelayedPath extends PathProviderPlatform {
  DelayedPath(this.path);
  final String path;
  final first = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> getApplicationDocumentsPath() =>
      calls++ == 0 ? first.future : Future.value(path);
}

final origin = DateTime(2026, 9, 27, 8);
RunPoint point(double meters, int seconds) => RunPoint(
  lat: meters / 6371000 * 180 / math.pi,
  lng: 0,
  altitude: 0,
  time: origin.add(Duration(seconds: seconds)),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGeo geo;
  late RunTracker tracker;
  late DateTime now;
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('runtrail-audit-');
    PathProviderPlatform.instance = FakePath(dir.path);
    WakelockPlusPlatformInterface.instance = FakeWake();
    geo = FakeGeo();
    GeolocatorPlatform.instance = geo;
    now = origin;
    tracker = RunTracker(now: () => now);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('runtrail/tts'),
          (_) async => false,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('runtrail/background'),
          (_) async => null,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('runtrail/tts'), null);
    await tracker.discard();
    tracker.dispose();
    await geo.positions.close();
    await geo.services.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  void emit(
    double meters,
    int seconds, {
    double accuracy = 5,
    double altitude = 0,
  }) {
    now = origin.add(Duration(seconds: seconds));
    final p = point(meters, seconds);
    geo.positions.add(
      Position(
        latitude: p.lat,
        longitude: p.lng,
        timestamp: p.time,
        accuracy: accuracy,
        altitude: altitude,
        altitudeAccuracy: 0.1,
        heading: 0,
        headingAccuracy: 0,
        speed: 5,
        speedAccuracy: 0,
      ),
    );
  }

  test('A01 pause before first GPS fix must not throw', () async {
    await tracker.start();
    expect(tracker.pause, returnsNormally);
  });
  test('A02 paused displacement and time must not count', () async {
    await tracker.start();
    emit(0, 0);
    emit(50, 10);
    tracker.pause();
    now = origin.add(const Duration(seconds: 70));
    await tracker.resume();
    emit(350, 70);
    expect(tracker.distanceM, closeTo(50, 0.01));
    expect(tracker.movingMs, 10000);
  });
  test('A03 constant 5 m/s must report 200 seconds/km', () async {
    await tracker.start();
    emit(0, 0);
    emit(50, 10);
    emit(100, 20);
    emit(150, 30);
    expect(tracker.currentPace, closeTo(200, 0.01));
  });
  test(
    'ohos requests one-second fixes and updates distance and pace',
    () async {
      tracker.dispose();
      tracker = OhosRunTracker(now: () => now);
      expect(await tracker.start(), isTrue);
      final settings = geo.lastSettings!;
      // The pinned native handler divides the wire value (ms) by 1000. Its
      // fallback without this key is 10,000 seconds, preventing live tracking.
      expect(settings.toJson()['timeInterval'], 1000);
      expect(settings.timeLimit, const Duration(seconds: 30));
      for (var second = 0; second <= 50; second++) {
        emit(second * 3.0, second);
      }
      expect(tracker.hasFix, isTrue);
      expect(tracker.points.length, 51);
      expect(tracker.km, closeTo(0.15, 0.00001));
      expect(tracker.currentPace, closeTo(1000 / 3, 0.01));
      expect(tracker.avgPace, closeTo(1000 / 3, 0.01));

      tracker.pause();
      now = origin.add(const Duration(seconds: 110));
      await tracker.resume();
      expect(geo.lastSettings!.toJson()['timeInterval'], 1000);
      emit(500, 110);
      emit(530, 120);
      expect(tracker.distanceM, closeTo(180, 0.01));
      expect(tracker.currentPace, closeTo(1000 / 3, 0.01));
    },
  );

  test(
    'silent-location timeout clears the fix and disconnected segment',
    () async {
      await tracker.start();
      emit(0, 0);
      emit(30, 10);
      geo.positions.addError(TimeoutException('no position updates'));
      expect(tracker.gpsError, isTrue);
      expect(tracker.hasFix, isFalse);
      expect(tracker.currentPace, isNull);
      now = origin.add(const Duration(seconds: 45));
      geo.services.add(ServiceStatus.enabled);
      await Future<void>.delayed(Duration.zero);
      emit(200, 45);
      emit(230, 55);
      expect(tracker.hasFix, isTrue);
      expect(tracker.points[2].startsSegment, isTrue);
      expect(tracker.distanceM, closeTo(60, 0.01));
    },
  );
  test(
    'A04 current pace must expire after 60 seconds without movement',
    () async {
      await tracker.start();
      emit(0, 0);
      emit(50, 10);
      emit(100, 20);
      emit(150, 30);
      now = origin.add(const Duration(seconds: 90));
      expect(tracker.currentPace, anyOf(isNull, 0));
    },
  );
  test('A05 live route must repaint when same list grows', () {
    final pts = [point(0, 0)];
    final oldPainter = RoutePainter(pts);
    pts.add(point(50, 10));
    expect(RoutePainter(pts).shouldRepaint(oldPainter), isTrue);
  });
  test('A06 split calculation must preserve distance beyond km boundary', () {
    final pts = [for (var i = 0; i <= 5; i++) point(i * 600.1, i * 120)];
    expect(splitsOf(pts).length, 3);
  });
  testWidgets('A07 countdown must still show 3 after 100 ms', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: MaterialApp(home: CountdownPage(onComplete: () {})),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((x) => x.data)
        .toList();
    await tester.pumpWidget(const SizedBox());
    expect(texts, isNot(contains('1')));
  });
  test('A08 stop must retain draft until database save succeeds', () async {
    await tracker.start();
    for (var i = 0; i <= 4; i++) {
      emit(i * 50.0, i * 10);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await RunDraft.load(), isNotNull);
    expect(await tracker.stop(), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await RunDraft.load(), isNotNull);
  });
  test('A09 inaccurate fix must not report usable GPS', () async {
    await tracker.start();
    emit(0, 0, accuracy: 500);
    expect(tracker.points, isEmpty);
    expect(tracker.hasFix, isFalse);
  });
  test('A10 concurrent start must only start one run', () async {
    final results = await Future.wait([tracker.start(), tracker.start()]);
    expect(results.where((r) => r).length, 1);
  });
  test('A11 gradual 5m climb must not be lost', () async {
    await tracker.start();
    for (var i = 0; i <= 10; i++) {
      emit(i * 5.0, i * 2, altitude: i * 0.5);
    }
    expect(tracker.climbM, closeTo(5, 0.1));
  });
  test(
    'A12 starting new run must not silently erase recoverable draft',
    () async {
      final draft = RunDraft(
        start: origin,
        elapsedMs: 60000,
        distanceM: 500,
        climbM: 0,
        points: [point(0, 0), point(500, 60)],
      );
      await RunDraft.save(draft);
      expect(await RunDraft.load(), isNotNull);
      await tracker.start();
      expect(await RunDraft.load(), isNotNull);
    },
  );
  test('A13 clear must not resurrect a pending draft write', () async {
    final dir = await Directory.systemTemp.createTemp('runtrail-race-audit-');
    final path = DelayedPath(dir.path);
    PathProviderPlatform.instance = path;
    final draft = RunDraft(
      start: origin,
      elapsedMs: 60000,
      distanceM: 500,
      climbM: 0,
      points: [point(0, 0), point(500, 60)],
    );
    final write = RunDraft.save(draft);
    final clear = RunDraft.clear();
    path.first.complete(dir.path);
    await Future.wait([write, clear]);
    expect(await RunDraft.load(), isNull);
  });

  test(
    'service recovery reconnects and starts a disconnected segment',
    () async {
      await tracker.start();
      emit(0, 0);
      emit(50, 10);
      geo.enabled = false;
      geo.services.add(ServiceStatus.disabled);
      expect(tracker.gpsError, isTrue);
      now = origin.add(const Duration(seconds: 40));
      geo.enabled = true;
      geo.services.add(ServiceStatus.enabled);
      await Future<void>.delayed(Duration.zero);
      emit(350, 40);
      expect(geo.subscriptions, 2);
      expect(tracker.hasFix, isTrue);
      expect(tracker.points.last.startsSegment, isTrue);
      expect(tracker.distanceM, closeTo(50, 0.01));
    },
  );

  test('a failed stream automatically retries while running', () async {
    await tracker.start();
    geo.positions.addError(StateError('provider disconnected'));
    expect(tracker.gpsError, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 5100));
    expect(geo.subscriptions, 2);
    emit(0, 6);
    expect(tracker.hasFix, isTrue);
  });

  test('ticker persists elapsed time without a new GPS position', () async {
    await tracker.start();
    emit(0, 0);
    emit(50, 10);
    expect((await RunDraft.load())!.elapsedMs, 10000);
    now = origin.add(const Duration(seconds: 45));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect((await RunDraft.load())!.elapsedMs, 45000);
    final record = await tracker.stop();
    final finalDraft = (await RunDraft.load())!;
    expect(record!.durationS, 45);
    expect(finalDraft.end, now);
    expect(finalDraft.sessionKey, record.sessionKey);
  });

  test('background task failure is visible to the running page', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('runtrail/background'), (
          call,
        ) async {
          if (call.method == 'start') throw PlatformException(code: 'failed');
          return null;
        });
    await tracker.start();
    await Future<void>.delayed(Duration.zero);
    expect(tracker.backgroundError, isTrue);
  });

  test(
    'splits exclude pause time and displacement but keep km remainder',
    () async {
      await tracker.start();
      emit(0, 0);
      emit(600, 120);
      tracker.pause();
      now = origin.add(const Duration(seconds: 180));
      await tracker.resume();
      emit(900, 180);
      emit(1500, 300);
      final splits = splitsOf(tracker.points);
      expect(tracker.distanceM, closeTo(1200, 0.01));
      expect(splits.length, 1);
      expect(splits.first.$2, closeTo(200, 0.01));
      expect(await tracker.stop(), isNotNull);
      final draft = RunDraft.fromMap((await RunDraft.load())!.toMap())!;
      expect(draft.points[2].startsSegment, isTrue);
      expect(draft.points.last.elapsedMs, 240000);
    },
  );

  test('a stale session cannot clear a newer draft', () async {
    final draft = RunDraft(
      sessionId: 'new-session',
      start: origin,
      elapsedMs: 10000,
      distanceM: 50,
      climbM: 0,
      points: [point(0, 0), point(50, 10)],
    );
    await RunDraft.save(draft);
    await RunDraft.clear(sessionId: 'old-session');
    expect((await RunDraft.load())!.sessionId, 'new-session');
    await RunDraft.clear(sessionId: 'new-session');
    expect(await RunDraft.load(), isNull);
  });

  test('failed draft replacement preserves the previous snapshot and permits retry', () async {
    final dir = await Directory.systemTemp.createTemp('runtrail-atomic-');
    PathProviderPlatform.instance = FakePath(dir.path);
    final draft = RunDraft(
      start: origin,
      elapsedMs: 10000,
      distanceM: 50,
      climbM: 0,
      points: [point(0, 0), point(50, 10)],
    );
    await RunDraft.save(draft);
    final file = dir.listSync().whereType<File>().single;
    final blocker = await Directory('${file.path}.tmp').create();
    await expectLater(
      RunDraft.save(draft),
      throwsA(isA<FileSystemException>()),
    );
    expect((await RunDraft.load())!.distanceM, 50);
    await blocker.delete();
    await RunDraft.save(draft);
    expect((await RunDraft.load())!.distanceM, 50);
  });
}
