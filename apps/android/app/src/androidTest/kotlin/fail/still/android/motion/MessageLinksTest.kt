package fail.still.android.motion

import android.content.ClipboardManager
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performFirstLinkClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.MessageBy
import fail.still.android.data.Topics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Links in a chat's messages (ui/Links.kt): a tap on one opens it (an agent's Markdown link, an address written bare or
 * alone in code, one in someone's words or in yours), the address written bare ending where the Chinese after it
 * begins; a long press on one is its menu (open it, copy it), not the message's page and not the link opening as the
 * finger lifts; a long press on the other words is the message's page still. `shots` pictures the menu into files/shots.
 */
class MessageLinksTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    /** What the app handed the system to open (a link not still.fail's own goes there). */
    private val opened = CopyOnWriteArrayList<String>()
    private val uris = object : UriHandler { override fun openUri(uri: String) { opened += uri } }

    private val said = "链接测试：\n- Markdown 链接：[PR #138](https://github.com/AFK-surf/still.fail/pull/138)\n- 代码里的网址：`https://example.com/code`\n- 裸网址：https://example.com/bare（已改到）"
    private val bob = Fixtures.mine(1, "这个页面打不开 https://example.com/person-bare（帮我看看）").copy(author = "bob@example.com", authorName = "Bob", mine = false, by = MessageBy("Bob"))

    private fun open(dark: Boolean = false): Harness {
        val h = Harness(rule)
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(listOf(bob, Fixtures.agent(2, said), Fixtures.mine(3, "我这边是 https://example.com/mine-bare。"))))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark, uris = uris)
        return h
    }

    /** The text holding `words`, as drawn (not merged into its message). */
    private fun text(words: String) = rule.onNode(hasText(words, substring = true), useUnmergedTree = true)

    /**
     * Where `words` are in the text holding them: their middle character's middle, in the node's coordinates (a bubble's
     * node holds its padding round the words, as much on each side).
     */
    private fun SemanticsNodeInteraction.at(words: String): Offset {
        val layouts = mutableListOf<TextLayoutResult>()
        performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val layout = layouts.first()
        val i = layout.layoutInput.text.text.indexOf(words)
        check(i >= 0) { "\"$words\" is not in ${layout.layoutInput.text.text}" }
        val node = fetchSemanticsNode()
        val padding = Offset((node.size.width - layout.size.width) / 2f, (node.size.height - layout.size.height) / 2f)
        return layout.getBoundingBox(i + words.length / 2).center + padding
    }

    private fun SemanticsNodeInteraction.hold(words: String) {
        val at = at(words)
        performTouchInput { longClick(at) }
    }

    private fun tapLink(words: String, url: String, h: Harness) {
        text(words).performFirstLinkClick { (it.item as? LinkAnnotation.Url)?.url == url }
        h.settle()
    }

    @Test fun aTapOpensIt() {
        val h = open()
        tapLink("PR #138", "https://github.com/AFK-surf/still.fail/pull/138", h)
        tapLink("代码里的网址", "https://example.com/code", h)
        tapLink("裸网址", "https://example.com/bare", h)
        tapLink("这个页面打不开", "https://example.com/person-bare", h)
        tapLink("我这边是", "https://example.com/mine-bare", h)
        assertEquals(
            listOf("https://github.com/AFK-surf/still.fail/pull/138", "https://example.com/code", "https://example.com/bare", "https://example.com/person-bare", "https://example.com/mine-bare"),
            opened.toList(),
        )
    }

    @Test fun aHoldIsItsMenu() {
        val h = open()
        text("PR #138").hold("PR #138")
        h.settle()
        assertEquals("opened as the finger lifted", emptyList<String>(), opened.toList())
        assertTrue("the message's page opened", h.app.stack.last() is Screen.Chat)
        rule.onNodeWithText("复制链接").performClick()
        h.settle()
        val clip = rule.activity.getSystemService(ClipboardManager::class.java).primaryClip
        assertEquals("https://github.com/AFK-surf/still.fail/pull/138", clip?.getItemAt(0)?.text?.toString())
        // Someone's words, and your own: the same menu, and 打开链接 opens it.
        text("这个页面打不开").hold("example.com/person-bare")
        h.settle()
        rule.onNodeWithText("打开链接").performClick()
        h.settle()
        text("我这边是").hold("example.com/mine-bare")
        h.settle()
        rule.onNodeWithText("打开链接").performClick()
        h.settle()
        assertEquals(listOf("https://example.com/person-bare", "https://example.com/mine-bare"), opened.toList())
        assertTrue(h.app.stack.last() is Screen.Chat)
    }

    @Test fun aHoldOnTheOtherWordsIsTheMessagesPage() {
        val h = open()
        text("链接测试").hold("链接测试")
        h.settle()
        assertTrue("its page", h.app.stack.last() is Screen.Annotate)
    }

    @Test fun shotsLight() = shots(false)
    @Test fun shotsDark() = shots(true)

    private fun shots(dark: Boolean) {
        val h = open(dark)
        val tag = if (dark) "dark" else "light"
        shot("links-$tag")
        text("PR #138").hold("PR #138")
        h.settle()
        shot("link-menu-$tag")
        rule.onNodeWithText("复制链接").performClick()
        h.settle(300)
        shot("link-copied-$tag")
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
