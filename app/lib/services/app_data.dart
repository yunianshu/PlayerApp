import 'package:flutter/foundation.dart';

import '../core/calendar.dart';

/// 全局数据版本号：跑步保存/删除/目标修改后 bump，
/// 各 tab 页监听它以刷新数据库内容（IndexedStack 常驻页面无法依赖 initState）。
class AppData extends ChangeNotifier {
  static final AppData instance = AppData._();
  AppData._();

  int _version = 0;
  int get version => _version;
  DateTime _date = Calendar.day(DateTime.now());

  bool refreshForDate({DateTime? now}) {
    final date = Calendar.day(now ?? DateTime.now());
    if (date == _date) return false;
    _date = date;
    bump();
    return true;
  }

  void bump() {
    _version++;
    notifyListeners();
  }
}
