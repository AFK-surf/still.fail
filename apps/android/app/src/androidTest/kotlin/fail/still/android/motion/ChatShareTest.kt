// Referring to a chat of another workspace from the composer (docs/chat-share.md; Composer.kt ChatRefMenu, sendSharing):
// the `@` menu lists the viewer's other workspaces' chats after the workspace's own, each with its workspace's name
// after its title; one picked goes in as a mark kept for this workspace (`chat.ref` `into`). Sent, a sheet says which
// chats this workspace's agents will read; 分享并发送 shares those the viewer may (`chat.xshareAdd`), then sends.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import fail.still.android.Screen
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatSearchView
import fail.still.android.data.OutsideRef
import fail.still.android.data.RowAgent
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.core.CoreException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ChatShareTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val topic = Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))
    private val talk = Fixtures.talk

    private fun agent(key: String) = RowAgent(key = key, runtime = "claude", process = "warm", pending = 0, agentText = "Opus 5.5", maker = Fixtures.anthropic, statusText = "已完成")

    private fun item(id: String, title: String, ago: Int, station: String = Fixtures.STATION, stationName: String = "studio", outside: String? = null) = ChatItem(
        id = id, session = "ember:$id", title = title, agents = listOf(agent("ember:$id")), unread = false, mine = true,
        lastActiveAt = Fixtures.NOW - ago * 60_000L, station = station, stationName = stationName, outside = outside,
        time = mapOf("lastActiveAt" to fail.still.android.data.Stamp((Fixtures.NOW - ago * 60_000L).toDouble(), "$ago 分钟前", "9月30日 10:00", "", true)),
    )

    /** The workspace's own chats, then two of the viewer's other workspaces'. */
    private val found = ChatSearchView(items = listOf(
        item("c-2", "登录页在 Safari 上没反应", 12),
        item("c-3", "发版说明 0.1.2500", 40),
        item("c-9", "首页改版的配色方案", 5, station = "ws-design/mac", stationName = "mac", outside = "设计组"),
        item("c-8", "Q3 招聘计划", 90, station = "ws-acme/srv", stationName = "srv", outside = "Acme 海外"),
    ))

    private val design = OutsideRef(station = "ws-design/mac", id = "c-9", title = "首页改版的配色方案", workspace = "ws-design", workspaceName = "设计组", may = true)
    private val acme = OutsideRef(station = "ws-acme/srv", id = "c-8", title = "Q3 招聘计划", workspace = "ws-acme", workspaceName = "Acme 海外", may = false)

    private fun refs(vararg chats: OutsideRef): JsonElement = buildJsonObject {
        put("chats", StillFailJson.encodeToJsonElement(ListSerializer(OutsideRef.serializer()), chats.toList()))
    }

    private fun Harness.type(text: String) = rule.onAllNodes(hasSetTextAction())[0].performClick().performTextReplacement(text)
    private fun Harness.send() = rule.onNode(hasContentDescription("发送")).performSemanticsAction(SemanticsActions.OnClick)

    /** The chat open, with what `answer` answers besides `chat.send` (taken into the outbox). */
    private fun open(dark: Boolean = false, answer: (String, kotlinx.serialization.json.JsonObject) -> JsonElement = { _, _ -> JsonNull }): Harness {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        h.fake.put(Topics.chatSearch(Fixtures.WS, "", Fixtures.STATION, null, 8, elsewhere = true), found)
        h.fake.answer = { name, params ->
            if (name == "chat.send") { h.fake.put(topic, Fixtures.chat(talk, listOf(Fixtures.outgoing("out-1", params["text"]!!.jsonPrimitive.content)))); JsonNull }
            else answer(name, params)
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))), dark = dark)
        return h
    }

    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }

    private fun names(h: Harness) = h.fake.calls.map { it.first }

    @Test fun theMenuSaysWhoseLight() = theMenuSaysWhose(false)
    @Test fun theMenuSaysWhoseDark() = theMenuSaysWhose(true)

    /** Other workspaces' chats after the workspace's own, each with its workspace's name; picked, its mark is kept for this workspace. */
    private fun theMenuSaysWhose(dark: Boolean) {
        val h = open(dark) { name, _ -> if (name == "chat.ref") buildJsonObject { put("mark", "@[首页改版的配色方案]") } else JsonNull }
        h.type("参考一下 @")
        h.keyboard()
        rule.onNodeWithText("首页改版的配色方案").assertIsDisplayed()
        rule.onAllNodesWithText("设计组")[0].assertIsDisplayed()
        rule.onAllNodesWithText("Acme 海外")[0].assertIsDisplayed()
        // The workspace's own say no workspace.
        assertEquals(1, rule.onAllNodesWithText("设计组").fetchSemanticsNodes().size)
        picture(h, if (dark) "xws-menu-dark" else "xws-menu-light")
        rule.onNodeWithText("首页改版的配色方案").performClick()
        h.settle()
        val ref = h.fake.calls.last { it.first == "chat.ref" }.second
        assertEquals("ws-design/mac", ref["station"]!!.jsonPrimitive.content)
        assertEquals("c-9", ref["id"]!!.jsonPrimitive.content)
        assertEquals(Fixtures.WS, ref["into"]!!.jsonPrimitive.content)
        rule.onNodeWithText("参考一下 @[首页改版的配色方案] ").assertExists()
    }

    /** More chats than the menu's height: a drag on it scrolls it to the last (a phone's, 2026-10-17: it did not). */
    @Test
    fun theMenuScrolls() {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(talk))
        h.fake.put(Topics.chatSearch(Fixtures.WS, "", Fixtures.STATION, null, 8, elsewhere = true), ChatSearchView(items = (1..8).map { item("c-l$it", "第 $it 个对话", it) }))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))))
        h.type("@")
        h.keyboard()
        rule.onNodeWithText("第 8 个对话").assertIsNotDisplayed()
        rule.onNodeWithText("第 4 个对话").performTouchInput { swipeUp() }
        h.settle()
        picture(h, "ref-menu-scrolled")
        rule.onNodeWithText("第 8 个对话").assertIsDisplayed()
    }

    @Test fun sharedThenSentLight() = sharedThenSent(false)
    @Test fun sharedThenSentDark() = sharedThenSent(true)

    /** Sent with a chat of another workspace in it: the sheet says which (one the viewer may not share, saying so); confirmed, it is shared, then sent. */
    private fun sharedThenSent(dark: Boolean) {
        val h = open(dark) { name, _ -> if (name == "chat.outsideRefs") refs(design, acme) else JsonNull }
        h.type("参考一下 @[首页改版的配色方案] 和 @[Q3 招聘计划]")
        h.settle()
        h.send()
        h.settle()
        rule.onNodeWithText("分享对话").assertIsDisplayed()
        rule.onNodeWithText("发送后，此 workspace 中的 agent 可读取以下内容（连续 6 小时未使用即失效）：").assertIsDisplayed()
        rule.onNodeWithText("来自 设计组").assertIsDisplayed()
        rule.onNodeWithText("来自 Acme 海外").assertIsDisplayed()
        rule.onNodeWithText("你没有分享权限，需由发起人或管理员分享").assertIsDisplayed()
        // Not sent yet.
        assertTrue("chat.send" !in names(h))
        val asked = h.fake.calls.last { it.first == "chat.outsideRefs" }.second
        assertEquals(Fixtures.STATION, asked["station"]!!.jsonPrimitive.content)
        picture(h, if (dark) "xws-sheet-dark" else "xws-sheet-light")
        rule.onNodeWithText("分享并发送").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(null, h.app.sheet) }
        // Only the one the viewer may share, with this workspace, its station told first; then the message.
        val shares = h.fake.calls.filter { it.first == "chat.xshareAdd" }.map { it.second }
        assertEquals(1, shares.size)
        assertEquals("ws-design/mac", shares[0]["station"]!!.jsonPrimitive.content)
        assertEquals("c-9", shares[0]["id"]!!.jsonPrimitive.content)
        assertEquals(Fixtures.WS, shares[0]["workspace"]!!.jsonPrimitive.content)
        assertEquals(Fixtures.STATION, shares[0]["prefer"]!!.jsonPrimitive.content)
        val order = names(h)
        assertTrue(order.indexOf("chat.xshareAdd") < order.indexOf("chat.send"))
        val sent = h.fake.calls.last { it.first == "chat.send" }.second
        assertEquals("参考一下 @[首页改版的配色方案] 和 @[Q3 招聘计划]", sent["text"]!!.jsonPrimitive.content)
    }

    /** None the viewer may share: 仍然发送 sends it as it is. */
    @Test
    fun noneMayBeSharedSentAnyway() {
        val h = open { name, _ -> if (name == "chat.outsideRefs") refs(acme) else JsonNull }
        h.type("看下 @[Q3 招聘计划]")
        h.settle()
        h.send()
        h.settle()
        rule.onNodeWithText("分享并发送").assertDoesNotExist()
        rule.onNodeWithText("仍然发送").performClick()
        h.settle()
        assertTrue("chat.xshareAdd" !in names(h))
        assertTrue("chat.send" in names(h))
    }

    /** 取消: nothing shared, nothing sent, the draft as it was. */
    @Test
    fun cancelledNothingGoes() {
        val h = open { name, _ -> if (name == "chat.outsideRefs") refs(design) else JsonNull }
        h.type("看下 @[首页改版的配色方案]")
        h.settle()
        h.send()
        h.settle()
        rule.onNodeWithText("取消").performClick()
        h.settle()
        assertTrue("chat.xshareAdd" !in names(h))
        assertTrue("chat.send" !in names(h))
        rule.onNodeWithText("看下 @[首页改版的配色方案]").assertExists()
    }

    /** A share failing is said in the sheet, which stays, and the message is not sent: the draft stays. */
    @Test
    fun aShareFailingKeepsTheDraft() {
        val h = open { name, _ ->
            when (name) {
                "chat.outsideRefs" -> refs(design)
                "chat.xshareAdd" -> throw CoreException("station_offline", "mac 离线", null)
                else -> JsonNull
            }
        }
        h.type("看下 @[首页改版的配色方案]")
        h.settle()
        h.send()
        h.settle()
        rule.onNodeWithText("分享并发送").performClick()
        h.deliver()
        h.settle()
        rule.onNodeWithText("分享失败：mac 离线").assertIsDisplayed()
        rule.runOnIdle { assertTrue(h.app.sheet != null) }
        assertTrue("chat.send" !in names(h))
        rule.onNodeWithText("看下 @[首页改版的配色方案]").assertExists()
    }

    /** Nothing of another workspace in it: no sheet, sent at once. */
    @Test
    fun nothingOutsideSentAtOnce() {
        val h = open { name, _ -> if (name == "chat.outsideRefs") refs() else JsonNull }
        h.type("看下 @[登录页在 Safari 上没反应]")
        h.settle()
        h.send()
        h.settle()
        rule.onNodeWithText("分享对话").assertDoesNotExist()
        assertTrue("chat.send" in names(h))
    }
}
