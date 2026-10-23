package com.runtrail.runtrail

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsInitialized = false
    private var ttsInitializing = false
    private var ttsGeneration = 0
    private val ttsHandler = Handler(Looper.getMainLooper())
    private var ttsTimeout: Runnable? = null
    private lateinit var ttsChannel: MethodChannel
    private val ttsInitResults = mutableListOf<MethodChannel.Result>()
    private var ttsLangTag = "zh-CN"

    // 播报期间压低其他应用音量：申请 AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK，
    // 计数入队未播完的播报，全部结束后归还焦点让音乐恢复音量。
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private val legacyFocusListener = AudioManager.OnAudioFocusChangeListener { }
    private var ttsFocusUtterances = 0

    private var filePickResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 启用全面屏/沉浸式状态栏，让 Flutter 内容可绘制到系统栏下方。
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LauncherIconManager.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        AiCredentialsStore.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        // 跑步保活通道：启动/停止前台服务（见 TrackingForegroundService）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runtrail/background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        ensureNotificationPermission()
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, TrackingForegroundService::class.java),
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, TrackingForegroundService::class.java))
                        result.success(null)
                    }
                    "notiPermission" -> {
                        val granted = Build.VERSION.SDK_INT < 33 ||
                            ContextCompat.checkSelfPermission(
                                this, Manifest.permission.POST_NOTIFICATIONS,
                            ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }
                    "openNotiSettings" -> {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        startActivity(intent)
                        result.success(null)
                    }
                    "update" -> {
                        val text = call.argument<String>("text")
                        if (!text.isNullOrBlank()) {
                            TrackingForegroundService.update(this, text)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runtrail/training_reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "replace" -> {
                        val entries = call.argument<List<Map<String, Any?>>>("entries") ?: emptyList()
                        TrainingAlarms.replace(this, entries)
                        ensureNotificationPermission()
                        result.success(true)
                    }
                    "cancel" -> {
                        TrainingAlarms.cancel(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 语音播报通道：系统 TextToSpeech。
        ttsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runtrail/tts")
        ttsChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> {
                        val lang = call.argument<String>("lang") ?: "zh-CN"
                        initTts(lang, result)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text")
                        val flush = call.argument<Boolean>("flush") == true
                        val engine = tts
                        if (!text.isNullOrBlank() && ttsReady && engine != null) {
                            val id = "runtrail-${System.currentTimeMillis()}"
                            val queue = if (flush) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                            // 播报音量跟随媒体音量，但设上下限：KEY_PARAM_VOLUME
                            // 是相对音量（与媒体音量相乘），纯按比例缩放会让实际
                            // 响度只剩比例的平方（媒体 60% → 36%），跑步中听不清。
                            // 下限 0.6 保证清晰可闻，上限 0.9 防止外放/耳机炸耳。
                            val params = android.os.Bundle()
                            val am = audioManager
                                ?: getSystemService(AudioManager::class.java)?.also { audioManager = it }
                            if (am != null) {
                                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                                val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                                val ratio = if (max > 0) cur.toFloat() / max else 1f
                                params.putFloat(
                                    TextToSpeech.Engine.KEY_PARAM_VOLUME,
                                    ratio.coerceIn(0.6f, 0.9f),
                                )
                            }
                            val status = engine.speak(text, queue, params, id)
                            if (status == TextToSpeech.SUCCESS) {
                                if (ttsFocusUtterances++ == 0) requestSpeechAudioFocus()
                                result.success(true)
                            } else {
                                releaseTts()
                                result.error("tts_speak_failed", "Speech request rejected", status)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        tts?.stop()
                        // stop() 会丢弃排队中的播报，这类播报不会再回调 onDone。
                        abandonSpeechAudioFocus()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // 备份恢复的文件选择通道（SAF）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "runtrail/filepicker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJson" -> {
                        if (filePickResult != null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        filePickResult = result
                        // SAF 优先；精简 ROM 上 DocumentsUI 可能缺失/被禁用，
                        // 此时降级 ACTION_GET_CONTENT（文件管理器等可响应）。
                        // 启动失败必须清空 pending result，否则防重入分支会让
                        // 之后每次选择都直接失败（导入功能永久失效）。
                        val safIntent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        val resolveSaf = safIntent.resolveActivity(packageManager)
                        val intent = if (resolveSaf != null) {
                            safIntent
                        } else {
                            Intent(Intent.ACTION_GET_CONTENT).apply { type = "*/*" }
                        }
                        try {
                            startActivityForResult(intent, REQUEST_PICK_JSON)
                        } catch (e: Exception) {
                            filePickResult = null
                            result.error("pick_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun initTts(lang: String, result: MethodChannel.Result) {
        ttsLangTag = lang
        ttsInitResults.add(result)
        if (ttsInitialized) {
            configureTts()
            return
        }
        if (ttsInitializing) return
        ttsInitializing = true
        val generation = ++ttsGeneration
        val timeout = Runnable {
            if (generation == ttsGeneration && ttsInitializing) {
                releaseTts()
                finishTtsInit("tts_init_timeout", "Speech engine initialization timed out")
            }
        }
        ttsTimeout = timeout
        ttsHandler.postDelayed(timeout, 10_000)
        try {
            tts = TextToSpeech(applicationContext) { status ->
                // 部分引擎会在构造函数返回前回调；排到主线程后再使用已赋值的实例。
                ttsHandler.post {
                    if (generation != ttsGeneration || !ttsInitializing) return@post
                    if (status == TextToSpeech.SUCCESS) {
                        ttsInitialized = true
                        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                            override fun onStart(utteranceId: String?) {}
                            override fun onDone(utteranceId: String?) {
                                ttsHandler.post {
                                    if (generation != ttsGeneration) return@post
                                    finishSpeechUtterance()
                                }
                            }
                            @Deprecated("Android compatibility callback")
                            override fun onError(utteranceId: String?) {
                                onError(utteranceId, TextToSpeech.ERROR)
                            }
                            override fun onError(utteranceId: String?, errorCode: Int) {
                                ttsHandler.post {
                                    if (generation != ttsGeneration) return@post
                                    releaseTts()
                                    ttsChannel.invokeMethod("error", mapOf(
                                        "utteranceId" to utteranceId,
                                        "code" to errorCode,
                                        "lang" to ttsLangTag,
                                    ))
                                }
                            }
                        })
                        configureTts()
                    } else {
                        releaseTts()
                        finishTtsInit("tts_init_failed", "Speech engine initialization failed: $status")
                    }
                }
            }
        } catch (error: Exception) {
            releaseTts()
            finishTtsInit("tts_init_failed", error.message)
        }
    }

    private fun configureTts() {
        ttsReady = false
        try {
            val engine = tts ?: throw IllegalStateException("Speech engine is unavailable")
            val status = engine.setLanguage(Locale.forLanguageTag(ttsLangTag))
            if (status < TextToSpeech.LANG_AVAILABLE) {
                val code = when (status) {
                    TextToSpeech.LANG_MISSING_DATA -> "tts_language_missing_data"
                    TextToSpeech.LANG_NOT_SUPPORTED -> "tts_language_not_supported"
                    else -> "tts_language_failed"
                }
                finishTtsInit(code, "Language $ttsLangTag unavailable: $status")
                return
            }
            val audioStatus = engine.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            if (audioStatus != TextToSpeech.SUCCESS) {
                releaseTts()
                finishTtsInit("tts_audio_failed", "Cannot configure speech audio: $audioStatus")
                return
            }
            ttsReady = true
            finishTtsInit()
        } catch (error: Exception) {
            releaseTts()
            finishTtsInit("tts_init_failed", error.message)
        }
    }

    private fun finishTtsInit(code: String? = null, message: String? = null) {
        ttsTimeout?.let(ttsHandler::removeCallbacks)
        ttsTimeout = null
        ttsInitializing = false
        val pending = ttsInitResults.toList()
        ttsInitResults.clear()
        for (result in pending) {
            if (code == null) result.success(ttsReady)
            else result.error(code, message, mapOf("lang" to ttsLangTag))
        }
    }

    private fun releaseTts() {
        ++ttsGeneration
        ttsTimeout?.let(ttsHandler::removeCallbacks)
        ttsTimeout = null
        ttsReady = false
        ttsInitialized = false
        ttsInitializing = false
        abandonSpeechAudioFocus()
        tts?.shutdown()
        tts = null
    }

    /** 申请音频焦点（不中断播放、压低其他应用音量），播报入队时调用。 */
    private fun requestSpeechAudioFocus() {
        val manager = audioManager
            ?: getSystemService(AudioManager::class.java)?.also { audioManager = it }
            ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            val request = audioFocusRequest
                ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setOnAudioFocusChangeListener(legacyFocusListener)
                    .build()
                    .also { audioFocusRequest = it }
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                legacyFocusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }
    }

    /** 一条播报播完：所有队列清空后归还焦点，其他应用恢复音量。 */
    private fun finishSpeechUtterance() {
        if (ttsFocusUtterances == 0) return
        ttsFocusUtterances--
        if (ttsFocusUtterances == 0) abandonSpeechAudioFocus()
    }

    private fun abandonSpeechAudioFocus() {
        ttsFocusUtterances = 0
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(legacyFocusListener)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_JSON) return
        val pending = filePickResult
        filePickResult = null
        if (pending == null) return
        val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) {
            pending.success(null)
            return
        }
        try {
            // SAF 返回的内容流拷贝到缓存目录，Dart 侧直接按路径读取。
            val cacheFile = File(cacheDir, "runtrail_import_${System.currentTimeMillis()}.json")
            contentResolver.openInputStream(uri)?.use { input ->
                cacheFile.outputStream().use { output -> input.copyTo(output) }
            } ?: throw IllegalStateException("无法读取所选文件")
            pending.success(cacheFile.absolutePath)
        } catch (e: Exception) {
            pending.error("pick_failed", e.message, null)
        }
    }

    override fun onDestroy() {
        releaseTts()
        finishTtsInit("tts_destroyed", "Activity destroyed during speech initialization")
        super.onDestroy()
    }

    /** Android 13+ 前台通知需要运行时通知权限，未授予时服务仍可用（仅通知不显示）。 */
    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    companion object {
        private const val REQUEST_PICK_JSON = 4201
    }
}
