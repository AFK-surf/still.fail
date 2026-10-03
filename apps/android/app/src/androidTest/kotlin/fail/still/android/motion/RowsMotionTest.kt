// A chat's rows and its scrolling, frame by frame (Harness.kt): an agent's reply coming out of its activity's avatar, the
// list gliding after what comes in, the jump to the latest, and a quoted message flashing.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import fail.still.android.Screen
import fail.still.android.data.Activity
import fail.still.android.data.ActivityNow
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.Live
import fail.still.android.data.Quote
import fail.still.android.data.Session
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class RowsMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val key = "ember:c-1"

    private val key2 = "ember:c-2"
    private val openai = fail.still.android.data.Maker("openai", "OpenAI")

    private fun session(k: String = key) = Session(
        key = k, runtime = if (k == key) "claude" else "codex", process = "running", pending = 0, statusText = "工作中", tone = "accent", titleText = "修一下登录",
        agentText = if (k == key) "Claude" else "Codex", maker = if (k == key) Fixtures.anthropic else openai, runtimeText = if (k == key) "Claude Code" else "Codex", efforts = listOf("high"),
    )

    /** `started`: seen starting while the chat shows, as the core marks it (attend.ts): its activity comes in. */
    private fun agentAt(running: Boolean, started: Boolean = running, k: String = key) = ChatAgent(
        session = session(k), status = if (running) "running" else "idle", profiles = emptyList(), choices = emptyList(), attention = emptyList(),
        since = if (running) System.currentTimeMillis() - 42_000 else null, started = if (started) true else null, turns = emptyList(), threads = emptyList(), jobs = emptyList(),
    )

    private fun live(now: String) = Live(loaded = true, timeline = emptyList(), steps = emptyList(), activity = Activity(ActivityNow(key = now, text = now)))

    private fun chat(messages: List<ChatMessage>, running: Boolean, started: Boolean = running) = Fixtures.chat(messages).copy(agents = listOf(agentAt(running, started)))

    /** The chat opened with its agent idle (a working one never lets the clock come to rest: its ring turns). */
    private fun open(messages: List<ChatMessage>): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), live("运行测试"))
        h.fake.put(topic, chat(messages, running = false))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        return h
    }

    /** Said after the chat opened (else it would be unread, under the unread line). */
    private fun later() = System.currentTimeMillis() + 60_000

    private val asked = Fixtures.talk + Fixtures.mine(5, "再跑一遍测试，看看都过了没有")

    /** The agent posts its reply while its activity shows: the reply comes out of the avatar; then its turn ends. */
    @Test
    fun replyComesOutOfTheAvatar() {
        val h = open(asked)
        val r = h.record("emit-one")
        h.fake.put(topic, chat(asked, running = true))
        h.deliver()
        r.frames(30)
        val reply = asked + Fixtures.agent(6, "都过了：42 个通过，0 个失败。登录页的三个用例也在里面。", later(), said = true)
        h.fake.put(topic, chat(reply, running = true))
        h.deliver()
        r.frames(80)
        h.fake.put(topic, chat(reply, running = false))
        h.deliver()
        r.frames(60)
        r.end()
    }

    /** Something said above the activity while it shows: the activity glides down to its new place, not there at once. */
    @Test
    fun activityPushedDown() {
        val h = open(asked)
        val r = h.record("activity-pushed")
        h.fake.put(topic, chat(asked, running = true))
        h.deliver()
        r.frames(30)
        h.fake.put(topic, chat(asked + Fixtures.mine(6, "顺便看一下 Safari 上那个按钮", later(), said = true), running = true))
        h.deliver()
        r.frames(50)
        h.fake.put(topic, chat(asked + Fixtures.mine(6, "顺便看一下 Safari 上那个按钮", later(), said = true), running = false))
        h.deliver()
        r.frames(40)
        r.end()
    }

    /** The second agent's reply: as Fixtures.agent, by Codex. */
    private fun codex(seq: Long, text: String) = Fixtures.agent(seq, text, later(), said = true).copy(
        author = key2, authorName = "Codex", by = fail.still.android.data.MessageBy("Codex", agent = key2, maker = openai, runtime = "codex"),
    )

    private fun two(messages: List<ChatMessage>, running: Boolean) =
        Fixtures.chat(messages).copy(agents = listOf(agentAt(running), agentAt(running, k = key2)))

    /** Replies one after another while the first is still coming out: each waits its turn, the avatar going straight on. */
    @Test
    fun repliesKeepComing() {
        val h = open(asked)
        val r = h.record("emit-stream")
        h.fake.put(topic, chat(asked, running = true))
        h.deliver()
        r.frames(30)
        var said = asked
        for ((i, text) in listOf("先说结果：都过了。", "42 个通过，0 个失败。", "登录页的三个用例也在里面，Safari 那个现在是绿的。").withIndex()) {
            said = said + Fixtures.agent(6L + i, text, later(), said = true)
            h.fake.put(topic, chat(said, running = true))
            h.deliver()
            r.frames(14)
        }
        r.frames(120)
        h.fake.put(topic, chat(said, running = false))
        h.deliver()
        r.frames(60)
        r.end()
    }

    /** Two agents at work, their replies interleaved: each comes out of its own avatar, one at a time. */
    @Test
    fun twoAgentsInterleaved() {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), live("运行测试"))
        h.fake.put(Topics.live(Fixtures.STATION, key2), live("读取 login.css"))
        h.fake.put(topic, two(asked, running = false))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        val r = h.record("emit-two-agents")
        h.fake.put(topic, two(asked, running = true))
        h.deliver()
        r.frames(30)
        var said = asked
        for (m in listOf(
            Fixtures.agent(6, "测试都过了：42 个通过。", later(), said = true),
            codex(7, "样式我看了：按钮在 375px 下溢出了 12px。"),
            Fixtures.agent(8, "Safari 那个用例现在也是绿的。", later(), said = true),
            codex(9, "改成了 width: 100%，截图核对过。"),
        )) {
            said = said + m
            h.fake.put(topic, two(said, running = true))
            h.deliver()
            r.frames(12)
        }
        r.frames(160)
        h.fake.put(topic, two(said, running = false))
        h.deliver()
        r.frames(60)
        r.end()
    }

    /** Two agents at work, one done first: its activity stays a moment, fades, and the other glides up into its place. */
    @Test
    fun oneAgentStopsFirst() {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), live("运行测试"))
        h.fake.put(Topics.live(Fixtures.STATION, key2), live("读取 login.css"))
        h.fake.put(topic, two(asked, running = false))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        val r = h.record("one-stops-first")
        h.fake.put(topic, two(asked, running = true))
        h.deliver()
        r.frames(30)
        h.fake.put(topic, Fixtures.chat(asked).copy(agents = listOf(agentAt(false), agentAt(true, k = key2))))
        h.deliver()
        r.frames(90)
        h.fake.put(topic, two(asked, running = false))
        h.deliver()
        r.frames(80)
        r.end()
    }

    /** Two replies at once: one after the other, the second straight from where the first left the avatar. */
    @Test
    fun twoRepliesOneAfterTheOther() {
        val h = open(asked)
        val r = h.record("emit-two")
        h.fake.put(topic, chat(asked, running = true))
        h.deliver()
        r.frames(30)
        val replies = asked + Fixtures.agent(6, "先说结果：都过了。", later(), said = true) + Fixtures.agent(7, "42 个通过，0 个失败；登录页的三个用例也在里面，Safari 那个现在是绿的。", later(), said = true)
        h.fake.put(topic, chat(replies, running = true))
        h.deliver()
        r.frames(150)
        h.fake.put(topic, chat(replies, running = false))
        h.deliver()
        r.frames(60)
        r.end()
    }

    /**
     * Opened from what the device kept while its agent is at work (at work already: not started while it shows), then
     * caught up on from the station: what was read is there at once (nothing comes out of the avatar, nothing rises in),
     * as the core marks it (no `said`). Opened idle first: a working agent's ring never lets the clock come to rest.
     */
    @Test
    fun caughtUpShowsAtOnce() {
        val h = open(asked)
        val r = h.record("caught-up")
        h.fake.put(topic, chat(asked, running = true, started = false))
        h.deliver()
        r.frames(10)
        val read = asked + Fixtures.agent(6, "先说结果：都过了。") + Fixtures.agent(7, "42 个通过，0 个失败；登录页的三个用例也在里面。")
        h.fake.put(topic, chat(read, running = true, started = false))
        h.deliver()
        r.frames(90)
        h.fake.put(topic, chat(read, running = false))
        h.deliver()
        r.frames(30)
        r.end()
    }

    private val long = (1L..24L).map { n ->
        if (n % 2 == 1L) Fixtures.mine(n, "第 $n 条：登录页在 Safari 上点了没反应，帮我看一下这一段为什么会这样")
        else Fixtures.agent(n, "第 $n 条：按钮的 `onClick` 在表单提交之前被 `preventDefault` 吞掉了。我把它改成在 `onSubmit` 里处理，Safari 和 Chrome 都试过了。")
    }

    /** A message arriving at the end while it is followed: the list glides after it (scroll.ts, 1 - e^(-dt/100ms)). */
    @Test
    fun followGlides() {
        val h = open(long)
        val r = h.record("follow-glide")
        r.frames(4)
        h.fake.put(topic, chat(long + Fixtures.agent(25, "改好了：密码错误、账号不存在、网络断开三种情况都有中文提示，另外把按钮的加载状态也补上了，点了以后会转圈，直到服务器回复。", later(), said = true), running = false))
        h.deliver()
        r.frames(40)
        probe("follow-glide last")
        r.end()
        probe("follow-glide settled")
    }

    /** Where some rows are, to the fraction of a pixel (logged, tag motion-probe). */
    private fun probe(label: String) {
        val tops = listOf("改好了", "第 24 条", "第 20 条", "发消息").map { t ->
            runCatching { rule.onAllNodesWithText(t, substring = true).fetchSemanticsNodes().joinToString("/") { n -> "%.2f+%d".format(n.positionInRoot.y, n.size.height) } }.getOrDefault("-")
        }
        android.util.Log.i("motion-probe", "$label ${tops.joinToString(" ")}")
    }

    /** Scrolled up, the button comes up; tapped, the list glides to the newest and the button goes. */
    @Test
    fun jumpToLatest() {
        val h = open(long)
        val show = h.record("jump-button-show")
        show.frame { rule.onRoot().performTouchInput { swipeDown(startY = height * 0.35f, endY = height * 0.75f, durationMillis = 200) } }
        // Until the fling the swipe leaves has come to rest (the list's own decay, about 2s here).
        show.frames(150)
        probe("jump-button-show last")
        show.end()
        probe("jump-button-show settled")
        val r = h.record("jump-latest")
        r.frame { rule.onNodeWithContentDescription("跳到最新").performClick() }
        r.frames(50)
        probe("jump-latest last")
        r.end()
        probe("jump-latest settled")
    }

    private fun quoteJump(name: String, quote: Quote, frames: Int = 170) {
        val quoting = Fixtures.mine(26, "这个还会出现吗", later(), said = true).copy(quotes = listOf(quote))
        val h = open(long + quoting)
        val r = h.record(name)
        r.frames(2)
        r.frame { rule.onAllNodesWithText("这个还会出现吗", substring = true).fetchSemanticsNodes(); rule.onAllNodesWithText(quote.text.take(6), substring = true).let { it[it.fetchSemanticsNodes().size - 1].performClick() } }
        r.frames(frames)
        r.end()
    }

    /** A quote of part of your words: that passage is marked in the bubble, 28% then 12%, gone at 2600ms (web Chrome). */
    @Test
    fun quotePassageInABubble() = quoteJump("quote-passage-mine", Quote(author = "你", text = "登录页在 Safari 上点了没反应", comment = "", ts = "t3", role = "person"))

    /** A quote of part of an agent's Markdown: marked in its paragraph, the code's marks gone as a quote takes them. */
    @Test
    fun quotePassageInMarkdown() = quoteJump("quote-passage-agent", Quote(author = "Claude", text = "preventDefault 吞掉了。我把它改成在 onSubmit 里处理", comment = "", ts = "t4", role = "agent"))

    /** A quote its message's words do not hold (edited since, or across paragraphs): the whole message flashes (msgFlash). */
    @Test
    fun quoteFlashesWhole() = quoteJump("quote-flash-whole", Quote(author = "你", text = "早就改掉的一句话", comment = "", ts = "t3", role = "person"), 100)
}
