import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/pages/training_plan_share_page.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/services/training_plan_export.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getTemporaryPath() async => path;
}

TrainingPlanExportData fixture(
  int count, {
  String note = '轻松训练，完整显示屏幕外的训练安排。',
}) {
  final start = DateTime(2026, 12, 20);
  return TrainingPlanExportData(
    name: '测试马拉松',
    raceDate: '2027-12-20',
    goal: '目标：健康完赛',
    createdAt: DateTime(2026, 12, 20),
    completed: {'2026-12-20'},
    tasks: List.generate(
      count,
      (i) => TrainingTask(
        start.add(Duration(days: i)).toIso8601String().substring(0, 10),
        i.isEven ? 'EASY' : 'REST',
        '训练日 ${i + 1}',
        i.isEven ? 5 : 0,
        '$note [${i + 1}]',
        easyPace: i.isEven ? 420 : null,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final regular = FontLoader('Noto Sans SC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf'));
    await regular.load();
  });
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('plan-export-test-');
    PathProviderPlatform.instance = _Paths(temp.path);
  });
  tearDown(() async {
    // Windows 上分享的长图可能仍被异步句柄短暂占用，硬删会抛 errno 32；
    // 清理失败不判定为用例失败，留给系统临时目录回收。
    if (await temp.exists()) {
      try {
        await temp.delete(recursive: true);
      } on FileSystemException {
        // ignore: best-effort cleanup
      }
    }
  });

  test(
    'snapshot sorts all dates and does not retain mutable completion state',
    () {
      final tasks = [...fixture(3).tasks.reversed];
      final completed = <String>{};
      final data = TrainingPlanExportData(
        name: '赛事',
        raceDate: '2026-12-20',
        goal: '完赛',
        createdAt: DateTime(2026, 12, 20),
        tasks: tasks,
        completed: completed,
      );
      tasks.clear();
      completed.add('2026-12-20');
      expect(data.tasks.length, 3);
      expect(data.tasks.first.date, '2026-12-20');
      expect(data.completed, isEmpty);
      expect(data.countdown, '今天比赛');
    },
  );

  for (final palette in [
    AppPalette.light,
    AppPalette.dark,
    AppPalette.editorial,
  ]) {
    testWidgets(
      'full PNG includes every date and both year/month boundaries (${palette.bg})',
      (tester) async {
        final data = fixture(28);
        final layout = TrainingPlanExportLayout(data, palette);
        addTearDown(layout.dispose);
        final text = layout.content.join('\n');
        for (final task in data.tasks) {
          expect(text, contains(task.date));
          expect(text, contains(task.title));
          expect(text, contains(task.notes));
        }
        expect(text, contains('2026 年 12 月'));
        expect(text, contains('2027 年 01 月'));
        expect(text, contains('手动标记完成'));
        expect(text, contains('暂无跑步记录'));
        expect(layout.supportsPng, isTrue);
        final result = await tester.runAsync(
          () => layout.generate(temporaryRoot: temp, pdf: false),
        );
        expect(result!.previews, hasLength(layout.pageCount));
        final bytes = await tester.runAsync(() => result.file.readAsBytes());
        expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), 900);
        expect(header.getUint32(20), layout.pageCount * 1400);
        // Decode our incremental PNG, not only its header, proving CRC/zlib framing.
        final image = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            return (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        });
        expect(image!.height, layout.pngHeight);
        image.dispose();
        final artifactDir = Platform.environment['TRAINING_EXPORT_PREVIEW_DIR'];
        if (artifactDir != null) {
          await tester.runAsync(() async {
            await Directory(artifactDir).create(recursive: true);
            final name = palette.isEditorial
                ? 'editorial'
                : palette.isDark
                ? 'dark'
                : 'light';
            await result.file.copy('$artifactDir/training-plan-$name.png');
            await result.previews.first.copy(
              '$artifactDir/training-plan-$name-first-page.png',
            );
            await result.previews.last.copy(
              '$artifactDir/training-plan-$name-last-page.png',
            );
          });
        }
        await tester.runAsync(result.dispose);
        expect(result.directory.existsSync(), isFalse);
      },
    );
  }

  testWidgets(
    '365 days requires explicit PDF and retains all dates on all pages',
    (tester) async {
      final data = fixture(365);
      final layout = TrainingPlanExportLayout(data, AppPalette.editorial);
      addTearDown(layout.dispose);
      expect(layout.supportsPng, isFalse);
      expect(layout.content.join('\n'), contains(data.tasks.last.date));
      await expectLater(
        layout.generate(temporaryRoot: temp, pdf: false),
        throwsStateError,
      );
      final result = await tester.runAsync(
        () => layout.generate(temporaryRoot: temp, pdf: true),
      );
      final bytes = await tester.runAsync(() => result!.file.readAsBytes());
      final pdf = String.fromCharCodes(bytes!);
      expect(pdf, startsWith('%PDF-1.4'));
      expect(pdf, contains('/Count ${layout.pageCount}'));
      expect(
        RegExp('/Type /Page /Parent').allMatches(pdf).length,
        layout.pageCount,
      );
      expect(result!.previews.length, layout.pageCount);
      expect(pdf, endsWith('%%EOF\n'));
      final artifactDir = Platform.environment['TRAINING_EXPORT_PREVIEW_DIR'];
      if (artifactDir != null) {
        await tester.runAsync(() async {
          await Directory(artifactDir).create(recursive: true);
          await result.file.copy('$artifactDir/training-plan-365-days.pdf');
        });
      }
      final xref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(pdf)!.group(1)!,
      );
      expect(pdf.substring(xref), startsWith('xref\n'));
      for (final match in RegExp(r'(\d{10}) 00000 n').allMatches(pdf)) {
        final offset = int.parse(match.group(1)!);
        expect(RegExp(r'^\d+ 0 obj').hasMatch(pdf.substring(offset)), isTrue);
      }
      final imageStream = RegExp(
        r'/Filter /FlateDecode /Length (\d+) >>\nstream\n',
      ).firstMatch(pdf)!;
      final streamLength = int.parse(imageStream.group(1)!);
      final raw = ZLibDecoder().convert(
        bytes.sublist(imageStream.end, imageStream.end + streamLength),
      );
      expect(raw.length, 900 * 1400 * 3);
    },
  );

  test('optional notes never silently disappear and actual results use shared model', () {
    final data = fixture(2);
    final privateLayout = TrainingPlanExportLayout(
      data,
      AppPalette.editorial,
      includeNotes: false,
    );
    final fullLayout = TrainingPlanExportLayout(
      data,
      AppPalette.editorial,
      includeNotes: true,
    );
    addTearDown(privateLayout.dispose);
    addTearDown(fullLayout.dispose);
    expect(privateLayout.content.join('\n'), contains('训练说明未附带'));
    expect(
      privateLayout.content.join('\n'),
      isNot(contains(data.tasks.first.notes)),
    );
    expect(fullLayout.content.join('\n'), contains(data.tasks.first.notes));
    expect(
      fullLayout.content.join('\n'),
      contains(data.resultFor(data.tasks.first).summary),
    );
  });

  testWidgets(
    'export pixels are independent of portrait or landscape viewport',
    (tester) async {
      final layout = TrainingPlanExportLayout(fixture(2), AppPalette.light);
      addTearDown(layout.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(360, 800);
      final portrait = await tester.runAsync(
        () => layout.generate(temporaryRoot: temp, pdf: false),
      );
      tester.view.physicalSize = const Size(800, 360);
      final landscape = await tester.runAsync(
        () => layout.generate(temporaryRoot: temp, pdf: false),
      );
      final a = await tester.runAsync(() => portrait!.file.readAsBytes());
      final b = await tester.runAsync(() => landscape!.file.readAsBytes());
      expect(a, orderedEquals(b!));
    },
  );

  testWidgets('cancel after a tile removes partial files and never truncates', (
    tester,
  ) async {
    final layout = TrainingPlanExportLayout(fixture(28), AppPalette.light);
    addTearDown(layout.dispose);
    var cancel = false;
    await tester.runAsync(() async {
      await expectLater(
        layout.generate(
          temporaryRoot: temp,
          pdf: false,
          cancelled: () => cancel,
          onProgress: (completed, total) => cancel = true,
        ),
        throwsA(isA<TrainingExportCancelled>()),
      );
    });
    expect(temp.listSync(), isEmpty);
  });

  testWidgets('long Unicode notes/newlines are expanded without ellipsis', (
    tester,
  ) async {
    final note = List.filled(500, '训练🙂\n').join();
    final data = fixture(1, note: note);
    final layout = TrainingPlanExportLayout(data, AppPalette.dark);
    addTearDown(layout.dispose);
    expect(layout.content.join('\n'), contains(note.trimRight()));
    expect(layout.pageCount, greaterThan(2));
    expect(layout.content.last, contains('恢复情况'));
  });

  testWidgets(
    'preview requires explicit generation then explicit share; double tap is guarded',
    (tester) async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return '';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingPlanSharePage(
            data: fixture(2),
            palette: AppPalette.editorial,
          ),
        ),
      );
      expect(calls, isEmpty);
      await tester.tap(find.text('生成完整长图'));
      await tester.tap(find.text('生成完整长图'));
      await tester.pump();
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const Key('training-export-preview')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        // Advance the widget zone's clock as well as real I/O. The exporter
        // yields through a zero-duration timer between bounded raster tiles.
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(calls, isEmpty);
      expect(find.byKey(const Key('training-export-preview')), findsOneWidget);
      await tester.tap(find.text('确认预览并分享长图'));
      await tester.tap(find.text('确认预览并分享长图'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['mimeTypes'], ['image/png']);
      final path =
          ((calls.single.arguments as Map)['paths'] as List).single as String;
      expect(File(path).existsSync(), isTrue);
      await tester.pumpWidget(const SizedBox());
      // File survives dismissal because native receivers may open it asynchronously.
      expect(File(path).existsSync(), isTrue);
    },
  );
}
