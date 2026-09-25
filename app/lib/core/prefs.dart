import 'package:shared_preferences/shared_preferences.dart';

/// 本地偏好设置（目标等），纯本地存储。
class Prefs {
  Prefs._();
  static final Prefs instance = Prefs._();

  static const _weeklyGoalKey = 'weekly_goal_km';
  static const _yearlyGoalKey = 'yearly_goal_km';

  double weeklyGoalKm = 20;
  double yearlyGoalKm = 500;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    weeklyGoalKm = sp.getDouble(_weeklyGoalKey) ?? 20;
    yearlyGoalKm = sp.getDouble(_yearlyGoalKey) ?? 500;
  }

  Future<void> setWeeklyGoal(double km) async {
    weeklyGoalKm = km;
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_weeklyGoalKey, km);
  }

  Future<void> setYearlyGoal(double km) async {
    yearlyGoalKm = km;
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_yearlyGoalKey, km);
  }
}
