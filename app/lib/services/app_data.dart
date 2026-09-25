import 'package:flutter/foundation.dart';

/// 全局数据版本号：跑步保存/删除/目标修改后 bump，
/// 各 tab 页监听它以刷新数据库内容（IndexedStack 常驻页面无法依赖 initState）。
class AppData extends ChangeNotifier {
  static final AppData instance = AppData._();
  AppData._();

  int _version = 0;
  int get version => _version;

  void bump() {
    _version++;
    notifyListeners();
  }
}
