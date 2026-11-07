package com.lumioapps.lockeye

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {

    private var pendingPick: MethodChannel.Result? = null
    private var pendingDelete: MethodChannel.Result? = null
    private var pickKey: ByteArray? = null
    private var pickDir: String? = null
    private var pickPhotos = false

    /** Gallery items of the last photo import, kept so the originals can be deleted on request. */
    private var deletable: List<Uri> = emptyList()

    private val adminComponent: ComponentName
        get() = ComponentName(this, LockeyeAdminReceiver::class.java)

    private val policyManager: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySecure(NativePrefs.of(this).getBoolean(NativePrefs.KEY_SECURE, true))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "configure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val dir = call.argument<String>("dir")
                    val editor = NativePrefs.of(this).edit().putBoolean(NativePrefs.KEY_ENABLED, enabled)
                    if (dir != null) editor.putString(NativePrefs.KEY_BASE_DIR, dir)
                    editor.apply()
                    result.success(null)
                }
                "requestAdmin" -> {
                    openSafely(
                        Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            .putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Lockeye only learns that an unlock attempt failed, so it can take a photo. " +
                                    "It cannot see, change or reset your PIN, and it cannot lock or wipe your phone."
                            )
                    )
                    result.success(null)
                }
                "requestOverlay" -> {
                    openSafely(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                    )
                    result.success(null)
                }
                "requestPermissions" -> {
                    val missing = ArrayList<String>()
                    if (!isGranted(PERMISSION_CAMERA)) missing.add(PERMISSION_CAMERA)
                    if (Build.VERSION.SDK_INT >= 33 && !isGranted(PERMISSION_NOTIFICATIONS)) {
                        missing.add(PERMISSION_NOTIFICATIONS)
                    }
                    if (missing.isNotEmpty() && Build.VERSION.SDK_INT >= 23) {
                        requestPermissions(missing.toTypedArray(), REQUEST_CODE)
                    }
                    result.success(null)
                }
                "openBatterySettings" -> {
                    if (Build.VERSION.SDK_INT >= 23) {
                        openSafely(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                    result.success(null)
                }
                "removeAdmin" -> {
                    // Removing it from inside Lockeye is not a tamper attempt.
                    NativePrefs.of(this).edit().putBoolean(NativePrefs.KEY_SELF_REMOVE, true).apply()
                    try {
                        policyManager.removeActiveAdmin(adminComponent)
                    } catch (e: Exception) {
                    }
                    result.success(null)
                }
                "testCapture" -> result.success(PhoneLockService.start(this, 0))
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") ?: true
                    NativePrefs.of(this).edit().putBoolean(NativePrefs.KEY_SECURE, on).apply()
                    applySecure(on)
                    result.success(null)
                }
                "elapsed" -> result.success(SystemClock.elapsedRealtime())
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, VAULT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "kek" -> runIo(result) {
                    VaultCrypto.kek(
                        call.argument<String>("pin") ?: "",
                        call.argument<ByteArray>("salt") ?: ByteArray(0),
                        call.argument<Int>("iters") ?: 150000
                    )
                }
                "seal" -> runIo(result) {
                    VaultCrypto.seal(call.argument<ByteArray>("key")!!, call.argument<ByteArray>("data")!!)
                }
                "open" -> runIo(result) {
                    VaultCrypto.open(call.argument<ByteArray>("key")!!, call.argument<ByteArray>("data")!!)
                }
                "pepperSeal" -> runIo(result) { VaultCrypto.pepperSeal(call.argument<ByteArray>("data")!!) }
                "pepperOpen" -> runIo(result) { VaultCrypto.pepperOpen(call.argument<ByteArray>("data")!!) }
                "encryptBytes" -> runIo(result) {
                    VaultCrypto.encryptBytes(
                        call.argument<ByteArray>("key")!!,
                        call.argument<ByteArray>("data")!!,
                        File(call.argument<String>("path")!!),
                        call.argument<String>("meta") ?: "{}"
                    )
                    true
                }
                "encryptFile" -> runIo(result) {
                    VaultCrypto.encryptFile(
                        call.argument<ByteArray>("key")!!,
                        File(call.argument<String>("src")!!),
                        File(call.argument<String>("path")!!),
                        call.argument<String>("meta") ?: "{}"
                    )
                    true
                }
                "readBytes" -> runIo(result) {
                    try {
                        VaultCrypto.readBytes(call.argument<ByteArray>("key")!!, File(call.argument<String>("path")!!))
                    } catch (e: Exception) {
                        null
                    }
                }
                "readMeta" -> runIo(result) {
                    VaultCrypto.readMeta(call.argument<ByteArray>("key")!!, File(call.argument<String>("path")!!))
                }
                "decryptToFile" -> runIo(result) {
                    try {
                        VaultCrypto.decryptToFile(
                            call.argument<ByteArray>("key")!!,
                            File(call.argument<String>("path")!!),
                            File(call.argument<String>("out")!!)
                        )
                        true
                    } catch (e: Exception) {
                        false
                    }
                }
                "importPick" -> startPick(call.argument<ByteArray>("key")!!, call.argument<String>("dir")!!,
                    call.argument<Boolean>("photos") ?: false, result)
                "deleteOriginals" -> deleteOriginals(result)
                else -> result.notImplemented()
            }
        }
    }

    // ---- helpers --------------------------------------------------------

    /** Runs slow work (key derivation, big files) off the main thread. */
    private fun runIo(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error("vault", e.message, null) }
            }
        }.start()
    }

    private fun applySecure(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    // ---- importing straight into the vault -------------------------------

    private fun startPick(key: ByteArray, dir: String, photos: Boolean, result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        pendingPick = result
        pickKey = key
        pickDir = dir
        pickPhotos = photos
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (photos) "image/*" else "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.success(hashMapOf("added" to 0, "deletable" to 0))
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQ_PICK -> handlePick(resultCode, data)
            REQ_DELETE -> {
                val result = pendingDelete
                pendingDelete = null
                if (result != null) {
                    if (resultCode == Activity.RESULT_OK) deletable = emptyList()
                    result.success(resultCode == Activity.RESULT_OK)
                }
            }
            else -> super.onActivityResult(requestCode, resultCode, data)
        }
    }

    private fun handlePick(resultCode: Int, data: Intent?) {
        val result = pendingPick ?: return
        pendingPick = null
        val key = pickKey
        val dir = pickDir
        val photos = pickPhotos
        pickKey = null

        val uris = ArrayList<Uri>()
        if (resultCode == Activity.RESULT_OK && data != null) {
            val clip = data.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            }
            val single = data.data
            if (uris.isEmpty() && single != null) uris.add(single)
        }
        if (uris.isEmpty() || key == null || dir == null) {
            result.success(hashMapOf("added" to 0, "deletable" to 0))
            return
        }

        Thread {
            var added = 0
            val media = ArrayList<Uri>()
            File(dir).mkdirs()
            for (uri in uris) {
                try {
                    importOne(uri, key, File(dir), photos)
                    added++
                    if (photos) {
                        val mediaUri = toMediaUri(uri)
                        if (mediaUri != null) media.add(mediaUri)
                    }
                } catch (e: Exception) {
                    // Skip this one; the others still go in.
                }
            }
            runOnUiThread {
                deletable = media
                result.success(hashMapOf("added" to added, "deletable" to media.size))
            }
        }.start()
    }

    private fun importOne(uri: Uri, key: ByteArray, dir: File, photos: Boolean) {
        var name = "file"
        var size = -1L
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
            }
        }
        val meta = JSONObject()
            .put("name", name)
            .put("size", size)
            .put("added", System.currentTimeMillis())
            .put("kind", if (photos) "photo" else "file")
            .toString()
        val dst = File(dir, UUID.randomUUID().toString().replace("-", "") + ".lky")
        val input = contentResolver.openInputStream(uri) ?: throw java.io.IOException("cannot open")
        input.use { VaultCrypto.encryptStream(key, it, dst, meta) }
    }

    /** Turns a gallery picker address into the gallery's own address, if there is one. */
    private fun toMediaUri(uri: Uri): Uri? {
        return try {
            if (uri.authority == "media") return uri
            if (!DocumentsContract.isDocumentUri(this, uri)) return null
            if (uri.authority != "com.android.providers.media.documents") return null
            val docId = DocumentsContract.getDocumentId(uri)
            val parts = docId.split(":")
            if (parts.size != 2 || parts[0] != "image") return null
            ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, parts[1].toLong())
        } catch (e: Exception) {
            null
        }
    }

    private fun deleteOriginals(result: MethodChannel.Result) {
        val uris = deletable
        if (uris.isEmpty()) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                val request = MediaStore.createDeleteRequest(contentResolver, uris)
                pendingDelete = result
                @Suppress("DEPRECATION")
                startIntentSenderForResult(request.intentSender, REQ_DELETE, null, 0, 0, 0)
            } catch (e: Exception) {
                pendingDelete = null
                result.success(false)
            }
        } else {
            Thread {
                var ok = true
                for (uri in uris) {
                    try {
                        if (contentResolver.delete(uri, null, null) < 1) ok = false
                    } catch (e: Exception) {
                        ok = false
                    }
                }
                runOnUiThread {
                    if (ok) deletable = emptyList()
                    result.success(ok)
                }
            }.start()
        }
    }

    // ---- phone lock screen ------------------------------------------------

    private fun status(): HashMap<String, Boolean> {
        val map = HashMap<String, Boolean>()
        map["admin"] = policyManager.isAdminActive(adminComponent)
        map["overlay"] = Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)
        map["camera"] = isGranted(PERMISSION_CAMERA)
        map["notifications"] = Build.VERSION.SDK_INT < 33 || isGranted(PERMISSION_NOTIFICATIONS)
        return map
    }

    private fun isGranted(permission: String): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun openSafely(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: Exception) {
        }
    }

    private companion object {
        const val CHANNEL = "com.lumioapps.lockeye/phonelock"
        const val VAULT_CHANNEL = "com.lumioapps.lockeye/vault"
        const val REQUEST_CODE = 4101
        const val REQ_PICK = 4201
        const val REQ_DELETE = 4202
        const val PERMISSION_CAMERA = "android.permission.CAMERA"
        const val PERMISSION_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    }
}
