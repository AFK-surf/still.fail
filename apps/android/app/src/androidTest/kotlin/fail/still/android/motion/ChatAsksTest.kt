// What waits to be decided in a chat, said over the composer's field (Composer.kt AsksNotice): all of what is wanted
// shows, and tapped, the list goes to the post that asks.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
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
    private val want = "这周要不要把 React Router 一起升到 8？它改了 loader 的写法，要动 14 个路由文件，多半天；不升的话这周先合其余 23 个包，下周单独升。"

    private fun open(h: Harness, ask: ChatAsk) {
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(long).copy(asks = listOf(ask)))
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
    }

    @Test
    fun aNeedTappedShowsThePostThatAsks() {
        val h = Harness(rule)
        open(h, ChatAsk(seq = 2u, card = false, mine = true, text = want))
        rule.onNodeWithText("第 2 条", substring = true).assertDoesNotExist()
        // All of it, to its last words.
        val notice = rule.onNodeWithText("下周单独升。", substring = true).assertIsDisplayed()
        val jump = h.record("asks-need")
        jump.frame { notice.performClick() }
        jump.frames(20)
        jump.end()
        rule.onNodeWithText("第 2 条", substring = true).assertIsDisplayed()
    }

    @Test
    fun aCardOutOfViewTappedShowsItsPost() {
        val h = Harness(rule)
        open(h, ChatAsk(seq = 4u, card = true, mine = true, text = want))
        rule.onNodeWithText("第 4 条", substring = true).assertDoesNotExist()
        val notice = rule.onNodeWithText("下周单独升。", substring = true).assertIsDisplayed()
        val jump = h.record("asks-card")
        jump.frame { notice.performClick() }
        jump.frames(20)
        jump.end()
        rule.onNodeWithText("第 4 条", substring = true).assertIsDisplayed()
        // Its post in view, nothing more is said of it over the field.
        rule.onNodeWithText("下周单独升。", substring = true).assertDoesNotExist()
    }
}
