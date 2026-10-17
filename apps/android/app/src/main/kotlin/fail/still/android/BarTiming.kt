// How long a switch between places on the bottom bar takes, and where the time goes (docs/telemetry.md → Android:
// `bar_switch`): from the finger lifted to the place's page on the stack, to the page shown (once it has what it opens
// with, App.kt Pages, LOCAL_MS at most), its first composition and first frame drawn; and for each topic the page
// follows anew, how long the core took to give its first value, decoding it, and how big it was. Logged on the device
// (`adb logcat -s StillfailTiming`), and to PostHog as the account signed in, in a build with its key (Crashes.kt).
// Only names of places and topics, counts and times: nothing a person wrote, no ids.
package fail.still.android

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.MotionEvent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import fail.still.android.data.TopicTiming
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.addJsonObject
import java.util.UUID

object BarTiming {
    private const val TAG = "StillfailTiming"
    /** A switch is told once its page is drawn and each topic it followed anew has a value; at the latest this long after. */
    private const val LONGEST_MS = 3_000L
    /** A finger lifted longer ago than this is not what switched (the back gesture, a switch from the bars' panel landing). */
    private const val TAP_MS = 1_000L
    /** Sent to PostHog in batches: once this many are waiting, or this long after the first. */
    private const val BATCH = 20
    private const val BATCH_MS = 60_000L

    @Volatile private var context: Context? = null
    @Volatile private var lastUp = 0L
    private val main = Handler(Looper.getMainLooper())
    /** The places shown since the app started, and when each was last left (ns). */
    private val seen = HashSet<String>()
    private val left = HashMap<String, Long>()
    /** The switch being timed; a new one tells it as it stands. */
    @Volatile private var on: Switch? = null
    private val waiting = ArrayList<JsonObject>()

    private class Topic(val name: String, val at: Long, val opening: Boolean, val held: Boolean) {
        /** The core's first value reached the app (ns), its decoding (ns), and shown (set on the main thread). */
        var arrived = 0L
        var decoding = 0L
        var shown = 0L
        var failed = false
        var json: JsonElement? = null
    }

    private class Switch(val from: String?, val to: String, val page: String, val tap: Long, val touched: Boolean, val placed: Long, val first: Boolean, val awayMs: Long?) {
        var effect = 0L
        var snapped = 0L
        var waited = false
        var timedOut = false
        var composed = 0L
        var drawn = 0L
        var frame = 0L
        val topics = LinkedHashMap<JsonObject, Topic>()
        var done = false
        /** The frames' times (ns, Choreographer's) from the tap until it is told: how the main thread kept up meanwhile. */
        val frames = ArrayList<Long>()
        val ticking = object : Choreographer.FrameCallback {
            override fun doFrame(at: Long) {
                if (done || frames.size >= 200) return
                frames += at
                Choreographer.getInstance().postFrameCallback(this)
            }
        }
    }

    fun start(context: Context) {
        this.context = context.applicationContext
        TopicTiming.followed = ::followed
        TopicTiming.decoded = ::decoded
        TopicTiming.shown = ::shown
    }

    /** Every touch of the activity: the last finger lifted is where a switch from the bar begins. */
    fun touched(e: MotionEvent) { if (e.actionMasked == MotionEvent.ACTION_UP) lastUp = e.eventTime * 1_000_000 }

    /** A place's page put on the stack in place of `from`'s (AppState.place), on the main thread. */
    fun placed(from: Screen?, to: Screen) {
        val now = System.nanoTime()
        on?.let { finish(it, cut = true) }
        val place = placeOf(to) ?: return
        val was = from?.let(::placeOf)
        if (was != null) { left[was] = now; seen += was }
        val touched = lastUp != 0L && now - lastUp in 0..TAP_MS * 1_000_000
        val since = left[place]
        val s = Switch(was, place, to.id, if (touched) lastUp else now, touched, now, seen.add(place), since?.let { (now - it) / 1_000_000 })
        on = s
        Choreographer.getInstance().postFrameCallback(s.ticking)
        main.postDelayed({ finish(s, cut = false) }, LONGEST_MS)
    }

    /** The switch's effect in Pages has begun (the frame after the stack changed). */
    fun effect() { on?.takeIf { it.effect == 0L }?.effect = System.nanoTime() }

    /** The page is now the one shown: `waited` for what it opens with, until LOCAL_MS ran out (`timedOut`). */
    fun snapped(waited: Boolean, timedOut: Boolean) {
        val s = on ?: return
        if (s.snapped != 0L) return
        s.snapped = System.nanoTime(); s.waited = waited; s.timedOut = timedOut
    }

    /** A topic followed anew by a page (data/Topics.kt PageTopics), `held` if what it showed first was a value already. */
    fun followed(topic: JsonObject, held: Boolean) {
        val s = on ?: return
        if (s.done || s.drawn != 0L && System.nanoTime() - s.drawn > 500_000_000L) return
        synchronized(this) {
            if (topic in s.topics) return
            s.topics[topic] = Topic((topic["topic"] as? JsonPrimitive)?.content ?: "?", System.nanoTime(), s.snapped == 0L, held)
        }
    }

    /** A value of `topic` reached the app at `arrived` and was decoded by now (any thread). */
    fun decoded(topic: JsonObject, arrived: Long, value: JsonElement?, failed: Boolean) {
        val s = on ?: return
        val now = System.nanoTime()
        synchronized(this) {
            val t = s.topics[topic] ?: return
            if (t.arrived != 0L || (value == null && !failed)) return
            t.arrived = arrived; t.decoding = now - arrived; t.json = value; t.failed = failed
        }
    }

    /** What a topic followed by a page shows changed (main thread). */
    fun shown(topic: JsonObject, value: Any?, failed: Boolean) {
        val s = on ?: return
        val t = s.topics[topic] ?: return
        if (t.shown != 0L || (value == null && !failed)) return
        t.shown = System.nanoTime()
        settle(s)
    }

    /** The page `screen` composed and drawn: the first time after a switch to it is the switch's. */
    @Composable
    fun page(screen: Screen): Modifier {
        val s = on
        if (s != null && s.page == screen.id && s.snapped != 0L && s.composed == 0L) s.composed = System.nanoTime()
        // The same one each time it is composed again: a new one would be updated, and the page drawn again, each time.
        return remember(screen.id) { Modifier.drawWithContent {
            drawContent()
            val now = on
            if (now != null && now.page == screen.id && now.snapped != 0L && now.drawn == 0L) {
                now.drawn = System.nanoTime()
                // The frame after the one it was drawn in: by then it has been handed to the display.
                Choreographer.getInstance().postFrameCallback { now.frame = System.nanoTime(); settle(now) }
            }
        } }
    }

    private fun settle(s: Switch) {
        if (s.frame != 0L && synchronized(this) { s.topics.values.all { it.shown != 0L || it.held } }) finish(s, cut = false)
    }

    private fun ms(from: Long, to: Long): Double? = if (from == 0L || to == 0L) null else Math.round((to - from) / 10_000.0) / 100.0

    private fun finish(s: Switch, cut: Boolean) {
        if (s.done) return
        s.done = true
        if (on === s) on = null
        val topics = synchronized(this) { s.topics.values.toList() }
        // Between frames, up to the one the page was handed to the display in.
        val frames = s.frames.filter { s.frame == 0L || it <= s.frame }
        val gaps = frames.zipWithNext { a, b -> Math.round((b - a) / 100_000.0) / 10.0 }
        val at = System.currentTimeMillis() - (System.nanoTime() - s.tap) / 1_000_000
        // The values' sizes are counted away from the main thread, after the switch: counting them is work too.
        Thread {
            val event = buildJsonObject {
                put("from", s.from); put("to", s.to)
                put("first", s.first); s.awayMs?.let { put("away_ms", it) }
                put("touched", s.touched)
                put("place_ms", ms(s.tap, s.placed))
                put("effect_ms", ms(s.tap, s.effect))
                put("snap_ms", ms(s.tap, s.snapped))
                put("wait_ms", ms(s.effect, s.snapped))
                put("waited", s.waited); put("timed_out", s.timedOut)
                put("composed_ms", ms(s.tap, s.composed))
                put("drawn_ms", ms(s.tap, s.drawn))
                put("frame_ms", ms(s.tap, s.frame))
                put("cut", cut || s.frame == 0L)
                put("frames", frames.size)
                put("longest_frame_ms", gaps.maxOrNull())
                putJsonArray("frame_gaps_ms") { gaps.take(30).forEach { add(JsonPrimitive(it)) } }
                put("topics_count", topics.size)
                putJsonArray("topics") {
                    for (t in topics) addJsonObject {
                        put("topic", t.name)
                        put("opening", t.opening)
                        put("held", t.held)
                        // From the page following it to the core's value in the app, decoding it, on screen.
                        put("core_ms", ms(t.at, t.arrived))
                        put("decode_ms", ms(t.arrived, t.arrived + t.decoding))
                        put("shown_ms", ms(t.at, t.shown))
                        put("tap_shown_ms", ms(s.tap, t.shown))
                        t.json?.let { put("bytes", it.toString().toByteArray().size) }
                        if (t.failed) put("failed", true)
                    }
                }
            }
            android.util.Log.i(TAG, "bar_switch $event")
            send(at, event)
        }.start()
    }

    private fun send(at: Long, properties: JsonObject) {
        if (BuildConfig.POSTHOG_KEY.isEmpty()) return
        val context = context ?: return
        val batch = synchronized(waiting) {
            waiting += buildJsonObject {
                put("event", "bar_switch")
                put("distinct_id", Crashes.account(context) ?: return)
                put("uuid", UUID.randomUUID().toString())
                put("timestamp", Crashes.iso(at))
                put("properties", JsonObject(properties + Crashes.device()))
            }
            if (waiting.size == 1) main.postDelayed({ flush() }, BATCH_MS)
            if (waiting.size < BATCH) return
            waiting.toList().also { waiting.clear() }
        }
        try { Crashes.send(batch) } catch (_: Exception) { }
    }

    private fun flush() {
        val batch = synchronized(waiting) { waiting.toList().also { waiting.clear() } }
        if (batch.isNotEmpty()) Thread { try { Crashes.send(batch) } catch (_: Exception) { } }.start()
    }
}
