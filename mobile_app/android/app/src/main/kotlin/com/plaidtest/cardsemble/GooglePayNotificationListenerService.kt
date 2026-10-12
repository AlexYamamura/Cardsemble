package com.plaidtest.cardsemble

import android.app.Notification
import android.content.Context
import android.os.Environment
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

class GooglePayNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val TAG = "GooglePayCapture"
        private const val GOOGLE_WALLET_PACKAGE = "com.google.android.apps.walletnfcrel"
        private const val PREFS = "google_pay_capture"
        private const val SEEN_EVENTS = "seen_notification_fingerprints"
        private const val MAX_SEEN_EVENTS = 500
        private val executor = Executors.newSingleThreadExecutor()
        private val amountPattern = Regex(
            """([$€£¥₹])\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)|""" +
                """([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(USD|EUR|GBP|CAD|AUD|JPY)""",
            RegexOption.IGNORE_CASE,
        )
        private val cardPattern = Regex(
            """\b(Visa|Mastercard|Master Card|American Express|Amex|Discover)\b""",
            RegexOption.IGNORE_CASE,
        )
        private val lastFourPattern = Regex("""(?:[•*xX]\s*){2,}(\d{4})\b""")
    }

    override fun onNotificationPosted(statusBarNotification: StatusBarNotification) {
        val isTestNotification =
            statusBarNotification.packageName == packageName &&
            statusBarNotification.id == MainActivity.TEST_NOTIFICATION_ID
        val isGoogleWallet = statusBarNotification.packageName == GOOGLE_WALLET_PACKAGE
        if (!isTestNotification && !isGoogleWallet) return
        val credentials = try {
            CaptureCredentialStore.credentials(applicationContext)
        } catch (error: Exception) {
            Log.e(TAG, "Could not read the protected capture credential.", error)
            return
        } ?: return
        val notification = statusBarNotification.notification ?: return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()
            ?.trim()
            .orEmpty()
        val text = sequenceOf(
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
        )
            .filterNotNull()
            .map(String::trim)
            .firstOrNull(String::isNotEmpty)
            .orEmpty()

        if (title.isBlank() || text.isBlank()) return
        val transaction = parseTransaction(title, text) ?: return
        val postedAt = if (notification.`when` > 0L) {
            notification.`when`
        } else {
            statusBarNotification.postTime
        }
        val fingerprint = listOf(
            statusBarNotification.key,
            postedAt.toString(),
            transaction.merchant,
            transaction.amount,
            transaction.currency,
        ).joinToString("|")

        // Log parsed transaction to file for testing
        logParsedTransaction(transaction, postedAt, title, text)

        executor.execute {
            if (wasAlreadySent(fingerprint)) return@execute
            if (sendEvent(credentials.first, credentials.second, transaction, postedAt)) {
                rememberSent(fingerprint)
            }
        }
    }

    private fun parseTransaction(title: String, text: String): ParsedTransaction? {
        val match = amountPattern.find(text) ?: return null
        val amountValue = match.groups[2]?.value ?: match.groups[3]?.value ?: return null
        val currency = when (match.groups[1]?.value) {
            "$" -> "USD"
            "€" -> "EUR"
            "£" -> "GBP"
            "¥" -> "JPY"
            "₹" -> "INR"
            else -> match.groups[4]?.value?.uppercase(Locale.ROOT) ?: return null
        }
        val amount = amountValue.replace(",", "").toBigDecimalOrNull() ?: return null
        if (amount <= java.math.BigDecimal.ZERO) return null

        val network = cardPattern.find(text)?.value?.replace(" ", "") ?: "Google Pay"
        val lastFour = lastFourPattern.find(text)?.groupValues?.get(1)
        val cardLabel = if (lastFour == null) network else "$network ending $lastFour"
        return ParsedTransaction(
            merchant = title.take(200),
            amount = amount.setScale(2).toPlainString(),
            currency = currency,
            cardLabel = cardLabel.take(100),
        )
    }

    private fun sendEvent(
        apiUrl: String,
        deviceToken: String,
        transaction: ParsedTransaction,
        postedAt: Long,
    ): Boolean {
        var connection: HttpURLConnection? = null
        return try {
            val dateFormatter = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                Locale.US,
            ).apply { timeZone = TimeZone.getTimeZone("UTC") }
            val occurredAt = dateFormatter.format(Date(postedAt))
            val payload = JSONObject()
                .put("event_id", "android-google-pay-${java.util.UUID.randomUUID()}")
                .put("occurred_at", occurredAt)
                .put("amount", transaction.amount)
                .put("currency", transaction.currency)
                .put("merchant", transaction.merchant)
                .put("card_label", transaction.cardLabel)
                .put("payment_label", "google_pay_notification")

            connection = URL("$apiUrl/api/card-events").openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer $deviceToken")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { stream ->
                stream.write(payload.toString().toByteArray(Charsets.UTF_8))
            }
            val status = connection.responseCode
            if (status !in 200..299) {
                Log.w(TAG, "Card event upload failed with HTTP $status.")
                false
            } else {
                true
            }
        } catch (error: Exception) {
            Log.e(TAG, "Could not submit Google Pay notification.", error)
            false
        } finally {
            connection?.disconnect()
        }
    }

    private fun wasAlreadySent(fingerprint: String): Boolean {
        val seen = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getStringSet(SEEN_EVENTS, emptySet())
            .orEmpty()
        return fingerprint in seen
    }

    private fun rememberSent(fingerprint: String) {
        val preferences = getSharedPreferences(PREFS, MODE_PRIVATE)
        val seen = preferences.getStringSet(SEEN_EVENTS, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        seen.add(fingerprint)
        while (seen.size > MAX_SEEN_EVENTS) {
            seen.remove(seen.first())
        }
        preferences.edit().putStringSet(SEEN_EVENTS, seen).apply()
    }

    private fun logParsedTransaction(
        transaction: ParsedTransaction,
        postedAt: Long,
        rawTitle: String,
        rawText: String,
    ) {
        val dateFormatter = SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            Locale.US,
        ).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val occurredAt = dateFormatter.format(Date(postedAt))
        val logDateFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
        val logTimestamp = logDateFormatter.format(Date())

        val logEntry = JSONObject().apply {
            put("timestamp", logTimestamp)
            put("occurred_at", occurredAt)
            put("raw_title", rawTitle)
            put("raw_text", rawText)
            put("merchant", transaction.merchant)
            put("amount", transaction.amount)
            put("currency", transaction.currency)
            put("card_label", transaction.cardLabel)
        }.toString()

        try {
            val dir = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
            val file = File(dir, "google_pay_capture_log.jsonl")
            FileWriter(file, true).use { writer ->
                writer.write(logEntry)
                writer.write("\n")
            }
            Log.d(TAG, "Logged parsed transaction to file: ${transaction.merchant} ${transaction.amount} ${transaction.currency}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write transaction log", e)
        }
    }

    private data class ParsedTransaction(
        val merchant: String,
        val amount: String,
        val currency: String,
        val cardLabel: String,
    )
}
