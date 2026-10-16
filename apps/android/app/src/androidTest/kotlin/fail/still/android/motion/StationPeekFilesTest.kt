// A chat's station card (screens/Stations.kt openStationPeek) leads to the station's files where it has a drive, as the
// wide screen's card does: the row says how many folders it pins, and opens its drive. Pictured light and dark
// (settled.png under motion/station-peek-files-*).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Counts
import fail.still.android.data.DriveRoot
import fail.still.android.data.DriveRoots
import fail.still.android.data.Overview
import fail.still.android.data.Topics
import fail.still.android.data.Viewer
import fail.still.android.screens.openStationPeek
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class StationPeekFilesTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val station = Fixtures.station.copy(
        overview = Overview(
            viewer = Viewer("direct"), connects = emptyList(), profiles = emptyList(), processes = emptyList(), counts = Counts(0, 0, 0),
            slackUsers = emptyList(), slackTeams = emptyList(), logins = emptyList(), processesText = "",
            drive = DriveRoots(listOf(DriveRoot("/Users/alice/Downloads", "下载", "ok"), DriveRoot("/Users/alice/code/acme", "acme", "ok"))),
        ),
    )

    @Test fun light() = leads(false)
    @Test fun dark() = leads(true)

    private fun leads(dark: Boolean) {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk))
        h.launch(listOf(Screen.Home, Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))), dark = dark)
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), listOf(station)) }
        h.settle()
        rule.runOnUiThread { openStationPeek(h.app, Fixtures.STATION) }
        h.settle()
        rule.onNodeWithText("2 个文件夹", substring = true).assertExists()
        val shot = h.record(if (dark) "station-peek-files-dark" else "station-peek-files-light"); shot.frame(); shot.end()
        rule.onNodeWithText("文件").performClick()
        h.settle()
        rule.runOnIdle {
            assertEquals(null, h.app.sheet)
            assertEquals(Screen.Drive(Fixtures.STATION, null, ""), h.app.stack.last())
        }
    }
}
