// The screens the mbui app is held to (client/fixtures/screens): each drawn by this app, the original, over the core's
// JSON the screen's file gives (the same file the mbui app draws from: apps/mbui/scripts/android-ref.sh), opened at
// the pages it names, pictured at the moment it names on the test's clock, once the words it names are on the screen.
// What comes out: <files>/screens/<name>.png, the whole screen as the system shows it (the system's bars in demo mode,
// set by the script that runs this).
package fail.still.android.motion

import android.content.Context
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.platform.app.InstrumentationRegistry
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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Rule
import org.junit.Test

class ScreensRefTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

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
        try { rule.waitUntil(20_000) { shown() } } catch (_: androidx.compose.ui.test.ComposeTimeoutException) {}
        rule.mainClock.autoAdvance = false
        rule.mainClock.advanceTimeBy(screen["at"]?.jsonPrimitive?.long ?: 3000L)
        // the window as composed at that moment (PixelCopy of the composition just drawn: not the display's last
        // frame, which may be one behind a paused clock), the whole of it, under the system's bars too; where those
        // bars are (their icons the system's, not the app's: left out of the comparison) beside it
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "screens").apply { mkdirs() }
        val shot = rule.onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(File(dir, "$name.png")).use { shot.compress(Bitmap.CompressFormat.PNG, 100, it) }
        var bars = intArrayOf(0, 0)
        rule.runOnUiThread {
            val insets = activity.window.decorView.rootWindowInsets.getInsets(android.view.WindowInsets.Type.systemBars())
            bars = intArrayOf(insets.top, insets.bottom)
        }
        File(dir, "$name.bars").writeText("${bars[0]} ${bars[1]}\n")
        // what the screen is said to show there, there (a fact of its state, not a wait for it to settle); else the
        // picture is no reference: it is kept as NAME.png beside the failure, for whoever looks
        for (words in shows) check(rule.onAllNodesWithText(words, substring = true).fetchSemanticsNodes().isNotEmpty()) { "$name: \"$words\" not shown" }
    }

    /** A page the screen's file opens: `{"page": "chat" | "history" | "settings", …}`. */
    private fun page(p: JsonObject): Screen {
        val s = { k: String -> p[k]!!.jsonPrimitive.content }
        return when (s("page")) {
            "chat" -> Screen.Chat(s("station"), ChatOf.Session(s("session")))
            "history" -> Screen.History(s("station"), ChatOf.Session(s("session")), s("key"))
            "settings" -> Screen.Settings
            else -> error("no page ${s("page")}")
        }
    }

    @Test fun chatCards() = ref("chat-cards")
    @Test fun history() = ref("history")
    @Test fun settings() = ref("settings")
}
