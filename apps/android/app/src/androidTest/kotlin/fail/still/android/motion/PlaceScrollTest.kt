// A place's page keeps its scroll place as the bottom bar switches away from it and back (Places.kt; App.kt Pages): the
// chats' list, 奏's idle page, 文件, Station, 连接, 用量 and 已归档, each long enough to scroll on the fake core, scrolled,
// switched to another place and back: the same row at the top, where it was. Pictures: motion/scroll-<place>-{before,after}.
package fail.still.android.motion

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import fail.still.android.Screen
import fail.still.android.data.ArchiveDay
import fail.still.android.data.ArchiveItem
import fail.still.android.data.ArchiveView
import fail.still.android.data.Bind
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.Connect
import fail.still.android.data.ConnectItem
import fail.still.android.data.ConnectState
import fail.still.android.data.ConnectsView
import fail.still.android.data.Counts
import fail.still.android.data.DecisionWorking
import fail.still.android.data.DecisionsView
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.Me
import fail.still.android.data.Overview
import fail.still.android.data.Owner
import fail.still.android.data.PersonShown
import fail.still.android.data.SlackIdentity
import fail.still.android.data.SlackTokens
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.UsageView
import fail.still.android.data.Viewer
import fail.still.android.data.WorkspaceView
import fail.still.android.screenOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

class PlaceScrollTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun item(i: Int) = ChatItem(
        id = "c$i", session = "ember:c-$i", thread = 100L + i, title = "row-$i", agents = emptyList(), unread = false, mine = true,
        lastActiveAt = Fixtures.NOW - i * 60_000L, station = Fixtures.STATION, stationName = "st",
    )

    private fun chats(n: Int) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "st", "st", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", (0 until n).map(::item))),
    )

    private fun overview(folders: Int) = Overview(
        viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
        slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
        drive = DriveRoots((0 until folders).map { DriveRoot("/Users/alice/f$it", "folder-$it", "ok") }),
    )

    private fun connect(id: String, name: String) = Connect(
        id = id, name = name, team = "Acme", enabled = true, kind = "slack", mode = "multi-session", requireMention = true,
        bind = Bind(runtime = "claude", model = "claude-opus-5-5", effort = "high"), slack = SlackTokens("", ""),
        connection = ConnectState(state = "connected", workspace = SlackIdentity("Acme", "T0$id", "https://$id.slack.com/", "U0$id", name)),
        createdBy = Owner("alice", "Alice", PersonShown("Alice", "Alice", mine = true)), sessions = 0,
        statusText = "在线", presence = "online", modeText = "多会话", modeShort = "多会话", runtimeText = "Claude Code", runText = "Claude Code · Opus 5.5 · high", modelName = "Opus 5.5",
    )

    /** Twelve stations, the first lending forty folders. */
    private val stations = (0 until 12).map { i ->
        Fixtures.station.copy(station = if (i == 0) Fixtures.STATION else "${Fixtures.WS}/s$i", id = if (i == 0) "st" else "s$i", name = "st-$i", overview = if (i == 0) overview(40) else null)
    }

    private fun launch(): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.chats(Fixtures.WS, false), chats(40))
        h.fake.put(Topics.chats(Fixtures.WS, true), chats(40))
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats(0))
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "owner"))
        // Two connects on each station: the list is a row each (stations with none are left out of it).
        h.fake.put(Topics.connects(Fixtures.WS, false), ConnectsView(Me("alice", "alice@example.com"), stations.flatMap { st ->
            (0 until 2).map { j -> ConnectItem(st.station, st.name, connect("${st.id}-$j", "conn-${st.id}-$j"), emptyList(), null, emptyList(), 0) }
        }, wait = Fixtures.NO_WAIT))
        h.fake.put(Topics.usage(Fixtures.WS, 7), UsageView(7u, Fixtures.NO_WAIT, true, emptyList(), emptyList(), emptyList(), 0.0, emptyList(), (0 until 60).map { "note-$it" }, "basis"))
        h.fake.put(Topics.archive(Fixtures.WS), ArchiveView(listOf(ArchiveDay("今天", (0 until 30).map {
            ArchiveItem(Fixtures.STATION, "a-$it", "ember:a-$it", 300L + it, "archived-$it", "说过的话", Fixtures.NOW.toDouble(), "10:00", "手动归档", true)
        })), emptyList(), wait = Fixtures.NO_WAIT))
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, wait = Fixtures.NO_WAIT, working = (0 until 30).map {
            DecisionWorking(Fixtures.STATION, "st", null, null, "ember:w-$it", 400L + it, "work-$it", "在做")
        }))
        h.launch(listOf(Screen.Home))
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), stations) }
        h.settle()
        return h
    }

    /** The texts starting with `prefix` on the screen, top to bottom, with their tops (px). */
    private fun shown(prefix: String): List<Pair<String, Float>> {
        val height = rule.onRoot().fetchSemanticsNode().size.height
        // Where each is laid out (its bounds are clipped to what shows: one scrolled away above is a line at the top).
        return rule.onAllNodesWithText(prefix, substring = true).fetchSemanticsNodes()
            .filter { it.positionInRoot.y >= 0 && it.positionInRoot.y + it.size.height <= height }
            .mapNotNull { n -> n.config.getOrNull(SemanticsProperties.Text)?.firstOrNull()?.text?.takeIf { it.startsWith(prefix) }?.let { it to n.positionInRoot.y } }
            .sortedBy { it.second }
    }

    @Test fun chats() = kept("chats", "row-", via = "files")
    @Test fun decisions() = kept("decisions", "work-")
    @Test fun files() = kept("files", "folder-")
    @Test fun stations() = kept("stations", "st-")
    @Test fun connects() = kept("connects", "conn-")
    @Test fun usage() = kept("usage", "note-")
    @Test fun archive() = kept("archive", "archived-")

    /** `place` scrolled (clear of the bar at the foot), switched to `via` on the bar and back: as it was left. */
    private fun kept(place: String, prefix: String, via: String = "chats") {
        val h = launch()
        rule.runOnUiThread { h.app.place(screenOf(place)) }
        h.settle()
        repeat(2) { rule.onRoot().performTouchInput { swipeUp(startY = bottom * 0.65f, endY = bottom * 0.35f) }; h.settle() }
        val before = shown(prefix)
        Log.i("placescroll", "$place before $before")
        h.record("scroll-$place-before").also { it.frames(1); it.end() }
        assertTrue("$place scrolled: $before", before.isNotEmpty() && before.first().first != "${prefix}0")
        rule.runOnUiThread { h.app.place(screenOf(via)) }
        h.settle()
        // As it is drawn coming back, frame by frame, not only once it has settled: its first frame is where it was left.
        val back = h.record("scroll-$place-back")
        rule.runOnUiThread { h.app.place(screenOf(place)) }
        back.framesUntil(40) { shown(prefix).isNotEmpty() }
        val first = shown(prefix)
        back.end()
        val after = shown(prefix)
        Log.i("placescroll", "$place first $first after $after")
        for ((name, now) in listOf("first frame" to first, "settled" to after)) {
            assertEquals("$place, $name: the row at the top", before.first().first, now.firstOrNull()?.first)
            assertTrue("$place, $name: where it was (${before.first().second} vs ${now.first().second})", abs(before.first().second - now.first().second) <= 2f)
        }
    }
}
