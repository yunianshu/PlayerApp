// 版本一致性：Diagnostics.appVersion 必须与 pubspec.yaml 的 version 同步。
// 防止再次出现"关于页只显示过期短版本"的问题。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/services/diagnostics.dart';

/// 解析 pubspec 的 flutter.assets 列表（保持两平台资源声明一致）。
List<String> _assetEntries(String pubspec) {
  // 归一换行：仓库文件多为 CRLF，Dart 的 `.` 不匹配 \r。
  final lines = pubspec.replaceAll('\r\n', '\n').split('\n');
  final entries = <String>[];
  var inAssets = false;
  for (final line in lines) {
    if (RegExp(r'^  assets:\s*$').hasMatch(line)) {
      inAssets = true;
      continue;
    }
    if (inAssets) {
      final m = RegExp(r'^    (.+)$').firstMatch(line);
      if (m == null) break; // 缩进结束，assets 列表结束
      final entry = m[1]!.split('#').first.trim();
      if (entry.isNotEmpty) entries.add(entry);
    }
  }
  return entries;
}

void main() {
  test('Diagnostics.appVersion 与 pubspec.yaml version 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 缺少 version 字段');
    expect(
      Diagnostics.appVersion,
      match!.group(1),
      reason: 'Diagnostics.appVersion 与 pubspec 版本不一致——'
          '升版本时两处都要改（显示完整版本依赖此常量）',
    );
  });

  test('pubspec_ohos 资源声明与主 pubspec 一致', () {
    final main = File('pubspec.yaml').readAsStringSync();
    final ohos = File('pubspec_ohos.yaml').readAsStringSync();
    final mainAssets = _assetEntries(main);
    final ohosAssets = _assetEntries(ohos);
    expect(mainAssets, isNotEmpty, reason: '主 pubspec 缺少 assets 声明');
    expect(
      ohosAssets.toSet().containsAll(mainAssets),
      isTrue,
      reason: 'pubspec_ohos.yaml 缺少资源声明：'
          '${mainAssets.where((a) => !ohosAssets.contains(a)).join(', ')}'
          '——鸿蒙包会漏掉这些文件（曾导致课程页视频缺失）',
    );
  });
}
