// What changes the height of a chat's list plays one at a time (screens/ListTurns.kt), frame by frame (Harness.kt): a
// decision waits at the end, the reader answers it by writing; their words fly in, the options close, the agent's line
// comes, its reply comes out of its avatar. Or they pick an option: the options close, their answer comes, then the line.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import fail.still.android.Screen
import fail.still.android.data.Activity
import fail.still.android.data.ActivityNow
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionOption
import fail.still.android.data.Live
import fail.still.android.data.MessageCard
import fail.still.android.data.MessageDecision
import fail.still.android.data.Session
import fail.still.android.data.Topics
import kotlinx.serialization.json.JsonNull
import org.junit.Rule
import org.junit.Test

class TurnsMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val key = "ember:c-1"

    private val session = Session(
        key = key, runtime = "claude", process = "running", pending = 0, statusText = "工作中", tone = "accent", titleText = "修一下登录",
        agentText = "Claude", maker = Fixtures.anthropic, runtimeText = "Claude Code", efforts = listOf("high"),
    )
    private fun agentAt(running: Boolean) = ChatAgent(
        session = session, status = if (running) "running" else "idle", profiles = emptyList(), choices = emptyList(), attention = emptyList(),
        since = if (running) System.currentTimeMillis() - 2_000 else null, started = if (running) true else null, turns = emptyList(), threads = emptyList(), jobs = emptyList(),
    )
    private fun chat(messages: List<ChatMessage>, running: Boolean, outbox: List<fail.still.android.data.Outgoing> = emptyList()) =
        Fixtures.chat(messages, outbox).copy(agents = listOf(agentAt(running)))

    /** Said after the chat opened (else it would be unread, under the unread line). */
    private fun later() = System.currentTimeMillis() + 60_000

    private val options = listOf(
        DecisionOption("直接替换", "几分钟完成，会中断一下"),
        DecisionOption("先不部署", "等下周再说"),
        DecisionOption("并行切换", "慢一点，不中断", recommended = true),
    )
    private fun card(resolved: Boolean, chosen: String? = null) = Fixtures.agent(5, "部署有两种做法：直接替换，几分钟完成但会中断一下；新旧并行再切流量，慢一点但不中断。你选哪个？").copy(
        card = MessageCard(type = "options", options = options, assigneeText = "待你决策"), options = options,
        decision = MessageDecision(resolved = resolved, answeredBy = if (resolved) "Alice" else null, chosen = chosen,
            text = if (!resolved) null else if (chosen != null) "Alice 选了「$chosen」" else "Alice 回复了"),
        asked = if (resolved) null else true,
    )

    @Test
    fun answeredByWriting() {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), Live(loaded = true, timeline = emptyList(), steps = emptyList(), activity = Activity(ActivityNow(key = "read", text = "读取 deploy.yml"))))
        val asking = Fixtures.talk + card(resolved = false)
        h.fake.put(topic, chat(asking, running = false))
        val text = "就并行吧，切之前先跟我说一声"
        h.fake.answer = { name, _ ->
            if (name == "chat.send") h.fake.put(topic, chat(asking, running = false, outbox = listOf(Fixtures.outgoing("out-1", text))))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.settle()
        rule.onAllNodes(hasSetTextAction())[0].performClick().performTextReplacement(text)
        h.keyboard()
        val r = h.record("answered-by-writing")
        r.frame { rule.onNode(hasContentDescription("发送")).performSemanticsAction(SemanticsActions.OnClick) }
        r.frames(8)
        // The station has it: the decision answered by it, the agent starting on it, at once.
        val answered = Fixtures.talk + card(resolved = true) + Fixtures.mine(6, text, later(), said = true)
        h.fake.put(topic, chat(answered, running = true))
        h.deliver()
        r.frames(110)
        // Its reply, and its turn's end.
        val replied = answered + Fixtures.agent(7, "好，切流量前我会先在这里说一声。", later(), said = true)
        h.fake.put(topic, chat(replied, running = true))
        h.deliver()
        r.frames(6)
        h.fake.put(topic, chat(replied, running = false))
        h.deliver()
        r.frames(110)
        r.end()
    }

    @Test
    fun answeredByPicking() {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), Live(loaded = true, timeline = emptyList(), steps = emptyList(), activity = Activity(ActivityNow(key = "read", text = "读取 deploy.yml"))))
        val asking = Fixtures.talk + card(resolved = false)
        h.fake.put(topic, chat(asking, running = false))
        val text = "并行切换"
        // The core sends the option picked (decisions.ts answer): it waits in the outbox, the decision answered by it.
        h.fake.answer = { name, _ ->
            if (name == "decision.answer") h.fake.put(topic, chat(Fixtures.talk + card(resolved = true, chosen = text), running = false, outbox = listOf(Fixtures.outgoing("out-2", text))))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.settle()
        val r = h.record("answered-by-picking")
        r.frame { rule.onNode(hasText(text)).performSemanticsAction(SemanticsActions.OnClick) }
        h.deliver()
        r.frames(20)
        // The station has it, the agent starting on it.
        val answered = Fixtures.talk + card(resolved = true, chosen = text) + Fixtures.mine(6, text, later(), said = true).copy(outgoing = "out-2")
        h.fake.put(topic, chat(answered, running = true))
        h.deliver()
        r.frames(110)
        val replied = answered + Fixtures.agent(7, "好，按并行切换来，切流量前我会先说一声。", later(), said = true)
        h.fake.put(topic, chat(replied, running = true))
        h.deliver()
        r.frames(6)
        h.fake.put(topic, chat(replied, running = false))
        h.deliver()
        r.frames(110)
        r.end()
    }
}
