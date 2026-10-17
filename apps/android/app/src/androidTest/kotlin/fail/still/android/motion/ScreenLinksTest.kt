// Links to a station's screens in an agent's words (screens/ScreenLinks.kt): one alone in a paragraph is the screen's
// card (its title and line the core's `screenCard`; one gone, quieter; one not known yet, the card's size with empty
// lines; one with its own words, those as its title), a tap on it opening the link; a bare one within a sentence reads
// as the screen's title. Pictured as screen-links/settled.png (and screen-links-dark).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.ScreenCard
import fail.still.android.data.Topics
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ScreenLinksTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val opened = CopyOnWriteArrayList<String>()
    private val uris = object : UriHandler { override fun openUri(uri: String) { opened += uri } }

    private fun path(id: String) = "/w/${Fixtures.WS}/s/st/screen/${id.replace(":", "%3A")}"
    private fun link(id: String) = "https://app.still.fail${path(id)}"
    private val tab = "browser:D4AD129260A6A360D131CA36CF35F544"
    private val closed = "browser:0F3E"
    private val unknown = "browser:9A1C"

    private val said = "Bob 正在看的标签页：\n\n${link(tab)}\n\n之前那个已经关了：\n\n${link(closed)}\n\n" +
        "[Bob 的另一个标签页](${link(unknown)})\n\n${link("desktop")}\n\n也可以直接点 ${link("desktop")} 接手桌面。"

    private fun open(dark: Boolean = false): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.screenCard(Fixtures.STATION, tab), ScreenCard("browser", "still.fail — 登录", "浏览器标签页 · 1280×800 · Bob 正在查看", path(tab), gone = false))
        h.fake.put(Topics.screenCard(Fixtures.STATION, closed), ScreenCard("browser", "浏览器标签页", "此屏幕已不存在", path(closed), gone = true))
        h.fake.put(Topics.screenCard(Fixtures.STATION, "desktop"), ScreenCard("desktop", "这台 Mac", "桌面 · 3024×1964", path("desktop"), gone = false))
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(listOf(Fixtures.mine(1, "能看下 Bob 的浏览器吗"), Fixtures.agent(2, said))))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark, uris = uris)
        return h
    }

    @Test fun screenLinksAreTheirCards() {
        val h = open()
        rule.onNodeWithText("浏览器标签页 · 1280×800 · Bob 正在查看").assertIsDisplayed()
        rule.onNodeWithText("此屏幕已不存在").assertIsDisplayed()
        rule.onNodeWithText("Bob 的另一个标签页").assertIsDisplayed()
        rule.onNodeWithText("桌面 · 3024×1964").assertIsDisplayed()
        rule.onNode(hasText("也可以直接点 这台 Mac 接手桌面。"), useUnmergedTree = true).assertIsDisplayed()
        h.record("screen-links").run { frame(); end() }
        rule.onNodeWithText("still.fail — 登录").performClick()
        h.settle()
        assertEquals(listOf(link(tab)), opened.toList())
    }

    @Test fun screenLinksInTheDark() {
        val h = open(dark = true)
        rule.onNodeWithText("此屏幕已不存在").assertIsDisplayed()
        h.record("screen-links-dark").run { frame(); end() }
    }
}
