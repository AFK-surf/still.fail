// A Mac station's grants on its page (screens/StationPermissions.kt, docs/remote-screens.md "Grants"): what each row
// ends with as the grant stands (given, its window up with the screen drivable or not, to ask for, not given to a
// member who may not ask); 申请 asks the core (`permissions.request`) and, the window up and the screen drivable,
// opens the screen viewer on the desktop in the same tap; a station that says nothing of grants shows no section.
// Pictured as station-perms-<state>-<light|dark>/settled.png.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.swipeUp
import fail.still.android.Screen
import fail.still.android.data.Counts
import fail.still.android.data.Overview
import fail.still.android.data.StationGrant
import fail.still.android.data.StationPermissions
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class StationPermissionsTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val opened = CopyOnWriteArrayList<Triple<String, String, String?>>()
    private val desktop = "/w/${Fixtures.WS}/s/st/screen/desktop"

    private fun grant(id: String, name: String, line: String, granted: Boolean = false, asking: Boolean = false) = StationGrant(id, name, line, granted, asking)

    private val capture = grant("capture", "屏幕录制", "远程查看此屏幕，agent 截屏", granted = true)
    private val control = grant("control", "辅助功能", "远程控制此屏幕，agent 操作屏幕")
    private val documents = grant("documents", "文稿", "在「文件」中访问文稿")
    private val desktopFolder = grant("desktop", "桌面", "在「文件」中访问桌面", granted = true)
    private val downloads = grant("downloads", "下载", "在「文件」中访问下载，接收拖入屏幕的文件", granted = true)
    private val removable = grant("removable", "外接磁盘", "在「文件」中访问外接磁盘")
    private val askingHere = "授权窗口已在该 Mac 上打开，可在远程屏幕中点击「允许」"
    private val askingThere = "授权窗口已在该 Mac 上打开，请在该 Mac 上点击「允许」"

    private fun station(p: StationPermissions?) = Fixtures.station.copy(
        overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "", permissions = p,
        ),
    )

    private fun launch(p: StationPermissions?, dark: Boolean = false, answer: (String) -> JsonElement = { JsonNull }): Harness {
        val h = Harness(rule)
        h.fake.answer = { name, _ -> if (name == "permissions.request") answer(name) else JsonNull }
        h.launch(listOf(Screen.Home, Screen.Station(Fixtures.STATION)), dark)
        h.app.openScreen = { station, screen, title -> opened += Triple(station, screen, title) }
        // Harness.launch puts the station without its overview: with it again, once the app is up.
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station(p))) }
        h.settle()
        return h
    }

    private fun picture(h: Harness, name: String, last: String) {
        rule.onNodeWithText(last).performScrollTo().assertIsDisplayed()
        // To the page's end: the footnote clear of the screen's edge.
        rule.onRoot().performTouchInput { swipeUp() }
        h.settle()
        h.record(name).run { frame(); end() }
    }

    private val missing = StationPermissions(
        grants = listOf(capture, control, documents, desktopFolder, downloads, removable),
        note = "当前不可用：远程控制屏幕、访问文稿、访问外接磁盘", screen = desktop, canRequest = true,
    )

    private fun requests(h: Harness) = h.fake.calls.filter { it.first == "permissions.request" }.map { it.second["station"]!!.jsonPrimitive.content to it.second["grant"]!!.jsonPrimitive.content }

    @Test fun everyGrantGiven() {
        launch(StationPermissions(grants = listOf(capture, desktopFolder, downloads), canRequest = true))
        rule.onNodeWithText("下载").performScrollTo().assertIsDisplayed()
        rule.onAllNodesWithText("已允许").assertCountEquals(3)
        rule.onAllNodesWithText("申请").assertCountEquals(0)
    }

    @Test fun someMissingAreAskedForAndTheDesktopOpens() {
        val h = launch(missing) { buildJsonObject { put("window", "up"); put("screen", true) } }
        rule.onNodeWithText(missing.note!!).performScrollTo().assertIsDisplayed()
        rule.onAllNodesWithText("已允许").assertCountEquals(3)
        rule.onAllNodesWithText("申请").assertCountEquals(3)
        rule.onNodeWithContentDescription("申请「辅助功能」").performScrollTo().performClick()
        rule.waitUntil(5_000) { opened.isNotEmpty() }
        assertEquals(listOf(Fixtures.STATION to "control"), requests(h))
        assertEquals(listOf(Triple(Fixtures.STATION, "desktop", "studio")), opened.toList())
    }

    @Test fun askedForWithoutTheScreenOpensNothing() {
        val h = launch(missing.copy(screen = null)) { buildJsonObject { put("window", "up"); put("screen", false) } }
        rule.onNodeWithContentDescription("申请「文稿」").performScrollTo().performClick()
        rule.waitUntil(5_000) { requests(h).isNotEmpty() }
        h.settle()
        assertEquals(listOf(Fixtures.STATION to "documents"), requests(h))
        assertTrue(opened.isEmpty())
    }

    @Test fun askingWithTheScreenOpensIt() {
        launch(missing.copy(grants = listOf(capture, control.copy(line = askingHere, asking = true), documents)))
        rule.onNodeWithText(askingHere).performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("打开屏幕").performClick()
        rule.waitUntil(5_000) { opened.isNotEmpty() }
        assertEquals(listOf(Triple(Fixtures.STATION, "desktop", "studio")), opened.toList())
    }

    @Test fun askingWithoutTheScreenWaits() {
        launch(missing.copy(grants = listOf(capture, control.copy(line = askingThere, asking = true), documents), screen = null))
        rule.onNodeWithText(askingThere).performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("等待允许").assertIsDisplayed()
        rule.onAllNodesWithText("打开屏幕").assertCountEquals(0)
        rule.onAllNodesWithText("申请").assertCountEquals(1)
    }

    @Test fun aReadOnlyMemberSeesWhatIsMissing() {
        launch(missing.copy(canRequest = false))
        rule.onNodeWithText(missing.note!!).performScrollTo().assertIsDisplayed()
        rule.onAllNodesWithText("未允许").assertCountEquals(3)
        rule.onAllNodesWithText("申请").assertCountEquals(0)
    }

    @Test fun aStationWithoutGrantsShowsNone() {
        launch(null)
        rule.onNodeWithText("Profile").assertExists()
        rule.onAllNodesWithText("权限").assertCountEquals(0)
    }

    // One launch a test (a test's content is set once): each state light and dark.
    private val waiting get() = missing.copy(grants = listOf(capture, control.copy(line = askingThere, asking = true), documents, desktopFolder, downloads, removable), screen = null)
    private val asking get() = missing.copy(grants = listOf(capture, control.copy(line = askingHere, asking = true), documents, desktopFolder, downloads, removable))

    private fun pictured(state: String, p: StationPermissions, dark: Boolean) {
        val h = launch(p, dark)
        picture(h, "station-perms-$state-${if (dark) "dark" else "light"}", p.note!!)
    }

    @Test fun picturedMissingLight() = pictured("missing", missing, false)
    @Test fun picturedMissingDark() = pictured("missing", missing, true)
    @Test fun picturedWaitingLight() = pictured("waiting", waiting, false)
    @Test fun picturedWaitingDark() = pictured("waiting", waiting, true)
    @Test fun picturedAskingLight() = pictured("asking", asking, false)
    @Test fun picturedAskingDark() = pictured("asking", asking, true)
    @Test fun picturedReadOnlyLight() = pictured("readonly", missing.copy(canRequest = false), false)
    @Test fun picturedReadOnlyDark() = pictured("readonly", missing.copy(canRequest = false), true)
}
