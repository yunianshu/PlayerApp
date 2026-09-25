import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'pages/countdown_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/running_page.dart';
import 'pages/stats_page.dart';
import 'services/run_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  // 与 runApp 前的必要初始化保持最短路径：只等主题（首帧配色需要）。
  await themeController.load();
  runApp(RunTrailApp(themeController: themeController));
}

class RunTrailApp extends StatelessWidget {
  final ThemeController themeController;

  const RunTrailApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RunTracker()),
        ChangeNotifierProvider.value(value: themeController),
      ],
      child: Builder(
        builder: (context) {
          final tc = context.watch<ThemeController>();
          // 沉浸式状态栏：内容延伸至系统栏下方，状态栏/导航栏透明。
          // 只在风格变化时设置一次，避免每次 build 重复调用系统通道。
          _syncSystemUi(tc.effectiveStyle != AppThemeStyle.dark);
          // 编辑风与白天主题为浅色背景 → 深色图标；夜间主题反之。
          final darkIcons = tc.effectiveStyle != AppThemeStyle.dark;
          final overlayStyle = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                darkIcons ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                darkIcons ? Brightness.dark : Brightness.light,
            systemNavigationBarDividerColor: Colors.transparent,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false,
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: MaterialApp(
              title: '跑迹 RunTrail',
              debugShowCheckedModeBanner: false,
              // ThemeController 已解析 auto/时间逻辑，直接给出目标风格。
              theme: buildTheme(tc.effectiveStyle),
              home: const HomeShell(),
            ),
          );
        },
      ),
    );
  }

  static AppThemeStyle? _lastUiStyle;

  void _syncSystemUi(bool darkIcons) {
    final style = darkIcons ? AppThemeStyle.light : AppThemeStyle.dark;
    if (_lastUiStyle == style) return;
    _lastUiStyle = style;
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            darkIcons ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            darkIcons ? Brightness.dark : Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }
}

/// 底部导航壳：首页 / 历史 / 统计 / 我的 + 中央开始按钮。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final _pages = [
    HomePage(
      onAvatarTap: () => setState(() => _index = 3),
      onSeeAllTap: () => setState(() => _index = 1),
    ),
    const HistoryPage(),
    const StatsPage(),
    const ProfilePage(),
  ];

  Future<void> _startRun() async {
    final tracker = context.read<RunTracker>();
    final messenger = ScaffoldMessenger.of(context);
    if (!await tracker.ensurePermission()) {
      final deniedForever = await Geolocator.checkPermission() ==
          LocationPermission.deniedForever;
      if (!mounted) return;
      if (deniedForever) {
        // 永久拒绝：系统弹窗不再出现，引导去设置页手动开启。
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要定位权限'),
            content: const Text('记录跑步轨迹需要定位权限，请在系统设置中允许"使用期间"访问位置。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        if (go == true) unawaited(Geolocator.openAppSettings());
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('需要定位权限才能记录跑步轨迹')),
      );
      return;
    }
    if (!await tracker.isServiceEnabled()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('定位服务未开启，请在系统设置中打开定位')),
      );
      return;
    }
    if (!mounted) return;
    final ready = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CountdownPage(
          onComplete: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    if (ready != true || !mounted) return;
    // start 可能因权限/服务在倒计时期间变化而失败，失败则不进入跑步页。
    final started = await tracker.start();
    if (!started || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法开始跑步：定位不可用')),
        );
      }
      return;
    }
    await Navigator.of(context).push(RunningPage.route());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editorial = c.isEditorial;
    return Scaffold(
      // 内容延伸到底部悬浮栏下方，实现透明悬浮效果。
      extendBody: true,
      body: _LazyIndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: editorial
              ? BoxDecoration(borderRadius: BorderRadius.circular(999))
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: c.cardShadow,
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      spreadRadius: -8,
                    ),
                  ],
                ),
          // 左右两端为半圆（胶囊形）。
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: editorial
                ? _barBody(c, editorial)
                : BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: _barBody(c, editorial),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _barBody(AppPalette c, bool editorial) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: c.tabbarBg,
        borderRadius: BorderRadius.circular(999),
        border: editorial ? null : Border.all(color: c.stroke),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _tab(Icons.cottage_outlined, Icons.cottage, '首页', 0),
          _tab(Icons.history, Icons.history, '历史', 1),
          _startButton(c),
          _tab(Icons.bar_chart_rounded, Icons.bar_chart_rounded, '统计', 2),
          _tab(Icons.person_outline, Icons.person, '我的', 3),
        ],
      ),
    );
  }

  Widget _tab(IconData outline, IconData filled, String label, int index) {
    final c = context.colors;
    final active = _index == index;
    return InkWell(
      onTap: () => setState(() => _index = index),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: Icon(
                active ? filled : outline,
                size: 21,
                color: active ? c.accent : c.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? c.accent : c.textMuted,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _startButton(AppPalette c) {
    // 白天：渐变圆钮；夜间/编辑风：实心圆钮（与原型一致）。
    final solid = identical(c, AppPalette.dark) || c.isEditorial;
    return GestureDetector(
      onTap: _startRun,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: solid ? null : accentGradient(c),
          color: solid ? c.accent : null,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.glow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(Icons.play_arrow_rounded, size: 30, color: c.onAccent),
      ),
    );
  }
}

/// 懒加载 IndexedStack：首次切到的 tab 才构建，之后保持存活（保留滚动位置与状态）。
/// 避免 4 个页面在启动时全部 build + 全部查数据库，拖慢首帧。
class _LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _LazyIndexedStack({required this.index, required this.children});

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _visited.contains(i)
              // 切换到某页时淡入；IndexedStack 只绘制当前页，状态保持不变。
              ? AnimatedOpacity(
                  opacity: i == widget.index ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: widget.children[i],
                )
              : const SizedBox.shrink(),
      ],
    );
  }
}
