// A chat made public (Publish.kt; docs/public-share.md): its sheet, from "…" (ChatInfo.kt), has 「公开分享」 and the
// links published, each to copy and, for who may, to revoke; 「公开分享」 opens the sheet that previews it (what was
// hidden in each message, the attachments to tick, one too big not), publishes it and then shows its link.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import fail.still.android.Screen
import fail.still.android.data.Attachment
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatPublish
import fail.still.android.data.ChatPublished
import fail.still.android.data.PublishFile
import fail.still.android.data.PublishMessage
import fail.still.android.data.PublishPreview
import fail.still.android.data.Stamp
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PublishSheetTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val of = ChatOf.Thread(Fixtures.THREAD)
    private val topic = Topics.chat(Fixtures.STATION, of)
    private val link = "https://share.still.fail/#B5CrvEZwwZq7oct4Vs0Ld90SJHgZO4uOwQdhtJsLRNE.Qm9vSzVnUkN2dUdS.k3Yq"

    private fun ago(text: String) = mapOf("createdAt" to Stamp(Fixtures.NOW.toDouble(), text, "10月15日 10:00", "", true))

    private fun published(id: String, by: String, mine: Boolean, ago: String) =
        ChatPublished(id = id, link = "$link-$id", createdAt = Fixtures.NOW, byName = by, mayRevoke = mine, time = ago(ago))

    /** As views/publish.ts previewShown has a station's answer: a person's message with a key hidden, an agent's reply,
     * three attachments. */
    private fun file(k: String, name: String, size: Long, sizeText: String, type: String) =
        PublishFile(k = k, name = name, size = size.toULong(), sizeText = sizeText, type = type, n = 9, file = Attachment(name = name, path = "/w/uploads/$name", size = size))

    private val files = listOf(
        file("f0", "login-page.png", 665, "665 B", "image/png"),
        file("f1", "deploy.log", 2048, "2.0 KB", "text/plain"),
        file("f2", "build-cache.tar", 12_582_912, "12 MB", "application/x-tar"),
    )

    private val preview = PublishPreview(
        upto = 9, title = "部署登录页",
        messages = listOf(
            PublishMessage(n = 4, author = "Alice", agent = false, text = "帮我把登录页部署到预发，token 是 [已隐藏]", files = emptyList(), hidden = 1u, hiddenText = "已隐藏 1 处", createdAt = Fixtures.NOW, time = ago("12 分钟前")),
            PublishMessage(n = 6, author = "Opus 5.5", agent = true, text = "部署好了：**登录后跳回原页面**，`npm run deploy:staging` 跑了 42 秒。", files = emptyList(), hidden = 0u, createdAt = Fixtures.NOW, time = ago("10 分钟前")),
            PublishMessage(n = 9, author = "Alice", agent = false, text = "截图、日志和构建缓存都附上了", files = files, hidden = 0u, createdAt = Fixtures.NOW, time = ago("8 分钟前")),
        ),
        files = files,
        hidden = 1u, hiddenText = "共隐藏 1 处疑似机密",
    )

    private fun open(publish: ChatPublish, dark: Boolean = false): Harness {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(Fixtures.talk).copy(publish = publish))
        h.fake.answer = { name, _ ->
            when (name) {
                "chat.publishPreview" -> StillFailJson.encodeToJsonElement(PublishPreview.serializer(), preview)
                "chat.publish" -> StillFailJson.encodeToJsonElement(ChatPublished.serializer(), published("p3", "Alice", true, "刚刚"))
                else -> JsonNull
            }
        }
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark = dark)
        return h
    }

    /** A still picture of the page as it is, under `name`. */
    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }

    private val two = ChatPublish(may = true, links = listOf(published("p2", "Alice", true, "10 分钟前"), published("p1", "Bob", false, "2 天前")))

    @Test
    fun theChatIsPreviewedTickedAndPublished() = publishing(dark = false)

    @Test
    fun theChatIsPublishedInTheDark() = publishing(dark = true)

    private fun publishing(dark: Boolean) {
        val suffix = if (dark) "-dark" else ""
        val h = open(two, dark)
        rule.onNodeWithContentDescription("对话信息").performClick()
        h.settle()
        rule.onNodeWithText("公开分享").assertIsDisplayed()
        rule.onNodeWithText("10 分钟前 · Alice").assertIsDisplayed()
        rule.onNodeWithText("2 天前 · Bob").assertIsDisplayed()
        // Bob's is only copied: the viewer did not publish it, and is no owner or admin.
        assertEquals(1, rule.onAllNodesWithText("撤销").fetchSemanticsNodes().size)
        picture(h, "chat-info-publish$suffix")

        rule.onNodeWithText("公开分享").performClick()
        h.settle()
        rule.onNodeWithText("持有链接的任何人都可查看这些消息；station 离线时无法打开").assertIsDisplayed()
        rule.onNodeWithText("已隐藏 1 处").assertIsDisplayed()
        picture(h, "publish-sheet$suffix")
        // The log and the cache unticked, where their message has them.
        rule.onNodeWithText("deploy.log").performScrollTo().performClick()
        rule.onNodeWithText("build-cache.tar").performScrollTo().performClick()
        h.settle()
        picture(h, "publish-sheet-files$suffix")
        rule.onNodeWithText("发布").performScrollTo().performClick()
        h.settle()
        val asked = h.fake.calls.last { it.first == "chat.publish" }.second
        assertEquals(Fixtures.STATION, asked["station"]!!.jsonPrimitive.content)
        assertEquals(Fixtures.THREAD.toString(), asked["thread"]!!.jsonPrimitive.content)
        assertEquals("9", asked["upto"]!!.jsonPrimitive.content)
        assertEquals(listOf("f0"), asked["files"]!!.jsonArray.map { it.jsonPrimitive.content })
        // Published: its link, to copy.
        rule.onNodeWithText("已发布").assertIsDisplayed()
        rule.onNodeWithText("$link-p3").assertIsDisplayed()
        picture(h, "publish-made$suffix")
    }

    /** A link revoked is asked about first, then the core told (`chat.unpublish`), the sheet gone at once. */
    @Test
    fun aLinkIsRevokedOnceAsked() {
        val h = open(two)
        rule.onNodeWithContentDescription("对话信息").performClick()
        h.settle()
        rule.onNodeWithText("撤销").performClick()
        h.settle()
        rule.onNodeWithText("撤销后，持有链接的人将无法打开").assertIsDisplayed()
        assertTrue(h.fake.calls.none { it.first == "chat.unpublish" })
        rule.onNodeWithText("撤销").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(null, h.app.sheet) }
        val asked = h.fake.calls.last { it.first == "chat.unpublish" }.second
        assertEquals("p2", asked["id"]!!.jsonPrimitive.content)
        assertEquals(Fixtures.THREAD.toString(), asked["thread"]!!.jsonPrimitive.content)
    }

    /** A read-only member does not publish: no 「公开分享」, the links only to copy. */
    @Test
    fun aReadOnlyMemberOnlyCopies() {
        val h = open(ChatPublish(may = false, links = listOf(published("p1", "Bob", false, "2 天前"))))
        rule.onNodeWithContentDescription("对话信息").performClick()
        h.settle()
        rule.onNodeWithText("2 天前 · Bob").assertIsDisplayed()
        rule.onNodeWithText("公开分享").assertDoesNotExist()
        rule.onNodeWithText("撤销").assertDoesNotExist()
    }
}
