package com.plaidtest.cardsemble

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.plaidtest.cardsemble/google_pay_capture"
        internal const val TEST_NOTIFICATION_ID = 99999
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val apiUrl = call.argument<String>("apiUrl")
                    val deviceToken = call.argument<String>("deviceToken")
                    val deviceId = call.argument<String>("deviceId")
                    if (apiUrl.isNullOrBlank() ||
                        deviceToken.isNullOrBlank() ||
                        deviceId.isNullOrBlank()
                    ) {
                        result.error("invalid_config", "Missing capture credentials.", null)
                    } else {
                        try {
                            CaptureCredentialStore.save(this, apiUrl, deviceToken, deviceId)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("secure_storage_error", error.message, null)
                        }
                    }
                }

                "clear" -> {
                    try {
                        CaptureCredentialStore.clear(this)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("secure_storage_error", error.message, null)
                    }
                }

                "isConfigured" -> result.success(CaptureCredentialStore.isConfigured(this))
                "deviceId" -> result.success(CaptureCredentialStore.deviceId(this))
                "hasNotificationAccess" -> result.success(hasNotificationAccess())
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }

                "sendTestNotification" -> {
                    val permission = "android.permission.POST_NOTIFICATIONS"
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(permission) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        pendingTestNotification = true
                        requestPermissions(arrayOf(permission), 1001)
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    _postTestNotification()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private var pendingTestNotification = false

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001 && pendingTestNotification) {
            pendingTestNotification = false
            if (grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                _postTestNotification()
            }
        }
    }

    private fun _postTestNotification() {
        val prefs = getSharedPreferences("google_pay_capture", Context.MODE_PRIVATE)
        val seenKey = "seen_notification_fingerprints"
        val seen = prefs.getStringSet(seenKey, emptySet()) ?: emptySet()
        if (seen.isNotEmpty()) {
            prefs.edit().putStringSet(seenKey, emptySet()).apply()
        }

        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                "cardsemble_debug",
                "Cardsemble debug",
                android.app.NotificationManager.IMPORTANCE_HIGH,
            )
            mgr.createNotificationChannel(channel)
        }

        val whenMs = System.currentTimeMillis()
        val notification = NotificationCompat.Builder(this, "cardsemble_debug")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("TEST")
            .setWhen(whenMs)
            .setTicker("Google Pay")
            .setContentText("Google Pay purchase  \$10.01  AAA Visa Signature ..XXXX")
            .build()
        mgr.notify(TEST_NOTIFICATION_ID, notification)
    }

    private fun hasNotificationAccess(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val component = "${packageName}/${GooglePayNotificationListenerService::class.java.name}"
        return enabledListeners.split(':').any { Uri.decode(it) == component }
    }
}
