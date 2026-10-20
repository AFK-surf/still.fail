// The archive's page (screens/Archive.kt) on the fake core: only its newest rows asked for (the core's `limit`), more as it
// is scrolled near its end; a field over it asks for those with its words (`q`); a row tapped opens its chat. Pictures:
// motion/archive-{list,search}.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.filter
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import fail.still.android.Screen
import fail.still.android.data.ArchiveDay
import fail.still.android.data.ArchiveItem
import fail.still.android.data.ArchiveView
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceView
import fail.still.android.screenOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ArchiveListTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun item(i: Int) = ArchiveItem(Fixtures.STATION, "a-$i", "ember:a-$i", 300L + i, "archived-$i", "说过的话", Fixtures.NOW.toDouble(), "10:00", "手动归档", true)
    private fun view(shown: List<Int>, total: Int) =
        ArchiveView(listOf(ArchiveDay("今天", shown.map(::item))), emptyList(), wait = Fixtures.NO_WAIT, total = total.toUInt(), more = shown.size < total)

    @Test fun pagesLooksForAndOpens() {
        val h = Harness(rule)
        val chats = ChatsView(me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "st", "st", "online")), loading = false,
            days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", emptyList())))
        h.fake.put(Topics.chats(Fixtures.WS, false), chats)
        h.fake.put(Topics.chats(Fixtures.WS, true), chats)
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats)
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "owner"))
        val page = Topics.ARCHIVE_PAGE
        h.fake.put(Topics.archive(Fixtures.WS), view((0 until page).toList(), 150))
        h.fake.put(Topics.archive(Fixtures.WS, limit = page * 2), view((0 until page * 2).toList(), 150))
        h.fake.put(Topics.archive(Fixtures.WS, limit = page * 3), view((0 until 150).toList(), 150))
        h.fake.put(Topics.archive(Fixtures.WS, "archived-7"), view(listOf(7), 1))
        h.launch(listOf(Screen.Home))
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(Fixtures.station)) }
        h.settle()
        rule.runOnUiThread { h.app.place(screenOf("archive")) }
        h.settle()
        h.record("archive-list").also { it.frames(1); it.end() }
        assertTrue(rule.onAllNodesWithText("archived-${page + 5}").fetchSemanticsNodes().isEmpty())

        // Scrolled on and on: the next rows come as the end nears, all of them in the end.
        repeat(40) { rule.onRoot().performTouchInput { swipeUp(startY = bottom * 0.8f, endY = bottom * 0.2f) }; h.settle() }
        assertTrue("the last row reached", rule.onAllNodesWithText("archived-149").fetchSemanticsNodes().isNotEmpty())

        // Looked for: only the one with the words.
        repeat(60) { rule.onRoot().performTouchInput { swipeDown(startY = bottom * 0.2f, endY = bottom * 0.8f) }; h.settle() }
        rule.onNodeWithContentDescription("搜索归档").performTextInput("archived-7")
        h.settle()
        h.record("archive-search").also { it.frames(1); it.end() }
        assertTrue(rule.onAllNodesWithText("archived-8", substring = true).fetchSemanticsNodes().isEmpty())

        // Tapped (the row, not the field with the same words in it): its chat.
        val row = rule.onAllNodesWithText("archived-7", substring = true).filter(hasClickAction() and !hasSetTextAction()).onFirst()
        row.performClick()
        h.settle()
        assertEquals(Screen.Chat(Fixtures.STATION, ChatOf.Session("ember:a-7")), h.app.stack.last())
    }
}
