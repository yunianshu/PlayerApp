import 'package:flutter/services.dart';

/// 系统文件选择（导入备份用）：Android SAF / iOS 文档选择器。
/// 鸿蒙端无原生实现 → 返回 null，由界面降级提示。
class FilePickService {
  FilePickService._();

  static const _channel = MethodChannel('runtrail/filepicker');

  /// 选择一个 JSON 文件，返回可读的本地路径；取消/不支持返回 null。
  static Future<String?> pickJson() async {
    try {
      return await _channel.invokeMethod<String>('pickJson');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
