// The screens the mbui app is held to (client/fixtures/screens): each drawn by this app, the original, over the core's
// JSON the screen's file gives (the same file the mbui app draws from: apps/mbui/scripts/android-ref.sh), opened at
// the pages it names, pictured at the moment it names on the test's clock, once the words it names are on the screen.
// What comes out: <files>/screens/<name>.png, the whole screen as the system shows it (the system's bars in demo mode,
// set by the script that runs this).
package fail.still.android.motion

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.platform.graphics.HardwareRendererCompat
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.StillFailApp
import fail.still.android.Updates
import fail.still.android.data.ChatOf
import fail.still.android.data.I18n
import fail.still.android.data.PrefsView
import fail.still.android.ui.LocalUi
import fail.still.android.ui.StillFailTheme
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/**
 * One run a screen (`name`: client/fixtures/screens/NAME.json): every screen there, or those the instrumentation's
 * `screens` argument names (scripts/android-ref.sh refs: `-e screens a,b`).
 */
@RunWith(Parameterized::class)
class ScreensRefTest(private val name: String) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun names(): List<String> {
            val asked = InstrumentationRegistry.getArguments().getString("screens")
            if (!asked.isNullOrBlank()) return asked.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            val context = InstrumentationRegistry.getInstrumentation().context
            return context.assets.list("screens").orEmpty().filter { it.endsWith(".json") && it != "allowed.json" }.map { it.removeSuffix(".json") }.sorted()
        }
    }

    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    /**
     * The app's window as drawn now, where its composition is (the whole of it): a frame drawn and committed on the main
     * thread, then PixelCopy of the window. Not `captureToImage`: it reads the node's semantics on this (the test's)
     * thread, which observes snapshot reads for the window's owner while the main thread may be drawing it ("Detected
     * multithreaded access to SnapshotStateObserver", settings, 2026-10-22). Nothing of the composition is read here.
     */
    private fun windowPicture(activity: ComponentActivity): Bitmap {
        // (the test runner turns the hardware renderer's drawing off; on while pictured, as captureToImage has it)
        val drawing = HardwareRendererCompat.isDrawingEnabled()
        if (!drawing) HardwareRendererCompat.setDrawingEnabled(true)
        try { return copyWindow(activity) } finally { if (!drawing) HardwareRendererCompat.setDrawingEnabled(false) }
    }

    private fun copyWindow(activity: ComponentActivity): Bitmap {
        val window = activity.window
        val where = Rect()
        val drawn = CountDownLatch(1)
        rule.runOnUiThread {
            val view = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
            val at = IntArray(2).also { view.getLocationInWindow(it) }
            where.set(at[0], at[1], at[0] + view.width, at[1] + view.height)
            window.decorView.viewTreeObserver.registerFrameCommitCallback { drawn.countDown() }
            window.decorView.invalidate()
        }
        // (the limits only failures: a frame and a copy are each the system's own word)
        check(drawn.await(10, TimeUnit.SECONDS)) { "no frame drawn for the picture" }
        val bitmap = Bitmap.createBitmap(where.width(), where.height(), Bitmap.Config.ARGB_8888)
        val copied = CountDownLatch(1)
        var result = -1
        PixelCopy.request(window, where, bitmap, { r -> result = r; copied.countDown() }, Handler(Looper.getMainLooper()))
        check(copied.await(10, TimeUnit.SECONDS) && result == PixelCopy.SUCCESS) { "the window not copied ($result)" }
        return bitmap
    }

    /** The screen `name` (client/fixtures/screens/`name`.json) drawn and pictured. */
    private fun ref(name: String) {
        val context = InstrumentationRegistry.getInstrumentation().context
        val screen = Json.parseToJsonElement(context.assets.open("screens/$name.json").bufferedReader().readText()).jsonObject
        I18n.load(InstrumentationRegistry.getInstrumentation().targetContext)
        I18n.lang = "zh"
        val fake = FakeCore()
        // what the core says of each topic, and answers to each call (by its name and params; the first by its name)
        for (t in screen["topics"]?.jsonArray.orEmpty()) fake.set(t.jsonObject["topic"]!!.jsonObject, t.jsonObject["value"]!!)
        val calls = screen["calls"]?.jsonArray.orEmpty().map { it.jsonObject }
        fake.answer = { call, params ->
            val said = calls.firstOrNull { it["call"]?.jsonPrimitive?.content == call && it["params"] == params }
                ?: calls.firstOrNull { it["call"]?.jsonPrimitive?.content == call }
            said?.get("ok") ?: JsonNull
        }
        val dark = screen["dark"]?.jsonPrimitive?.content == "true"
        val activity = rule.activity
        val prefs = activity.getSharedPreferences("screens-ref", Context.MODE_PRIVATE)
        prefs.edit().clear().putBoolean("notifyAsked", true).putString("workspace", screen["workspace"]!!.jsonPrimitive.content)
            .putString("theme", if (dark) "dark" else "light").commit()
        rule.runOnUiThread { activity.enableEdgeToEdge() }
        // the window's insets come with its next layout: the page composed before them lays out as if there were no
        // system bars, then moves when they come. Composed once they have (a fact of the window's state).
        val barsKnown = {
            var top = 0
            rule.runOnUiThread { top = activity.window.decorView.rootWindowInsets?.getInsets(android.view.WindowInsets.Type.systemBars())?.top ?: 0 }
            top > 0
        }
        rule.waitUntil(20_000) { barsKnown() }
        fail.still.android.ui.FaceFiles.init(activity)
        val app = AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(activity, "http://127.0.0.1:9", fake.core), PrefsView())
        for (p in screen["open"]?.jsonArray.orEmpty()) app.push(page(p.jsonObject))
        // the test's clock alone from the first frame: what moves (a spinner's turn, a list's glide) is where the
        // moment has it, not where the machine's speed left it before the clock stopped
        rule.mainClock.autoAdvance = false
        val start = rule.mainClock.currentTime
        rule.setContent {
            StillFailTheme(dark, fail.still.android.ui.rememberFonts(app.kept.faces)) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) { StillFailApp(app) }
            }
        }
        // what the screen is said to show, once there (a fact of its state: what the fake core said has come in and is
        // drawn; the limit only a failure), then the moment it names after that on the test's clock, stopped: the same
        // picture whatever the machine's speed
        val shows = screen["shows"]?.jsonArray.orEmpty().map { it.jsonPrimitive.content }
        val shown = { shows.all { rule.onAllNodesWithText(it, substring = true).fetchSemanticsNodes().isNotEmpty() } }
        // a frame at a time on that clock until it shows them (what the fake core said come in, off the main thread)
        val limit = android.os.SystemClock.uptimeMillis() + 20_000
        while (!shown() && android.os.SystemClock.uptimeMillis() < limit) rule.mainClock.advanceTimeByFrame()
        rule.waitForIdle()
        val at = screen["at"]?.jsonPrimitive?.long ?: 3000L
        rule.mainClock.advanceTimeBy(maxOf(0L, start + at - rule.mainClock.currentTime))
        // the window as composed at that moment (PixelCopy of the composition just drawn: not the display's last
        // frame, which may be one behind a paused clock), the whole of it, under the system's bars too; where those
        // bars are (their icons the system's, not the app's: left out of the comparison) beside it
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "screens").apply { mkdirs() }
        val shot = windowPicture(activity)
        FileOutputStream(File(dir, "$name.png")).use { shot.compress(Bitmap.CompressFormat.PNG, 100, it) }
        var bars = intArrayOf(0, 0)
        rule.runOnUiThread {
            val insets = activity.window.decorView.rootWindowInsets.getInsets(android.view.WindowInsets.Type.systemBars())
            bars = intArrayOf(insets.top, insets.bottom)
        }
        File(dir, "$name.bars").writeText("${bars[0]} ${bars[1]}\n")
        // its lines of words, where they stand, as this picture has them (read on the main thread, as the composition
        // is: never on the test's): what the mbui app's words are held to by place, not by their pixels
        var lines = ""
        rule.runOnUiThread { lines = textLines(activity) }
        File(dir, "$name.texts.json").writeText(lines)
        // what the screen is said to show there, there (a fact of its state, not a wait for it to settle); else the
        // picture is no reference: it is kept as NAME.png beside the failure, for whoever looks
        for (words in shows) check(rule.onAllNodesWithText(words, substring = true).fetchSemanticsNodes().isNotEmpty()) { "$name: \"$words\" not shown" }
    }

    /**
     * The window's lines of words as JSON (apps/mbui/scripts/android_ref.py texts): each text's lines as laid out, its
     * words (the spaces it starts or ends in left out), the left of its first letter and the right of its last, its
     * baseline, the line's top and bottom, in the window's pixels; those its clip hides left out. On the main thread.
     */
    private fun textLines(activity: ComponentActivity): String {
        val roots = mutableListOf<ViewRootForTest>()
        fun find(v: android.view.View) {
            if (v is ViewRootForTest) roots += v
            if (v is ViewGroup) for (i in 0 until v.childCount) find(v.getChildAt(i))
        }
        find(activity.window.decorView)
        return buildJsonArray {
            fun walk(n: SemanticsNode) {
                val get = n.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action
                if (get != null) {
                    val results = mutableListOf<TextLayoutResult>()
                    get(results)
                    val at = n.positionInWindow
                    val clip = n.boundsInWindow
                    for (r in results) {
                        val text = r.layoutInput.text.text
                        for (l in 0 until r.lineCount) {
                            var a = r.getLineStart(l)
                            var b = r.getLineEnd(l, visibleEnd = true)
                            while (a < b && text[a].isWhitespace()) a++
                            while (b > a && text[b - 1].isWhitespace()) b--
                            val top = at.y + r.getLineTop(l)
                            val bottom = at.y + r.getLineBottom(l)
                            if (a >= b || bottom <= clip.top || top >= clip.bottom) continue
                            add(buildJsonObject {
                                put("t", text.substring(a, b))
                                put("x0", at.x + r.getBoundingBox(a).left)
                                put("x1", at.x + r.getBoundingBox(b - 1).right)
                                put("b", at.y + r.getLineBaseline(l))
                                put("top", top)
                                put("bot", bottom)
                            })
                        }
                    }
                }
                for (c in n.children) walk(c)
            }
            for (root in roots) walk(root.semanticsOwner.unmergedRootSemanticsNode)
        }.toString()
    }

    /**
     * A page the screen's file opens (apps/mbui src/sfapp/screen_dump_wbtest.mbt page_json, the mbui app's page as
     * this app's): `{"page": "chat" | "history" | "settings" | "me" | …, …}`.
     */
    private fun page(p: JsonObject): Screen {
        val s = { k: String -> p[k]!!.jsonPrimitive.content }
        // ("" or none: every station's)
        val opt = { k: String -> p[k]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content?.takeIf { it.isNotEmpty() } }
        return when (s("page")) {
            "chat" -> Screen.Chat(s("station"), ChatOf.Session(s("session")))
            "history" -> Screen.History(s("station"), ChatOf.Session(s("session")), s("key"))
            "new" -> Screen.NewChat
            "decisions" -> Screen.Decisions
            "settings" -> Screen.Settings
            "me" -> Screen.Me
            "appearance" -> Screen.Appearance
            "fonts" -> Screen.Fonts
            "workspace" -> Screen.Workspace
            "security" -> Screen.Security
            "vault" -> Screen.Vault
            "stations" -> Screen.Stations
            "station" -> Screen.Station(s("station"))
            "profiles" -> Screen.Profiles(opt("station"))
            "profile" -> Screen.Profile(s("station"), s("profile"))
            "pick-models" -> Screen.PickModels(s("station"), s("profile"))
            "connects" -> Screen.Connects(opt("station"))
            "connect" -> Screen.Connect(s("station"), s("connect"))
            "new-profile" -> Screen.NewProfile(s("station"))
            "new-connect" -> Screen.NewConnect(s("station"))
            "memories" -> Screen.Memories
            "memory" -> Screen.Memory(s("station"))
            "memory-doc" -> Screen.MemoryDoc(s("station"), opt("skill"), p["at"]?.jsonPrimitive?.content?.toDouble()?.toInt() ?: 0)
            "usage" -> Screen.Usage
            "archive" -> Screen.Archive
            "auto-decisions" -> Screen.AutomaticDecisions
            "bar-settings" -> Screen.BarSettings
            "kept-files" -> Screen.KeptFiles
            "changelog" -> Screen.Changelog
            "files" -> Screen.Files
            "drive" -> Screen.Drive(s("station"), opt("root"), s("path"))
            "drive-read" -> Screen.DriveRead(s("station"), s("root"), s("path"))
            else -> error("no page ${s("page")}")
        }
    }

    @Test fun screen() = ref(name)
}
