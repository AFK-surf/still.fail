// What the home search lists once words are typed (Search.kt, the core's `search`, docs/search.md): the chats, the
// messages, then a section per kind the stations found (here execution history and services and tasks), each row its
// kind's icon, title, station (with several) and time over its line with the words marked; 查看更多 under a kind lists
// it alone (the topic asked again with `kind`), 全部结果 every kind again; under it all, the stations still answering
// and the core's note. A step of an execution history opens its chat and the history at it.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import fail.still.android.Screen
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatsView
import fail.still.android.data.FoundMessage
import fail.still.android.data.ListNote
import fail.still.android.data.Me
import fail.still.android.data.RowAgent
import fail.still.android.data.SearchGroup
import fail.still.android.data.SearchItem
import fail.still.android.data.SearchView
import fail.still.android.data.Stamp
import fail.still.android.data.StationState
import fail.still.android.data.TextMark
import fail.still.android.data.Topics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SearchResultsTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION
    private val mac = "${Fixtures.WS}/mac"
    private val q = "登录"

    private fun stamp(field: String, minutes: Int) = mapOf(field to Stamp((Fixtures.NOW - minutes * 60_000L).toDouble(), "$minutes 分钟前", "9月30日 10:00", "", true))
    private fun marks(text: String): List<TextMark> = text.indexOf(q).let { at -> if (at < 0) emptyList() else listOf(TextMark(at.toUInt(), (at + q.length).toUInt())) }
    private fun agent(key: String) = RowAgent(key = key, runtime = "claude", process = "warm", pending = 0, agentText = "Opus 5.5", maker = Fixtures.anthropic, statusText = "已完成")

    private fun chat(id: String, thread: Long, title: String, minutes: Int, station: String = st, name: String = "studio") = ChatItem(
        id = id, session = "ember:$id", thread = thread, title = title, agents = listOf(agent("ember:$id")), unread = false, mine = true,
        lastActiveAt = Fixtures.NOW - minutes * 60_000L, station = station, stationName = name, time = stamp("lastActiveAt", minutes),
    )

    private fun message(c: ChatItem, seq: Long, by: String, text: String, minutes: Int) = FoundMessage(
        station = c.station, thread = c.thread ?: 0L, seq = seq, chat = c, by = by, text = text, marks = marks(text),
        createdAt = Fixtures.NOW - minutes * 60_000L, time = stamp("createdAt", minutes),
    )

    private fun step(chat: ChatItem, index: Int, tool: String, text: String, minutes: Int) = SearchItem(
        kind = "history", key = "${chat.station}\u0001h:${chat.session}:$index", station = chat.station, stationName = chat.stationName,
        title = chat.title, text = text, marks = marks(text), chat = chat.session, chatTitle = chat.title, thread = chat.thread,
        session = chat.session, index = index.toUInt(), tool = tool, createdAt = Fixtures.NOW - minutes * 60_000L, time = stamp("createdAt", minutes),
    )

    private fun job(chat: ChatItem, id: String, title: String, text: String, port: Int?, minutes: Int) = SearchItem(
        kind = "job", key = "${chat.station}\u0001j:$id", station = chat.station, stationName = chat.stationName, title = title, text = text,
        marks = marks(text), chat = chat.session, thread = chat.thread, session = chat.session, job = id, port = port?.toUInt(),
        createdAt = Fixtures.NOW - minutes * 60_000L, time = stamp("createdAt", minutes),
    )

    private val safari = chat("c-2", 102L, "登录页在 Safari 上没反应", 12)
    private val sso = chat("c-5", 105L, "SSO 登录接入", 95, station = mac, name = "mac")
    private val steps = listOf(
        step(safari, 14, "Bash", "grep -rn \"登录\" web/src/pages/Login.tsx", 11),
        step(sso, 3, "Read", "docs/sso.md：登录回调地址要配成 /auth/callback", 90),
        step(safari, 22, "Edit", "修好 Safari 下登录按钮的点击区域", 8),
    )
    private val all = SearchView(
        items = listOf(safari, sso), chatsMore = false, words = listOf(q),
        messages = listOf(
            message(safari, 41, "Alice", "Safari 17 上点了登录没有任何反应", 12),
            message(sso, 7, "Opus 5.5", "…登录成功后回到原来的页面", 95),
        ),
        messagesMore = false,
        groups = listOf(
            SearchGroup("history", "执行历史", steps.take(2), more = true),
            SearchGroup("job", "服务和任务", listOf(
                job(safari, "j-1", "登录页预览", "vite dev · 登录页 :5173", 5173, 10),
                job(sso, "j-2", "登录回归测试", "pnpm test e2e/登录.spec.ts", null, 80),
            ), more = false),
        ),
        wait = ListNote(reading = true, text = "正在等待 mini", failing = emptyList(), empty = false),
        note = "部分 station 正在建立索引，结果可能不完整",
    )
    private val onlyHistory = SearchView(
        items = emptyList(), chatsMore = false, words = listOf(q), messages = emptyList(), messagesMore = false,
        groups = listOf(SearchGroup("history", "执行历史", steps, more = false)), wait = Fixtures.NO_WAIT,
    )

    private fun list() = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(st, "studio", "studio", "online"), StationState(mac, "mac", "mac", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", listOf(safari, sso))),
    )

    @Test fun light() = results(false)
    @Test fun dark() = results(true)

    private fun results(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = Harness(rule)
        h.fake.put(Topics.chats(Fixtures.WS, false), list())
        h.fake.put(Topics.chats(Fixtures.WS, true), list())
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), list().copy(days = emptyList()))
        h.fake.put(Topics.search(Fixtures.WS, q), all)
        h.fake.put(Topics.search(Fixtures.WS, q, "history"), onlyHistory)
        h.launch(listOf(Screen.Home), dark)
        // Two stations: each found thing says which it is on.
        h.fake.put(Topics.stations(Fixtures.WS), listOf(Fixtures.station, Fixtures.station.copy(station = mac, id = "mac", name = "mac")))
        rule.onRoot().performTouchInput { swipeDown(startY = bottom * 0.3f, endY = bottom * 0.7f) }
        h.settle()
        val fields = rule.onAllNodesWithText("搜索全部内容")
        val at = fields.fetchSemanticsNodes().indexOfFirst { it.boundsInRoot.left >= 0f && it.boundsInRoot.left < 100f }
        fields[at].performClick()
        h.keyboard()
        rule.onNode(hasSetTextAction()).performTextReplacement(q)
        // The keyboard away, the whole list in the picture.
        rule.runOnUiThread { WindowCompat.getInsetsController(rule.activity.window, rule.activity.window.decorView).hide(WindowInsetsCompat.Type.ime()) }
        h.keyboard()

        // (The home list stays under the search, its rows and bar too: what is looked for here is the search's alone.)
        rule.onNodeWithText("执行历史").assertIsDisplayed()
        rule.onNodeWithText("服务和任务").assertExists()
        rule.onNodeWithText("Safari 17 上点了登录没有任何反应").assertIsDisplayed()
        // Only the kind with more has 查看更多; the station and the time beside each found thing.
        rule.onAllNodesWithText("查看更多").assertCountEquals(1)
        rule.onNodeWithText("studio · 11 分钟前").assertIsDisplayed()
        rule.onNodeWithText("部分 station 正在建立索引，结果可能不完整").assertExists()
        h.record("search-all-$tone").end()

        // 查看更多: execution history alone, asked of the core with its kind.
        rule.onNodeWithText("查看更多").performClick()
        h.settle()
        assertTrue("the kind alone was not asked for", h.fake.subscribed(Topics.search(Fixtures.WS, q, "history")))
        rule.onNodeWithText("全部结果").assertIsDisplayed()
        rule.onNodeWithText("修好 Safari 下登录按钮的点击区域").assertIsDisplayed()
        rule.onAllNodesWithText("服务和任务").assertCountEquals(0)
        rule.onAllNodesWithText("查看更多").assertCountEquals(0)
        h.record("search-history-$tone").end()

        // 全部结果: every kind again.
        rule.onNodeWithText("全部结果").performClick()
        h.settle()
        rule.onNodeWithText("服务和任务").assertExists()
        rule.onAllNodesWithText("全部结果").assertCountEquals(0)

        // A step of an execution history: its chat, and the history at it over it.
        rule.onNodeWithText("grep -rn \"登录\" web/src/pages/Login.tsx").performClick()
        h.settle()
        val of = ChatOf.Session(safari.session)
        assertEquals(listOf(Screen.Chat(st, of), Screen.History(st, of, safari.session, 14L)), h.app.stack.takeLast(2))
    }
}
