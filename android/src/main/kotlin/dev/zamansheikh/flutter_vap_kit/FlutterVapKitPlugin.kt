package dev.zamansheikh.flutter_vap_kit

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.concurrent.Executors

/**
 * Registers the VAP platform view and a small utility channel:
 *
 *  - `resolveAsset` turns a Flutter asset key into a file the decoder can open
 *    (VAP needs a real file; Flutter assets live inside the APK). The copy is
 *    made once and reused.
 *  - `poster` renders a clip's first frame, with its alpha applied, as a PNG.
 */
class FlutterVapKitPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_vap_kit")
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "flutter_vap_kit/view",
            VapKitViewFactory(binding.binaryMessenger),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resolveAsset" -> {
                val key = call.argument<String>("asset")
                val pkg = call.argument<String>("package")
                if (key == null) {
                    result.error("bad_args", "asset is required", null)
                    return
                }
                background(result) { resolveAsset(key, pkg) }
            }
            "poster" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "path is required", null)
                    return
                }
                background(result) { VapPoster.render(path) }
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [work] off the main thread and answers [result] back on it. */
    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("vap_kit_error", e.message, null) }
            }
        }
    }

    /**
     * Copies a Flutter asset to the cache directory once and returns its path.
     * The file name carries the asset's size, so a rebuilt app with a changed
     * asset gets a fresh copy instead of a stale one.
     */
    private fun resolveAsset(asset: String, pkg: String?): String {
        val loader = FlutterInjector.instance().flutterLoader()
        val key = if (pkg == null) loader.getLookupKeyForAsset(asset)
        else loader.getLookupKeyForAsset(asset, pkg)

        val dir = File(context.cacheDir, "flutter_vap_kit").apply { mkdirs() }
        val safeName = key.replace(Regex("[^A-Za-z0-9._-]"), "_")

        // Assets may be stored compressed, in which case their size is only
        // known after reading them; copy to a temp file first, then name the
        // final file after the real length.
        val partial = File.createTempFile("copy_", ".part", dir)
        context.assets.open(key).use { input ->
            partial.outputStream().use { output -> input.copyTo(output) }
        }
        val target = File(dir, "${partial.length()}_$safeName")
        if (target.exists() && target.length() == partial.length()) {
            partial.delete()
            return target.absolutePath
        }
        if (!partial.renameTo(target)) {
            partial.copyTo(target, overwrite = true)
            partial.delete()
        }
        return target.absolutePath
    }
}

private class VapKitViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        VapKitView(context, messenger, viewId)
}
