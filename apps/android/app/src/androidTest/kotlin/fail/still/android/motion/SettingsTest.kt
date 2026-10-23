// Settings on a fake core (screens/SettingsHome.kt): the account's card and the workspace's, the workspace's rows in
// small groups each with its icon, this device's, and 关于 a row of its own whose page has this build, the changelog and
// the terms. Each state is pictured into the app's files (motion/settings-…).
package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import fail.still.android.BuildConfig
import fail.still.android.Screen
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class SettingsTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun shot(h: Harness, name: String) = h.record(name).also { it.frames(1); it.end() }

    private fun theme(dark: Boolean) = if (dark) "dark" else "light"

    @Test fun groupedLight() = grouped(false)
    @Test fun groupedDark() = grouped(true)

    /** The page from its top to its foot: the workspace's card under the account's, the groups, 关于 last with this build. */
    private fun grouped(dark: Boolean) {
        val h = Harness(rule)
        h.launch(listOf(Screen.Home, Screen.Settings), dark)
        rule.onNodeWithText("Dev").assertIsDisplayed()
        rule.onNodeWithText("Owner · 1 人").assertIsDisplayed()
        shot(h, "settings-top-${theme(dark)}")
        rule.onNodeWithText("关于").performScrollTo()
        h.settle()
        rule.onNodeWithText(BuildConfig.VERSION_NAME).assertIsDisplayed()
        shot(h, "settings-end-${theme(dark)}")
        rule.onNodeWithText("关于").performClick()
        h.settle()
        assertEquals(Screen.About, h.app.stack.last())
        rule.onNodeWithText("更新日志").assertIsDisplayed()
        rule.onNodeWithText("服务条款").assertIsDisplayed()
        shot(h, "settings-about-${theme(dark)}")
    }

    /** The workspace's card opens its page, as the Workspace row did. */
    @Test fun workspaceCard() {
        val h = Harness(rule)
        h.launch(listOf(Screen.Home, Screen.Settings))
        rule.onNodeWithText("Dev").performClick()
        h.settle()
        assertEquals(Screen.Workspace, h.app.stack.last())
    }
}
