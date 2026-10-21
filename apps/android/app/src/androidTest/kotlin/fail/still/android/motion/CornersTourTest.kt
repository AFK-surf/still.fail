// TEMPORARY (not committed): pictures of the sheets, menus and cards with buttons, to look at their corners.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionOption
import fail.still.android.data.MessageDecision
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.screens.Attach
import fail.still.android.screens.ask
import fail.still.android.screens.confirm
import fail.still.android.screens.openAttach
import fail.still.android.screens.openChatInfo
import fail.still.android.screens.openInviteLink
import fail.still.android.screens.openJobs
import fail.still.android.screens.openStationMenu
import fail.still.android.screens.openWorkspaces
import fail.still.android.ui.Icons
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import org.junit.Rule
import org.junit.Test

class CornersTourTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val of = ChatOf.Thread(Fixtures.THREAD)
    private val topic = Topics.chat(Fixtures.STATION, of)
    private val asking = Fixtures.agent(5, "间距那三处要不要两处一起改？").copy(
        options = listOf(DecisionOption("先只改设置页", "侧栏那行下次再说"), DecisionOption("两处一起改", "多半个小时", recommended = true)),
        decision = MessageDecision(resolved = false),
    )

    @Test fun light() = tour(false)
    @Test fun dark() = tour(true)

    private fun tour(dark: Boolean) {
        val theme = if (dark) "dark" else "light"
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(Fixtures.talk + asking))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, of)), dark)
        fun shot(name: String, open: () -> Unit) {
            rule.runOnUiThread { open() }
            h.settle(2500)
            for (attempt in 1..4) {
                try { h.record("corners-$theme-$name").end(); break } catch (e: Throwable) {
                    if (e.javaClass.simpleName != "PixelCopyException") throw e
                    rule.mainClock.autoAdvance = true; Thread.sleep(1000)
                }
            }
            rule.mainClock.autoAdvance = true
            rule.runOnUiThread { h.app.sheet = null; h.app.menu = null }
            h.settle(1500)
        }
        shot("chat") {}
        shot("confirm") { confirm(h.app, "归档这个对话？", "归档后还能在归档页找到，随时可以恢复。", "归档", danger = true) {} }
        shot("ask") { ask(h.app, "重命名", "修一下登录", "名字", "保存") {} }
        shot("info") { openChatInfo(h.app, Fixtures.STATION, of, Fixtures.thread(5)) }
        shot("attach") { openAttach(h.app, Attach({}, {}, {})) }
        shot("menu") { h.app.menu = MenuSpec(Rect(600f, 300f, 680f, 360f), listOf(MenuItem("复制", Icons.Check) {}, MenuItem("引用", null) {}, MenuItem("删除", null) {})) }
        shot("jobs") { openJobs(h.app, Fixtures.STATION, of) }
        shot("workspaces") { openWorkspaces(h.app) }
        shot("invite") { openInviteLink(h.app) }
        shot("station") { openStationMenu(h.app, WorkspaceEntry(Fixtures.workspaces[0].workspaces[0], Fixtures.account), Fixtures.station) }
    }
}
