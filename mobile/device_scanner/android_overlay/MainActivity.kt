package com.casavino.device_scanner

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Adds a method channel so the Dart side can hold a Wi-Fi MulticastLock while
/// it runs mDNS/DNS-SD discovery. Without the lock, Android drops inbound
/// multicast and Bonjour comes back empty.
class MainActivity : FlutterActivity() {
    private val channelName = "device_scanner/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquire()
                        result.success(true)
                    }
                    "release" -> {
                        release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquire() {
        if (multicastLock == null) {
            val wifi =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("device_scanner").apply {
                setReferenceCounted(true)
            }
        }
        multicastLock?.acquire()
    }

    private fun release() {
        multicastLock?.let { if (it.isHeld) it.release() }
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }
}
