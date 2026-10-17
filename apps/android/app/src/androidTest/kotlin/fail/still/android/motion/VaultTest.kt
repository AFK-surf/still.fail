// The workspace's library (screens/Vault.kt) on a fake core: its row in the settings, its page before the lock and before
// it is turned on, turning it on (the recovery words shown, then the personal vault made), the library not locked and
// locked (the profiles' accounts, the secrets a section a kind, what is still in plain text encrypted), a secret's page
// (its content shown, edited, its uses), adding one, a request approved from the page and from its card in a chat, and
// a web page's names only. Each state is pictured into the app's files/shots.
package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.Access
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionOption
import fail.still.android.data.MessageCard
import fail.still.android.data.MessageDecision
import fail.still.android.data.Profile
import fail.still.android.data.ProfilesView
import fail.still.android.data.Stamp
import fail.still.android.data.Topics
import fail.still.android.data.VaultItemRow
import fail.still.android.data.VaultItemsView
import fail.still.android.data.VaultMember
import fail.still.android.data.VaultRefusal
import fail.still.android.data.VaultRequest
import fail.still.android.data.VaultRow
import fail.still.android.data.VaultUse
import fail.still.android.data.VaultUsesView
import fail.still.android.data.VaultsView
import fail.still.android.data.WorkspaceProfile
import java.io.File
import java.io.FileOutputStream
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class VaultTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val ws = Fixtures.WS
    private val at = Fixtures.NOW / 1000
    private val words = "orbit canvas lemon thrive patrol velvet ankle humble glide quarter mosaic ripple sponsor dune fabric wisdom cradle ozone timber jungle echo salute pigeon harbor"

    private val off = VaultsView(available = true, locked = true, canSign = true, setUp = false, vaults = emptyList(), requests = emptyList(), refused = emptyList())
    private val personal = VaultRow(
        id = "v_1", name = "个人", owner = "alice", ownerName = "Alice", mine = true, members = listOf(VaultMember("alice", "Alice")),
        station = "st", stationName = "studio", items = 4u, devices = 2u, open = true, keyed = true, missing = 1u, recoverable = true,
    )
    private val request = VaultRequest(
        id = "r_1", vault = "v_1", vaultName = "个人", item = "i_1", itemName = "GitHub token", session = "ember:c-1", chat = "", mode = "proxy",
        reason = "重跑 PR #512 失败的 release job", command = "gh run rerun 1846 --failed", hosts = listOf("api.github.com"), at = at,
    )
    private val on = off.copy(setUp = true, vaults = listOf(personal), requests = listOf(request))

    private val github = VaultItemRow("i_1", 2u, at, "GitHub token", "token", listed = true, modes = listOf("proxy"), hosts = listOf("api.github.com", "uploads.github.com"), env = "GH_TOKEN")
    private val deploy = VaultItemRow("i_2", 0u, at, "部署机 SSH 钥匙", "ssh_key", listed = true, modes = listOf("ssh"), hosts = emptyList())
    private val openai = VaultItemRow("i_3", 1u, at, "OpenAI key", "token", listed = true, modes = listOf("proxy"), hosts = listOf("api.openai.com"), env = "OPENAI_API_KEY")
    private val aliyun = VaultItemRow("i_4", 0u, at, "阿里云控制台", "login", listed = false, modes = emptyList(), hosts = emptyList())
    private val unlocked = VaultItemsView("v_1", "个人", open = true, items = listOf(deploy, github, openai, aliyun))
    /** Locked here: the listed ones' names (their listings'), the other unknown. */
    private val locked = VaultItemsView("v_1", "个人", open = false, items = listOf(deploy, github, openai, aliyun.copy(name = null, kind = null)))

    private val post = "申请使用「GitHub token」：重跑 PR #512 失败的 release job\n\n命令：`gh run rerun 1846 --failed`\n\n方式：代理（限 api.github.com）"
    private val stationOptions = listOf(
        DecisionOption("仅本次", "单次有效", recommended = true),
        DecisionOption("本对话 1 小时内", "期间无需再次批准"),
        DecisionOption("拒绝", "通知 agent 已拒绝"),
    )

    private fun theme(dark: Boolean) = if (dark) "dark" else "light"

    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun page(h: Harness, view: VaultsView, items: VaultItemsView? = unlocked, dark: Boolean) {
        h.fake.put(Topics.vaults(ws), view)
        if (items != null) h.fake.put(Topics.vaultItems(ws, "v_1"), items)
        h.launch(listOf(Screen.Home, Screen.Vault), dark)
    }

    private fun settingsRow(dark: Boolean) {
        val h = Harness(rule)
        h.fake.put(Topics.vaults(ws), on)
        h.launch(listOf(Screen.Home, Screen.Settings), dark)
        rule.onNodeWithText("1 个待批准").assertIsDisplayed()
        shot("vault-settings-${theme(dark)}")
        rule.onNodeWithText("密钥").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.Vault, h.app.stack.last()) }
    }

    @Test fun settingsRowLight() = settingsRow(false)
    @Test fun settingsRowDark() = settingsRow(true)

    /** Before the lock: the way to it and nothing else. */
    @Test fun needsTheLockFirst() {
        val h = Harness(rule)
        page(h, off.copy(locked = false, canSign = false), null, false)
        rule.onNodeWithText("需先开启安全模式").assertIsDisplayed()
        rule.onNodeWithText("开启密钥库").assertDoesNotExist()
        shot("vault-needs-lock-light")
        rule.onNodeWithText("安全").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.Security, h.app.stack.last()) }
    }

    /** Turned on: the words the core gives that once, three to a row; written down, the personal vault is made. */
    private fun turningOn(dark: Boolean) {
        val h = Harness(rule)
        h.fake.answer = { name, _ -> if (name == "vault.setup") buildJsonObject { put("words", words); put("device", "aa") } else JsonNull }
        page(h, off, null, dark)
        rule.onNodeWithText("密钥库未开启").assertIsDisplayed()
        shot("vault-off-${theme(dark)}")
        rule.onNodeWithText("开启密钥库").performClick()
        h.settle()
        rule.onNodeWithText("抄写恢复码").assertIsDisplayed()
        rule.onNodeWithText("harbor").assertIsDisplayed()
        shot("vault-words-${theme(dark)}")
        rule.onNodeWithText("已抄写").performClick()
        h.settle()
        val create = h.fake.calls.first { it.first == "vault.create" }.second
        assertEquals("个人", create["name"]!!.jsonPrimitive.content)
        rule.onNodeWithText("harbor").assertDoesNotExist()
    }

    @Test fun turningOnLight() = turningOn(false)
    @Test fun turningOnDark() = turningOn(true)

    /** Set up, unlocked: the request waiting, the items, the devices; approved from the page with its first answer. */
    private fun items(dark: Boolean) {
        val h = Harness(rule)
        page(h, on, unlocked, dark)
        rule.onNodeWithText("申请使用「GitHub token」").assertIsDisplayed()
        shot("vault-page-${theme(dark)}")
        rule.onNodeWithText("授权新设备").performScrollTo()
        h.settle()
        shot("vault-page-items-${theme(dark)}")
        rule.onNodeWithText("授权新设备").performScrollTo().performClick()
        h.settle()
        assertTrue(h.fake.calls.any { it.first == "vault.addDevice" && it.second["vault"]!!.jsonPrimitive.content == "v_1" })
        rule.onAllNodesWithText("仅本次")[0].performScrollTo().performClick()
        h.settle()
        val approve = h.fake.calls.first { it.first == "vault.approve" }.second
        assertEquals("r_1", approve["request"]!!.jsonPrimitive.content)
        assertEquals("once", approve["scope"]!!.jsonPrimitive.content)
    }

    @Test fun itemsLight() = items(false)
    @Test fun itemsDark() = items(true)

    /** Locked here: the listed ones by name; a tap opens its page, 显示 opens it (the core's prompt), 编辑 its editor. */
    private fun opened(dark: Boolean) {
        val h = Harness(rule)
        h.fake.answer = { name, params ->
            if (name == "vault.open" && params["item"]!!.jsonPrimitive.content == "i_1") buildJsonObject {
                put("vault", "v_1"); put("id", "i_1"); put("version", 2)
                putJsonObject("plain") {
                    put("kind", "token"); put("name", "GitHub token")
                    putJsonObject("fields") { put("value", "ghp_8fK2xQ7mLwN4pR1sT6vY9zB3cD5eF0gH2jK4") }
                    putJsonArray("domains") {}; put("notes", "")
                }
            } else JsonNull
        }
        page(h, on.copy(requests = emptyList(), vaults = listOf(personal.copy(open = false, missing = 0u))), locked, dark)
        rule.onNodeWithText("已加锁").assertIsDisplayed()
        shot("vault-locked-${theme(dark)}")
        rule.onNodeWithText("GitHub token").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.VaultItem("v_1", "i_1"), h.app.stack.last()) }
        rule.onNodeWithText("代理 · 限 api.github.com, uploads.github.com").assertIsDisplayed()
        rule.onNodeWithText("GH_TOKEN").assertIsDisplayed()
        shot("vault-item-${theme(dark)}")
        rule.onNodeWithText("显示").performClick()
        h.settle()
        rule.onNodeWithText("ghp_8fK2xQ7mLwN4pR1sT6vY9zB3cD5eF0gH2jK4").assertDoesNotExist()
        rule.onNodeWithContentDescription("显示").performClick()
        h.settle()
        rule.onNodeWithText("ghp_8fK2xQ7mLwN4pR1sT6vY9zB3cD5eF0gH2jK4").assertIsDisplayed()
        shot("vault-item-shown-${theme(dark)}")
        rule.onNodeWithContentDescription("编辑").performClick()
        h.settle()
        rule.onNodeWithText("编辑「GitHub token」").assertIsDisplayed()
        shot("vault-editor-${theme(dark)}")
        rule.onNodeWithText("保存").performClick()
        h.settle()
        val put = h.fake.calls.first { it.first == "vault.putItem" }.second
        assertEquals("i_1", put["id"]!!.jsonPrimitive.content)
        assertTrue(put["listing"].toString(), put["listing"].toString().contains("\"env\":\"GH_TOKEN\""))
        assertTrue(put["listing"].toString(), put["listing"].toString().contains("uploads.github.com"))
    }

    @Test fun openedLight() = opened(false)
    @Test fun openedDark() = opened(true)

    /** A new one, from the page's +: 添加 lists the kinds; an SSH key's editor has no kinds to switch. */
    private fun adding(dark: Boolean) {
        val h = Harness(rule)
        page(h, on.copy(requests = emptyList()), unlocked, dark)
        rule.onNodeWithContentDescription("添加").performClick()
        h.settle()
        rule.onNodeWithText("订阅或模型 API Key").assertIsDisplayed()
        rule.onAllNodesWithText("SSH 密钥").onLast().performClick()
        h.settle()
        rule.onNodeWithText("私钥").assertIsDisplayed()
        shot("vault-new-${theme(dark)}")
    }

    @Test fun addingLight() = adding(false)
    @Test fun addingDark() = adding(true)

    /** In the chat: the request's card, approved with its answers rather than answered in the chat. */
    private fun card(dark: Boolean) {
        val h = Harness(rule)
        val asking = Fixtures.agent(5, post).copy(
            options = stationOptions, decision = MessageDecision(resolved = false),
            card = MessageCard(assignee = Fixtures.account.email, assigneeText = "待你决策", type = "options", options = stationOptions, vault = "r_1"),
        )
        val talk = listOf(Fixtures.mine(3, "release 那一步挂了，帮我重跑一下"), Fixtures.agent(4, "看了：PR #512 的检查挂在发布那一步，是 GitHub 那边超时。我要用 GitHub token 重跑失败的 job。"), asking)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(talk, title = "修登录页的 CI"))
        h.fake.put(Topics.vaults(ws), on)
        h.launch(listOf(Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))), dark)
        rule.onNodeWithText("本对话 1 小时内").assertIsDisplayed()
        shot("vault-card-${theme(dark)}")
        rule.onNodeWithText("本对话 1 小时内").performClick()
        h.settle()
        val approve = h.fake.calls.first { it.first == "vault.approve" }.second
        assertEquals("hour", approve["scope"]!!.jsonPrimitive.content)
        // Decided (elsewhere, or here): nothing left to tap, until the station takes the card back.
        h.fake.put(Topics.vaults(ws), on.copy(requests = emptyList()))
        h.settle()
        rule.onNodeWithText("此申请已处理").assertIsDisplayed()
    }

    @Test fun cardLight() = card(false)
    @Test fun cardDark() = card(true)

    /** A web page's (no keys there): the names known, read only. */
    private fun web(dark: Boolean) {
        val h = Harness(rule)
        page(h, on.copy(available = false, canSign = false, setUp = false, requests = emptyList(), refused = listOf(VaultRefusal("mba", "MBA", "http_404"))), locked, dark)
        rule.onNodeWithText("网页端仅显示名称，请在客户端查看和批准").assertIsDisplayed()
        shot("vault-web-${theme(dark)}")
    }

    @Test fun webLight() = web(false)
    @Test fun webDark() = web(true)

    // ── the library (web/stories/vault.ts libraryDemo) ──

    private val libVault = personal.copy(id = "v_lib", stationName = "Studio", items = 3u, missing = 0u)
    private fun stamp(minutes: Long, full: String) = Stamp(
        at = (Fixtures.NOW - minutes * 60_000).toDouble(), full = full, until = "", past = true,
        ago = if (minutes < 60) "$minutes 分钟前" else if (minutes < 1440) "${Math.round(minutes / 60.0)} 小时前" else "${Math.round(minutes / 1440.0)} 天前",
    )
    private fun use(minutes: Long, full: String, chat: String, mode: String, command: String, denied: Boolean? = null) =
        VaultUse(at = stamp(minutes, full), session = "ember:c-demo-safari", station = "st", chatTitle = chat, mode = mode, command = command, hosts = listOf("api.github.com"), denied = denied)
    private val ghUses = listOf(
        use(12, "10/17 20:28", "修 Safari 上的登录跳转", "proxy", "gh pr create --fill"),
        use(130, "10/17 18:30", "重跑发布流水线", "proxy", "gh run rerun 1846 --failed"),
        use(1500, "10/16 19:40", "清理过期分支", "proxy", "gh api -X DELETE repos/acme/web/git/refs/heads/old", denied = true),
    )
    private val deployUse = use(2900, "10/15 20:20", "部署 staging", "ssh", "git push deploy main")
    private val libItems = VaultItemsView("v_lib", "个人", open = true, items = listOf(github.copy(lastUse = ghUses[0]), aliyun, deploy.copy(lastUse = deployUse)))
    private val claude = WorkspaceProfile(
        key = "$ws/st/p1", group = "claude", groupTitle = "Claude 订阅", station = Fixtures.STATION, stationId = "st", stationName = "Studio",
        profile = Profile(
            id = "p1", name = "lin@acme.dev", email = "lin@acme.dev", runtime = "claude", runtimes = listOf("claude"), access = Access(kind = "subscription", key = ""),
            home = "/Users/lin/.stillfail/profiles/p1", homeExists = true, models = listOf("opus"), env = emptyList(), usedBy = emptyList(), loginCommand = "",
            checkText = "可用", checkTone = "green", makers = emptyMap(), names = emptyMap(), series = emptyList(), modelsText = "1 个模型",
        ),
        shared = false, host = "st", hostName = "Studio", hostOnline = true, usable = true, where = "仅在 Studio", stations = emptyList(), editable = true, canShare = true,
    )
    private val plainLib = VaultsView(available = true, locked = false, canSign = false, setUp = true, vaults = listOf(libVault.copy(recoverable = false)), requests = emptyList(), refused = emptyList(), plain = true)
    private val sealedLib = VaultsView(available = true, locked = true, canSign = true, setUp = true, vaults = listOf(libVault), requests = emptyList(), refused = emptyList())

    private fun library(h: Harness, view: VaultsView, stack: List<Screen> = listOf(Screen.Home, Screen.Vault)) {
        h.fake.put(Topics.vaults(ws), view)
        h.fake.put(Topics.vaultItems(ws, "v_lib"), libItems)
        h.fake.put(Topics.vaultUses(ws, "v_lib", "i_1"), VaultUsesView("i_1", ghUses))
        h.fake.put(Topics.profiles(ws), ProfilesView(listOf(claude), loading = false))
        h.launch(stack, false)
    }

    /** Not locked: the library at once (no gate), each secret said to be in plain text; a secret's page says so too. */
    @Test fun libraryPlain() {
        val h = Harness(rule)
        library(h, plainLib)
        rule.onNodeWithText("未加锁").assertIsDisplayed()
        rule.onNodeWithText("Profile · 仅在 Studio").assertIsDisplayed()
        rule.onNodeWithText("需先开启安全模式").assertDoesNotExist()
        shot("vault-lib-plain-light")
        rule.onNodeWithText("GitHub token").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.VaultItem("v_lib", "i_1"), h.app.stack.last()) }
        rule.onNodeWithText("此密钥未加密").assertIsDisplayed()
        rule.onNodeWithText("清理过期分支 · 已拒绝").assertIsDisplayed()
        shot("vault-lib-item-light")
        rule.onNodeWithText("修 Safari 上的登录跳转").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.Chat(Fixtures.STATION, ChatOf.Session("ember:c-demo-safari")), h.app.stack.last()) }
    }

    /** Locked: 已加锁 leads to 安全, the devices last; what is still in plain text from before, encrypted from its card. */
    @Test fun librarySealed() {
        val h = Harness(rule)
        library(h, sealedLib)
        rule.onNodeWithText("已加锁").assertIsDisplayed()
        rule.onNodeWithText("2 台设备已授权").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("未加锁").assertDoesNotExist()
        shot("vault-lib-sealed-light")
        h.fake.put(Topics.vaults(ws), sealedLib.copy(plainLeft = 2u))
        h.settle()
        rule.onNodeWithText("2 条密钥尚未加密").performScrollTo().assertIsDisplayed()
        shot("vault-lib-migrate-light")
        rule.onNodeWithText("加密").performClick()
        h.settle()
        assertTrue(h.fake.calls.any { it.first == "vault.migrate" })
        rule.onNodeWithText("已加锁").performScrollTo().performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.Security, h.app.stack.last()) }
    }

    /** 添加: a profile (to the Profile list) or a secret of a kind (its editor, the kind fixed, the risk said at its top). */
    @Test fun libraryAdd() {
        val h = Harness(rule)
        library(h, plainLib)
        rule.onNodeWithContentDescription("添加").performClick()
        h.settle()
        rule.onNodeWithText("网站的用户名和密码").assertIsDisplayed()
        shot("vault-lib-add-light")
        rule.onAllNodesWithText("Token").onLast().performClick()
        h.settle()
        rule.onNodeWithText("添加密钥").assertIsDisplayed()
        shot("vault-lib-editor-light")
        h.app.sheet = null
        h.settle()
        rule.onNodeWithContentDescription("添加").performClick()
        h.settle()
        rule.onNodeWithText("订阅或模型 API Key").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.Profiles(), h.app.stack.last()) }
    }
}
