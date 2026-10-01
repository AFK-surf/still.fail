package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import fail.still.android.Screen
import fail.still.android.ui.Icons
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.screens.openAttach
import org.junit.Rule
import org.junit.Test

/** First mount, dismissal and an interrupted dismissal, on the real overlay hosts. */
class MenuMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    @Test fun light() = menus(false)
    @Test fun dark() = menus(true)

    private fun menus(dark: Boolean) {
        val h = Harness(rule)
        h.launch(listOf(Screen.Home), dark)
        val theme = if (dark) "dark" else "light"
        fun menu(bottom: Boolean = false) = MenuSpec(
            Rect(600f, if (bottom) 2100f else 200f, 680f, if (bottom) 2160f else 260f),
            listOf(MenuItem("全部", Icons.Check) {}, MenuItem("我参与的", null) {}, MenuItem("监控中", null) {}),
        )
        val open = h.record("$theme-menu-open")
        open.frame { rule.runOnUiThread { h.app.menu = menu() } }
        open.frames(40)
        open.end()
        val close = h.record("$theme-menu-close")
        close.frame { rule.runOnUiThread { h.app.menu = null } }
        close.frames(40)
        close.end()
        val again = h.record("$theme-menu-reopen")
        again.frame { rule.runOnUiThread { h.app.menu = menu(true) } }
        again.frames(5)
        again.frame { rule.runOnUiThread { h.app.menu = null } }
        again.frames(4)
        again.frame { rule.runOnUiThread { h.app.menu = menu(true) } }
        again.frames(40)
        again.end()
        rule.runOnUiThread { h.app.menu = null }
        h.settle()
        val sheet = h.record("$theme-sheet-open")
        sheet.frame { rule.runOnUiThread { openAttach(h.app, Triple({}, {}, {})) } }
        sheet.frames(60)
        sheet.end()
        val down = h.record("$theme-sheet-close")
        down.frame { rule.runOnUiThread { h.app.sheet = null } }
        down.frames(60)
        down.end()
    }
}
