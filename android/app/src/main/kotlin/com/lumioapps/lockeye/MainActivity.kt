package com.lumioapps.lockeye

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val adminComponent: ComponentName
        get() = ComponentName(this, LockeyeAdminReceiver::class.java)

    private val policyManager: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                    try {
                        policyManager.removeActiveAdmin(adminComponent)
                    } catch (e: Exception) {
                    }
                    result.success(null)
                }
                "testCapture" -> result.success(PhoneLockService.start(this, 0))
                else -> result.notImplemented()
            }
        }
    }

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
        const val REQUEST_CODE = 4101
        const val PERMISSION_CAMERA = "android.permission.CAMERA"
        const val PERMISSION_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    }
}
