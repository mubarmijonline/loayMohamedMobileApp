package com.example.loay_mohamed_elearning

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Host activity.
 *
 * Screen-capture protection is applied here, app-wide, from the first frame —
 * see [onCreate]. The Dart side (lib/core/security/screen_guard.dart) can
 * observe and query it but never toggles it.
 */
class MainActivity : FlutterActivity() {
    // Channel names mirror lib/core/security/screen_guard.dart.
    private val methodChannelName = "app/playback_security"
    private val eventChannelName = "app/playback_security/events"

    private var eventSink: EventChannel.EventSink? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var observing = false
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Android 14+ screenshot telemetry. Null below API 34. */
    private var screenCaptureCallback: Any? = null

    /**
     * Applies FLAG_SECURE before the first frame exists.
     *
     * This is deliberately app-wide and permanent rather than toggled around
     * the player. A per-screen toggle leaves a window where the flag is off,
     * and that window is exactly when someone screenshots — during the
     * transition into the video. The cost is that the whole app is
     * unscreenshottable, which is the intended trade.
     *
     * FLAG_SECURE blocks screenshots, blacks the app out of screen recordings
     * and casts, and hides content in the recents/app-switcher preview.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> { startObserving(); result.success(null) }
                    "disable" -> { stopObserving(); result.success(null) }
                    // The runtime integrity check. Reports whether FLAG_SECURE
                    // is actually set on the window right now, rather than
                    // whether we asked for it — a silent failure here is the
                    // whole risk.
                    "isProtected" -> result.success(isFlagSecureSet())
                    // Android refuses the capture at the OS layer, so there is
                    // never anything in progress to report.
                    "isCaptured" -> result.success(false)
                    "hasExternalDisplay" -> result.success(hasExternalDisplay())
                    "isDeviceCompromised" -> result.success(isRooted())
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            })
    }

    /** True when FLAG_SECURE is genuinely set on this window. */
    private fun isFlagSecureSet(): Boolean =
        (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0

    private fun startObserving() {
        if (observing) return
        observing = true

        // Re-assert the flag. It is set in onCreate and nothing in this app
        // clears it, but a future plugin might, and the player is the one
        // place where being wrong is expensive.
        runOnUiThread {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }

        registerScreenshotTelemetry()

        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return
        val listener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) {
                emit("external_display_detected", mapOf("count" to dm.displays.size))
            }

            override fun onDisplayRemoved(displayId: Int) {
                if (dm.displays.size <= 1) {
                    emit("external_display_disconnected")
                } else {
                    emit("external_display_detected", mapOf("count" to dm.displays.size))
                }
            }

            override fun onDisplayChanged(displayId: Int) {
                // Rotation and refresh-rate changes are not surveillance events.
            }
        }
        dm.registerDisplayListener(listener, mainHandler)
        displayListener = listener

        // Snapshot the current state so the player locks down on open rather
        // than waiting for a change that already happened.
        if (hasExternalDisplay()) {
            emit("external_display_detected", mapOf("count" to dm.displays.size))
        }
    }

    /**
     * Android 14 (API 34) added a screenshot-detection callback.
     *
     * This is telemetry only: FLAG_SECURE already blocks the capture, so in
     * normal operation the callback should never fire. It is wired anyway so
     * that if the flag is ever lost we find out from the event queue instead
     * of from a leaked video. Registered reflectively so the app still builds
     * against SDKs below 34, and wrapped because the API needs the
     * DETECT_SCREEN_CAPTURE permission and throws without it.
     */
    private fun registerScreenshotTelemetry() {
        if (Build.VERSION.SDK_INT < 34 || screenCaptureCallback != null) return
        try {
            val callbackClass = Class.forName("android.app.Activity\$ScreenCaptureCallback")
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                callbackClass.classLoader,
                arrayOf(callbackClass),
            ) { _, method, _ ->
                if (method.name == "onScreenCaptured") {
                    emit("screenshot", mapOf("platform" to "android"))
                }
                null
            }
            // Post back on the main looper rather than Activity.mainExecutor,
            // which needs API 28 and an extra lint gate for no benefit here.
            val executor = java.util.concurrent.Executor { mainHandler.post(it) }
            javaClass.getMethod(
                "registerScreenCaptureCallback",
                java.util.concurrent.Executor::class.java,
                callbackClass,
            ).invoke(this, executor, proxy)
            screenCaptureCallback = proxy
        } catch (_: Throwable) {
            // Missing permission, or an OEM without the API. Not fatal —
            // FLAG_SECURE is the actual protection, this was only telemetry.
        }
    }

    private fun unregisterScreenshotTelemetry() {
        val cb = screenCaptureCallback ?: return
        try {
            val callbackClass = Class.forName("android.app.Activity\$ScreenCaptureCallback")
            javaClass.getMethod("unregisterScreenCaptureCallback", callbackClass)
                .invoke(this, cb)
        } catch (_: Throwable) {
            // Nothing to do.
        }
        screenCaptureCallback = null
    }

    private fun stopObserving() {
        if (!observing) return
        observing = false
        // NOTE: FLAG_SECURE is intentionally NOT cleared. See onCreate.
        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        displayListener?.let { dm?.unregisterDisplayListener(it) }
        displayListener = null
        unregisterScreenshotTelemetry()
    }

    private fun hasExternalDisplay(): Boolean {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return false
        return dm.displays.count { it.displayId != Display.DEFAULT_DISPLAY } > 0
    }

    /**
     * Heuristic root detection.
     *
     * On a rooted device FLAG_SECURE can be patched out and the WebView can be
     * instrumented, so the Dart side refuses video playback when this returns
     * true. A determined attacker with a hooking framework passes this; it
     * raises the cost rather than making the device trustworthy.
     */
    private fun isRooted(): Boolean {
        // 1. Test-keys build — a debug/AOSP ROM rather than a signed release.
        val tags = Build.TAGS
        if (tags != null && tags.contains("test-keys")) return true

        // 2. su and common root-manager binaries on disk.
        val binaries = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
            "/system/app/Superuser.apk", "/data/local/xbin/su",
            "/data/local/bin/su", "/system/sd/xbin/su",
            "/system/bin/failsafe/su", "/data/local/su", "/vendor/bin/su",
            "/system/bin/magisk", "/sbin/magisk", "/data/adb/magisk",
            "/data/adb/modules",
        )
        if (binaries.any { runCatching { File(it).exists() }.getOrDefault(false) }) return true

        // 3. Root manager packages installed.
        val packages = arrayOf(
            "com.topjohnwu.magisk", "eu.chainfire.supersu",
            "com.noshufou.android.su", "com.koushikdutta.superuser",
            "com.thirdparty.superuser", "com.yellowes.su",
        )
        val pm = packageManager
        for (p in packages) {
            try {
                pm.getPackageInfo(p, 0)
                return true
            } catch (_: Exception) {
                // Not installed — expected for a clean device.
            }
        }

        // 4. Normally read-only paths that are writable.
        val readOnly = arrayOf("/system", "/system/bin", "/vendor", "/etc")
        if (readOnly.any { runCatching { File(it).canWrite() }.getOrDefault(false) }) return true

        // 5. `which su` resolves.
        return runCatching {
            val proc = Runtime.getRuntime().exec(arrayOf("which", "su"))
            val found = proc.inputStream.bufferedReader().readLine() != null
            proc.destroy()
            found
        }.getOrDefault(false)
    }

    /**
     * Emits on the event channel.
     *
     * The key MUST be `event`. The Dart side keys on it, and an earlier
     * version of this file sent `type`, which meant every capture event was
     * silently filtered out and the stream never delivered anything.
     */
    private fun emit(event: String, extra: Map<String, Any?> = emptyMap()) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any?>(extra.size + 1)
        payload["event"] = event
        payload.putAll(extra)
        mainHandler.post { sink.success(payload) }
    }

    override fun onDestroy() {
        stopObserving()
        super.onDestroy()
    }
}
