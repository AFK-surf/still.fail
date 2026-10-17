// A link to a station's 共享调试 in an agent's words (screens/AdbLinks.kt): alone in a paragraph it is a card (a phone,
// 共享调试, how this phone's sharing with that station stands: the core's `adbCard`), a tap on it opening the link; a
// bare one within a sentence reads as 共享调试. Pictured as adb-links/settled.png (and adb-links-dark).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.AdbCard
import fail.still.android.data.ChatOf
import fail.still.android.data.Topics
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class AdbLinksTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val opened = CopyOnWriteArrayList<String>()
    private val uris = object : UriHandler { override fun openUri(uri: String) { opened += uri } }

    private val link = "https://app.still.fail/w/${Fixtures.WS}/s/st/adb"
    private val said = "好，我用 adb 直接装。现在这台 station 上没有共享中的手机，麻烦在 App 里点一下「开始共享」：\n\n$link\n\n" +
        "正式环境的包正在 studio 上打，大约 3 分钟。也可以从 $link 停止共享。"

    private fun open(dark: Boolean = false): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.adbCard(Fixtures.STATION), AdbCard("共享调试", "未共享", sharing = false, lendable = true))
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(listOf(Fixtures.mine(1, "用 adb 装一下"), Fixtures.agent(2, said))))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark, uris = uris)
        h.settle()
        return h
    }

    @Test fun adbLinkIsItsCard() {
        val h = open()
        rule.onNodeWithText("未共享").assertIsDisplayed()
        rule.onNode(hasText("也可以从 共享调试 停止共享。", substring = true), useUnmergedTree = true).assertIsDisplayed()
        h.record("adb-links").run { frame(); end() }
        rule.onNodeWithText("未共享").performClick()
        h.settle()
        assertEquals(listOf(link), opened.toList())
    }

    @Test fun adbLinkInTheDarkWhileShared() {
        val h = open(dark = true)
        h.fake.put(Topics.adbCard(Fixtures.STATION), AdbCard("共享调试", "共享中 · 剩余 42 分钟", sharing = true, lendable = true))
        h.settle()
        rule.onNodeWithText("共享中 · 剩余 42 分钟").assertIsDisplayed()
        h.record("adb-links-dark").run { frame(); end() }
    }
}
