package com.lumioapps.lockeye

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import java.io.FileOutputStream

/**
 * Takes the photo when the phone's lock screen reports a wrong attempt.
 *
 * Android only lets an app use the camera from the background while it shows
 * something to the user, so the service shows a notification and a 1 pixel
 * transparent overlay (needs "Display over other apps") while it works, then
 * stops itself.
 */
class PhoneLockService : Service() {

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var overlay: View? = null

    // Only touched on the handler thread.
    private val queue = ArrayDeque<Int>()
    private var busy = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        enterForeground()
        showOverlay()

        val attempt = intent?.getIntExtra(EXTRA_ATTEMPT, 1) ?: 1
        val worker = ensureHandler()
        worker.post {
            queue.addLast(attempt)
            next()
        }
        return START_NOT_STICKY
    }

    private fun ensureHandler(): Handler {
        handler?.let { return it }
        val newThread = HandlerThread("lockeye-phone-lock")
        newThread.start()
        val newHandler = Handler(newThread.looper)
        thread = newThread
        handler = newHandler
        return newHandler
    }

    private fun next() {
        if (busy) return
        val attempt = if (queue.isEmpty()) null else queue.removeFirst()
        if (attempt == null) {
            stopSelf()
            return
        }
        val worker = handler ?: return
        busy = true
        val timeMs = System.currentTimeMillis()
        FrontCameraShot(this, worker).start { bytes ->
            PendingLog.append(this, timeMs, attempt, savePhoto(timeMs, bytes))
            busy = false
            next()
        }
    }

    private fun savePhoto(timeMs: Long, bytes: ByteArray?): String? {
        if (bytes == null || bytes.isEmpty()) return null
        val file = PendingLog.photoFile(this, timeMs) ?: return null
        return try {
            FileOutputStream(file).use { it.write(bytes) }
            file.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun newNotificationBuilder(): Notification.Builder {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Lock screen guard", NotificationManager.IMPORTANCE_LOW)
            )
            return Notification.Builder(this, CHANNEL_ID)
        }
        return Notification.Builder(this)
    }

    private fun enterForeground() {
        val notification = newNotificationBuilder()
            .setContentTitle("Lockeye")
            .setContentText("Checking an unlock attempt")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android refused the foreground start; the photo may still work.
        }
    }

    private fun showOverlay() {
        if (overlay != null) return
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(this)) return
        try {
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            @Suppress("DEPRECATION")
            val type = if (Build.VERSION.SDK_INT >= 26) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                1,
                1,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.TOP or Gravity.START
            val view = View(this)
            windowManager.addView(view, params)
            overlay = view
        } catch (e: Exception) {
            overlay = null
        }
    }

    override fun onDestroy() {
        overlay?.let {
            try {
                (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it)
            } catch (e: Exception) {
            }
        }
        overlay = null
        thread?.quitSafely()
        thread = null
        handler = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_ATTEMPT = "attempt"
        private const val CHANNEL_ID = "lockeye_lock_screen"
        private const val NOTIFICATION_ID = 4101

        /** Returns false when Android refuses to start the service. */
        fun start(context: Context, attempt: Int): Boolean {
            val intent = Intent(context, PhoneLockService::class.java).putExtra(EXTRA_ATTEMPT, attempt)
            return try {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                false
            }
        }
    }
}
