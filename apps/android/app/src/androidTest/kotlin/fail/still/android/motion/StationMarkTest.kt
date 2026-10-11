package fail.still.android.motion

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import fail.still.android.Screen
import fail.still.android.data.Link
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.screens.openStationMenu
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** A station's icon in a colour: shown in it where the station is named, and picked in its sheet. */
class StationMarkTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun station(name: String, emoji: String, icon: String) = StationView(
        station = "${Fixtures.WS}/$name", id = name, name = name, summary = "10 核 · 32 GB", face = "idle", online = true, link = Link("online"),
        runtimes = emptyList(), models = emptyList(), emoji = emoji, icon = icon,
    )

    @Test fun colourLight() = colour(false)
    @Test fun colourDark() = colour(true)

    private fun colour(dark: Boolean) {
        val theme = if (dark) "dark" else "light"
        val h = Harness(rule)
        h.launch(listOf(Screen.Stations), dark)
        val list = listOf(station("Studio", "🧠", "glyph:chip:purple"), station("Mini1", "🎲", "glyph:dice-1:blue"), station("Mini2", "🎲", "glyph:dice-2:blue"), station("ccvm", "🧊", "glyph:layers:teal"), station("test", "🐛", "glyph:bug"))
        rule.runOnUiThread { h.fake.put(Topics.stations(Fixtures.WS), list) }
        h.settle()
        h.record("mark-list-$theme").end()

        val current = WorkspaceEntry(Fixtures.workspaces[0].workspaces[0], Fixtures.account)
        rule.runOnUiThread { openStationMenu(h.app, current, list[1]) }
        h.settle()
        rule.onNodeWithText("图标").performClick()
        h.settle()
        h.record("mark-sheet-$theme").end()

        // It has an icon: a colour picked is its colour at once, and the sheet stays for another.
        rule.onNodeWithContentDescription("green").performClick()
        h.settle()
        assertEquals("glyph:dice-1:green", sent(h))
        h.record("mark-sheet-green-$theme").end()

        // Typed, a word finds the icons named by it (in Chinese too), and only those.
        rule.onNode(hasSetTextAction()).performTextInput("棋子")
        h.settle()
        rule.onNodeWithContentDescription("chess-knight").assertExists()
        rule.onNodeWithContentDescription("desktop").assertDoesNotExist()
        h.record("mark-sheet-search-$theme").end()

        // An icon picked is in the colour the sheet shows.
        rule.onNodeWithContentDescription("chess-knight").performScrollTo().performClick()
        h.settle()
        assertEquals("glyph:chess-knight:green", sent(h))
    }

    /** The icon last sent to the cloud. */
    private fun sent(h: Harness): String? = h.fake.calls.mapNotNull { Regex("\"(glyph:[^\"]+)\"").find(it.second.toString())?.groupValues?.get(1) }.lastOrNull()
}
