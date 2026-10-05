// Switching workspace from the switcher (Workspaces.kt): the list goes from one workspace's rows to the other's, never
// through the loading look (its placeholders, with no rows) while the core reads the new one from the device.
package fail.still.android.motion

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
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

    @Test fun switched() {
        val h = Harness(rule)
        h.fake.put(Topics.workspaces, listOf(AccountWorkspaces(Fixtures.account, listOf(
            WorkspaceSummary(Fixtures.WS, "Dev", "owner", 1, 1), WorkspaceSummary(other, "Other", "owner", 1, 1),
        ), loaded = true)))
        for (mine in listOf(false, true)) {
            h.fake.put(Topics.chats(Fixtures.WS, mine), view(Fixtures.WS, "a"))
            h.fake.put(Topics.chats(other, mine), view(other, "b"))
        }
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), view(Fixtures.WS, "a"))
        h.fake.put(Topics.chats(other, false, watching = true), view(other, "b"))
        // As long as the real core takes to read a workspace's list from the device the first time.
        for (topic in listOf(Topics.chats(other, false), Topics.chats(other, true), Topics.chats(other, false, watching = true))) h.fake.lags[topic] = 50
        h.launch(listOf(Screen.Home))
        check(rows() == "a") { "start: ${rows()}" }
        val r = h.record("workspace-switch")
        val seen = ArrayList<String>()
        r.frame { rule.runOnUiThread { h.app.pickWorkspace(other); h.app.home() } }
        seen += rows()
        repeat(30) { r.frame(); seen += rows() }
        r.end()
        Log.i("wsswitch", "rows by frame: $seen")
        check(seen.last() == "b") { "never switched: $seen" }
        check("none" !in seen) { "the list went through its loading look: $seen" }
    }
}
