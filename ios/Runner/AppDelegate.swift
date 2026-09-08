import Flutter
// `_dyld_image_count` / `_dyld_get_image_name`, used by JailbreakCheck to spot
// injected tweak dylibs. Only referenced in the non-simulator branch, so a
// simulator build compiles without this import and a device build does not.
import MachO
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
      securityBridge = PlaybackSecurityBridge(
        messenger: controller.binaryMessenger,
        window: window
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: App-switcher snapshot
  //
  // The OS snapshots the window for the multitasking card when the app leaves
  // the foreground. Without a cover that snapshot is a frame of the lesson.

  override func applicationWillResignActive(_ application: UIApplication) {
    securityBridge?.coverForAppSwitcher()
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    securityBridge?.uncoverFromAppSwitcher()
    super.applicationDidBecomeActive(application)
  }
}

// MARK: - Playback security bridge (channel: app/playback_security)
//
// Mirrors lib/core/security/screen_guard.dart. The Dart side owns policy;
// this owns the platform mechanics.
//
// What iOS can actually do, stated plainly (see lib/core/security/README.md):
//
//   * It CANNOT block a screenshot, and it cannot blank one either. The
//     frame-blanking trick was tried here and crashed the app on launch —
//     see the note at the top of SecureCanvas.swift before reaching for it.
//   * It CAN detect a recording or mirror (`UIScreen.isCaptured`) and a
//     screenshot after the fact (`userDidTakeScreenshotNotification`).
//   * A jailbroken device defeats all of it, and nothing stops a second phone
//     pointed at the screen. Hence the watermark.
final class PlaybackSecurityBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var observing = false

  private weak var window: UIWindow?
  private let appSwitcherCover = AppSwitcherCover()

  init(messenger: FlutterBinaryMessenger, window: UIWindow?) {
    self.window = window
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
      // The runtime integrity check.
      //
      // On iOS this reports whether the *detection* layer is genuinely armed —
      // the capture/screenshot/display observers are installed and the
      // app-switcher cover is wired. It deliberately does NOT claim captured
      // frames are blanked, because iOS cannot do that (see SecureCanvas.swift
      // for the removed attempt and why).
      //
      // Reporting false here would block video playback entirely on iOS, which
      // is the wrong trade: the watermark plus detection is the real iOS
      // protection, and withholding lessons does not make it stronger.
      case "isProtected":
        result(self.observing)
      case "isCaptured":
        result(UIScreen.main.isCaptured || UIScreen.screens.count > 1)
      case "hasExternalDisplay":
        result(UIScreen.screens.count > 1)
      case "isDeviceCompromised":
        result(JailbreakCheck.isJailbroken())
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

  // MARK: App-switcher cover

  func coverForAppSwitcher() {
    guard let window = window else { return }
    appSwitcherCover.show(in: window)
  }

  func uncoverFromAppSwitcher() {
    appSwitcherCover.hide()
  }

  // MARK: Enable / disable

  private func enable() {
    guard !observing else { return }
    observing = true

    // Detection layers. There is no frame-blanking layer on iOS — see the
    // note at the top of SecureCanvas.swift.
    if window == nil {
      emit("protection_unavailable", extra: ["reason": "no window"])
    }

    let nc = NotificationCenter.default
    nc.addObserver(
      self,
      selector: #selector(handleScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    nc.addObserver(
      self,
      selector: #selector(handleCapturedChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
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

    // Snapshot the current state, so a player opened *during* an active
    // recording locks down immediately instead of waiting for a change.
    if UIScreen.main.isCaptured {
      emit("recording_detected", extra: ["state": "captured"])
    }
    if UIScreen.screens.count > 1 {
      emit("external_display_detected", extra: ["count": UIScreen.screens.count])
    }
  }

  private func disable() {
    guard observing else { return }
    observing = false
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: Handlers

  @objc private func handleScreenshot() {
    // The image already exists. This cannot be undone — it is reported so the
    // event is attributable, and so repeat offences can be escalated.
    emit("screenshot", extra: ["platform": "ios"])
  }

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

  /// Emits on the event channel.
  ///
  /// The key MUST be `event`. The Dart side keys on it, and an earlier version
  /// of this file sent `type`, which meant every capture event was silently
  /// filtered out and the stream never delivered anything.
  private func emit(_ event: String, extra: [String: Any] = [:]) {
    guard let sink = sink else { return }
    var payload: [String: Any] = ["event": event]
    for (k, v) in extra { payload[k] = v }
    DispatchQueue.main.async { sink(payload) }
  }
}

// MARK: - Jailbreak detection

/// Heuristic jailbreak detection.
///
/// On a jailbroken device the secure canvas can be hooked out, so the Dart
/// side refuses video playback when this returns true. A determined attacker
/// with a hooking framework passes this; it raises the cost rather than making
/// the device trustworthy.
enum JailbreakCheck {
  static func isJailbroken() -> Bool {
    #if targetEnvironment(simulator)
      // The simulator trips several of these by design.
      return false
    #else
      // 1. Jailbreak tooling on disk.
      let paths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
        "/usr/bin/ssh",
        "/var/jb",
      ]
      for path in paths where FileManager.default.fileExists(atPath: path) {
        return true
      }

      // 2. Can we open a package manager?
      if let url = URL(string: "cydia://package/com.example.package"),
         UIApplication.shared.canOpenURL(url) {
        return true
      }

      // 3. Can we write outside the sandbox? A stock device cannot.
      let probe = "/private/jailbreak_probe_\(UUID().uuidString).txt"
      do {
        try "probe".write(toFile: probe, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: probe)
        return true
      } catch {
        // Expected on a clean device.
      }

      // 4. Suspicious dynamic libraries loaded into the process.
      for i in 0..<_dyld_image_count() {
        guard let name = _dyld_get_image_name(i) else { continue }
        let path = String(cString: name)
        if path.contains("MobileSubstrate") || path.contains("TweakInject")
            || path.contains("libhooker") || path.contains("SubstrateLoader") {
          return true
        }
      }

      return false
    #endif
  }
}
