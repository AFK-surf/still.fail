// A station's 共享调试 while it waits to be paired (screens/AdbShare.kt): the pairing section, its first row asking for
// the reader that fills the code in by itself (AdbCodeReader), off on a phone that has not turned it on.
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import fail.still.android.Screen
import fail.still.android.data.AdbShareView
import fail.still.android.data.Topics
import org.junit.Rule
import org.junit.Test

class AdbShareTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    @Test fun pairingAsksForTheReader() {
        val h = Harness(rule)
        h.fake.put(Topics.adbShare, AdbShareView(sharing = true, station = Fixtures.STATION, phase = "offered", adb = "unpaired", tunnels = 0u, connectPort = 37123u, pairPort = 41234u))
        h.launch(listOf(Screen.Home, Screen.AdbShare(Fixtures.STATION)))
        rule.onNodeWithText("自动填配对码").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("前往开启").assertIsDisplayed()
        rule.onNodeWithText("打开配对窗口").assertIsDisplayed()
        val shot = h.record("adb-pairing")
        shot.frame()
        shot.end()
    }
}
