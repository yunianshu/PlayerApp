import 'package:shared_preferences/shared_preferences.dart';

/// 本地偏好设置（目标、记录设置等），纯本地存储。
class Prefs {
  Prefs._();
  static final Prefs instance = Prefs._();

  static const _weeklyGoalKey = 'weekly_goal_km';
  static const _yearlyGoalKey = 'yearly_goal_km';
  static const _autoPauseKey = 'auto_pause_enabled';
  static const _keepScreenOnKey = 'keep_screen_on_enabled';
  static const _voiceKey = 'voice_announce_enabled';
  static const _voiceDistanceKey = 'voice_announce_distance';
  static const _voiceTimeKey = 'voice_announce_time';
  static const _voicePaceKey = 'voice_announce_pace';
  static const _voiceIntervalKey = 'voice_announce_interval_m';
  static const _paceTargetKey = 'pace_target_sec_per_km';

  double weeklyGoalKm = 20;
  double yearlyGoalKm = 500;

  /// 自动暂停：默认关闭，避免升级用户感觉行为突变。
  bool autoPauseEnabled = false;

  /// 跑步时保持屏幕常亮：关闭后允许息屏省电，
  /// 实时成绩仍可在锁屏通知上看到（Keep 同款取舍）。
  bool keepScreenOn = true;

  /// 语音播报总开关与内容开关（TTS 不可用时静默跳过）。
  bool voiceEnabled = true;
  bool voiceDistance = true;
  bool voiceTime = true;
  bool voicePace = true;

  /// 播报间隔（米）：500 / 1000 / 2000，Keep 同款的自定义间隔播报。
  int voiceIntervalM = 1000;

  static const validIntervals = {500, 1000, 2000};

  /// 目标配速（秒/公里），0 表示未启用提醒。
  double paceTargetSecPerKm = 0;

  static bool validGoal(double value) =>
      value.isFinite && value >= 1 && value <= 1000;
  static String formatGoal(double value) => value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    double read(String key, double fallback) {
      final value = sp.get(key);
      return value is num && validGoal(value.toDouble())
          ? value.toDouble()
          : fallback;
    }

    weeklyGoalKm = read(_weeklyGoalKey, 20);
    yearlyGoalKm = read(_yearlyGoalKey, 500);
    autoPauseEnabled = sp.getBool(_autoPauseKey) ?? false;
    keepScreenOn = sp.getBool(_keepScreenOnKey) ?? true;
    voiceEnabled = sp.getBool(_voiceKey) ?? true;
    voiceDistance = sp.getBool(_voiceDistanceKey) ?? true;
    voiceTime = sp.getBool(_voiceTimeKey) ?? true;
    voicePace = sp.getBool(_voicePaceKey) ?? true;
    final interval = sp.getInt(_voiceIntervalKey) ?? 1000;
    voiceIntervalM = validIntervals.contains(interval) ? interval : 1000;
    final target = sp.get(_paceTargetKey);
    paceTargetSecPerKm =
        target is num && target.toDouble() > 0 && validPace(target.toDouble())
        ? target.toDouble()
        : 0;
  }

  Future<void> setWeeklyGoal(double km) async {
    if (!validGoal(km)) throw ArgumentError.value(km, 'km', '请输入 1–1000 公里');
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setDouble(_weeklyGoalKey, km)) throw StateError('目标保存失败');
    weeklyGoalKm = km;
  }

  Future<void> setYearlyGoal(double km) async {
    if (!validGoal(km)) throw ArgumentError.value(km, 'km', '请输入 1–1000 公里');
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setDouble(_yearlyGoalKey, km)) throw StateError('目标保存失败');
    yearlyGoalKm = km;
  }

  Future<void> setAutoPause(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setBool(_autoPauseKey, enabled)) {
      throw StateError('设置保存失败');
    }
    autoPauseEnabled = enabled;
  }

  Future<void> setKeepScreenOn(bool enabled) async {
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setBool(_keepScreenOnKey, enabled)) {
      throw StateError('设置保存失败');
    }
    keepScreenOn = enabled;
  }

  Future<void> setVoice({
    required bool enabled,
    required bool distance,
    required bool time,
    required bool pace,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setBool(_voiceKey, enabled) ||
        !await sp.setBool(_voiceDistanceKey, distance) ||
        !await sp.setBool(_voiceTimeKey, time) ||
        !await sp.setBool(_voicePaceKey, pace)) {
      throw StateError('设置保存失败');
    }
    voiceEnabled = enabled;
    voiceDistance = distance;
    voiceTime = time;
    voicePace = pace;
  }

  Future<void> setVoiceInterval(int meters) async {
    if (!validIntervals.contains(meters)) {
      throw ArgumentError.value(meters, 'meters', '播报间隔仅支持 500/1000/2000 米');
    }
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setInt(_voiceIntervalKey, meters)) {
      throw StateError('设置保存失败');
    }
    voiceIntervalM = meters;
  }

  /// 目标配速有效范围：1:00 – 30:00 /公里。
  static bool validPace(double secPerKm) =>
      secPerKm.isFinite && secPerKm >= 60 && secPerKm <= 1800;

  Future<void> setPaceTarget(double secPerKm) async {
    if (secPerKm != 0 && !validPace(secPerKm)) {
      throw ArgumentError.value(secPerKm, 'secPerKm', '目标配速需在 1:00 – 30:00');
    }
    final sp = await SharedPreferences.getInstance();
    if (!await sp.setDouble(_paceTargetKey, secPerKm)) {
      throw StateError('设置保存失败');
    }
    paceTargetSecPerKm = secPerKm;
  }
}
