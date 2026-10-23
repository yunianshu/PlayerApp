import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/marathon_training_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // activePlan 读取用户偏好的计划 ID，测试环境需 mock 插件通道。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('厦门马拉松计划覆盖完整日期且包含比赛', () async {
    final tasks = await MarathonTrainingService.load();
    expect(tasks.length, 80);
    expect(tasks.first.date, '2026-10-23');
    expect(tasks.last.date, '2027-01-10');
    expect(tasks.last.type, 'RACE');
    expect(tasks.last.km, closeTo(42.195, 0.001));
    expect(tasks.map((e) => e.date).toSet().length, 80);
    expect(tasks.where((e) => e.km < 0), isEmpty);
    expect(tasks.where((e) => e.isRun && e.easyPace == null && e.type != 'RACE'), isEmpty);
  });
}
