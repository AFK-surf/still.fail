// One station in several workspaces (docs/multi-workspace.md) on the phone: 添加 station offers a station the viewer
// manages in another workspace beside a new machine (Settings.kt openAddStation), a station this workspace joined says
// where it is at home in the list and on its page, and a station's page in its home workspace lists the workspaces it is
// in (Stations.kt).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.JoinableStation
import fail.still.android.data.JoinableView
import fail.still.android.data.Link
import fail.still.android.data.MembershipsView
import fail.still.android.data.StationMembership
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceSummary
import fail.still.android.data.WorkspaceView
import fail.still.android.screens.openAddStation
import fail.still.core.CoreException
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class StationJoinTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val ws = Fixtures.WS
    private val entry = WorkspaceEntry(WorkspaceSummary(ws, "Dev", "owner", 1, 1), Fixtures.account)

    private fun station(id: String, name: String, joined: Boolean = false, home: String? = null, emoji: String? = null) = StationView(
        station = "$ws/$id", id = id, name = name, summary = "10 核 · 32 GB", face = "idle", online = true, link = Link("online"),
        runtimes = emptyList(), models = emptyList(), emoji = emoji, joined = joined, home = home,
    )

    private val stations = listOf(station("studio", "studio", emoji = "🖥️"), station("mini", "mini", joined = true, home = "Acme"), station("gpu", "gpu", joined = true))

    private val candidates = listOf(
        JoinableStation(station = "ws-acme/air", id = "air", name = "air", emoji = "🍎", workspace = "ws-acme", workspaceName = "Acme", online = true, line = "Acme · 在线"),
        JoinableStation(station = "ws-acme/box", id = "box", name = "box", workspace = "ws-acme", workspaceName = "Acme", online = false, line = "Acme · 离线"),
        JoinableStation(station = "ws-lab/rig", id = "rig", name = "rig", workspace = "ws-lab", workspaceName = "Lab", online = true, line = "Lab · 在线"),
    )

    private fun start(dark: Boolean, joinable: JoinableView): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.workspace(ws), WorkspaceView(id = ws, name = "Dev", role = "owner"))
        h.fake.put(Topics.joinable(ws), joinable)
        h.fake.put(Topics.memberships("$ws/studio"), MembershipsView(
            manages = true, loading = false, canJoin = true, workspaces = listOf(
                StationMembership(workspace = ws, name = "Dev", stationName = "studio", home = true, here = true, line = "主 workspace", roots = emptyList()),
                StationMembership(workspace = "ws-acme", name = "Acme", stationName = "studio", home = false, here = false, line = "开放的文件夹：still.fail、notes", roots = emptyList()),
            ),
        ))
        h.launch(listOf(Screen.Stations), dark)
        rule.runOnUiThread { h.fake.put(Topics.stations(ws), stations) }
        h.settle()
        return h
    }

    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }

    private fun openSheet(h: Harness) {
        rule.runOnUiThread { openAddStation(h.app, entry, stations.map { it.id }) }
        h.settle()
    }

    /** The button that adds the one picked (not a row's words). */
    private fun join() = rule.onNode(hasText("加进来") and hasClickAction())

    @Test fun light() = walk(false)
    @Test fun dark() = walk(true)

    private fun walk(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = start(dark, JoinableView(offered = true, loading = false, items = candidates))
        // The list: a joined station says where it is at home, after what it is.
        rule.onNodeWithText("来自 Acme · 10 核 · 32 GB").assertIsDisplayed()
        rule.onNodeWithText("来自别的 workspace · 10 核 · 32 GB").assertIsDisplayed()
        picture(h, "join-list-$tone")

        // 添加 station: a new machine first, as before; the other way a tap away.
        openSheet(h)
        rule.onNodeWithText("新机器").assertIsDisplayed()
        picture(h, "join-sheet-new-$tone")
        rule.onNodeWithText("已有的 station").performClick()
        h.settle()
        rule.onNodeWithText("Acme · 在线").assertIsDisplayed()
        rule.onNodeWithText("那台机器上的 agent 用同一个系统用户运行", substring = true).assertIsDisplayed()
        rule.onNodeWithText("box").performClick()
        h.settle()
        picture(h, "join-sheet-existing-$tone")

        // Refused: why, in red, under the list; the sheet stays.
        h.fake.answer = { name, _ -> if (name == "station.join") throw CoreException("invalid", "这台 station 还不能加入别的 workspace：先把它更新到最新版", 404) else JsonNull }
        join().performClick()
        h.settle()
        rule.onNodeWithText("这台 station 还不能加入别的 workspace", substring = true).assertIsDisplayed()
        val (call, params) = h.fake.calls.last { it.first == "station.join" }
        assertEquals("station.join", call)
        assertEquals(ws, params["workspace"]!!.jsonPrimitive.content)
        assertEquals("ws-acme/box", params["station"]!!.jsonPrimitive.content)
        picture(h, "join-sheet-error-$tone")

        // Joined: said with the name it has here, and Done.
        h.fake.answer = { name, _ ->
            if (name == "station.join") buildJsonObject { putJsonObject("joined") { put("workspace", ws); put("workspaceName", "Dev"); put("name", "box") } } else JsonNull
        }
        join().performClick()
        h.settle()
        rule.onNodeWithText("「box」已加入这个 workspace。").assertIsDisplayed()
        picture(h, "join-sheet-joined-$tone")
        rule.runOnUiThread { h.app.sheet = null }
        h.settle()

        // None to add: said so; the button stays off.
        rule.runOnUiThread { h.fake.put(Topics.joinable(ws), JoinableView(offered = true, loading = false, items = emptyList())) }
        openSheet(h)
        rule.onNodeWithText("已有的 station").performClick()
        h.settle()
        rule.onNodeWithText("你管理的其他 workspace 里没有能加进来的 station").assertIsDisplayed()
        join().assertIsNotEnabled()
        picture(h, "join-sheet-empty-$tone")
        rule.runOnUiThread { h.app.sheet = null }
        h.settle()

        // Its page in its home workspace: the workspaces it is in.
        rule.runOnUiThread { h.app.push(Screen.Station("$ws/studio")) }
        h.settle()
        rule.onNodeWithText("开放的文件夹：still.fail、notes").assertIsDisplayed()
        picture(h, "join-page-workspaces-$tone")

        // A joined station's page: where it is at home, under its name; no workspaces of its own here.
        rule.runOnUiThread { h.app.pop(); h.app.push(Screen.Station("$ws/mini")) }
        h.settle()
        assertTrue(rule.onAllNodesWithText("来自 Acme", substring = true).fetchSemanticsNodes().isNotEmpty())
        picture(h, "join-page-joined-$tone")
    }

    /** One who manages no other workspace: no choice, the sheet as it was. */
    @Test fun notOffered() {
        val h = start(false, JoinableView(offered = false, loading = false, items = emptyList()))
        openSheet(h)
        assertEquals(0, rule.onAllNodesWithText("已有的 station").fetchSemanticsNodes().size)
    }
}
