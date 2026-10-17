// One station in several workspaces (docs/multi-workspace.md) on the phone: 添加 station offers a station the viewer
// manages in another workspace beside a new machine (Settings.kt openAddStation), a station this workspace joined says
// where it is at home in the list and on its page, and a station's page in its home workspace lists the workspaces it is
// in (Stations.kt). A profile of such a station is opened to a joined workspace by a switch (Profiles.kt
// WorkspacesSection); a joined station none of whose profiles is open to this workspace says whom to ask on a new
// chat's page, offering neither a profile to add nor the machine's sessions (NewChat.kt).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import fail.still.android.data.Access
import fail.still.android.data.Counts
import fail.still.android.data.NewChatView
import fail.still.android.data.Overview
import fail.still.android.data.Profile
import fail.still.android.data.Viewer
import fail.still.android.screens.Drafts
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
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
                StationMembership(workspace = ws, name = "Dev", stationName = "studio", home = true, here = true, line = "主 workspace"),
                StationMembership(workspace = "ws-acme", name = "Acme", stationName = "studio", home = false, here = false, line = "加入的 workspace"),
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
    private fun join() = rule.onNode(hasText("添加到此 workspace") and hasClickAction())

    @Test fun light() = walk(false)
    @Test fun dark() = walk(true)

    private fun walk(dark: Boolean) {
        val tone = if (dark) "dark" else "light"
        val h = start(dark, JoinableView(offered = true, loading = false, items = candidates))
        // The list: a joined station says where it is at home, after what it is.
        rule.onNodeWithText("来自 Acme · 10 核 · 32 GB").assertIsDisplayed()
        rule.onNodeWithText("来自其他 workspace · 10 核 · 32 GB").assertIsDisplayed()
        picture(h, "join-list-$tone")

        // 添加 station: a new machine first, as before; the other way a tap away.
        openSheet(h)
        rule.onNodeWithText("新机器").assertIsDisplayed()
        picture(h, "join-sheet-new-$tone")
        rule.onNodeWithText("已有的 station").performClick()
        h.settle()
        rule.onNodeWithText("Acme · 在线").assertIsDisplayed()
        rule.onNodeWithText("该机器上的 agent 以同一系统用户运行", substring = true).assertIsDisplayed()
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
        rule.onNodeWithText("「box」已加入此 workspace").assertIsDisplayed()
        picture(h, "join-sheet-joined-$tone")
        rule.runOnUiThread { h.app.sheet = null }
        h.settle()

        // None to add: no choice, the sheet as it was.
        rule.runOnUiThread { h.fake.put(Topics.joinable(ws), JoinableView(offered = true, loading = false, items = emptyList())) }
        openSheet(h)
        assertEquals(0, rule.onAllNodesWithText("已有的 station").fetchSemanticsNodes().size)
        rule.runOnUiThread { h.app.sheet = null }
        h.settle()

        // Its page in its home workspace: the workspaces it is in.
        rule.runOnUiThread { h.app.push(Screen.Station("$ws/studio")) }
        h.settle()
        rule.onNodeWithText("加入的 workspace").assertIsDisplayed()
        picture(h, "join-page-workspaces-$tone")

        // A joined station's page: where it is at home, under its name; no workspaces of its own here.
        rule.runOnUiThread { h.app.pop(); h.app.push(Screen.Station("$ws/mini")) }
        h.settle()
        assertTrue(rule.onAllNodesWithText("来自 Acme", substring = true).fetchSemanticsNodes().isNotEmpty())
        picture(h, "join-page-joined-$tone")
    }

    /** Many to pick from: the choice stays at the top and the actions under the list; only the list scrolls. */
    @Test fun longList() {
        val many = (1..14).map { JoinableStation(station = "ws-acme/m$it", id = "m$it", name = "machine $it", workspace = "ws-acme", workspaceName = "Acme", online = false, line = "Acme · 离线") }
        val h = start(false, JoinableView(offered = true, loading = false, items = many))
        openSheet(h)
        rule.onNodeWithText("已有的 station").performClick()
        h.settle()
        rule.onNodeWithText("新机器").assertIsDisplayed()
        join().assertIsDisplayed()
        picture(h, "join-sheet-long-light")
        rule.onNodeWithText("machine 14").performScrollTo()
        h.settle()
        rule.onNodeWithText("新机器").assertIsDisplayed()
        join().assertIsDisplayed()
        picture(h, "join-sheet-long-scrolled-light")
    }

    /** One who manages no other workspace: no choice, the sheet as it was. */
    @Test fun notOffered() {
        val h = start(false, JoinableView(offered = false, loading = false, items = emptyList()))
        openSheet(h)
        assertEquals(0, rule.onAllNodesWithText("已有的 station").fetchSemanticsNodes().size)
    }

    // ── a profile opened to a joined workspace ──

    private val home = "$ws/studio"

    private fun profile(workspaces: List<String>?) = Profile(
        id = "p1", name = "zzj-max", email = "zzj@example.com", runtime = "claude", runtimes = listOf("claude"), access = Access(kind = "subscription", key = ""),
        home = "/Users/zzj/.stillfail/profiles/p1", homeExists = true, models = listOf("opus"), env = emptyList(), usedBy = emptyList(), loginCommand = "",
        checkText = "可用", checkTone = "green", makers = emptyMap(), names = emptyMap(), series = emptyList(), modelsText = "1 个模型", workspaces = workspaces,
    )

    private fun overview(profiles: List<Profile>) = Overview(
        viewer = Viewer("direct"), connects = emptyList(), profiles = profiles, processes = emptyList(), counts = Counts(0, 0, 0),
        slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
    )

    private fun lab(manages: Boolean) = MembershipsView(
        manages = manages, loading = false, canJoin = true, workspaces = listOf(
            StationMembership(workspace = ws, name = "Dev", stationName = "studio", home = true, here = true, line = "主 workspace"),
            StationMembership(workspace = "lab", name = "Lab", stationName = "studio", home = false, here = false, line = "加入的 workspace"),
        ),
    )

    private fun profilePage(dark: Boolean, manages: Boolean, workspaces: List<String>?): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.workspace(ws), WorkspaceView(id = ws, name = "Dev", role = "owner"))
        h.fake.put(Topics.memberships(home), lab(manages))
        h.launch(listOf(Screen.Stations, Screen.Station(home), Screen.Profile(home, "p1")), dark)
        rule.runOnUiThread { h.fake.put(Topics.stations(ws), listOf(station("studio", "studio").copy(overview = overview(listOf(profile(workspaces)))))) }
        h.settle()
        return h
    }

    private fun showsProfile(dark: Boolean) {
        val h = profilePage(dark, manages = true, workspaces = null)
        // Off: a switch for Lab, its chats not on this account.
        rule.onNodeWithText("同时用于 Lab").assertIsDisplayed()
        rule.onNodeWithText("Lab 中的对话无法使用此账号").assertIsDisplayed()
        // A tap opens it to Lab: profile.put with the whole list.
        rule.onNodeWithText("同时用于 Lab").performClick()
        h.settle()
        val (_, params) = h.fake.calls.last { it.first == "profile.put" }
        assertEquals(home, params["station"]!!.jsonPrimitive.content)
        assertEquals("p1", params["id"]!!.jsonPrimitive.content)
        assertEquals(listOf("lab"), params["input"]!!.jsonObject["workspaces"]!!.jsonArray.map { it.jsonPrimitive.content })
        // Open to Lab (as the station says once it has it): on, and a tap would close it again.
        rule.runOnUiThread { h.fake.put(Topics.stations(ws), listOf(station("studio", "studio").copy(overview = overview(listOf(profile(listOf("lab"))))))) }
        h.settle()
        rule.onNodeWithText("Lab 中的对话可使用此账号运行 agent").assertIsDisplayed()
        rule.onNodeWithText("同时用于 Lab").performScrollTo()
        h.settle()
        picture(h, "join-profile-workspaces-${if (dark) "dark" else "light"}")
        rule.onNodeWithText("同时用于 Lab").performClick()
        h.settle()
        val (_, closing) = h.fake.calls.last { it.first == "profile.put" }
        assertEquals(emptyList<String>(), closing["input"]!!.jsonObject["workspaces"]!!.jsonArray.map { it.jsonPrimitive.content })
    }

    @Test fun profileWorkspacesLight() = showsProfile(false)
    @Test fun profileWorkspacesDark() = showsProfile(true)

    /** Not its home's manager: no switches (the core says so with `manages`). */
    @Test fun profileWorkspacesNotManaged() {
        profilePage(false, manages = false, workspaces = null)
        rule.onNodeWithText("同时用于 Lab").assertDoesNotExist()
    }

    // ── a new chat on a joined station with no profile open to this workspace ──

    private val shared = "Studio 属于 Lab，其 Profile 尚未对此 workspace 开放：请 Lab 的管理员在 Profile 页开启「同时用于 Acme」"

    private fun notShared(dark: Boolean) {
        val joined = station("lab-studio", "Studio", joined = true, home = "Lab").copy(overview = overview(emptyList()))
        val h = Harness(rule)
        // The machine has sessions of its own: offered elsewhere, not here.
        h.fake.answer = { name, _ ->
            if (name == "machineSessions.list") buildJsonObject { putJsonArray("sessions") { add(buildJsonObject { put("runtime", "claude"); put("id", "s1"); put("cwd", "/Users/zzj/x"); put("updatedAt", Fixtures.NOW) }) } }
            else JsonNull
        }
        val view = NewChatView(
            kept = joined.station, stations = listOf(joined), any = true, station = joined, efforts = emptyList(), accounts = emptyList(),
            pickAccount = false, waiting = false, blocked = "shared", problem = shared,
        )
        h.fake.put(Topics.newChat(ws), view)
        h.launch(listOf(Screen.Home, Screen.NewChat), dark)
        rule.runOnUiThread { Drafts.of(rule.activity, h.fake.core, "new:${joined.station}").files.clear() }
        rule.runOnUiThread { h.fake.put(Topics.stations(ws), listOf(joined)) }
        h.settle()
        rule.onNodeWithText(shared).assertIsDisplayed()
        rule.onNodeWithText("添加 Profile").assertDoesNotExist()
        rule.onNodeWithText("继续 Studio 终端中的会话").assertDoesNotExist()
        picture(h, "join-new-chat-not-shared-${if (dark) "dark" else "light"}")
        // The same page with a profile open: the machine's sessions are offered (so their absence above is the block's).
        rule.runOnUiThread { h.fake.put(Topics.newChat(ws), view.copy(blocked = null, problem = null)) }
        h.settle()
        rule.onNodeWithText("继续 Studio 终端中的会话").assertIsDisplayed()
    }

    @Test fun newChatNotSharedLight() = notShared(false)
    @Test fun newChatNotSharedDark() = notShared(true)
}
