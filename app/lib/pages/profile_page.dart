import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/prefs.dart';
import '../core/theme.dart';
import '../core/theme_controller.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import '../services/app_data.dart';
import '../widgets/common.dart';

/// 我的：累计统计、年度目标、成就徽章、设置（主题切换 / 周目标 / 数据导出）。
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
    await Prefs.instance.load();
    final db = RunDatabase.instance;
    final totals = await db.totals();
    final runs = await db.listRuns();
    if (!mounted) return;
    setState(() {
      _totals = totals;
      _all = runs;
      _weeklyGoal = Prefs.instance.weeklyGoalKm;
      _yearlyGoal = Prefs.instance.yearlyGoalKm;
    });
  }

  Future<void> _exportCsv() async {
    if (_all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有跑步记录可以导出')),
      );
      return;
    }
    final buf = StringBuffer(
      'date,start,end,distance_km,duration_s,avg_pace,calories,climb_m\n',
    );
    for (final r in _all) {
      buf.writeln(
        '${r.start.toIso8601String().substring(0, 10)},'
        '${r.start.toIso8601String()},${r.end.toIso8601String()},'
        '${r.distanceKm.toStringAsFixed(3)},${r.durationS},'
        '${r.avgPaceSecPerKm.toStringAsFixed(1)},'
        '${r.calories},${r.climbM.toStringAsFixed(1)}',
      );
    }
    try {
      // 写成 .csv 文件分享（而非纯文本），表格软件可直接打开。
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/runtrail_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(buf.toString());
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'RunTrail 跑步记录',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出失败，请重试')),
      );
    }
  }

  Future<void> _editGoal({
    required String title,
    required double current,
    required Future<void> Function(double) onSave,
  }) async {
    final c = context.colors;
    final controller = TextEditingController(text: current.toStringAsFixed(0));
    final ok = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          title,
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(
            suffixText: 'km',
            suffixStyle: TextStyle(color: c.textSecondary),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: Text('保存', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
    // 对话框退场动画期间 TextField 仍持有控制器，延迟释放避免 use-after-dispose。
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (!mounted) return;
    if (ok == null) return; // 取消
    // 输入非法时给出反馈，而不是静默忽略。
    if (ok <= 0 || ok > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 1 - 1000 之间的公里数')),
      );
      return;
    }
    await onSave(ok);
  }

  Future<void> _editWeeklyGoal() => _editGoal(
    title: '每周目标（公里）',
    current: _weeklyGoal,
    onSave: (v) async {
      await Prefs.instance.setWeeklyGoal(v);
      if (!mounted) return;
      setState(() => _weeklyGoal = v);
      AppData.instance.bump(); // 首页英雄卡同步刷新
    },
  );

  Future<void> _editYearlyGoal() => _editGoal(
    title: '年度目标（公里）',
    current: _yearlyGoal,
    onSave: (v) async {
      await Prefs.instance.setYearlyGoal(v);
      if (!mounted) return;
      setState(() => _yearlyGoal = v);
    },
  );

  Future<void> _pickTheme() async {
    final c = context.colors;
    final tc = context.read<ThemeController>();
    final picked = await showModalBottomSheet<AppThemeMode>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  '外观主题',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cc.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '自动模式：白天清透玻璃，夜间高燃运动',
                  style: TextStyle(fontSize: 12, color: cc.textSecondary),
                ),
                const SizedBox(height: 14),
                for (final (m, label, icon) in [
                  (AppThemeMode.auto, '跟随时间自动', Icons.brightness_auto_outlined),
                  (AppThemeMode.light, '白天 · 清透玻璃', Icons.light_mode_outlined),
                  (AppThemeMode.dark, '夜间 · 高燃运动', Icons.dark_mode_outlined),
                  (AppThemeMode.editorial, '主题一 · 编辑风', Icons.article_outlined),
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
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '跑迹 RunTrail',
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        content: Text(
          'v1.0 · 第一期\n\n纯本地跑步记录应用：GPS 轨迹、里程、配速、卡路里，数据仅保存在本机，无需联网与账号。',
          style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('好', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final totals = _totals;
    final totalKm = totals?.$1 ?? 0;
    final tc = context.watch<ThemeController>();
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: dampedPhysics,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
          children: [
            _header(c),
            const SizedBox(height: 16),
            Row(
              children: [
                _stat(c, '累计里程', totalKm.toStringAsFixed(1)),
                const SizedBox(width: 10),
                _stat(c, '总时长', totals == null ? '—' : _hours(totals.$2)),
                const SizedBox(width: 10),
                _stat(c, '累计次数', (totals?.$3 ?? 0).toString()),
              ],
            ),
            const SizedBox(height: 12),
            _goalCard(c, totalKm),
            const SizedBox(height: 12),
            _badges(c, totalKm),
            const SizedBox(height: 12),
            _settings(c, tc),
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
                      '跑者',
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
                        borderRadius: BorderRadius.circular(9),
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
                  '累计跑步 ${_days()} 天',
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
        radius: 18,
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

  Widget _goalCard(AppPalette c, double km) {
    final yearGoal = _yearlyGoal;
    final pct = yearGoal > 0 ? (km / yearGoal).clamp(0.0, 1.0) : 0.0;
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
                    '年度目标',
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
            '${km.toStringAsFixed(1)} / ${yearGoal.toStringAsFixed(0)} 公里 · 还差 ${(yearGoal - km).abs().toStringAsFixed(1)} 公里',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 12),
          GradientProgress(
            value: pct,
            trackColor: editorial
                ? scaleAlpha(c.onInverse, 0.2)
                : null,
            fillColor: editorial ? c.onInverseAccent : null,
          ),
        ],
      ),
    );
  }

  Widget _badges(AppPalette c, double km) {
    final badges = [
      ('首跑完成', Icons.flag_outlined, km >= 0.01),
      ('十公里', Icons.emoji_events_outlined, km >= 10),
      ('百公里', Icons.military_tech_outlined, km >= 100),
      ('半马挑战', Icons.workspace_premium_outlined, km >= 210.975),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '成就徽章',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (name, icon, ok) in badges)
                SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: ok ? c.accentSoft : c.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ok ? c.accentStroke : c.stroke,
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: ok ? c.accent : c.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 10,
                          color: ok ? c.textPrimary : c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settings(AppPalette c, ThemeController tc) {
    final themeLabel = switch (tc.mode) {
      AppThemeMode.auto => '自动',
      AppThemeMode.light => '白天',
      AppThemeMode.dark => '夜间',
      AppThemeMode.editorial => '编辑风',
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _row(
            c,
            Icons.adjust,
            '每周目标',
            '${_weeklyGoal.toStringAsFixed(0)} km',
            onTap: _editWeeklyGoal,
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.emoji_events_outlined,
            '年度目标',
            '${_yearlyGoal.toStringAsFixed(0)} km',
            onTap: _editYearlyGoal,
          ),
          Divider(height: 1, color: c.divider),
          _row(
            c,
            Icons.brightness_6_outlined,
            '外观主题',
            themeLabel,
            onTap: _pickTheme,
          ),
          Divider(height: 1, color: c.divider),
          _row(c, Icons.download_outlined, '数据导出', 'CSV', onTap: _exportCsv),
          Divider(height: 1, color: c.divider),
          _row(c, Icons.info_outline, '关于跑迹', 'v1.0', onTap: _showAbout),
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
