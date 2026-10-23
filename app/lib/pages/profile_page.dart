import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import '../services/backup_service.dart';
import '../services/diagnostics.dart';
import '../services/badges.dart';
import '../services/file_pick.dart';
import '../services/gpx.dart';
import '../services/share_service.dart';
import '../widgets/badges_card.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/load_error_page.dart';
import '../widgets/settings_sheets.dart';
import '../widgets/app_toast.dart';
import 'ai_coach_settings_page.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../core/theme.dart';
import '../core/theme_controller.dart';
import '../core/launcher_icon_controller.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../services/tracking_policies.dart';
import '../widgets/common.dart';

/// 我的：累计统计、年度目标、成就徽章、设置（记录/通用/数据）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  (double, int, int)? _totals;
  List<RunRecord> _all = const [];
  double _weeklyGoal = 20;
  double _yearlyGoal = 500;
  bool _autoPause = false;
  bool _keepScreenOn = true;
  bool _loadError = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
    AppData.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    AppData.instance.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() => _load();

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() => _loadError = false);
    try {
      await Prefs.instance.load();
      final results = await Future.wait([
        RunDatabase.instance.totals(),
        RunDatabase.instance.listRuns(),
      ]);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _totals = results[0] as (double, int, int);
        _all = results[1] as List<RunRecord>;
        _weeklyGoal = Prefs.instance.weeklyGoalKm;
        _yearlyGoal = Prefs.instance.yearlyGoalKm;
        _autoPause = Prefs.instance.autoPauseEnabled;
        _keepScreenOn = Prefs.instance.keepScreenOn;
      });
    } catch (_) {
      if (mounted && version == _loadVersion) setState(() => _loadError = true);
    }
  }

  Future<void> _exportCsv() async {
    if (_all.isEmpty) {
      showAppToast(context, '还没有跑步记录可以导出'.tr);
      return;
    }
    final buf = StringBuffer(
      'date,start,end,distance_km,duration_s,avg_pace,calories,climb_m,source,title\n',
    );
    for (final r in _all) {
      buf.writeln(
        '${r.start.toIso8601String().substring(0, 10)},'
        '${r.start.toIso8601String()},${r.end.toIso8601String()},'
        '${r.distanceKm.toStringAsFixed(3)},${r.durationS},'
        '${r.avgPaceSecPerKm.toStringAsFixed(1)},'
        '${r.calories},${r.climbM.toStringAsFixed(1)},'
        '${r.source},"${r.title.replaceAll('"', '""')}"',
      );
    }
    try {
      // 写成 .csv 文件分享（而非纯文本），表格软件可直接打开。
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/runtrail_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(buf.toString());
      await ShareService.file(file.path, subject: 'RunTrail 跑步记录');
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '导出失败，请重试'.tr);
    }
  }

  Future<void> _backup() async {
    try {
      final json = await BackupService.exportJson();
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/runtrail_backup_$stamp.json');
      await file.writeAsString(json, flush: true);
      await ShareService.file(file.path, subject: 'RunTrail 备份');
      if (!mounted) return;
      showAppToast(context, '备份已生成，选择保存位置'.tr);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '备份失败，请重试'.tr);
    }
  }

  Future<void> _restore() async {
    final path = await FilePickService.pickJson();
    if (path == null) {
      if (!mounted) return;
      showAppToast(context, '未选择文件或当前平台不支持文件选择'.tr);
      return;
    }
    try {
      final json = await File(path).readAsString();
      final result = await BackupService.restoreJson(json);
      AppData.instance.bump();
      if (!mounted) return;
      showAppToast(
        context,
        result.skipped > 0
            ? '${'恢复完成'.tr} · ${result.imported} ${'条'.tr} · ${'跳过'.tr} ${result.skipped}'
            : '${'恢复完成'.tr} · ${result.imported} ${'条'.tr}',
      );
    } on BackupFormatException {
      if (!mounted) return;
      showAppToast(context, '备份文件格式不正确'.tr);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '恢复失败，请重试'.tr);
    }
  }

  /// 从 GPX 文件导入一次跑步（Keep / Strava / Garmin 等平台导出）。
  /// 会话 ID 由开始时间推导，重复导入同一文件会幂等跳过。
  Future<void> _importGpx() async {
    final path = await FilePickService.pickJson();
    if (path == null) {
      if (!mounted) return;
      showAppToast(context, '未选择文件或当前平台不支持文件选择'.tr);
      return;
    }
    try {
      final xml = await File(path).readAsString();
      final outcome = await importRunFromGpx(xml);
      if (outcome.isDuplicate) {
        if (!mounted) return;
        showAppToast(context, '这条 GPX 记录之前已导入过'.tr);
        return;
      }
      AppData.instance.bump();
      if (!mounted) return;
      showAppToast(
        context,
        '${'GPX 导入完成'.tr} · ${(outcome.import.record.distanceKm).toStringAsFixed(2)} ${'公里'.tr}',
      );
    } on GpxFormatException {
      if (!mounted) return;
      showAppToast(context, 'GPX 文件不正确或缺少时间信息'.tr);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '恢复失败，请重试'.tr);
    }
  }

  Future<void> _editGoal({
    required String title,
    required double current,
    required Future<void> Function(double) onSave,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GoalDialog(title: title, current: current, onSave: onSave),
  );

  Future<void> _editWeeklyGoal() => _editGoal(
    title: '每周目标（公里）'.tr,
    current: _weeklyGoal,
    onSave: (v) async {
      await Prefs.instance.setWeeklyGoal(v);
      if (!mounted) return;
      setState(() => _weeklyGoal = v);
      AppData.instance.bump(); // 首页英雄卡同步刷新
    },
  );

  Future<void> _editYearlyGoal() => _editGoal(
    title: '年度目标（公里）'.tr,
    current: _yearlyGoal,
    onSave: (v) async {
      await Prefs.instance.setYearlyGoal(v);
      if (!mounted) return;
      setState(() => _yearlyGoal = v);
    },
  );

  Future<void> _toggleAutoPause(bool v) async {
    try {
      await Prefs.instance.setAutoPause(v);
      if (!mounted) return;
      setState(() => _autoPause = v);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '保存失败，请重试'.tr);
    }
  }

  Future<void> _toggleKeepScreenOn(bool v) async {
    try {
      await Prefs.instance.setKeepScreenOn(v);
      if (!mounted) return;
      setState(() => _keepScreenOn = v);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '保存失败，请重试'.tr);
    }
  }

  Future<void> _pickTheme() async {
    final c = context.readColors;
    final tc = context.read<ThemeController>();
    final picked = await showModalBottomSheet<AppThemeMode>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        final cc = ctx.colors;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '外观主题'.tr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cc.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '自动模式：白天清透玻璃，夜间高燃运动'.tr,
                  style: TextStyle(fontSize: 12, color: cc.textSecondary),
                ),
                const SizedBox(height: 14),
                for (final (m, label, icon) in [
                  (
                    AppThemeMode.auto,
                    '跟随时间自动'.tr,
                    Icons.brightness_auto_outlined,
                  ),
                  (
                    AppThemeMode.light,
                    '白天 · 清透玻璃'.tr,
                    Icons.light_mode_outlined,
                  ),
                  (AppThemeMode.dark, '夜间 · 高燃运动'.tr, Icons.dark_mode_outlined),
                  (
                    AppThemeMode.editorial,
                    '主题一 · 编辑风'.tr,
                    Icons.article_outlined,
                  ),
                ])
                  ListTile(
                    leading: Icon(icon, color: cc.accent),
                    title: Text(
                      label,
                      style: TextStyle(fontSize: 14, color: cc.textPrimary),
                    ),
                    trailing: tc.mode == m
                        ? Icon(Icons.check_circle, color: cc.accent, size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) tc.setMode(picked);
  }

  void _showAbout() {
    final c = context.readColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '跑迹 RunTrail',
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Text(
          'v${Diagnostics.appVersion} · 第二期\n\n本地优先的跑步记录应用：GPS 轨迹、里程、配速、卡路里，支持语音播报、自动暂停、手动补录、个人纪录与数据备份；跑步数据保存在本机。AI 教练是可选联网功能，仅在你确认后将汇总信息发送至你配置的模型服务。',
          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('好'.tr, style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleController>();
    if (_loadError) return LoadErrorPage(onRetry: _load);
    final c = context.colors;
    final totals = _totals;
    final totalKm = totals?.$1 ?? 0;
    final tc = context.watch<ThemeController>();
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            physics: dampedPhysics,
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 8,
              20,
              110,
            ),
            children: [
              _header(c),
              const SizedBox(height: 16),
              Row(
                children: [
                  _stat(c, '累计里程'.tr, totalKm.toStringAsFixed(1)),
                  const SizedBox(width: 10),
                  _stat(c, '总时长'.tr, totals == null ? '—' : _hours(totals.$2)),
                  const SizedBox(width: 10),
                  _stat(c, '累计次数'.tr, (totals?.$3 ?? 0).toString()),
                ],
              ),
              const SizedBox(height: 12),
              _goalCard(c),
              const SizedBox(height: 12),
              BadgesCard(unlocked: unlockedBadges(badgeContext(_all))),
              const SizedBox(height: 12),
              _goalSettings(c),
              const SizedBox(height: 12),
              _recordSettings(c),
              const SizedBox(height: 12),
              _generalSettings(c, tc),
              const SizedBox(height: 12),
              _dataSettings(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppPalette c) {
    final editorial = c.isEditorial;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                // 编辑风：墨色圆 + 荧光绿人像；其余主题：浅底 + 描边。
                color: editorial ? c.inverseSurface : c.surface2,
                shape: BoxShape.circle,
                border: editorial
                    ? null
                    : Border.all(color: c.accent, width: 2),
              ),
              child: Icon(
                Icons.person_outline,
                size: 28,
                color: editorial ? c.onInverseAccent : c.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '跑者'.tr,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        'LV${_level()}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: c.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${'累计跑步'.tr} ${_days()} ${'天'.tr}',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ],
        ),
        CircleBtn(Icons.settings_outlined, onTap: _pickTheme),
      ],
    );
  }

  int _level() {
    final km = _totals?.$1 ?? 0;
    if (km >= 500) return 5;
    if (km >= 200) return 4;
    if (km >= 100) return 3;
    if (km >= 20) return 2;
    return 1;
  }

  int _days() {
    // 实际有跑步记录的自然日数量（而非"从首跑到今天的天数"）。
    final days = _all
        .map((r) => DateTime(r.start.year, r.start.month, r.start.day))
        .toSet();
    return days.length;
  }

  String _hours(int secs) {
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  Widget _stat(AppPalette c, String label, String value) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14),
        radius: AppRadius.md,
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: c.isEditorial ? 'Playfair Display' : null,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _goalCard(AppPalette c) {
    final now = DateTime.now();
    final yearKm = _all
        .where((r) => r.start.year == now.year)
        .fold<double>(0, (sum, r) => sum + r.distanceKm);
    final yearGoal = _yearlyGoal;
    final pct = yearGoal > 0 ? (yearKm / yearGoal).clamp(0.0, 1.0) : 0.0;
    final editorial = c.isEditorial;
    // 编辑风：深色反转卡（墨底 + 荧光绿进度与百分比）。
    final fg = editorial ? c.onInverse : c.textPrimary;
    final muted = editorial ? scaleAlpha(c.onInverse, 0.7) : c.textSecondary;
    return AppCard(
      inverse: editorial,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: editorial
                          ? scaleAlpha(c.onInverseAccent, 0.2)
                          : c.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.workspace_premium_outlined,
                      size: 15,
                      color: editorial ? c.onInverseAccent : c.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '年度目标'.tr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: editorial ? c.onInverseAccent : c.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${yearKm.toStringAsFixed(1)} / ${Prefs.formatGoal(yearGoal)} km · ${'还差'.tr} ${(yearGoal - yearKm).clamp(0, double.infinity).toStringAsFixed(1)} km',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 12),
          GradientProgress(
            value: pct,
            trackColor: editorial ? scaleAlpha(c.onInverse, 0.2) : null,
            fillColor: editorial ? c.onInverseAccent : null,
          ),
        ],
      ),
    );
  }

  Widget _goalSettings(AppPalette c) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _row(
            c,
            Icons.adjust,
            '每周目标'.tr,
            '${Prefs.formatGoal(_weeklyGoal)} km',
            onTap: _editWeeklyGoal,
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.emoji_events_outlined,
            '年度目标'.tr,
            '${Prefs.formatGoal(_yearlyGoal)} km',
            onTap: _editYearlyGoal,
          ),
        ],
      ),
    );
  }

  Widget _recordSettings(AppPalette c) {
    final paceTarget = Prefs.instance.paceTargetSecPerKm;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleAutoPause(!_autoPause),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.pause_circle_outline,
                      size: 15,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自动暂停'.tr,
                          style: TextStyle(fontSize: 13, color: c.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '停止移动约 10 秒自动暂停，恢复跑动自动继续'.tr,
                          style: TextStyle(fontSize: 10, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  // Flutter 3.47 弃用 activeColor；鸿蒙 3.22 无 activeThumbColor。
                  Switch(
                    value: _autoPause,
                    // ignore: deprecated_member_use
                    activeColor: c.accent,
                    onChanged: _toggleAutoPause,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.divider),
          InkWell(
            onTap: () => _toggleKeepScreenOn(!_keepScreenOn),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.brightness_high,
                      size: 15,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '跑步时屏幕常亮'.tr,
                          style: TextStyle(fontSize: 13, color: c.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '关闭后可息屏省电，实时成绩仍在锁屏通知显示'.tr,
                          style: TextStyle(fontSize: 10, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _keepScreenOn,
                    // ignore: deprecated_member_use
                    activeColor: c.accent,
                    onChanged: _toggleKeepScreenOn,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.volume_up_outlined,
            '语音播报'.tr,
            Prefs.instance.voiceEnabled ? '开'.tr : '关'.tr,
            onTap: () => showVoiceSettingsDialog(context),
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.speed_outlined,
            '配速提醒'.tr,
            paceTarget > 0 ? formatPaceInput(paceTarget) : '关'.tr,
            onTap: () => showPaceTargetDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _generalSettings(AppPalette c, ThemeController tc) {
    final themeLabel = switch (tc.mode) {
      AppThemeMode.auto => '自动'.tr,
      AppThemeMode.light => '白天'.tr,
      AppThemeMode.dark => '夜间'.tr,
      AppThemeMode.editorial => '编辑风'.tr,
    };
    final langLabel = switch (LocaleController.instance.pref) {
      AppLanguage.system => '跟随系统'.tr,
      AppLanguage.zh => '中文'.tr,
      AppLanguage.en => 'English',
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _row(
            c,
            Icons.smart_toy_outlined,
            'AI 服务设置',
            'API Key / 模型',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AiCoachSettingsPage()),
            ),
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.brightness_6_outlined,
            '外观主题'.tr,
            themeLabel,
            onTap: _pickTheme,
          ),
          Divider(height: 1, color: c.divider),
          Consumer<LauncherIconController>(
            builder: (context, icons, _) => SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '桌面图标跟随主题',
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
              subtitle: Text(
                !icons.loaded
                    ? '正在检查支持情况…'
                    : !icons.supported
                    ? '当前平台或安装包暂不支持，保留默认图标'
                    : icons.error ?? '桌面刷新可能稍有延迟；自动主题在应用运行或返回时同步',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
              value: icons.supported && icons.enabled,
              activeThumbColor: c.accent,
              onChanged: !icons.loaded || !icons.supported || icons.busy
                  ? null
                  : (value) async {
                      final ok = await icons.setEnabled(value);
                      if (!context.mounted) return;
                      showAppToast(
                        context,
                        ok
                            ? (value ? '已开启桌面图标跟随主题' : '已恢复默认桌面图标')
                            : '桌面图标设置失败，应用主题不受影响',
                      );
                    },
            ),
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.translate_outlined,
            '语言'.tr,
            langLabel,
            onTap: () => showLanguageDialog(context),
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.bug_report_outlined,
            '诊断日志'.tr,
            '',
            onTap: () => showDiagnosticsDialog(context),
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.info_outline,
            '关于跑迹'.tr,
            'v${Diagnostics.appVersion}',
            onTap: _showAbout,
          ),
        ],
      ),
    );
  }

  Widget _dataSettings(AppPalette c) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _row(c, Icons.download_outlined, '数据导出'.tr, 'CSV', onTap: _exportCsv),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.upload_file_outlined,
            '从 GPX 导入'.tr,
            'GPX',
            onTap: _importGpx,
          ),
          Divider(height: 1, color: c.divider),
          _row(c, Icons.ios_share, '备份数据'.tr, 'JSON', onTap: _backup),
          Divider(height: 1, color: c.divider),
          _row(c, Icons.restore_outlined, '从文件恢复'.tr, '', onTap: _restore),
        ],
      ),
    );
  }

  Widget _row(
    AppPalette c,
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: c.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
            ),
            Text(value, style: TextStyle(fontSize: 12, color: c.textMuted)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}
