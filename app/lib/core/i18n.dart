import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 语言偏好：跟随系统 / 中文 / English。
enum AppLanguage { system, zh, en }

/// 轻量双语方案：源码中的中文字符串本身就是中文文案（key），
/// 英文通过 `_en` 字典覆盖，未收录的字符串回退中文原文。
///
/// 不使用 gen-l10n 的原因：本项目同时受两套工具链约束
/// （主 Flutter 3.47 / 鸿蒙 Flutter 3.22），代码生成产物和
/// synthetic package 行为存在差异；`.tr` 方案无代码生成，
/// 对两套工具链行为一致，且新增文案无需登记 key。
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const _key = 'app_language';

  AppLanguage pref = AppLanguage.system;

  /// 当前生效语言码（'zh' / 'en'）。
  String get code => switch (pref) {
    AppLanguage.zh => 'zh',
    AppLanguage.en => 'en',
    AppLanguage.system => systemCode,
  };

  /// 系统语言：仅取主语言码；中文/英文以外一律回退中文。
  /// 测试环境固定 zh，避免宿主机 locale（CI 常为 en_US）影响中文断言。
  @visibleForTesting
  static String get systemCode {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return 'zh';
    final lang = Platform.localeName.split(RegExp('[-_.]')).first.toLowerCase();
    return lang == 'en' ? 'en' : 'zh';
  }

  bool get isEnglish => code == 'en';

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getString(_key);
      pref = AppLanguage.values.firstWhere(
        (m) => m.name == v,
        orElse: () => AppLanguage.system,
      );
    } on Object {
      // 偏好读取失败时保持默认（跟随系统），不影响功能。
    }
  }

  Future<void> set(AppLanguage lang) async {
    pref = lang;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, lang.name);
    } on Object {
      // 内存状态已生效；持久化失败下次启动回退。
    }
  }
}

/// 中文 → 英文。
String translate(String zh) {
  if (!LocaleController.instance.isEnglish) return zh;
  return _en[zh] ?? zh;
}

extension TrString on String {
  /// 界面文案双语入口：`'数据统计'.tr`。中文环境返回原文。
  String get tr => translate(this);
}

/// 英文字典。key 必须与源码中的中文文案逐字一致。
const Map<String, String> _en = {
  // ---- 通用 ----
  '取消': 'Cancel',
  '保存': 'Save',
  '保存中…': 'Saving…',
  '放弃': 'Discard',
  '删除': 'Delete',
  '重试': 'Retry',
  '好': 'OK',
  '确认': 'Confirm',
  '公里': 'km',
  '完成': 'Done',
  '编辑': 'Edit',
  '数据加载失败，请重试': 'Failed to load data, please retry',
  // ---- 首页 ----
  '早上好': 'Good morning',
  '中午好': 'Good noon',
  '下午好': 'Good afternoon',
  '晚上好': 'Good evening',
  '跑者': 'Runner',
  '本周里程': 'This week',
  '目标': 'Goal',
  '周目标': 'Weekly goal',
  '时长': 'Time',
  '次数': 'Runs',
  '消耗': 'Calories',
  '千卡': 'kcal',
  '本周活动': 'Weekly activity',
  '最近跑步': 'Recent runs',
  '全部': 'All',
  '还没有跑步记录\n点击下方按钮开始第一次跑步吧':
      'No runs yet.\nTap the button below to start your first run!',
  '今天': 'Today',
  '昨天': 'Yesterday',
  '有一次未保存的跑步': 'An unsaved run',
  '保存失败，请重试': 'Save failed, please retry',
  '放弃失败，请重试': 'Discard failed, please retry',
  '放弃未完成的记录？': 'Discard this unfinished run?',
  '这条轨迹数据将被删除，无法恢复。': 'The track data will be deleted and cannot be recovered.',
  '手动补录': 'Add manually',
  '还差': 'to go',
  // ---- 开始跑步 ----
  '请先保存或放弃首页的未完成记录，再开始新跑步':
      'Save or discard the unfinished run on Home before starting a new one',
  '需要定位权限': 'Location permission required',
  '记录跑步轨迹需要定位权限，请在系统设置中允许"使用期间"访问位置。': 'Recording runs needs location access. Please allow location (While Using) in system settings.',
  '去设置': 'Open settings',
  '需要定位权限才能记录跑步轨迹': 'Location permission is required to record runs',
  '定位服务未开启，请在系统设置中打开定位':
      'Location service is off. Please enable it in system settings.',
  '无法开始跑步：定位不可用': 'Cannot start: location unavailable',
  '无法开始跑步，请检查定位与存储后重试': 'Cannot start. Check location and storage, then retry',
  // ---- 跑步中 ----
  '跑步中': 'Running',
  '已暂停': 'Paused',
  '换边': 'Switch sides',
  '时间过半': 'Halfway done',
  '还剩10秒': '10 seconds left',
  '还剩5秒': '5 seconds left',
  '已自动暂停': 'Auto-paused',
  'GPS 不可用': 'GPS unavailable',
  '精度不足，请开启精确定位': 'Weak accuracy — enable precise location',
  '搜索 GPS…': 'Searching GPS…',
  'GPS 记录中': 'GPS recording',
  '草稿保存失败，请检查存储并及时保存记录':
      'Draft save failed — check storage and save your run soon',
  '后台定位启动失败，请保持应用在前台记录':
      'Background location failed — keep the app in foreground',
  '当前配速': 'Pace',
  '卡路里': 'Calories',
  '已自动暂停 · 跑动后会自动继续': 'Auto-paused · resumes when you move',
  '已自动暂停，继续跑动即可恢复': 'Auto-paused. Start moving to resume.',
  '已自动恢复，加油！': 'Auto-resumed. Keep going!',
  '继续跑步，加油！': 'Resumed. Keep going!',
  '结束跑步？': 'Finish run?',
  '当前里程': 'Current distance',
  ' 公里，结束后将进入保存页。': ' km. You will go to the save screen.',
  '继续跑': 'Keep running',
  '结束': 'Finish',
  '结束记录失败，请重试': 'Failed to finish, please retry',
  '跑步结束': 'Run finished',
  '正在生成运动记录…': 'Generating your run record…',
  '已锁定，防止误触': 'Locked to prevent accidental taps',
  '长按下方按钮解锁': 'Long-press the button below to unlock',
  '长按解锁': 'Long-press to unlock',
  '慢于目标': 'Slower than target',
  '快于目标': 'Faster than target',
  '配速提醒': 'Pace alert',
  // ---- 总结页 ----
  '跑步完成！': 'Run completed!',
  '晨跑': 'Morning run',
  '午间跑': 'Noon run',
  '午后跑': 'Afternoon run',
  '夜跑': 'Night run',
  '凌晨跑': 'Late-night run',
  '跑步距离': 'Distance',
  '分段配速': 'Splits',
  '最快': 'Best',
  '已保存 ✓': 'Saved ✓',
  '保存记录': 'Save run',
  '分享成绩单': 'Share result',
  '分享图片': 'Share image',
  '正在生成图片…': 'Preparing image…',
  '分享未完成': 'Sharing was cancelled',
  '放弃这条记录？': 'Discard this run?',
  '放弃这条记录': 'Discard this run',
  '分享失败，请重试': 'Share failed, please retry',
  // ---- 历史 ----
  '跑步记录': 'Run history',
  '暂无跑步记录': 'No runs yet',
  '本周': 'This week',
  '上周': 'Last week',
  '更早': 'Earlier',
  '没有跑步记录': 'No runs',
  '次': ' runs',
  ' 手动': ' manual',
  // ---- 详情 ----
  '跑步详情': 'Run detail',
  '距离': 'Distance',
  '平均配速': 'Avg pace',
  '平均速度': 'Avg speed',
  '累计爬升': 'Elevation gain',
  '每公里配速': 'Pace per km',
  '海拔变化': 'Elevation',
  '删除这条记录？': 'Delete this run?',
  '轨迹数据将一并删除，无法恢复。': 'Track data will be deleted and cannot be recovered.',
  '删除失败，请重试': 'Delete failed, please retry',
  '删除这条记录': 'Delete this run',
  '手动记录': 'Manual entry',
  '备注': 'Notes',
  '编辑标题与备注': 'Edit title & notes',
  '标题': 'Title',
  '备注内容': 'Notes content',
  '导出 GPX': 'Export GPX',
  'GPX 已生成，选择保存位置': 'GPX ready — choose where to save',
  '导出失败，请重试': 'Export failed, please retry',
  '手动记录没有轨迹，无法导出 GPX': 'Manual entries have no track to export',
  '分享': 'Share',
  '海报已生成，选择分享方式': 'Poster ready — choose how to share',
  '海报生成失败，请重试': 'Poster generation failed, please retry',
  '保存修改': 'Save changes',
  // ---- 统计 ----
  '数据统计': 'Stats',
  '汇总': ' summary',
  '本月': 'This month',
  '今年': 'This year',
  '运动日历': 'Activity calendar',
  '天': ' days',
  '近 8 周里程': 'Last 8 weeks',
  '平均': 'Average',
  '最快配速': 'Best pace',
  '单次最佳': 'Single-run best',
  '当前范围': 'In range',
  '个人纪录': 'Personal records',
  '最快 1 公里': 'Fastest 1 km',
  '最快 5 公里': 'Fastest 5 km',
  '最快 10 公里': 'Fastest 10 km',
  '最长单次': 'Longest run',
  '最长时长': 'Longest time',
  '连续打卡': 'Streak',
  '连续': 'day streak',
  '本月对比': 'Month vs last',
  '上月': 'Last month',
  '暂无足够数据': 'Not enough data yet',
  // ---- 我的 ----
  '累计里程': 'Total distance',
  '总时长': 'Total time',
  '累计次数': 'Total runs',
  '累计跑步': 'days running',
  '年度目标': 'Yearly goal',
  '成就徽章': 'Badges',
  '每周目标（公里）': 'Weekly goal (km)',
  '年度目标（公里）': 'Yearly goal (km)',
  '外观主题': 'Appearance',
  '自动': 'Auto',
  '白天': 'Light',
  '夜间': 'Dark',
  '编辑风': 'Editorial',
  '自动模式：白天清透玻璃，夜间高燃运动': 'Auto: light glass by day, sporty dark by night',
  '跟随时间自动': 'Follow time of day',
  '白天 · 清透玻璃': 'Light · clear glass',
  '夜间 · 高燃运动': 'Dark · high-energy',
  '主题一 · 编辑风': 'Editorial',
  '数据导出': 'Export data',
  '关于跑迹': 'About RunTrail',
  '我的': 'Me',
  '首页': 'Home',
  '历史': 'History',
  '统计': 'Stats',
  '记录设置': 'Recording',
  '自动暂停': 'Auto-pause',
  '语音播报': 'Voice announcements',
  '每公里播报距离、用时与配速': 'Announce each km: distance, time and pace',
  '语言': 'Language',
  '跟随系统': 'System',
  '中文': 'Chinese',
  'English': 'English',
  '数据管理': 'Data',
  '导出 CSV': 'Export CSV',
  '备份数据': 'Backup',
  '从文件恢复': 'Restore',
  '从 GPX 导入': 'Import GPX',
  'GPX 导入完成': 'GPX run imported',
  '这条 GPX 记录之前已导入过': 'This GPX run was already imported',
  'GPX 文件不正确或缺少时间信息': 'Invalid GPX file, or no timestamps in it',
  '备份已生成，选择保存位置': 'Backup ready — choose where to save',
  '备份失败，请重试': 'Backup failed, please retry',
  '还没有跑步记录可以导出': 'No runs to export yet',
  '已恢复': 'restored',
  '恢复完成': 'Restore complete',
  '恢复失败，请重试': 'Restore failed, please retry',
  '未选择文件或当前平台不支持文件选择': 'No file chosen, or file picking is unsupported here',
  '备份文件格式不正确': 'Not a valid RunTrail backup file',
  '选择备份 JSON 文件': 'Choose a backup JSON file',
  '播报内容': 'Announce',
  '用时': 'Elapsed',
  '当前目标配速': 'Target pace',
  '每分钟秒数或 分:秒，如 5:30': 'Seconds per km or m:ss, e.g. 5:30',
  '格式无效，请输入如 5:30': 'Invalid format, try 5:30',
  '目标配速需在 1:00 – 30:00 /公里 之间': 'Target pace must be 1:00 – 30:00 per km',
  '保存目标失败': 'Failed to save target',
  '恭喜解锁新徽章': 'New badges unlocked!',
  '收下勋章': 'Claim badge',
  // ---- 徽章 ----
  '首跑完成': 'First run',
  '首个 5 公里': 'First 5 km',
  '十公里突破': '10K breakthrough',
  '半马挑战': 'Half marathon',
  '全马挑战': 'Full marathon',
  '累计 50 公里': '50 km total',
  '百公里俱乐部': '100 km club',
  '五百公里': '500 km club',
  '千公里传奇': '1000 km legend',
  '三日连续': '3-day streak',
  '七日连续': '7-day streak',
  '廿一日坚持': '21-day streak',
  '运动十小时': '10 hours moving',
  '运动五十小时': '50 hours moving',
  '晨型跑者': 'Early bird',
  '星夜跑者': 'Night owl',
  '完成你的第一次跑步': 'Complete your first run',
  '单次跑步达到 5 公里': 'Run 5 km in a single run',
  '单次跑步达到 10 公里': 'Run 10 km in a single run',
  '单次跑步达到 21.0975 公里': 'Run a half marathon (21.0975 km)',
  '单次跑步达到 42.195 公里': 'Run a full marathon (42.195 km)',
  '累计里程达到 50 公里': 'Reach 50 km in total',
  '累计里程达到 100 公里': 'Reach 100 km in total',
  '累计里程达到 500 公里': 'Reach 500 km in total',
  '累计里程达到 1000 公里': 'Reach 1000 km in total',
  '连续 3 天跑步': 'Run 3 days in a row',
  '连续 7 天跑步': 'Run 7 days in a row',
  '连续 21 天跑步': 'Run 21 days in a row',
  '累计运动时长达到 10 小时': 'Accumulate 10 hours of running',
  '累计运动时长达到 50 小时': 'Accumulate 50 hours of running',
  '完成一次清晨（5–8 点）跑步': 'Finish a run between 5:00 and 8:00',
  '完成一次深夜（21 点后）跑步': 'Finish a run after 21:00',
  // ---- 手动补录 ----
  '补录一次跑步（跑步机、忘带手机等场景）': 'Log a run without GPS (treadmill, forgot the phone…)',
  '日期': 'Date',
  '开始时间': 'Start time',
  '时长（分:秒）': 'Duration (m:ss)',
  '距离（公里）': 'Distance (km)',
  '标题（可选）': 'Title (optional)',
  '备注（可选）': 'Notes (optional)',
  '跑步机 5km': 'Treadmill 5km',
  '请输入有效时长，如 30:00 或 90': 'Enter a valid duration, e.g. 30:00',
  '请输入有效距离（0.1 – 200 公里）': 'Enter a valid distance (0.1 – 200 km)',
  '时间格式应为 时:分': 'Time format should be h:mm',
  '日期不能晚于今天': 'Date cannot be in the future',
  '补录成功': 'Run added',
  '补录失败，请重试': 'Failed to add, please retry',
  // ---- 诊断 ----
  '查看诊断日志': 'View diagnostic log',
  '诊断日志': 'Diagnostic log',
  '暂无诊断日志': 'No diagnostics yet',
  '复制': 'Copy',
  '清除': 'Clear',
  '已清除': 'Cleared',
  '日志已复制': 'Log copied',
  '复制失败': 'Copy failed',
  // ---- GPX / 目标 ----
  '请输入 1–1000 之间的有效公里数': 'Enter a valid value between 1 and 1000 km',
  '每周目标': 'Weekly goal',
  '每公里': ' /km',
  // ---- 单位与杂项 ----
  '分钟': 'min',
  '秒': 's',
  '开始跑步！': "Let's run!",
  '试听': 'Preview',
  '立刻验证语音是否正常': 'Verify voice right now',
  '语音播报正常，3、2、1，开始跑步！': "Voice check: 3, 2, 1, let's run!",
  'TTS 初始化失败，请查看诊断日志': 'TTS unavailable — see the diagnostic log',
  '系统语音引擎缺少当前语言，请在系统文字转语音设置中安装语音数据': 'The speech engine needs voice data for this language. Install it in system text-to-speech settings.',
  '系统语音引擎不可用，请在系统文字转语音设置中启用或安装语音引擎': 'No speech engine is available. Enable or install one in system text-to-speech settings.',
  '语音播放失败，请检查媒体音量及系统文字转语音设置，详情见诊断日志': 'Speech playback failed. Check media volume and system text-to-speech settings. See the diagnostic log for details.',
  '语音状态': 'Voice status',
  '就绪': 'Ready',
  '未就绪': 'Not ready',
  // ---- 第二期补充 ----
  '跑步': 'Run',
  '，': ', ',
  '开': 'On',
  '关': 'Off',
  '条': 'runs',
  '跳过': 'skipped',
  '配速': 'Pace',
  '关闭': 'Close',
  '分享成绩海报': 'Share poster',
  '文字成绩单': 'Share result text',
  '包含轨迹点，可导入其他平台': 'Includes track points for other platforms',
  '记录每一步': 'Every step counts',
  '停止移动约 10 秒自动暂停，恢复跑动自动继续':
      'Auto-pause after ~10 s of stillness; resumes when you move',
  // 单字段切换与星期
  '周': 'W',
  '月': 'M',
  '年': 'Y',
  '一': 'Mo',
  '二': 'Tu',
  '三': 'We',
  '四': 'Th',
  '五': 'Fr',
  '六': 'Sa',
  '日': 'Su',
  // ---- 跑步协助课程（热身 / 拉伸） ----
  '跑前热身': 'Pre-run warm-up',
  '跑后拉伸': 'Post-run stretch',
  '跑前热身？': 'Warm up first?',
  '是否直接开跑？': 'Start running now?',
  '确认后进入开跑倒计时。': 'Confirm to start the countdown.',
  '热身': 'Warm up',
  '开跑': 'Start run',
  '直接开跑': 'Just run',
  '开始热身': 'Start warm-up',
  '热身完成！': 'Warm-up done!',
  '拉伸完成！': 'Stretch done!',
  '结束课程？': 'End this session?',
  '剩余动作将不再继续': 'The remaining moves will be skipped',
  '继续课程': 'Keep going',
  '播报间隔': 'Announce every',
  '500米': '500 m',
  '1公里': '1 km',
  '2公里': '2 km',
  '跑步时屏幕常亮': 'Keep screen on while running',
  '关闭后可息屏省电，实时成绩仍在锁屏通知显示':
      'Turn off to save battery; live stats stay on the lock-screen notification',
  '课程': 'Courses',
  '跑步课程': 'Running courses',
  '协助课程': 'Companion courses for every run',
  '长按按钮结束并保存': 'Hold the button to finish and save',
  '自动保存失败，请在下一页手动保存':
      'Auto-save failed — save manually on the next screen',
  '跑后拉伸？': 'Stretch now?',
  '帮助恢复，减少肌肉酸痛，约5分钟':
      'Speed up recovery and ease soreness, about 5 min',
  '暂不': 'Not now',
  '开始拉伸': 'Start stretching',
  '未授予通知权限，锁屏将看不到实时成绩':
      'No notification permission — live stats will not show on the lock screen',
  '去开启': 'Enable',
  // 热身动作
  '原地慢跑': 'Jog in place',
  '轻盈落地，逐渐把心率带起来': 'Land softly and raise your heart rate',
  '踝关节环绕': 'Ankle circles',
  '脚尖点地画最大的圆，双脚交替': 'Toe down, draw the widest circle; switch feet',
  '开合跳': 'Jumping jacks',
  '落地屈膝缓冲，保持稳定节奏': 'Bend your knees on landing, keep a steady rhythm',
  '弓步转体': 'Lunge with twist',
  '前膝对准脚尖，转体看向后方': 'Front knee over toes, twist and look behind',
  '高抬腿': 'High knees',
  '大腿抬至水平，核心收紧不后仰': 'Lift knees to hip height, core tight, no leaning back',
  '腿后侧动态拉伸': 'Dynamic hamstring stretch',
  '直腿体前屈，感受大腿后侧发力': 'Hinge forward with a straight leg, feel the hamstring',
  // 拉伸动作
  '大腿前侧拉伸': 'Quad stretch',
  '手扶脚背向臀部收，两侧各约 20 秒': 'Pull your heel to your glutes; ~20 s each side',
  '大腿后侧拉伸': 'Hamstring stretch',
  '直腿勾脚尖，背部平直向前压': 'Flex the foot, hinge with a flat back',
  '小腿拉伸': 'Calf stretch',
  '后腿伸直脚跟踩地，前腿弓步下压': 'Back leg straight, heel down; lean into the front knee',
  '臀部拉伸': 'Glute stretch',
  '脚踝搭在对侧膝上，臀部向后坐': 'Ankle over the opposite knee, sit your hips back',
  '髋屈肌拉伸': 'Hip flexor stretch',
  '弓步下压，骨盆微微后倾': 'Low lunge, tuck the pelvis slightly',
  '大腿外侧拉伸': 'Outer thigh (IT band) stretch',
  '前腿交叉，俯身向侧下方压': 'Cross the front leg, hinge down and sideways',
  '深呼吸放松': 'Cool-down breathing',
  '鼻吸口呼，让心率缓缓回落': 'Inhale through the nose, exhale through the mouth',
};

/// 月份英文缩写（formatRunTime 英文形态使用）。
const List<String> enMonthAbbr = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
