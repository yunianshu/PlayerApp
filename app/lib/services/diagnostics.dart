import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 本地诊断日志：未捕获异常与关键事件（启动/TTS）落盘，供"我的 → 诊断日志"查看。
/// 无服务器上报；测试环境（FLUTTER_TEST）自动禁用。
class Diagnostics {
  Diagnostics._();

  /// 与 pubspec version 同步更新（启动标记/关于页显示用）。
  /// test/version_sync_test.dart 会校验两者一致，改 pubspec 时记得同步这里。
  static const appVersion = '1.3.2+20';

  static const _fileName = 'diagnostics.log';
  static const _maxBytes = 256 * 1024;
  static bool _installed = false;

  /// 挂接 Flutter 框架异常与未捕获异步异常。可在 main() 调用一次。
  static void install() {
    if (_installed || _isTest) return;
    _installed = true;
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(logError('FLUTTER', details.exception, details.stack));
      original?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(logError('UNCAUGHT', error, stack));
      return true;
    };
  }

  /// 启动标记：日志永远至少有一行，便于确认日志链路与安装的构建版本。
  static Future<void> logStartup() async {
    if (_isTest) return;
    await _write(
      'INFO app start RunTrail $appVersion (${Platform.operatingSystem})',
    );
  }

  static bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> log(String message) async {
    if (_isTest) return;
    await _write('INFO $message');
  }

  static Future<void> logError(
    String source,
    Object error,
    StackTrace? stack,
  ) async {
    if (_isTest) return;
    // 保留调用位置，避免日志只剩无法定位的 null check 文案。
    final trace = stack == null ? '' : '\n${stack.toString().trimRight()}';
    await _write('$source $error$trace');
  }

  static Future<void> _write(String line) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      final stamp = DateTime.now().toIso8601String();
      await file.writeAsString('$stamp $line\n', mode: FileMode.append);
      if (await file.length() > _maxBytes) {
        // 超限截断：只保留后半段，避免无限增长。
        final content = await file.readAsString();
        await file.writeAsString(content.substring(content.length ~/ 2));
      }
    } on Object {
      // 诊断写入失败必须静默：不能因日志再抛异常。
    }
  }

  /// 读取最近的日志（尾部 maxChars 字符）；文件不存在返回 null。
  static Future<String?> readRecent({int maxChars = 6000}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) return null;
      var content = await file.readAsString();
      if (content.length > maxChars) {
        content = content.substring(content.length - maxChars);
      }
      return content;
    } on Object {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (await file.exists()) await file.delete();
    } on Object {
      // 静默。
    }
  }
}
