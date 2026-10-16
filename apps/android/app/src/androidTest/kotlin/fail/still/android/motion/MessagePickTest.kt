package fail.still.android.motion

import android.content.ClipboardManager
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.MessageBy
import fail.still.android.data.Topics
import fail.still.android.screens.Drafts
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.io.FileOutputStream

/**
 * Picking a passage of a message where it is, in its chat (screens/MessagePick.kt): a long press picks the word under
 * the finger, sliding on widens it, and its bar quotes it into the chat's draft (as who said it), copies it or takes all
 * of it; a tap elsewhere or going back lets go of it, the chat staying where it is. `shots` pictures it into files/shots.
 */
class MessagePickTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val said = "先看日志：\n- 登录页在 Safari 上一直转圈\n- 换成 Chrome 就好了，应该是 cookie 的 SameSite 设置不对"
    private val bob = Fixtures.mine(1, "这个页面打不开，帮我看看").copy(author = "bob@example.com", authorName = "Bob", mine = false, by = MessageBy("Bob"))

    private fun open(dark: Boolean = false): Harness {
        val h = Harness(rule)
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(listOf(bob, Fixtures.agent(2, said), Fixtures.mine(3, "我这边是 Android 上的问题吗"))))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark)
        // The app's drafts outlive a test (Composer.kt Drafts): this one starts empty.
        rule.runOnUiThread { draft(h).quotes.clear() }
        h.settle()
        return h
    }

    private fun draft(h: Harness) = Drafts.of(rule.activity, h.app.core, "${Fixtures.STATION}:thread:${Fixtures.THREAD}")

    /** The text holding `words`, as drawn (not merged into its message). */
    private fun text(words: String) = rule.onNode(hasText(words, substring = true), useUnmergedTree = true)

    /** Where `words` are in the text holding them: their middle character's middle, in the node's coordinates. */
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

    private fun hold(words: String) {
        val node = text(words)
        val at = node.at(words)
        node.performTouchInput { longClick(at) }
    }

    /** Held on `from`, slid to `to` (in another text, maybe), lifted. */
    private fun holdAndSlide(from: String, to: String) {
        val a = text(from)
        val b = text(to)
        val start = a.at(from)
        val end = b.at(to) + b.fetchSemanticsNode().positionInRoot - a.fetchSemanticsNode().positionInRoot
        a.performTouchInput {
            down(start)
            advanceEventTime(viewConfiguration.longPressTimeoutMillis + 100)
            for (k in 1..8) { moveTo(start + (end - start) * (k / 8f)); advanceEventTime(16) }
            up()
        }
    }

    private fun clip() = rule.activity.getSystemService(ClipboardManager::class.java).primaryClip?.getItemAt(0)?.text?.toString()

    private fun barShown() = rule.onAllNodesWithText("引用").fetchSemanticsNodes().isNotEmpty()

    @Test fun aHoldPicksAWordWhereItIs() {
        val h = open()
        hold("一直转圈")
        h.settle()
        assertTrue("still the chat", h.app.stack.last() is Screen.Chat)
        assertTrue("its bar", barShown())
        rule.onNodeWithText("复制").performClick()
        h.settle()
        val copied = clip().orEmpty()
        assertTrue("a word of it copied: $copied", copied.isNotEmpty() && "一直转圈".contains(copied))
        assertTrue("let go of", !barShown())
    }

    @Test fun slidingWidensItAcrossLines() {
        val h = open()
        holdAndSlide("一直转圈", "SameSite")
        h.settle()
        rule.onNodeWithText("复制").performClick()
        h.settle()
        val copied = clip().orEmpty()
        assertTrue("from the word held to the one slid to: $copied", !copied.contains("Safari") && copied.contains("Chrome") && copied.endsWith("SameSite"))
    }

    @Test fun quotedIntoTheDraftAsWhoSaidIt() {
        val h = open()
        hold("一直转圈")
        h.settle()
        rule.onNodeWithText("全选").performClick()
        h.settle()
        rule.onAllNodesWithText("全选").assertCountEquals(0)
        rule.onNodeWithText("引用").performClick()
        h.settle()
        val q = draft(h).quotes.single()
        assertEquals("Claude", q.author)
        assertEquals("agent", q.role)
        assertEquals("t2", q.ts)
        assertTrue("all of it: ${q.text}", q.text.startsWith("先看日志") && q.text.endsWith("设置不对"))
        assertTrue("let go of", !barShown())
        // Someone's words, and yours.
        hold("这个页面打不开")
        h.settle()
        rule.onNodeWithText("引用").performClick()
        h.settle()
        assertEquals("Bob", draft(h).quotes.last().author)
    }

    @Test fun yoursQuotedAsYours() {
        val h = open()
        hold("Android")
        h.settle()
        rule.onNodeWithText("引用").performClick()
        h.settle()
        assertEquals(listOf("你", "person", "Android"), draft(h).quotes.last().let { listOf(it.author, it.role, it.text) })
    }

    @Test fun aTapElsewhereOrBackLetsGo() {
        val h = open()
        hold("一直转圈")
        h.settle()
        text("这个页面打不开").performClick()
        h.settle()
        assertTrue("a tap elsewhere", !barShown())
        hold("Android")
        h.settle()
        assertTrue(barShown())
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        h.settle()
        assertTrue("back", !barShown())
        assertTrue("the chat stays", h.app.stack.last() is Screen.Chat)
    }

    @Test fun shotsLight() = shots(false)
    @Test fun shotsDark() = shots(true)

    private fun shots(dark: Boolean) {
        val h = open(dark)
        val tag = if (dark) "dark" else "light"
        holdAndSlide("一直转圈", "SameSite")
        h.settle()
        shot("pick-$tag")
        rule.onNodeWithText("引用").performClick()
        h.settle()
        shot("quoted-$tag")
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
