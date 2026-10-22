// What other chats' agents wrote to a chat (the core's `letters`): a run of it is one pill across the chat (Chat.kt
// LettersLine), its messages out of the list; tapped, the core is asked to show it whole (`chat.letters`) and the
// messages come in under the pill; tapped again, folded.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.Letters
import fail.still.android.data.MessageBy
import fail.still.android.data.Topics
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ChatLettersTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val from = MessageBy("BFT 备份尺寸分析", from = "https://app.still.fail/o/w/s/ember%3Ac-4dbf0d0c6e", maker = Fixtures.anthropic)
    private fun letter(seq: Long, text: String) = Fixtures.agent(seq, text).copy(author = "peer/ember:c-9", authorName = null, by = from)
    private val run = listOf(
        letter(2, "用户让精简备份并改用 zstd。改好的两个脚本放在 `~/bft/backup/`，麻烦替换一下"),
        letter(3, "补充一点：macOS 自带的 tar 能直接解 zstd"),
        letter(4, "已替换，今晚 02:00 那份会按新脚本出"),
    )
    private fun messages(open: Boolean): List<ChatMessage> {
        val line = Letters(count = 3, line = "「BFT 备份尺寸分析」发来 3 条消息", last = "已替换，今晚 02:00 那份会按新脚本出", open = open)
        val shown = listOf(run[0].copy(letters = line)) + if (open) run.drop(1) else emptyList()
        return listOf(Fixtures.mine(1, "备份改成 zstd，顺便看看每份为什么这么大")) + shown + Fixtures.agent(5, "备份改好了：每份从 650 MiB 降到 180 MiB")
    }

    @Test
    fun aRunIsOnePillTappedOpenAndFoldedAgain() {
        val h = Harness(rule)
        h.fake.answer = { name, params ->
            if (name == "chat.letters") h.fake.put(topic, Fixtures.chat(messages(params.jsonObject["open"]!!.jsonPrimitive.boolean)))
            kotlinx.serialization.json.JsonNull
        }
        h.fake.put(topic, Fixtures.chat(messages(false)))
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        val pill = rule.onNodeWithText("「BFT 备份尺寸分析」发来 3 条消息").assertIsDisplayed()
        rule.onNodeWithText("补充一点", substring = true).assertDoesNotExist()
        val opening = h.record("letters-open")
        opening.frame { pill.performClick() }
        opening.frames(12)
        opening.end()
        assertTrue(h.fake.calls.any { it.first == "chat.letters" })
        rule.onNodeWithText("补充一点", substring = true).assertIsDisplayed()
        rule.onNodeWithText("「BFT 备份尺寸分析」发来 3 条消息").performClick()
        h.settle()
        rule.onNodeWithText("补充一点", substring = true).assertDoesNotExist()
        val folded = h.record("letters-folded")
        folded.end()
    }
}
