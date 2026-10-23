import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_training_coach.dart';
import 'package:runtrail/services/backup_service.dart';

class FakeCredentials implements AiCredentialStore {
  String? value;
  bool failWrite = false;
  bool failRead = false;
  bool failDelete = false;
  @override
  Future<String?> read() async {
    if (failRead) throw PlatformException(code: 'unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw PlatformException(code: 'unavailable');
    this.value = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw PlatformException(code: 'unavailable');
    value = null;
  }
}

class FakeAiTransport implements AiCoachTransport {
  int requests = 0;
  Uri? endpoint;
  String? apiKey;
  Map<String, Object>? body;
  @override
  Future<String> complete({
    required Uri endpoint,
    required String apiKey,
    required Map<String, Object> body,
  }) async {
    requests++;
    this.endpoint = endpoint;
    this.apiKey = apiKey;
    this.body = body;
    return 'OK';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = AiCoachConfig(
    endpoint: 'https://example.invalid/v1/chat/completions',
    model: 'test-model',
  );
  const fakeKey = 'fake-key-for-tests-only';
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'persists metadata and secure credential separately, excludes backup',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      await store.save(config: config, apiKey: fakeKey, persistKey: true);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AiCoachSettingsStore.preferencesKey),
        isNot(contains(fakeKey)),
      );
      expect(prefs.getKeys(), {AiCoachSettingsStore.preferencesKey});
      expect(jsonEncode(BackupService.build([], {})), isNot(contains(fakeKey)));
      expect(
        jsonEncode(BackupService.build([], {})),
        isNot(contains(config.endpoint)),
      );
      final restored = await AiCoachSettingsStore(credentials: secure).load();
      expect(restored.ready, isTrue);
      expect(restored.apiKey, fakeKey);
      expect(restored.config!.model, config.model);
      expect(restored.sessionOnly, isFalse);
    },
  );

  test(
    'explicit session mode does not persist a key and clears an old key',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      await store.save(config: config, apiKey: fakeKey, persistKey: true);
      await store.save(config: config, apiKey: fakeKey, persistKey: false);
      expect(secure.value, isNull);
      final active = await store.load();
      expect(active.ready, isTrue);
      expect(active.sessionOnly, isTrue);
      expect(
        (await AiCoachSettingsStore(credentials: secure).load()).ready,
        isFalse,
      );
    },
  );

  test(
    'secure write failure never falls back to plaintext or session silently',
    () async {
      final secure = FakeCredentials()..failWrite = true;
      final store = AiCoachSettingsStore(credentials: secure);
      await expectLater(
        store.save(config: config, apiKey: fakeKey, persistKey: true),
        throwsA(isA<AiSettingsException>()),
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect((await store.load()).ready, isFalse);
    },
  );

  test(
    'secure read error is surfaced as unavailable, not as a saved key',
    () async {
      final secure = FakeCredentials()..failRead = true;
      final settings = await AiCoachSettingsStore(credentials: secure).load();
      expect(settings.secureStorageAvailable, isFalse);
      expect(settings.ready, isFalse);
    },
  );

  test(
    'restored metadata cannot send an existing key to a different endpoint',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      await store.save(config: config, apiKey: fakeKey, persistKey: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AiCoachSettingsStore.preferencesKey,
        jsonEncode({
          'endpoint': 'https://different.invalid/v1/chat/completions',
          'model': config.model,
        }),
      );
      final restored = await store.load();
      expect(restored.ready, isFalse);
      expect(restored.apiKey, isNull);
    },
  );

  test(
    'clears secure and ordinary settings without touching training data',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('training_feedback_v1', 'keep');
      await store.save(config: config, apiKey: fakeKey, persistKey: true);
      await store.clear();
      expect(secure.value, isNull);
      expect(prefs.getString(AiCoachSettingsStore.preferencesKey), isNull);
      expect(prefs.getString('training_feedback_v1'), 'keep');
    },
  );

  test(
    'cannot claim session-only or cleared when secure deletion failed',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      await store.save(config: config, apiKey: fakeKey, persistKey: true);
      secure.failDelete = true;
      await expectLater(
        store.save(config: config, apiKey: fakeKey, persistKey: false),
        throwsA(isA<AiSettingsException>()),
      );
      await expectLater(store.clear(), throwsA(isA<AiSettingsException>()));
      expect(secure.value, isNotNull);
    },
  );

  test(
    'secure envelope is bounded by Harmony Asset Store 1024-byte limit',
    () async {
      final secure = FakeCredentials();
      final store = AiCoachSettingsStore(credentials: secure);
      await expectLater(
        store.save(
          config: config,
          apiKey: List.filled(600, '密').join(),
          persistKey: true,
        ),
        throwsA(isA<AiSettingsException>()),
      );
      expect(secure.value, isNull);
    },
  );

  test(
    'validates HTTPS and rejects credential-bearing URLs and header injection',
    () {
      for (final endpoint in [
        'http://example.invalid/chat',
        'not a url',
        'https://user:pass@example.invalid/chat',
        'https://example.invalid/chat?key=secret',
        'https://example.invalid/chat#fragment',
      ]) {
        expect(AiCoachConfig.endpointError(endpoint), isNotNull);
      }
      expect(AiCoachConfig.endpointError(config.endpoint), isNull);
      expect(AiCoachConfig.keyError('fake\nheader'), isNotNull);
      expect(AiCoachConfig.modelError(' '), isNotNull);
    },
  );

  test(
    'connection test uses only explicit endpoint, key, model and fixed text',
    () async {
      final transport = FakeAiTransport();
      await AiTrainingCoach.testConnection(
        endpoint: config.uri,
        apiKey: fakeKey,
        model: config.model,
        transport: transport,
      );
      expect(transport.requests, 1);
      expect(transport.endpoint, config.uri);
      expect(transport.apiKey, fakeKey);
      expect(transport.body!['model'], config.model);
      expect(transport.body!['messages'], [
        {'role': 'user', 'content': 'Reply with OK.'},
      ]);
      expect(jsonEncode(transport.body), isNot(contains(fakeKey)));
    },
  );

  test(
    'invalid configuration is rejected before transport is invoked',
    () async {
      final transport = FakeAiTransport();
      await expectLater(
        AiTrainingCoach.testConnection(
          endpoint: Uri.parse('http://example.invalid'),
          apiKey: fakeKey,
          model: config.model,
          transport: transport,
        ),
        throwsA(isA<AiCoachException>()),
      );
      expect(transport.requests, 0);
    },
  );

  test('parses compatible completion and gives sanitized status messages', () {
    expect(
      HttpAiCoachTransport.parseCompletion(
        '{"choices":[{"message":{"content":" OK "}}]}',
      ),
      'OK',
    );
    expect(
      () => HttpAiCoachTransport.parseCompletion('{"choices":[]}'),
      throwsA(isA<AiCoachException>()),
    );
    expect(HttpAiCoachTransport.httpErrorMessage(401), contains('认证失败'));
    expect(HttpAiCoachTransport.httpErrorMessage(429), contains('额度'));
    expect(HttpAiCoachTransport.httpErrorMessage(302), contains('阻止转发密钥'));
  });
}
