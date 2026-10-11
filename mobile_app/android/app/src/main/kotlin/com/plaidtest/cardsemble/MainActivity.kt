package com.plaidtest.cardsemble

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.plaidtest.cardsemble/google_pay_capture"
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

                else -> result.notImplemented()
            }
        }
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
