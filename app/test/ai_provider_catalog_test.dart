import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/ai_provider_catalog.dart';

const _testKey = 'fake-api-key-for-unit-tests';

AiModelHttpResponse _response(Object? data, {int status = 200}) =>
    AiModelHttpResponse(
      statusCode: status,
      body: utf8.encode(jsonEncode(data)),
    );

class FakeModelTransport implements AiModelTransport {
  AiModelHttpResponse response;
  Object? failure;
  Future<AiModelHttpResponse>? pending;
  int calls = 0;
  Uri? endpoint;
  String? key;
  Duration? timeout;
  int? maxBytes;

  FakeModelTransport({AiModelHttpResponse? response})
    : response =
          response ??
          _response({
            'data': [
              {'id': 'test-model'},
            ],
          });

  @override
  Future<AiModelHttpResponse> getModels({
    required Uri endpoint,
    required String apiKey,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    calls++;
    this.endpoint = endpoint;
    key = apiKey;
    this.timeout = timeout;
    maxBytes = maxResponseBytes;
    if (failure != null) throw failure!;
    return pending ?? response;
  }
}

class FakeHeaders implements HttpHeaders {
  final values = <String, Object>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  final Stream<List<int>> chunks;
  @override
  final int statusCode;
  @override
  final int contentLength;
  bool listened = false;

  FakeResponse({
    List<List<int>> chunks = const [],
    this.statusCode = 200,
    this.contentLength = -1,
  }) : chunks = Stream.fromIterable(chunks);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listened = true;
    return chunks.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  final FakeHeaders headers = FakeHeaders();
  final FakeResponse response;

  FakeRequest(this.response);

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClient implements HttpClient {
  final FakeRequest request;
  Future<HttpClientRequest>? pending;
  Uri? uri;
  bool closed = false;
  bool? forced;
  @override
  Duration? connectionTimeout;

  FakeHttpClient(this.request);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    return pending ?? request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    forced = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher _error(AiModelDiscoveryCode code) => isA<AiModelDiscoveryException>()
    .having((error) => error.code, 'code', code)
    .having(
      (error) => error.message,
      'sanitized message',
      isNot(contains(_testKey)),
    )
    .having(
      (error) => error.toString(),
      'sanitized string',
      isNot(contains(_testKey)),
    );

void main() {
  group('catalog', () {
    test('contains fixed domestic official HTTPS destinations', () {
      expect(AiProviderCatalog.providers.map((provider) => provider.id), [
        'deepseek',
        'qwen',
        'glm',
        'kimi',
        'mimo',
        'minimax',
      ]);
      for (final provider in AiProviderCatalog.providers) {
        expect(AiProviderCatalog.byId(provider.id), same(provider));
        expect(
          AiProviderCatalog.forEndpoint(provider.chatEndpoint),
          same(provider),
        );
        for (final address in [
          provider.chatEndpoint,
          provider.docsUrl,
          if (provider.modelsEndpoint != null) provider.modelsEndpoint!,
        ]) {
          final uri = Uri.parse(address);
          expect(uri.scheme, 'https');
          expect(uri.userInfo, isEmpty);
          expect(uri.hasQuery, isFalse);
          expect(uri.hasFragment, isFalse);
        }
      }
    });

    test('catalog and preset lists cannot be mutated', () {
      expect(() => AiProviderCatalog.providers.clear(), throwsUnsupportedError);
      for (final provider in AiProviderCatalog.providers) {
        expect(
          () => provider.presetModels.add('injected'),
          throwsUnsupportedError,
        );
        expect(
          () => provider.tokenPlanModels.add('injected'),
          throwsUnsupportedError,
        );
      }
    });

    test('lookup does not accept endpoint aliases or host suffix attacks', () {
      expect(AiProviderCatalog.byId('DeepSeek'), isNull);
      expect(
        AiProviderCatalog.forEndpoint(
          'https://api.deepseek.com.evil.invalid/chat/completions',
        ),
        isNull,
      );
      expect(
        AiProviderCatalog.forEndpoint(
          'http://api.deepseek.com/chat/completions',
        ),
        isNull,
      );
      expect(
        AiProviderCatalog.forEndpoint(
          'https://api.deepseek.com/chat/completions?key=anything',
        ),
        isNull,
      );
    });

    test(
      'only reviewed MiniMax plan is enabled, with an explicit model subset',
      () {
        expect(
          AiProviderCatalog.providers
              .where((p) => p.supportsTokenPlan)
              .map((p) => p.id),
          ['minimax'],
        );
        expect(
          AiProviderCatalog.byId('minimax')!.presetModelsFor('tokenPlan'),
          ['MiniMax-M3.1-Flash'],
        );
        expect(
          AiProviderCatalog.byId('qwen')!.presetModelsFor('tokenPlan'),
          isEmpty,
        );
        expect(
          AiProviderCatalog.byId('minimax')!.presetModelsFor('unknown'),
          isEmpty,
        );
      },
    );
  });

  group('model discovery', () {
    test(
      'requests exact endpoint with trimmed key and bounded settings',
      () async {
        final transport = FakeModelTransport(
          response: _response({
            'data': [
              {'id': 'deepseek-flash'},
              {'id': 'deepseek-v4-pro'},
              {'id': 'deepseek-flash'},
            ],
          }),
        );
        final result = await AiModelDiscoveryService(transport: transport)
            .discover(providerId: 'deepseek', apiKey: '  $_testKey  ');
        expect(result.models, ['deepseek-flash', 'deepseek-v4-pro']);
        expect(result.live, isTrue);
        expect(result.note, contains('平台获取'));
        expect(
          transport.endpoint.toString(),
          'https://api.deepseek.com/models',
        );
        expect(transport.key, _testKey);
        expect(transport.timeout, const Duration(seconds: 15));
        expect(transport.maxBytes, AiModelDiscoveryService.maxResponseBytes);
        expect(transport.calls, 1);
        expect(() => result.models.add('mutate'), throwsUnsupportedError);
      },
    );

    for (final id in ['minimax', 'kimi', 'mimo']) {
      test('$id uses its own fixed model-list destination', () async {
        final transport = FakeModelTransport();
        await AiModelDiscoveryService(transport: transport)
            .discover(providerId: id, apiKey: _testKey);
        expect(
          transport.endpoint.toString(),
          AiProviderCatalog.byId(id)!.modelsEndpoint,
        );
      });
    }

    test('unknown provider never transmits a credential', () async {
      final transport = FakeModelTransport();
      final result = await AiModelDiscoveryService(transport: transport)
          .discover(
            providerId: 'https://unreviewed.invalid/models',
            apiKey: _testKey,
          );
      expect(result.models, isEmpty);
      expect(result.live, isFalse);
      expect(result.note, contains('未发送'));
      expect(transport.calls, 0);
    });

    for (final id in ['qwen', 'glm']) {
      test(
        '$id deliberately returns presets without claiming authentication',
        () async {
          final transport = FakeModelTransport();
          final result = await AiModelDiscoveryService(transport: transport)
              .discover(providerId: id, apiKey: _testKey);
          expect(result.models, AiProviderCatalog.byId(id)!.presetModels);
          expect(result.live, isFalse);
          expect(result.note, contains('尚未验证'));
          expect(transport.calls, 0);
        },
      );
    }

    for (final key in [
      '',
      '   ',
      'a b',
      'a\nb',
      'a\rb',
      '\n$_testKey',
      'a\tb',
      'a\u0000b',
      'a\u007fb',
      '密钥',
      'x' * 4097,
    ]) {
      test(
        'rejects invalid key ${key.length} characters without network',
        () async {
          final transport = FakeModelTransport();
          await expectLater(
            AiModelDiscoveryService(transport: transport)
                .discover(providerId: 'deepseek', apiKey: key),
            throwsA(_error(AiModelDiscoveryCode.invalidKey)),
          );
          expect(transport.calls, 0);
        },
      );
    }

    for (final entry in {
      401: AiModelDiscoveryCode.unauthorized,
      403: AiModelDiscoveryCode.forbidden,
      429: AiModelDiscoveryCode.rateLimited,
      301: AiModelDiscoveryCode.redirectBlocked,
      302: AiModelDiscoveryCode.redirectBlocked,
      307: AiModelDiscoveryCode.redirectBlocked,
      308: AiModelDiscoveryCode.redirectBlocked,
      400: AiModelDiscoveryCode.server,
      500: AiModelDiscoveryCode.server,
    }.entries) {
      test(
        'maps HTTP ${entry.key} without displaying server text or key',
        () async {
          final transport = FakeModelTransport(
            response: _response({'error': _testKey}, status: entry.key),
          );
          await expectLater(
            AiModelDiscoveryService(transport: transport)
                .discover(providerId: 'deepseek', apiKey: _testKey),
            throwsA(_error(entry.value)),
          );
          expect(transport.calls, 1);
        },
      );
    }

    for (final status in [404, 405, 501]) {
      test(
        'HTTP $status gives explicitly labeled, unverified presets',
        () async {
          final transport = FakeModelTransport(
            response: _response({'error': _testKey}, status: status),
          );
          final result = await AiModelDiscoveryService(transport: transport)
              .discover(providerId: 'deepseek', apiKey: _testKey);
          expect(
            result.models,
            AiProviderCatalog.byId('deepseek')!.presetModels,
          );
          expect(result.live, isFalse);
          expect(result.note, contains('预设'));
          expect(result.note, isNot(contains(_testKey)));
        },
      );
    }

    test('filters unsafe, duplicate and incompatible model IDs', () async {
      final transport = FakeModelTransport(
        response: _response({
          'data': [
            {'id': 'Vendor/model-1.2:latest'},
            {'id': 'plain-model'},
            {'id': 'plain-model'},
            {
              'id': 'multimodal',
              'input_modalities': ['text', 'image'],
              'output_modalities': ['text'],
            },
            {
              'id': 'vision-only',
              'input_modalities': ['image'],
            },
            {
              'id': 'tts',
              'output_modalities': ['audio'],
            },
            {'id': 'malformed-modality', 'modalities': 'text'},
            {'id': 'empty-modality', 'modalities': []},
            {
              'id': 'nested-audio',
              'architecture': {
                'output_modalities': ['audio'],
              },
            },
            {'id': 'embedding', 'type': 'embedding'},
            {'id': 'ranking', 'task': 'rerank'},
            {'id': 'bad\nname'},
            {'id': 'trailing-newline\n'},
            {'id': ' white-space'},
            {'id': '<script>'},
            {'id': 'a?key=value'},
            {'id': ''},
            {'id': _testKey},
            {'id': 'prefix-$_testKey-suffix'},
            {'id': 'a' * (AiModelDiscoveryService.maxModelIdLength + 1)},
            {'id': 12},
            {},
            null,
            'not-an-object',
          ],
        }),
      );
      final result = await AiModelDiscoveryService(transport: transport)
          .discover(providerId: 'deepseek', apiKey: _testKey);
      expect(result.models, [
        'Vendor/model-1.2:latest',
        'plain-model',
        'multimodal',
      ]);
    });

    test('bounds the number of accepted model IDs', () async {
      final transport = FakeModelTransport(
        response: _response({
          'data': List.generate(
            AiModelDiscoveryService.maxModels + 20,
            (i) => {'id': 'model-$i'},
          ),
        }),
      );
      final result = await AiModelDiscoveryService(transport: transport)
          .discover(providerId: 'deepseek', apiKey: _testKey);
      expect(result.models.length, AiModelDiscoveryService.maxModels);
      expect(result.models.first, 'model-0');
    });

    test(
      'MiMo excludes ASR and TTS even when modality metadata is absent',
      () async {
        final transport = FakeModelTransport(
          response: _response({
            'data': [
              {'id': 'mimo-v2.5-asr'},
              {'id': 'mimo-v2.5-tts'},
              {'id': 'mimo-v2.5-tts-voiceclone'},
              {'id': 'mimo-v2.6-flash'},
              {'id': 'mimo-v2.6-pro'},
            ],
          }),
        );
        final result = await AiModelDiscoveryService(transport: transport)
            .discover(providerId: 'mimo', apiKey: _testKey);
        expect(result.models, ['mimo-v2.6-flash', 'mimo-v2.6-pro']);
      },
    );

    test('unknown access mode is rejected without transmission', () async {
      final transport = FakeModelTransport();
      await expectLater(
        AiModelDiscoveryService(transport: transport).discover(
          providerId: 'minimax',
          apiKey: _testKey,
          accessMode: 'unverified-plan',
        ),
        throwsA(_error(AiModelDiscoveryCode.notSupported)),
      );
      expect(transport.calls, 0);
    });

    for (final body in [
      'not-json $_testKey',
      '[]',
      '{}',
      '{"data":null}',
      '{"data":{}}',
    ]) {
      test('rejects malformed response ${body.length}', () async {
        final transport = FakeModelTransport(
          response: AiModelHttpResponse(
            statusCode: 200,
            body: utf8.encode(body),
          ),
        );
        await expectLater(
          AiModelDiscoveryService(transport: transport)
              .discover(providerId: 'deepseek', apiKey: _testKey),
          throwsA(_error(AiModelDiscoveryCode.invalidResponse)),
        );
      });
    }

    test('rejects invalid UTF-8', () async {
      final transport = FakeModelTransport(
        response: AiModelHttpResponse(statusCode: 200, body: [0xff]),
      );
      await expectLater(
        AiModelDiscoveryService(transport: transport)
            .discover(providerId: 'deepseek', apiKey: _testKey),
        throwsA(_error(AiModelDiscoveryCode.invalidResponse)),
      );
    });

    for (final data in [
      [],
      [
        {'id': '\n'},
      ],
      [
        {
          'id': 'audio',
          'output_modalities': ['audio'],
        },
      ],
    ]) {
      test('empty usable list remains an error, not fake success', () async {
        final transport = FakeModelTransport(
          response: _response({'data': data}),
        );
        await expectLater(
          AiModelDiscoveryService(transport: transport)
              .discover(providerId: 'deepseek', apiKey: _testKey),
          throwsA(_error(AiModelDiscoveryCode.emptyResponse)),
        );
      });
    }

    test(
      'checks byte bound even when an injected transport ignores it',
      () async {
        final transport = FakeModelTransport(
          response: AiModelHttpResponse(
            statusCode: 200,
            body: List.filled(AiModelDiscoveryService.maxResponseBytes + 1, 32),
          ),
        );
        await expectLater(
          AiModelDiscoveryService(transport: transport)
              .discover(providerId: 'deepseek', apiKey: _testKey),
          throwsA(_error(AiModelDiscoveryCode.responseTooLarge)),
        );
      },
    );

    test(
      'sanitizes transport failures and enforces a service deadline',
      () async {
        final transport = FakeModelTransport()
          ..failure = Exception('secret $_testKey');
        await expectLater(
          AiModelDiscoveryService(transport: transport)
              .discover(providerId: 'deepseek', apiKey: _testKey),
          throwsA(_error(AiModelDiscoveryCode.network)),
        );
        transport.failure = null;
        transport.pending = Completer<AiModelHttpResponse>().future;
        await expectLater(
          AiModelDiscoveryService(
            transport: transport,
            timeout: const Duration(milliseconds: 2),
          ).discover(providerId: 'deepseek', apiKey: _testKey),
          throwsA(_error(AiModelDiscoveryCode.timeout)),
        );
      },
    );

    test('Token Plan lists only the reviewed MiniMax model subset', () async {
      final transport = FakeModelTransport(
        response: _response({
          'data': [
            {'id': 'MiniMax-M3'},
            {'id': 'MiniMax-M3.1-Flash'},
            {'id': 'MiniMax-M2.7'},
          ],
        }),
      );
      final result = await AiModelDiscoveryService(transport: transport)
          .discover(
            providerId: 'minimax',
            apiKey: _testKey,
            accessMode: 'tokenPlan',
          );
      expect(result.live, isTrue);
      expect(result.models, ['MiniMax-M3.1-Flash']);
      expect(transport.calls, 1);
    });

    test('Token Plan fallback does not include ordinary API models', () async {
      final transport = FakeModelTransport(
        response: _response({}, status: 404),
      );
      final result = await AiModelDiscoveryService(transport: transport)
          .discover(
            providerId: 'minimax',
            apiKey: _testKey,
            accessMode: 'tokenPlan',
          );
      expect(result.live, isFalse);
      expect(result.models, ['MiniMax-M3.1-Flash']);
    });

    test('Token Plan never silently falls back to standard after no matching models', () async {
      final transport = FakeModelTransport(
        response: _response({
          'data': [
            {'id': 'MiniMax-M3'},
          ],
        }),
      );
      await expectLater(
        AiModelDiscoveryService(transport: transport).discover(
          providerId: 'minimax',
          apiKey: _testKey,
          accessMode: 'tokenPlan',
        ),
        throwsA(_error(AiModelDiscoveryCode.emptyResponse)),
      );
      expect(transport.calls, 1);
    });

    for (final id in ['deepseek', 'qwen', 'glm', 'kimi', 'mimo']) {
      test('$id refuses unapproved Token Plan before network', () async {
        final transport = FakeModelTransport();
        await expectLater(
          AiModelDiscoveryService(
            transport: transport,
          ).discover(providerId: id, apiKey: _testKey, accessMode: 'tokenPlan'),
          throwsA(_error(AiModelDiscoveryCode.notSupported)),
        );
        expect(transport.calls, 0);
      });
    }
  });

  group('production HTTP transport with fake sockets', () {
    Future<AiModelHttpResponse> send(
      FakeHttpClient client, {
      int limit = 32,
      Duration timeout = const Duration(seconds: 1),
      Uri? endpoint,
    }) => IoAiModelTransport(clientFactory: () => client).getModels(
      endpoint: endpoint ?? Uri.parse('https://api.deepseek.com/models'),
      apiKey: _testKey,
      timeout: timeout,
      maxResponseBytes: limit,
    );

    test(
      'uses Bearer only at fixed HTTPS endpoint and disables every redirect',
      () async {
        final request = FakeRequest(
          FakeResponse(
            chunks: [
              [1, 2],
              [3],
            ],
          ),
        );
        final client = FakeHttpClient(request);
        final response = await send(client);
        expect(response.body, [1, 2, 3]);
        expect(
          request.headers.values[HttpHeaders.authorizationHeader],
          'Bearer $_testKey',
        );
        expect(
          request.headers.values[HttpHeaders.acceptHeader],
          'application/json',
        );
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.persistentConnection, isFalse);
        expect(client.closed, isTrue);
        expect(client.forced, isTrue);
      },
    );

    for (final url in [
      'http://api.deepseek.com/models',
      'https://api.deepseek.com.evil.invalid/models',
      'https://api.deepseek.com/models?secret=anything',
      'https://user:password@api.deepseek.com/models',
      'https://api.deepseek.com/models#fragment',
      'https://api.deepseek.com/other',
    ]) {
      test(
        'refuses unreviewed destination $url before creating a client',
        () async {
          var created = false;
          final transport = IoAiModelTransport(
            clientFactory: () {
              created = true;
              return FakeHttpClient(FakeRequest(FakeResponse()));
            },
          );
          await expectLater(
            transport.getModels(
              endpoint: Uri.parse(url),
              apiKey: _testKey,
              timeout: const Duration(seconds: 1),
              maxResponseBytes: 32,
            ),
            throwsA(_error(AiModelDiscoveryCode.notSupported)),
          );
          expect(created, isFalse);
        },
      );
    }

    test('does not retain or read error response bodies', () async {
      final raw = FakeResponse(
        statusCode: 302,
        chunks: [utf8.encode(_testKey)],
      );
      final client = FakeHttpClient(FakeRequest(raw));
      final result = await send(client);
      expect(result.statusCode, 302);
      expect(result.body, isEmpty);
      expect(raw.listened, isFalse);
      expect(client.closed, isTrue);
    });

    test('rejects declared oversized payload before reading it', () async {
      final raw = FakeResponse(contentLength: 33);
      final client = FakeHttpClient(FakeRequest(raw));
      await expectLater(
        send(client),
        throwsA(_error(AiModelDiscoveryCode.responseTooLarge)),
      );
      expect(raw.listened, isFalse);
      expect(client.closed, isTrue);
    });

    test('enforces streamed byte bound and closes connection', () async {
      final client = FakeHttpClient(
        FakeRequest(
          FakeResponse(chunks: [List.filled(20, 32), List.filled(13, 32)]),
        ),
      );
      await expectLater(
        send(client),
        throwsA(_error(AiModelDiscoveryCode.responseTooLarge)),
      );
      expect(client.closed, isTrue);
    });

    test('timeout closes the underlying client rather than leaving a request alive', () async {
      final client = FakeHttpClient(FakeRequest(FakeResponse()))
        ..pending = Completer<HttpClientRequest>().future;
      await expectLater(
        send(client, timeout: const Duration(milliseconds: 2)),
        throwsA(_error(AiModelDiscoveryCode.timeout)),
      );
      expect(client.closed, isTrue);
      expect(client.forced, isTrue);
    });
  });
}
