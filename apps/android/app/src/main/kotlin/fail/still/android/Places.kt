// The places of the phone's bottom bar (ui/Bar.kt): which page each is, what it looks like, and the bar as the app
// wires it (the core keeps the bars whole in the device's prefs, `bars`: client/core-ts/src/prefs.ts barsOf).
package fail.still.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import fail.still.android.data.BarPrefs
import fail.still.android.data.ChatsView
import fail.still.android.data.StatusView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.data.AccountWorkspaces
import fail.still.android.ui.BarAction
import fail.still.android.ui.BarWorkspace
import fail.still.android.ui.BottomBar
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.StationGlyph
import fail.still.android.ui.glyphCounts

/** Every place a bar can hold, in the order the picker lists them (the core's BAR_PLACES). */
val PLACES = listOf("chats", "decisions", "files", "stations", "profiles", "connects", "usage", "archive")

/** At most this many places in one bar (the core's BAR_SIZE). */
const val BAR_SIZE = 4

/** The chats' family: on their pages 令 (a new chat) stands in the bar's notch; the other places' pages say theirs (PlaceAction). */
val CHAT_FAMILY = setOf("chats", "decisions", "archive")

/** The bars before the core has said (the core's BARS_DEFAULT). */
val DEFAULT_BARS = BarPrefs(listOf(listOf("chats", "files", "profiles", "stations"), listOf("decisions", "usage", "connects", "archive")), 0)

/**
 * The bars whole, as the core keeps them (barsOf): each bar one to four known places, none twice; empty bars dropped;
 * none left, the default ones; the one in view one of them.
 */
fun barsOf(sets: List<List<String>>, current: Int): BarPrefs {
    val kept = sets.map { set -> set.filter { it in PLACES }.distinct().take(BAR_SIZE) }.filter { it.isNotEmpty() }
    if (kept.isEmpty()) return DEFAULT_BARS
    return BarPrefs(kept, current.coerceIn(0, kept.size - 1).toLong())
}

/** The place a page is the top of (null: it is not a place's): the workspace's profiles and connects, not a station's. */
fun placeOf(screen: Screen): String? = when (screen) {
    Screen.Home -> "chats"
    Screen.Decisions -> "decisions"
    Screen.Files -> "files"
    Screen.Stations -> "stations"
    is Screen.Profiles -> if (screen.station == null) "profiles" else null
    is Screen.Connects -> if (screen.station == null) "connects" else null
    Screen.Usage -> "usage"
    Screen.Archive -> "archive"
    else -> null
}

/** A place's page. */
fun screenOf(place: String): Screen = when (place) {
    "decisions" -> Screen.Decisions
    "files" -> Screen.Files
    "stations" -> Screen.Stations
    "profiles" -> Screen.Profiles()
    "connects" -> Screen.Connects()
    "usage" -> Screen.Usage
    "archive" -> Screen.Archive
    else -> Screen.Home
}

/** A place's name (the settings' cards, the picker, what a screen reader says on the bar). */
fun placeLabel(place: String): String = t("android-misc.bar.place.$place")

/**
 * What a page is to the bar: not a place's top (`None`); a place's top with the bar under it (`Bar`: no back, room at
 * its foot for the bar); a place's top on a wide screen, which has no bar (`Wide`: its back goes to the chats).
 */
enum class PlaceRoot { None, Bar, Wide }

val LocalPlaceRoot = compositionLocalOf { PlaceRoot.None }

/** The room a place's top page keeps at its foot (over the navigation bar) for the bar to float over: none without it. */
val LocalBarRoom = compositionLocalOf { 0.dp }

/**
 * The bar's height, its distance from the foot (over the navigation bar), a little air over it, and the action in its
 * notch, which stands 32 over the bar (ui/Bar.kt: half of it, and its lift): what a page keeps clear. Every place's page
 * keeps it, with an action or not, so nothing moves as one comes and goes.
 */
val BAR_ROOM: Dp = (56 + 22 + 16 + 32).dp

/** A place's icon, 28 as the bar draws them. */
@Composable
fun PlaceIcon(place: String, tint: Color, glyph: fail.still.android.ui.GlyphCounts?) {
    when (place) {
        "stations" -> if (glyph != null) StationGlyph(glyph, 28.dp, tint) else IconIn(Icons.Server, 28.dp, tint)
        else -> IconIn(placeIcon(place), 28.dp, tint)
    }
}

/**
 * A place's top page says its primary action (null: none) for the bar's notch (PlaceBar), while it is the bar's page; on
 * the chats' pages it is always 令. Kept once said, by workspace and place, so coming back to a place the notch is as it
 * will be at once. `known` false: what decides it is not read yet, and the notch stays as it is meanwhile, rather than
 * closing only to open again.
 */
@Composable
fun PlaceAction(workspace: String, place: String, action: BarAction?, known: Boolean = true) {
    val app = LocalApp.current
    if (LocalPlaceRoot.current != PlaceRoot.Bar || place in CHAT_FAMILY) return
    SideEffect {
        if (!known) return@SideEffect
        val key = "$workspace|$place"
        val was = app.placeActions[key]
        // The same action: its latest doing, nothing for the bar to redraw.
        if (action != null && was != null && was.key == action.key && was.label == action.label) was.run = action.run
        else if (was != action || key !in app.placeActions) app.placeActions[key] = action
    }
}

private fun placeIcon(place: String) = when (place) {
    "chats" -> Icons.Chats
    "decisions" -> Icons.Zou
    "files" -> Icons.Folder
    "profiles" -> Icons.Quota
    "connects" -> Icons.Im
    "usage" -> Icons.Chart
    "archive" -> Icons.Archive
    else -> Icons.Server
}

/**
 * The bottom bar on the pages of `current` (App.kt Pages): shown on a place's top page with nothing over it; its dots
 * as Home and Settings say them (奏 waiting for the viewer, a station in trouble). With more than one workspace, the
 * panel's top row is them, as the switcher lists them (screens/Workspaces.kt), with what each has waiting; one chosen
 * there is switched to on the place shown.
 */
@Composable
fun PlaceBar(app: AppState, current: WorkspaceEntry, haze: HazeState, shown: Boolean) {
    val ws = current.workspace.id
    val bars = app.bars
    val root = app.stack.first()
    val active = placeOf(root)
    val marks by rememberTopic<fail.still.android.data.WorkspaceMarksView>(app.core, Topics.workspaceMarks(ws))
    val decisions = marks.value?.workspaces?.get(ws)?.decisions?.toInt() ?: 0
    val chats by rememberTopic<ChatsView>(app.core, Topics.chats(ws, false))
    val status by rememberTopic<StatusView>(app.core, Topics.status(ws))
    val glyph = glyphCounts(chats.value, status.value?.state == "trouble")
    // The stations in trouble as the core says it (web mobile/Bar.tsx the same); in words, what Home's corner said.
    val trouble = chats.value?.trouble
    val said = if (glyph.asleep) status.value?.text.orEmpty() else chats.value?.glyph?.label.orEmpty()
    val stationsSaid = trouble?.let { t("android-chat.home.stations.trouble", "said" to said, "trouble" to it.text) } ?: t("android-chat.home.stations", "said" to said)
    val accent = C.accent
    val red = C.red
    val dots = buildMap {
        if (decisions > 0) put("decisions", accent)
        if (trouble != null) put("stations", red)
    }
    // The notch's action: 令 on the chats' pages, else what the place's page said (PlaceAction); a page not drawn yet
    // that has not said, the notch as it was until it does (from 令 to a "+", it stays open), a second at most.
    val lingLabel = t("android-chat.newChat")
    val ling = remember(lingLabel) { BarAction("ling", lingLabel, Icons.Ling) { app.push(Screen.NewChat) } }
    val actions = app.placeActions
    val held = remember { arrayOf<BarAction?>(null) }
    val all by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    val workspaces = all.value.orEmpty().flatMap { it.workspaces }.distinctBy { it.id }.map { w ->
        val m = marks.value?.workspaces?.get(w.id)
        BarWorkspace(w.id, w.name, w.emoji, w.icon, m?.tone, m?.label)
    }
    var waited by remember(ws, active) { mutableStateOf(false) }
    LaunchedEffect(ws, active) { delay(1000); waited = true }
    val action = when {
        active == null -> null
        active in CHAT_FAMILY -> ling
        "$ws|$active" in actions -> actions["$ws|$active"]
        waited -> null
        else -> held[0]
    }
    held[0] = action
    BottomBar(
        sets = bars.sets, cur = bars.current.toInt(), active = active, action = action, shown = shown,
        haze = haze, dots = dots, labelOf = { key -> if (key == "stations" && said.isNotEmpty()) stationsSaid else placeLabel(key) },
        notches = { place -> place in CHAT_FAMILY || actions["$ws|$place"] != null },
        icon = { place, tint -> PlaceIcon(place, tint, glyph) },
        onTab = { place -> if (app.stack.size == 1) app.place(screenOf(place)) },
        onSwitch = { i, place ->
            val now = app.bars
            app.setBars(now.sets, i)
            // Only from a place's top: a page pushed meanwhile (a notification opened) stays.
            if (place != null && app.stack.size == 1 && placeOf(app.stack.first()) != place) app.place(screenOf(place))
        },
        workspaces = workspaces, workspace = ws,
        // The place shown stays, in the workspace chosen.
        onWorkspace = { id -> app.pickWorkspace(id) },
        workspaceLabel = { w -> listOfNotNull(t("android-misc.bar.workspace", "name" to w.name), w.label?.takeIf { w.id != ws }).joinToString(" · ") },
    )
}
