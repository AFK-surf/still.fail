// How smooth the pages are under the bottom bar, on the real clock (not the motion tests' stopped one): the app on the
// fake core in a plain activity, flung and dragged by injected touches, the window's frames counted by the system
// (dumpsys gfxinfo). Nothing asserted: each case logs (tag "jank") and writes motion/jank/<case>.txt, what a change to
// the bar or the frosted bars is measured by — the chats' list flung with the bar and with it away (the same list, so
// the bar's own cost), the ball dragged along the bar and up into the panel, a place's page flung.
package fail.still.android.motion

import android.content.Context
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.StillFailApp
import fail.still.android.Updates
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.I18n
import fail.still.android.data.Me
import fail.still.android.data.Overview
import fail.still.android.data.Counts
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import fail.still.android.data.WorkspaceView
import fail.still.android.ui.LocalUi
import fail.still.android.ui.StillFailTheme
import org.junit.Test
import java.io.File

class JankTest {
    private val inst = InstrumentationRegistry.getInstrumentation()
    private val pkg = inst.targetContext.packageName

    private fun item(i: Int) = ChatItem(
        id = "c$i", session = "ember:c-$i", thread = 100L + i, title = listOf("修一下登录", "整理发布流程", "看看 CI 为什么慢", "首页改版")[i % 4] + " $i",
        agents = emptyList(), unread = i % 5 == 0, mine = true, lastActiveAt = Fixtures.NOW - i * 60_000L, station = Fixtures.STATION, stationName = "studio",
    )

    private fun chats(n: Int) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "studio", "studio", "online")), loading = false,
        days = (0 until n / 10).map { d -> ChatDay(d.toLong(), (Fixtures.NOW - d * 86_400_000L).toDouble(), "${d + 1} 天前", (d * 10 until d * 10 + 10).map(::item)) },
    )

    private val station = Fixtures.station.copy(
        overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
            drive = DriveRoots((0 until 40).map { DriveRoot("/Users/alice/f$it", "文件夹 $it", "ok") }),
        ),
    )

    private lateinit var app: AppState
    private lateinit var scenario: ActivityScenario<ComponentActivity>
    private var width = 0
    private var height = 0
    private var navBottom = 0
    private var density = 1f

    private fun launch(stack: List<Screen>) {
        I18n.load(inst.targetContext)
        I18n.lang = "zh"
        val fake = FakeCore()
        fake.put(Topics.accounts, listOf(Fixtures.account))
        fake.put(Topics.workspaces, Fixtures.workspaces)
        fake.put(Topics.stations(Fixtures.WS), listOf(station))
        fake.put(Topics.chats(Fixtures.WS, false), chats(80))
        fake.put(Topics.chats(Fixtures.WS, true), chats(80))
        fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats(0))
        fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "owner"))
        scenario = ActivityScenario.launch(ComponentActivity::class.java)
        scenario.onActivity { a ->
            a.enableEdgeToEdge()
            val prefs = a.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
            prefs.edit().clear().putBoolean("notifyAsked", true).putString("workspace", Fixtures.WS).putString("theme", "light").commit()
            app = AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(a, "http://127.0.0.1:9", fake.core))
            stack.forEach { if (it != Screen.Home) app.push(it) }
            a.setContent { StillFailTheme(false) { CompositionLocalProvider(LocalApp provides app, LocalUi provides app) { StillFailApp(app) } } }
        }
        Thread.sleep(2500)
        scenario.onActivity { a ->
            val v = a.window.decorView
            width = v.width; height = v.height
            density = a.resources.displayMetrics.density
            navBottom = v.rootWindowInsets?.getInsets(android.view.WindowInsets.Type.navigationBars())?.bottom ?: 0
        }
    }

    private fun shell(cmd: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(inst.uiAutomation.executeShellCommand(cmd)).bufferedReader().readText()

    /** What the system counted of the window's frames since `reset`: its summary, up to the histogram. */
    private fun measure(name: String, act: () -> Unit) {
        Thread.sleep(500)
        shell("dumpsys gfxinfo $pkg reset")
        act()
        Thread.sleep(300)
        val out = shell("dumpsys gfxinfo $pkg")
        val summary = out.lines().dropWhile { !it.startsWith("Total frames rendered") }.takeWhile { !it.startsWith("HISTOGRAM") }.filter { it.isNotBlank() }
        val text = summary.joinToString("\n")
        Log.i("jank", "== $name\n$text")
        File(inst.targetContext.getExternalFilesDir(null), "motion/jank").apply { mkdirs() }.resolve("$name.txt").writeText(text + "\n")
        scenario.close()
    }

    private fun swipe(x: Int, y1: Int, y2: Int, ms: Int) { shell("input swipe $x $y1 $x $y2 $ms"); Thread.sleep(900) }

    /** Flings the page up and down `times` times, in its middle (clear of the bar). */
    private fun fling(times: Int) {
        val x = width / 2
        repeat(times) {
            swipe(x, (height * 0.65f).toInt(), (height * 0.25f).toInt(), 120)
            swipe(x, (height * 0.3f).toInt(), (height * 0.7f).toInt(), 120)
        }
    }

    /** A slow drag of the list (a finger on it, not a fling), down and back. */
    private fun drag(times: Int) {
        val x = width / 2
        repeat(times) {
            swipe(x, (height * 0.65f).toInt(), (height * 0.3f).toInt(), 900)
            swipe(x, (height * 0.3f).toInt(), (height * 0.65f).toInt(), 900)
        }
    }

    /** One finger on the bar: `path` its points (px), a move every 8 ms; let go at the last. */
    private fun touch(path: List<Pair<Float, Float>>) {
        val down = SystemClock.uptimeMillis()
        fun send(action: Int, x: Float, y: Float, t: Long) {
            val e = MotionEvent.obtain(down, t, action, x, y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
            inst.uiAutomation.injectInputEvent(e, true)
            e.recycle()
        }
        send(MotionEvent.ACTION_DOWN, path[0].first, path[0].second, down)
        var t = down
        for ((x, y) in path.drop(1)) {
            t += 8
            val wait = t - SystemClock.uptimeMillis()
            if (wait > 0) Thread.sleep(wait)
            send(MotionEvent.ACTION_MOVE, x, y, SystemClock.uptimeMillis())
        }
        val (x, y) = path.last()
        send(MotionEvent.ACTION_UP, x, y, SystemClock.uptimeMillis())
        Thread.sleep(1200)
    }

    private val barY get() = height - navBottom - (22 + 28) * density
    private val barLeft get() = 22 * density + 30 * density
    private val barRight get() = width - 22 * density - 30 * density

    /** From the first place to the last and back, three times, ending where it began (nothing chosen). */
    private fun alongBar(): List<Pair<Float, Float>> {
        val steps = 120
        val one = (0..steps).map { barLeft + (barRight - barLeft) * it / steps to barY }
        return (one + one.reversed()).let { it + it + it }
    }

    /** Up into the panel of the other bars, across it and back down to where it began. */
    private fun intoPanel(): List<Pair<Float, Float>> {
        val up = (0..60).map { barLeft to barY - 90 * density * it / 60 }
        val across = (0..120).map { barLeft + (barRight - barLeft) * it / 120 to barY - 90 * density }
        return up + across + across.reversed() + up.reversed()
    }

    @Test fun homeFlingWithBar() { launch(listOf(Screen.Home)); measure("home-fling-bar") { fling(4) } }
    @Test fun homeFlingBarAway() { launch(listOf(Screen.Home)); scenario.onActivity { app.barAway = true }; measure("home-fling-away") { fling(4) } }
    @Test fun homeDragWithBar() { launch(listOf(Screen.Home)); measure("home-drag-bar") { drag(2) } }
    @Test fun homeDragBarAway() { launch(listOf(Screen.Home)); scenario.onActivity { app.barAway = true }; measure("home-drag-away") { drag(2) } }
    @Test fun ballAlongBar() { launch(listOf(Screen.Home)); measure("ball-along") { touch(alongBar()) } }
    @Test fun ballIntoPanel() { launch(listOf(Screen.Home)); measure("ball-panel") { touch(intoPanel()) } }
    @Test fun filesFlingWithBar() {
        launch(listOf(Screen.Home))
        scenario.onActivity { app.place(Screen.Files) }
        Thread.sleep(1500)
        measure("files-fling-bar") { fling(4) }
    }
    @Test fun filesFlingPushed() { launch(listOf(Screen.Home, Screen.Files)); measure("files-fling-pushed") { fling(4) } }
}
