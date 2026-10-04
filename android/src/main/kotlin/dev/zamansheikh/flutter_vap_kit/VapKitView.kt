package dev.zamansheikh.flutter_vap_kit

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import com.tencent.qgame.animplayer.AnimConfig
import com.tencent.qgame.animplayer.AnimView
import com.tencent.qgame.animplayer.inter.IAnimListener
import com.tencent.qgame.animplayer.util.ScaleType
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File

/**
 * One VAP player surface.
 *
 * Channel `flutter_vap_kit/view_<id>`:
 *   play { path, loop, fit, frames }  — loop < 0 means "forever"
 *   stop
 * and back to Dart: onStart, onFrame { frame }, onComplete,
 * onError { code, message }.
 *
 * Every play request carries a ticket. Callbacks from a clip that has since
 * been replaced or stopped are dropped here, so Dart never sees a stale
 * "complete" for something it already moved on from.
 */
internal class VapKitView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView, IAnimListener, MethodChannel.MethodCallHandler {

    private val animView = AnimView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
    }
    private val channel = MethodChannel(messenger, "flutter_vap_kit/view_$viewId")
    private val main = Handler(Looper.getMainLooper())

    private var disposed = false

    /** Ticket of the clip currently playing; 0 when nothing is. */
    private var ticket = 0

    /** Whether Dart asked to be told about every drawn frame. */
    @Volatile
    private var reportFrames = false

    /** A play request waiting for the previous clip to finish tearing down. */
    private var pendingStart: Runnable? = null

    init {
        animView.setAnimListener(this)
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = animView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                val path = call.argument<String>("path")
                val loop = call.argument<Int>("loop") ?: 1
                val fit = call.argument<String>("fit") ?: "contain"
                val id = call.argument<Int>("ticket") ?: 0
                reportFrames = call.argument<Boolean>("frames") ?: false
                if (path == null) {
                    result.error("bad_args", "path is required", null)
                    return
                }
                play(path, loop, fit, id)
                result.success(null)
            }
            "stop" -> {
                cancelPending()
                ticket = 0
                animView.stopPlay()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun play(path: String, loop: Int, fit: String, id: Int) {
        cancelPending()
        val file = File(path)
        if (!file.exists()) {
            emitError(id, -1, "File does not exist: $path")
            return
        }

        val start = Runnable {
            pendingStart = null
            if (disposed) return@Runnable
            ticket = id
            animView.setScaleType(
                when (fit) {
                    "cover" -> ScaleType.CENTER_CROP
                    "fill" -> ScaleType.FIT_XY
                    else -> ScaleType.FIT_CENTER
                },
            )
            animView.setLoop(if (loop < 0) Int.MAX_VALUE else loop.coerceAtLeast(1))
            try {
                animView.startPlay(file)
            } catch (e: Throwable) {
                emitError(id, -1, e.message ?: "startPlay failed")
            }
        }

        if (animView.isRunning()) {
            // The decoder releases its surface asynchronously; starting the next
            // clip in the same tick is ignored by the player.
            ticket = 0
            animView.stopPlay()
            pendingStart = start
            main.postDelayed(start, 80)
        } else {
            start.run()
        }
    }

    private fun cancelPending() {
        pendingStart?.let { main.removeCallbacks(it) }
        pendingStart = null
    }

    override fun dispose() {
        disposed = true
        cancelPending()
        ticket = 0
        channel.setMethodCallHandler(null)
        try {
            animView.stopPlay()
        } catch (_: Throwable) {
        }
    }

    // ── IAnimListener (called on the decoder thread) ────────────────────────

    override fun onVideoStart() {
        val id = ticket
        if (id == 0) return
        main.post { if (!disposed && id == ticket) channel.invokeMethod("onStart", mapOf("ticket" to id)) }
    }

    override fun onVideoRender(frameIndex: Int, config: AnimConfig?) {
        if (!reportFrames) return
        val id = ticket
        if (id == 0) return
        main.post {
            if (!disposed && id == ticket) {
                channel.invokeMethod("onFrame", mapOf("ticket" to id, "frame" to frameIndex))
            }
        }
    }

    override fun onVideoComplete() {
        val id = ticket
        if (id == 0) return
        main.post {
            if (!disposed && id == ticket) {
                ticket = 0
                channel.invokeMethod("onComplete", mapOf("ticket" to id))
            }
        }
    }

    override fun onVideoDestroy() {}

    override fun onFailed(errorType: Int, errorMsg: String?) {
        val id = ticket
        if (id == 0) return
        emitError(id, errorType, errorMsg ?: "Playback failed")
    }

    private fun emitError(id: Int, code: Int, message: String) {
        main.post {
            if (disposed) return@post
            if (id == ticket) ticket = 0
            channel.invokeMethod(
                "onError",
                mapOf("ticket" to id, "code" to code, "message" to message),
            )
        }
    }
}
