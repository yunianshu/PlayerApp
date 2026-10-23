import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'adaptive_training_service.dart';
import 'ai_coach_settings.dart';

class AiCoachException implements Exception {
  final String message;
  const AiCoachException(this.message);
  @override
  String toString() => message;
}

/// Injectable transport: tests use fake responses and never a real API key.
abstract class AiCoachTransport {
  Future<String> complete({
    required Uri endpoint,
    required String apiKey,
    required Map<String, Object> body,
  });
}

class HttpAiCoachTransport implements AiCoachTransport {
  const HttpAiCoachTransport();

  @override
  Future<String> complete({
    required Uri endpoint,
    required String apiKey,
    required Map<String, Object> body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      // Bound the whole request, including a response that never finishes.
      return await _send(
        client,
        endpoint,
        apiKey,
        body,
      ).timeout(const Duration(seconds: 40));
    } on AiCoachException {
      rethrow;
    } on TimeoutException {
      throw const AiCoachException('连接超时，请检查网络或服务地址后重试');
    } on SocketException {
      throw const AiCoachException('无法连接模型服务，请检查网络或服务地址');
    } on HandshakeException {
      throw const AiCoachException('HTTPS 安全连接失败，请检查服务证书');
    } catch (_) {
      // Never surface raw URLs, headers, server bodies or credentials in errors.
      throw const AiCoachException('模型响应无效，请检查接口兼容性与模型名称');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _send(
    HttpClient client,
    Uri endpoint,
    String apiKey,
    Map<String, Object> body,
  ) async {
    final req = await client.postUrl(endpoint);
    // Do not forward a credential to a redirect destination, even same-host.
    req.followRedirects = false;
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(requestBody(endpoint, body)));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw AiCoachException(httpErrorMessage(resp.statusCode));
    }
    final bytes = <int>[];
    await for (final chunk in resp) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const AiCoachException('模型响应过大，请重试');
      }
      bytes.addAll(chunk);
    }
    return parseCompletion(utf8.decode(bytes), endpoint: endpoint);
  }

  static String httpErrorMessage(int status) {
    if (status == 401 || status == 403) return '认证失败，请检查 API Key、模型权限和套餐是否有效';
    if (status == 404) return '接口或模型不存在，请检查完整 API 地址与模型名称';
    if (status == 429) return '请求受限或额度不足，请检查服务商账户后重试';
    if (status >= 300 && status < 400) return '接口返回重定向，已阻止转发密钥，请填写最终 HTTPS 地址';
    if (status >= 500) return '模型服务暂时不可用，请稍后重试';
    return '模型接口返回 HTTP $status，请检查服务设置';
  }

  /// Kimi's current models reject sampling overrides (official models-overview).
  /// Match the complete reviewed destination, never a look-alike host.
  static Map<String, Object> requestBody(
    Uri endpoint,
    Map<String, Object> body,
  ) {
    final result = Map<String, Object>.from(body);
    if (endpoint.toString() == 'https://api.moonshot.cn/v1/chat/completions') {
      result.remove('temperature');
      result.remove('top_p');
    }
    if (endpoint.toString() ==
        'https://api.xiaomimimo.com/v1/chat/completions') {
      // MiMo documents max_completion_tokens, which includes reasoning tokens.
      final budget = result.remove('max_tokens');
      if (budget != null) {
        result.putIfAbsent('max_completion_tokens', () => budget);
      }
      result.remove('temperature');
      result.remove('top_p');
    }
    return result;
  }

  static String parseCompletion(String body, {Uri? endpoint}) {
    final parsed = jsonDecode(body);
    final choices = parsed is Map ? parsed['choices'] : null;
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiCoachException('模型响应缺少有效 choices');
    }
    if ((choices.first as Map)['finish_reason'] == 'length') {
      throw const AiCoachException('模型输出达到长度上限，未获得完整结果，请重试或选择其他模型');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AiCoachException('模型响应内容为空');
    }
    var answer = content.trim();
    if (endpoint?.toString() == 'https://api.minimax.cn/v1/chat/completions') {
      // MiniMax documents a leading reasoning block in OpenAI content. Never
      // expose it as the plan, and never repair a partial/truncated answer.
      answer = answer
          .replaceFirst(RegExp(r'^<think>[\s\S]*?</think>\s*'), '')
          .trim();
      if (answer.isEmpty || answer.startsWith('<think>')) {
        throw const AiCoachException('模型仅返回思考内容或输出被截断，请重试');
      }
    }
    return answer;
  }
}

/// Explicit opt-in AI requests only. No credential or training data is logged.
class AiTrainingCoach {
  static void _validate(Uri endpoint, String apiKey, String model) {
    final error =
        AiCoachConfig.endpointError(endpoint.toString()) ??
        AiCoachConfig.modelError(model) ??
        AiCoachConfig.keyError(apiKey);
    if (error != null) throw AiCoachException(error);
  }

  /// Called only by the settings page's confirmed test action. Sends no runs,
  /// scores, dates, GPS tracks or other training information.
  static Future<void> testConnection({
    required Uri endpoint,
    required String apiKey,
    required String model,
    AiCoachTransport transport = const HttpAiCoachTransport(),
  }) async {
    _validate(endpoint, apiKey, model);
    await transport.complete(
      endpoint: endpoint,
      apiKey: apiKey,
      body: {
        'model': model,
        'max_tokens':
            const {
              'api.deepseek.com',
              'api.moonshot.cn',
              'api.minimax.cn',
              'open.bigmodel.cn',
              'dashscope.aliyuncs.com',
              'api.xiaomimimo.com',
            }.contains(endpoint.host)
            ? 4096
            : 8,
        'messages': [
          {'role': 'user', 'content': 'Reply with OK.'},
        ],
      },
    );
  }

  static Future<String> review({
    required Uri endpoint,
    required String apiKey,
    required String model,
    required Map<String, dynamic> proposal,
    AiCoachTransport transport = const HttpAiCoachTransport(),
  }) async {
    _validate(endpoint, apiKey, model);
    return transport.complete(
      endpoint: endpoint,
      apiKey: apiKey,
      body: {
        'model': model,
        'temperature': 0.2,
        'messages': [
          {
            'role': 'system',
            'content':
                '你是跑步训练计划审查助手，只解释风险与恢复策略，不诊断疾病。'
                '根据匿名汇总信息用中文回答，禁止要求补跑漏掉的公里数、禁止提高建议跑量。'
                '出现疼痛持续或改变步态时提示暂停训练并寻求专业评估。',
          },
          {
            'role': 'user',
            'content': '请评估这份由本地规则引擎生成的调整方案：${jsonEncode(proposal)}',
          },
        ],
      },
    );
  }

  static Future<Map<String, dynamic>?> localProposal(
    DateTime now,
    Map<String, double> actualKm,
  ) => AdaptiveTrainingService.suggest(now: now, actualKm: actualKm);
}
