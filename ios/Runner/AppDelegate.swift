import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Keeps the native DSP exports alive through dead-code stripping so Dart's
    // DynamicLibrary.process() can resolve them in release builds.
    _ = aura_keep_symbols()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let screen = FlutterMethodChannel(
      name: "aurasync/screen",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    screen.setMethodCallHandler { call, result in
      if call.method == "keepAwake" {
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let launch = FlutterMethodChannel(
      name: "aurasync/launch",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    launch.setMethodCallHandler { call, result in
      if call.method == "initialMode" {
        result(LaunchShortcuts.shared.takePending())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    LaunchShortcuts.shared.channel = launch
    let voice = FlutterMethodChannel(
      name: "aurasync/voice",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    voice.setMethodCallHandler { [voiceRecorder] call, result in
      voiceRecorder.handle(call, result)
    }
  }

  private let voiceRecorder = VoiceCaptureHandler()
}

/// Home Screen quick actions (long-press menu on the app icon): SOS, Focus, Calm, Deep calm.
/// A cold start leaves the mode pending until Dart asks for it ("initialMode"); a tap while the
/// app is running is pushed straight to Dart ("launchMode").
final class LaunchShortcuts {
  static let shared = LaunchShortcuts()
  var channel: FlutterMethodChannel?
  private var pending: String?
  private static let modes: Set<String> = ["sos", "focus", "calm", "deep"]

  private func mode(for type: String) -> String? {
    guard let last = type.split(separator: ".").last else { return nil }
    let mode = String(last)
    return LaunchShortcuts.modes.contains(mode) ? mode : nil
  }

  /// App launched by the shortcut: remember it for Dart's first question.
  func recordColdStart(_ type: String) {
    pending = mode(for: type)
  }

  /// App already running: deliver now, or keep it pending if Dart is not listening yet.
  func deliver(_ type: String) {
    guard let mode = mode(for: type) else { return }
    if let channel = channel {
      channel.invokeMethod("launchMode", arguments: mode)
    } else {
      pending = mode
    }
  }

  func takePending() -> String? {
    defer { pending = nil }
    return pending
  }
}

/// Caregiver phrase capture: 16-bit mono PCM WAV in the temp directory, capped at 6 s.
/// The session category is switched to playAndRecord only while recording and restored
/// to .playback afterwards (the DSP output runs through an AudioQueue on that category).
final class VoiceCaptureHandler {
  private static let maxSeconds: TimeInterval = 6.0
  private static let sampleRate: Double = 48000
  private var recorder: AVAudioRecorder?
  private var url: URL?

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "start": start(result)
    case "stop": stop(result)
    case "cancel":
      teardown(deleteFile: true)
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermission(_ done: @escaping (Bool) -> Void) {
    let reply: (Bool) -> Void = { granted in DispatchQueue.main.async { done(granted) } }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: reply)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(reply)
    }
  }

  private func start(_ result: @escaping FlutterResult) {
    requestPermission { [weak self] granted in
      guard let self = self, granted else { return result(false) }
      self.teardown(deleteFile: true)
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("aura_voice_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
          AVFormatIDKey: Int(kAudioFormatLinearPCM),
          AVSampleRateKey: VoiceCaptureHandler.sampleRate,
          AVNumberOfChannelsKey: 1,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsBigEndianKey: false,
        ]
        let rec = try AVAudioRecorder(url: file, settings: settings)
        guard rec.prepareToRecord(), rec.record(forDuration: VoiceCaptureHandler.maxSeconds) else {
          self.restorePlayback()
          return result(false)
        }
        self.recorder = rec
        self.url = file
        result(true)
      } catch {
        self.restorePlayback()
        result(false)
      }
    }
  }

  private func stop(_ result: @escaping FlutterResult) {
    guard let rec = recorder, let file = url else {
      return result(FlutterError(code: "not_recording", message: "No active recording", details: nil))
    }
    rec.stop()
    recorder = nil
    url = nil
    restorePlayback()
    result(["path": file.path, "sampleRate": Int(VoiceCaptureHandler.sampleRate)])
  }

  private func teardown(deleteFile: Bool) {
    let hadRecorder = recorder != nil
    recorder?.stop()
    recorder = nil
    if deleteFile, let file = url { try? FileManager.default.removeItem(at: file) }
    url = nil
    if hadRecorder { restorePlayback() }
  }

  private func restorePlayback() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback)
    try? session.setActive(true)
  }
}
