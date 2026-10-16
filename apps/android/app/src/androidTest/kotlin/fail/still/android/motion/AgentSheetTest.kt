// An agent's card (AgentSheet.kt): its name beside its messages opens it over the chat, with where it stands, its
// latest lines, its figures and the rows that lead on (its history among them); at work it can be stopped from there.
// The chat's own sheet, from "…" (ChatInfo.kt): its name, its agents (each opens its card) and what can be done with it.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.Activity
import fail.still.android.data.ActivityNow
import fail.still.android.data.AgentCardLine
import fail.still.android.data.AgentCardMeter
import fail.still.android.data.AgentCardNote
import fail.still.android.data.AgentCardView
import fail.still.android.data.Attention
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatShare
import fail.still.android.data.ChatSharePlace
import fail.still.android.data.ChatShareTo
import fail.still.android.data.Creator
import fail.still.android.data.HistoryView
import fail.still.android.data.Job
import fail.still.android.data.Live
import fail.still.android.data.Person
import fail.still.android.data.PersonShown
import fail.still.android.data.Quota
import fail.still.android.data.QuotaWindow
import fail.still.android.data.RunnableProfile
import fail.still.android.data.Session
import fail.still.android.data.Stamp
import fail.still.android.data.Topics
import fail.still.android.data.TurnRecord
import fail.still.android.data.UsageLine
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AgentSheetTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val of = ChatOf.Thread(Fixtures.THREAD)
    private val topic = Topics.chat(Fixtures.STATION, of)
    private val key = "ember:c-1"
    private val name = "Opus 5.5 · high"

    private fun quota(short: Long, week: Long) = Quota(
        state = "ok", checkedAt = Fixtures.NOW,
        windows = listOf(
            QuotaWindow(label = "5 小时", usedPercent = 100.0 - short, mark = "5h", left = short, level = if (short < 10) "red" else "ok"),
            QuotaWindow(label = "本周", usedPercent = 100.0 - week, mark = "周", left = week, level = "ok"),
        ),
    )

    private fun agent(running: Boolean, left: Long = 72, notes: List<AgentCardNote> = emptyList()) = ChatAgent(
        session = Session(
            key = key, runtime = "claude", process = if (running) "running" else "warm", pending = 0,
            statusText = if (running) "进行中" else "已完成", tone = if (running) "accent" else "green", mark = if (running) "run" else null,
            titleText = "修一下登录", agentText = name, model = "opus", modelName = "Opus 5.5", effort = "high", maker = Fixtures.anthropic, runtimeText = "Claude Code",
            processText = if (running) "运行中" else "保温中", efforts = listOf("high"),
            time = mapOf("lastActiveAt" to Stamp(Fixtures.NOW.toDouble(), "12 分钟前", "9月30日 10:00", "", true)),
        ),
        status = if (running) "running" else "final", badge = if (running) "run" else null, profiles = emptyList(), choices = emptyList(),
        account = RunnableProfile(id = "p1", name = "zzj-max", current = true, quota = quota(left, 41)),
        attention = notes.map { Attention(kind = "disk", text = it.text) }, since = if (running) System.currentTimeMillis() - 252_000 else null,
        turns = (1..8).map { TurnRecord(id = "t$it", kind = "input", startedAt = Fixtures.NOW - it * 600_000L, endedAt = Fixtures.NOW - it * 600_000L + 540_000) },
        threads = emptyList(),
        jobs = listOf(Job(id = "j1", name = "web", state = "running", port = 5173, startedAt = Fixtures.NOW)),
    )

    private fun card(running: Boolean, context: Double = 61.0, notes: List<AgentCardNote> = emptyList()) = AgentCardView(
        work = "8 轮 · 共干了 1 小时 12 分", cost = "$4.20", tokens = "输入 1.2M · 输出 34K",
        cache = AgentCardMeter(92.0, "92%", "ok"),
        context = AgentCardMeter(context, "122K / 200K", if (context >= 95) "red" else if (context >= 80) "amber" else "ok"),
        jobs = "服务在线：web · 在盯着：CI",
        latest = listOf(AgentCardLine("11", "读取 History.kt"), AgentCardLine("12", "在 studio 上跑 check.sh full")) +
            if (running) listOf(AgentCardLine("now", "编辑 AgentSheet.kt", now = true)) else listOf(AgentCardLine("13", "改好了：密码错误、账号不存在、网络断开三种情况都有中文提示。")),
        attention = notes,
    )

    private val people = listOf("alice" to "Alice", "bob" to "Bob").map { (id, n) -> Person(id = id, name = n, via = "ember", shown = PersonShown(name = n, display = n, mine = id == "alice")) }

    private val chatPage = listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of))

    private fun open(running: Boolean, dark: Boolean = false, left: Long = 72, context: Double = 61.0, notes: List<AgentCardNote> = emptyList(), pinned: Boolean? = false, stack: List<Screen> = chatPage, xshare: ChatShare? = null): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), Live(loaded = true, timeline = emptyList(), steps = emptyList(), activity = if (running) Activity(ActivityNow("now", "编辑 AgentSheet.kt")) else null))
        h.fake.put(Topics.agentCard(Fixtures.STATION, key), card(running, context, notes))
        val talk = Fixtures.talk.map { if (it.authorKind == "agent") it.copy(by = it.by.copy(name = name)) else it }
        val thread = Fixtures.thread(talk.last().seq).copy(
            creator = Creator(id = "alice", name = "Alice", via = "ember", shown = people[0].shown),
            time = mapOf("createdAt" to Stamp(Fixtures.NOW.toDouble(), "3 小时前", "9月30日 07:00", "", true)),
        )
        h.fake.put(topic, Fixtures.chat(talk, thread = thread).copy(agents = listOf(agent(running, left, notes)), people = people, pinned = pinned, xshare = xshare))
        h.fake.put(Topics.history(Fixtures.STATION, key), HistoryView(
            items = emptyList(), live = emptyList(), edge = "已到会话开头", empty = false, loaded = true,
            usage = listOf(UsageLine("模型调用", "142 次"), UsageLine("输入", "1.2M"), UsageLine("其中缓存", "1.1M"), UsageLine("输出", "34K"), UsageLine("缓存命中率", "92%"), UsageLine("上下文", "122K / 200K（61%）"), UsageLine("费用估算", "$4.20")),
        ))
        h.launch(stack, dark = dark)
        return h
    }

    /** A still picture of the page as it is, under `name`. */
    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }

    @Test
    fun aNameOpensItsCardAndTheCardItsHistory() {
        val h = open(running = false)
        rule.onAllNodesWithText(name)[0].performClick()
        h.settle()
        // Where it stands and when, its figures, and the rows that lead on.
        rule.onNodeWithText("做完了 · 12 分钟前").assertIsDisplayed()
        rule.onNodeWithText("$4.20").assertIsDisplayed()
        rule.onNodeWithText("92%").assertIsDisplayed()
        rule.onNodeWithText("61%").assertIsDisplayed()
        rule.onNodeWithText("zzj-max · 自动").assertIsDisplayed()
        rule.onNodeWithText("服务在线：web · 在盯着：CI").assertIsDisplayed()
        // Not at work: nothing to stop.
        rule.onNodeWithText("停止").assertDoesNotExist()
        picture(h, "agent-card")
        rule.onNodeWithText("8 轮 · 共干了 1 小时 12 分").assertIsDisplayed().performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.History(Fixtures.STATION, of, key), h.app.stack.last()) }
        rule.runOnIdle { assertEquals(null, h.app.sheet) }
    }

    @Test
    fun atWorkItSaysWhatItDoesAndCanBeStopped() {
        val h = open(running = true)
        rule.onAllNodesWithText(name)[0].performClick()
        h.settle()
        rule.onNodeWithText("进行中", substring = true).assertIsDisplayed()
        rule.onAllNodesWithText("编辑 AgentSheet.kt")[0].assertIsDisplayed()
        picture(h, "agent-card-working")
        rule.onNodeWithText("停止").assertIsDisplayed().performClick()
        h.settle()
        assertTrue(h.fake.calls.any { it.first == "session.stop" })
    }

    /** What is worth a look is coloured (a context filling up, an allowance running out, the disk), in the dark too. */
    @Test
    fun whatIsWorthALookInTheDark() {
        val h = open(running = false, dark = true, left = 8, context = 86.0, notes = listOf(AgentCardNote("磁盘只剩 4.1 GB", "amber")))
        rule.onAllNodesWithText(name)[0].performClick()
        h.settle()
        rule.onNodeWithText("86%").assertIsDisplayed()
        rule.onNodeWithText("磁盘只剩 4.1 GB").assertIsDisplayed()
        picture(h, "agent-card-dark")
    }

    @Test
    fun theChatsOwnSheetHasItsAgentsAndWhatCanBeDone() {
        val h = open(running = false)
        rule.onNodeWithContentDescription("对话信息").performClick()
        h.settle()
        rule.onNodeWithContentDescription("重命名").assertIsDisplayed()
        rule.onNodeWithText("Alice 3 小时前开始 · 2 人").assertIsDisplayed()
        rule.onNodeWithText("做完了 · 12 分钟前").assertIsDisplayed()
        rule.onNodeWithText("固定到列表顶部").assertIsDisplayed()
        rule.onNodeWithText("归档对话").assertIsDisplayed()
        picture(h, "chat-info")
        // Its agent's row opens the agent's card.
        rule.onNodeWithText("做完了 · 12 分钟前").performClick()
        h.settle()
        rule.onNodeWithText("$4.20").assertIsDisplayed()
        rule.onNodeWithText("归档对话").assertDoesNotExist()
    }

    /** Shared with two of the viewer's other workspaces, read only (views/xshare.ts `shown`). */
    private fun shared(may: Boolean) = ChatShare(
        session = key, text = "设计组、Acme 海外 · 只读", write = false, may = may,
        to = listOf(ChatShareTo("wb", "设计组"), ChatShareTo("wc", "Acme 海外")),
        places = listOf(ChatSharePlace("wb", "设计组", true), ChatSharePlace("wc", "Acme 海外", true), ChatSharePlace("wd", "个人", false)),
    )

    /** Its sharing with other workspaces: a row of the chat's sheet with where it is shared, whose sheet ticks them. */
    @Test
    fun theChatsSharingIsTickedInASheetOfItsOwn() = sharing(dark = false)

    @Test
    fun theChatsSharingInTheDark() = sharing(dark = true)

    private fun sharing(dark: Boolean) {
        val h = open(running = false, dark = dark, xshare = shared(may = true))
        rule.onNodeWithContentDescription("对话信息").performClick()
        h.settle()
        rule.onNodeWithText("设计组、Acme 海外 · 只读").assertIsDisplayed()
        picture(h, if (dark) "chat-info-share-dark" else "chat-info-share")
        rule.onNodeWithText("分享给其他 workspace").performClick()
        h.settle()
        rule.onNodeWithText("所选 workspace 中的 agent 可读取此对话").assertIsDisplayed()
        rule.onNodeWithText("个人").performClick()
        rule.onNodeWithText("可发送消息").performClick()
        h.settle()
        picture(h, if (dark) "share-sheet-dark" else "share-sheet")
        rule.onNodeWithText("完成").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(null, h.app.sheet) }
        val asked = h.fake.calls.last { it.first == "chat.xshare" }.second
        assertEquals(Fixtures.STATION, asked["station"]!!.jsonPrimitive.content)
        assertEquals(key, asked["session"]!!.jsonPrimitive.content)
        assertEquals(listOf("wb", "wc", "wd"), asked["to"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals(true, asked["write"]!!.jsonPrimitive.boolean)
    }

    /** One who may not change it (not its starter, nor an owner or admin) sees where it is shared, and nothing opens. */
    @Test
    fun theChatsSharingIsOnlyShownToWhoMayNotChangeIt() {
        val h = open(running = false, xshare = shared(may = false))
        rule.onNodeWithContentDescription("对话信息").performClick()
        h.settle()
        rule.onNodeWithText("设计组、Acme 海外 · 只读").assertIsDisplayed()
        rule.onNodeWithText("分享给其他 workspace").performClick()
        h.settle()
        rule.onNodeWithText("所选 workspace 中的 agent 可读取此对话").assertDoesNotExist()
        assertTrue(h.fake.calls.none { it.first == "chat.xshare" })
    }

    /** Its history's details open with the same: where it stands and its figures, over how it runs and what it used. */
    @Test
    fun itsHistorysDetailsHeadWithWhereItStandsAndItsFigures() {
        val h = open(running = false, stack = chatPage + Screen.History(Fixtures.STATION, of, key))
        rule.onNodeWithText("详情").performClick()
        h.settle()
        rule.onNodeWithText("做完了 · 12 分钟前").assertIsDisplayed()
        // Its cost large in a tile, and again among what it used.
        rule.onAllNodesWithText("$4.20")[0].assertIsDisplayed()
        rule.onNodeWithText("61%").assertIsDisplayed()
        rule.onNodeWithText("8 轮 · 共干了 1 小时 12 分").assertIsDisplayed()
        rule.onNodeWithText("142 次").assertIsDisplayed()
        picture(h, "history-details")
    }
}
