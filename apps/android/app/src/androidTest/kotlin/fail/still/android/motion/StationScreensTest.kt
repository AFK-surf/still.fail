// Where the screen viewer is opened from (docs/remote-screens.md): the station's page lists its screens (the `screens`
// topic), a row each opening the viewer; a station from before screens says so in a quiet row; a screen's link (in a
// chat, or an App Link) opens the viewer as `link.parse` says. Pictured as station-screens/settled.png.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import fail.still.android.Screen
import fail.still.android.data.LinkTarget
import fail.still.android.data.ScreenAccess
import fail.still.android.data.ScreenItem
import fail.still.android.data.ScreensView
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.encodeToJsonElement
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class StationScreensTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val opened = CopyOnWriteArrayList<Triple<String, String, String?>>()

    private fun launch(view: ScreensView): Harness {
        val h = Harness(rule)
        h.fake.put(Topics.screens(Fixtures.STATION), view)
        h.launch(listOf(Screen.Home, Screen.Station(Fixtures.STATION)))
        h.app.openScreen = { station, screen, title -> opened += Triple(station, screen, title) }
        return h
    }

    @Test fun theStationsScreensOpenTheViewer() {
        val h = launch(ScreensView(
            screens = listOf(
                ScreenItem("desktop", "desktop", "这台 Mac", 3024u, 1964u, line = "桌面 · 3024×1964 · 只能看：在 辅助功能 里打开 stillfail-station", link = "/w/ws-motion/s/st/screen/desktop",
                    access = ScreenAccess(capture = true, control = false, message = "在 辅助功能 里打开 stillfail-station")),
                ScreenItem("browser:1", "browser", "still.fail — 登录", 1280u, 800u, viewers = listOf("李雷"), line = "浏览器标签页 · 李雷在看", link = "/w/ws-motion/s/st/screen/browser%3A1"),
            ),
            outdated = false, control = true, known = true,
        ))
        rule.onNodeWithText("still.fail — 登录").performScrollTo().assertIsDisplayed()
        h.record("station-screens").run { frame(); end() }
        rule.onNodeWithText("still.fail — 登录").performClick()
        h.settle()
        assertEquals(listOf(Triple(Fixtures.STATION, "browser:1", "still.fail — 登录")), opened.toList())
    }

    @Test fun aStationFromBeforeScreensSaysSo() {
        launch(ScreensView(screens = emptyList(), outdated = true, control = true, known = true, note = "这台 station 版本太旧，更新后才能看屏幕"))
        rule.onNodeWithText("这台 station 版本太旧，更新后才能看屏幕").performScrollTo().assertIsDisplayed()
    }

    @Test fun aScreensLinkOpensTheViewer() {
        val h = launch(ScreensView(screens = emptyList(), outdated = false, control = true, known = false))
        h.fake.answer = { name, _ ->
            if (name == "link.parse") StillFailJson.encodeToJsonElement(LinkTarget(opens = "screen", workspace = Fixtures.WS, station = "st", screen = "browser:1"))
            else kotlinx.serialization.json.JsonNull
        }
        rule.runOnUiThread { h.app.openLink("https://app.still.fail/w/ws-motion/s/st/screen/browser%3A1") }
        rule.waitUntil(5_000) { opened.isNotEmpty() }
        assertEquals(Triple(Fixtures.STATION, "browser:1", null), opened.single())
    }
}
