// The places' pages as the chats' list is (screens/PlacePage.kt), on the fake core: with the bar under them, Home's top
// bar (settings, the page's name, its other actions), no back, no large title or note; pushed from settings, a sub-page
// (back to 设置, its name in the middle, its "+" at the right) with no bar. Pictures: motion/place-<place>-{light,dark},
// motion/place-pushed-profiles-{light,dark}.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import fail.still.android.PLACES
import fail.still.android.Screen
import fail.still.android.data.ArchiveDay
import fail.still.android.data.ArchiveItem
import fail.still.android.data.ArchiveView
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.ConnectsView
import fail.still.android.data.Counts
import fail.still.android.data.DecisionWorking
import fail.still.android.data.DecisionsToday
import fail.still.android.data.DecisionsView
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.Me
import fail.still.android.data.Overview
import fail.still.android.data.ProfilesView
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.UsageView
import fail.still.android.data.Viewer
import fail.still.android.data.WorkspaceView
import fail.still.android.placeLabel
import fail.still.android.screenOf
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class PlacePagesTest {
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

    private fun launch(stack: List<Screen>, dark: Boolean): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.chats(Fixtures.WS, false), chats(12))
        h.fake.put(Topics.chats(Fixtures.WS, true), chats(12))
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), chats(0))
        h.fake.put(Topics.workspace(Fixtures.WS), WorkspaceView(id = Fixtures.WS, name = "Dev", role = "owner"))
        h.fake.put(Topics.connects(Fixtures.WS, false), ConnectsView(Me("alice", "alice@example.com"), emptyList(), wait = Fixtures.NO_WAIT))
        h.fake.put(Topics.profiles(Fixtures.WS), ProfilesView(emptyList(), wait = Fixtures.NO_WAIT))
        h.fake.put(Topics.usage(Fixtures.WS, 7), UsageView(7u, Fixtures.NO_WAIT, true, emptyList(), emptyList(), emptyList(), 0.0, emptyList(), listOf("没有读到 studio 的用量"), "按各家 API 价折算"))
        h.fake.put(Topics.archive(Fixtures.WS), ArchiveView(listOf(ArchiveDay("今天", (0 until 6).map {
            ArchiveItem(Fixtures.STATION, "a-$it", "ember:a-$it", 300L + it, listOf("旧的发版清单", "试一下新模型", "周报")[it % 3], "已完成", Fixtures.NOW.toDouble(), "10:0$it", "手动归档", true)
        })), emptyList(), wait = Fixtures.NO_WAIT))
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(emptyList(), 0u, wait = Fixtures.NO_WAIT, today = DecisionsToday(3u, "6 分钟", 1u), working = listOf(
            DecisionWorking(Fixtures.STATION, "studio", null, null, "ember:w-1", 401L, "官网首屏", "在做 · 截三种首屏"),
        )))
        h.launch(stack, dark)
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station)) }
        h.settle()
        return h
    }

    private fun shot(h: Harness, name: String) = h.record(name).also { it.frames(1); it.end() }

    @Test fun placesLight() = places(false)
    @Test fun placesDark() = places(true)

    /** Each place's top page with the bar: its name in the top bar, the gear, no back (to 设置 or the chats). */
    private fun places(dark: Boolean) {
        val h = launch(listOf(Screen.Home), dark)
        for (place in PLACES) {
            rule.runOnUiThread { h.app.place(screenOf(place)) }
            h.settle()
            assertEquals(listOf(screenOf(place)), h.app.stack)
            shot(h, "place-$place-" + if (dark) "dark" else "light")
            rule.onNodeWithTag("bar-glass").assertExists()
            rule.onNodeWithContentDescription("设置").assertExists()
            if (place != "chats") rule.onNodeWithText(placeLabel(place)).assertExists()
            rule.onNodeWithText("对话").assertDoesNotExist()
        }
    }

    @Test fun pushedProfilesLight() = pushedProfiles(false)
    @Test fun pushedProfilesDark() = pushedProfiles(true)

    /** Profile from settings: back to 设置, its name in the middle, its "+" at the right (no bar to hold it), adding one. */
    private fun pushedProfiles(dark: Boolean) {
        val h = launch(listOf(Screen.Home, Screen.Settings), dark)
        rule.onNodeWithText("Profile").performScrollTo().performClick()
        h.settle()
        assertEquals(listOf(Screen.Home, Screen.Settings, Screen.Profiles()), h.app.stack)
        shot(h, "place-pushed-profiles-" + if (dark) "dark" else "light")
        rule.onNodeWithTag("bar-glass").assertDoesNotExist()
        rule.onNodeWithText("设置").assertExists()
        rule.onNode(hasContentDescription("添加 Profile") and !hasTestTag("bar-action")).performClick()
        h.settle()
        assertEquals(Screen.NewProfile(Fixtures.STATION), h.app.stack.last())
    }
}
