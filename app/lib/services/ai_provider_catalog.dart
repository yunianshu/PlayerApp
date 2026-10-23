import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A reviewed, fixed destination. Neither restored settings nor API responses
/// can add an endpoint to this catalog or redirect a credential elsewhere.
class AiProvider {
  final String id;
  final String label;
  final String chatEndpoint;
  final String? modelsEndpoint;
  final List<String> presetModels;
  final String docsUrl;
  final String tokenPlanNote;
  final bool supportsTokenPlan;
  final List<String> tokenPlanModels;

  const AiProvider._({
    required this.id,
    required this.label,
    required this.chatEndpoint,
    required this.modelsEndpoint,
    required this.presetModels,
    required this.docsUrl,
    required this.tokenPlanNote,
    this.supportsTokenPlan = false,
    this.tokenPlanModels = const [],
  });

  List<String> presetModelsFor(String accessMode) => accessMode == 'standard'
      ? presetModels
      : accessMode == 'tokenPlan' && supportsTokenPlan
      ? tokenPlanModels
      : const [];
}

/// Official provider documentation reviewed on 2026-10-23. Presets are
/// suggestions, not a claim that a particular account can access a model.
abstract final class AiProviderCatalog {
  static const providers = <AiProvider>[
    AiProvider._(
      id: 'deepseek',
      label: 'DeepSeek',
      chatEndpoint: 'https://api.deepseek.com/chat/completions',
      modelsEndpoint: 'https://api.deepseek.com/models',
      presetModels: ['deepseek-flash', 'deepseek-v4-pro'],
      docsUrl: 'https://api-docs.deepseek.com/',
      tokenPlanNote: '使用 DeepSeek 开放平台 API Key；暂未提供已核实的 Token Plan 接入方式。',
    ),
    AiProvider._(
      id: 'qwen',
      label: '通义千问 · 百炼（北京）',
      // Aliyun explicitly continues to support this legacy Beijing domain.
      // The newer model-list API needs a workspace ID, not just an API key:
      // https://help.aliyun.com/zh/model-studio/list-models
      chatEndpoint:
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      modelsEndpoint: null,
      presetModels: ['qwen3.8-max'],
      docsUrl: 'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope',
      tokenPlanNote: '使用北京地域的普通 API Key。Coding Plan 不用于本应用的跑步计划生成。',
    ),
    AiProvider._(
      id: 'glm',
      label: '智谱 GLM',
      chatEndpoint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      modelsEndpoint: null,
      presetModels: ['glm-5.3', 'glm-5.3-flash', 'glm-5.2'],
      docsUrl: 'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction',
      tokenPlanNote: '使用智谱开放平台普通 API Key。GLM Coding Plan 不用于本应用。',
    ),
    AiProvider._(
      id: 'kimi',
      label: 'Kimi · 月之暗面',
      chatEndpoint: 'https://api.moonshot.cn/v1/chat/completions',
      modelsEndpoint: 'https://api.moonshot.cn/v1/models',
      presetModels: ['kimi-k3'],
      docsUrl: 'https://platform.kimi.com/docs/api/overview',
      tokenPlanNote: '使用开放平台普通 API Key；Kimi Code 仅用于指定编程工具，不用于本应用。',
    ),
    AiProvider._(
      id: 'mimo',
      label: '小米 MiMo',
      chatEndpoint: 'https://api.xiaomimimo.com/v1/chat/completions',
      modelsEndpoint: 'https://api.xiaomimimo.com/v1/models',
      presetModels: ['mimo-v2.6-pro', 'mimo-v2.6-flash'],
      docsUrl:
          'https://mimo.mi.com/docs/zh-CN/quick-start/summary/first-api-call',
      tokenPlanNote: '使用普通 API Key；MiMo Token Plan 仅用于编程场景，不用于本应用。',
    ),
    AiProvider._(
      id: 'minimax',
      label: 'MiniMax',
      chatEndpoint: 'https://api.minimax.cn/v1/chat/completions',
      // https://platform.minimax.cn/docs/api-reference/models/openai/list-models
      modelsEndpoint: 'https://api.minimax.cn/v1/models',
      presetModels: ['MiniMax-M3.1-Flash', 'MiniMax-M3'],
      docsUrl: 'https://platform.minimax.cn/docs/api-reference/text-openai-api',
      // https://platform.minimax.cn/docs/m-plan/other-tools
      tokenPlanNote: 'M Plan / Token Plan 仅用于个人开发者交互式调用，生产服务建议使用普通 API。套餐使用专用 Key 和支持的模型，不会自动切换为普通 API 计费。',
      supportsTokenPlan: true,
      tokenPlanModels: ['MiniMax-M3.1-Flash'],
    ),
  ];

  static AiProvider? byId(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  static AiProvider? forEndpoint(String endpoint) {
    for (final provider in providers) {
      if (provider.chatEndpoint == endpoint) return provider;
    }
    return null;
  }

  static bool _allowsModelsEndpoint(Uri endpoint) =>
      endpoint.scheme == 'https' &&
      endpoint.userInfo.isEmpty &&
      !endpoint.hasQuery &&
      !endpoint.hasFragment &&
      providers.any(
        (provider) => provider.modelsEndpoint == endpoint.toString(),
      );
}

class AiModelDiscoveryResult {
  final List<String> models;
  final bool live;
  final String note;

  AiModelDiscoveryResult({
    required List<String> models,
    required this.live,
    required this.note,
  }) : models = List.unmodifiable(models);
}

enum AiModelDiscoveryCode {
  invalidKey,
  unauthorized,
  forbidden,
  rateLimited,
  notSupported,
  redirectBlocked,
  invalidResponse,
  emptyResponse,
  responseTooLarge,
  timeout,
  network,
  server,
}

/// Only fixed messages reach the UI. Never include a response body, request
/// header, URL supplied by the server, or underlying exception in an error.
class AiModelDiscoveryException implements Exception {
  final AiModelDiscoveryCode code;
  const AiModelDiscoveryException(this.code);

  String get message => switch (code) {
    AiModelDiscoveryCode.invalidKey => '请输入有效的 API Key，不能包含空格、换行或控制字符。',
    AiModelDiscoveryCode.unauthorized => 'API Key 无效或已过期，请检查所选平台及接入方式。',
    AiModelDiscoveryCode.forbidden => '当前 API Key 没有获取模型的权限，请检查平台账户权限。',
    AiModelDiscoveryCode.rateLimited => '请求过于频繁或当前额度受限，请稍后再试。',
    AiModelDiscoveryCode.notSupported => '该平台暂不支持仅凭 API Key 自动获取模型。',
    AiModelDiscoveryCode.redirectBlocked => '平台返回了重定向，为保护 API Key 已停止请求。',
    AiModelDiscoveryCode.invalidResponse => '模型列表格式无效，请稍后重试。',
    AiModelDiscoveryCode.emptyResponse => '平台没有返回可用的文本对话模型，请检查账户权限。',
    AiModelDiscoveryCode.responseTooLarge => '模型列表超过安全大小限制，已停止读取。',
    AiModelDiscoveryCode.timeout => '获取模型超时，请检查网络后重试。',
    AiModelDiscoveryCode.network => '无法连接模型平台，请检查网络后重试。',
    AiModelDiscoveryCode.server => '模型平台暂时无法提供列表，请稍后重试。',
  };

  @override
  String toString() => message;
}

class AiModelHttpResponse {
  final int statusCode;
  final List<int> body;

  AiModelHttpResponse({required this.statusCode, required List<int> body})
    : body = List.unmodifiable(body);
}

/// Fake this boundary in tests; no real credentials or network are needed.
abstract class AiModelTransport {
  Future<AiModelHttpResponse> getModels({
    required Uri endpoint,
    required String apiKey,
    required Duration timeout,
    required int maxResponseBytes,
  });
}

class IoAiModelTransport implements AiModelTransport {
  final HttpClient Function() _clientFactory;

  IoAiModelTransport({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  @override
  Future<AiModelHttpResponse> getModels({
    required Uri endpoint,
    required String apiKey,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    if (!AiProviderCatalog._allowsModelsEndpoint(endpoint)) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.notSupported);
    }
    _validateKey(apiKey);
    final client = _clientFactory();
    try {
      client.connectionTimeout = timeout;
      // The deadline covers connection, headers and the entire streamed body.
      return await (() async {
        final request = await client.getUrl(endpoint);
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.persistentConnection = false;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          // Error responses may echo credentials. Do not retain their bodies.
          return AiModelHttpResponse(statusCode: response.statusCode, body: []);
        }
        if (response.contentLength > maxResponseBytes) {
          throw const AiModelDiscoveryException(
            AiModelDiscoveryCode.responseTooLarge,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (chunk.length > maxResponseBytes - bytes.length) {
            throw const AiModelDiscoveryException(
              AiModelDiscoveryCode.responseTooLarge,
            );
          }
          bytes.addAll(chunk);
        }
        return AiModelHttpResponse(
          statusCode: response.statusCode,
          body: bytes,
        );
      })().timeout(timeout);
    } on AiModelDiscoveryException {
      rethrow;
    } on TimeoutException {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.timeout);
    } catch (_) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.network);
    } finally {
      client.close(force: true);
    }
  }
}

void _validateKey(String apiKey) {
  if (apiKey.isEmpty ||
      apiKey.length > 4096 ||
      apiKey.codeUnits.any((unit) => unit <= 32 || unit >= 127)) {
    throw const AiModelDiscoveryException(AiModelDiscoveryCode.invalidKey);
  }
}

class AiModelDiscoveryService {
  static const maxResponseBytes = 512 * 1024;
  static const maxModels = 500;
  static const maxModelIdLength = 200;
  static final _modelId = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._:/-]*$');
  static final _nonChatId = RegExp(
    r'(^|[-_/])(asr|tts|embedding|embeddings|rerank|reranker)([-_/]|$)',
    caseSensitive: false,
  );

  final AiModelTransport transport;
  final Duration timeout;

  AiModelDiscoveryService({
    AiModelTransport? transport,
    this.timeout = const Duration(seconds: 15),
  }) : transport = transport ?? IoAiModelTransport();

  Future<AiModelDiscoveryResult> discover({
    required String providerId,
    required String apiKey,
    String accessMode = 'standard',
  }) async {
    final provider = AiProviderCatalog.byId(providerId);
    if (provider == null) {
      return AiModelDiscoveryResult(
        models: const [],
        live: false,
        note: '未识别的平台，未发送 API Key。请重新选择平台。',
      );
    }
    if (accessMode != 'standard' &&
        (accessMode != 'tokenPlan' || !provider.supportsTokenPlan)) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.notSupported);
    }
    final key = apiKey.trim();
    // Reject CR/LF even at the edges rather than silently fixing header input.
    if (apiKey.contains('\r') || apiKey.contains('\n')) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.invalidKey);
    }
    _validateKey(key);
    final modelsEndpoint = provider.modelsEndpoint;
    if (modelsEndpoint == null) return _presets(provider, accessMode);
    final endpoint = Uri.parse(modelsEndpoint);
    if (!AiProviderCatalog._allowsModelsEndpoint(endpoint)) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.notSupported);
    }
    AiModelHttpResponse response;
    try {
      response = await transport
          .getModels(
            endpoint: endpoint,
            apiKey: key,
            timeout: timeout,
            maxResponseBytes: maxResponseBytes,
          )
          .timeout(timeout);
    } on AiModelDiscoveryException {
      rethrow;
    } on TimeoutException {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.timeout);
    } catch (_) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.network);
    }
    switch (response.statusCode) {
      case HttpStatus.ok:
        break;
      case HttpStatus.unauthorized:
        throw const AiModelDiscoveryException(
          AiModelDiscoveryCode.unauthorized,
        );
      case HttpStatus.forbidden:
        throw const AiModelDiscoveryException(AiModelDiscoveryCode.forbidden);
      case HttpStatus.tooManyRequests:
        throw const AiModelDiscoveryException(AiModelDiscoveryCode.rateLimited);
      case HttpStatus.notFound:
      case HttpStatus.methodNotAllowed:
      case HttpStatus.notImplemented:
        return _presets(provider, accessMode);
      default:
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const AiModelDiscoveryException(
            AiModelDiscoveryCode.redirectBlocked,
          );
        }
        throw const AiModelDiscoveryException(AiModelDiscoveryCode.server);
    }
    if (response.body.length > maxResponseBytes) {
      throw const AiModelDiscoveryException(
        AiModelDiscoveryCode.responseTooLarge,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.body));
    } catch (_) {
      throw const AiModelDiscoveryException(
        AiModelDiscoveryCode.invalidResponse,
      );
    }
    if (decoded is! Map || decoded['data'] is! List) {
      throw const AiModelDiscoveryException(
        AiModelDiscoveryCode.invalidResponse,
      );
    }
    final models = <String>{};
    for (final entry in decoded['data'] as List) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String ||
          id.isEmpty ||
          id.length > maxModelIdLength ||
          !_modelId.hasMatch(id) ||
          _nonChatId.hasMatch(id) ||
          id.contains(key) ||
          (accessMode == 'tokenPlan' &&
              !provider.tokenPlanModels.contains(id)) ||
          !_supportsText(entry)) {
        continue;
      }
      models.add(id);
      if (models.length == maxModels) break;
    }
    if (models.isEmpty) {
      throw const AiModelDiscoveryException(AiModelDiscoveryCode.emptyResponse);
    }
    return AiModelDiscoveryResult(
      models: models.toList(),
      live: true,
      note: '已从平台获取模型；实际调用权限与额度以当前 API Key 为准。',
    );
  }

  static AiModelDiscoveryResult _presets(
    AiProvider provider,
    String accessMode,
  ) => AiModelDiscoveryResult(
    models: provider.presetModelsFor(accessMode),
    live: false,
    note: '该平台暂不支持仅凭 API Key 获取模型，显示官方预设列表；尚未验证密钥或模型权限。',
  );

  static bool _supportsText(Map entry) {
    final architecture = entry['architecture'];
    for (final metadata in [entry, if (architecture is Map) architecture]) {
      for (final field in [
        'input_modalities',
        'output_modalities',
        'modalities',
      ]) {
        if (!metadata.containsKey(field)) continue;
        final modalities = metadata[field];
        if (modalities is! List || !modalities.contains('text')) return false;
      }
    }
    // Some providers also explicitly identify embedding, reranking or media
    // models, even when they do not provide modality arrays.
    const nonChatTasks = {
      'embedding',
      'embeddings',
      'rerank',
      'reranking',
      'text-to-speech',
      'speech-to-text',
      'image-generation',
      'video-generation',
    };
    return !nonChatTasks.contains(entry['type']) &&
        !nonChatTasks.contains(entry['task']);
  }
}
