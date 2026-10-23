// A place's page (Places.kt: 文件, Station, Profile, 连接, 用量, 已归档, 奏) as the chats' list is one: with the bottom bar
// under it, Home's frosted top bar over it (settings, the page's name, its other actions), what it shows scrolling under
// that bar, and its primary action in the bar's notch. Pushed (from settings, the list's menu), it is a sub-page as any:
// back to the page under it, its name in the middle, its actions with its "+" at the right. No large title, no note
// under it either way.
package fail.still.android.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import fail.still.android.LocalApp
import fail.still.android.LocalPlaceRoot
import fail.still.android.PlaceAction
import fail.still.android.PlaceRoot
import fail.still.android.Screen
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.t
import fail.still.android.placeLabel
import fail.still.android.ui.BarAction
import fail.still.android.ui.C
import fail.still.android.ui.Icons
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.glass

/**
 * The top bars' height under the status bar: Home's and a place's (TopGlassBar) and a chat's (Chat.kt BarFrame),
 * what is in them in its middle. One length, on the device's pixels at once: 8 + 34 + 8dp and 5 + 40 + 5dp, each
 * rounded, can come out a pixel apart (at 2.85 pixels a dp, 143 and 142), the two bars' lines apart as a chat is swiped
 * back.
 */
val TopBarHeight = 50.dp

/** Home's top bar (and a place's): frosted over what `haze` is the source of, a hairline under it; its row of buttons. */
@Composable
fun TopGlassBar(haze: HazeState, modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) = Row(
    modifier.fillMaxWidth().glass(haze).windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp).heightIn(min = TopBarHeight),
    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), content = content,
)

/** Settings, at the top bar's left (SettingsHome.kt): the account, the workspace's things, this device's. */
@Composable
fun SettingsGear() {
    val app = LocalApp.current
    Box(Modifier.semantics { contentDescription = t("android-chat.home.settings") }) { NavButton(Icons.Settings, { app.push(Screen.Settings) }, 22.dp) }
}

/** The name in the top bar, as Home's workspace name is set. */
@Composable
fun TopBarTitle(text: String, modifier: Modifier = Modifier) =
    Text(text, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = modifier)

/** A page's "+" in its top bar (pushed, or on a wide screen: no bar to hold it), named as what it adds. */
@Composable
fun PlusButton(action: BarAction) {
    Box(Modifier.semantics { contentDescription = action.label }) { NavButton(action.icon, { action.run() }, 20.dp) }
}

/**
 * What the back of a pushed page says: the page under it, the chats or settings; `orElse` for any other (a station's).
 */
@Composable
private fun underLabel(orElse: String): String {
    val app = LocalApp.current
    val stack = app.stack
    return when (stack.getOrNull(stack.size - 2)) {
        Screen.Home -> placeLabel("chats")
        Screen.Settings -> t("android-settings.title")
        else -> orElse
    }
}

/**
 * A place's page. `place` is which (its name the title unless `title` says another); `primary` its main action (null:
 * none), in the bar's notch on the bar's page and the top bar's "+" otherwise; `known` false while what decides it is not
 * read (the notch stays as it is meanwhile). `actions`: the page's others, at the top bar's right (用量's days). `back`:
 * what the back of a pushed page says when the page under it is neither the chats nor settings. `content` gets the room
 * to keep at its top: what scrolls starts there, under the frosted bar.
 */
@Composable
fun PlacePage(
    current: WorkspaceEntry,
    place: String,
    primary: BarAction?,
    known: Boolean = true,
    title: String = placeLabel(place),
    back: String = t("android-settings.title"),
    actions: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable (top: Dp) -> Unit,
) {
    val app = LocalApp.current
    val root = LocalPlaceRoot.current
    PlaceAction(current.workspace.id, place, primary, known)
    if (root == PlaceRoot.Bar) {
        val haze = remember { HazeState() }
        val density = LocalDensity.current
        // Its height kept with the page's state (as Home's): coming back, what scrolls is laid out under it at once.
        val statusTop = WindowInsets.statusBars.getTop(density)
        var bar by rememberSaveable { mutableIntStateOf(statusTop + with(density) { 50.dp.roundToPx() }) }
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().hazeSource(haze)) { content(with(density) { bar.toDp() } + 8.dp) }
            TopGlassBar(haze, Modifier.align(Alignment.TopCenter).onSizeChanged { bar = it.height }) {
                SettingsGear()
                TopBarTitle(title, Modifier.weight(1f))
                actions?.invoke(this)
            }
        }
        return
    }
    // Pushed, or the top of a place on a wide screen (no bar there: back goes to the chats).
    val wide = root == PlaceRoot.Wide
    Column(Modifier.fillMaxSize()) {
        NavBar(
            if (wide) placeLabel("chats") else underLabel(back), { if (wide) app.place(Screen.Home) else app.pop() }, title,
            trailing = if (actions == null && primary == null) null else ({
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    actions?.invoke(this)
                    primary?.let { PlusButton(it) }
                }
            }),
        )
        Box(Modifier.weight(1f).fillMaxWidth()) { content(4.dp) }
    }
}
