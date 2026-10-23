import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/widgets/app_toast.dart';

void main() {
  late BuildContext pageContext;
  Widget app({MediaQueryData? media, VoidCallback? onTap}) => MaterialApp(
    builder: (context, child) =>
        media == null ? child! : MediaQuery(data: media, child: child!),
    home: Scaffold(
      body: Builder(
        builder: (context) {
          pageContext = context;
          return Align(
            alignment: Alignment.topLeft,
            child: TextButton(
              onPressed: onTap ?? () {},
              child: const Text('Page'),
            ),
          );
        },
      ),
    ),
  );

  testWidgets('feedback is centered and outside taps reach the page', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(app(onTap: () => tapped = true));
    showAppToast(pageContext, '已保存');
    await tester.pump();
    final toast = find.byKey(const ValueKey('app-toast'));
    expect(tester.getCenter(toast), const Offset(400, 300));
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Page'));
    expect(tapped, isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(toast, findsNothing);
  });

  testWidgets('repeated feedback replaces old text and restarts timeout', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    showAppToast(pageContext, '旧消息', duration: const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    showAppToast(pageContext, '新消息', duration: const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('旧消息'), findsNothing);
    expect(find.text('新消息'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('新消息'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('新消息'), findsNothing);
  });

  testWidgets('long feedback wraps with large text and a visible keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const message = '提醒设置失败，请先开启通知权限，再返回训练计划页面重新设置每日训练提醒。';
    await tester.pumpWidget(
      app(
        media: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
          viewInsets: EdgeInsets.only(bottom: 240),
        ),
      ),
    );
    showAppToast(pageContext, message);
    await tester.pump();
    final text = tester.widget<Text>(find.text(message));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
    expect(
      tester.getRect(find.byKey(const ValueKey('app-toast'))).bottom,
      lessThanOrEqualTo(400),
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'action is retained and accessible users have time to activate it',
    (tester) async {
      var actions = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(media: const MediaQueryData(accessibleNavigation: true)),
      );
      showAppToast(
        pageContext,
        '通知权限尚未开启',
        duration: const Duration(seconds: 8),
        actionLabel: '去开启',
        onAction: () => actions++,
      );
      await tester.pump();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('app-toast-announcement')))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('app-toast-announcement')))
            .getSemanticsData()
            .label,
        '通知权限尚未开启',
      );
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('去开启'), findsOneWidget);
      await tester.tap(find.text('去开启'));
      await tester.pump();
      expect(actions, 1);
      expect(find.byKey(const ValueKey('app-toast')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('success feedback survives popping its originating route', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    Navigator.of(pageContext).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                showAppToast(context, '补录成功');
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('补录成功'), findsOneWidget);
    expect(find.text('Page'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'disposing an overlay cancels timers and permits fresh feedback',
    (tester) async {
      await tester.pumpWidget(app());
      showAppToast(pageContext, '旧页面');
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(app());
      showAppToast(pageContext, '新页面');
      await tester.pump();
      expect(find.text('新页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  test('all app transient feedback uses the shared centered toast', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              RegExp(r'\b(?:SnackBar|SnackBarAction|showSnackBar)\s*\(')
                  .hasMatch(file.readAsStringSync()),
        )
        .map((file) => file.path);
    expect(offenders, isEmpty);
  });
}
