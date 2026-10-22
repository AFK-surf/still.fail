// What a chat's agents and other chats' wrote each other (the core's `chatLetters`): not in the chat at all; its bar
// has a button for them (the chat's `letters`), which opens them in a sheet, by the other chat, both ways (Letters.kt).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.ChatLettersView
import fail.still.android.data.ChatOf
import fail.still.android.data.LettersChat
import fail.still.android.data.MessageBy
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class ChatLettersTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val link = "https://app.still.fail/o/w/s/ember%3Ac-4dbf0d0c6e"
    private val theirs = MessageBy("「BFT 备份尺寸分析」的 agent", from = link, maker = Fixtures.anthropic)
    private fun coming(seq: Long, text: String) = Fixtures.agent(seq, text).copy(author = "peer/ember:c-9", authorName = null, by = theirs, way = "in")
    private fun going(seq: Long, text: String) = Fixtures.agent(seq, text).copy(way = "out")
    private val letters = ChatLettersView(
        title = "修一下登录",
        chats = listOf(LettersChat(title = "BFT 备份尺寸分析", link = link, letters = listOf(
            coming(2, "用户让精简备份并改用 zstd。改好的两个脚本放在 `~/bft/backup/`，麻烦替换一下"),
            going(3, "已替换，今晚 02:00 那份会按新脚本出"),
            coming(4, "补充一点：macOS 自带的 tar 能直接解 zstd"),
        ))),
        whole = true,
    )

    @Test
    fun theyAreNotInTheChatButInTheirSheet() {
        val h = Harness(rule)
        val messages = listOf(Fixtures.mine(1, "备份改成 zstd，顺便看看每份为什么这么大"), Fixtures.agent(5, "备份改好了：每份从 650 MiB 降到 180 MiB"))
        h.fake.put(topic, Fixtures.chat(messages).copy(letters = 3L))
        h.fake.put(Topics.chatLetters(Fixtures.STATION, Fixtures.THREAD), letters)
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        rule.onNodeWithText("补充一点", substring = true).assertDoesNotExist()
        val chat = h.record("letters-chat")
        chat.end()
        val opening = h.record("letters-open")
        opening.frame { rule.onNodeWithContentDescription("agent 往来 · 3 条").performClick() }
        opening.frames(16)
        opening.end()
        rule.onNodeWithText("补充一点", substring = true).assertIsDisplayed()
        rule.onNodeWithText("「BFT 备份尺寸分析」的 agent").assertExists()
        rule.onNodeWithText("BFT 备份尺寸分析").assertIsDisplayed()
    }
}
