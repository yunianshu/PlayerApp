import 'dart:convert';
import 'dart:io';
import 'adaptive_training_service.dart';

/// Explicit opt-in AI review: the user supplies endpoint and key for this request.
/// No credential or training data is persisted here.
class AiTrainingCoach {
  static Future<String> review({
    required Uri endpoint,
    required String apiKey,
    required String model,
    required Map<String, dynamic> proposal,
  }) async {
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw ArgumentError('必须使用 HTTPS API 地址');
    }
    if (apiKey.trim().isEmpty || model.trim().isEmpty) {
      throw ArgumentError('模型和密钥不能为空');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(endpoint).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'model': model,
        'temperature': 0.2,
        'messages': [
          {
            'role': 'system',
            'content': '你是跑步训练计划审查助手，只解释风险与恢复策略，不诊断疾病。'
                '根据匿名汇总信息用中文回答，禁止要求补跑漏掉的公里数、禁止提高建议跑量。'
                '出现疼痛持续或改变步态时提示暂停训练并寻求专业评估。'
          },
          {
            'role': 'user',
            'content': '请评估这份由本地规则引擎生成的调整方案：${jsonEncode(proposal)}'
          }
        ]
      }));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final body = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) {
        throw HttpException('模型接口返回 HTTP ${resp.statusCode}');
      }
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      final choices = parsed['choices'] as List?;
      if (choices == null || choices.isEmpty) throw const FormatException('模型响应缺少 choices');
      final content = (choices.first as Map)['message']?['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const FormatException('模型响应为空');
      }
      return content.trim();
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> localProposal(
      DateTime now, Map<String, double> actualKm) =>
      AdaptiveTrainingService.suggest(now: now, actualKm: actualKm);
}
