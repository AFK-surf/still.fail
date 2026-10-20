// The workspace's security mode (Security.kt): its row in the settings, its page off and on, a waiting device confirmed
// from a bottom sheet once its code is compared, a new device met face to face shown this one's code (put up by itself
// wherever the app is, naming every workspace it asks for, turned away only: nothing here approves it), turning it on,
// turning it off only once the workspace's name is typed, and what a device waiting itself shows (asking by hand, the
// code typed in, and why its request did not go).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.LockDevice
import fail.still.android.data.LockDraftDevice
import fail.still.android.data.LockDraftMember
import fail.still.android.data.LockDraftStation
import fail.still.android.data.LockDraftView
import fail.still.android.data.LockMe
import fail.still.android.data.LockPerson
import fail.still.android.data.LockPair
import fail.still.android.data.LockPairing
import fail.still.android.data.LockPromptWorkspace
import fail.still.android.data.LockPromptsView
import fail.still.android.data.LockRequest
import fail.still.android.data.LockStation
import fail.still.android.data.LockView
import fail.still.android.data.Stamp
import fail.still.android.data.Topics
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SecurityTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val ws = Fixtures.WS
    private val me = LockMe(device = "aa".repeat(32), code = "SZN-LYA", kind = "app", confirmed = true, waiting = false)

    private fun off() = LockView(
        available = true, locked = false, notice = true, role = "owner", manages = true, owner = true, canSign = true, signs = false, me = me,
        signers = 0u, members = emptyList(), stations = emptyList(), protected = 0u, requests = emptyList(), renew = emptyList(), attention = 0u,
    )

    private fun on(): LockView {
        val web = LockDevice(id = "bb".repeat(32), kind = "web", label = "still.fail 网页版 · Chrome · macOS", signs = false, older = false, mine = false, daysLeft = 3u, renewSoon = true, recent = false)
        val mac = LockDevice(id = "aa".repeat(32), kind = "app", label = "still.fail 安卓版 · Pixel 8", signs = true, older = false, mine = true, renewSoon = false, recent = false)
        val request = LockRequest(device = "cc".repeat(32), sub = "carol", email = "lier@example.com", name = "李二", kind = "web", label = "still.fail 网页版 · Chrome · Windows",
            code = "K7F-2QX", created_at = Fixtures.NOW / 1000, yours = false, time = mapOf("created_at" to Stamp(Fixtures.NOW.toDouble(), "3 分钟前", "", "", true)))
        return off().copy(
            locked = true, notice = false, signs = true, signers = 2u, protected = 2u, requests = listOf(request), renew = listOf(web), attention = 2u,
            members = listOf(
                LockPerson(sub = "zzj", email = "zuozijian@example.com", name = "左子健", role = "owner", you = true, devices = listOf(mac, web)),
                LockPerson(sub = "carol", email = "lier@example.com", name = "李二", role = "member", you = false, devices = emptyList()),
            ),
            stations = listOf(LockStation(id = "s1", name = "Studio", online = true, protected = true), LockStation(id = "s2", name = "MBA", version = "0.1.2571", online = true, protected = false)),
        )
    }

    private fun draft() = LockDraftView(
        available = true, loading = false, canSign = true, owner = true, ready = true,
        members = listOf(LockDraftMember("zzj", "zuozijian@example.com", "左子健", "owner"), LockDraftMember("carol", "lier@example.com", "李二", "member")),
        devices = listOf(
            LockDraftDevice(id = "aa".repeat(32), person = "左子健", kind = "app", label = "", older = false, current = true, last_seen = Fixtures.NOW / 1000, on = true, fixed = true),
            LockDraftDevice(id = "dd".repeat(32), person = "李二", kind = "web", label = "still.fail 网页版 · Firefox · Windows", older = false, current = false, last_seen = Fixtures.NOW / 1000, on = false, fixed = false),
        ),
        stations = listOf(LockDraftStation(id = "s1", name = "Studio", version = "0.1.2680", state = "ok", on = true, fixed = false), LockDraftStation(id = "s2", name = "MBA", version = "0.1.2571", state = "old", on = false, fixed = true)),
    )

    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }

    @Test fun settingsRowSaysItIsOff() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), off())
        h.launch(listOf(Screen.Home, Screen.Settings))
        rule.onNodeWithText("未开启").assertIsDisplayed()
        picture(h, "security-row")
        rule.onNodeWithText("安全").performClick()
        h.settle()
        rule.onNodeWithText("安全模式未开启").assertIsDisplayed()
        picture(h, "security-off")
        rule.onNodeWithText("开启安全模式").performClick()
        h.settle()
        rule.runOnIdle { assertEquals(Screen.SecurityOpen, h.app.stack.last()) }
    }

    @Test fun turningItOnSignsTheDraft() {
        val h = Harness(rule)
        h.fake.put(Topics.lockDraft(ws), draft())
        h.launch(listOf(Screen.Home, Screen.Settings, Screen.Security, Screen.SecurityOpen))
        rule.onNodeWithText("版本过旧，不受保护 · 更新后可在此保护").assertIsDisplayed()
        picture(h, "security-draft")
        rule.onNodeWithText("李二 · still.fail 网页版 · Firefox · Windows").performClick()
        h.settle()
        assertTrue(h.fake.calls.any { it.first == "lock.toggle" && it.second["id"]!!.jsonPrimitive.content == "dd".repeat(32) })
        rule.onNodeWithText("批准并开启").performClick()
        h.settle()
        assertTrue(h.fake.calls.any { it.first == "lock.open" })
    }

    @Test fun aWaitingDeviceIsConfirmedByItsCode() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), on())
        h.launch(listOf(Screen.Home, Screen.Settings, Screen.Security))
        rule.onNodeWithText("安全模式已开启").assertIsDisplayed()
        picture(h, "security-on")
        rule.onNodeWithText("李二的新设备").performClick()
        h.settle()
        rule.onNodeWithText("验证李二的新设备").assertIsDisplayed()
        picture(h, "security-confirm")
        rule.onNodeWithText("一致，批准").performClick()
        h.settle()
        val call = h.fake.calls.first { it.first == "lock.confirm" }.second
        assertEquals("cc".repeat(32), call["device"]!!.jsonPrimitive.content)
        assertEquals("K7F-2QX", call["code"]!!.jsonPrimitive.content)
    }

    @Test fun turningItOffTakesTheWorkspaceName() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), on())
        h.launch(listOf(Screen.Home, Screen.Settings, Screen.Security))
        rule.onNodeWithText("关闭安全模式").performScrollTo().performClick()
        h.settle()
        rule.onNodeWithText("关闭安全模式？").assertIsDisplayed()
        rule.onNodeWithText("密钥库将无法使用").assertIsDisplayed()
        picture(h, "security-turn-off")
        // Not yet named: the button does nothing.
        rule.onAllNodesWithText("关闭安全模式").onLast().performClick()
        h.settle()
        rule.runOnIdle { assertTrue(h.fake.calls.none { it.first == "lock.disable" }) }
        rule.onNode(hasSetTextAction()).performTextInput("Dev")
        h.settle()
        picture(h, "security-turn-off-named")
        rule.onAllNodesWithText("关闭安全模式").onLast().performClick()
        h.settle()
        rule.runOnIdle { assertTrue(h.fake.calls.any { it.first == "lock.disable" && it.second["workspace"]!!.jsonPrimitive.content == ws }) }
    }

    /** A new device asking in two workspaces of the person's, `日常` not the one open, shown this one's code. */
    private fun prompts(): LockPromptsView {
        val r = on().requests.first()
        val p = LockPairing(device = r.device, email = r.email, name = r.name, kind = r.kind, label = r.label, code = "482913", created_at = r.created_at, time = r.time,
            workspaces = listOf(LockPromptWorkspace(id = ws, name = "Dev"), LockPromptWorkspace(id = "w2", name = "日常")))
        return LockPromptsView(pairing = listOf(p))
    }

    @Test fun aNewDeviceShowsThisOnesCodeAndIsNotApprovedHere() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), on())
        h.fake.put(Topics.lockPrompts, prompts())
        h.launch(listOf(Screen.Home))
        rule.onNodeWithText("李二的新设备请求批准").assertIsDisplayed()
        rule.onNodeWithText("482 913").assertIsDisplayed()
        rule.onNodeWithText("日常").assertIsDisplayed()
        rule.onNodeWithText("一致", substring = true).assertDoesNotExist()
        picture(h, "security-prompt")
        rule.onNodeWithText("拒绝").performClick()
        h.settle()
        rule.onNodeWithText("李二的新设备请求批准").assertDoesNotExist()
        rule.runOnIdle {
            val call = h.fake.calls.first { it.first == "lockPrompt.deny" }.second
            assertEquals("cc".repeat(32), call["device"]!!.jsonPrimitive.content)
        }
    }

    @Test fun aNewDeviceClosedByHandIsTurnedAway() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), on())
        h.fake.put(Topics.lockPrompts, prompts())
        h.launch(listOf(Screen.Home))
        rule.onNodeWithText("李二的新设备请求批准").assertIsDisplayed()
        rule.runOnIdle { assertTrue(h.fake.calls.none { it.first == "lockPrompt.deny" }) }
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        h.settle()
        rule.onNodeWithText("李二的新设备请求批准").assertDoesNotExist()
        rule.runOnIdle { assertTrue(h.fake.calls.any { it.first == "lockPrompt.deny" && it.second["device"]!!.jsonPrimitive.content == "cc".repeat(32) }) }
    }

    private fun waiting(pair: LockPair? = null, failed: String? = null) =
        off().copy(locked = true, me = me.copy(confirmed = false, waiting = true, asked = false, failed = failed, pair = pair))

    @Test fun aWaitingDeviceAsksByHand() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), waiting())
        h.launch(listOf(Screen.Home))
        rule.onNodeWithText("等待批准此设备").assertIsDisplayed()
        // Its own code is no longer what it shows.
        rule.onNodeWithText("SZN-LYA").assertDoesNotExist()
        picture(h, "security-waiting")
        rule.onNodeWithText("发送批准请求").performClick()
        h.settle()
        rule.runOnIdle { assertTrue(h.fake.calls.any { it.first == "lock.pair" && it.second["workspace"]!!.jsonPrimitive.content == ws }) }
    }

    @Test fun aWaitingDeviceTypesTheCodeItIsShown() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), waiting(LockPair(state = "code", devices = 1u)))
        h.launch(listOf(Screen.Home))
        rule.onNodeWithText("输入你的受信任设备上显示的安全码").assertIsDisplayed()
        // Five digits: nothing goes yet; the sixth hands it on by itself.
        rule.onNode(hasSetTextAction()).performTextInput("48291")
        h.settle()
        picture(h, "security-waiting-code")
        rule.runOnIdle { assertTrue(h.fake.calls.none { it.first == "lock.pairCode" }) }
        rule.onNode(hasSetTextAction()).performTextInput("3")
        h.settle()
        rule.runOnIdle {
            val call = h.fake.calls.first { it.first == "lock.pairCode" }.second
            assertEquals(ws, call["workspace"]!!.jsonPrimitive.content)
            assertEquals("482913", call["code"]!!.jsonPrimitive.content)
        }
    }

    @Test fun aWrongCodeSaysHowManyTriesAreLeft() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), waiting(LockPair(state = "wrong", devices = 1u, left = 2u)))
        h.launch(listOf(Screen.Home))
        rule.onNodeWithText("安全码不对，还可以试 2 次").assertIsDisplayed()
    }

    @Test fun aWaitingDeviceWhoseRequestDidNotGoSaysWhy() {
        val h = Harness(rule)
        h.fake.put(Topics.lock(ws), waiting(failed = "无法在系统钥匙串中保存此设备的密钥：secure.set unsupported"))
        h.launch(listOf(Screen.Home))
        rule.onNodeWithText("此设备无法提交批准请求：无法在系统钥匙串中保存此设备的密钥：secure.set unsupported").assertIsDisplayed()
        rule.onNodeWithText("发送批准请求").performClick()
        h.settle()
        rule.runOnIdle { assertTrue(h.fake.calls.any { it.first == "lock.pair" && it.second["workspace"]!!.jsonPrimitive.content == ws }) }
    }
}
