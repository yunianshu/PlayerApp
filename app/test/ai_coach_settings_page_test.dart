import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/pages/ai_coach_settings_page.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_provider_catalog.dart';
import 'package:runtrail/services/ai_training_coach.dart';

import 'ai_coach_settings_test.dart' show FakeCredentials, FakeAiTransport;

const fakeKey = 'fake-key-for-widget-tests-only';

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

class FakeModelTransport implements AiModelTransport {
  int requests = 0;
  Uri? endpoint;
  String? apiKey;
  Completer<AiModelHttpResponse>? pending;

  static AiModelHttpResponse response() => AiModelHttpResponse(
    statusCode: 200,
    body: utf8.encode(
      jsonEncode({
        'data': [
          {'id': 'test-chat-model'},
          {'id': 'second-chat-model'},
          {'id': 'MiniMax-M3.1-Flash'},
        ],
      }),
    ),
  );

  @override
  Future<AiModelHttpResponse> getModels({
    required Uri endpoint,
    required String apiKey,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    requests++;
    this.endpoint = endpoint;
    this.apiKey = apiKey;
    return pending == null ? response() : pending!.future;
  }
}

Finder dropdown(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(prefix),
);

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  await tester.pump();
}

Future<void> tapTarget(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String prefix, String label) async {
  await tapTarget(tester, dropdown(prefix));
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> chooseProvider(WidgetTester tester, String id) =>
    choose(tester, 'ai-provider-', AiProviderCatalog.byId(id)!.label);

Future<void> enterKey(WidgetTester tester, [String key = fakeKey]) async {
  final field = find.byKey(const Key('ai-key'));
  await reveal(tester, field);
  await tester.enterText(field, key);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> fillOfflineSettings(WidgetTester tester) async {
  await chooseProvider(tester, 'qwen');
  await enterKey(tester);
  await tapTarget(tester, find.text('查看官方预置模型'));
  await choose(
    tester,
    'ai-model-',
    AiProviderCatalog.byId('qwen')!.presetModels.first,
  );
}

Future<void> mountSettings(
  WidgetTester tester, {
  AiCoachSettingsStore? store,
  AiCoachTransport? transport,
  FakeModelTransport? models,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AiCoachSettingsPage(
        store: store ?? AiCoachSettingsStore(credentials: FakeCredentials()),
        transport: transport ?? FakeAiTransport(),
        discovery: AiModelDiscoveryService(
          transport: models ?? FakeModelTransport(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('only API key is typed and presets save entirely offline', (
    tester,
  ) async {
    final secure = FakeCredentials();
    final store = AiCoachSettingsStore(credentials: secure);
    final transport = FakeAiTransport();
    final models = FakeModelTransport();
    await mountSettings(
      tester,
      store: store,
      transport: transport,
      models: models,
    );
    expect(transport.requests, 0);
    expect(models.requests, 0);
    expect(find.byType(TextFormField), findsNothing);

    await chooseProvider(tester, 'qwen');
    await enterKey(tester);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byKey(const Key('ai-endpoint')), findsNothing);
    expect(find.byKey(const Key('ai-model')), findsNothing);
    final editable = find.descendant(
      of: find.byKey(const Key('ai-key')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).obscureText, isTrue);
    await tapTarget(tester, find.text('查看官方预置模型'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(models.requests, 0);
    await choose(
      tester,
      'ai-model-',
      AiProviderCatalog.byId('qwen')!.presetModels.first,
    );
    await tapTarget(tester, find.text('保存设置'));
    final saved = await store.load();
    expect(saved.ready, isTrue);
    expect(saved.config!.providerId, 'qwen');
    expect(saved.config!.accessMode, 'standard');
    expect(saved.apiKey, fakeKey);
    expect(models.requests, 0);
    expect(transport.requests, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'model discovery requires destination confirmation and cancel sends nothing',
    (tester) async {
      final transport = FakeAiTransport();
      final models = FakeModelTransport();
      await mountSettings(tester, transport: transport, models: models);
      await chooseProvider(tester, 'deepseek');
      await enterKey(tester);
      expect(models.requests, 0);
      await tapTarget(tester, find.text('获取模型'));
      expect(
        find.textContaining(
          AiProviderCatalog.byId('deepseek')!.modelsEndpoint!,
        ),
        findsOneWidget,
      );
      expect(models.requests, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(models.requests, 0);
      expect(dropdown('ai-model-'), findsNothing);
      await tapTarget(tester, find.text('获取模型'));
      await tester.tap(find.text('同意并获取'));
      await tester.pumpAndSettle();
      expect(models.requests, 1);
      expect(models.apiKey, fakeKey);
      expect(
        models.endpoint.toString(),
        AiProviderCatalog.byId('deepseek')!.modelsEndpoint,
      );
      expect(transport.requests, 0);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await choose(tester, 'ai-model-', 'test-chat-model');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'connection test requires separate confirmation and does not save',
    (tester) async {
      final transport = FakeAiTransport();
      final models = FakeModelTransport();
      await mountSettings(tester, transport: transport, models: models);
      await fillOfflineSettings(tester);
      await tapTarget(tester, find.text('测试连接'));
      expect(
        find.textContaining(AiProviderCatalog.byId('qwen')!.chatEndpoint),
        findsOneWidget,
      );
      expect(transport.requests, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(transport.requests, 0);
      await tapTarget(tester, find.text('测试连接'));
      await tester.tap(find.text('发送测试'));
      await tester.pumpAndSettle();
      expect(transport.requests, 1);
      expect(models.requests, 0);
      expect(transport.apiKey, fakeKey);
      expect(
        transport.body!['model'],
        AiProviderCatalog.byId('qwen')!.presetModels.first,
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('changing provider clears the credential and selected models', (
    tester,
  ) async {
    final transport = FakeAiTransport();
    final models = FakeModelTransport();
    await mountSettings(tester, transport: transport, models: models);
    await fillOfflineSettings(tester);
    await chooseProvider(tester, 'minimax');
    await reveal(tester, find.byKey(const Key('ai-key')));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ai-key')))
          .controller!
          .text,
      isEmpty,
    );
    expect(dropdown('ai-model-'), findsNothing);
    await tapTarget(tester, find.text('测试连接'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(transport.requests, 0);
    expect(models.requests, 0);
    await reveal(tester, find.byKey(const Key('ai-key')));
    expect(find.text('请输入 API Key'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'changing access mode clears typed and saved credentials and models',
    (tester) async {
      final provider = AiProviderCatalog.byId('minimax')!;
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      await store.save(
        config: AiCoachConfig(
          endpoint: provider.chatEndpoint,
          model: 'test-chat-model',
          providerId: provider.id,
        ),
        apiKey: 'fake-saved-standard-key',
        persistKey: true,
      );
      final models = FakeModelTransport();
      final transport = FakeAiTransport();
      await mountSettings(
        tester,
        store: store,
        transport: transport,
        models: models,
      );
      await enterKey(tester, 'fake-replacement-standard-key');
      await tapTarget(tester, find.text('获取模型'));
      await tester.tap(find.text('同意并获取'));
      await tester.pumpAndSettle();
      await choose(tester, 'ai-model-', 'test-chat-model');
      await choose(tester, 'ai-mode-', 'Token Plan / 订阅套餐');
      await reveal(tester, find.byKey(const Key('ai-key')));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('ai-key')))
            .controller!
            .text,
        isEmpty,
      );
      expect(dropdown('ai-model-'), findsNothing);
      await tapTarget(tester, find.text('获取模型'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(models.requests, 1);
      expect(transport.requests, 0);
      await reveal(tester, find.byKey(const Key('ai-key')));
      expect(find.text('请输入 API Key'), findsOneWidget);
      expect((await store.load()).config!.accessMode, 'standard');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('editing API key invalidates its previously selected model', (
    tester,
  ) async {
    final store = AiCoachSettingsStore(credentials: FakeCredentials());
    final transport = FakeAiTransport();
    await mountSettings(tester, store: store, transport: transport);
    await fillOfflineSettings(tester);
    await enterKey(tester, 'fake-other-account-key');
    expect(dropdown('ai-model-'), findsNothing);
    await tapTarget(tester, find.text('保存设置'));
    expect(find.text('请先获取并选择模型'), findsOneWidget);
    expect((await store.load()).ready, isFalse);
    expect(transport.requests, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed secure write never silently saves a session-only key', (
    tester,
  ) async {
    final secure = FakeCredentials()..failWrite = true;
    final store = AiCoachSettingsStore(credentials: secure);
    await mountSettings(tester, store: store);
    await fillOfflineSettings(tester);
    await tapTarget(tester, find.text('保存设置'));
    expect(find.text('安全保存失败，未改为明文保存。请重试或选择仅本次使用密钥。'), findsOneWidget);
    expect((await store.load()).ready, isFalse);
    expect((await store.load()).sessionOnly, isFalse);
    expect(secure.value, isNull);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'stale settings cannot overwrite an externally saved configuration',
    (tester) async {
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      await mountSettings(tester, store: store);
      await fillOfflineSettings(tester);
      final provider = AiProviderCatalog.byId('deepseek')!;
      await store.save(
        config: AiCoachConfig(
          endpoint: provider.chatEndpoint,
          model: 'external-model',
          providerId: provider.id,
        ),
        apiKey: 'fake-external-key',
        persistKey: true,
      );
      await tapTarget(tester, find.text('保存设置'));
      expect(find.text('AI 设置已在其他页面变更，请重新读取后再操作'), findsOneWidget);
      final saved = await store.load();
      expect(saved.config!.providerId, 'deepseek');
      expect(saved.config!.model, 'external-model');
      expect(saved.apiKey, 'fake-external-key');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('supported Token Plan is fetched selected and saved distinctly', (
    tester,
  ) async {
    final store = AiCoachSettingsStore(credentials: FakeCredentials());
    final models = FakeModelTransport();
    await mountSettings(tester, store: store, models: models);
    await chooseProvider(tester, 'minimax');
    await choose(tester, 'ai-mode-', 'Token Plan / 订阅套餐');
    await enterKey(tester, 'fake-plan-key-only');
    await tapTarget(tester, find.text('获取模型'));
    expect(find.textContaining('Token Plan / M Plan'), findsOneWidget);
    await tester.tap(find.text('同意并获取'));
    await tester.pumpAndSettle();
    await choose(tester, 'ai-model-', 'MiniMax-M3.1-Flash');
    await tapTarget(tester, find.text('保存设置'));
    final saved = await store.load();
    expect(saved.ready, isTrue);
    expect(saved.config!.providerId, 'minimax');
    expect(saved.config!.accessMode, 'tokenPlan');
    expect(saved.apiKey, 'fake-plan-key-only');
    expect(models.requests, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unsupported Token Plan cannot send or save', (tester) async {
    final store = AiCoachSettingsStore(credentials: FakeCredentials());
    final models = FakeModelTransport();
    final transport = FakeAiTransport();
    await mountSettings(
      tester,
      store: store,
      models: models,
      transport: transport,
    );
    await chooseProvider(tester, 'deepseek');
    await enterKey(tester);
    await choose(tester, 'ai-mode-', 'Token Plan / 订阅套餐');
    expect(find.text('此接入类型暂不可用于训练助手，请选择标准 API。'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('获取模型'), findsNothing);
    await reveal(tester, find.text('保存设置'));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存设置'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '测试连接'))
          .onPressed,
      isNull,
    );
    expect(models.requests, 0);
    expect(transport.requests, 0);
    expect((await store.load()).ready, isFalse);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'legacy custom destination and model remain read only with saved key',
    (tester) async {
      const legacy = AiCoachConfig(
        endpoint: 'https://example.invalid/v1/chat/completions',
        model: 'legacy-model',
      );
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      await store.save(
        config: legacy,
        apiKey: 'fake-legacy-key',
        persistKey: true,
      );
      final transport = FakeAiTransport();
      final models = FakeModelTransport();
      await mountSettings(
        tester,
        store: store,
        transport: transport,
        models: models,
      );
      expect(find.text('原有自定义配置已保留'), findsOneWidget);
      expect(find.textContaining(legacy.endpoint), findsOneWidget);
      await reveal(tester, find.byKey(const Key('ai-key')));
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('ai-key')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('获取模型'), findsNothing);
      expect(dropdown('ai-model-'), findsNothing);
      await tapTarget(tester, find.text('测试连接'));
      expect(transport.requests, 0);
      await tester.tap(find.text('发送测试'));
      await tester.pumpAndSettle();
      expect(transport.requests, 1);
      expect(transport.endpoint, legacy.uri);
      expect(transport.apiKey, 'fake-legacy-key');
      expect(transport.body!['model'], legacy.model);
      await chooseProvider(tester, 'deepseek');
      expect((await store.load()).config!.endpoint, legacy.endpoint);
      await tapTarget(tester, find.text('获取模型'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(models.requests, 0);
      expect((await store.load()).apiKey, 'fake-legacy-key');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unavailable secure backend makes session-only choice explicit', (
    tester,
  ) async {
    final secure = FakeCredentials()..failRead = true;
    final store = AiCoachSettingsStore(credentials: secure);
    await mountSettings(tester, store: store);
    await fillOfflineSettings(tester);
    await reveal(tester, find.text('保存（密钥仅本次）'));
    expect(find.text('当前安全存储不可用。不会明文保存密钥，可仅本次使用。'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    await tester.tap(find.text('保存（密钥仅本次）'));
    await tester.pumpAndSettle();
    expect((await store.load()).ready, isTrue);
    expect((await store.load()).sessionOnly, isTrue);
    expect(secure.value, isNull);
    expect(
      (await AiCoachSettingsStore(credentials: secure).load()).ready,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pending test disables repeat actions and completing after pop is safe',
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
                    builder: (_) => AiCoachSettingsPage(
                      store: store,
                      transport: transport,
                      discovery: AiModelDiscoveryService(
                        transport: FakeModelTransport(),
                      ),
                    ),
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
      await fillOfflineSettings(tester);
      await tapTarget(tester, find.text('测试连接'));
      await tester.tap(find.text('发送测试'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(transport.requests, 1);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '测试连接'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存设置'))
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byKey(const Key('ai-key')));
      expect(
        tester.widget<TextFormField>(find.byKey(const Key('ai-key'))).enabled,
        isFalse,
      );
      await reveal(tester, dropdown('ai-provider-'));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(dropdown('ai-provider-'))
            .onChanged,
        isNull,
      );
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

  testWidgets(
    'external changes before confirmation prevent any network request',
    (tester) async {
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      final transport = FakeAiTransport();
      await mountSettings(tester, store: store, transport: transport);
      await fillOfflineSettings(tester);
      await tapTarget(tester, find.text('测试连接'));
      final provider = AiProviderCatalog.byId('deepseek')!;
      await store.save(
        config: AiCoachConfig(
          endpoint: provider.chatEndpoint,
          model: 'new-model',
          providerId: provider.id,
        ),
        apiKey: 'fake-external-key',
        persistKey: true,
      );
      await tester.tap(find.text('发送测试'));
      await tester.pumpAndSettle();
      expect(transport.requests, 0);
      expect(find.text('AI 设置已在其他页面变更，请重新读取后再操作'), findsOneWidget);
      expect((await store.load()).apiKey, 'fake-external-key');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('external changes while fetching reject stale model results', (
    tester,
  ) async {
    final store = AiCoachSettingsStore(credentials: FakeCredentials());
    final models = FakeModelTransport()
      ..pending = Completer<AiModelHttpResponse>();
    await mountSettings(tester, store: store, models: models);
    await chooseProvider(tester, 'deepseek');
    await enterKey(tester);
    await tapTarget(tester, find.text('获取模型'));
    await tester.tap(find.text('同意并获取'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(models.requests, 1);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '获取模型'))
          .onPressed,
      isNull,
    );
    final provider = AiProviderCatalog.byId('qwen')!;
    await store.save(
      config: AiCoachConfig(
        endpoint: provider.chatEndpoint,
        model: provider.presetModels.first,
        providerId: provider.id,
      ),
      apiKey: 'fake-external-key',
      persistKey: true,
    );
    models.pending!.complete(FakeModelTransport.response());
    await tester.pumpAndSettle();
    expect(dropdown('ai-model-'), findsNothing);
    await reveal(tester, find.text('AI 设置已在其他页面变更，请重新读取后再操作'));
    expect(find.text('AI 设置已在其他页面变更，请重新读取后再操作'), findsOneWidget);
    expect((await store.load()).apiKey, 'fake-external-key');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '320px screen at 200 percent text stays scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = AiProviderCatalog.byId('qwen')!;
      final store = AiCoachSettingsStore(credentials: FakeCredentials());
      await store.save(
        config: AiCoachConfig(
          endpoint: provider.chatEndpoint,
          model: provider.presetModels.first,
          providerId: provider.id,
        ),
        apiKey: fakeKey,
        persistKey: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AiCoachSettingsPage(
            store: store,
            transport: FakeAiTransport(),
            discovery: AiModelDiscoveryService(transport: FakeModelTransport()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await reveal(tester, find.text('清除设置和密钥'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
