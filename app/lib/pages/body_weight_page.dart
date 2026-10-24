import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/body_weight_service.dart';
import '../widgets/ai_plan_design.dart';
import '../widgets/app_toast.dart';

class BodyWeightPage extends StatefulWidget {
  const BodyWeightPage({super.key, this.service, this.now});
  final BodyWeightService? service;
  final DateTime? now;
  @override
  State<BodyWeightPage> createState() => _BodyWeightPageState();
}

class _BodyWeightPageState extends State<BodyWeightPage> {
  BodyWeightService get _service =>
      widget.service ?? BodyWeightService.instance;
  List<BodyWeightRecord> _records = [];
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _service.snapshot();
      if (mounted) {
        setState(() {
          _records = result.records;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '体重记录读取失败，原数据未改动';
        });
      }
    }
  }

  Future<void> _edit([BodyWeightRecord? old]) async {
    final record = await showDialog<BodyWeightRecord>(
      context: context,
      builder: (ctx) => Theme(
        data: PlanDesign.theme(context),
        child: _WeightRecordDialog(
          old: old,
          records: _records,
          now: widget.now,
        ),
      ),
    );
    if (record == null || !mounted) return;
    await _mutate(
      () => _service.save(record, replace: old != null, now: widget.now),
    );
  }

  Future<void> _delete(BodyWeightRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: PlanDesign.theme(context),
        child: AlertDialog(
          title: const Text('删除这条体重记录？'),
          content: Text(
            '${record.date} · ${record.kg.toStringAsFixed(1)} kg\n删除后无法撤销，不会改变训练计划。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (confirm == true && mounted) {
      await _mutate(() => _service.delete(record.date));
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，原记录保持不变，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: PlanDesign.theme(context),
    child: Builder(
      builder: (context) {
        final p = PlanDesign.of(context).palette;
        final recent = _records
            .where(
              (r) =>
                  r.date.compareTo(
                    BodyWeightRecord.dateKey(
                      (widget.now ?? DateTime.now()).subtract(
                        const Duration(days: 89),
                      ),
                    ),
                  ) >=
                  0,
            )
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('体重记录')),
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      '记录变化，不给身体打分。',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '数据默认仅保存在本机。只有主动生成或调整 AI 计划并勾选同意时，才发送最近 28 天的摘要。体重变化不会自动修改训练量。',
                      style: TextStyle(color: p.textSecondary, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null) ...[
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ] else ...[
                      if (_records.isNotEmpty) ...[
                        Text(
                          '${_records.last.kg.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '最近一次 · ${_records.last.date}',
                          style: TextStyle(color: p.textSecondary),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (recent.isNotEmpty) ...[
                        const Text('近 90 天实测记录'),
                        const SizedBox(height: 12),
                        Semantics(
                          label: '体重散点图，横轴为真实日期，未记录的日期留空。完整数值见下方记录列表。',
                          child: SizedBox(
                            height: 150,
                            child: CustomPaint(
                              painter: WeightTrendPainter(
                                recent,
                                p.isEditorial ? p.textPrimary : p.accent,
                                p.stroke,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(recent.first.date),
                            Text(recent.last.date),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '仅显示实测点，不补值、不连线推算缺失日期。',
                          style: TextStyle(color: p.textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 24),
                      ],
                      FilledButton.icon(
                        key: const Key('weight-add'),
                        onPressed: _busy ? null : () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('记录体重'),
                      ),
                      const SizedBox(height: 20),
                      if (_records.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('还没有体重记录，从一次真实测量开始。'),
                        ),
                      for (final record in _records.reversed)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${record.kg.toStringAsFixed(1)} kg'),
                          subtitle: Text(record.date),
                          onTap: _busy ? null : () => _edit(record),
                          trailing: IconButton(
                            tooltip: '删除 ${record.date} 的体重记录',
                            onPressed: _busy ? null : () => _delete(record),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      '体重不是体能或恢复程度的判断标准。如果体重持续无意下降，或伴随不适，请寻求专业评估。',
                      style: TextStyle(color: p.textSecondary, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Scatter plot uses elapsed calendar days, not equally spaced record indexes.
class WeightTrendPainter extends CustomPainter {
  final List<BodyWeightRecord> records;
  final Color color, grid;
  WeightTrendPainter(this.records, this.color, this.grid);
  static double dayPosition(
    BodyWeightRecord record,
    BodyWeightRecord first,
    BodyWeightRecord last,
  ) {
    final start = DateTime.parse(first.date);
    final span = DateTime.parse(last.date).difference(start).inDays;
    return span == 0
        ? .5
        : DateTime.parse(record.date).difference(start).inDays / span;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;
    final low = records.map((r) => r.kg).reduce(math.min);
    final high = records.map((r) => r.kg).reduce(math.max);
    canvas.drawLine(
      Offset(8, size.height - 8),
      Offset(size.width - 8, size.height - 8),
      Paint()..color = grid,
    );
    for (final record in records) {
      final x =
          8 +
          dayPosition(record, records.first, records.last) * (size.width - 16);
      final y = high == low
          ? size.height / 2
          : 8 + (high - record.kg) / (high - low) * (size.height - 24);
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant WeightTrendPainter old) =>
      old.records != records || old.color != color || old.grid != grid;
}

/// Own the controller until the dialog actually unmounts. A timer cannot
/// approximate route lifetime, especially while its exit animation is running.
class _WeightRecordDialog extends StatefulWidget {
  const _WeightRecordDialog({
    required this.old,
    required this.records,
    this.now,
  });
  final BodyWeightRecord? old;
  final List<BodyWeightRecord> records;
  final DateTime? now;
  @override
  State<_WeightRecordDialog> createState() => _WeightRecordDialogState();
}

class _WeightRecordDialogState extends State<_WeightRecordDialog> {
  late String date;
  late final TextEditingController controller;
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    date =
        widget.old?.date ??
        BodyWeightRecord.dateKey(widget.now ?? DateTime.now());
    controller = TextEditingController(text: widget.old?.kg.toString() ?? '');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.old == null ? '记录体重' : '编辑体重'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(date),
              subtitle: Text(widget.old == null ? '选择测量日期' : '日期固定；修改后会替换当天记录'),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: widget.old != null
                  ? null
                  : () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: DateTime.parse(date),
                        firstDate: DateTime(1900),
                        lastDate: widget.now ?? DateTime.now(),
                        builder: (ctx, child) => Theme(
                          data: PlanDesign.theme(context),
                          child: child!,
                        ),
                      );
                      if (chosen != null && mounted) {
                        setState(() => date = BodyWeightRecord.dateKey(chosen));
                      }
                    },
            ),
            TextFormField(
              key: const Key('weight-kg'),
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '体重（kg）',
                helperText: '每天保留一条记录，不设置目标体重',
              ),
              validator: (value) {
                final kg = double.tryParse(value?.trim() ?? '');
                if (kg == null) return '请输入体重（kg）';
                try {
                  BodyWeightRecord(
                    date: date,
                    kg: kg,
                  ).validate(now: widget.now);
                } catch (_) {
                  return '请核对输入，支持 20–500 kg';
                }
                if (widget.old == null &&
                    widget.records.any((r) => r.date == date)) {
                  return '当天已有记录，请取消后编辑当天记录';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              BodyWeightRecord(
                date: date,
                kg: double.parse(controller.text.trim()),
              ),
            );
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
