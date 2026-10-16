// The bottom bar (ui/Bar.kt, Places.kt) on the fake core: on Home in light and dark (the ball 6 past the bar on every
// side at rest; the notch empty, the page's own paper showing there; no shadow above the bar), a place tapped (the page
// switched in place, the ball over it), the panel of the other bars snapping open and closed under a finger by how high
// it is (leaning toward it; let go, as the finger left it; a finger on it as it goes has it from there, a tap changes
// nothing), one stroke from the bar into a place of another bar (that bar and that place at once; the frame it is chosen
// drawn as the frame before; it lands whole, the bar left never drawn over it, the ball and the notch never jumping, a
// finger on it as it lands changing nothing), the settings
// page's cards (a place taken out, one added, a bar made and deleted, a place moved), and the notch's action: 令 on the
// chats' pages, a "+" on a page that adds (Station, for a manager), none on 用量 (the notch closed), the notch staying
// open between two pages that have one, the icon in it swapping. Pictures: settled.png under motion/bar-*.
package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.filter
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.TouchInjectionScope
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.click
import fail.still.android.Screen
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.Counts
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.Me
import fail.still.android.data.Overview
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import fail.still.android.data.WorkspaceView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs
import kotlin.math.max

class BarTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun item(i: Int) = ChatItem(
        id = "c$i", session = "ember:c-$i", thread = 100L + i, title = listOf("修一下登录", "整理发布流程", "看看 CI 为什么慢")[i % 3], agents = emptyList(), unread = false, mine = true,
        lastActiveAt = Fixtures.NOW - i * 60_000L, station = Fixtures.STATION, stationName = "studio",
    )

    private fun chats(n: Int) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "studio", "studio", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", (0 until n).map(::item))),
    )

    private val station = Fixtures.station.copy(
        overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
            drive = DriveRoots(listOf(DriveRoot("/Users/alice/书", "书", "ok"), DriveRoot("/Volumes/media/影视", "影视", "ok"))),
        ),
    )

    private fun launch(stack: List<Screen> = listOf(Screen.Home), dark: Boolean = false): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.chats(Fixtures.WS, false), chats(3))
        h.fake.put(Topics.chats(Fixtures.WS, true), chats(3))
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats(0))
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "owner"))
        h.launch(stack, dark)
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station)) }
        h.settle()
        return h
    }

    private val d get() = rule.density.density
    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
    private fun shot(h: Harness, name: String) = h.record(name).also { it.frames(1); it.end() }

    /** The ball at rest over a place: 6 past the glass at its top and foot, and at the bar's end it is at (`end`: -1 first, 1 last). */
    private fun ballAtRest(end: Int) {
        val g = bounds("bar-glass")
        val b = bounds("bar-ball")
        val six = 6 * d
        val tol = 1.5f
        assertTrue("ball's top ${b.top} vs glass ${g.top}", abs((g.top - b.top) - six) <= tol)
        assertTrue("ball's foot ${b.bottom} vs glass ${g.bottom}", abs((b.bottom - g.bottom) - six) <= tol)
        assertTrue("ball is round: ${b.width} × ${b.height}", abs(b.width - b.height) <= tol && abs(b.width - 68 * d) <= tol)
        if (end < 0) assertTrue("ball's left ${b.left} vs glass ${g.left}", abs((g.left - b.left) - six) <= tol)
        if (end > 0) assertTrue("ball's right ${b.right} vs glass ${g.right}", abs((b.right - g.right) - six) <= tol)
    }

    private fun pixel(bmp: Bitmap, x: Float, y: Float) = bmp.getPixel(x.toInt(), y.toInt())
    private fun near(a: Int, b: Int, by: Int) = abs(android.graphics.Color.red(a) - android.graphics.Color.red(b)) <= by &&
        abs(android.graphics.Color.green(a) - android.graphics.Color.green(b)) <= by && abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(b)) <= by
    private fun hex(c: Int) = "#%06X".format(c and 0xFFFFFF)

    /** The notch shows the page's paper (nothing frosted, no shadow), as does what is just above the bar; the glass does not. */
    private fun notchEmpty(paper: Int, dark: Boolean = false) {
        val g = bounds("bar-glass")
        val bmp = rule.onRoot().captureToImage().asAndroidBitmap()
        val cx = g.center.x
        // In the gap round 令 (between its 28 and the notch's 34, about 令's middle 4 above the bar's top), 20 below the top.
        val gap = pixel(bmp, cx + 19.6f * d, g.top + 20 * d)
        val above = pixel(bmp, cx + 60 * d, g.top - 3 * d)
        val glass = pixel(bmp, cx + 40 * d, g.top + 50 * d)
        // Past the bar's rounded left end, in the row of its top (and clear of the ball): no line drawn there. (In the dark,
        // where a lit line shows most and the shadow least.)
        if (dark) {
            val corner = pixel(bmp, g.left + 3 * d, g.top + 0.5f)
            assertTrue("past the bar's rounded end ${hex(corner)} is the paper ${hex(paper)}", near(corner, paper, 8))
        }
        assertTrue("the notch's gap ${hex(gap)} is the paper ${hex(paper)}", near(gap, paper, 4))
        assertTrue("above the bar ${hex(above)} is the paper ${hex(paper)}", near(above, paper, 4))
        assertTrue("the glass ${hex(glass)} is not the paper ${hex(paper)}", !near(glass, paper, 3))
    }

    @Test fun homeLight() {
        val h = launch()
        shot(h, "bar-home-light")
        ballAtRest(-1)
        notchEmpty(0xFFF5F3EF.toInt())
        rule.onNodeWithContentDescription("新建对话").assertExists()
    }

    @Test fun homeDark() {
        val h = launch(dark = true)
        shot(h, "bar-home-dark")
        ballAtRest(-1)
        notchEmpty(0xFF1B1C1F.toInt(), dark = true)
    }

    /** A place tapped: its page in place of the one shown (nothing to go back to), the ball over it, 令 gone. */
    @Test fun tapSwitch() {
        val h = launch()
        val r = h.record("bar-tap-files")
        rule.onNodeWithTag("bar-place-files").performClick()
        r.frames(30)
        r.end()
        assertEquals(listOf<Screen>(Screen.Files), h.app.stack)
        ballAtRest(0)
        rule.onNodeWithText("书").assertExists()
        rule.onNodeWithContentDescription("新建对话").assertDoesNotExist()
        rule.onNodeWithTag("bar-place-stations").performClick()
        h.settle()
        assertEquals(listOf<Screen>(Screen.Stations), h.app.stack)
        ballAtRest(1)
        shot(h, "bar-stations-light")
        // Switched away from a page that has a back when pushed (the stations' 设置): it goes as it was, never shown
        // with that back (or without its foot's room) while the place coming in gets what it shows.
        val away = h.record("bar-tap-away")
        rule.onNodeWithTag("bar-place-files").performClick()
        repeat(12) { away.frame(); rule.onNodeWithText("设置").assertDoesNotExist() }
        away.end()
        assertEquals(listOf<Screen>(Screen.Files), h.app.stack)
        // Quick taps one after another, as the ball still moves: it ends where the last one sent it.
        rule.onNodeWithTag("bar-place-profiles").performClick()
        rule.onNodeWithTag("bar-place-chats").performClick()
        h.settle()
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        ballAtRest(-1)
    }

    /**
     * A finger moving along the bar every frame, as a real one does: the ball goes along with it. (Its spring was started
     * over at each move and never got past its first frame: it stayed where it was until the finger stopped.)
     */
    @Test fun slideFollows() {
        val h = launch()
        val g = bounds("bar-glass")
        val y = g.top + 28 * d
        val x0 = g.left + 28 * d
        val x1 = g.right - 28 * d
        val r = h.record("bar-slide")
        rule.onRoot().performTouchInput { down(Offset(x0, y)) }
        r.frame()
        val start = bounds("bar-ball").center.x
        for (i in 1..30) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x0 + (x1 - x0) * i / 30f, y)) } }
        val moved = bounds("bar-ball").center.x - start
        rule.onRoot().performTouchInput { up() }
        r.frames(30)
        r.end()
        assertTrue("the ball went along with the finger (${moved / d} dp of ${(x1 - x0) / d})", moved > (x1 - x0) * 0.6f)
    }

    /**
     * The same up into the panel of the other bars and across its row, the finger moving every frame: the panel open,
     * the ball goes up into the row and along it with the finger; brought back down and let go where it began, nothing
     * is chosen.
     */
    @Test fun panelSlideFollows() {
        val h = launch()
        val g = bounds("bar-glass")
        val y0 = g.top + 28 * d
        val x0 = g.left + 28 * d
        val x1 = g.right - 28 * d
        val row = y0 - 56 * d
        val r = h.record("bar-panel-slide")
        rule.onRoot().performTouchInput { down(Offset(x0, y0)) }
        r.frame()
        val start = bounds("bar-ball").center
        for (i in 1..15) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x0, y0 + (row - y0) * i / 15f)) } }
        // The panel open once the finger is 24 over the bar (the last frames): the ball goes up with it from then.
        for (i in 1..12) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x0, row)) } }
        val up = start.y - bounds("bar-ball").center.y
        val from = bounds("bar-ball").center.x
        for (i in 1..30) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x0 + (x1 - x0) * i / 30f, row)) } }
        val across = bounds("bar-ball").center.x - from
        for (i in 1..20) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x1 + (x0 - x1) * i / 20f, row + (y0 - row) * i / 20f)) } }
        rule.onRoot().performTouchInput { up() }
        r.frames(40)
        r.end()
        assertTrue("the ball went up into the row with the finger (${up / d} dp)", up > 35 * d)
        assertTrue("the ball went along the row with the finger (${across / d} dp of ${(x1 - x0) / d})", across > (x1 - x0) * 0.6f)
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        assertEquals(0L, h.app.bars.current)
    }

    /**
     * A page pushed over a place's top hides the bar (and its back is there again, to the page under it, with its "+");
     * back, the bar is back. Back on a place's top other than the chats goes to the chats, in place.
     */
    @Test fun pushedAndBack() {
        val h = launch()
        rule.runOnUiThread { h.app.push(Screen.Stations) }
        h.settle()
        rule.onNodeWithTag("bar-glass").assertDoesNotExist()
        rule.onNodeWithText("对话").assertExists()
        rule.onNodeWithContentDescription("添加 station").assertExists()
        rule.runOnUiThread { h.app.pop() }
        h.settle()
        rule.onNodeWithTag("bar-glass").assertExists()
        ballAtRest(-1)
        rule.onNodeWithTag("bar-place-stations").performClick()
        h.settle()
        // A place's top: no back to anywhere; its "+" in the notch, not in its top bar too.
        rule.onNodeWithText("对话").assertDoesNotExist()
        rule.onAllNodesWithContentDescription("添加 station").assertCountEquals(1)
        rule.onNode(hasTestTag("bar-action") and hasContentDescription("添加 station")).assertExists()
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        h.settle()
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        assertEquals(false, rule.activity.isFinishing)
    }

    /** A swipe up on the bar past 24 over it, let go above the rows: the panel opens and stays open; a press beside it closes it. */
    @Test fun panelOpen() = panel(false)
    @Test fun panelOpenDark() = panel(true)

    private fun panel(dark: Boolean) {
        val h = launch(dark = dark)
        val g = bounds("bar-glass")
        rule.onRoot().performTouchInput {
            down(Offset(g.left + 28 * d, g.top + 28 * d))
            moveTo(Offset(g.left + 30 * d, g.top + 10 * d))
            moveTo(Offset(g.left + 32 * d, g.top - 60 * d))
            up()
        }
        h.settle()
        shot(h, if (dark) "bar-panel-dark" else "bar-panel-light")
        // The other bar's places are there, over the bar.
        val connects = bounds("bar-place-connects")
        assertTrue("the panel's row is above the bar", connects.bottom <= g.top)
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        rule.onRoot().performTouchInput { click(Offset(g.center.x, g.top - 300 * d)) }
        h.settle()
        rule.onNodeWithTag("bar-place-connects").assertDoesNotExist()
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
    }

    /** One stroke from the bar's first place up into the other bar's row and across to 连接: that bar and that place. */
    @Test fun strokeToAnotherBar() {
        val h = launch()
        val g = bounds("bar-glass")
        val w = g.width / d
        // The other bar's places sit where a bar of four's do with the notch closed.
        val connectsX = g.left + (w - 28 - (w - 56) / 3) * d
        val r = h.record("bar-stroke")
        rule.onRoot().performTouchInput { down(Offset(g.left + 28 * d, g.top + 28 * d)) }
        r.frames(2)
        rule.onRoot().performTouchInput { moveTo(Offset(g.left + 40 * d, g.top - 12 * d)) }
        r.frames(4)
        rule.onRoot().performTouchInput { moveTo(Offset((g.left + 40 * d + connectsX) / 2, g.top - 24 * d)) }
        r.frames(4)
        rule.onRoot().performTouchInput { moveTo(Offset(connectsX, g.top - 28 * d)) }
        r.frames(30)
        rule.onRoot().performTouchInput { up() }
        // The place and the bar at once, the glass still closing over them.
        r.frames(2)
        assertEquals(listOf<Screen>(Screen.Connects()), h.app.stack)
        assertEquals(1L, h.app.bars.current)
        r.frames(38)
        r.end()
        assertEquals(1L, h.app.bars.current)
        assertEquals(listOf<Screen>(Screen.Connects()), h.app.stack)
        ballAtRest(0)
        // The bar is the other one now: its places, not the first one's.
        rule.onNodeWithTag("bar-place-usage").assertExists()
        rule.onNodeWithTag("bar-place-chats").assertDoesNotExist()
        shot(h, "bar-connects-light")
    }

    /**
     * Gone up too far: past the panel's top, over 连接's column, and let go there: the bar the ball kept to (the top row's
     * place) is chosen, as on the web. (It was let go open with nothing chosen: the bar could not be switched.)
     */
    @Test fun strokePastTheRows() {
        val h = launch()
        val g = bounds("bar-glass")
        val w = g.width / d
        val connectsX = g.left + (w - 28 - (w - 56) / 3) * d
        val r = h.record("bar-stroke-past")
        val x0 = g.left + 28 * d
        val y0 = g.top + 28 * d
        r.touch { down(Offset(x0, y0)) }
        // Up and across a frame at a time, to 160 over the bar's top: well past the panel's.
        for (i in 1..30) r.touch { moveTo(Offset(x0 + (connectsX - x0) * i / 30f, y0 - (188 * d) * i / 30f)) }
        r.frames(20)
        r.touch { up() }
        r.frames(40)
        r.end()
        assertEquals(1L, h.app.bars.current)
        assertEquals(listOf<Screen>(Screen.Connects()), h.app.stack)
    }

    /** One frame, the finger doing `block` at its start. */
    private fun Recording.touch(block: TouchInjectionScope.() -> Unit) = frame { rule.onRoot().performTouchInput(block) }

    /** The glass's top (px): the bar's when the panel is closed, a row (56) higher open. */
    private fun glassTop() = bounds("bar-glass").top

    /** How open the panel is, by the glass's top (`closed`: its top with the panel closed). */
    private fun openness(closed: Float) = (closed - glassTop()) / (56 * d)

    /**
     * A finger on a recording: moved every frame, from where it last was, each move in its frame (no time of its own
     * besides: a frame a move, as a finger's).
     */
    private inner class Finger(val r: Recording, var at: Offset) {
        fun down() = r.touch { down(at) }
        fun to(p: Offset, frames: Int) {
            val from = at
            for (i in 1..frames) r.touch { moveTo(from + (p - from) * (i / frames.toFloat()), delayMillis = 0) }
            at = p
        }
        /** Still `frames` frames (moving to where it is, as a finger on glass does): how open the panel is each frame. */
        fun hold(frames: Int, closed: Float) = (1..frames).map { r.touch { moveTo(at, delayMillis = 0) }; openness(closed) }
        fun up() = r.touch { up() }
    }

    /** Where the panel leans to, drawn by a finger from the bar's middle to `over` dp above its top, open or closed. */
    private fun lean(open: Boolean, over: Float): Float {
        val raw = (28 + over - 8) / 56
        val snap = if (open) 1f else 0f
        return (snap + 0.25f * (raw - snap)).coerceIn(0f, 1.1f)
    }

    /** Held still, once settled (its last 30 frames): where it rests, and that it rests there. */
    private fun settled(name: String, path: List<Float>, expect: Float) {
        val rest = path.takeLast(30)
        assertTrue("$name: settled at $expect (${rest.min()}..${rest.max()})", rest.all { abs(it - expect) < 0.012f })
    }

    /**
     * The panel snaps as the ball does: a finger drawn up from the bar and held, the panel is closed (leaning a quarter of
     * the way toward the finger) under 24 above the bar, open (leaning) once over it, and stays open back down to 16, closed
     * under it; held still, it rests there. Let go above the panel: open, the lean gone. Frames: motion/bar-panel-snap.
     */
    @Test fun panelSnapsWhileHeld() {
        val h = launch()
        val g = bounds("bar-glass")
        val closed = g.top
        fun over(dp: Float) = Offset(g.left + 28 * d, closed - dp * d)
        val f = Finger(h.record("bar-panel-snap"), Offset(g.left + 28 * d, closed + 28 * d))
        f.down()
        f.to(over(10f), 8)
        settled("10 over the bar", f.hold(60, closed), lean(false, 10f))
        f.to(over(40f), 8)
        val opening = f.hold(60, closed)
        assertTrue("open while held: ${opening.max()}", opening.max() > 0.98f)
        settled("40 over", opening, lean(true, 40f))
        f.to(over(20f), 6)
        settled("back to 20 over: still open", f.hold(60, closed), lean(true, 20f))
        f.to(over(10f), 6)
        val closing = f.hold(60, closed)
        assertTrue("closed while held: ${closing.min()}", closing.min() < 0.15f)
        settled("back to 10 over: closed", closing, lean(false, 10f))
        f.to(over(60f), 10)
        settled("60 over", f.hold(60, closed), lean(true, 60f))
        f.up()
        f.r.frames(40)
        f.r.end()
        // Let go above the panel's row, open: the place the ball kept to there, the top row's (奏, under the finger).
        assertEquals(1L, h.app.bars.current)
        assertEquals(listOf<Screen>(Screen.Decisions), h.app.stack)
    }

    /** Opened, drawn back under 16 and let go there: closed, nothing chosen. */
    @Test fun panelLetGoBelow() {
        val h = launch()
        val g = bounds("bar-glass")
        val closed = g.top
        val f = Finger(h.record("bar-panel-below"), Offset(g.left + 28 * d, closed + 28 * d))
        f.down()
        f.to(Offset(f.at.x, closed - 40 * d), 8)
        f.hold(30, closed)
        f.to(Offset(f.at.x, closed - 10 * d), 6)
        f.hold(10, closed)
        f.up()
        val after = (1..40).map { f.r.frame(); openness(closed) }
        f.r.end()
        assertEquals("closed", 0f, after.last(), 0.01f)
        rule.onNodeWithTag("bar-place-connects").assertDoesNotExist()
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        assertEquals(0L, h.app.bars.current)
    }

    /**
     * A finger put on the panel as it goes: a tap changes nothing (frame for frame as if none); one that moves has it by
     * where it is, from there, not stopping it (closing, drawn up past 24 over the bar: it opens again, held).
     */
    @Test fun panelTouchedAsItGoes() {
        val h = launch()
        val g = bounds("bar-glass")
        val closed = g.top
        fun open(name: String, tap: Boolean): List<Float> {
            val f = Finger(h.record(name), Offset(g.left + 28 * d, closed + 28 * d))
            f.down()
            // Over the line and let go half open (not yet 85%, so nothing chosen): it opens on.
            f.to(Offset(f.at.x, closed - 40 * d), 2)
            var n = 0
            while (openness(closed) < 0.5f && n++ < 30) f.r.frame()
            assertTrue("let go before 85%: ${openness(closed)}", openness(closed) < 0.85f)
            f.up()
            val path = ArrayList<Float>()
            for (i in 1..30) {
                when {
                    tap && i == 1 -> f.r.touch { down(Offset(g.left + 60 * d, glassTop() + 10 * d)) }
                    tap && i == 2 -> f.r.touch { up() }
                    else -> f.r.frame()
                }
                path += glassTop()
            }
            f.r.end()
            assertEquals("$name: open", 1f, openness(closed), 0.01f)
            rule.onRoot().performTouchInput { click(Offset(g.center.x, closed - 300 * d)) }
            h.settle()
            return path
        }
        val alone = open("bar-panel-opening", false)
        val tapped = open("bar-panel-opening-tapped", true)
        alone.zip(tapped).forEachIndexed { i, (a, b) -> assertEquals("frame $i: tapped as it opened, as if not", a, b, 0.5f) }
        // Open; drawn down under 16 and let go: closing; two frames on, a finger on it drawn up past 24: open again.
        val r = h.record("bar-panel-closing-taken")
        val f = Finger(r, Offset(g.left + 28 * d, closed + 28 * d))
        f.down()
        f.to(Offset(f.at.x, closed - 40 * d), 8)
        f.hold(40, closed)
        f.to(Offset(f.at.x, closed - 5 * d), 8)
        f.up()
        r.frames(2)
        val o0 = openness(closed)
        val g2 = Finger(r, Offset(g.left + 60 * d, glassTop() + 10 * d))
        g2.down()
        val goes = openness(closed)
        assertTrue("not stopped by the finger: $o0 then $goes", goes < o0 - 0.01f)
        val y0 = g2.at.y
        g2.to(Offset(g2.at.x, g2.at.y - 30 * d), 10)
        val held = g2.hold(60, closed)
        val raw = o0 + (y0 - g2.at.y) / (56 * d)
        settled("drawn up past 24 as it closed: open, leaning", held, 1f + 0.25f * (raw - 1f))
        g2.to(Offset(g2.at.x, closed - 60 * d), 6)
        g2.up()
        r.frames(40)
        r.end()
        assertEquals(1f, openness(closed), 0.01f)
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        assertEquals(0L, h.app.bars.current)
    }

    /** From the bar's first place up into the other bar's row to 连接, held there `still` frames (the finger moving every frame). */
    private fun strokeToConnects(f: Finger, still: Int) {
        val g = bounds("bar-glass")
        val w = g.width / d
        val connectsX = g.left + (w - 28 - (w - 56) / 3) * d
        f.down()
        f.to(Offset(connectsX, g.top - 34 * d), 20)
        f.hold(still, g.top)
    }

    /**
     * A finger put on the bar as a bar chosen lands, moved and lifted: the landing goes on untouched, frame for frame as
     * one nobody touched; the bar and the place stay chosen.
     */
    @Test fun touchDuringLanding() {
        val h = launch()
        val g = bounds("bar-glass")
        fun land(name: String, touch: Boolean): List<Float> {
            val r = h.record(name)
            val f = Finger(r, Offset(g.left + 28 * d, g.top + 28 * d))
            strokeToConnects(f, 40)
            f.up()
            assertEquals(1L, h.app.bars.current)
            val path = ArrayList<Float>()
            var t: Finger? = null
            for (i in 1..50) {
                when {
                    touch && i == 3 -> t = Finger(r, Offset(g.left + 60 * d, glassTop() + 20 * d)).also { it.down() }
                    touch && i in 4..18 -> t!!.to(Offset(t.at.x, t.at.y + 2 * d), 1)
                    touch && i == 19 -> t!!.up()
                    else -> r.frame()
                }
                path += glassTop()
            }
            r.end()
            assertEquals(1L, h.app.bars.current)
            assertEquals(listOf<Screen>(Screen.Connects()), h.app.stack)
            return path
        }
        val alone = land("bar-landing", false)
        rule.runOnUiThread { h.app.setBars(h.app.bars.sets, 0); h.app.place(Screen.Home) }
        h.settle()
        val touched = land("bar-landing-touched", true)
        android.util.Log.i("bartest", "landing, glass top a frame: ${alone.joinToString(" ")} / touched ${touched.joinToString(" ")}")
        alone.zip(touched).forEachIndexed { i, (a, b) -> assertEquals("frame $i of the landing, touched as not", a, b, 0.5f) }
        rule.onNodeWithTag("bar-place-usage").assertExists()
    }

    /**
     * The frame a bar is chosen (the panel at rest, the finger held still on 连接 and let go): the stack is drawn as the
     * rows and the bar were the frame before, every place where it was (to a pixel), as faded and as lit; the ball goes
     * on from where it was. Frames: motion/bar-pick.
     */
    @Test fun pickSeamless() {
        val h = launch()
        val g = bounds("bar-glass")
        val chosen = listOf("decisions", "usage", "connects", "archive")
        val left = listOf("chats", "files", "profiles", "stations")
        val r = h.record("bar-pick")
        val f = Finger(r, Offset(g.left + 28 * d, g.top + 28 * d))
        strokeToConnects(f, 90)
        fun centre(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().let { it.positionInRoot + Offset(it.size.width / 2f, it.size.height / 2f) }
        val before = (chosen + left).associateWith { centre("bar-place-$it") }
        val ball0 = bounds("bar-ball").center
        val bmp0 = rule.onRoot().captureToImage().asAndroidBitmap()
        f.up()
        assertEquals(1L, h.app.bars.current)
        val after = (chosen + left).associateWith { centre("bar-flying-$it") }
        val ball1 = bounds("bar-ball").center
        val bmp1 = rule.onRoot().captureToImage().asAndroidBitmap()
        r.frames(40)
        r.end()
        /** An icon's ink: the mean of the darkest sixth of its box (28 dp about its middle). */
        fun ink(b: Bitmap, c: Offset): Float {
            val half = (14 * d).toInt()
            val l = ArrayList<Int>()
            for (y in c.y.toInt() - half until c.y.toInt() + half) for (x in c.x.toInt() - half until c.x.toInt() + half) {
                val p = b.getPixel(x, y)
                l += (android.graphics.Color.red(p) * 299 + android.graphics.Color.green(p) * 587 + android.graphics.Color.blue(p) * 114) / 1000
            }
            l.sort()
            return l.take(l.size / 6).average().toFloat()
        }
        val moved = (chosen + left).associateWith { (after[it]!! - before[it]!!).getDistance() }
        // Under 连接 the ball (it moves on its spring): its icon's ink is not compared.
        val inks = (chosen + left).filter { it != "connects" }.associateWith { abs(ink(bmp1, after[it]!!) - ink(bmp0, before[it]!!)) }
        android.util.Log.i("bartest", "pick: moved (px) $moved; ink change $inks; ball ${(ball1 - ball0).getDistance() / d} dp")
        moved.forEach { (k, v) -> assertTrue("$k moved $v px at the pick", v <= 1f) }
        // 0.02 of the icons' alpha is about 3 of the ink's levels.
        inks.forEach { (k, v) -> assertTrue("$k changed by $v levels at the pick", v <= 3f) }
        assertTrue("the ball moved ${(ball1 - ball0).getDistance() / d} dp at the pick", (ball1 - ball0).getDistance() <= 3 * d)
    }

    /**
     * The stroke into another bar, the finger moving every frame, then every frame stepped until well after the chosen
     * bar has landed: no frame has places of two bars at the bar's middle (the bar left drawn over the chosen one's places
     * was a flash); the ball and the notch never jump between two frames; the frame the stack goes (the panel closed)
     * changes the bar no more than the frames round it. Frames: motion/bar-stroke-lands.
     */
    @Test fun strokeLandsWhole() {
        val h = launch()
        val g = bounds("bar-glass")
        val w = g.width / d
        val connectsX = g.left + (w - 28 - (w - 56) / 3) * d
        val left = listOf("chats", "files", "profiles", "stations")
        val chosen = listOf("decisions", "usage", "connects", "archive")
        val from = Offset(g.left + 28 * d, g.top + 28 * d)
        val to = Offset(connectsX, g.top - 34 * d)
        val r = h.record("bar-stroke-lands")
        r.touch { down(from) }
        for (i in 1..20) r.touch { moveTo(from + (to - from) * (i / 20f)) }
        for (i in 1..30) r.touch { moveTo(to) }
        r.touch { up() }
        assertEquals(1L, h.app.bars.current)
        assertEquals(listOf<Screen>(Screen.Connects()), h.app.stack)
        val box = android.graphics.Rect(g.left.toInt(), (g.top - 80 * d).toInt(), g.right.toInt(), g.bottom.toInt())
        fun crop() = rule.onRoot().captureToImage().asAndroidBitmap().let { Bitmap.createBitmap(it, box.left, box.top, box.width(), box.height()) }
        fun changed(a: Bitmap, b: Bitmap): Float {
            val pa = IntArray(a.width * a.height); val pb = IntArray(pa.size)
            a.getPixels(pa, 0, a.width, 0, 0, a.width, a.height); b.getPixels(pb, 0, b.width, 0, 0, b.width, b.height)
            var n = 0
            for (i in pa.indices) if (!near(pa[i], pb[i], 24)) n++
            return n.toFloat() / pa.size
        }
        fun middle(keys: List<String>) = keys.filter { key ->
            (rule.onAllNodesWithTag("bar-place-$key").fetchSemanticsNodes() + rule.onAllNodesWithTag("bar-flying-$key").fetchSemanticsNodes()).any { node ->
                // Where it is drawn, not clipped to the bar (bounds clipped to nothing would sit on the bar's foot).
                abs(node.positionInRoot.y + node.size.height / 2f - g.center.y) < 14 * d
            }
        }
        fun notchW() = rule.onAllNodesWithTag("bar-action").fetchSemanticsNodes().firstOrNull()?.boundsInRoot?.width ?: 0f
        var cleared = -1
        var n = 0
        var ball = bounds("bar-ball").center
        var notch = notchW()
        var shot = crop()
        val diffs = ArrayList<Float>()
        var maxBall = 0f
        var maxNotch = 0f
        while (n < 120 && (cleared < 0 || n < cleared + 30)) {
            r.frame()
            val both = middle(left) to middle(chosen)
            assertTrue("frame $n after the let-go: places of both bars at the bar's middle: $both", both.first.isEmpty() || both.second.isEmpty())
            val b = bounds("bar-ball").center
            val k = notchW()
            // The glass as wide as it was, all the way down (it narrowed with the panel's speed, going off to the side).
            val gw = bounds("bar-glass").width
            assertTrue("frame $n: the glass ${gw / d} dp wide, not ${g.width / d}", abs(gw - g.width) < 1f)
            maxBall = max(maxBall, (b - ball).getDistance() / d)
            maxNotch = max(maxNotch, abs(k - notch) / d)
            assertTrue("frame $n: the ball jumped ${(b - ball).getDistance() / d} dp", (b - ball).getDistance() < 16 * d)
            assertTrue("frame $n: the notch's action jumped ${abs(k - notch) / d} dp", abs(k - notch) < 12 * d)
            ball = b
            notch = k
            val now = crop()
            diffs += changed(shot, now)
            shot = now
            val flying = (left + chosen).any { rule.onAllNodesWithTag("bar-flying-$it").fetchSemanticsNodes().isNotEmpty() }
            if (!flying && cleared < 0) cleared = n
            n++
        }
        r.end()
        android.util.Log.i("bartest", "stroke lands: stack gone at frame $cleared; ball at most $maxBall dp a frame, the notch $maxNotch; the bar's change a frame ${diffs.joinToString(" ") { "%.4f".format(it) }}")
        assertTrue("the chosen bar landed within 120 frames", cleared >= 0)
        val around = max(diffs.getOrElse(cleared - 1) { 0f }, diffs.getOrElse(cleared + 1) { 0f })
        assertTrue("the frame the stack went changed the bar by ${diffs[cleared]} (round it $around)", diffs[cleared] <= around * 1.5f + 0.002f)
        assertEquals(1L, h.app.bars.current)
        rule.onNodeWithTag("bar-place-usage").assertExists()
        rule.onNodeWithTag("bar-place-chats").assertDoesNotExist()
    }

    /** 设置 · 下方栏: a place taken out and added back, a place moved, a bar made and deleted; the bar on Home follows. */
    @Test fun settingsAddRemove() {
        val h = launch(listOf(Screen.Home, Screen.Settings))
        rule.onNodeWithText("下方栏").performScrollTo().performClick()
        h.settle()
        assertEquals(Screen.BarSettings, h.app.stack.last())
        shot(h, "bar-settings")
        rule.onNodeWithTag("bar-remove-0-files").performClick()
        h.settle()
        assertEquals(listOf("chats", "profiles", "stations"), h.app.bars.sets[0])
        rule.onNodeWithTag("bar-add-0").performClick()
        h.settle()
        shot(h, "bar-settings-picker")
        rule.onAllNodesWithText("文件").filter(hasClickAction()).onFirst().performClick()
        h.settle()
        assertEquals(listOf("chats", "profiles", "stations", "files"), h.app.bars.sets[0])
        // Held and moved one slot right: 对话 after Profile.
        val slot = bounds("bar-slot-0-chats")
        rule.onRoot().performTouchInput {
            down(slot.center)
            for (i in 1..10) moveTo(Offset(slot.center.x + slot.width * i / 10f, slot.center.y))
            up()
        }
        h.settle()
        assertEquals(listOf("profiles", "chats", "stations", "files"), h.app.bars.sets[0])
        // A new bar: empty until a place is picked for it, then kept.
        rule.onNodeWithText("新建一栏").performScrollTo().performClick()
        h.settle()
        rule.onAllNodesWithText("用量").filter(hasClickAction()).onFirst().performClick()
        h.settle()
        assertEquals(3, h.app.bars.sets.size)
        assertEquals(listOf("usage"), h.app.bars.sets[2])
        shot(h, "bar-settings-three")
        rule.onNodeWithContentDescription("删除第 3 栏").performScrollTo().performClick()
        h.settle()
        assertEquals(2, h.app.bars.sets.size)
        // Made the second the one in view, then back on Home the bar is it.
        rule.onAllNodesWithText("设为当前").onFirst().performScrollTo().performClick()
        h.settle()
        assertEquals(1L, h.app.bars.current)
        rule.runOnUiThread { h.app.home() }
        h.settle()
        rule.onNodeWithTag("bar-place-usage").assertExists()
        // On Home, which is not in this bar: no ball.
        shot(h, "bar-home-other-bar")
    }

    /** On Station, for a manager: a "+" in the notch (named as what it adds; none in the top bar), which adds a station. */
    @Test fun stationsPlus() = stationsPlus(false)
    @Test fun stationsPlusDark() = stationsPlus(true)

    private fun stationsPlus(dark: Boolean) {
        val h = launch(dark = dark)
        rule.onNodeWithTag("bar-place-stations").performClick()
        h.settle()
        shot(h, if (dark) "bar-stations-plus-dark" else "bar-stations-plus-light")
        rule.onNode(hasTestTag("bar-action") and hasContentDescription("添加 station")).assertExists()
        rule.onAllNodesWithContentDescription("添加 station").assertCountEquals(1)
        rule.onNodeWithContentDescription("新建对话").assertDoesNotExist()
        rule.onNodeWithContentDescription("添加 station").performClick()
        h.settle()
        rule.runOnIdle { assertTrue("the sheet adding a station is open", h.app.sheet != null) }
    }

    /** Not a manager: no "+" on Station, the notch closed; on 用量 (nothing to add) closed too. */
    @Test fun noActionClosed() {
        val h = launch()
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "member"))
        h.settle()
        rule.onNodeWithTag("bar-place-stations").performClick()
        h.settle()
        rule.onNodeWithTag("bar-action").assertDoesNotExist()
        rule.onNodeWithContentDescription("添加 station").assertDoesNotExist()
        // The other bar: 连接 (a station online: a "+"), then 用量 (none): the notch closes.
        rule.runOnUiThread { h.app.setBars(h.app.bars.sets, 1) }
        h.settle()
        rule.onNodeWithTag("bar-place-connects").performClick()
        h.settle()
        rule.onNode(hasTestTag("bar-action") and hasContentDescription("添加连接")).assertExists()
        rule.onNodeWithTag("bar-place-usage").performClick()
        h.settle()
        assertEquals(listOf<Screen>(Screen.Usage), h.app.stack)
        rule.onNodeWithTag("bar-action").assertDoesNotExist()
        shot(h, "bar-usage-closed")
        // An owner again: the workspace as this test found it outlives it in the topics last shown (Topics.kt `latest`),
        // and a test after it opening Station drew it once as for a member (no "+", the notch closing a frame).
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "owner"))
        h.settle()
    }

    /**
     * Home to Station and back (Station not drawn before: what it adds not said yet as the bar switches): the notch stays
     * open the whole way, frame by frame, the icon in it swapping (令 to "+", and back).
     */
    @Test fun homeStationsSwap() {
        val h = launch()
        val full = 56 * d
        fun open(r: Recording, frames: Int) = repeat(frames) {
            r.frame()
            val b = rule.onNodeWithTag("bar-action").fetchSemanticsNode().boundsInRoot
            assertTrue("the notch's action stays (${b.width} of $full)", b.width >= 0.9f * full)
        }
        val there = h.record("bar-swap-to-stations")
        rule.onNodeWithTag("bar-place-stations").performClick()
        open(there, 30)
        there.end()
        rule.onNode(hasTestTag("bar-action") and hasContentDescription("添加 station")).assertExists()
        val back = h.record("bar-swap-to-chats")
        rule.onNodeWithTag("bar-place-chats").performClick()
        open(back, 30)
        back.end()
        rule.onNode(hasTestTag("bar-action") and hasContentDescription("新建对话")).assertExists()
    }

    /** From one "+" to another (Station's to 文件's): the same icon, which stays as it is, nothing popping in. */
    @Test fun plusToPlusStill() {
        val h = launch()
        rule.onNodeWithTag("bar-place-stations").performClick()
        h.settle()
        val r = h.record("bar-plus-to-plus")
        rule.onNodeWithTag("bar-place-files").performClick()
        repeat(20) {
            r.frame()
            val icons = rule.onAllNodesWithTag("bar-action-icon", useUnmergedTree = true).fetchSemanticsNodes()
            assertEquals("one icon in the notch", 1, icons.size)
            assertTrue("the icon at its size (${icons[0].boundsInRoot.width})", icons[0].boundsInRoot.width >= 29 * d)
        }
        r.end()
        rule.onNode(hasTestTag("bar-action") and hasContentDescription("添加文件夹")).assertExists()
    }

    /**
     * A place tapped shows its page at once, within two frames of the tap, not once what it shows has come (its
     * stations here take a while to come from the core) or the ball has arrived: the page's name in its top bar, then
     * its rows as they come. Back to a place already shown, at once too, with what it showed.
     */
    @Test fun tapShowsAtOnce() {
        val h = launch()
        h.fake.lags[Topics.stations(Fixtures.WS)] = 1500L
        val r = h.record("bar-tap-at-once")
        rule.onNodeWithTag("bar-place-stations").performClick()
        var n = 0
        r.framesUntil(30) { (rule.onAllNodesWithText("Station").fetchSemanticsNodes().isNotEmpty()).also { if (!it) n++ } }
        android.util.Log.i("bartap", "stations shown $n frames after the tap")
        assertTrue("Station shown $n frames after the tap", n <= 2)
        r.frames(10)
        r.end()
        rule.onNodeWithTag("bar-place-files").performClick()
        h.settle()
        val back = h.record("bar-tap-back")
        rule.onNodeWithTag("bar-place-stations").performClick()
        var m = 0
        back.framesUntil(30) { (rule.onAllNodesWithText("在线").fetchSemanticsNodes().isNotEmpty()).also { if (!it) m++ } }
        back.end()
        android.util.Log.i("bartap", "stations again, its rows $m frames after the tap")
        assertTrue("Station's rows shown again $m frames after the tap", m <= 2)
    }

    /**
     * Chats to 文件 (to its right in the bar): the page coming in is there the frame after the tap, moving in from the
     * right as it fades in, and comes to rest where it is; the chats' list fades out. Frames: motion/bar-switch-files.
     */
    @Test fun switchMotion() {
        val h = launch()
        val r = h.record("bar-switch-files")
        rule.onNodeWithTag("bar-place-files").performClick()
        r.frames(2)
        val coming = rule.onAllNodesWithText("文件").fetchSemanticsNodes().first().boundsInRoot.left
        r.frames(20)
        r.end()
        val rest = rule.onAllNodesWithText("文件").fetchSemanticsNodes().first().boundsInRoot.left
        assertTrue("文件 comes in from the right ($coming, at rest $rest)", coming > rest + 4 * d)
        assertEquals(listOf<Screen>(Screen.Files), h.app.stack)
    }
}
