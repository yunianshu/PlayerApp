package com.runtrail.runtrail

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileNotFoundException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device-local AES-GCM envelope; the encryption key never leaves Android Keystore. */
internal class AiCredentialsStore(context: Context) {
    private val file by lazy { AtomicFile(File(context.noBackupFilesDir, "ai_credentials.v1")) }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    private fun key(create: Boolean): SecretKey {
        check(Build.VERSION.SDK_INT >= 23)
        val store = keyStore()
        val existing = store.getKey(KEY_ALIAS, null)
        if (existing != null) return existing as SecretKey
        check(create) // A missing/inaccessible key is not silently regenerated on read.
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        ).setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    @Synchronized
    fun read(): String? {
        check(Build.VERSION.SDK_INT >= 23)
        val record = try {
            file.openRead().use { input ->
                // Bound malformed files before allocating; never return corrupt data as a key.
                val buffer = ByteArray(MAX_RECORD_BYTES + 1)
                var size = 0
                while (size < buffer.size) {
                    val count = input.read(buffer, size, buffer.size - size)
                    if (count == -1) break
                    size += count
                }
                check(size <= MAX_RECORD_BYTES)
                buffer.copyOf(size)
            }
        } catch (error: FileNotFoundException) {
            if (file.baseFile.exists()) throw error
            return null
        }
        check(record.size in MIN_RECORD_BYTES..MAX_RECORD_BYTES && record[0] == FORMAT_VERSION)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, record.copyOfRange(1, 13)))
        cipher.updateAAD(KEY_ALIAS.toByteArray(Charsets.UTF_8))
        val plaintext = cipher.doFinal(record, 13, record.size - 13)
        try {
            check(plaintext.size in 1..MAX_CREDENTIAL_BYTES)
            return Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(plaintext)).toString()
        } finally {
            plaintext.fill(0)
        }
    }

    @Synchronized
    fun write(value: String) {
        val plaintext = value.toByteArray(Charsets.UTF_8)
        try {
            require(plaintext.size in 1..MAX_CREDENTIAL_BYTES)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key(true))
            cipher.updateAAD(KEY_ALIAS.toByteArray(Charsets.UTF_8))
            check(cipher.iv.size == 12)
            val record = byteArrayOf(FORMAT_VERSION) + cipher.iv + cipher.doFinal(plaintext)
            val stream = file.startWrite()
            try {
                stream.write(record)
                file.finishWrite(stream)
            } catch (error: Exception) {
                file.failWrite(stream)
                throw error
            }
            // AtomicFile reports some disk errors internally. Verify the stored value
            // before Dart is allowed to claim that the credential was persisted.
            check(read() == value)
        } finally {
            plaintext.fill(0)
        }
    }

    @Synchronized
    fun delete() {
        check(Build.VERSION.SDK_INT >= 23)
        // Delete the key first so any leftover ciphertext is unusable if disk removal fails.
        keyStore().deleteEntry(KEY_ALIAS)
        file.delete()
        check(!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists() &&
            !File(file.baseFile.path + ".new").exists())
    }

    companion object {
        private const val KEY_ALIAS = "runtrail.ai_credentials.v1"
        private const val FORMAT_VERSION: Byte = 1
        private const val MAX_CREDENTIAL_BYTES = 1024
        private const val MIN_RECORD_BYTES = 1 + 12 + 16 + 1
        private const val MAX_RECORD_BYTES = 1 + 12 + 16 + MAX_CREDENTIAL_BYTES

        fun register(messenger: BinaryMessenger, context: Context) {
            val store = AiCredentialsStore(context)
            // Serial background queue keeps Keystore and disk work off the UI thread.
            MethodChannel(messenger, "runtrail/ai_credentials", StandardMethodCodec.INSTANCE,
                messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "read" -> result.success(store.read())
                        "write" -> {
                            val value = call.argument<Any?>("apiKey") as? String
                            if (value.isNullOrEmpty()) {
                                result.error("invalid_credentials", "Invalid credential data", null)
                            } else {
                                store.write(value)
                                result.success(null)
                            }
                        }
                        "delete" -> {
                            store.delete()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    // Do not log or return exceptions: they may contain credential data.
                    result.error("secure_storage_unavailable", "Secure credential storage is unavailable", null)
                }
            }
        }
    }
}
