// The chats list (Home.kt, ListMotion.kt) as it changes, frame by frame (Harness.kt), for the mbui app to be held to
// (it replays these tapes: apps/mbui/src/sfreplay/tapes_wbtest.mbt): a chat with news going to the top over the others,
// one gone, one new, a new chat its station makes keeping its row, a mark coming, a row going from one day to another
// and a day's heading going, the filter switched from its menu, a row swiped away to archive it, the search opened from
// the list's top and closed, and the list come back to from a chat after it changed meanwhile.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import fail.still.android.Screen
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.RowMessage
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class HomeMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val titles = listOf("修一下登录", "整理发布清单", "首页加载变慢", "换掉旧的图标", "写周报草稿", "清理测试数据", "数据库迁移", "改进搜索排序", "设置页的开关", "看一下崩溃日志")
    private val said = listOf(
        "按钮的点击被表单吞掉了", "清单列好了，等你看", "首屏多请求了两次", "新图标放进去了", "草稿在共享文件夹里",
        "删掉了三百条旧数据", "迁移脚本跑完了", "排序按最近用过的", "开关的说明改好了", "崩溃出在启动的时候",
    )
    private val day = 86_400_000L

    /** Row `i`: its chat, said in `at`; every other one the viewer's (the 我参与的 list's). */
    private fun item(
        i: Int, at: Long = Fixtures.NOW - i * 60_000L, unread: Boolean = false, tone: String? = null, state: String? = null,
        id: String = "c$i", clientKey: String? = null, pending: Boolean? = null, archivable: Boolean? = null,
    ) = ChatItem(
        id = id, session = "ember:c-$i", thread = 100L + i, title = titles[i % titles.size], agents = emptyList(),
        last = RowMessage(seq = 1, authorKind = "agent", author = "ember:c-$i", text = said[i % said.size], createdAt = at, preview = said[i % said.size]),
        unread = unread, mine = i % 2 == 0, lastActiveAt = at, station = Fixtures.STATION, stationName = "studio", tone = tone, state = state,
        clientKey = clientKey, pending = pending, archivable = archivable,
    )

    private fun today(rows: List<ChatItem>) = ChatDay(0, Fixtures.NOW.toDouble(), "今天", rows)
    private fun yesterday(rows: List<ChatItem>) = ChatDay(1, (Fixtures.NOW - day).toDouble(), "昨天", rows)

    private fun view(days: List<ChatDay>) = ChatsView(
        me = Me("alice", "alice@example.com"), stations = listOf(StationState(Fixtures.STATION, "st", "studio", "online")), loading = false,
        days = days.filter { it.items.isNotEmpty() }, note = Fixtures.NO_WAIT,
    )

    /** The lists as the core has them now: all of them, and the viewer's. */
    private fun put(h: Harness, vararg days: ChatDay) {
        h.fake.put(Topics.chats(Fixtures.WS, false), view(days.toList()))
        h.fake.put(Topics.chats(Fixtures.WS, true), view(days.map { d -> d.copy(items = d.items.filter { it.mine }) }))
    }

    private fun launch(vararg days: ChatDay, stack: List<Screen> = listOf(Screen.Home), before: (Harness) -> Unit = {}): Harness {
        val h = Harness(rule)
        put(h, *days)
        h.fake.put(Topics.chats(Fixtures.WS, false, watching = true), view(emptyList()))
        before(h)
        h.launch(stack)
        return h
    }

    private fun rows(n: Int) = (0 until n).map { item(it) }

    /** Where the words `text` are on the screen (the shown list's, of the three side by side), in the root's px. */
    private fun at(text: String): Rect {
        val w = rule.onRoot().fetchSemanticsNode().size.width
        return rule.onAllNodesWithText(text).fetchSemanticsNodes().map { it.boundsInRoot }.first { it.left >= 0f && it.left < w }
    }

    @Test fun newsGoesUp() {
        val rows = rows(8)
        val h = launch(today(rows))
        val r = h.record("home-news-up")
        r.frame { put(h, today(listOf(item(5, at = Fixtures.NOW + 60_000, unread = true, tone = "done")) + rows.filter { it.id != "c5" })) }
        r.frames(45)
        r.end()
    }

    @Test fun rowGoes() {
        val rows = rows(8)
        val h = launch(today(rows))
        val r = h.record("home-row-gone")
        r.frame { put(h, today(rows.filter { it.id != "c2" })) }
        r.frames(40)
        r.end()
    }

    @Test fun rowComes() {
        val rows = rows(8)
        val h = launch(today(rows))
        val r = h.record("home-row-new")
        r.frame { put(h, today(listOf(item(9, at = Fixtures.NOW + 60_000, unread = true, tone = "done")) + rows)) }
        r.frames(40)
        r.end()
    }

    /** A chat asked for here (its station has not made it yet), then made: one row throughout, by its `clientKey`. */
    @Test fun madeChatKeepsItsRow() {
        val rows = rows(6)
        val asked = item(9, at = Fixtures.NOW + 60_000, id = "k-9", clientKey = "k-9", pending = true)
        val h = launch(today(listOf(asked) + rows))
        val r = h.record("home-made-chat")
        // (not at work: its spokes step on the wall clock, which never lets the page come to rest)
        r.frame { put(h, today(listOf(item(9, at = Fixtures.NOW + 60_000, clientKey = "k-9")) + rows)) }
        r.frames(30)
        r.end()
    }

    @Test fun markComes() {
        val rows = rows(6)
        val h = launch(today(rows))
        val r = h.record("home-mark")
        r.frame { put(h, today(rows.map { if (it.id == "c1") item(1, tone = "alert", state = "block") else it })) }
        r.frames(30)
        r.end()
    }

    /** A row from yesterday with news goes to today's top; then the last of yesterday's does, its heading going too. */
    @Test fun daysChange() {
        val now = rows(3)
        val before = (3 until 5).map { item(it, at = Fixtures.NOW - day - it * 60_000L) }
        val h = launch(today(now), yesterday(before))
        val first = h.record("home-days")
        val four = item(4, at = Fixtures.NOW + 60_000, unread = true, tone = "done")
        first.frame { put(h, today(listOf(four) + now), yesterday(before.take(1))) }
        first.frames(45)
        first.end()
        val second = h.record("home-day-gone")
        second.frame { put(h, today(listOf(item(3, at = Fixtures.NOW + 120_000, unread = true, tone = "done"), four) + now)) }
        second.frames(45)
        second.end()
    }

    /** The filter's menu opened from the top bar, 我参与的 picked: the lists slide. */
    @Test fun filterSwitched() {
        val h = launch(today(rows(8)))
        val r = h.record("home-filter")
        r.frame { r.tapAt(rule.onNodeWithContentDescription("筛选会话：全部").fetchSemanticsNode().boundsInRoot.center) }
        r.frames(25)
        r.frame { r.tapAt(at("我参与的").center) }
        r.frames(35)
        r.end()
    }

    /** A row with nothing left in it swiped left past the line: it goes off, is archived, and the rows close over it. */
    @Test fun swipedAway() {
        val rows = rows(8).map { if (it.id == "c3") item(3, archivable = true) else it }
        val h = launch(today(rows))
        val r = h.record("home-swipe")
        val row = at(titles[3])
        val width = rule.onRoot().fetchSemanticsNode().size.width.toFloat()
        val from = Offset(width * 0.75f, row.center.y)
        r.frame { r.finger("down", from) }
        for (i in 1..12) r.frame { r.finger("move", from - Offset(width * 0.05f * i, 0f)) }
        r.frame { r.finger("up", from - Offset(width * 0.6f, 0f)) }
        // off the screen and archived (Home.kt archive: the call once it has gone), then the core's list without it
        r.frames(20)
        r.frame { put(h, today(rows.filter { it.id != "c3" })) }
        r.frames(35)
        r.end()
    }

    /** The search at the list's top (the list put there first), opened, then closed. */
    @Test fun searchOpensAndCloses() {
        val h = launch(today(rows(12)))
        val r = h.record("home-search")
        r.frame { r.listTop() }
        r.frames(5)
        r.frame { r.tapAt(at("搜索全部内容").center) }
        r.frames(30)
        r.frame { r.tapAt(at("取消").center) }
        r.frames(30)
        r.end()
    }

    /**
     * A chat opened from the list, the list changing while the chat shows (one of its rows went to the top, one went,
     * one came), then back: the list drawn anew as it is, nothing moving in it.
     */
    @Test fun backToAChangedList() {
        val rows = rows(8)
        val h = launch(today(rows)) { it.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk)) }
        val r = h.record("home-back-changed")
        r.frame { r.push(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))) }
        r.frames(30)
        r.frame { put(h, today(listOf(item(9, at = Fixtures.NOW + 120_000, unread = true, tone = "done"), item(4, at = Fixtures.NOW + 60_000)) + rows.filter { it.id != "c4" && it.id != "c6" })) }
        r.frames(10)
        r.frame { r.back() }
        r.frames(40)
        r.end()
    }
}
