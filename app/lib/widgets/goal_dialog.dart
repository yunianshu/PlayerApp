import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';

class GoalDialog extends StatefulWidget {
  const GoalDialog({
    super.key,
    required this.title,
    required this.current,
    required this.onSave,
  });
  final String title;
  final double current;
  final Future<void> Function(double) onSave;

  @override
  State<GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<GoalDialog> {
  late final _controller = TextEditingController(
    text: Prefs.formatGoal(widget.current),
  );
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    final value = double.tryParse(_controller.text.trim());
    if (value == null || !Prefs.validGoal(value)) {
      setState(() => _error = '请输入 1–1000 之间的有效公里数'.tr);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        enabled: !_saving,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: 'km', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('取消'.tr),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…'.tr : '保存'.tr),
        ),
      ],
    ),
  );
}
