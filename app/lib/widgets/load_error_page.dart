import 'package:flutter/material.dart';

import '../core/i18n.dart';

class LoadErrorPage extends StatelessWidget {
  const LoadErrorPage({
    super.key,
    required this.onRetry,
    this.showBack = false,
  });
  final VoidCallback onRetry;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showBack
        ? AppBar(title: Text('跑步详情'.tr))
        : null,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32),
              const SizedBox(height: 12),
              Text('数据加载失败，请重试'.tr),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: Text('重试'.tr),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
