package com.lumioapps.lockeye

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.util.Size
import android.view.Surface
import java.util.concurrent.atomic.AtomicBoolean

/**
 * One silent front-camera photo, no preview on screen.
 *
 * A tiny hidden preview stream runs for a moment first so auto exposure can
 * settle, then one JPEG is captured. Everything runs on [handler]'s thread.
 * [start] reports exactly once: the JPEG bytes, or null if anything failed.
 */
class FrontCameraShot(private val context: Context, private val handler: Handler) {

    private val finished = AtomicBoolean(false)
    private var onResult: ((ByteArray?) -> Unit)? = null

    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var texture: SurfaceTexture? = null
    private var previewSurface: Surface? = null
    private var jpegOrientation = 270

    private val timeoutTask = Runnable { finish(null) }
    private val shootTask = Runnable { shoot() }

    @SuppressLint("MissingPermission")
    fun start(callback: (ByteArray?) -> Unit) {
        onResult = callback
        handler.postDelayed(timeoutTask, TIMEOUT_MS)

        if (Build.VERSION.SDK_INT >= 23 &&
            context.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            finish(null)
            return
        }

        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            var frontId: String? = null
            for (id in manager.cameraIdList) {
                val facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                    frontId = id
                    break
                }
            }
            if (frontId == null) {
                finish(null)
                return
            }
            manager.openCamera(frontId, deviceCallback, handler)
        } catch (e: Exception) {
            finish(null)
        }
    }

    private val deviceCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(device: CameraDevice) {
            if (finished.get()) {
                device.close()
                return
            }
            camera = device
            startSession(device)
        }

        override fun onDisconnected(device: CameraDevice) {
            device.close()
            finish(null)
        }

        override fun onError(device: CameraDevice, error: Int) {
            device.close()
            finish(null)
        }
    }

    @Suppress("DEPRECATION")
    private fun startSession(device: CameraDevice) {
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val chars = manager.getCameraCharacteristics(device.id)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            jpegOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 270

            val jpegSize = pickJpegSize(map?.getOutputSizes(ImageFormat.JPEG))
            val previewSize = pickPreviewSize(map?.getOutputSizes(SurfaceTexture::class.java))

            val imageReader = ImageReader.newInstance(jpegSize.width, jpegSize.height, ImageFormat.JPEG, 2)
            reader = imageReader
            imageReader.setOnImageAvailableListener({ source ->
                val bytes = readJpeg(source)
                if (bytes != null) finish(bytes)
            }, handler)

            val surfaceTexture = SurfaceTexture(10)
            surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
            texture = surfaceTexture
            val preview = Surface(surfaceTexture)
            previewSurface = preview

            device.createCaptureSession(
                listOf(preview, imageReader.surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(configured: CameraCaptureSession) {
                        if (finished.get()) {
                            configured.close()
                            return
                        }
                        session = configured
                        try {
                            val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                            request.addTarget(preview)
                            configured.setRepeatingRequest(request.build(), null, handler)
                            handler.postDelayed(shootTask, WARM_UP_MS)
                        } catch (e: Exception) {
                            finish(null)
                        }
                    }

                    override fun onConfigureFailed(failed: CameraCaptureSession) {
                        finish(null)
                    }
                },
                handler
            )
        } catch (e: Exception) {
            finish(null)
        }
    }

    private fun readJpeg(source: ImageReader): ByteArray? {
        return try {
            val image = source.acquireLatestImage() ?: return null
            try {
                val buffer = image.planes[0].buffer
                val data = ByteArray(buffer.remaining())
                buffer.get(data)
                data
            } finally {
                image.close()
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun shoot() {
        if (finished.get()) return
        val device = camera ?: return
        val active = session ?: return
        val imageReader = reader ?: return
        try {
            val request = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            request.addTarget(imageReader.surface)
            request.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation)
            request.set(CaptureRequest.JPEG_QUALITY, 85.toByte())
            active.capture(request.build(), null, handler)
        } catch (e: Exception) {
            finish(null)
        }
    }

    private fun finish(bytes: ByteArray?) {
        if (!finished.compareAndSet(false, true)) return
        handler.removeCallbacks(timeoutTask)
        handler.removeCallbacks(shootTask)
        try { session?.close() } catch (e: Exception) { }
        try { camera?.close() } catch (e: Exception) { }
        try { reader?.close() } catch (e: Exception) { }
        try { previewSurface?.release() } catch (e: Exception) { }
        try { texture?.release() } catch (e: Exception) { }
        val callback = onResult
        onResult = null
        callback?.invoke(bytes)
    }

    /** Biggest JPEG up to about 2 megapixels: sharp enough, small on disk. */
    private fun pickJpegSize(sizes: Array<Size>?): Size {
        if (sizes == null || sizes.isEmpty()) return Size(640, 480)
        val fitting = sizes.filter { it.width.toLong() * it.height <= MAX_PIXELS }
        return fitting.maxByOrNull { it.width.toLong() * it.height }
            ?: sizes.minByOrNull { it.width.toLong() * it.height }
            ?: Size(640, 480)
    }

    /** The hidden preview only exists to warm up exposure, so smaller is better. */
    private fun pickPreviewSize(sizes: Array<Size>?): Size {
        if (sizes == null || sizes.isEmpty()) return Size(640, 480)
        val target = 640L * 480L
        return sizes.minByOrNull { Math.abs(it.width.toLong() * it.height - target) } ?: Size(640, 480)
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        const val WARM_UP_MS = 900L
        const val MAX_PIXELS = 2_100_000L
    }
}
