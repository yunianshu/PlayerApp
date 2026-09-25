import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/core/theme.dart';

void main() {
  group('formatPace', () {
    test('常规配速', () {
      expect(formatPace(329), "5'29\"");
    });

    test('秒位 59.5+ 进位后不显示 60（回归：5\'60"）', () {
      expect(formatPace(359.7), "6'00\"");
      expect(formatPace(359.4), "5'59\"");
      expect(formatPace(59.8), "1'00\"");
    });

    test('非法输入返回占位', () {
      expect(formatPace(null), "--'--\"");
      expect(formatPace(0), "--'--\"");
      expect(formatPace(-5), "--'--\"");
      expect(formatPace(double.nan), "--'--\"");
      expect(formatPace(3601), "--'--\"");
    });

    test('整分钟', () {
      expect(formatPace(300), "5'00\"");
    });
  });

  group('formatDuration', () {
    test('时分秒', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 42, seconds: 3)), '1:42:03');
      expect(formatDuration(const Duration(minutes: 28, seconds: 3)), '28:03');
    });
  });
}
