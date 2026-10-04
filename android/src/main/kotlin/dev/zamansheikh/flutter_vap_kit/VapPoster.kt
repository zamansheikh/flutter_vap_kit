package dev.zamansheikh.flutter_vap_kit

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile

/**
 * Renders the first frame of a VAP clip as a transparent PNG.
 *
 * A VAP file is an ordinary MP4 whose picture holds the colour image and its
 * alpha mask side by side. Where each one sits is described by a JSON `vapc`
 * box inside the file. This reads that box, grabs the first video frame and
 * merges the two regions into one image with real transparency.
 */
internal object VapPoster {

    /** Returns PNG bytes, or null when the file carries no `vapc` layout. */
    fun render(path: String): ByteArray? {
        val info = readInfo(File(path)) ?: return null
        val width = info.optInt("w")
        val height = info.optInt("h")
        val rgb = info.optJSONArray("rgbFrame") ?: return null
        val alpha = info.optJSONArray("aFrame") ?: return null
        if (width <= 0 || height <= 0 || rgb.length() < 4 || alpha.length() < 4) return null

        val retriever = MediaMetadataRetriever()
        val frame: Bitmap = try {
            retriever.setDataSource(path)
            retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } finally {
            retriever.release()
        } ?: return null

        val source = if (frame.config == Bitmap.Config.ARGB_8888) frame
        else frame.copy(Bitmap.Config.ARGB_8888, false)
        val sw = source.width
        val sh = source.height

        // The decoder may hand back a frame scaled from the coded size; map the
        // layout rectangles through that scale.
        val scaleX = sw.toFloat() / info.optInt("videoW", sw).coerceAtLeast(1)
        val scaleY = sh.toFloat() / info.optInt("videoH", sh).coerceAtLeast(1)

        val rx = rgb.getInt(0) * scaleX
        val ry = rgb.getInt(1) * scaleY
        val rw = rgb.getInt(2) * scaleX
        val rh = rgb.getInt(3) * scaleY
        val ax = alpha.getInt(0) * scaleX
        val ay = alpha.getInt(1) * scaleY
        val aw = alpha.getInt(2) * scaleX
        val ah = alpha.getInt(3) * scaleY

        val pixels = IntArray(sw * sh)
        source.getPixels(pixels, 0, sw, 0, 0, sw, sh)

        val out = IntArray(width * height)
        for (y in 0 until height) {
            val cy = (ry + (y + 0.5f) * rh / height).toInt().coerceIn(0, sh - 1)
            val my = (ay + (y + 0.5f) * ah / height).toInt().coerceIn(0, sh - 1)
            for (x in 0 until width) {
                val cx = (rx + (x + 0.5f) * rw / width).toInt().coerceIn(0, sw - 1)
                val mx = (ax + (x + 0.5f) * aw / width).toInt().coerceIn(0, sw - 1)
                val colour = pixels[cy * sw + cx]
                // The mask is greyscale; any channel carries the alpha value.
                val a = (pixels[my * sw + mx] shr 16) and 0xFF
                out[y * width + x] = (a shl 24) or (colour and 0x00FFFFFF)
            }
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(out, 0, width, 0, 0, width, height)
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
        bitmap.recycle()
        if (source !== frame) source.recycle()
        frame.recycle()
        return bytes.toByteArray()
    }

    /** The `info` object of the file's `vapc` box, or null if there is none. */
    private fun readInfo(file: File): JSONObject? {
        if (!file.exists()) return null
        RandomAccessFile(file, "r").use { raf ->
            val length = raf.length()
            var offset = 0L
            // Top-level MP4 boxes: [4-byte size][4-byte type][payload].
            while (offset + 8 <= length) {
                raf.seek(offset)
                var size = raf.readInt().toLong() and 0xFFFFFFFFL
                val type = ByteArray(4).also { raf.readFully(it) }
                var header = 8L
                if (size == 1L) {
                    size = raf.readLong()
                    header = 16L
                } else if (size == 0L) {
                    size = length - offset
                }
                if (size < header) return null

                if (String(type, Charsets.ISO_8859_1) == "vapc") {
                    val payload = (size - header).toInt()
                    if (payload <= 0 || payload > 4 * 1024 * 1024) return null
                    val json = ByteArray(payload).also { raf.readFully(it) }
                    return JSONObject(String(json, Charsets.UTF_8)).optJSONObject("info")
                }
                offset += size
            }
        }
        return null
    }
}
