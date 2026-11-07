package com.lumioapps.lockeye

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * All the cryptography of the vault.
 *
 * - A PIN becomes a key with PBKDF2-HMAC-SHA256 ([kek]).
 * - Keys are wrapped with AES-256-GCM ([seal] / [open]).
 * - [pepperSeal] adds a second layer with a key that lives in the Android
 *   Keystore and never leaves this phone, so a copied vault cannot be
 *   brute-forced somewhere else.
 * - Vault files are AES-256-GCM in 1 MiB chunks: magic "LKY1", one encrypted
 *   metadata record, then the data records. Every record is authenticated.
 */
object VaultCrypto {
    private const val CHUNK = 1 shl 20
    private const val TAG_BITS = 128
    private const val KEYSTORE = "AndroidKeyStore"
    private const val PEPPER_ALIAS = "lockeye_pepper"
    private val MAGIC = byteArrayOf(0x4C, 0x4B, 0x59, 0x31) // "LKY1"
    private val META_AAD = byteArrayOf(0x4D) // "M"
    private val random = SecureRandom()

    // ---- keys -----------------------------------------------------------

    fun kek(pin: String, salt: ByteArray, iterations: Int): ByteArray {
        val pinBytes = pin.toByteArray(Charsets.UTF_8)
        if (Build.VERSION.SDK_INT >= 26) {
            val spec = PBEKeySpec(pin.toCharArray(), salt, iterations, 256)
            try {
                return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
            } finally {
                spec.clearPassword()
            }
        }
        // Older phones: the same PBKDF2 written out by hand.
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(pinBytes, "HmacSHA256"))
        mac.update(salt)
        mac.update(byteArrayOf(0, 0, 0, 1))
        var u = mac.doFinal()
        val t = u.copyOf()
        for (i in 1 until iterations) {
            u = mac.doFinal(u)
            for (j in t.indices) t[j] = (t[j].toInt() xor u[j].toInt()).toByte()
        }
        return t
    }

    fun seal(key: ByteArray, data: ByteArray, aad: ByteArray? = null): ByteArray {
        val iv = ByteArray(12)
        random.nextBytes(iv)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, iv))
        if (aad != null) cipher.updateAAD(aad)
        return iv + cipher.doFinal(data)
    }

    /** Returns null when the key is wrong or the data was changed. */
    fun open(key: ByteArray, blob: ByteArray, aad: ByteArray? = null): ByteArray? {
        if (blob.size < 12 + 16) return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"),
                GCMParameterSpec(TAG_BITS, blob.copyOfRange(0, 12))
            )
            if (aad != null) cipher.updateAAD(aad)
            cipher.doFinal(blob, 12, blob.size - 12)
        } catch (e: Exception) {
            null
        }
    }

    // ---- Keystore pepper ------------------------------------------------

    private fun pepperKey(): SecretKey? {
        if (Build.VERSION.SDK_INT < 23) return null
        return try {
            val store = KeyStore.getInstance(KEYSTORE)
            store.load(null)
            val existing = store.getKey(PEPPER_ALIAS, null) as? SecretKey
            if (existing != null) return existing
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            generator.init(
                KeyGenParameterSpec.Builder(
                    PEPPER_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            generator.generateKey()
        } catch (e: Exception) {
            null
        }
    }

    /** First byte: 1 = wrapped by the Keystore key, 0 = Keystore unavailable. */
    fun pepperSeal(data: ByteArray): ByteArray {
        val key = pepperKey()
        if (key != null) {
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key)
                val iv = cipher.iv
                return byteArrayOf(1, iv.size.toByte()) + iv + cipher.doFinal(data)
            } catch (e: Exception) {
                // fall through to the unwrapped form
            }
        }
        return byteArrayOf(0) + data
    }

    fun pepperOpen(blob: ByteArray): ByteArray? {
        if (blob.isEmpty()) return null
        if (blob[0].toInt() == 0) return blob.copyOfRange(1, blob.size)
        if (blob.size < 3) return null
        val key = pepperKey() ?: return null
        return try {
            val ivLen = blob[1].toInt() and 0xFF
            val iv = blob.copyOfRange(2, 2 + ivLen)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            cipher.doFinal(blob, 2 + ivLen, blob.size - 2 - ivLen)
        } catch (e: Exception) {
            null
        }
    }

    // ---- files ----------------------------------------------------------

    private fun dataAad(index: Long, last: Boolean): ByteArray =
        ByteBuffer.allocate(9).putLong(index).put(if (last) 1 else 0).array()

    private fun readChunk(input: InputStream): ByteArray {
        val buffer = ByteArray(CHUNK)
        var n = 0
        while (n < CHUNK) {
            val read = input.read(buffer, n, CHUNK - n)
            if (read < 0) break
            n += read
        }
        return if (n == CHUNK) buffer else buffer.copyOf(n)
    }

    private fun writeRecord(out: DataOutputStream, key: ByteArray, plain: ByteArray, aad: ByteArray, last: Boolean) {
        val blob = seal(key, plain, aad)
        out.writeInt(blob.size)
        out.writeByte(if (last) 1 else 0)
        out.write(blob)
    }

    /** Encrypts [input] into [dst]. The file appears only when it is complete. */
    fun encryptStream(key: ByteArray, input: InputStream, dst: File, metaJson: String) {
        val tmp = File(dst.parentFile, dst.name + ".tmp")
        try {
            DataOutputStream(BufferedOutputStream(FileOutputStream(tmp))).use { out ->
                out.write(MAGIC)
                writeRecord(out, key, metaJson.toByteArray(Charsets.UTF_8), META_AAD, true)
                var index = 0L
                var current = readChunk(input)
                while (true) {
                    val next = if (current.size == CHUNK) readChunk(input) else ByteArray(0)
                    val last = next.isEmpty()
                    writeRecord(out, key, current, dataAad(index, last), last)
                    if (last) break
                    index++
                    current = next
                }
            }
            if (dst.exists()) dst.delete()
            if (!tmp.renameTo(dst)) throw java.io.IOException("rename failed")
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }

    fun encryptFile(key: ByteArray, src: File, dst: File, metaJson: String) {
        FileInputStream(src).use { encryptStream(key, it, dst, metaJson) }
    }

    fun encryptBytes(key: ByteArray, data: ByteArray, dst: File, metaJson: String) {
        encryptStream(key, data.inputStream(), dst, metaJson)
    }

    private fun checkMagic(input: DataInputStream) {
        val magic = ByteArray(4)
        input.readFully(magic)
        if (!magic.contentEquals(MAGIC)) throw java.io.IOException("not a vault file")
    }

    /** The small description stored in front of the data, or null if it cannot be read. */
    fun readMeta(key: ByteArray, src: File): String? {
        return try {
            DataInputStream(BufferedInputStream(FileInputStream(src))).use { input ->
                checkMagic(input)
                val size = input.readInt()
                input.readByte()
                if (size < 0 || size > 1 shl 16) return null
                val blob = ByteArray(size)
                input.readFully(blob)
                open(key, blob, META_AAD)?.toString(Charsets.UTF_8)
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Decrypts the data of [src] into [out]. Throws if the key is wrong or the file was changed. */
    fun decryptTo(key: ByteArray, src: File, out: OutputStream) {
        DataInputStream(BufferedInputStream(FileInputStream(src))).use { input ->
            checkMagic(input)
            val metaSize = input.readInt()
            input.readByte()
            if (metaSize < 0 || metaSize > 1 shl 16) throw java.io.IOException("bad header")
            input.readFully(ByteArray(metaSize))
            var index = 0L
            while (true) {
                val size = input.readInt()
                val last = input.readByte().toInt() == 1
                if (size < 0 || size > CHUNK + 64) throw java.io.IOException("bad record")
                val blob = ByteArray(size)
                input.readFully(blob)
                val plain = open(key, blob, dataAad(index, last)) ?: throw java.io.IOException("wrong key")
                out.write(plain)
                if (last) break
                index++
            }
        }
    }

    fun readBytes(key: ByteArray, src: File): ByteArray {
        val out = ByteArrayOutputStream()
        decryptTo(key, src, out)
        return out.toByteArray()
    }

    fun decryptToFile(key: ByteArray, src: File, dst: File) {
        dst.parentFile?.mkdirs()
        BufferedOutputStream(FileOutputStream(dst)).use { decryptTo(key, src, it) }
    }
}
