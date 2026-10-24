import 'package:flutter/material.dart';

import '../services/body_weight_service.dart';

/// A fresh, unchecked choice per request. Caller discloses the named provider
/// and all other data in the same dialog; declining weight never blocks AI.
class WeightAiConsent extends StatelessWidget {
  const WeightAiConsent({
    super.key,
    required this.summary,
    required this.selected,
    required this.onChanged,
    this.unavailable = false,
  });
  final BodyWeightSummary? summary;
  final bool unavailable;
  final bool selected;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => summary == null
      ? Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            unavailable ? '体重记录暂时无法读取，本次不发送体重，仍可继续生成。' : '不发送体重：最近 28 天没有测量记录。',
          ),
        )
      : CheckboxListTile(
          key: const Key('weight-ai-consent'),
          contentPadding: EdgeInsets.zero,
          value: selected,
          onChanged: (value) => onChanged(value ?? false),
          title: const Text('本次同意向上述服务发送体重摘要（可选）'),
          subtitle: Text(
            '${summary!.disclosure}\n属于个人健康相关信息；不用于减重建议或单凭体重加量。不勾选仍可生成计划。',
          ),
        );
}
