// The workspaces in the bottom bar's panel (ui/Bar.kt, Places.kt) on the fake core: with two, the panel's top row is
// them, laid out as a bar's places are, the other's dot at its mark's corner; one stroke from the bar onto the other
// switches to it on the place shown (the ball going with the finger); a tap on it in the open panel does the same; the
// one in use tapped only closes the panel; with a single bar the panel still opens for them. Pictures: motion/bar-ws-*.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import fail.still.android.Screen
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceMark
import fail.still.android.data.WorkspaceMarksView
import fail.still.android.data.WorkspaceSummary
import fail.still.android.data.WorkspaceView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

class BarWorkspacesTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val other = "ws-other"

    private fun chats(ws: String, prefix: String) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState("$ws/st", "studio", "studio", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", (0 until 4).map { i ->
            ChatItem(
                id = "$prefix$i", session = "ember:c-$prefix$i", thread = 100L + i, title = "$prefix-row-$i", agents = emptyList(), unread = false, mine = true,
                lastActiveAt = Fixtures.NOW - i * 60_000L, station = "$ws/st", stationName = "studio",
            )
        })),
    )

    private fun launch(stack: List<Screen> = listOf(Screen.Home), dark: Boolean = false): Harness {
        val h = Harness(rule)
        for ((ws, prefix) in listOf(Fixtures.WS to "a", other to "b")) {
            h.fake.put(Topics.chats(ws, false), chats(ws, prefix))
            h.fake.put(Topics.chats(ws, true), chats(ws, prefix))
            h.fake.put(Topics.chats(ws, false, watching = true), chats(ws, prefix))
            h.fake.put(Topics.workspace(ws), WorkspaceView(id = ws, name = if (ws == other) "Other" else "Dev", role = "owner"))
        }
        // What the other has waiting for its person: one gone wrong, one waiting on them.
        val marks = WorkspaceMarksView(mapOf(
            Fixtures.WS to WorkspaceMark(alert = 0u, unread = 0u),
            other to WorkspaceMark(alert = 1u, unread = 2u, wait = 1u, tone = "alert", label = "1 个出错了 · 1 个在等你"),
        ), others = "alert")
        h.fake.put(Topics.workspaceMarks(Fixtures.WS), marks)
        h.fake.put(Topics.workspaceMarks(other), marks)
        h.launch(stack, dark)
        // Two workspaces (launch puts Fixtures' one).
        rule.runOnUiThread {
            h.fake.put(Topics.workspaces, listOf(AccountWorkspaces(Fixtures.account, listOf(
                WorkspaceSummary(Fixtures.WS, "Dev", "owner", 1, 1), WorkspaceSummary(other, "Other", "owner", 1, 1, emoji = "🌊"),
            ), loaded = true)))
        }
        h.settle()
        return h
    }

    private val d get() = rule.density.density
    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    /** A swipe up from the bar's first place, let go before the panel is open: it opens and stays. */
    private fun openPanel(h: Harness) {
        val g = bounds("bar-glass")
        rule.onRoot().performTouchInput {
            down(Offset(g.left + 28 * d, g.top + 28 * d))
            moveTo(Offset(g.left + 30 * d, g.top + 10 * d))
            moveTo(Offset(g.left + 32 * d, g.top - 20 * d))
            up()
        }
        h.settle(800)
    }

    /** One stroke from 对话 up onto the other workspace: the ball goes with the finger into its row; let go, it is the one in use, the list its. */
    @Test fun strokeToWorkspace() = stroke(false)
    @Test fun strokeToWorkspaceDark() = stroke(true)

    private fun stroke(dark: Boolean) {
        val h = launch(dark = dark)
        val g = bounds("bar-glass")
        val x0 = g.left + 28 * d
        val y0 = g.top + 28 * d
        val r = h.record(if (dark) "bar-ws-stroke-dark" else "bar-ws-stroke")
        rule.onRoot().performTouchInput { down(Offset(x0, y0)) }
        r.frame()
        // Up past the other bar's row, every frame a move.
        val top = g.top - 130 * d
        for (i in 1..20) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x0, y0 + (top - y0) * i / 20f)) } }
        r.frames(20)
        val chip = bounds("bar-workspace-$other")
        // In the columns a bar's places are in (two: at its ends), a bar's row under them.
        val mine = bounds("bar-workspace-${Fixtures.WS}")
        val first = bounds("bar-place-decisions")
        val last = bounds("bar-place-archive")
        assertTrue("the first workspace over the first column (${mine.center.x} vs ${first.center.x})", abs(mine.center.x - first.center.x) < 1.5f)
        assertTrue("the other over the last column (${chip.center.x} vs ${last.center.x})", abs(chip.center.x - last.center.x) < 1.5f)
        assertTrue("a bar's row 56 under the workspaces' (${(first.center.y - mine.center.y) / d})", abs(first.center.y - mine.center.y - 56 * d) < 1.5f)
        // Across onto the other workspace.
        for (i in 1..20) r.frame { rule.onRoot().performTouchInput { moveTo(Offset(x0 + (chip.center.x - x0) * i / 20f, top + (chip.center.y - top) * i / 20f)) } }
        r.frames(20)
        val ball = bounds("bar-ball")
        assertTrue("the ball is over the other workspace (${ball.center} vs ${chip.center})",
            abs(ball.center.x - chip.center.x) < 12 * d && abs(ball.center.y - chip.center.y) < 12 * d)
        rule.onRoot().performTouchInput { up() }
        r.frames(40)
        r.end()
        h.settle()
        assertEquals(other, h.app.workspace)
        assertEquals(listOf<Screen>(Screen.Home), h.app.stack)
        rule.onNodeWithTag("bar-workspace-$other").assertDoesNotExist()
    }

    /** On a place other than the chats (Station), the panel opened, the other workspace tapped: switched, still on Station. */
    @Test fun tapKeepsPlace() {
        val h = launch()
        rule.onNodeWithTag("bar-place-stations").let { n ->
            val b = n.fetchSemanticsNode().boundsInRoot
            rule.onRoot().performTouchInput { click(b.center) }
        }
        h.settle()
        assertEquals(listOf<Screen>(Screen.Stations), h.app.stack)
        openPanel(h)
        val chip = bounds("bar-workspace-$other")
        h.record("bar-ws-panel").also { it.frames(1); it.end() }
        rule.onRoot().performTouchInput { click(chip.center) }
        h.settle()
        assertEquals(other, h.app.workspace)
        assertEquals(listOf<Screen>(Screen.Stations), h.app.stack)
    }

    /** The one in use tapped: the panel closes, nothing else. */
    @Test fun tapCurrentCloses() {
        val h = launch()
        openPanel(h)
        val chip = bounds("bar-workspace-${Fixtures.WS}")
        rule.onRoot().performTouchInput { click(chip.center) }
        h.settle()
        assertEquals(Fixtures.WS, h.app.workspace)
        rule.onNodeWithTag("bar-workspace-${Fixtures.WS}").assertDoesNotExist()
    }

    /** With a single bar the panel opens all the same, its one row the workspaces. */
    @Test fun singleBar() {
        val h = launch()
        rule.runOnUiThread { h.app.setBars(listOf(listOf("chats", "files", "profiles", "stations")), 0) }
        h.settle()
        openPanel(h)
        h.record("bar-ws-single").also { it.frames(1); it.end() }
        val chip = bounds("bar-workspace-$other")
        rule.onRoot().performTouchInput { click(chip.center) }
        h.settle()
        assertEquals(other, h.app.workspace)
    }
}
