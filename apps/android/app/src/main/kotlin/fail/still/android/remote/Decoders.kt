// A screen's frames decoded off the main thread (docs/remote-screens.md): H.264 or H.265 by MediaCodec straight onto a surface,
// JPEG by BitmapFactory into bitmaps the viewer draws. Each frame is acknowledged once it is shown (H.264: released to
// the surface; JPEG: drawn by the viewer), or dropped: the station sends no more while those it sent wait
// unacknowledged (docs/remote-screens.md, "Pace"), so a frame that is never acknowledged would stop the stream.
package fail.still.android.remote

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.util.ArrayDeque
import java.util.concurrent.Executors

private const val TAG = "screen"

/**
 * H.264 or H.265 onto `surface` (set as the viewer's texture comes and goes): reconfigured on each config, reset on a decoder
 * error. `shown`: a frame's timestamp once it is on the surface (or dropped); `broken`: the decoder lost its state
 * (an error, a new surface), the next frame has to be a key frame (`screen.keyframe`); `unplayable`: H.265 that the
 * phone said it decodes failed before a frame came out (from then on [hevcFailed]: the view is opened again for H.264).
 * Everything runs on its own
 * thread, the codec's callbacks too.
 */
internal class VideoDecoder(private val shown: (Long) -> Unit, private val broken: () -> Unit, private val unplayable: () -> Unit = {}) {
    private class Frame(val data: ByteArray, val key: Boolean, val ts: Long)

    private val thread = HandlerThread("screen-video").apply { start() }
    private val handler = Handler(thread.looper)
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var config: VideoConfig? = null
    private var width = 0
    private var height = 0
    /** Frames waiting for an input buffer, and the free input buffers. */
    private val waiting = ArrayDeque<Frame>()
    private val inputs = ArrayDeque<Int>()
    /** Frames in the decoder, not out on the surface yet (their timestamps, in order). */
    private val inside = ArrayDeque<Long>()
    /** Until a key frame comes, frames are dropped (a decoder started anew, or broken). */
    private var needKey = true
    private var released = false
    /** A frame came out of a decoder of this view's. */
    private var played = false

    /** H.265 that cannot be had here after all: the view goes to H.264. */
    private fun h265Failed(c: VideoConfig?): Boolean {
        if (c !is HevcConfig || played) return false
        hevcFailed = true
        unplayable()
        return true
    }

    /** The surface it draws on; null while there is none (frames are dropped meanwhile). */
    fun surface(s: Surface?) = handler.post {
        if (s === surface) return@post
        surface = s
        // A decoder on a new surface starts anew, from a key frame (none comes by itself: asked for).
        if (start()) broken()
    }

    /** A config: its codec (`h264`, `h265`), its avcC or hvcC (`description`) and the frame's size. */
    fun configure(codec: String, description: ByteArray, width: Int, height: Int) = handler.post {
        val parsed = parseConfig(codec, description)
        if (parsed == null) {
            Log.w(TAG, "a $codec config that is not one (${description.size} bytes)")
            config = null
            stop()
            return@post
        }
        config = parsed
        this.width = width
        this.height = height
        // The station's next frame after a config is a key frame.
        start()
    }

    fun frame(data: ByteArray, key: Boolean, ts: Long) = handler.post {
        if (codec == null || (needKey && !key)) {
            shown(ts)
            return@post
        }
        needKey = false
        waiting += Frame(data, key, ts)
        feed()
    }

    fun release() = handler.post {
        released = true
        stop()
        thread.quitSafely()
    }

    /** A decoder for the config and surface there are (none without either); answers whether there is one now. */
    private fun start(): Boolean {
        stop()
        val c = config ?: return false
        val s = surface ?: return false
        if (released) return false
        return try {
            val format = MediaFormat.createVideoFormat(c.mime, width.coerceAtLeast(16), height.coerceAtLeast(16))
            c.into(format)
            // A key frame of a whole screen can be large; the decoder's own guess for the size is often too small.
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, (width * height).coerceAtLeast(1 shl 20))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            format.setInteger(MediaFormat.KEY_PRIORITY, 0)
            val made = MediaCodec.createDecoderByType(c.mime)
            made.setCallback(callback, handler)
            made.configure(format, s, null, 0)
            made.start()
            codec = made
            needKey = true
            true
        } catch (e: Exception) {
            Log.w(TAG, "no ${c.mime} decoder", e)
            stop()
            h265Failed(c)
            false
        }
    }

    private fun stop() {
        codec?.let { c -> try { c.stop() } catch (_: Exception) {}; try { c.release() } catch (_: Exception) {} }
        codec = null
        inputs.clear()
        // What was waiting or inside is let go: taken, as far as the station is concerned.
        (waiting.map { it.ts } + inside).maxOrNull()?.let(shown)
        waiting.clear()
        inside.clear()
        needKey = true
    }

    private fun feed() {
        val c = codec ?: return
        val lengthSize = config?.lengthSize ?: return
        while (inputs.isNotEmpty() && waiting.isNotEmpty()) {
            val index = inputs.removeFirst()
            val f = waiting.removeFirst()
            val buffer = c.getInputBuffer(index) ?: continue
            buffer.clear()
            val n = writeAnnexB(f.data, lengthSize, buffer)
            if (n < 0) {
                // Not a frame it can take: given back empty, the next key frame asked for.
                c.queueInputBuffer(index, 0, 0, f.ts, 0)
                shown(f.ts)
                needKey = true
                broken()
                continue
            }
            c.queueInputBuffer(index, 0, n, f.ts, if (f.key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            inside += f.ts
            // A decoder that holds frames back (some keep one or two before the first comes out) would wait for more
            // while the station waits for an acknowledgement: with two inside, the older one counts as taken.
            if (inside.size >= 2) shown(inside.removeFirst())
        }
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            if (codec !== this@VideoDecoder.codec) return
            inputs += index
            feed()
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            if (codec !== this@VideoDecoder.codec) return
            val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
            try { codec.releaseOutputBuffer(index, !config && info.size > 0) } catch (_: Exception) { return }
            if (config) return
            val ts = info.presentationTimeUs
            if (info.size > 0) played = true
            while (inside.isNotEmpty() && inside.first() <= ts) inside.removeFirst()
            shown(ts)
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            if (codec !== this@VideoDecoder.codec) return
            Log.w(TAG, "the video decoder failed", e)
            if (h265Failed(config)) { stop(); return }
            // Anew, from the next key frame.
            if (start()) broken()
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {}
    }

    companion object {
        private fun decoders(mime: String) = try {
            android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
                !info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
            }
        } catch (_: Exception) { emptyList() }

        /** Whether the phone has an H.264 decoder at all (else the view asks for JPEG only). */
        val available: Boolean by lazy { decoders(MediaFormat.MIMETYPE_VIDEO_AVC).isNotEmpty() }

        /** H.265 failed on this phone though it said it decodes it: not asked again while the app runs. */
        @Volatile var hevcFailed = false

        /** Whether it decodes H.265 on its hardware (a software decoder of a screen's frames is too slow to ask it). */
        val hevc: Boolean by lazy { decoders(MediaFormat.MIMETYPE_VIDEO_HEVC).any { it.isHardwareAccelerated } }
    }
}

/**
 * JPEG frames decoded on a thread of their own into bitmaps for the viewer to draw (`decoded`, on that thread). Bitmaps
 * the viewer no longer draws come back (`reuse`) and are decoded into again: a frame a whole screen large is 8 MB.
 */
internal class JpegDecoder(private val decoded: (Bitmap, Long) -> Unit, private val failed: (Long) -> Unit) {
    private val executor = Executors.newSingleThreadExecutor { Thread(it, "screen-jpeg") }
    private val spare = ArrayDeque<Bitmap>()
    @Volatile private var released = false

    fun frame(data: ByteArray, ts: Long) {
        if (released) return
        executor.execute {
            if (released) return@execute
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
            val into = synchronized(spare) {
                spare.firstOrNull { it.width == bounds.outWidth && it.height == bounds.outHeight && it.isMutable && !it.isRecycled }?.also { spare.remove(it) }
            }
            val options = BitmapFactory.Options().apply {
                inMutable = true
                inPreferredConfig = Bitmap.Config.ARGB_8888
                inBitmap = into
            }
            val bitmap = try {
                BitmapFactory.decodeByteArray(data, 0, data.size, options)
            } catch (_: IllegalArgumentException) {
                // The spare one did not fit after all: into a new one.
                BitmapFactory.decodeByteArray(data, 0, data.size, options.apply { inBitmap = null })
            }
            if (bitmap == null) failed(ts) else decoded(bitmap, ts)
        }
    }

    /** A bitmap the viewer is done with (two frames on), to decode into again. */
    fun reuse(bitmap: Bitmap) {
        if (released) return
        synchronized(spare) { if (spare.size < 2) spare += bitmap }
    }

    fun release() {
        released = true
        executor.shutdown()
        synchronized(spare) { spare.clear() }
    }
}
