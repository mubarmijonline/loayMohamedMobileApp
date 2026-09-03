import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var securityBridge: PlaybackSecurityBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      securityBridge = PlaybackSecurityBridge(messenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - Playback security bridge (channel: app/playback_security)
//
// Mirrors lib/core/security/playback_security.dart. Reports screenshot
// attempts, screen capture/mirroring state, and external display
// connect/disconnect events so the Cloudflare Stream player can react
// (pause + show a "Recording / mirroring detected" overlay).
//
// Hard DRM (FairPlay license session) is **not** wired here — the Dart side
// gates playback purely on the `fairplay`/`widevine` flags coming from
// `/api/student/videos/<id>/playback`. AVPlayer's `allowsExternalPlayback`
// cannot be globally forced from outside the `video_player` plugin, so it
// is documented as a known best-effort limitation.
final class PlaybackSecurityBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var enabled: Bool = false

  init(messenger: FlutterBinaryMessenger) {
    self.methodChannel = FlutterMethodChannel(
      name: "app/playback_security",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterEventChannel(
      name: "app/playback_security/events",
      binaryMessenger: messenger
    )
    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "enable":
        self.enable()
        result(nil)
      case "disable":
        self.disable()
        result(nil)
      case "isCaptured":
        if #available(iOS 11.0, *) {
          result(UIScreen.main.isCaptured)
        } else {
          result(false)
        }
      case "hasExternalDisplay":
        result(UIScreen.screens.count > 1)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    eventChannel.setStreamHandler(self)
  }

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.sink = nil
    return nil
  }

  // MARK: Enable / disable

  private func enable() {
    guard !enabled else { return }
    enabled = true

    let nc = NotificationCenter.default
    nc.addObserver(
      self,
      selector: #selector(handleScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    if #available(iOS 11.0, *) {
      nc.addObserver(
        self,
        selector: #selector(handleCapturedChanged),
        name: UIScreen.capturedDidChangeNotification,
        object: nil
      )
    }
    nc.addObserver(
      self,
      selector: #selector(handleScreenConnected),
      name: UIScreen.didConnectNotification,
      object: nil
    )
    nc.addObserver(
      self,
      selector: #selector(handleScreenDisconnected),
      name: UIScreen.didDisconnectNotification,
      object: nil
    )

    // Emit an immediate state snapshot so the player can lock down
    // playback if mirroring/capture is already active when the video opens.
    if #available(iOS 11.0, *), UIScreen.main.isCaptured {
      emit("recording_detected", extra: ["state": "captured"])
    }
    if UIScreen.screens.count > 1 {
      emit("external_display_detected", extra: ["count": UIScreen.screens.count])
    }
  }

  private func disable() {
    guard enabled else { return }
    enabled = false
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: Handlers

  @objc private func handleScreenshot() {
    emit("screenshot_attempt")
  }

  @available(iOS 11.0, *)
  @objc private func handleCapturedChanged() {
    if UIScreen.main.isCaptured {
      emit("recording_detected", extra: ["state": "captured"])
    } else {
      emit("capture_ended")
    }
  }

  @objc private func handleScreenConnected() {
    emit("external_display_detected", extra: ["count": UIScreen.screens.count])
  }

  @objc private func handleScreenDisconnected() {
    if UIScreen.screens.count <= 1 {
      emit("external_display_disconnected")
    } else {
      emit("external_display_detected", extra: ["count": UIScreen.screens.count])
    }
  }

  // MARK: Sink helper

  private func emit(_ type: String, extra: [String: Any] = [:]) {
    guard let sink = sink else { return }
    var payload: [String: Any] = ["type": type]
    for (k, v) in extra { payload[k] = v }
    DispatchQueue.main.async { sink(payload) }
  }
}
