// Links to a station's screens in an agent's words (screens/ScreenLinks.kt): one alone in a paragraph is the screen's
// card (its title and line the core's `screenCard`; one gone, quieter; one not known yet, the card's size with empty
// lines; one with its own words, those as its title), a tap on it opening the link; a bare one within a sentence reads
// as the screen's title. A tab its station previews is live in its card (`screen.view` with `peek`, JPEG). Pictured as
// screen-links/settled.png (and screen-links-dark).
package fail.still.android.motion

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Color as AColor
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
import java.io.ByteArrayOutputStream
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

private const val VIEW = "screen.view"

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
        h.fake.put(Topics.screenCard(Fixtures.STATION, tab), ScreenCard("browser", "still.fail — 登录", "浏览器标签页 · 1280×800 · Bob 正在查看", path(tab), gone = false, peek = true, width = 1280u, height = 800u))
        h.fake.put(Topics.screenCard(Fixtures.STATION, closed), ScreenCard("browser", "浏览器标签页", "此屏幕已不存在", path(closed), gone = true, peek = false, width = 0u, height = 0u))
        h.fake.put(Topics.screenCard(Fixtures.STATION, "desktop"), ScreenCard("desktop", "这台 Mac", "桌面 · 3024×1964", path("desktop"), gone = false, peek = false, width = 3024u, height = 1964u))
        val of = ChatOf.Thread(Fixtures.THREAD)
        h.fake.put(Topics.chat(Fixtures.STATION, of), Fixtures.chat(listOf(Fixtures.mine(1, "能看下 Bob 的浏览器吗"), Fixtures.agent(2, said))))
        h.fake.streams += VIEW
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark, uris = uris)
        // The live tab's preview: asked only looking, in JPEG; a picture of it comes and is acknowledged.
        rule.waitUntil(5_000) { h.fake.opened(VIEW) }
        val asked = h.fake.calls.last { it.first == VIEW }.second
        assertEquals(true, asked["peek"]?.jsonPrimitive?.booleanOrNull)
        assertEquals(listOf("jpeg"), asked["codecs"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals(tab, asked["screen"]?.jsonPrimitive?.content)
        h.fake.say(VIEW, buildJsonObject { put("config", buildJsonObject { put("codec", "jpeg"); put("width", 640); put("height", 400) }) })
        h.fake.say(VIEW, buildJsonObject { put("frame", buildJsonObject { put("ts", 1); put("key", true) }) }, page())
        rule.waitUntil(5_000) { h.fake.calls.any { it.first == "screen.ack" && it.second["ts"]?.jsonPrimitive?.content == "1" } }
        h.settle()
        return h
    }

    /** A tab's picture, as its station sends one: a login page, in JPEG. */
    private fun page(): ByteArray {
        val b = Bitmap.createBitmap(640, 400, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        c.drawColor(AColor.WHITE)
        paint.color = AColor.rgb(36, 39, 43); c.drawRect(0f, 0f, 640f, 44f, paint)
        paint.color = AColor.WHITE; paint.textSize = 20f; c.drawText("still.fail", 20f, 29f, paint)
        paint.color = AColor.rgb(36, 39, 43); paint.textSize = 30f; c.drawText("登录", 270f, 120f, paint)
        paint.color = AColor.rgb(227, 225, 222)
        c.drawRoundRect(170f, 150f, 470f, 194f, 10f, 10f, paint)
        c.drawRoundRect(170f, 210f, 470f, 254f, 10f, 10f, paint)
        paint.color = AColor.rgb(225, 90, 40); c.drawRoundRect(170f, 280f, 470f, 324f, 22f, 22f, paint)
        paint.color = AColor.WHITE; paint.textSize = 18f; c.drawText("继续", 302f, 308f, paint)
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
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
