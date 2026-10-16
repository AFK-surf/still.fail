// One view of a station's screen (docs/remote-screens.md, docs/client-core.md `screen.view`): the core's call kept open
// while the viewer is on screen, its values taken apart (the state, a config, frames with their bytes), frames handed to
// the decoders, each acknowledged once shown; input, 只看/控制 and key frames told back to the core. The connection, the
// credentials and the reconnecting are the core's; this only draws what it says.
package fail.still.android.remote

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.IntSize
import fail.still.android.data.ScreenViewState
import fail.still.android.data.decode
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** A JPEG frame decoded, as the viewer draws it. */
class Picture(val bitmap: Bitmap, val ts: Long)

/**
 * `station` is its address (`<workspace>/<station>`), `screen` its id there; `limit`: the largest frame worth sending
 * (the phone's screen, in px, its longer side first); `h264`: the phone decodes it (else JPEG only).
 */
class ScreenSession(
    private val core: StillFailCore,
    val station: String,
    val screen: String,
    private val scope: CoroutineScope,
    private val limit: IntSize = IntSize(1920, 1080),
    private val h264: Boolean = H264Decoder.available,
) {
    /** The name the core knows this view by (unique per viewer). */
    val view = "android-" + UUID.randomUUID().toString().take(8)

    /** The core's latest state of the view (whole each time); null before the first. */
    var state by mutableStateOf<ScreenViewState?>(null); private set
    /** The call failed (the core said why), rather than the view ending. */
    var failure by mutableStateOf<String?>(null); private set
    /** The call answered: the view ended (the last state says why). */
    var finished by mutableStateOf(false); private set
    /** The frames' codec and size, from the latest config. */
    var codec by mutableStateOf<String?>(null); private set
    var size by mutableStateOf<IntSize?>(null); private set
    /** The JPEG frame to draw now; a frame of H.264 goes straight to the surface. */
    var picture by mutableStateOf<Picture?>(null); private set
    /** Something was shown since it opened: a frame kept on screen through a reconnect or an end. */
    var shownAny by mutableStateOf(false); private set
    /** 控制 (true) or 只看, as the person chose. */
    var wantsControl by mutableStateOf(true); private set

    private val main = Handler(Looper.getMainLooper())
    private var job: Job? = null
    private val lock = Any()
    private var acked = Long.MIN_VALUE
    /** The bitmaps drawn last: the one before the one on screen goes back to the decoder once a newer one is drawn. */
    private val drawn = ArrayDeque<Picture>()
    private var surface: Surface? = null

    private val video = H264Decoder(shown = { ts -> ack(ts); main.post { shownAny = true } }, broken = { core.tell("screen.keyframe", viewParams()) })
    private val jpeg = JpegDecoder(decoded = { bitmap, ts -> main.post { picture = Picture(bitmap, ts) } }, failed = { ts -> ack(ts) })

    /** What the phase is as the viewer shows it: the call's own failure and end over what the state last said. */
    val phase: String get() {
        if (failure != null) return "failed"
        val p = state?.phase ?: "connecting"
        return if (finished && p in setOf("connecting", "live", "reconnecting")) "ended" else p
    }

    /** Why, in the viewer's words, for a phase that needs saying. */
    val message: String? get() = failure ?: state?.message

    /** Input goes to the station now: it is live and driven by this viewer. */
    val driving: Boolean get() = phase == "live" && state?.control == true

    /** Opens the view (again: after a pause, or 再试一次). */
    fun open() {
        if (job?.isActive == true) return
        // Again after it ended (再试一次): on its way, not still saying how the last one ended.
        if (finished || failure != null) state = null
        failure = null
        finished = false
        val params = buildJsonObject {
            put("station", station)
            put("screen", screen)
            put("view", view)
            put("codecs", JsonArray(listOfNotNull(if (h264) "h264" else null, "jpeg").map(::JsonPrimitive)))
            put("maxWidth", limit.width)
            put("maxHeight", limit.height)
            put("control", wantsControl)
        }
        job = scope.launch {
            try {
                core.stream("screen.view", params, ::take)
                main.post { finished = true }
            } catch (e: CancellationException) {
                throw e
            } catch (e: CoreException) {
                main.post { failure = e.message }
            }
        }
    }

    /** Stops viewing (the app went out of sight); the last frame stays, [open] goes on from it. */
    fun pause() {
        job?.cancel()
        job = null
    }

    /** Ends it for good: the view, the decoders. */
    fun close() {
        pause()
        video.release()
        jpeg.release()
    }

    /** The surface H.264 is drawn on, as the viewer's texture comes and goes. */
    fun surface(s: Surface?) {
        surface = s
        video.surface(s)
    }

    /** 只看 or 控制: the core opens the view again with it, the frame on screen kept meanwhile. */
    fun control(on: Boolean) {
        wantsControl = on
        core.tell("screen.control", buildJsonObject { put("view", view); put("control", on) })
    }

    /** Input for the station (`screen.input`): only while this viewer drives it. */
    fun input(input: JsonObject) {
        if (!driving) return
        core.tell("screen.input", buildJsonObject { put("view", view); put("input", input) })
    }

    /** The viewer drew `p`: acknowledged, and the bitmap two frames back given to the decoder again. */
    fun drew(p: Picture) {
        if (drawn.lastOrNull() === p) return
        ack(p.ts)
        drawn.addLast(p)
        while (drawn.size > 2) jpeg.reuse(drawn.removeFirst().bitmap)
        if (!shownAny) shownAny = true
    }

    private fun viewParams() = buildJsonObject { put("view", view) }

    private fun ack(ts: Long) {
        synchronized(lock) {
            if (ts <= acked) return
            acked = ts
        }
        core.tell("screen.ack", buildJsonObject { put("view", view); put("ts", ts) })
    }

    /** A value of the call, on the core's thread: taken apart, the heavy parts handed on. */
    private fun take(value: JsonElement, bytes: ByteArray?) {
        val o = value as? JsonObject ?: return
        o["state"]?.let { s ->
            val next = try { decode(ScreenViewState.serializer(), s) } catch (e: CoreException) { core.reportError("android.screen", e.message); null }
            if (next != null) main.post { state = next }
        }
        (o["config"] as? JsonObject)?.let { c ->
            val kind = (c["codec"] as? JsonPrimitive)?.contentOrNull ?: return@let
            val w = (c["width"] as? JsonPrimitive)?.intOrNull ?: (c["width"] as? JsonPrimitive)?.contentOrNull?.toDoubleOrNull()?.toInt() ?: 0
            val h = (c["height"] as? JsonPrimitive)?.intOrNull ?: (c["height"] as? JsonPrimitive)?.contentOrNull?.toDoubleOrNull()?.toInt() ?: 0
            if (kind == "h264" && bytes != null) video.configure(bytes, w, h)
            main.post { codec = kind; if (w > 0 && h > 0) size = IntSize(w, h) }
            synchronized(lock) { this.kind = kind }
        }
        (o["frame"] as? JsonObject)?.let { f ->
            val ts = (f["ts"] as? JsonPrimitive)?.let { it.longOrNull ?: it.contentOrNull?.toDoubleOrNull()?.toLong() } ?: return@let
            val key = (f["key"] as? JsonPrimitive)?.booleanOrNull ?: false
            if (bytes == null) { ack(ts); return@let }
            when (synchronized(lock) { kind }) {
                "h264" -> video.frame(bytes, key, ts)
                "jpeg" -> jpeg.frame(bytes, ts)
                else -> ack(ts)
            }
        }
    }

    /** The codec of the frames coming now (the core's thread's own view of it, ahead of `codec` on the main thread). */
    private var kind: String? = null
}
