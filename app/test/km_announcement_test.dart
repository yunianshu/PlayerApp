import 'package:flutter_test/flutter_test.dart';

import 'package:runtrail/services/tracking_policies.dart';

void main() {
  test('默认间隔全开时播报距离 + 最近一公里分段用时 + 平均配速', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: true,
      sayTime: true,
      sayPace: true,
      unitIndex: 2,
      intervalM: 1000,
      splitSeconds: 330,
      totalSeconds: 720,
    );
    expect(r.text, '第2公里，最近一公里用时5分30秒，平均配速6分00秒');
    expect(r.newBest1km, isFalse);
    expect(r.newLongest, isFalse);
    expect(r.newHalf, isFalse);
    expect(r.newFull, isFalse);
  });

  test('分段用时秒位补零', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: true,
      sayPace: false,
      unitIndex: 1,
      intervalM: 1000,
      splitSeconds: 365,
      totalSeconds: 365,
    );
    expect(r.text, '最近一公里用时6分05秒');
  });

  test('500 米间隔播报累计距离与最近 500 米用时', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: true,
      sayTime: true,
      sayPace: true,
      unitIndex: 7, // 7 × 500m = 3.5 km
      intervalM: 500,
      splitSeconds: 170,
      totalSeconds: 1260,
    );
    expect(r.text, '已跑3.5公里，最近500米用时2分50秒，平均配速6分00秒');
  });

  test('2 公里间隔播报累计距离与最近两公里用时', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: true,
      sayTime: true,
      sayPace: false,
      unitIndex: 2,
      intervalM: 2000,
      splitSeconds: 660,
      totalSeconds: 1320,
    );
    expect(r.text, '已跑4公里，最近两公里用时11分00秒');
  });

  test('开关全关返回 null', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 3,
      intervalM: 1000,
      splitSeconds: 300,
      totalSeconds: 900,
    );
    expect(r.text, isNull);
  });

  test('整公里分段快于最快 1 公里纪录时追加破纪录播报', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: true,
      sayTime: true,
      sayPace: false,
      unitIndex: 4,
      intervalM: 1000,
      splitSeconds: 290,
      totalSeconds: 1300,
      km: 4,
      kmSplitSeconds: 290,
      best1kmSec: 300,
    );
    expect(r.newBest1km, isTrue);
    expect(r.text, contains('刷新一公里最快纪录'));
  });

  test('非公里点（500 米间隔）即使分段快也不触发 1 公里破纪录', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 1,
      intervalM: 500,
      splitSeconds: 140,
      totalSeconds: 140,
      best1kmSec: 300,
    );
    expect(r.newBest1km, isFalse);
    expect(r.text, isNull);
  });

  test('分段慢于纪录不播报破纪录', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 4,
      intervalM: 1000,
      splitSeconds: 310,
      totalSeconds: 1300,
      km: 4,
      kmSplitSeconds: 310,
      best1kmSec: 300,
    );
    expect(r.newBest1km, isFalse);
    expect(r.text, isNull);
  });

  test('超过最长距离纪录播报一次，重复回调不再播', () {
    final first = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 6,
      intervalM: 1000,
      splitSeconds: 360,
      totalSeconds: 2100,
      longestDistanceM: 5500,
      currentDistanceM: 6012,
    );
    expect(first.newLongest, isTrue);
    expect(first.text, contains('刷新最长跑步距离纪录'));

    final again = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 7,
      intervalM: 1000,
      splitSeconds: 360,
      totalSeconds: 2460,
      longestDistanceM: 5500,
      currentDistanceM: 7000,
      longestAlreadyAnnounced: true,
    );
    expect(again.newLongest, isFalse);
    expect(again.text, isNull);
  });

  test('半马里程碑达成播报一次', () {
    final first = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 22,
      intervalM: 1000,
      splitSeconds: 400,
      totalSeconds: 8800,
      currentDistanceM: halfMarathonM,
    );
    expect(first.newHalf, isTrue);
    expect(first.text, contains('完成半马距离'));

    final again = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 23,
      intervalM: 1000,
      splitSeconds: 400,
      totalSeconds: 9200,
      currentDistanceM: 22500,
      halfMarathonAnnounced: true,
    );
    expect(again.newHalf, isFalse);
    expect(again.text, isNull);
  });

  test('全马里程碑达成播报且不重复半马', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 43,
      intervalM: 1000,
      splitSeconds: 400,
      totalSeconds: 17200,
      currentDistanceM: fullMarathonM,
      halfMarathonAnnounced: true,
    );
    expect(r.newFull, isTrue);
    expect(r.newHalf, isFalse);
    expect(r.text, contains('完成全马距离'));
  });

  test('无历史纪录（首次跑步）不播破纪录', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: true,
      sayTime: true,
      sayPace: true,
      unitIndex: 1,
      intervalM: 1000,
      splitSeconds: 400,
      totalSeconds: 400,
    );
    expect(r.text, '第1公里，最近一公里用时6分40秒，平均配速6分40秒');
  });

  test('英文文案（默认间隔与 500 米间隔）', () {
    final r = kmAnnouncementText(
      english: true,
      sayDistance: true,
      sayTime: true,
      sayPace: true,
      unitIndex: 2,
      intervalM: 1000,
      splitSeconds: 330,
      totalSeconds: 720,
    );
    expect(
      r.text,
      'Kilometer 2, last km 5 minutes 30 seconds, '
      'average pace 6 minutes 0 seconds per kilometer',
    );

    final half = kmAnnouncementText(
      english: true,
      sayDistance: false,
      sayTime: false,
      sayPace: false,
      unitIndex: 3,
      intervalM: 500,
      splitSeconds: 150,
      totalSeconds: 1000,
      currentDistanceM: halfMarathonM,
    );
    expect(half.text, contains('half marathon distance done'));
  });

  test('非法输入返回空结果', () {
    final r = kmAnnouncementText(
      english: false,
      sayDistance: true,
      sayTime: true,
      sayPace: true,
      unitIndex: 0,
      intervalM: 1000,
      splitSeconds: -1,
      totalSeconds: 10,
    );
    expect(r.text, isNull);
    expect(r.newBest1km, isFalse);
    expect(r.newLongest, isFalse);
    expect(r.newHalf, isFalse);
    expect(r.newFull, isFalse);
  });
}

