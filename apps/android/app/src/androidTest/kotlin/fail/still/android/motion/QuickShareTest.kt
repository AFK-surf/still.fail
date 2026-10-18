// The share list's second entry (share/Quick.kt, QuickSheet.kt; docs/client-plugins.md): the person's plugins that take
// what is shared. One: it runs as the sheet comes (`plugins.run`), the sheet says where it went and goes by itself;
// several: the person picks; none: the ordinary sheet.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.data.ChatItem
import fail.still.android.data.PluginAction
import fail.still.android.data.PluginEntry
import fail.still.android.data.PluginItem
import fail.still.android.data.PluginsView
import fail.still.android.data.ShareInView
import fail.still.android.data.Topics
import fail.still.android.share.ShareScreen
import fail.still.android.share.ShareTarget
import fail.still.android.share.Shared
import fail.still.android.ui.StillFailTheme
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class QuickShareTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val shared = Shared("7.10 复制打开抖音，看看【昔年的作品】《齐天大圣》 https://v.douyin.com/0LYqjyDj3Q0/ RKj:/", null)

    private fun plugin(id: String, name: String, chat: String, session: String) = PluginItem(
        station = Fixtures.STATION, id = id, name = name, entries = listOf(PluginEntry(kind = "share", match = "douyin")),
        action = PluginAction(kind = "chat", session = session, send = "auto"), chat = chat,
    )
    private val douyin = plugin("douyin", "抖音下载", "抖音视频下载", "ember:c-1")
    private val notes = plugin("notes", "存到笔记", "读书笔记", "ember:c-2")

    private var closed = false
    private val opened = ArrayList<fail.still.android.share.Opened>()

    private fun show(plugins: List<PluginItem>): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.plugins(Fixtures.WS, shared.source), PluginsView(items = plugins))
        h.fake.put(Topics.shareIn(Fixtures.WS, shared.source, ""), ShareInView(items = emptyList<ChatItem>(), stations = emptyList(), loading = false))
        h.fake.answer = { name, params ->
            if (name == "plugins.run") {
                val p = plugins.first { it.id == params["id"]!!.jsonPrimitive.content }
                buildJsonObject { put("station", p.station); put("session", p.action.session); put("key", "${p.station}:${p.action.session}"); put("title", p.chat); put("sent", true) }
            } else kotlinx.serialization.json.JsonNull
        }
        rule.setContent {
            StillFailTheme(false) {
                ShareScreen(shared, ShareTarget(h.fake.core, Fixtures.WS), onOpen = { opened += it }, onOpenApp = {}, onClose = { closed = true }, quick = true)
            }
        }
        return h
    }

    private fun runs(h: Harness) = h.fake.calls.filter { it.first == "plugins.run" }

    @Test fun onePluginRunsAtOnceAndTheSheetGoesByItself() {
        val h = show(listOf(douyin))
        val shot = h.record("quick-share-one")
        shot.frames(40)
        assertEquals(1, runs(h).size)
        val p = runs(h).single().second
        assertEquals("douyin", p["id"]!!.jsonPrimitive.content)
        assertEquals(shared.source, p["source"]!!.jsonPrimitive.content)
        rule.onNodeWithText("已发到「抖音视频下载」").assertExists()
        rule.onNodeWithText("打开对话").assertExists()
        // Then it goes by itself.
        shot.frames(150)
        shot.end()
        assertTrue(closed)
    }

    @Test fun severalArePickedFrom() {
        val h = show(listOf(notes, douyin))
        h.settle()
        val shot = h.record("quick-share-several")
        shot.frame()
        shot.end()
        assertEquals(0, runs(h).size)
        rule.onNodeWithText("存到笔记").performClick()
        h.settle(500)
        assertEquals(listOf("notes"), runs(h).map { it.second["id"]!!.jsonPrimitive.content })
        rule.onNodeWithText("已发到「读书笔记」").assertExists()
        rule.onNodeWithText("打开对话").performClick()
        h.settle(300)
        assertEquals(listOf("ember:c-2"), opened.map { it.session })
    }

    @Test fun noneTakingItShowsTheOrdinarySheet() {
        val h = show(emptyList())
        h.settle()
        rule.onNodeWithText("发到").assertExists()
        assertEquals(0, runs(h).size)
    }
}
