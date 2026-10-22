import AVFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var ttsConfigured = false
  private var pickCompletion: ((String?) -> Void)?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "RunTrailNative").messenger()
    registerTtsChannel(messenger)
    registerFilePickChannel(messenger)
  }

  // MARK: - 语音播报（AVSpeechSynthesizer）

  private func registerTtsChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "runtrail/tts", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "delegate gone", details: nil))
        return
      }
      switch call.method {
      case "init":
        let lang = (call.arguments as? [String: Any])?["lang"] as? String ?? "zh-CN"
        result(self.configureTts(language: lang))
      case "speak":
        guard let args = call.arguments as? [String: Any],
          let text = args["text"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "text required", details: nil))
          return
        }
        if args["flush"] as? Bool == true {
          self.synthesizer.stopSpeaking(at: .immediate)
        }
        self.speak(text)
        result(true)
      case "stop":
        self.synthesizer.stopSpeaking(at: .immediate)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureTts(language: String) -> Bool {
    if !ttsConfigured {
      // 后台/锁屏播报需要 playback 类型的音频会话（配合 Info.plist 的 audio 后台模式）。
      try? AVAudioSession.sharedInstance().setCategory(
        .playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
      try? AVAudioSession.sharedInstance().setActive(true)
      ttsConfigured = true
    }
    if AVSpeechSynthesisVoice(language: language) == nil {
      // 目标语言无语音包时交给系统默认语音。
      return true
    }
    return true
  }

  private func speak(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    let lang = Locale.preferredLanguages.first?.hasPrefix("en") == true ? "en-US" : "zh-CN"
    utterance.voice = AVSpeechSynthesisVoice(language: lang)
    utterance.rate = max(0.42, AVSpeechUtteranceDefaultSpeechRate)
    synthesizer.stopSpeaking(at: .word)
    synthesizer.speak(utterance)
  }

  // MARK: - 备份恢复的文件选择（UIDocumentPickerViewController）

  private func registerFilePickChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "runtrail/filepicker", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickJson" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self else {
        result(nil)
        return
      }
      guard let root = self.rootViewController() else {
        result(nil)
        return
      }
      self.pickCompletion = result
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.json, UTType.data], asCopy: true)
      picker.allowsMultipleSelection = false
      picker.delegate = self
      root.present(picker, animated: true)
    }
  }

  private func rootViewController() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene,
        let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
      {
        return root
      }
    }
    return window?.rootViewController
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let completion = pickCompletion else { return }
    pickCompletion = nil
    // asCopy: true 时 URL 指向沙盒临时目录内的副本，可直接读取。
    if let url = urls.first {
      completion(url.path)
    } else {
      completion(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let completion = pickCompletion else { return }
    pickCompletion = nil
    completion(nil)
  }
}
