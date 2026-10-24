import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/body_weight_service.dart';
import 'package:runtrail/services/ai_plan_generator.dart';

import 'ai_plan_creation_page_test.dart' as flow;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('declining weight still generates and excludes weight', (
    tester,
  ) async {
    await BodyWeightService.instance.save(
      const BodyWeightRecord(date: '2026-10-22', kg: 65),
    );
    GenericTrainingRequest? sent;
    await flow.showPage(
      tester,
      generate: (request, _) async {
        sent = request;
        return flow.draft;
      },
    );
    await flow.fill(tester);
    await flow.tapKey(tester, 'plan-generate');
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('weight-ai-consent')))
          .value,
      false,
    );
    await tester.tap(find.text('同意发送并生成'));
    await tester.pumpAndSettle();
    expect(sent, isNotNull);
    expect(sent!.weightSummary, isNull);
  });
  testWidgets('opted-in weight changed during generation invalidates draft', (
    tester,
  ) async {
    await BodyWeightService.instance.save(
      const BodyWeightRecord(date: '2026-10-22', kg: 65),
    );
    final result = Completer<AiPlanDraft>();
    GenericTrainingRequest? sent;
    await flow.showPage(
      tester,
      generate: (request, _) {
        sent = request;
        return result.future;
      },
    );
    await flow.fill(tester);
    await flow.tapKey(tester, 'plan-generate');
    await tester.ensureVisible(find.byKey(const Key('weight-ai-consent')));
    await tester.tap(find.byKey(const Key('weight-ai-consent')));
    await tester.pump();
    await tester.tap(find.text('同意发送并生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(sent!.weightSummary, isNotNull);
    await BodyWeightService.instance.save(
      const BodyWeightRecord(date: '2026-10-22', kg: 64),
      replace: true,
    );
    result.complete(flow.draft);
    await tester.pumpAndSettle();
    expect(find.text('AI 计划预览 · 尚未保存'), findsNothing);
    expect(find.textContaining('体重记录已变化'), findsOneWidget);
  });
  testWidgets('corrupt weight data does not prevent normal generation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      BodyWeightService.storageKey: 'broken',
    });
    var calls = 0;
    await flow.showPage(
      tester,
      generate: (request, _) async {
        calls++;
        expect(request.weightSummary, isNull);
        return flow.draft;
      },
    );
    await flow.fill(tester);
    await flow.tapKey(tester, 'plan-generate');
    expect(find.textContaining('体重记录暂时无法读取'), findsOneWidget);
    await tester.tap(find.text('同意发送并生成'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
