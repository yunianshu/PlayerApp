import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/pages/ai_coach_settings_page.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_training_coach.dart';

import 'ai_coach_settings_test.dart' show FakeCredentials, FakeAiTransport;

class PendingTransport implements AiCoachTransport {
  final response = Completer<String>();
  int requests = 0;
  @override
  Future<String> complete({
    required Uri endpoint,
    required String apiKey,
    required Map<String, Object> body,
  }) {
    requests++;
    return response.future;
  }
}

Future<void> fillSettings(WidgetTester tester) async {
  for (final item in [
    ('ai-endpoint', 'https://example.invalid/v1/chat/completions'),
    ('ai-model', 'test-model'),
    ('ai-key', 'fake-key-for-widget-tests'),
  ]) {
    final field = find.byKey(Key(item.$1));
    await tester.ensureVisible(field);
    await tester.enterText(field, item.$2);
    await tester.pump();
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.scrollUntilVisible(
    target,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'settings starts offline, masks key and saves without contacting API',
    (tester) async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      final transport = FakeAiTransport();
      await tester.pumpWidget(
        MaterialApp(
          home: AiCoachSettingsPage(store: store, transport: transport),
        ),
      );
      await tester.pumpAndSettle();
      expect(transport.requests, 0);
      await fillSettings(tester);
      final editable = find.descendant(
        of: find.byKey(const Key('ai-key')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).obscureText, isTrue);
      await tapText(tester, '保存设置');
      expect((await store.load()).ready, isTrue);
      expect(transport.requests, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'test requires destination confirmation and cancel sends nothing',
    (tester) async {
      final transport = FakeAiTransport();
      await tester.pumpWidget(
        MaterialApp(
          home: AiCoachSettingsPage(
            store: AiCoachSettingsStore(credentials: FakeCredentials()),
            transport: transport,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await fillSettings(tester);
      await tapText(tester, '测试连接');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'https://example.invalid/v1/chat/completions',
          ),
        ),
        findsOneWidget,
      );
      expect(transport.requests, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(transport.requests, 0);
      await tapText(tester, '测试连接');
      await tester.tap(find.text('发送测试'));
      await tester.pumpAndSettle();
      expect(transport.requests, 1);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'endpoint changes require entering a key for the new destination',
    (tester) async {
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      await store.save(
        config: const AiCoachConfig(
          endpoint: 'https://example.invalid/v1/chat/completions',
          model: 'test-model',
        ),
        apiKey: 'fake-old-key',
        persistKey: true,
      );
      final transport = FakeAiTransport();
      await tester.pumpWidget(
        MaterialApp(
          home: AiCoachSettingsPage(store: store, transport: transport),
        ),
      );
      await tester.pumpAndSettle();
      final key = tester.widget<TextFormField>(find.byKey(const Key('ai-key')));
      expect(key.controller!.text, isEmpty);
      await tester.enterText(
        find.byKey(const Key('ai-endpoint')),
        'https://other.invalid/chat',
      );
      await tapText(tester, '测试连接');
      expect(transport.requests, 0);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('ai-key')));
      await tester.pumpAndSettle();
      expect(find.text('请输入 API Key'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'in-flight test disables repeat submit and completing after leaving is safe',
    (tester) async {
      final transport = PendingTransport();
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        AiCoachSettingsPage(store: store, transport: transport),
                  ),
                ),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      await fillSettings(tester);
      await tapText(tester, '测试连接');
      await tester.tap(find.text('发送测试'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(transport.requests, 1);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '测试连接'),
      );
      expect(button.onPressed, isNull);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      transport.response.complete('OK');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('打开设置'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unavailable secure backend makes session-only choice explicit', (
    tester,
  ) async {
    final secure = FakeCredentials()..failRead = true;
    final store = AiCoachSettingsStore(credentials: secure);
    await tester.pumpWidget(
      MaterialApp(home: AiCoachSettingsPage(store: store)),
    );
    await tester.pumpAndSettle();
    await fillSettings(tester);
    await tapText(tester, '保存（密钥仅本次）');
    expect((await store.load()).sessionOnly, isTrue);
    expect(secure.value, isNull);
    expect(
      (await AiCoachSettingsStore(credentials: secure).load()).ready,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'small screen and large text remain scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: AiCoachSettingsPage(
            store: AiCoachSettingsStore(credentials: FakeCredentials()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('清除设置和密钥'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
