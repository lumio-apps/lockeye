package com.lumioapps.lockeye

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Android tells this receiver when someone types a wrong PIN, pattern or
 * password on the phone's own lock screen. That is all it is used for.
 */
class LockeyeAdminReceiver : DeviceAdminReceiver() {

    override fun onPasswordFailed(context: Context, intent: Intent) {
        val prefs = NativePrefs.of(context)
        if (!prefs.getBoolean(NativePrefs.KEY_ENABLED, false)) return

        val now = System.currentTimeMillis()
        val last = prefs.getLong(NativePrefs.KEY_LAST_FAIL, 0L)
        // A new streak starts after 10 quiet minutes or after a correct unlock.
        val attempt = if (now - last > STREAK_MS) 1 else prefs.getInt(NativePrefs.KEY_ATTEMPT, 0) + 1
        prefs.edit()
            .putLong(NativePrefs.KEY_LAST_FAIL, now)
            .putInt(NativePrefs.KEY_ATTEMPT, attempt)
            .apply()

        if (!PhoneLockService.start(context, attempt)) {
            // Android refused to start the camera service: still record the attempt.
            PendingLog.append(context, now, attempt, null)
        }
    }

    override fun onPasswordSucceeded(context: Context, intent: Intent) {
        NativePrefs.of(context).edit().putInt(NativePrefs.KEY_ATTEMPT, 0).apply()
    }

    private companion object {
        const val STREAK_MS = 10 * 60 * 1000L
    }
}
