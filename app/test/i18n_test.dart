import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/i18n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.pref = AppLanguage.system;
  });

  group('LocaleController.systemCode（测试环境固定 zh）', () {
    test('FLUTTER_TEST 环境返回 zh，避免宿主机 locale 影响断言', () {
      expect(LocaleController.systemCode, 'zh');
    });
  });

  group('translate / .tr', () {
    test('中文（默认）返回原文', () {
      LocaleController.instance.pref = AppLanguage.zh;
      expect('数据统计'.tr, '数据统计');
      expect(translate('本周里程'), '本周里程');
    });

    test('英文走字典覆盖', () {
      LocaleController.instance.pref = AppLanguage.en;
      expect('数据统计'.tr, 'Stats');
      expect('本周里程'.tr, 'This week');
      expect('恭喜解锁新徽章'.tr, 'New badges unlocked!');
      // 底栏、开始跑步、加载错误、手动补录（曾经漏翻的入口）。
      expect('首页'.tr, 'Home');
      expect('我的'.tr, 'Me');
      expect('需要定位权限才能记录跑步轨迹'.tr,
          'Location permission is required to record runs');
      expect('数据加载失败，请重试'.tr, 'Failed to load data, please retry');
      expect('放弃这条记录'.tr, 'Discard this run');
      expect('跑步机 5km'.tr, 'Treadmill 5km');
    });

    test('字典未收录的字符串回退中文', () {
      LocaleController.instance.pref = AppLanguage.en;
      expect('没有这个词条的字符串'.tr, '没有这个词条的字符串');
    });

    test('跟随系统时取 systemCode', () {
      LocaleController.instance.pref = AppLanguage.system;
      expect(LocaleController.instance.code, LocaleController.systemCode);
    });

    test('isEnglish 与 code 一致', () {
      LocaleController.instance.pref = AppLanguage.en;
      expect(LocaleController.instance.isEnglish, isTrue);
      LocaleController.instance.pref = AppLanguage.zh;
      expect(LocaleController.instance.isEnglish, isFalse);
    });
  });

  group('语言偏好持久化', () {
    test('set 写入偏好并可加载回读', () async {
      await LocaleController.instance.set(AppLanguage.en);
      expect(LocaleController.instance.pref, AppLanguage.en);
      // 单例上的 load 会覆盖内存值：清空 mock 后再读应回退 system→zh。
      SharedPreferences.setMockInitialValues({});
      await LocaleController.instance.load();
      expect(LocaleController.instance.pref, AppLanguage.system);
    });

    test('损坏的偏好值回退跟随系统', () async {
      SharedPreferences.setMockInitialValues({'app_language': 'fr'});
      await LocaleController.instance.load();
      expect(LocaleController.instance.pref, AppLanguage.system);
    });
  });
}
