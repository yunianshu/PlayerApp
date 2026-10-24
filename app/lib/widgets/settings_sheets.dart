import 'dart:async';

import 'package:flutter/material.dart';

import 'app_toast.dart';

import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../services/diagnostics.dart';
import '../services/tts_service.dart';
import '../services/tracking_policies.dart';

/// 语音播报设置：总开关 + 播报内容（距离/用时/配速）。
Future<void> showVoiceSettingsDialog(BuildContext context) async {
  final c = context.readColors;
  var enabled = Prefs.instance.voiceEnabled;
  var distance = Prefs.instance.voiceDistance;
  var time = Prefs.instance.voiceTime;
  var pace = Prefs.instance.voicePace;
  var interval = Prefs.instance.voiceIntervalM;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '语音播报'.tr,
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              // ignore: deprecated_member_use
              activeColor: c.accent,
              title: Text(
                '每公里播报距离、用时与配速'.tr,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
              onChanged: (v) => setState(() => enabled = v),
            ),
            if (enabled) ...[
              _toggle(
                c,
                '距离'.tr,
                distance,
                (v) => setState(() => distance = v),
              ),
              _toggle(c, '用时'.tr, time, (v) => setState(() => time = v)),
              _toggle(c, '平均配速'.tr, pace, (v) => setState(() => pace = v)),
              const SizedBox(height: 6),
              Text(
                '播报间隔'.tr,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 500,
                    label: Text(
                      '500米'.tr,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  ButtonSegment(
                    value: 1000,
                    label: Text('1公里'.tr, style: const TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 2000,
                    label: Text('2公里'.tr, style: const TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {interval},
                onSelectionChanged: (s) => setState(() => interval = s.first),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  Icons.play_circle_outline,
                  size: 20,
                  color: c.accent,
                ),
                title: Text(
                  '试听'.tr,
                  style: TextStyle(fontSize: 13, color: c.textPrimary),
                ),
                subtitle: Text(
                  '立刻验证语音是否正常'.tr,
                  style: TextStyle(fontSize: 10, color: c.textMuted),
                ),
                onTap: () async {
                  final spoken = await TtsService.speak(
                    '语音播报正常，3、2、1，开始跑步！'.tr,
                    flush: true,
                  );
                  if (!spoken && ctx.mounted) {
                    showAppToast(ctx, TtsService.failureMessage);
                  }
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消'.tr, style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('保存'.tr, style: TextStyle(color: c.actionForeground)),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    await Prefs.instance.setVoice(
      enabled: enabled,
      distance: distance,
      time: time,
      pace: pace,
    );
    if (interval != Prefs.instance.voiceIntervalM) {
      await Prefs.instance.setVoiceInterval(interval);
    }
    if (enabled) {
      unawaited(TtsService.ensureInitialized());
    } else {
      unawaited(TtsService.stop());
    }
  }
}

/// 目标配速提醒设置：启用开关 + 目标配速（m:ss /公里）。
Future<void> showPaceTargetDialog(BuildContext context) async {
  final c = context.readColors;
  final current = Prefs.instance.paceTargetSecPerKm;
  var enabled = current > 0;
  final ctrl = TextEditingController(
    text: current > 0 ? formatPaceInput(current) : '6:00',
  );
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '配速提醒'.tr,
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              // ignore: deprecated_member_use
              activeColor: c.accent,
              title: Text(
                '当前目标配速'.tr,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
              onChanged: (v) => setState(() => enabled = v),
            ),
            if (enabled) ...[
              Text(
                '每分钟秒数或 分:秒，如 5:30'.tr,
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.text,
                style: TextStyle(fontSize: 15, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: '5:30',
                  hintStyle: TextStyle(fontSize: 13, color: c.textMuted),
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(fontSize: 12, color: c.danger)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消'.tr, style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              if (!enabled) {
                await Prefs.instance.setPaceTarget(0);
                if (ctx.mounted) Navigator.pop(ctx, true);
                return;
              }
              final pace = parsePaceInput(ctrl.text);
              if (pace == null) {
                setState(() => error = '格式无效，请输入如 5:30'.tr);
                return;
              }
              if (!Prefs.validPace(pace)) {
                setState(() => error = '目标配速需在 1:00 – 30:00 /公里 之间'.tr);
                return;
              }
              try {
                await Prefs.instance.setPaceTarget(pace);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on Object {
                setState(() => error = '保存目标失败'.tr);
              }
            },
            child: Text('保存'.tr, style: TextStyle(color: c.actionForeground)),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    unawaited(TtsService.ensureInitialized());
  }
}

/// 应用语言设置。
Future<void> showLanguageDialog(BuildContext context) async {
  final c = context.readColors;
  final current = LocaleController.instance.pref;
  final picked = await showDialog<AppLanguage>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        '语言'.tr,
        style: TextStyle(fontSize: 17, color: c.textPrimary),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (lang, label) in [
            (AppLanguage.system, '跟随系统'.tr),
            (AppLanguage.zh, '中文'.tr),
            (AppLanguage.en, 'English'),
          ])
            ListTile(
              leading: current == lang
                  ? Icon(Icons.check_circle, size: 20, color: c.accent)
                  : Icon(
                      Icons.radio_button_unchecked,
                      size: 20,
                      color: c.textMuted,
                    ),
              title: Text(
                label,
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
              onTap: () => Navigator.pop(ctx, lang),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('取消'.tr, style: TextStyle(color: c.textSecondary)),
        ),
      ],
    ),
  );
  if (picked != null) await LocaleController.instance.set(picked);
}

/// 诊断日志查看（未捕获异常本地落盘，无网络上传）。
Future<void> showDiagnosticsDialog(BuildContext context) async {
  final c = context.readColors;
  final log = await Diagnostics.readRecent();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        '诊断日志'.tr,
        style: TextStyle(fontSize: 17, color: c.textPrimary),
      ),
      content: SizedBox(
        width: 320,
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over, size: 14, color: c.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '语音状态'.tr,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const Spacer(),
                Text(
                  TtsService.isReady ? '就绪'.tr : '未就绪'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: TtsService.isReady ? c.accent : c.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: log == null || log.isEmpty
                  ? Center(
                      child: Text(
                        '暂无诊断日志'.tr,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        log,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (log != null && log.isNotEmpty)
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: log));
                if (ctx.mounted) {
                  showAppToast(ctx, '日志已复制'.tr);
                }
              } on Object {
                if (ctx.mounted) {
                  showAppToast(ctx, '复制失败'.tr);
                }
              }
            },
            child: Text('复制'.tr, style: TextStyle(color: c.actionForeground)),
          ),
        if (log != null && log.isNotEmpty)
          TextButton(
            onPressed: () async {
              await Diagnostics.clear();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('清除'.tr, style: TextStyle(color: c.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('关闭'.tr, style: TextStyle(color: c.textSecondary)),
        ),
      ],
    ),
  );
}

Widget _toggle(
  AppPalette c,
  String label,
  bool value,
  ValueChanged<bool> onChanged,
) {
  return CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: value,
    activeColor: c.accent,
    title: Text(label, style: TextStyle(fontSize: 13, color: c.textPrimary)),
    onChanged: (v) => onChanged(v ?? false),
  );
}
