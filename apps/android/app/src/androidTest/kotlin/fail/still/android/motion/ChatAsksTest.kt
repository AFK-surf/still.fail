// What waits to be decided in a chat whose post does not show: a bell over the list (Chat.kt JumpToAsk), no words;
// tapped, the list goes to the post that asks. With the post in view there is none.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.ChatAsk
import fail.still.android.data.ChatOf
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class ChatAsksTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val long = (1L..24L).map { s ->
        if (s % 2 == 1L) Fixtures.mine(s, "第 $s 条：这里要再看一下")
        else Fixtures.agent(s, "第 $s 条：" + "改好了，测试都过了。".repeat(if (s == 12L) 4 else 2))
    }
    private val want = "这周要不要把 React Router 一起升到 8？"
    private val bell = "跳到待决策的消息"
    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))

    private fun open(h: Harness, ask: ChatAsk) {
        h.fake.put(topic, Fixtures.chat(long).copy(asks = listOf(ask)))
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
    }

    @Test
    fun aNeedTappedShowsThePostThatAsks() {
        val h = Harness(rule)
        open(h, ChatAsk(seq = 2u, card = false, mine = true, text = want))
        rule.onNodeWithText("第 2 条", substring = true).assertDoesNotExist()
        // No words of it anywhere but its post.
        rule.onNodeWithText("React Router", substring = true).assertDoesNotExist()
        val button = rule.onNodeWithContentDescription(bell).assertIsDisplayed()
        val jump = h.record("asks-need")
        jump.frame { button.performClick() }
        jump.frames(20)
        jump.end()
        rule.onNodeWithText("第 2 条", substring = true).assertIsDisplayed()
        // Its post in view, the bell is gone.
        rule.onNodeWithContentDescription(bell).assertDoesNotExist()
    }

    @Test
    fun aCardOutOfViewTappedShowsItsPost() {
        val h = Harness(rule)
        open(h, ChatAsk(seq = 4u, card = true, mine = true, text = want))
        rule.onNodeWithText("第 4 条", substring = true).assertDoesNotExist()
        rule.onNodeWithContentDescription(bell).assertIsDisplayed().performClick()
        h.settle()
        rule.onNodeWithText("第 4 条", substring = true).assertIsDisplayed()
        rule.onNodeWithContentDescription(bell).assertDoesNotExist()
    }

    /** Its post before the pages loaded: they are brought in, then it shows. */
    @Test
    fun aPostNotLoadedIsBroughtIn() {
        val h = Harness(rule)
        val ask = ChatAsk(seq = 2u, card = true, mine = true, text = want)
        h.fake.answer = { name, _ ->
            if (name == "chat.older") h.fake.put(topic, Fixtures.chat(long).copy(asks = listOf(ask)))
            kotlinx.serialization.json.JsonNull
        }
        h.fake.put(topic, Fixtures.chat(long.drop(12)).copy(asks = listOf(ask), more = true))
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        rule.onNodeWithContentDescription(bell).assertIsDisplayed().performClick()
        h.settle()
        h.settle()
        rule.onNodeWithText("第 2 条", substring = true).assertIsDisplayed()
    }

    /** Its post already in view (the chat's last): nothing leads to it. */
    @Test
    fun noBellWhileThePostShows() {
        val h = Harness(rule)
        open(h, ChatAsk(seq = 24u, card = false, mine = true, text = want))
        rule.onNodeWithText("第 24 条", substring = true).assertIsDisplayed()
        rule.onNodeWithContentDescription(bell).assertDoesNotExist()
    }

    /** The post that asks has 忽略 under it: tapped, the decision is let go (`decision.dismiss`) and the word is gone. */
    @Test
    fun thePostThatAsksLetsItGo() {
        val h = Harness(rule)
        val asking = long.map { if (it.seq == 24L) it.copy(asked = true) else it }
        h.fake.put(topic, Fixtures.chat(asking).copy(asks = listOf(ChatAsk(seq = 24u, card = false, mine = true, text = want))))
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        val dismiss = rule.onNodeWithText("忽略").assertIsDisplayed()
        val shot = h.record("asks-dismiss")
        shot.frame()
        shot.end()
        dismiss.performClick()
        h.settle()
        rule.onNodeWithText("忽略").assertDoesNotExist()
        org.junit.Assert.assertTrue(h.fake.calls.any { it.first == "decision.dismiss" })
    }
}
