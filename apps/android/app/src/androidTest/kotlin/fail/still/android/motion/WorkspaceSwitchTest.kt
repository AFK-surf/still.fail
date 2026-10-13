// Switching workspace (Home.kt, Workspaces.kt): the lists slide from one workspace's rows to the other's, never through
// the loading look (its placeholders, with no rows) while the core reads the new one from the device. Switched by the
// app (a notification's link), from the panel the workspace's capsule opens, and by a swipe on the capsule.
package fail.still.android.motion

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import fail.still.android.Screen
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceSummary
import org.junit.Rule
import org.junit.Test

class WorkspaceSwitchTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val other = "ws-other"

    private fun view(ws: String, prefix: String) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState("$ws/st", "st", "st", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", (0 until 12).map { i ->
            ChatItem(
                id = "$prefix$i", session = "ember:c-$prefix$i", thread = 100L + i, title = "$prefix-row-$i", agents = emptyList(), unread = false, mine = true,
                lastActiveAt = Fixtures.NOW - i * 60_000L, station = "$ws/st", stationName = "st",
            )
        })),
    )

    /** Which workspace's rows are on screen: "a", "b", both, or none (the loading look). */
    private fun rows(): String {
        val texts = rule.onAllNodesWithText("-row-", substring = true).fetchSemanticsNodes()
            .mapNotNull { it.config.getOrNull(SemanticsProperties.Text)?.firstOrNull()?.text }
        return listOf("a", "b").filter { p -> texts.any { it.startsWith("$p-row-") } }.joinToString("+").ifEmpty { "none" }
    }

    /** Home on "Dev" (its rows "a-…"), with "Other" (rows "b-…") after it, read as slowly as the real core reads a list. */
    private fun twoWorkspaces(): Harness {
        val h = Harness(rule)
        for (mine in listOf(false, true)) {
            h.fake.put(Topics.chats(Fixtures.WS, mine), view(Fixtures.WS, "a"))
            h.fake.put(Topics.chats(other, mine), view(other, "b"))
        }
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), view(Fixtures.WS, "a"))
        h.fake.put(Topics.chats(other, false, watching = true), view(other, "b"))
        // As long as the real core takes to read a workspace's list from the device the first time.
        for (topic in listOf(Topics.chats(other, false), Topics.chats(other, true), Topics.chats(other, false, watching = true))) h.fake.lags[topic] = 50
        h.launch(listOf(Screen.Home))
        // Two workspaces (launch puts Fixtures' one).
        h.fake.put(Topics.workspaces, listOf(AccountWorkspaces(Fixtures.account, listOf(
            WorkspaceSummary(Fixtures.WS, "Dev", "owner", 1, 1), WorkspaceSummary(other, "Other", "owner", 1, 1),
        ), loaded = true)))
        h.settle()
        check(rows() == "a") { "start: ${rows()}" }
        return h
    }

    /** Steps `n` frames, noting whose rows each shows; checks they end on the other's, never through the loading look. */
    private fun follow(h: Harness, r: Recording, what: String, seen: ArrayList<String>, n: Int = 30) {
        repeat(n) { r.frame(); seen += rows() }
        r.end()
        Log.i("wsswitch", "$what: rows by frame: $seen")
        check(seen.last() == "b") { "$what: never switched: $seen" }
        check("none" !in seen) { "$what: the list went through its loading look: $seen" }
        check(h.app.workspace == other) { "$what: the workspace kept is ${h.app.workspace}" }
    }

    @Test fun switched() {
        val h = twoWorkspaces()
        val r = h.record("workspace-switch")
        val seen = ArrayList<String>()
        r.frame { rule.runOnUiThread { h.app.pickWorkspace(other); h.app.home() } }
        seen += rows()
        follow(h, r, "switched", seen)
    }

    /** The capsule opens the panel; a tap on the other workspace there closes it and slides over to it. */
    @Test fun fromThePanel() {
        val h = twoWorkspaces()
        rule.onNodeWithText("Dev").performClick()
        h.settle()
        rule.onNodeWithText("Other").assertExists("the panel lists the other workspace")
        val r = h.record("workspace-panel-switch")
        val seen = ArrayList<String>()
        r.frame { rule.onNodeWithText("Other").performClick() }
        seen += rows()
        follow(h, r, "from the panel", seen)
        rule.onNodeWithText("新建 workspace").assertDoesNotExist()
    }

    /** Dragged left on the capsule past the threshold, it lets go onto the next workspace and the lists slide with it. */
    @Test fun swiped() {
        val h = twoWorkspaces()
        val title = rule.onNodeWithText("Dev").fetchSemanticsNode().boundsInRoot
        val r = h.record("workspace-swipe")
        val seen = ArrayList<String>()
        r.frame { rule.onRoot().performTouchInput { down(Offset(title.left + title.width * 0.6f, title.center.y)) } }
        repeat(10) { r.frame { rule.onRoot().performTouchInput { moveBy(Offset(-30f, 0f)) } }; seen += rows() }
        // Not switched while the finger is down: only the capsule's names move.
        check(seen.all { it == "a" }) { "switched before letting go: $seen" }
        check(h.app.workspace == Fixtures.WS) { "switched before letting go" }
        r.frame { rule.onRoot().performTouchInput { up() } }
        seen += rows()
        follow(h, r, "swiped", seen)
    }

    /** At the last workspace a drag on toward the next one gives a little and springs back: nothing is switched. */
    @Test fun swipedPastTheEnd() {
        val h = twoWorkspaces()
        rule.runOnUiThread { h.app.pickWorkspace(other); h.app.home() }
        h.settle()
        check(rows() == "b") { "start: ${rows()}" }
        val title = rule.onNodeWithText("Other").fetchSemanticsNode().boundsInRoot
        rule.onRoot().performTouchInput { down(Offset(title.left + title.width * 0.6f, title.center.y)); repeat(10) { moveBy(Offset(-30f, 0f)) }; up() }
        h.settle()
        check(h.app.workspace == other) { "switched past the end, to ${h.app.workspace}" }
        check(rows() == "b") { "after: ${rows()}" }
    }
}
