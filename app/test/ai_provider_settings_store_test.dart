import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_provider_catalog.dart';

import 'ai_coach_settings_test.dart' show FakeCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fakeKey = 'fake-provider-key-only';
  final provider = AiProviderCatalog.byId('minimax')!;
  final config = AiCoachConfig(
    endpoint: provider.chatEndpoint,
    model: provider.tokenPlanModels.first,
    providerId: provider.id,
    accessMode: 'tokenPlan',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final qwen = AiProviderCatalog.byId('qwen')!;
  final invalidConfigurations = <String, AiCoachConfig>{
    'known provider with a nonofficial host': AiCoachConfig(
      endpoint: 'https://other.invalid/v1/chat/completions',
      model: provider.presetModels.first,
      providerId: provider.id,
    ),
    'unknown provider ID': AiCoachConfig(
      endpoint: provider.chatEndpoint,
      model: provider.presetModels.first,
      providerId: 'unknown-platform',
    ),
    'Token Plan on a restricted platform': AiCoachConfig(
      endpoint: qwen.chatEndpoint,
      model: qwen.presetModels.first,
      providerId: qwen.id,
      accessMode: 'tokenPlan',
    ),
    'MiniMax Token Plan with a non-plan model': AiCoachConfig(
      endpoint: provider.chatEndpoint,
      model: 'MiniMax-M3',
      providerId: provider.id,
      accessMode: 'tokenPlan',
    ),
  };

  for (final scenario in invalidConfigurations.entries) {
    test(
      'rejects ${scenario.key} on save and restored metadata load',
      () async {
        final secure = FakeCredentials();
        final store = AiCoachSettingsStore(credentials: secure);
        await store.save(config: config, apiKey: fakeKey, persistKey: true);
        final prefs = await SharedPreferences.getInstance();
        final originalMetadata = prefs.getString(
          AiCoachSettingsStore.preferencesKey,
        );
        final originalCredential = secure.value;

        await expectLater(
          store.save(
            config: scenario.value,
            apiKey: 'fake-rejected-key',
            persistKey: true,
          ),
          throwsA(isA<AiSettingsException>()),
        );
        expect(secure.value, originalCredential);
        expect(
          prefs.getString(AiCoachSettingsStore.preferencesKey),
          originalMetadata,
        );

        // Even matching tampered metadata and credential bindings must not turn
        // an invalid provider destination or plan/model into a ready setting.
        final invalid = scenario.value;
        await prefs.setString(
          AiCoachSettingsStore.preferencesKey,
          jsonEncode({
            'endpoint': invalid.endpoint,
            'model': invalid.model,
            'providerId': invalid.providerId,
            'accessMode': invalid.accessMode,
          }),
        );
        secure.value = jsonEncode({
          'endpoint': invalid.endpoint,
          'providerId': invalid.providerId,
          'accessMode': invalid.accessMode,
          'apiKey': fakeKey,
        });
        final restored = await AiCoachSettingsStore(credentials: secure).load();
        expect(restored.config, isNull);
        expect(restored.apiKey, isNull);
        expect(restored.ready, isFalse);
      },
    );
  }

  test('provider and mode persist in metadata and secure binding, never plaintext key', () async {
    final secure = FakeCredentials();
    await AiCoachSettingsStore(credentials: secure)
        .save(config: config, apiKey: fakeKey, persistKey: true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AiCoachSettingsStore.preferencesKey)!;
    final metadata = jsonDecode(raw) as Map<String, dynamic>;
    final envelope = jsonDecode(secure.value!) as Map<String, dynamic>;
    expect(metadata['providerId'], 'minimax');
    expect(metadata['accessMode'], 'tokenPlan');
    expect(metadata['endpoint'], provider.chatEndpoint);
    expect(metadata['model'], config.model);
    expect(raw, isNot(contains(fakeKey)));
    expect(envelope['providerId'], 'minimax');
    expect(envelope['accessMode'], 'tokenPlan');
    expect(envelope['endpoint'], provider.chatEndpoint);
    expect(envelope['apiKey'], fakeKey);
    final restored = await AiCoachSettingsStore(credentials: secure).load();
    expect(restored.ready, isTrue);
    expect(restored.config!.providerId, 'minimax');
    expect(restored.config!.accessMode, 'tokenPlan');
    expect(restored.apiKey, fakeKey);
  });

  test(
    'legacy endpoint-only metadata and envelope remain load compatible',
    () async {
      const endpoint = 'https://legacy.invalid/v1/chat/completions';
      SharedPreferences.setMockInitialValues({
        AiCoachSettingsStore.preferencesKey: jsonEncode({
          'endpoint': endpoint,
          'model': 'legacy-model',
        }),
      });
      final secure = FakeCredentials()
        ..value = jsonEncode({'endpoint': endpoint, 'apiKey': fakeKey});
      final restored = await AiCoachSettingsStore(credentials: secure).load();
      expect(restored.ready, isTrue);
      expect(restored.config!.providerId, isNull);
      expect(restored.config!.accessMode, 'standard');
      expect(restored.config!.endpoint, endpoint);
      expect(restored.config!.model, 'legacy-model');
      expect(restored.apiKey, fakeKey);
    },
  );

  test(
    'legacy official destination is not silently assigned a provider',
    () async {
      SharedPreferences.setMockInitialValues({
        AiCoachSettingsStore.preferencesKey: jsonEncode({
          'endpoint': provider.chatEndpoint,
          'model': provider.presetModels.first,
        }),
      });
      final secure = FakeCredentials()
        ..value = jsonEncode({
          'endpoint': provider.chatEndpoint,
          'apiKey': fakeKey,
        });
      final restored = await AiCoachSettingsStore(credentials: secure).load();
      expect(restored.ready, isTrue);
      expect(restored.config!.providerId, isNull);
      expect(restored.config!.accessMode, 'standard');
    },
  );

  for (final mutation in <String, Object?>{
    'providerId': 'deepseek',
    'accessMode': 'standard',
    'endpoint': 'https://other.invalid/v1/chat/completions',
  }.entries) {
    test(
      '${mutation.key} mismatch with the secure envelope denies key reuse',
      () async {
        final secure = FakeCredentials();
        await AiCoachSettingsStore(credentials: secure)
            .save(config: config, apiKey: fakeKey, persistKey: true);
        final prefs = await SharedPreferences.getInstance();
        final metadata = jsonDecode(
          prefs.getString(AiCoachSettingsStore.preferencesKey)!,
        ) as Map<String, dynamic>;
        metadata[mutation.key] = mutation.value;
        await prefs.setString(
          AiCoachSettingsStore.preferencesKey,
          jsonEncode(metadata),
        );
        final restored = await AiCoachSettingsStore(credentials: secure).load();
        expect(restored.ready, isFalse);
        expect(restored.apiKey, isNull);
        expect(secure.value, contains(fakeKey));
      },
    );
  }

  test(
    'stripping new binding fields cannot downgrade a saved plan credential',
    () async {
      final secure = FakeCredentials();
      await AiCoachSettingsStore(credentials: secure)
          .save(config: config, apiKey: fakeKey, persistKey: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AiCoachSettingsStore.preferencesKey,
        jsonEncode({'endpoint': config.endpoint, 'model': config.model}),
      );
      final restored = await AiCoachSettingsStore(credentials: secure).load();
      expect(restored.apiKey, isNull);
      expect(restored.ready, isFalse);
    },
  );

  test(
    'legacy envelope cannot be rebound to a newly labeled provider',
    () async {
      SharedPreferences.setMockInitialValues({
        AiCoachSettingsStore.preferencesKey: jsonEncode({
          'endpoint': provider.chatEndpoint,
          'model': provider.presetModels.first,
          'providerId': provider.id,
          'accessMode': 'standard',
        }),
      });
      final secure = FakeCredentials()
        ..value = jsonEncode({
          'endpoint': provider.chatEndpoint,
          'apiKey': fakeKey,
        });
      final restored = await AiCoachSettingsStore(credentials: secure).load();
      expect(restored.ready, isFalse);
      expect(restored.apiKey, isNull);
    },
  );

  test(
    'session-only plan credentials retain binding and disappear in a new store',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      await store.save(config: config, apiKey: fakeKey, persistKey: false);
      expect(secure.value, isNull);
      final active = await store.load();
      expect(active.ready, isTrue);
      expect(active.sessionOnly, isTrue);
      expect(active.config!.providerId, 'minimax');
      expect(active.config!.accessMode, 'tokenPlan');
      expect(
        (await AiCoachSettingsStore(credentials: secure).load()).ready,
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      final metadata = jsonDecode(
        prefs.getString(AiCoachSettingsStore.preferencesKey)!,
      ) as Map<String, dynamic>;
      metadata['accessMode'] = 'standard';
      await prefs.setString(
        AiCoachSettingsStore.preferencesKey,
        jsonEncode(metadata),
      );
      expect((await store.load()).apiKey, isNull);
    },
  );
}
