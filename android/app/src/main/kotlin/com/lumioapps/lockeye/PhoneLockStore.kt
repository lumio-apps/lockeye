package com.lumioapps.lockeye

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

/** Settings the native side needs even while the Flutter app is closed. */
object NativePrefs {
    const val KEY_ENABLED = "enabled"
    const val KEY_BASE_DIR = "base_dir"
    const val KEY_LAST_FAIL = "last_fail"
    const val KEY_ATTEMPT = "attempt"

    fun of(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences("lockeye_native", Context.MODE_PRIVATE)
}

/**
 * Wrong unlock attempts seen on the phone's own lock screen. The Flutter app
 * reads this file the next time it opens and adds the entries to the intruder log.
 * [KEY_BASE_DIR] is the app's documents folder, handed over by Flutter.
 */
object PendingLog {
    private const val FILE_NAME = "phone_lock_pending.jsonl"

    private fun baseDir(context: Context): File? {
        val path = NativePrefs.of(context).getString(NativePrefs.KEY_BASE_DIR, null) ?: return null
        return File(path)
    }

    /** Where the photo for an attempt made at [timeMs] should be written. */
    fun photoFile(context: Context, timeMs: Long): File? {
        val base = baseDir(context) ?: return null
        val dir = File(base, "intruders")
        if (!dir.exists() && !dir.mkdirs()) return null
        return File(dir, "phone_$timeMs.jpg")
    }

    @Synchronized
    fun append(context: Context, timeMs: Long, attempt: Int, photoPath: String?) {
        val base = baseDir(context) ?: return
        try {
            if (!base.exists()) base.mkdirs()
            val line = JSONObject()
                .put("time", timeMs)
                .put("attempt", attempt)
                .put("path", photoPath ?: JSONObject.NULL)
                .toString()
            FileOutputStream(File(base, FILE_NAME), true).use { out ->
                out.write((line + "\n").toByteArray(Charsets.UTF_8))
            }
        } catch (e: Exception) {
            // Nothing sensible to do: the log entry is lost, the app keeps working.
        }
    }
}
