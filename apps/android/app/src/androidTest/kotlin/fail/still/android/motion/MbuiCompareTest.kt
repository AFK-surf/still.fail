// The pictures the mbui app (apps/mbui) is compared with, on the same made-up data as its sffix fixture modes
// (apps/mbui/src/sfapp: decide_fixture.mbt fix_history, chat_fixture.mbt chat-login): a link opening an agent's
// history at an entry, which flashes (cmp-link-history: the frames as it opens); a login's page opened in a Custom Tab
// over the app (cmp-login-tab.png, the whole screen); the system bars over Home, light and dark (cmp-bars-light.png,
// cmp-bars-dark.png, the whole screen). The whole screen is the system's picture of it (UiAutomation), the bars and
// another app's tab in it, written beside the recordings (motion/cmp/).
package fail.still.android.motion

import android.graphics.Bitmap
import android.view.WindowInsetsController
import android.view.accessibility.AccessibilityEvent
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionOption
import fail.still.android.data.MachineLoginShown
import fail.still.android.data.MachineLoginsView
import fail.still.android.data.MessageCard
import fail.still.android.data.MessageDecision
import fail.still.android.data.RunnableProfile
import fail.still.android.data.Session
import fail.still.android.data.Stamp
import fail.still.android.data.Topics
import java.io.File
import java.io.FileOutputStream
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Rule
import org.junit.Test

class MbuiCompareTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION
    private val session = "s-c1"

    /** The whole screen as the system shows it, as `name`.png in motion/cmp/. */
    private fun screen(name: String) {
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "motion/cmp").apply { mkdirs() }
        val shot = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: error("no screenshot")
        FileOutputStream(File(dir, "$name.png")).use { shot.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    /** The agent the history is of: Claude on Opus, done (as fix_detailed_chat's s-c1). */
    private val agent = ChatAgent(
        session = Session(
            key = session, runtime = "claude", process = "warm", pending = 0, statusText = "已完成", tone = "green", mark = null,
            titleText = "整理发布清单", agentText = "Claude", model = "opus", modelName = "Opus 5.5", effort = "high", maker = Fixtures.anthropic,
            runtimeText = "Claude Code", processText = "保温中", efforts = listOf("high"),
            time = mapOf("lastActiveAt" to Stamp(Fixtures.NOW.toDouble(), "5 分钟前", "9月30日 10:00", "", true)),
        ),
        status = "final", badge = null, profiles = emptyList(), choices = emptyList(),
        account = RunnableProfile(id = "p1", name = "zzj-max", current = true), attention = emptyList(), since = null,
        turns = emptyList(), threads = emptyList(), jobs = emptyList(),
    )

    /** decide_fixture.mbt fix_history, as the core says it (its words parsed too, `md`, which the app draws). */
    private val history = """
        {"items":[
          {"key":"h1","entries":[1,2],"body":{"kind":"received","content":{"tasks":[],"messages":[{"key":"m1","from":{"name":"林","bound":false},"text":"帮我把聊天页的列表做成虚拟列表，几千条消息也要滚得顺。"}]}}},
          {"key":"h2","entries":[1,2],"body":{"kind":"group","content":{"summary":"读了 src/ui/list.mbt 等 2 个文件，跑了测试","title":"读取","failures":0,"pending":0,"rows":[
            {"kind":"step","content":{"name":"Read","hint":"src/ui/list.mbt","meta":"","failed":false,"call":"{\"file_path\": \"/Users/lin/mbui/src/ui/list.mbt\", \"offset\": 80, \"limit\": 3}","result":"    80→pub fn Ctx::list(\n    81→  self : Ctx,\n    82→  key : String,","entries":[3,4],"brief":false}},
            {"kind":"step","content":{"said":"跑一遍列表的测试","name":"Bash","hint":"","meta":"4.2s","failed":false,"call":"{\"command\": \"moon test -p ui -f list_test.mbt\", \"description\": \"跑一遍列表的测试\", \"timeout\": 120000}","result":"Total tests: 9, passed: 9, failed: 0.","entries":[3,4],"brief":false}},
            {"kind":"thought","content":{"text":"行高先按估计值占位，滚到时再量。","first":"行高先按估计值占位","entries":[5],"brief":false}}]}}},
          {"key":"h3","entries":[1,2],"body":{"kind":"text","content":{"text":"列表只建看得见的行，其余的按估计的高度占位；量过一次的行记住它的高度，滚回来时不再跳。","md":[["p",["列表只建看得见的行，其余的按估计的高度占位；量过一次的行记住它的高度，滚回来时不再跳。"]]],"subagent":false}}},
          {"key":"h4","entries":[1,2],"body":{"kind":"group","content":{"summary":"改了 src/ui/list.mbt，跑了 2 条命令","title":"修改","failures":1,"pending":0,"rows":[
            {"kind":"step","content":{"name":"Edit","hint":"src/ui/list.mbt","meta":"","failed":false,"call":"{\"file_path\": \"/Users/lin/mbui/src/ui/list.mbt\"}","result":"The file has been updated.","entries":[3,4],"brief":false}},
            {"kind":"step","content":{"said":"截图对比","name":"Bash","hint":"","meta":"退出码 1","failed":true,"call":"{\"command\": \"scripts/shots.sh chat\", \"description\": \"截图对比\"}","result":"mac-chat.png: 312 px differ\n[exit code: 1]","entries":[3,4],"brief":false}}]}}},
          {"key":"h5","entries":[1,2],"body":{"kind":"post","content":{"text":"做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。","md":[["p",["做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。"]]],"place":{"name":"整理发布清单","surface":"ember","session":"s-c1"},"block":false,"failed":false}}},
          {"key":"h6","entries":[1,2],"body":{"kind":"mark","content":{"text":"标记为做完了：截图已更新，测试全部通过"}}}
        ],
        "live":[],"usage":[{"label":"输入","value":"1.2M tokens"},{"label":"输出","value":"34K tokens"}],
        "edge":"从 10/19 08:12 开始","empty":false,"loaded":true,"more":false}
    """.trimIndent()

    /** A link to the agent's history at entry 1 (its first item, marked a moment), opened from outside as MainActivity does. */
    @Test
    fun aLinkOpensTheHistoryAtItsEntry() {
        val h = Harness(rule)
        val chat = Topics.chat(st, ChatOf.Session(session))
        h.fake.put(chat, Fixtures.chat(Fixtures.talk, title = "整理发布清单").copy(agents = listOf(agent)))
        h.fake.set(Topics.history(st, session), Json.parseToJsonElement(history))
        val url = "https://app.still.fail/o/${Fixtures.WS}/st/$session?history=$session&entry=1"
        h.fake.answer = { name, params ->
            if (name == "link.parse" && params["url"]?.jsonPrimitive?.content == url) buildJsonObject {
                put("opens", "item"); put("workspace", Fixtures.WS); put("station", "st"); put("session", session)
                put("history", session); put("entry", 1)
            } else JsonNull
        }
        h.launch(listOf(Screen.Home))
        val r = h.record("cmp-link-history")
        r.frame { rule.runOnUiThread { h.app.openLink(url, outside = true) } }
        r.frames(150)
        r.end()
        screen("cmp-link-history")
    }

    /** A login whose page opens in the browser (在浏览器里登录), under an options card, as chat_fixture.mbt's chat-login. */
    @Test
    fun aLoginsPageOpensInACustomTab() {
        val h = Harness(rule)
        val at = Fixtures.NOW
        val login = MachineLoginShown(
            id = "login-1", station = st, stationName = "Studio", name = "gh", title = "在 Studio 上登录 gh", command = "gh auth login",
            state = "browser", step = "open", active = true, url = "https://github.com/login", domain = "github.com",
            code = null, codeUrl = null, port = null, waiting = false, listening = false, relayText = null, statusText = "在浏览器里完成登录",
            byText = "林", chat = "ember:c-demo", chatTitle = "整理发布清单", doneByText = null, endedText = null, whenText = "16:00",
            startedAt = at, expiresAt = at + 900_000, endedAt = null,
        )
        h.fake.put(Topics.machineLogins(st), MachineLoginsView(supported = true, loaded = true, canLogin = true, canRelay = true, logins = listOf(login)))
        h.fake.put(Topics.machineLogin(st, login.id), login)
        // an options card above it, as the fixture's chat has (both on the chip's grey)
        val options = listOf(DecisionOption("先不换", "这次只改列表，截图下次再说"), DecisionOption("一起换", "把首页和聊天页的截图都更新", recommended = true))
        val messages = listOf(
            Fixtures.mine(1, "截图换好了就推上去"),
            Fixtures.agent(2, "高度先按 90 估，量过一次就记住。深色模式我一起看。要不要把旧的截图也一起换掉？").copy(
                card = MessageCard(type = "options", options = options, assigneeText = "等 林 决定"), options = options,
                decision = MessageDecision(resolved = false), asked = true,
            ),
            Fixtures.agent(3, "推送截图前要先登录 gh。").copy(card = MessageCard(type = "login", login = login.id), decision = MessageDecision(resolved = false)),
        )
        h.fake.put(Topics.chat(st, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(messages, title = "整理发布清单"))
        h.launch(listOf(Screen.Home, Screen.Chat(st, ChatOf.Thread(Fixtures.THREAD))))
        rule.onNodeWithText("在 Studio 上登录 gh").assertIsDisplayed()
        screen("cmp-login-card")
        // the tab is another app's (the browser's): its window come up over this one, as the system says it (an
        // accessibility event of another package's window), the limit only a failure
        val ours = InstrumentationRegistry.getInstrumentation().targetContext.packageName
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeAndWaitForEvent(
            { rule.onNodeWithText("在浏览器里登录").performClick() },
            { e ->
                e.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                    e.packageName?.toString().let { it != null && it != ours && it != "com.android.systemui" }
            },
            30_000,
        )
        screen("cmp-login-tab")
    }

    private fun bars(dark: Boolean) {
        val h = Harness(rule)
        h.launch(listOf(Screen.Home), dark)
        // the bars' words as MainActivity sets them by the theme (the harness's activity follows the system's)
        rule.runOnUiThread {
            val bars = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
            else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
            rule.activity.enableEdgeToEdge(bars, bars)
        }
        // the bars' words as wanted before the picture: the window's own say (its insets controller's appearance)
        val light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
        var said = -1
        rule.runOnUiThread { said = rule.activity.window.decorView.windowInsetsController!!.systemBarsAppearance and light }
        check(said == if (dark) 0 else light) { "the bars' appearance $said, not ${if (dark) "dark" else "light"}'s" }
        screen("cmp-bars-${if (dark) "dark" else "light"}")
    }

    @Test fun theBarsOverHomeLight() = bars(false)
    @Test fun theBarsOverHomeDark() = bars(true)
}
