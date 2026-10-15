// The bottom bar (ui/Bar.kt, Places.kt) on the fake core: on Home in light and dark (the ball 6 past the bar on every
// side at rest; the notch empty, the page's own paper showing there; no shadow above the bar), a place tapped (the page
// switched in place, the ball over it), the panel of the other bars opened by a swipe up, one stroke from the bar into
// a place of another bar (that bar and that place), and the settings page's cards (a place taken out, one added, a bar
// made and deleted, a place moved). Pictures: settled.png under motion/bar-*.
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
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
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
     * A page pushed over a place's top hides the bar (and its back is there again); back, the bar is back. Back on a
     * place's top other than the chats goes to the chats, in place.
     */
    @Test fun pushedAndBack() {
        val h = launch()
        rule.runOnUiThread { h.app.push(Screen.Stations) }
        h.settle()
        rule.onNodeWithTag("bar-glass").assertDoesNotExist()
        rule.onNodeWithText("设置").assertExists()
        rule.runOnUiThread { h.app.pop() }
        h.settle()
        rule.onNodeWithTag("bar-glass").assertExists()
        ballAtRest(-1)
        rule.onNodeWithTag("bar-place-stations").performClick()
        h.settle()
        // A place's top: no back to anywhere.
        rule.onNodeWithText("设置").assertDoesNotExist()
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        h.settle()
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        assertEquals(false, rule.activity.isFinishing)
    }

    /** A swipe up on the bar, let go early: the panel goes on opening and stays open; a press beside it closes it. */
    @Test fun panelOpen() = panel(false)
    @Test fun panelOpenDark() = panel(true)

    private fun panel(dark: Boolean) {
        val h = launch(dark = dark)
        val g = bounds("bar-glass")
        rule.onRoot().performTouchInput {
            down(Offset(g.left + 28 * d, g.top + 28 * d))
            moveTo(Offset(g.left + 30 * d, g.top + 10 * d))
            moveTo(Offset(g.left + 32 * d, g.top - 20 * d))
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
        // The place at once, the glass still closing over it (the bar it is in not yet the one in view).
        r.frames(2)
        assertEquals(listOf<Screen>(Screen.Connects()), h.app.stack)
        assertEquals(0L, h.app.bars.current)
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
}
