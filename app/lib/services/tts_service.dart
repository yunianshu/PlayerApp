import 'dart:async';

import 'package:flutter/services.dart';

import 'diagnostics.dart';
import '../core/i18n.dart';

/// 语音播报：原生 TTS（Android TextToSpeech / iOS AVSpeechSynthesizer /
/// HarmonyOS CoreSpeechKit）。宿主无实现或引擎不可用时优雅降级为不播报。
class TtsService {
  TtsService._();

  static const _channel = MethodChannel('runtrail/tts');
  static bool _ready = false;
  static String? _readyLanguage;
  static Future<bool>? _initializing;
  static String? _initializingLanguage;
  static String? _lastErrorCode;
  static int _speechGeneration = 0;

  /// TTS 是否可用（已成功初始化）。
  static bool get isReady => _ready && _readyLanguage == _languageTag;

  static String get failureMessage => switch (_lastErrorCode) {
    'tts_language_missing_data' ||
    'tts_language_not_supported' => '系统语音引擎缺少当前语言，请在系统文字转语音设置中安装语音数据'.tr,
    'tts_init_failed' ||
    'missing_plugin' => '系统语音引擎不可用，请在系统文字转语音设置中启用或安装语音引擎'.tr,
    _ => '语音播放失败，请检查媒体音量及系统文字转语音设置，详情见诊断日志'.tr,
  };

  static String get _languageTag =>
      LocaleController.instance.isEnglish ? 'en-US' : 'zh-CN';

  /// 初始化 TTS 引擎。失败（不支持/无语音数据）返回 false，不抛异常。
  /// 每次进入跑步页/开启开关都会重试，失败原因落诊断日志便于排查。
  static Future<bool> ensureInitialized() async {
    if (isReady) return true;
    final lang = _languageTag;
    final pending = _initializing;
    if (pending != null) {
      final pendingLanguage = _initializingLanguage;
      final ready = await pending;
      if (pendingLanguage == lang) return ready && isReady;
      return ensureInitialized();
    }
    _initializingLanguage = lang;
    final initialization = _initialize(lang);
    _initializing = initialization;
    try {
      return await initialization;
    } finally {
      _initializing = null;
      _initializingLanguage = null;
    }
  }

  static Future<bool> _initialize(String lang) async {
    _ready = false;
    _lastErrorCode = null;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'error') {
        _ready = false;
        _lastErrorCode = 'tts_playback_failed';
        await Diagnostics.log('TTS playback failed: ${call.arguments}');
      }
    });
    try {
      _ready =
          await _channel
              .invokeMethod<bool>('init', {'lang': lang})
              .timeout(const Duration(seconds: 12)) ??
          false;
      _readyLanguage = _ready ? lang : null;
      if (_ready) {
        await Diagnostics.log('TTS ready ($lang)');
      } else {
        _lastErrorCode = 'tts_init_failed';
        await Diagnostics.log('TTS init returned false ($lang)');
      }
    } on MissingPluginException {
      _lastErrorCode = 'missing_plugin';
      await Diagnostics.log('TTS unavailable: missing plugin');
    } on PlatformException catch (error) {
      _lastErrorCode = error.code;
      await Diagnostics.log(
        'TTS init failed ($lang): ${error.code} ${error.message} ${error.details}',
      );
    } on TimeoutException {
      _lastErrorCode = 'tts_init_timeout';
      await Diagnostics.log('TTS init timed out ($lang)');
    }
    return isReady;
  }

  /// 初始化后播报一段文字，返回是否成功提交给引擎；失败不影响记录。
  /// [flush] 为 true 时打断上一条未播完的内容（倒计时逐字播报用），
  /// false 则排队接续（每公里成绩接在上一条之后）。
  static Future<bool> speak(String text, {bool flush = false}) async {
    if (text.trim().isEmpty) return false;
    final generation = _speechGeneration;
    if (!await ensureInitialized()) {
      // 播报请求被跳过的原因落日志：这是"没有声音"问题的关键线索。
      await Diagnostics.log('TTS speak skipped (not ready): $text');
      return false;
    }
    // 关闭播报时，连同仍在等待初始化的请求一起取消。
    if (generation != _speechGeneration) return false;
    try {
      final spoken = await _channel.invokeMethod<bool>(
        'speak',
        <String, Object?>{'text': text, 'flush': flush},
      );
      if (spoken != true) {
        _ready = false;
        _lastErrorCode = 'tts_speak_failed';
        await Diagnostics.log('TTS speak rejected: $text');
      } else {
        // 原生返回 SUCCESS 仅代表入队；实际播放错误由原生回调另行记录。
        await Diagnostics.log('TTS speak queued: $text');
      }
      return spoken == true;
    } on MissingPluginException {
      _ready = false;
      _lastErrorCode = 'missing_plugin';
      await Diagnostics.log('TTS speak unavailable: missing plugin');
    } on PlatformException catch (error) {
      // 播报失败不影响记录。
      _ready = false;
      _lastErrorCode = error.code;
      await Diagnostics.log(
        'TTS speak error: ${error.code} ${error.message} ${error.details}',
      );
    }
    return false;
  }

  static Future<void> stop() async {
    _speechGeneration++;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      _ready = false;
    } on PlatformException {
      // 静默。
    }
  }

  /// 测试钩子：重置初始化状态。
  static void resetForTest() {
    _speechGeneration++;
    _ready = false;
    _readyLanguage = null;
    _initializing = null;
    _initializingLanguage = null;
    _lastErrorCode = null;
  }
}
