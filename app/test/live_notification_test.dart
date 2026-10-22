// 锁屏通知实时刷新链路：tracker 每秒把成绩推进 runtrail/background 通道。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'; // ignore: depend_on_referenced_packages
import 'package:runtrail/services/run_tracker.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart'; // ignore: depend_on_referenced_packages

class FakeGeo extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast(sync: true);
  final services = StreamController<ServiceStatus>.broadcast(sync: true);
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Stream<ServiceStatus> getServiceStatusStream() => services.stream;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      positions.stream;
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

final origin = DateTime(2026, 9, 27, 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeGeo geo;
  late RunTracker tracker;
  late DateTime now;
  final calls = <(String, String)>[];

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('runtrail-live-notif-');
    PathProviderPlatform.instance = FakePath(dir.path);
    WakelockPlusPlatformInterface.instance = FakeWake();
    geo = FakeGeo();
    GeolocatorPlatform.instance = geo;
    now = origin;
    tracker = RunTracker(now: () => now);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('runtrail/background'), (
          call,
        ) async {
          calls.add((call.method, '${call.arguments}'));
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('runtrail/background'), null);
    await tracker.discard();
    tracker.dispose();
    await geo.positions.close();
    await geo.services.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  void emit(double meters, int seconds) {
    now = origin.add(Duration(seconds: seconds));
    geo.positions.add(
      Position(
        latitude: meters / 6371000 * 180 / math.pi,
        longitude: 0,
        altitude: 0,
        timestamp: now,
        accuracy: 5,
        altitudeAccuracy: 0.1,
        heading: 0,
        headingAccuracy: 0,
        speed: 3,
        speedAccuracy: 0.1,
      ),
    );
  }

  // 每秒 ticker 是真实定时器：让测试进程真实等待 [seconds] 秒并同步推进注入时钟。
  Future<void> passSeconds(int seconds) async {
    for (var i = 0; i < seconds; i++) {
      now = now.add(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 1050));
    }
  }

  test('跑步中通知随时间刷新，文案去重', () async {
    expect(await tracker.start(), isTrue);
    // start 走 _backgroundWork 微任务链，先让出事件循环。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls.map((c) => c.$1), contains('start'));

    emit(0, 1); // 首点作为锚点。
    emit(50, 21); // 20 秒前进 50 米（2.5 m/s，通过跳跃速度守卫）。
    await passSeconds(12);

    final updates = calls.where((c) => c.$1 == 'update').map((c) => c.$2).toList();
    // 每秒刷新且文案随用时变化（去重后仍有多个不同值）。
    expect(updates.length, greaterThanOrEqualTo(2));
    expect(updates.toSet().length, greaterThanOrEqualTo(2));
    expect(updates.last, contains('0.05 公里'));
    expect(updates.last, contains('/公里'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('停止后不再刷新通知', () async {
    expect(await tracker.start(), isTrue);
    await passSeconds(2);
    await tracker.stop();
    final countBefore = calls.length;
    await passSeconds(2);
    // stop 之后通道不再有任何新调用（含 update）。
    expect(calls.length, countBefore);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
