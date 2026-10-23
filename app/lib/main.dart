import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'core/i18n.dart';
import 'core/prefs.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'core/launcher_icon_controller.dart';
import 'pages/countdown_page.dart';
import 'pages/course_page.dart';
import 'pages/courses_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/running_page.dart';
import 'pages/stats_page.dart';
import 'services/run_tracker.dart';
import 'services/run_draft.dart';
import 'services/app_data.dart';
import 'services/courses.dart';
import 'services/diagnostics.dart';
import 'services/tts_service.dart';
import 'widgets/splash_gate.dart';
import 'widgets/app_toast.dart';
import 'widgets/run_start_confirmation.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 未捕获异常本地落盘（我的 → 诊断日志可查看），无网络上报。
      Diagnostics.install();
      unawaited(Diagnostics.logStartup());
      final themeController = ThemeController();
      final localeController = LocaleController.instance;
      // 在首帧前恢复保存的主题和语言；过场与首页共用同一调色板。
      // 偏好通道异常或无响应也必须继续启动，不能无限停在原生启动页。
      await Future.wait([
        themeController.load(),
        localeController.load().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        ),
      ]);
      runApp(RunTrailApp(themeController: themeController, showSplash: true));
    },
    (error, stack) {
      // runZonedGuarded 兜底：Diagnostics.install 已接管 PlatformDispatcher，
      // 这里主要防御安装前的同步异常。
      unawaited(Diagnostics.logError('ZONE', error, stack));
    },
  );
}

class RunTrailApp extends StatelessWidget {
  final ThemeController themeController;

  /// 正常冷启动播放一次；组件/页面测试和嵌入场景默认不播放。
  final bool showSplash;

  const RunTrailApp({
    super.key,
    required this.themeController,
    this.showSplash = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RunTracker()),
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => LauncherIconController(themeController)..load(),
        ),
        ChangeNotifierProvider.value(value: LocaleController.instance),
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
            statusBarIconBrightness: darkIcons
                ? Brightness.dark
                : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: darkIcons
                ? Brightness.dark
                : Brightness.light,
            systemNavigationBarDividerColor: Colors.transparent,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarContrastEnforced: false,
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: ListenableBuilder(
              listenable: LocaleController.instance,
              builder: (context, _) => MaterialApp(
                title: '跑迹 RunTrail'.tr,
                debugShowCheckedModeBanner: false,
                // ThemeController 已解析 auto/时间逻辑，直接给出目标风格。
                theme: buildTheme(tc.effectiveStyle),
                // 启动动画跟随已保存主题；首页同时预热且不因过场移除重建。
                home: SplashGate(enabled: showSplash, child: const HomeShell()),
              ),
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
        statusBarIconBrightness: darkIcons ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: darkIcons
            ? Brightness.dark
            : Brightness.light,
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _starting = false;
  Timer? _dateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      AppData.instance.refreshForDate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!AppData.instance.refreshForDate()) AppData.instance.bump();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dateTimer?.cancel();
    super.dispose();
  }

  late final _pages = [
    HomePage(
      onAvatarTap: () => setState(() => _index = 3),
      // 历史 tab 已让位给课程；全部记录从首页"全部"以路由进入。
      onSeeAllTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const HistoryPage())),
    ),
    const CoursesPage(),
    const StatsPage(),
    const ProfilePage(),
  ];

  Future<void> _startRun() async {
    if (_starting) return;
    setState(() => _starting = true);
    final tracker = context.read<RunTracker>();
    try {
      final draft = await RunDraft.load();
      if (!mounted) return;
      if (draft != null && draft.recoverable) {
        setState(() => _index = 0);
        AppData.instance.bump();
        showAppToast(context, '请先保存或放弃首页的未完成记录，再开始新跑步'.tr);
        return;
      }
      if (!await tracker.ensurePermission()) {
        final deniedForever =
            await Geolocator.checkPermission() ==
            LocationPermission.deniedForever;
        if (!mounted) return;
        if (deniedForever) {
          // 永久拒绝：系统弹窗不再出现，引导去设置页手动开启。
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('需要定位权限'.tr),
              content: Text('记录跑步轨迹需要定位权限，请在系统设置中允许"使用期间"访问位置。'.tr),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('取消'.tr),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('去设置'.tr),
                ),
              ],
            ),
          );
          if (go == true) unawaited(Geolocator.openAppSettings());
          return;
        }
        showAppToast(context, '需要定位权限才能记录跑步轨迹'.tr);
        return;
      }
      if (!await tracker.isServiceEnabled()) {
        if (!mounted) return;
        showAppToast(context, '定位服务未开启，请在系统设置中打开定位'.tr);
        return;
      }
      if (!mounted) return;
      // 首次提示热身，明确选择后持久保存；取消不算已提醒。
      final choice = await showRunStartConfirmation(context);
      if (!mounted) return;
      if (choice == RunStartChoice.warmup) {
        // 中途放弃热身视为取消本次开跑；完成热身进入倒计时。
        final done = await Navigator.of(context)
            .push<bool>(CoursePage.route(warmupCourse, '热身完成！'));
        if (done != true || !mounted) return;
      } else if (choice != RunStartChoice.run) {
        // 对话框被系统返回关闭：不开始跑步。
        return;
      }
      // 在倒计时开始前预热引擎，避免异步初始化吞掉开头的数字。
      if (Prefs.instance.voiceEnabled) await TtsService.ensureInitialized();
      if (!mounted) return;
      final ready = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              CountdownPage(onComplete: () => Navigator.of(context).pop(true)),
        ),
      );
      if (ready != true || !mounted) return;
      // start 可能因权限/服务在倒计时期间变化而失败，失败则不进入跑步页。
      final started = await tracker.start();
      if (!started || !mounted) {
        if (mounted) {
          showAppToast(context, '无法开始跑步：定位不可用'.tr);
        }
        return;
      }
      await Navigator.of(context).push(RunningPage.route());
    } catch (_) {
      if (mounted) {
        showAppToast(context, '无法开始跑步，请检查定位与存储后重试'.tr);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // home 是 const 实例，MaterialApp 重建会被 Element 短路；
    // 必须显式 watch 才能在语言切换时重建底栏。
    context.watch<LocaleController>();
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
          Expanded(
            child: _tab(Icons.cottage_outlined, Icons.cottage, '首页'.tr, 0),
          ),
          Expanded(
            child: _tab(
              Icons.play_circle_outline,
              Icons.play_circle,
              '课程'.tr,
              1,
            ),
          ),
          _startButton(c),
          Expanded(
            child: _tab(
              Icons.bar_chart_rounded,
              Icons.bar_chart_rounded,
              '统计'.tr,
              2,
            ),
          ),
          Expanded(child: _tab(Icons.person_outline, Icons.person, '我的'.tr, 3)),
        ],
      ),
    );
  }

  Widget _tab(IconData outline, IconData filled, String label, int index) {
    final c = context.colors;
    final active = _index == index;
    // 编辑风底栏是墨底胶囊：textMuted（为米底调的深灰）在墨上不可读，
    // 用柔化的米白替代；其余主题用 textMuted（已加深到 WCAG 达标）。
    final inactive = c.isEditorial
        ? Color.lerp(c.onInverse, c.inverseSurface, 0.45)!
        : c.textMuted;
    return InkWell(
      onTap: () {
        AppData.instance.refreshForDate();
        setState(() => _index = index);
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
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
                color: active ? c.accent : inactive,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? c.accent : inactive,
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
      onTap: _starting ? null : _startRun,
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
