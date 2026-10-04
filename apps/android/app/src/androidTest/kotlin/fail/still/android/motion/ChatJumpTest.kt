// A chat opened at a message (a row's state line: what it is about): it shows at the top, as the unread line puts one,
// and flashes.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class ChatJumpTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val long = (1L..24L).map { s ->
        if (s % 2 == 1L) Fixtures.mine(s, "第 $s 条：这里要再看一下")
        else Fixtures.agent(s, "第 $s 条：" + "改好了，测试都过了。".repeat(if (s == 12L) 4 else 2))
    }

    @Test
    fun opensAtTheMessage() {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(long))
        h.launch(listOf(Screen.Home))
        val open = h.record("chat-jump")
        open.frame { rule.runOnUiThread { h.app.push(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD), at = 12)) } }
        open.frames(90)
        open.end()
    }
}
