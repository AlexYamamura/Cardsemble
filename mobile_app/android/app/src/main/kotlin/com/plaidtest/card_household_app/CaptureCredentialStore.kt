package com.plaidtest.card_household_app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal object CaptureCredentialStore {
    private const val PREFS = "google_pay_capture"
    private const val TOKEN = "encrypted_device_token"
    private const val API_URL = "api_url"
    private const val DEVICE_ID = "device_id"
    private const val KEY_ALIAS = "google_pay_capture_key"
    private const val ANDROID_KEY_STORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH = 128

    fun save(context: Context, apiUrl: String, deviceToken: String, deviceId: String) {
        val encryptedToken = encrypt(deviceToken)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(API_URL, apiUrl.trimEnd('/'))
            .putString(TOKEN, encryptedToken)
            .putString(DEVICE_ID, deviceId)
            .apply()
    }

    fun deviceId(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(DEVICE_ID, null)

    fun credentials(context: Context): Pair<String, String>? {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val apiUrl = preferences.getString(API_URL, null) ?: return null
        val encryptedToken = preferences.getString(TOKEN, null) ?: return null
        return apiUrl to decrypt(encryptedToken)
    }

    fun isConfigured(context: Context): Boolean = credentials(context) != null

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val data = Base64.encodeToString(ciphertext, Base64.NO_WRAP)
        return "$iv:$data"
    }

    private fun decrypt(encoded: String): String {
        val parts = encoded.split(':', limit = 2)
        require(parts.size == 2) { "Stored device credential is malformed." }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(GCM_TAG_LENGTH, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEY_STORE,
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }
}
