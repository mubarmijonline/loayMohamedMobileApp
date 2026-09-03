package com.example.loay_mohamed_elearning

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Channel names mirror lib/core/security/playback_security.dart.
    private val methodChannelName = "app/playback_security"
    private val eventChannelName = "app/playback_security/events"

    private var eventSink: EventChannel.EventSink? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var enabled = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> { enableProtection(); result.success(null) }
                    "disable" -> { disableProtection(); result.success(null) }
                    "isCaptured" -> result.success(false) // Android exposes no public API; rely on FLAG_SECURE.
                    "hasExternalDisplay" -> result.success(hasExternalDisplay())
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

    private fun enableProtection() {
        if (enabled) return
        enabled = true

        // FLAG_SECURE is already applied app-wide by the secure_application
        // plugin; explicitly re-apply so the Cloudflare Stream player is
        // always protected even if a parent route had toggled it off.
        runOnUiThread {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }

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
                // No-op for now; rotation/refresh changes are not surveillance events.
            }
        }
        dm.registerDisplayListener(listener, mainHandler)
        displayListener = listener

        // Emit current snapshot so the player can lock down on open.
        if (hasExternalDisplay()) {
            emit("external_display_detected", mapOf("count" to dm.displays.size))
        }
    }

    private fun disableProtection() {
        if (!enabled) return
        enabled = false
        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        displayListener?.let { dm?.unregisterDisplayListener(it) }
        displayListener = null
    }

    private fun hasExternalDisplay(): Boolean {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return false
        return dm.displays.count { it.displayId != Display.DEFAULT_DISPLAY } > 0
    }

    private fun emit(type: String, extra: Map<String, Any?> = emptyMap()) {
        val sink = eventSink ?: return
        val payload = HashMap<String, Any?>(extra.size + 1)
        payload["type"] = type
        payload.putAll(extra)
        mainHandler.post { sink.success(payload) }
    }

    override fun onDestroy() {
        disableProtection()
        super.onDestroy()
    }
}
