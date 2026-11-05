package com.casavino.device_scanner

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthNr
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Native method channels for things Flutter plugins don't cover:
///  * device_scanner/multicast — hold a Wi-Fi MulticastLock during mDNS.
///  * device_scanner/cell — read serving-cell / tower info via TelephonyManager.
class MainActivity : FlutterActivity() {
    private val multicastChannel = "device_scanner/multicast"
    private val cellChannel = "device_scanner/cell"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, multicastChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> { acquireLock(); result.success(true) }
                "release" -> { releaseLock(); result.success(true) }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, cellChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(cellInfo())
                else -> result.notImplemented()
            }
        }
    }

    private fun cellInfo(): HashMap<String, Any?> {
        val m = HashMap<String, Any?>()
        try {
            val tm = applicationContext
                .getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            try { m["operator"] = tm.networkOperatorName } catch (_: Exception) {}
            try { m["mccMnc"] = tm.networkOperator } catch (_: Exception) {}
            try { m["sim"] = tm.simOperatorName } catch (_: Exception) {}
            try { m["networkType"] = networkTypeName(tm.dataNetworkType) } catch (_: Exception) {}

            val cells = ArrayList<HashMap<String, Any?>>()
            try {
                for (ci in tm.allCellInfo ?: emptyList()) {
                    if (!ci.isRegistered) continue
                    val c = HashMap<String, Any?>()
                    when (ci) {
                        is CellInfoLte -> {
                            c["type"] = "LTE"
                            c["ci"] = ci.cellIdentity.ci
                            c["tac"] = ci.cellIdentity.tac
                            c["pci"] = ci.cellIdentity.pci
                            c["dbm"] = ci.cellSignalStrength.dbm
                        }
                        is CellInfoGsm -> {
                            c["type"] = "GSM"
                            c["cid"] = ci.cellIdentity.cid
                            c["lac"] = ci.cellIdentity.lac
                            c["dbm"] = ci.cellSignalStrength.dbm
                        }
                        is CellInfoWcdma -> {
                            c["type"] = "WCDMA"
                            c["cid"] = ci.cellIdentity.cid
                            c["dbm"] = ci.cellSignalStrength.dbm
                        }
                        else -> {
                            if (Build.VERSION.SDK_INT >= 29 && ci is CellInfoNr) {
                                c["type"] = "5G NR"
                                val ss = ci.cellSignalStrength
                                if (ss is CellSignalStrengthNr) c["dbm"] = ss.dbm
                            }
                        }
                    }
                    if (c.isNotEmpty()) cells.add(c)
                }
            } catch (e: Exception) {
                m["cellError"] = e.message
            }
            m["cells"] = cells
        } catch (e: Exception) {
            m["error"] = e.message
        }
        return m
    }

    private fun networkTypeName(t: Int): String = when (t) {
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_NR -> "5G NR"
        TelephonyManager.NETWORK_TYPE_HSPAP,
        TelephonyManager.NETWORK_TYPE_HSPA,
        TelephonyManager.NETWORK_TYPE_UMTS -> "3G"
        TelephonyManager.NETWORK_TYPE_EDGE,
        TelephonyManager.NETWORK_TYPE_GPRS -> "2G"
        TelephonyManager.NETWORK_TYPE_UNKNOWN -> "unknown"
        else -> "type $t"
    }

    private fun acquireLock() {
        if (multicastLock == null) {
            val wifi =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val lock = wifi.createMulticastLock("device_scanner")
            lock.setReferenceCounted(true)
            multicastLock = lock
        }
        multicastLock?.acquire()
    }

    private fun releaseLock() {
        val lock = multicastLock
        if (lock != null && lock.isHeld) {
            lock.release()
        }
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }
}
