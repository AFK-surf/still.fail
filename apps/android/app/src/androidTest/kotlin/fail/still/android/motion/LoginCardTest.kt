// A login an agent started (docs/remote-login.md), on the phone (screens/LoginCards.kt): the same card as the web's in a
// chat under the agent's message, on 奏, and on the station page's 登录, in each of its states (a device code, its code
// copied on a tap and 复制并打开; 在浏览器里登录 for a loopback login, which listens before the page opens, and says so
// when this phone's port is taken; a page to open; its agent answering the command; ended, a line), 取消 beside; a
// read-only member only sees how it stands. Pictured as login-cards(-older)-light|dark, login-station-light|dark,
// login-decision-light|dark (settled.png).
package fail.still.android.motion

import android.content.ClipboardManager
import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import fail.still.android.AppHooks
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionItem
import fail.still.android.data.DecisionsView
import fail.still.android.data.MachineLoginShown
import fail.still.android.data.MachineLoginsView
import fail.still.android.data.MessageCard
import fail.still.android.data.MessageDecision
import fail.still.android.data.Topics
import fail.still.android.screens.LoginPages
import fail.still.core.CoreException
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class LoginCardTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION
    private val at = Fixtures.NOW
    private val gcloudUrl = "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=32555940559.apps.googleusercontent.com&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2F&state=s3"

    /** A login in one state or another, as the core shows it (web/stories/data.ts LOGINS). */
    private fun login(id: String, command: String, state: String = "browser", active: Boolean = true, step: String? = null, url: String? = null, domain: String? = null,
                      code: String? = null, codeUrl: String? = null, waiting: Boolean = false, listening: Boolean = false, relayText: String? = null, statusText: String = "",
                      endedText: String? = null, doneByText: String? = null, chatTitle: String? = "发布 0.4 版", whenText: String = "16:00") = MachineLoginShown(
        id = id, station = st, stationName = "studio", name = command.substringBefore(' '), title = "在 studio 上登录 ${command.substringBefore(' ')}", command = command,
        state = state, step = step, active = active, url = url, domain = domain, code = code, codeUrl = codeUrl, port = if (step == "loopback") 8085u else null,
        waiting = waiting, listening = listening, relayText = relayText, statusText = statusText, byText = "林", chat = "ember:c-demo", chatTitle = chatTitle,
        doneByText = doneByText, endedText = endedText, whenText = whenText, startedAt = at, expiresAt = at + 900_000, endedAt = if (active) null else at + 60_000,
    )

    private val device = login("device", "gh auth login", state = "code", step = "device", url = "https://github.com/login/device", domain = "github.com", code = "ABCD-1234", statusText = "验证码 ABCD-1234")
    private val loopback = login("loopback", "gcloud auth login", step = "loopback", url = gcloudUrl, domain = "accounts.google.com", statusText = "等你打开浏览器")
    private val listening = loopback.copy(id = "listening", listening = true, statusText = "等浏览器回来")
    private val taken = loopback.copy(id = "taken", relayText = "本机 8085 端口被占用")
    private val open = login("open", "npm login", step = "open", url = "https://www.npmjs.com/login?next=/login/cli/6f1c2b", domain = "www.npmjs.com", statusText = "在浏览器里完成登录")
    private val question = login("question", "gh auth login", state = "input", step = "terminal", waiting = true, statusText = "等 agent 回答命令的问题")
    private val done = login("done", "gh auth login", state = "done", active = false, statusText = "登录完成", endedText = "已在 studio 上登录 gh", doneByText = "林 完成", chatTitle = "修 CI 的 token", whenText = "10/16 11:20")
    private val failed = login("failed", "gcloud auth login", state = "failed", active = false, statusText = "登录失败", endedText = "在 studio 上登录 gcloud 失败：ERROR: (gcloud.auth.login) There was a problem with web authentication.", whenText = "10/15 09:05")
    private val cancelled = login("cancelled", "npm login", state = "cancelled", active = false, statusText = "已取消", endedText = "Ada 取消了在 studio 上登录 npm", doneByText = "Ada 取消", chatTitle = "npm 发包", whenText = "10/14 18:42")
    private val all = listOf(device, loopback, listening, taken, open, question, done, failed, cancelled)

    private val opened = CopyOnWriteArrayList<String>()
    private val relaying = CopyOnWriteArrayList<String>()
    private var pages: ((Context, String) -> Unit)? = null

    @Before fun record() {
        pages = LoginPages.open
        LoginPages.open = { _, url -> opened += url }
        AppHooks.relaying = { relaying += it }
    }

    @After fun restore() {
        pages?.let { LoginPages.open = it }
    }

    private val chatTopic = Topics.chat(st, ChatOf.Thread(Fixtures.THREAD))

    /** The logins on the station, and a chat whose agent posted a card for each of `cards`. */
    private fun chat(cards: List<MachineLoginShown>, dark: Boolean = false, canLogin: Boolean = true): Harness {
        val h = Harness(rule)
        put(h, canLogin)
        val messages = listOf(Fixtures.mine(1, "把 gh、gcloud、npm 都登录一下")) + cards.mapIndexed { i, l ->
            Fixtures.agent(2L + i, "要在 studio 上登录 ${l.name}").copy(card = MessageCard(type = "login", login = l.id), decision = MessageDecision(resolved = !l.active))
        }
        h.fake.put(chatTopic, Fixtures.chat(messages))
        h.launch(listOf(Screen.Chat(st, ChatOf.Thread(Fixtures.THREAD))), dark)
        return h
    }

    private fun put(h: Harness, canLogin: Boolean = true, logins: List<MachineLoginShown> = all) {
        h.fake.put(Topics.machineLogins(st), MachineLoginsView(supported = true, loaded = true, canLogin = canLogin, canRelay = true, logins = logins))
        // A read-only member's: no page, no code.
        all.forEach { l -> h.fake.put(Topics.machineLogin(st, l.id), if (canLogin) l else l.copy(url = null, code = null, codeUrl = null)) }
    }

    private fun clipboard(): String? {
        var text: String? = null
        rule.runOnUiThread { text = (rule.activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip?.getItemAt(0)?.text?.toString() }
        return text
    }

    // ── each state, pictured ──

    private fun cards(dark: Boolean) {
        // The chat opens at its end: the newest cards, then (scrolled up) the older ones.
        val h = chat(listOf(done, failed, question, taken, loopback, device), dark)
        rule.onNodeWithText("ABCD-1234").assertIsDisplayed()
        h.record("login-cards-${if (dark) "dark" else "light"}").run { frame(); end() }
        // The list (the composer's field scrolls too, after it).
        rule.onAllNodes(hasScrollAction()).onFirst().performScrollToNode(hasText("已在 studio 上登录 gh"))
        h.settle()
        rule.onNodeWithText("已在 studio 上登录 gh").assertIsDisplayed()
        h.record("login-cards-older-${if (dark) "dark" else "light"}").run { frame(); end() }
    }

    @Test fun theCardsInAChatLight() = cards(false)
    @Test fun theCardsInAChatDark() = cards(true)

    private fun station(dark: Boolean) {
        val h = Harness(rule)
        put(h, logins = listOf(listening, open, done, failed, cancelled))
        h.launch(listOf(Screen.Stations, Screen.Station(st, login = "open")), dark)
        rule.onNodeWithText("登录页在 www.npmjs.com").assertIsDisplayed()
        h.record("login-station-${if (dark) "dark" else "light"}").run { frame(); end() }
        rule.onNodeWithText("gcloud auth login").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Ada 取消", substring = true).performScrollTo().assertIsDisplayed()
    }

    @Test fun theStationsPageLight() = station(false)
    @Test fun theStationsPageDark() = station(true)

    private fun decision(dark: Boolean) {
        val h = Harness(rule)
        put(h)
        val post = Fixtures.agent(12, "要在 studio 上登录 GitHub：点下面卡片的「复制并打开」").copy(card = MessageCard(type = "login", login = "device"), decision = MessageDecision(resolved = false))
        h.fake.put(Topics.decisions(Fixtures.WS), DecisionsView(listOf(DecisionItem(
            station = st, stationName = "studio", session = "ember:c-7", thread = post.thread, title = "修 CI 的 token", seq = post.seq, message = post,
            before = listOf(Fixtures.mine(11, "CI 的 gh 掉登录了")), options = emptyList(), card = post.card, text = "奏 · 要在 studio 上登录 GitHub",
        )), 1u, wait = Fixtures.NO_WAIT))
        h.launch(listOf(Screen.Home, Screen.Decisions), dark)
        rule.onNodeWithText("ABCD-1234").assertIsDisplayed()
        h.record("login-decision-${if (dark) "dark" else "light"}").run { frame(); end() }
    }

    @Test fun onZouLight() = decision(false)
    @Test fun onZouDark() = decision(true)

    // ── what a tap does ──

    @Test fun theCodeTappedIsCopiedAndNothingOpens() {
        val h = chat(listOf(device))
        rule.onNodeWithContentDescription("复制验证码 ABCD-1234").performClick()
        h.settle()
        assertEquals("ABCD-1234", clipboard())
        assertEquals(emptyList<String>(), opened.toList())
        rule.onNodeWithText("验证码已复制").assertIsDisplayed()
        assertTrue(h.fake.calls.none { it.first.startsWith("machineLogin.") })
    }

    @Test fun copyAndOpenCopiesThenOpensItsPage() {
        val h = chat(listOf(device))
        rule.onNodeWithText("复制并打开").performClick()
        h.settle()
        assertEquals("ABCD-1234", clipboard())
        assertEquals(listOf("https://github.com/login/device"), opened.toList())
        // A page that needs nothing of this phone opens as it is: no relay asked for, the app not held up.
        assertTrue(h.fake.calls.none { it.first == "machineLogin.open" })
        assertEquals(emptyList<String>(), relaying.toList())
    }

    @Test fun aLoopbackLoginListensHereBeforeItsPageOpens() {
        val h = chat(listOf(loopback))
        val order = CopyOnWriteArrayList<String>()
        h.fake.answer = { name, params ->
            if (name == "machineLogin.open") {
                order += "open ${params["id"]!!.jsonPrimitive.content} here=${params["here"]!!.jsonPrimitive.content}"
                buildJsonObject { put("url", gcloudUrl) }
            } else JsonNull
        }
        AppHooks.relaying = { order += "held: $it" }
        LoginPages.open = { _, url -> order += "page: $url" }
        rule.onNodeWithText("在浏览器里登录").performClick()
        rule.waitUntil(5_000) { order.size == 3 }
        assertEquals(listOf("open loopback here=false", "held: 在 studio 上登录 gcloud", "page: $gcloudUrl"), order.toList())
        // The core says it listens: 等浏览器回来, the page to open again.
        h.fake.put(Topics.machineLogin(st, "loopback"), listening.copy(id = "loopback"))
        h.settle()
        rule.onNodeWithText("正在等待浏览器").assertIsDisplayed()
        rule.onNodeWithText("再打开一次").assertIsDisplayed()
    }

    @Test fun thisPhonesPortTakenIsSaidOnTheCardNothingOpens() {
        val h = chat(listOf(loopback))
        h.fake.answer = { name, _ -> if (name == "machineLogin.open") throw CoreException("port_taken", "本机 8085 端口被占用", null) else JsonNull }
        rule.onNodeWithText("在浏览器里登录").performClick()
        h.settle()
        assertEquals(emptyList<String>(), opened.toList())
        assertEquals(emptyList<String>(), relaying.toList())
        // No toast: the card says it (the core's relayText), the button there to try again.
        rule.onNodeWithText("无法打开浏览器", substring = true).assertDoesNotExist()
        h.fake.put(Topics.machineLogin(st, "loopback"), taken.copy(id = "loopback"))
        h.settle()
        rule.onNodeWithText("本机 8085 端口被占用").assertIsDisplayed()
        rule.onNodeWithText("在浏览器里登录").assertIsDisplayed()
    }

    @Test fun cancelEndsIt() {
        val h = chat(listOf(open))
        rule.onNodeWithText("取消").performClick()
        h.settle()
        val call = h.fake.calls.single { it.first == "machineLogin.cancel" }.second
        assertEquals(listOf(st, "open"), listOf(call["station"]!!.jsonPrimitive.content, call["id"]!!.jsonPrimitive.content))
    }

    @Test fun aReadOnlyMemberSeesOnlyHowItStands() {
        chat(listOf(device), canLogin = false)
        rule.onNodeWithText("验证码 ABCD-1234").assertIsDisplayed()
        rule.onNodeWithText("复制并打开").assertDoesNotExist()
        rule.onNodeWithText("取消").assertDoesNotExist()
    }

    @Test fun endedItIsOneLine() {
        chat(listOf(done, failed, cancelled))
        assertEquals(0, rule.onAllNodesWithTag("login-card").fetchSemanticsNodes().size)
        assertEquals(3, rule.onAllNodesWithTag("login-ended").fetchSemanticsNodes().size)
        rule.onNodeWithText("Ada 取消了在 studio 上登录 npm").assertIsDisplayed()
    }
}
