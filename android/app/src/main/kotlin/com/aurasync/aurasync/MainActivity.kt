package com.aurasync.aurasync

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    // Long-press menu on the app icon: a shortcut carries "aurasync.mode" (sos, focus, calm, deep).
    // A cold start is picked up by Dart through "initialMode"; later taps are pushed to Dart.
    private var launchChannel: MethodChannel? = null
    private var pendingMode: String? = null

    private fun modeFrom(intent: Intent?): String? = intent?.getStringExtra("aurasync.mode")

    private val micRequestCode = 4721
    private var pendingStart: MethodChannel.Result? = null
    private var capture: VoiceCapture? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingMode = modeFrom(intent)
        intent?.removeExtra("aurasync.mode") // read once: a re-created activity must not replay it
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aurasync/launch").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "initialMode") {
                    val mode = pendingMode
                    pendingMode = null
                    result.success(mode)
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aurasync/screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "keepAwake") {
                    val awake = call.arguments as? Boolean ?: false
                    runOnUiThread {
                        if (awake) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aurasync/voice")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> startVoice(result)
                    "stop" -> stopVoice(result)
                    "cancel" -> {
                        capture?.finish(null)
                        capture = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVoice(result: MethodChannel.Result) {
        if (pendingStart != null) {
            result.success(false)
            return
        }
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            beginCapture(result)
        } else {
            pendingStart = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), micRequestCode)
        }
    }

    private fun beginCapture(result: MethodChannel.Result) {
        capture?.finish(null)
        capture = null
        val c = VoiceCapture.create()
        if (c == null) {
            result.success(false)
            return
        }
        capture = c
        c.begin()
        result.success(true)
    }

    private fun stopVoice(result: MethodChannel.Result) {
        val c = capture
        if (c == null) {
            result.error("not_recording", "No active recording", null)
            return
        }
        capture = null
        val file = c.finish(File(cacheDir, "aura_voice_${System.nanoTime()}.wav"))
        if (file == null) {
            result.error("empty", "No audio captured", null)
        } else {
            result.success(mapOf("path" to file.absolutePath, "sampleRate" to c.sampleRate))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Already running: hand the shortcut to Dart, which starts the session if the home screen is showing.
        modeFrom(intent)?.let { launchChannel?.invokeMethod("launchMode", it) }
        intent.removeExtra("aurasync.mode")
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != micRequestCode) return
        val result = pendingStart ?: return
        pendingStart = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            beginCapture(result)
        } else {
            result.success(false)
        }
    }

    override fun onDestroy() {
        capture?.finish(null)
        capture = null
        super.onDestroy()
    }
}

/** 16-bit mono AudioRecord capture, hard-capped at [MAX_SECONDS] of audio. */
internal class VoiceCapture private constructor(
    private val record: AudioRecord,
    val sampleRate: Int,
    private val chunkSamples: Int
) {
    private val maxSamples = (MAX_SECONDS * sampleRate).toInt()
    private val pcm = ShortArray(maxSamples)
    @Volatile private var count = 0
    @Volatile private var running = false
    private var thread: Thread? = null

    fun begin() {
        running = true
        record.startRecording()
        thread = Thread {
            val buf = ShortArray(chunkSamples)
            while (running && count < maxSamples) {
                val n = record.read(buf, 0, minOf(chunkSamples, maxSamples - count))
                if (n <= 0) break
                System.arraycopy(buf, 0, pcm, count, n)
                count += n
            }
        }.also { it.start() }
    }

    /** Stops capture; writes a WAV to [out] when given. Returns the file, or null if nothing was written. */
    fun finish(out: File?): File? {
        running = false
        thread?.join(1000)
        thread = null
        try {
            record.stop()
        } catch (_: IllegalStateException) {
        }
        record.release()
        if (out == null || count == 0) return null
        val bytes = count * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt(36 + bytes).put("WAVE".toByteArray())
        header.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
        header.putInt(sampleRate).putInt(sampleRate * 2).putShort(2).putShort(16)
        header.put("data".toByteArray()).putInt(bytes)
        val body = ByteBuffer.allocate(bytes).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until count) body.putShort(pcm[i])
        RandomAccessFile(out, "rw").use { f ->
            f.setLength(0)
            f.write(header.array())
            f.write(body.array())
        }
        return out
    }

    companion object {
        const val MAX_SECONDS = 6.0

        @Suppress("MissingPermission")
        fun create(): VoiceCapture? {
            for (rate in intArrayOf(48000, 44100, 16000)) {
                val minBuf = AudioRecord.getMinBufferSize(
                    rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
                )
                if (minBuf <= 0) continue
                val chunk = maxOf(rate / 50, 256)
                val bufBytes = maxOf(minBuf, chunk * 2) * 2
                val rec = try {
                    AudioRecord(
                        MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, bufBytes
                    )
                } catch (_: Exception) {
                    continue
                }
                if (rec.state == AudioRecord.STATE_INITIALIZED) return VoiceCapture(rec, rate, chunk)
                rec.release()
            }
            return null
        }
    }
}
