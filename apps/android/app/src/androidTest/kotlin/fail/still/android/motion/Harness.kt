// Frame by frame, on the test's clock (as the web's "animations paused, currentTime stepped"): the real app, on a fake
// core (FakeCore) with made-up data (Fixtures), its clock stopped; a motion is started, then each frame is stepped and
// pictured. What comes out, per recording, in the app's files (motion.sh pulls it and makes the videos):
//   <name>/f000.jpg …   every frame, full size (the videos)
//   <name>/settled.png   the page once everything has come to rest
//   <name>/strip.png     the frames in a grid, each with its time and how far it is from the settled page
//   <name>/diff.csv      frame, ms, share of pixels unlike the settled page, their mean difference
//   <name>/tape.json     what the mbui app (apps/mbui) replays to be compared with it (its src/sfapp/tape.mbt): the
//                        pages launched, the theme, the window, its system bars, the wall clock as it began; every
//                        topic's value as it starts; then, by the
//                        recording's ms, each value set, each call with its answer, each tap (by its words, or where
//                        it was), each finger's down, move and up, a list put at its top, each page pushed, each
//                        back; and each frame's words
//                        where they were drawn (each text node of the semantics: its top left in the root, as moved
//                        and scaled by the layers over it, its size, and whether any of it shows), in dp
// A motion that ends precisely has its difference fall smoothly to 0; one that snaps at the end drops to 0 at once
// (the largest drop between two frames is logged, tag "motion").
package fail.still.android.motion

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.geometry.Offset
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.StillFailApp
import fail.still.android.Updates
import fail.still.android.data.PrefsView
import fail.still.android.data.Topics
import fail.still.android.data.I18n
import fail.still.android.ui.KeyboardAt
import fail.still.android.ui.StillFailTheme
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.performSemanticsAction
import fail.still.android.data.ChatOf
import java.io.File
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.FileOutputStream
import kotlin.math.abs
import fail.still.android.ui.LocalUi

typealias MotionRule = AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>

/** The app on a fake core, in `rule`'s activity. */
class Harness(val rule: MotionRule) {
    val fake = FakeCore()
    lateinit var app: AppState
        private set
    /** The pages it was launched with, and its theme (a recording's tape says them). */
    var launched: List<Screen> = emptyList()
        private set
    var dark = false
        private set

    init {
        // The words as the tests expect them: in Chinese, whatever the emulator's language (en-US).
        I18n.load(InstrumentationRegistry.getInstrumentation().targetContext)
        I18n.lang = "zh"
    }

    /**
     * Shows the app signed in to Fixtures' workspace, with the pages of `stack` over its list (the last on top), in the
     * light or dark theme, with the prefs `kept` (the core's as the app starts); lets it come to rest. `uris`: what opens the links the app hands the system (by default the
     * system's own).
     */
    fun launch(stack: List<Screen>, dark: Boolean = false, uris: UriHandler? = null, keyboard: WindowInsets? = null, kept: PrefsView = PrefsView()) {
        launched = stack
        this.dark = dark
        fake.put(Topics.accounts, listOf(Fixtures.account))
        fake.put(Topics.workspaces, Fixtures.workspaces)
        fake.put(Topics.stations(Fixtures.WS), listOf(Fixtures.station))
        val context = rule.activity
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putBoolean("notifyAsked", true).putString("workspace", Fixtures.WS).putString("theme", if (dark) "dark" else "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        fail.still.android.ui.FaceFiles.init(context)
        app = AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", fake.core), kept)
        stack.forEach { if (it != Screen.Home) app.push(it) }
        rule.setContent {
            // As MainActivity: the faces chosen (ui/Fonts.kt).
            StillFailTheme(dark, fail.still.android.ui.rememberFonts(app.kept.faces)) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    val shown = @Composable { if (uris == null) StillFailApp(app) else CompositionLocalProvider(LocalUriHandler provides uris) { StillFailApp(app) } }
                    if (keyboard == null) shown() else KeyboardAt(keyboard) { shown() }
                }
            }
        }
        settle()
    }

    /** Runs the clock until what moves has come to rest (and what the core sent has come in). */
    fun settle(ms: Long = 1500) {
        rule.mainClock.autoAdvance = true
        repeat(3) { Thread.sleep(40); rule.waitForIdle() }
        rule.mainClock.advanceTimeBy(ms)
        repeat(3) { Thread.sleep(40); rule.waitForIdle() }
    }

    /** Waits (on the system's clock) for the keyboard a focused field brought up, then lets the page come to rest. */
    fun keyboard() { settle(); Thread.sleep(1200); settle() }

    /** Lets what the fake core sent (on its own threads) reach the page, without moving the clock. */
    fun deliver() { repeat(3) { Thread.sleep(30); rule.waitForIdle() } }

    /** A new recording, `name` its directory; the clock stops until it ends. */
    fun record(name: String, region: Rect? = null, ignore: List<Rect> = emptyList()): Recording = Recording(this, name, region, ignore)
}

/**
 * Frames of one motion: `frame()` steps the clock one frame (16 ms) and pictures the page; `end()` lets it come to
 * rest, pictures that, and writes the strip and the differences. `region` (in the screen's pixels): the part compared
 * with the settled page (all of it by default); it should hold everything that moves. `ignore`: parts left out of the
 * comparison that never settle (a caret blinking, a spinner, an agent's ring turning): with them in, the difference
 * cannot reach 0. Frames and the settled page are compared as they were captured (in memory, lossless), not as the
 * JPEGs written for the videos.
 */
class Recording(private val h: Harness, val name: String, private val region: Rect?, private val ignore: List<Rect> = emptyList()) {
    val dir: File = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "motion/$name").apply { deleteRecursively(); mkdirs() }
    private val small = ArrayList<Bitmap>()
    private val times = ArrayList<Long>()
    private var t = 0L

    /** The tape (tape.json): what happened, by ms, and each frame's words. */
    private val events = java.util.Collections.synchronizedList(ArrayList<JsonObject>())
    private val texts = ArrayList<JsonObject>()
    private val start = h.fake.snapshot()
    /** The wall clock as it began (what the app's times are worked out from: an agent's `since`, a message's "刚刚"). */
    private val wall = System.currentTimeMillis()

    init {
        h.rule.mainClock.autoAdvance = false
        h.fake.heard = { e -> events += JsonObject(e + ("t" to JsonPrimitive(t))) }
        shot()
    }

    /** The words of `text` tapped (as its semantics' click), told to the tape. */
    fun tap(text: String) {
        events += buildJsonObject { put("t", t); put("tap", text) }
        h.rule.onNode(hasText(text)).performSemanticsAction(SemanticsActions.OnClick)
    }

    /** The page `s` pushed over what shows (as a tap on a row does), told to the tape. */
    fun push(s: Screen) {
        events += buildJsonObject { put("t", t); put("push", screenJson(s)) }
        h.rule.runOnUiThread { h.app.push(s) }
    }

    /** What is described as `description` (an icon's button) tapped, told to the tape. */
    fun tapDescribed(description: String) {
        events += buildJsonObject { put("t", t); put("tapDescribed", description) }
        h.rule.onNode(hasContentDescription(description)).performSemanticsAction(SemanticsActions.OnClick)
    }

    /** A finger put down and lifted at once at `at` (px in the root), told to the tape (in dp). */
    fun tapAt(at: Offset) {
        val d = h.rule.density.density
        events += buildJsonObject { put("t", t); put("tapAt", buildJsonObject { put("x", at.x / d); put("y", at.y / d) }) }
        h.rule.onRoot().performTouchInput { down(at); up() }
    }

    /** A finger `down`, moved (`move`) or lifted (`up`) at `at` (px in the root), told to the tape (in dp). */
    fun finger(kind: String, at: Offset) {
        val d = h.rule.density.density
        events += buildJsonObject { put("t", t); put("finger", kind); put("x", at.x / d); put("y", at.y / d) }
        h.rule.onRoot().performTouchInput {
            when (kind) {
                "down" -> down(at)
                "move" -> moveTo(at, delayMillis = 0)
                else -> up()
            }
        }
    }

    /**
     * The list in view (of those side by side, the one on the screen) at its top, as its semantics' ScrollToIndex 0 has
     * it (not dragged there: a finger held at a list's top stretches it, and the stretch never lets the paused clock's
     * page come to idle), told to the tape.
     */
    fun listTop() {
        events += buildJsonObject { put("t", t); put("listTop", true) }
        val w = h.rule.onRoot().fetchSemanticsNode().size.width
        val lists = h.rule.onAllNodes(hasScrollToIndexAction())
        val at = lists.fetchSemanticsNodes().indexOfFirst { it.boundsInRoot.left >= 0f && it.boundsInRoot.left < w }
        lists[at].performScrollToIndex(0)
    }

    /** The system's back (the back gesture let go, or its key), told to the tape. */
    fun back() {
        events += buildJsonObject { put("t", t); put("back", true) }
        h.rule.runOnUiThread { h.rule.activity.onBackPressedDispatcher.onBackPressed() }
    }

    /** The words drawn now: each text node, in dp. */
    private fun words(): JsonObject {
        val d = h.rule.density.density
        val nodes = ArrayList<JsonObject>()
        fun walk(n: SemanticsNode) {
            val words = n.config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text }.orEmpty()
            if (words.isNotEmpty()) {
                val at = n.positionInRoot
                val b = n.boundsInRoot
                nodes += buildJsonObject {
                    put("text", words)
                    put("x", at.x / d); put("y", at.y / d); put("w", n.size.width / d); put("h", n.size.height / d)
                    put("shown", b.width > 0f && b.height > 0f)
                }
            }
            n.children.forEach { walk(it) }
        }
        walk(h.rule.onRoot(useUnmergedTree = true).fetchSemanticsNode())
        return buildJsonObject { put("t", t); put("words", JsonArray(nodes)) }
    }

    /** tape.json (see the file's head). */
    private fun tape() {
        val root = h.rule.onRoot().fetchSemanticsNode()
        val d = h.rule.density.density
        val out = buildJsonObject {
            put("name", name)
            put("launched", JsonArray(h.launched.map { screenJson(it) }))
            put("dark", h.dark)
            put("window", buildJsonObject { put("w", root.size.width / d); put("h", root.size.height / d) })
            // the system bars over the window (edge to edge: the app pads its pages by them)
            var top = 0f
            var bottom = 0f
            h.rule.runOnUiThread {
                h.rule.activity.window.decorView.rootWindowInsets?.getInsets(android.view.WindowInsets.Type.systemBars())?.let {
                    top = it.top / d; bottom = it.bottom / d
                }
            }
            put("bars", buildJsonObject { put("top", top); put("bottom", bottom) })
            put("wall", wall)
            put("topics", JsonArray(start.map { (topic, value) -> buildJsonObject { put("topic", topic); put("value", value) } }))
            put("events", JsonArray(synchronized(events) { events.toList() }))
            put("frames", JsonArray(texts))
        }
        File(dir, "tape.json").writeText(out.toString())
    }

    /** The window as drawn (PixelCopy; an emulator's GPU now and then misses one, or the window is busy a moment: asked again). */
    private fun capture(): Bitmap {
        repeat(5) { attempt ->
            try { return h.rule.onRoot().captureToImage().asAndroidBitmap() } catch (e: Throwable) {
                if (e !is AssertionError && e !is androidx.compose.ui.test.ComposeTimeoutException) throw e
                Log.w("motion", "$name: capture failed (${e.message}), again")
                Thread.sleep(200L * (attempt + 1))
            }
        }
        return h.rule.onRoot().captureToImage().asAndroidBitmap()
    }

    /** The last frame as captured, kept to be written losslessly beside the settled page (last.png). */
    private var lastFull: Bitmap? = null

    private fun shot() {
        val full = capture()
        lastFull = full
        FileOutputStream(File(dir, "f%03d.jpg".format(small.size))).use { full.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        small += Bitmap.createScaledBitmap(full, full.width / SCALE, full.height / SCALE, true)
        times += t
        texts += words()
    }

    /** One frame on (after `before`, done at the frame's start: data arriving, a tap), pictured. */
    fun frame(before: () -> Unit = {}) {
        before()
        // What the fake core answers (on its own threads) lands before the frame, as it would between two real ones.
        Thread.sleep(12)
        h.rule.waitForIdle()
        h.rule.mainClock.advanceTimeByFrame()
        t += 16
        shot()
    }

    fun frames(n: Int) = repeat(n) { frame() }

    /** Steps frames until `done` (at most `most`). */
    fun framesUntil(most: Int = 120, done: () -> Boolean) { var i = 0; while (i++ < most && !done()) frame() }

    /** Lets it come to rest and writes what it saw. Answers the largest drop, between two frames, of the share unlike the settled page. */
    fun end(): Float {
        h.fake.heard = null
        tape()
        lastFull?.let { l -> FileOutputStream(File(dir, "last.png")).use { l.compress(Bitmap.CompressFormat.PNG, 100, it) } }
        h.settle(2000)
        val settledFull = capture()
        FileOutputStream(File(dir, "settled.png")).use { settledFull.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val settled = Bitmap.createScaledBitmap(settledFull, settledFull.width / SCALE, settledFull.height / SCALE, true)
        // And half a second on: a caret blinks (on 500 ms, off 500), so the settled page is either; each pixel is
        // compared with the nearer of the two.
        h.rule.mainClock.advanceTimeBy(500)
        h.rule.waitForIdle()
        val later = capture().let { Bitmap.createScaledBitmap(it, it.width / SCALE, it.height / SCALE, true) }
        val box = region?.let { Rect(it.left / SCALE, it.top / SCALE, it.right / SCALE, it.bottom / SCALE) } ?: Rect(0, 0, settled.width, settled.height)
        val cut = ignore.map { Rect(it.left / SCALE, it.top / SCALE, (it.right + SCALE - 1) / SCALE, (it.bottom + SCALE - 1) / SCALE) }
        val diffs = small.map { diff(it, settled, later, box, cut) }
        File(dir, "diff.csv").writeText("frame,ms,unlike,mean\n" + diffs.mapIndexed { i, d -> "$i,${times[i]},${"%.4f".format(d.first)},${"%.2f".format(d.second)}" }.joinToString("\n") + "\n")
        strip(diffs.map { it.first }, box)
        val drop = diffs.zipWithNext { a, b -> a.first - b.first }.maxOrNull() ?: 0f
        Log.i("motion", "$name: ${small.size} frames, unlike the settled page ${diffs.joinToString(" ") { "%.3f".format(it.first) }}; largest drop ${"%.3f".format(drop)}")
        return drop
    }

    /** The share of pixels in `box` that differ (by more than a little) from the settled page, and their mean difference. */
    private fun diff(a: Bitmap, b: Bitmap, c: Bitmap, box: Rect, cut: List<Rect>): Pair<Float, Float> {
        val w = box.width(); val hgt = box.height()
        val pa = IntArray(w * hgt); val pb = IntArray(w * hgt); val pc = IntArray(w * hgt)
        a.getPixels(pa, 0, w, box.left, box.top, w, hgt); b.getPixels(pb, 0, w, box.left, box.top, w, hgt); c.getPixels(pc, 0, w, box.left, box.top, w, hgt)
        var unlike = 0; var sum = 0L; var n = 0
        for (i in pa.indices) {
            if (cut.isNotEmpty() && cut.any { it.contains(box.left + i % w, box.top + i / w) }) continue
            n++
            val x = pa[i]; val y = pb[i]; val z = pc[i]
            val d = minOf(
                abs(Color.red(x) - Color.red(y)) + abs(Color.green(x) - Color.green(y)) + abs(Color.blue(x) - Color.blue(y)),
                abs(Color.red(x) - Color.red(z)) + abs(Color.green(x) - Color.green(z)) + abs(Color.blue(x) - Color.blue(z)),
            )
            sum += d
            if (d > 24) unlike++
        }
        return unlike.toFloat() / maxOf(n, 1) to sum.toFloat() / maxOf(n, 1) / 3f
    }

    private fun strip(unlike: List<Float>, box: Rect) {
        val cols = 8
        val cw = small[0].width; val ch = small[0].height; val label = 34
        val rows = (small.size + cols - 1) / cols
        val out = Bitmap.createBitmap(cols * cw, rows * (ch + label), Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        c.drawColor(Color.rgb(40, 40, 40))
        val text = Paint().apply { color = Color.WHITE; textSize = 22f; isAntiAlias = true }
        val frame = Paint().apply { color = Color.rgb(255, 120, 60); style = Paint.Style.STROKE; strokeWidth = 2f }
        small.forEachIndexed { i, b ->
            val x = (i % cols) * cw; val y = (i / cols) * (ch + label)
            c.drawBitmap(b, x.toFloat(), (y + label).toFloat(), null)
            if (region != null) c.drawRect((x + box.left).toFloat(), (y + label + box.top).toFloat(), (x + box.right).toFloat(), (y + label + box.bottom).toFloat(), frame)
            c.drawText("f$i ${times[i]}ms Δ${"%.1f".format(unlike[i] * 100)}%", x + 6f, y + 25f, text)
        }
        FileOutputStream(File(dir, "strip.png")).use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private companion object { const val SCALE = 3 }
}

/** A page as a tape says it (tape.json `launched`): a chat by its station and thread or session, else its name. */
private fun screenJson(s: Screen): JsonElement = when (s) {
    is Screen.Chat -> buildJsonObject {
        put("chat", s.station)
        when (val of = s.of) { is ChatOf.Thread -> put("thread", of.id); is ChatOf.Session -> put("session", of.key) }
    }
    else -> JsonPrimitive(s::class.simpleName ?: s.toString())
}
