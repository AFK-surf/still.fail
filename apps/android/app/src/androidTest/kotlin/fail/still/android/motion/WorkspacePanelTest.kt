// The workspace capsule, its panel and its swipe (Home.kt, Workspaces.kt) with four workspaces over two accounts and an
// invitation waiting, light and dark: Home with the capsule, the panel open, a swipe on the capsule half way, and a
// switch half way; and the capsule with one workspace, and with a long name. Each picture is written as a PNG beside the
// recordings (files/motion/workspace-shots/), the frames as the recordings'.
package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.Account
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatsView
import fail.still.android.data.Me
import fail.still.android.data.PendingInvitation
import fail.still.android.data.RowMessage
import fail.still.android.data.StationState
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceMark
import fail.still.android.data.WorkspaceMarksView
import fail.still.android.data.WorkspaceSummary
import java.io.File
import java.io.FileOutputStream
import org.junit.Rule
import org.junit.Test

class WorkspacePanelTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val afk = Fixtures.WS
    private val still = "ws-still"
    private val cue = "ws-cue"
    private val own = "ws-own"
    private val work = Account("zuo", "zuo@afk.surf", "Zuo")
    private val gmail = Account("zuo-g", "zuo@gmail.com", "Zuo")

    private fun row(ws: String, i: Int, title: String, last: String, tone: String? = null, stateText: String? = null, unread: Boolean = false) = ChatItem(
        id = "$ws-$i", session = "ember:c-$ws-$i", thread = 100L + i, title = title, agents = emptyList(), unread = unread, mine = true,
        last = RowMessage(seq = 1, authorKind = "agent", author = "ember:c-$ws-$i", text = last, createdAt = Fixtures.NOW - i * 600_000L, preview = last),
        lastActiveAt = Fixtures.NOW - i * 600_000L, station = "$ws/st", stationName = "studio", tone = tone, stateText = stateText,
    )

    private fun view(ws: String, today: List<ChatItem>, before: List<ChatItem>) = ChatsView(
        me = Me(work.email, work.email), stations = listOf(StationState("$ws/st", "st", "studio", "online")), loading = false,
        days = listOf(ChatDay(0, Fixtures.NOW.toDouble(), "今天", today), ChatDay(1, (Fixtures.NOW - 86_400_000L).toDouble(), "昨天", before)),
    )

    private val lists = mapOf(
        afk to view(afk, listOf(
            row(afk, 0, "安卓切换 workspace 要方便", "面板和左右滑都做好了，截图在上面", tone = "wait", stateText = "在等：你看截图"),
            row(afk, 1, "Safari 登录按钮没反应", "改成在 onSubmit 里处理了，两个浏览器都试过", tone = "done", unread = true),
            row(afk, 2, "CI 随机失败统计", "最近 40 次运行里还剩 3 条随机失败", tone = "busy", stateText = "在跑：拆 main 的失败记录"),
            row(afk, 3, "周报：本周发布", "草稿写好了，放在 docs/weekly.md"),
        ), listOf(
            row(afk, 4, "官网首页的 demo 动效", "换成 Astra 画的那一版了"),
            row(afk, 5, "station 更新后连不上", "重启后好了，原因是端口被占"),
            row(afk, 6, "清理 studio 磁盘", "删了闲置的 worktree，腾出 120G"),
            row(afk, 7, "奏页空状态的插图", "三版放在 design/ 下面了"),
        )),
        still to view(still, listOf(
            row(still, 0, "发版 0.1.2500", "签名那一步失败了：钥匙串没解锁", tone = "alert", stateText = "出错了：签名失败"),
            row(still, 1, "更新日志的中文措辞", "按你说的改短了", tone = "done", unread = true),
            row(still, 2, "首页加载慢", "列表的第一屏现在 80ms", tone = "done", unread = true),
        ), listOf(
            row(still, 3, "安卓通知分组", "按 workspace 分组了", tone = "done", unread = true),
            row(still, 4, "设置页卡片圆角", "统一成 22 了"),
        )),
        cue to view(cue, listOf(
            row(cue, 0, "报价单模板", "两版报价放在上面了", tone = "wait", stateText = "奏 · 用哪一版报价"),
            row(cue, 1, "客户访谈纪要", "整理好了，等你看一眼", tone = "wait", stateText = "在等：你确认纪要"),
            row(cue, 2, "合同里的付款节点", "改成三期了"),
        ), listOf(row(cue, 3, "演示环境", "部署好了，链接在上面"))),
        own to view(own, listOf(row(own, 0, "读书笔记整理", "按月份归好了")), listOf(row(own, 1, "旅行行程", "订好了周五的票"))),
    )

    private val marks = WorkspaceMarksView(
        workspaces = mapOf(
            afk to WorkspaceMark(alert = 0u, unread = 1u, wait = 1u, tone = "wait", label = "1 个在等你 · 1 个有新消息"),
            still to WorkspaceMark(alert = 1u, unread = 3u, tone = "alert", label = "1 个出错了 · 3 个有新消息"),
            cue to WorkspaceMark(alert = 0u, unread = 0u, wait = 2u, decisions = 1u, tone = "wait", label = "2 个在等你"),
            own to WorkspaceMark(alert = 0u, unread = 0u),
        ),
        others = "alert", othersLabel = "其他 workspace：1 个出错了 · 2 个在等你 · 3 个有新消息",
    )

    /**
     * Home on AFK, with still.fail, `cueName` after it and 个人 under the other account, and 林一's invitation to 设计组;
     * `one`: AFK alone, nothing waiting.
     */
    private fun home(dark: Boolean = false, one: Boolean = false, cueName: String = "Cue 客户"): Harness {
        val h = Harness(rule)
        for ((ws, list) in lists) {
            h.fake.put(Topics.chats(ws, false), list)
            h.fake.put(Topics.chats(ws, true), list)
            h.fake.put(Topics.chats(ws, false, watching = true), list.copy(days = emptyList()))
            h.fake.put(Topics.workspaceMarks(ws), marks)
        }
        h.launch(listOf(Screen.Home), dark = dark)
        if (one) {
            h.fake.put(Topics.accounts, listOf(work))
            h.fake.put(Topics.workspaces, listOf(AccountWorkspaces(work, listOf(WorkspaceSummary(afk, "AFK", "owner", 1, 6)), loaded = true)))
        } else {
            h.fake.put(Topics.accounts, listOf(work, gmail))
            h.fake.put(Topics.workspaces, listOf(
                AccountWorkspaces(work, listOf(
                    WorkspaceSummary(afk, "AFK", "owner", 1, 6), WorkspaceSummary(still, "still.fail", "owner", 3, 4), WorkspaceSummary(cue, cueName, "member", 1, 3),
                ), invitations = listOf(PendingInvitation("inv-1", "ws-design", "设计组", "member", "林一")), loaded = true),
                AccountWorkspaces(gmail, listOf(WorkspaceSummary(own, "个人", "owner", 1, 1)), loaded = true),
            ))
        }
        h.settle()
        return h
    }

    private val shots = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "motion/workspace-shots").apply { mkdirs() }

    /** The window as it is now, as a PNG (the clock not moved). */
    private fun png(name: String) {
        rule.waitForIdle()
        val b = rule.onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(File(shots, "$name.png")).use { b.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun theme(dark: Boolean) = if (dark) "dark" else "light"

    private fun panel(dark: Boolean) {
        val h = home(dark)
        png("a-home-${theme(dark)}")
        rule.onNodeWithText("AFK").performClick()
        h.settle()
        // The tap's ripple is the platform's (RippleDrawable), on the system's clock rather than the test's: let it fade.
        Thread.sleep(1000)
        png("b-panel-${theme(dark)}")
        rule.onNodeWithText("林一邀请你加入「设计组」").assertExists()
        rule.onNodeWithText("zuo@gmail.com").assertExists("two accounts: each one's workspaces under its email")
        for (name in listOf("still.fail", "Cue 客户", "个人", "新建 workspace", "登录其它账号")) rule.onNodeWithText(name).assertExists(name)
        // Over the capsule, not over the bar: the panel ends above the capsule's top.
        val capsule = rule.onAllNodesWithText("AFK").fetchSemanticsNodes().maxBy { it.boundsInRoot.bottom }.boundsInRoot
        val foot = rule.onNodeWithText("登录其它账号").fetchSemanticsNode().boundsInRoot
        check(foot.bottom < capsule.top) { "the panel's foot ($foot) is not above the capsule ($capsule)" }
    }

    @Test fun panelLight() = panel(false)
    @Test fun panelDark() = panel(true)

    /** Half way through a drag on the capsule, then let go: on to still.fail, the frames recorded (the videos). */
    private fun swipe(dark: Boolean) {
        val h = home(dark)
        val name = rule.onNodeWithText("AFK").fetchSemanticsNode().boundsInRoot
        val r = h.record("workspace-swipe-${theme(dark)}")
        r.frame { rule.onRoot().performTouchInput { down(Offset(name.left + name.width * 0.6f, name.center.y)) } }
        repeat(8) { r.frame { rule.onRoot().performTouchInput { moveBy(Offset(-10f, 0f)) } } }
        png("c-mid-swipe-${theme(dark)}")
        repeat(6) { r.frame { rule.onRoot().performTouchInput { moveBy(Offset(-10f, 0f)) } } }
        r.frame { rule.onRoot().performTouchInput { up() } }
        repeat(6) { r.frame() }
        png("d-mid-switch-swipe-${theme(dark)}")
        r.frames(24)
        r.end()
        check(h.app.workspace == still) { "swiped to ${h.app.workspace}" }
    }

    @Test fun swipeLight() = swipe(false)
    @Test fun swipeDark() = swipe(true)

    private fun panelSwitch(dark: Boolean) {
        val h = home(dark)
        rule.onNodeWithText("AFK").performClick()
        h.settle()
        val r = h.record("workspace-panel-switch-${theme(dark)}")
        r.frame { rule.onNodeWithText("Cue 客户").performClick() }
        repeat(8) { r.frame() }
        png("d-mid-switch-panel-${theme(dark)}")
        r.frames(24)
        r.end()
        check(h.app.workspace == cue) { "switched to ${h.app.workspace}" }
    }

    @Test fun panelSwitchLight() = panelSwitch(false)
    @Test fun panelSwitchDark() = panelSwitch(true)

    /** One workspace: its name alone in the capsule, no dots. */
    @Test fun single() {
        home(one = true)
        png("g-single-light")
        rule.onNodeWithText("AFK").assertExists()
    }

    /** A long name: the capsule goes up to 12dp short of 奏, the name cut short with an ellipsis. */
    @Test fun longName() {
        val long = "Cue 客户的长名字工作区测试"
        val h = home(cueName = long)
        rule.runOnUiThread { h.app.pickWorkspace(cue); h.app.home() }
        h.settle()
        png("h-long-name-light")
        rule.onNodeWithText(long).assertExists()
    }
}
