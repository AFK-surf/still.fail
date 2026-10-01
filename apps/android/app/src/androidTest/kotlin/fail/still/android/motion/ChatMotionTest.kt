// A chat's motions, frame by frame (Harness.kt): what is sent, from the composer into the list; the station taking it;
// a new chat becoming its chat; the composer changing shape.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Topics
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Rule
import org.junit.Test

class ChatMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val talk = Fixtures.talk

    private fun Harness.type(text: String) = rule.onAllNodes(hasSetTextAction())[0].performTextReplacement(text)

    // Its click action, not a touch: no input injected (which fails while the window is busy, e.g. an IME coming up).
    private fun Harness.send() = rule.onNode(hasContentDescription("发送")).performSemanticsAction(SemanticsActions.OnClick)

    /** A message in the outbox that the station takes (its seq), then shows as the chat's: the row stays the same one. */
    @Test
    fun outboxBecomesTheMessage() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        val text = "那顺便加一个单元测试"
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text))))
        h.settle()
        val r = h.record("outbox-to-message")
        r.frames(4)
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text, seq = 5))))
        h.deliver()
        r.frames(4)
        h.fake.put(topic, Fixtures.chat(talk + Fixtures.mine(5, text, said = true)))
        h.deliver()
        r.frames(24)
        r.end()
    }

    /** Sent in a chat: the words go from the composer to their place at the end of the list; the station takes them mid-way. */
    @Test
    fun sentInAChat() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        val text = "那顺便加一个单元测试，覆盖 Safari 和 Chrome 两种情况"
        h.fake.answer = { name, _ ->
            // The core puts what is sent in the chat's outbox at once, and answers once the station has it.
            if (name == "chat.send") h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text))))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.type(text)
        h.keyboard()
        val r = h.record("sent-in-chat")
        r.frame { h.send() }
        r.frames(14)
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text, seq = 5))))
        r.frames(2)
        h.fake.put(topic, Fixtures.chat(talk + Fixtures.mine(5, text, said = true)))
        r.frames(40)
        r.end()
    }

    /** Sent in a chat, written over several lines (one wrapping): each line from where it was typed to its place in the bubble. */
    @Test
    fun sentManyLines() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        val text = "还有几件事：\n1. 登录页在 Safari 上点了没反应，Chrome 上是好的，可能是 cookie 的 SameSite 设置\n2. 顺便加一个单元测试\n3. 改完发截图"
        h.fake.answer = { name, _ ->
            if (name == "chat.send") h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text))))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.type(text)
        h.keyboard()
        val r = h.record("sent-many-lines")
        r.frame { h.send() }
        r.frames(14)
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text, seq = 5))))
        r.frames(2)
        h.fake.put(topic, Fixtures.chat(talk + Fixtures.mine(5, text, said = true)))
        r.frames(40)
        r.end()
    }

    /** Sent in a chat over several lines, the outbox a few frames behind (as on a device): the words wait in the field as typed. */
    @Test
    fun sentManyLinesOutboxLate() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        val text = "还有几件事：\n1. 登录页在 Safari 上点了没反应，Chrome 上是好的，可能是 cookie 的 SameSite 设置\n2. 顺便加一个单元测试\n3. 改完发截图"
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.type(text)
        h.keyboard()
        val r = h.record("sent-many-lines-late")
        r.frame { h.send() }
        r.frames(6)
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text))))
        r.frames(14)
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text, seq = 5))))
        r.frames(2)
        h.fake.put(topic, Fixtures.chat(talk + Fixtures.mine(5, text, said = true)))
        r.frames(40)
        r.end()
    }

    /** Sent in a chat, more than the field shows (it scrolled), its long lines breaking elsewhere in the bubble. */
    @Test
    fun sentPastTheField() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        val text = "这次改动要注意的几件事情我先列一下，大家看看有没有漏掉的地方，然后我们再决定先做哪一件比较好\n" +
            "1. 登录页\n2. 注册页\n3. 忘记密码的邮件模板也要跟着一起改掉，不然用户收到的还是旧的文案\n4. 单元测试\n5. 截图\n6. 发版说明"
        h.fake.answer = { name, _ ->
            if (name == "chat.send") h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text))))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.type(text)
        h.keyboard()
        val r = h.record("sent-past-the-field")
        r.frame { h.send() }
        r.frames(14)
        h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", text, seq = 5))))
        r.frames(2)
        h.fake.put(topic, Fixtures.chat(talk + Fixtures.mine(5, text, said = true)))
        r.frames(40)
        r.end()
    }

    /** Sent to a quick station: the list never shows the outbox's row, only the chat's message; the words go to that. */
    @Test
    fun sentToAQuickStation() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        val text = "那顺便加一个单元测试"
        h.fake.answer = { name, _ ->
            if (name == "chat.send") h.fake.put(topic, Fixtures.chat(talk + Fixtures.mine(5, text, said = true)))
            JsonNull
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.type(text)
        h.keyboard()
        val r = h.record("sent-quick-station")
        r.frame { h.send() }
        r.frames(40)
        r.end()
    }

    /** A new chat's first message: the scene leaves, the words go up into the chat it made, the composer stays. */
    @Test
    fun newChatBecomesItsChat() {
        val h = Harness(rule)
        val text = "帮我看看登录页为什么在 Safari 上点了没反应"
        val made = Topics.chat(Fixtures.STATION, ChatOf.Session("new:1"))
        h.fake.answer = { name, _ ->
            when (name) {
                "chat.create" -> buildJsonObject { put("key", "new:1") }
                "chat.send" -> { h.fake.put(made, Fixtures.chat(emptyList(), listOf(Fixtures.outgoing("out-1", text)), thread = null, title = text)); JsonNull }
                else -> JsonNull
            }
        }
        h.launch(listOf(Screen.Home, Screen.NewChat))
        h.type(text)
        h.keyboard()
        val r = h.record("new-chat")
        r.frame { h.send() }
        r.frames(16)
        // Its station makes it and takes the message, which becomes the chat's first.
        h.fake.put(made, Fixtures.chat(emptyList(), listOf(Fixtures.outgoing("out-1", text, seq = 1)), title = text))
        r.frames(2)
        h.fake.put(made, Fixtures.chat(listOf(Fixtures.mine(1, text, said = true)), title = text))
        r.frames(30)
        r.end()
    }

    /** The composer growing by lines as it is written in, and back: its height, corners and parts in one motion. */
    @Test
    fun composerChangesShape() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        // The keyboard up first (it comes up on the system's clock, not the test's).
        h.type("第一行")
        h.keyboard()
        val r = h.record("composer-grows")
        r.frame { h.type("第一行\n第二行\n第三行") }
        r.frames(20)
        r.end()
        val back = h.record("composer-shrinks")
        back.frame { h.type("") }
        back.frames(20)
        back.end()
    }
}
