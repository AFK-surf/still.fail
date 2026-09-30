// Frame by frame, on the test's clock (as the web's "animations paused, currentTime stepped"): the real app, on a fake
// core (FakeCore) with made-up data (Fixtures), its clock stopped; a motion is started, then each frame is stepped and
// pictured. What comes out, per recording, in the app's files (motion.sh pulls it and makes the videos):
//   <name>/f000.jpg …   every frame, full size (the videos)
//   <name>/settled.png   the page once everything has come to rest
//   <name>/strip.png     the frames in a grid, each with its time and how far it is from the settled page
//   <name>/diff.csv      frame, ms, share of pixels unlike the settled page, their mean difference
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onRoot
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.StillFailApp
import fail.still.android.Updates
import fail.still.android.data.Topics
import fail.still.android.ui.StillFailTheme
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs

typealias MotionRule = AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>

/** The app on a fake core, in `rule`'s activity. */
class Harness(val rule: MotionRule) {
    val fake = FakeCore()
    lateinit var app: AppState
        private set

    /**
     * Shows the app signed in to Fixtures' workspace, with the pages of `stack` over its list (the last on top), in the
     * light or dark theme; lets it come to rest.
     */
    fun launch(stack: List<Screen>, dark: Boolean = false) {
        fake.put(Topics.accounts, listOf(Fixtures.account))
        fake.put(Topics.workspaces, Fixtures.workspaces)
        fake.put(Topics.stations(Fixtures.WS), listOf(Fixtures.station))
        val context = rule.activity
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putBoolean("notifyAsked", true).putString("workspace", Fixtures.WS).putString("theme", if (dark) "dark" else "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        app = AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9"))
        stack.forEach { if (it != Screen.Home) app.push(it) }
        rule.setContent { StillFailTheme(dark) { CompositionLocalProvider(LocalApp provides app) { StillFailApp(app) } } }
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

    init {
        h.rule.mainClock.autoAdvance = false
        shot()
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
