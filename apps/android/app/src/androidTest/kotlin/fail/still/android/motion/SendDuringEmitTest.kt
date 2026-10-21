// Words sent while an agent's replies come in, out of its avatar (ChatMotion.kt), frame by frame: they wait their turn
// (ListTurns.kt), then fly to their row at the list's end, under the replies, the rows above going from where they are
// then (not where they were as the words were sent).
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
import fail.still.android.data.Live
import fail.still.android.data.Session
import fail.still.android.data.Topics
import kotlinx.serialization.json.JsonNull
import androidx.compose.ui.semantics.SemanticsProperties
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SendDuringEmitTest {
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
    private fun chat(messages: List<ChatMessage>, running: Boolean = true, outbox: List<fail.still.android.data.Outgoing> = emptyList()) =
        Fixtures.chat(messages, outbox).copy(agents = listOf(agentAt(running)))
    private fun later() = System.currentTimeMillis() + 60_000

    /** Where the sent row is in the list (its top, px), and the agent's last reply, in the frame as it is. */
    private fun Harness.tops(text: String, last: String): Pair<Float?, Float?> {
        val field = rule.onAllNodes(hasSetTextAction())[0].fetchSemanticsNode().boundsInRoot
        fun at(t: String) = rule.onAllNodes(hasText(t, substring = true)).fetchSemanticsNodes().map { it.boundsInRoot.top }.firstOrNull { it < field.top }
        return at(text) to at(last)
    }

    private fun run(name: String, sendAt: Int, replies: Int, ackAfter: Int) {
        val h = Harness(rule)
        h.fake.put(Topics.live(Fixtures.STATION, key), Live(loaded = true, timeline = emptyList(), steps = emptyList(), activity = Activity(ActivityNow(key = "read", text = "读取 deploy.yml"))))
        val base = Fixtures.talk
        h.fake.put(topic, chat(base))
        // Words and an outbox id of this test's own: what an earlier test in the same process left is not taken for them.
        val text = "顺便看下 Safari $replies-$ackAfter"
        val out = "out-$name"
        var now = base
        // The core has what is sent in the outbox at once (a quick core: in the frame it is sent).
        h.fake.answer = { n, _ ->
            if (n == "chat.send") h.fake.put(topic, chat(now, outbox = listOf(Fixtures.outgoing(out, text))))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.settle()
        rule.onAllNodes(hasSetTextAction())[0].performClick().performTextReplacement(text)
        h.keyboard()
        val r = h.record(name)
        var seq = 5L
        var sentAt = -1
        val last = "第 $replies 条"
        for (i in 0 until 200) {
            r.frame {
                // The agent's replies, one every 5 frames, said while the chat shows (before the words are sent).
                if (i < replies * 5 && i % 5 == 0) {
                    now = now + Fixtures.agent(seq++, "第 ${i / 5 + 1} 条：登录页的错误提示改好了，接着看注册页", later(), said = true)
                    h.fake.put(topic, chat(now, outbox = if (sentAt >= 0) listOf(Fixtures.outgoing(out, text)) else emptyList()))
                }
                if (i == sendAt) { rule.onNode(hasContentDescription("发送")).performSemanticsAction(SemanticsActions.OnClick); sentAt = i }
                if (sentAt >= 0 && i == sentAt + ackAfter) {
                    now = now + Fixtures.mine(seq++, text, later(), said = true).copy(outgoing = out)
                    h.fake.put(topic, chat(now))
                }
            }
            // Said after the replies, the words wait their turn: their row comes once the last is out, under it (not in
            // first, the replies coming out above it after).
            val (sent, reply) = h.tops(text, last)
            if (sent != null) assertTrue("$name f$i: sent row at $sent, the last reply at $reply", reply != null && reply < sent)
        }
        // A few seconds on: in view above the composer (not given up on, out of sight), the field empty.
        val (sent, _) = h.tops(text, last)
        assertTrue("$name: the sent row is not in view", sent != null && sent > 0f)
        val field = rule.onAllNodes(hasSetTextAction())[0].fetchSemanticsNode()
        assertEquals("", field.config.getOrElseNullable(SemanticsProperties.EditableText) { null }?.text)
        r.end()
    }

    /** One reply coming out, the words sent as it does; the station has them 10 frames on. */
    @Test fun sentAsOneComesOut() = run("send-during-one", sendAt = 14, replies = 1, ackAfter = 10)

    /** Three replies one after another, the words sent as they come out. */
    @Test fun sentAsThreeComeOut() = run("send-during-three", sendAt = 14, replies = 3, ackAfter = 10)

    /** The station has them at once (a quick link). */
    @Test fun sentAsOneComesOutQuick() = run("send-during-one-quick", sendAt = 14, replies = 1, ackAfter = 1)
}
