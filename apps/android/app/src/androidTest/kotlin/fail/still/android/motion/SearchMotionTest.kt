// The home search opening from the field at the list's top and closing back into it (Search.kt; motion.sh runs it):
// the field is as wide as the list's where it starts and ends, and narrows or widens frame by frame as 取消 comes in
// or goes, not jumping between the two widths when the search's field gives way to the list's.
package fail.still.android.motion

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.unit.dp
import fail.still.android.Screen
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

class SearchMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun item(i: Int) = ChatItem(
        id = "c$i", session = "ember:c-$i", thread = 100L + i, title = "row-$i", agents = emptyList(), unread = false, mine = true,
        lastActiveAt = Fixtures.NOW - i * 60_000L, station = Fixtures.STATION, stationName = "st",
    )

    private fun view(n: Int) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "st", "st", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", (0 until n).map(::item))),
    )

    /** The search page's text field's width (px), or null once the page is gone. */
    private fun typed(): Float? = rule.onAllNodesWithContentDescription("搜索对话和消息").fetchSemanticsNodes().firstOrNull()?.boundsInRoot?.width

    @Test fun light() = openAndClose(false)
    @Test fun dark() = openAndClose(true)

    private fun openAndClose(dark: Boolean) {
        val h = Harness(rule)
        h.fake.put(Topics.chats(Fixtures.WS, false), view(12))
        h.fake.put(Topics.chats(Fixtures.WS, true), view(12))
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), view(0))
        h.launch(listOf(Screen.Home), dark)
        // The list first shows from its first row, the search above it: scrolled up to it.
        rule.onRoot().performTouchInput { swipeDown(startY = bottom * 0.3f, endY = bottom * 0.7f) }
        h.settle()
        val theme = if (dark) "dark" else "light"
        // The shown list's field (each list has one, the others off the screen): its text
        // field would be as wide as it, less its padding, icon and gap (Search.kt).
        val fields = rule.onAllNodesWithText("搜索对话和消息")
        val at = fields.fetchSemanticsNodes().indexOfFirst { it.boundsInRoot.left >= 0f && it.boundsInRoot.left < 100f }
        val list = fields.fetchSemanticsNodes()[at].boundsInRoot.width
        val full = list - with(rule.density) { (24 + 17 + 8).dp.toPx() }

        val open = mutableListOf<Float>()
        val opening = h.record("$theme-search-open")
        opening.frame { fields[at].performClick() }
        repeat(24) { typed()?.let(open::add); opening.frame() }
        opening.end()
        val narrow = typed()!!

        val close = mutableListOf<Float>()
        val closing = h.record("$theme-search-close")
        closing.frame { rule.onNodeWithText("取消").performClick() }
        repeat(24) { typed()?.let(close::add); closing.frame() }
        closing.end()
        Log.i("searchmotion", "$theme list $full narrow $narrow open $open close $close")

        check(narrow < full - 20) { "the field does not make room for 取消: $narrow of $full" }
        check(abs(open.first() - full) < 2f) { "opening, the field starts at ${open.first()}, not as wide as the list's ($full)" }
        check(abs(close.last() - full) < 2f) { "closing, the field ends at ${close.last()}, not as wide as the list's ($full)" }
        check(close.zipWithNext().all { (a, b) -> b >= a - 0.5f }) { "closing, the field narrows somewhere: $close" }
        check(close.size >= 8 && close.zipWithNext().count { (a, b) -> b > a + 0.5f } >= 6) { "closing, the field does not widen frame by frame: $close" }
    }
}
