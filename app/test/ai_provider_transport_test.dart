import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/ai_training_coach.dart';

import 'ai_coach_settings_test.dart' show FakeAiTransport;

void main() {
  test('MiMo maps output budget to documented completion token field', () {
    final body = <String, Object>{'max_tokens': 32000, 'temperature': .2};
    final adjusted = HttpAiCoachTransport.requestBody(
      Uri.parse('https://api.xiaomimimo.com/v1/chat/completions'),
      body,
    );
    expect(adjusted, {'max_completion_tokens': 32000});
    expect(body['max_tokens'], 32000);
    expect(
      HttpAiCoachTransport.requestBody(
        Uri.parse('https://api.xiaomimimo.com/v1/chat/completions'),
        {'max_tokens': 32000, 'max_completion_tokens': 1000},
      ),
      {'max_completion_tokens': 1000},
    );
  });
  test('truncated result is never treated as successful completion', () {
    final raw = jsonEncode({
      'choices': [
        {
          'finish_reason': 'length',
          'message': {'content': 'partial answer'},
        },
      ],
    });
    expect(
      () => HttpAiCoachTransport.parseCompletion(raw),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('Kimi exact official endpoint omits unsupported sampling overrides', () {
    final body = <String, Object>{
      'model': 'kimi-k3',
      'temperature': .2,
      'top_p': .9,
      'max_tokens': 32000,
    };
    final adjusted = HttpAiCoachTransport.requestBody(
      Uri.parse('https://api.moonshot.cn/v1/chat/completions'),
      body,
    );
    expect(adjusted.containsKey('temperature'), isFalse);
    expect(adjusted.containsKey('top_p'), isFalse);
    expect(adjusted['max_tokens'], 32000);
    expect(body['temperature'], .2);
    expect(
      HttpAiCoachTransport.requestBody(
        Uri.parse('https://api.moonshot.cn.evil.invalid/v1/chat/completions'),
        body,
      ),
      body,
    );
    expect(
      HttpAiCoachTransport.requestBody(
        Uri.parse('https://other.invalid/v1/chat/completions'),
        body,
      ),
      body,
    );
  });

  test('MiniMax reasoning prefix removed only on its reviewed endpoint', () {
    final raw = jsonEncode({
      'choices': [
        {
          'message': {
            'content': '<think>private reasoning</think>\n{"plan":1}',
          },
        },
      ],
    });
    expect(
      HttpAiCoachTransport.parseCompletion(
        raw,
        endpoint: Uri.parse('https://api.minimax.cn/v1/chat/completions'),
      ),
      '{"plan":1}',
    );
    expect(HttpAiCoachTransport.parseCompletion(raw), startsWith('<think>'));
    for (final content in ['<think>partial', '<think>thinking only</think>']) {
      expect(
        () => HttpAiCoachTransport.parseCompletion(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
          endpoint: Uri.parse('https://api.minimax.cn/v1/chat/completions'),
        ),
        throwsA(isA<AiCoachException>()),
      );
    }
  });

  test('reasoning-provider test budget not eight tokens and contains no training data', () async {
    final transport = FakeAiTransport();
    await AiTrainingCoach.testConnection(
      endpoint: Uri.parse('https://api.minimax.cn/v1/chat/completions'),
      apiKey: 'fake-key',
      model: 'MiniMax-M3.1-Flash',
      transport: transport,
    );
    expect(transport.body!['max_tokens'], 4096);
    expect(transport.body!['messages'], [
      {'role': 'user', 'content': 'Reply with OK.'},
    ]);
  });
}
