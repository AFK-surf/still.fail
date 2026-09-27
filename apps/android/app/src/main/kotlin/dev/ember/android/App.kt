// The app: signed out it is the sign-in page; signed in, the chats of one
// workspace are home, and everything else is a page pushed over it (no tab
// bar), or a sheet from the bottom.
package dev.ember.android

import dev.ember.android.ui.Splash
import androidx.compose.ui.unit.IntOffset
import androidx.compose.animation.core.FastOutSlowInEasing
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.HazeState
import android.content.SharedPreferences
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.CubicBezierEasing
import dev.ember.android.data.AccountWorkspaces
import dev.ember.android.data.Account
import dev.ember.android.data.ChatOf
import dev.ember.android.data.StationApi
import dev.ember.android.data.Topics
import dev.ember.android.data.entries
import dev.ember.android.data.rememberTopic
import dev.ember.android.screens.ChatScreen
import dev.ember.android.screens.HomeScreen
import dev.ember.android.screens.ProfileScreen
import dev.ember.android.screens.Landing
import dev.ember.android.screens.MeScreen
import dev.ember.android.screens.NewChatScreen
import dev.ember.android.screens.SignInScreen
import dev.ember.android.screens.StationScreen
import dev.ember.android.screens.StationsScreen
import dev.ember.android.ui.C
import dev.ember.android.ui.Loading
import dev.ember.android.ui.MenuHost
import dev.ember.android.ui.ReaderHost
import dev.ember.android.ui.ReaderSpec
import dev.ember.android.ui.SheetHost
import dev.ember.android.ui.SheetSpec
import dev.ember.android.ui.MenuSpec
import dev.ember.android.ui.ToastHost
import dev.ember.core.EmberCore
import kotlinx.coroutines.MainScope

sealed interface Screen {
    val id: String
    data object Home : Screen { override val id = "home" }
    /** An item's page: its chat, or its agent before it has one. */
    data class Chat(val station: String, val of: ChatOf) : Screen {
        override val id = "chat/$station/" + when (of) { is ChatOf.Thread -> of.id.toString(); is ChatOf.Session -> of.key }
    }
    /** Rises from the bottom rather than coming in from the side. */
    data object NewChat : Screen { override val id = "new" }
    data object Stations : Screen { override val id = "stations" }
    data class Station(val address: String) : Screen { override val id = "station/$address" }
    /** How an agent runs, changed: its model, how hard it thinks, who runs it. */
    data class RunSettings(val station: String, val of: ChatOf, val key: String) : Screen { override val id = "run/$station/$key" }
    /** A profile's models, to pick which may be used. */
    data class Profile(val address: String, val profile: String) : Screen { override val id = "profile/$address/$profile" }
    data object Me : Screen { override val id = "me" }
    /** A web service on a station's machine, full screen. */
    data class Preview(val station: String, val port: Int) : Screen { override val id = "preview/$station/$port" }
    /** The workspace itself: its name, its people, leaving it. */
    data object Workspace : Screen { override val id = "workspace" }
}

class AppState(val core: EmberCore, private val prefs: SharedPreferences, val cloudOrigin: String) {
    var stack by mutableStateOf(listOf<Screen>(Screen.Home)); private set
    /** Whether the last move went deeper, for the direction of the transition. */
    var forward by mutableStateOf(true); private set
    var sheet by mutableStateOf<SheetSpec?>(null)
    var menu by mutableStateOf<MenuSpec?>(null)
    var toast by mutableStateOf<String?>(null)
    /** One entry of an execution history in full, over everything (the sheet stays under it). */
    var reader by mutableStateOf<ReaderSpec?>(null)

    /** The workspace chosen last; the first one when it is gone. */
    var workspace by mutableStateOf(prefs.getString("workspace", null)); private set
    fun pickWorkspace(id: String) { workspace = id; prefs.edit().putString("workspace", id).apply() }

    /** 外观: "system" (the default), "light" or "dark", kept on the device. */
    var theme by mutableStateOf(prefs.getString("theme", null) ?: "system"); private set
    fun useTheme(value: String) { theme = value; prefs.edit().putString("theme", value).apply() }

    var onlyMine by mutableStateOf(prefs.getBoolean("onlyMine", false)); private set
    fun showOnlyMine(on: Boolean) { onlyMine = on; prefs.edit().putBoolean("onlyMine", on).apply() }

    fun flag(name: String, default: Boolean) = prefs.getBoolean(name, default)
    fun setFlag(name: String, on: Boolean) = prefs.edit().putBoolean(name, on).apply()
    fun strings(name: String): List<String> = prefs.getString(name, null)?.split('\u0000')?.filter { it.isNotEmpty() } ?: emptyList()
    fun setStrings(name: String, values: List<String>) = prefs.edit().putString(name, values.joinToString("\u0000")).apply()

    fun push(screen: Screen) { sheet = null; menu = null; forward = true; stack = stack + screen }
    fun pop() { if (stack.size > 1) { sheet = null; menu = null; forward = false; stack = stack.dropLast(1) } }
    /** The top page gives way to another (a new chat becomes the chat it made). */
    fun replace(screen: Screen) { sheet = null; forward = true; stack = stack.dropLast(1) + screen }
    fun home() { sheet = null; forward = false; stack = listOf(Screen.Home) }
    /** An item's link from outside: its workspace, and its page over the list (back goes to the list). */
    fun openItem(workspace: String, station: String, session: String) {
        pickWorkspace(workspace)
        sheet = null; menu = null; forward = true
        stack = listOf(Screen.Home, Screen.Chat("$workspace/$station", ChatOf.Session(session)))
    }

    fun api(station: String) = StationApi(core, station)
    /** For what outlives the page that started it (a message sent as the page moves to its new chat). */
    val scope = MainScope()

    /** Where each chat was left: the message at the top of the list and how far below the top it sat. */
    val places = HashMap<String, Pair<String, Int>>()
    /** The pages, as what a sheet over them frosts. */
    val haze = HazeState()
}

val LocalApp = staticCompositionLocalOf<AppState> { error("no app") }

private val Ease = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

@Composable
fun EmberApp(app: AppState) {
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val workspaces by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    Box(Modifier.fillMaxSize().background(C.bg)) {
        val signedIn = accounts.value
        Box(Modifier.fillMaxSize().hazeSource(app.haze).background(C.bg)) { when {
            signedIn == null -> Splash(accounts.error?.message, now = accounts.error != null)
            signedIn.isEmpty() -> SignInScreen()
            else -> {
                val entries = workspaces.value?.entries()
                val current = entries?.firstOrNull { it.workspace.id == app.workspace } ?: entries?.firstOrNull()
                LaunchedEffect(current?.workspace?.id) { current?.let { if (it.workspace.id != app.workspace) app.pickWorkspace(it.workspace.id) } }
                // Only once every account has answered does "no workspace" mean none: not before, not after a failure.
                val all = workspaces.value
                if (current == null) {
                    if (entries == null || all == null || !all.all { it.loaded }) {
                        val failed = workspaces.error?.message ?: all?.firstNotNullOfOrNull { it.error }?.let { "没能读取你的 workspace" }
                        Splash(failed ?: "正在读取你的 workspace…", now = failed != null)
                    }
                    else Landing(signedIn, all)
                } else {
                    Pages(app, current)
                }
            }
        } }
        // Pages scroll under the status bar; it keeps the paper behind its icons (the list and a chat have frosted bars
        // there instead, which show what runs under them).
        val top = app.stack.lastOrNull()
        if (top !is Screen.Home && top !is Screen.Chat) Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(C.bg))
        SheetHost(app)
        ReaderHost(app)
        MenuHost(app)
        ToastHost(app)
    }
}

@Composable
private fun Pages(app: AppState, current: dev.ember.android.data.WorkspaceEntry) {
    BackHandler(enabled = app.stack.size > 1 && app.sheet == null && app.menu == null) { app.pop() }
    val saved = rememberSaveableStateHolder()
    AnimatedContent(
        targetState = app.stack.last(),
        transitionSpec = { transition(initialState, targetState, app.forward) },
        label = "pages",
    ) { screen ->
        saved.SaveableStateProvider(screen.id) {
            Box(Modifier.fillMaxSize().background(C.bg)) {
                when (screen) {
                    Screen.Home -> HomeScreen(current)
                    is Screen.Chat -> ChatScreen(screen.station, screen.of)
                    Screen.NewChat -> NewChatScreen(current.workspace.id)
                    Screen.Stations -> StationsScreen(current)
                    is Screen.Station -> StationScreen(current, screen.address)
                    is Screen.Profile -> ProfileScreen(current, screen.address, screen.profile)
                    is Screen.RunSettings -> dev.ember.android.screens.RunSettingsScreen(screen.station, screen.of, screen.key)
                    Screen.Me -> MeScreen(current)
                    Screen.Workspace -> dev.ember.android.screens.WorkspaceScreen(current)
                    is Screen.Preview -> dev.ember.android.screens.PreviewScreen(screen.station, screen.port)
                }
            }
        }
    }
}

/**
 * Pages move side by side, as the list's two panes do when switched: the new one pushes in whole from the right and
 * the old goes out whole to the left (and back the other way), nothing fading. The viewer's own page is on the left
 * instead; a new chat rises from the bottom.
 */
private fun transition(from: Screen, to: Screen, forward: Boolean): ContentTransform {
    val time = 380
    val slide = tween<IntOffset>(300, easing = FastOutSlowInEasing)
    return when {
        forward && to == Screen.NewChat -> slideInVertically(tween(time, easing = Ease)) { it } togetherWith fadeOut(tween(time), 0.99f)
        !forward && from == Screen.NewChat -> fadeIn(tween(1), 0.99f) togetherWith slideOutVertically(tween(time, easing = Ease)) { it }
        // The viewer's own page is to the left of the list (its avatar is at the list's left): it comes and goes that way.
        forward && to == Screen.Me -> slideInHorizontally(slide) { -it } togetherWith slideOutHorizontally(slide) { it }
        !forward && from == Screen.Me -> slideInHorizontally(slide) { it } togetherWith slideOutHorizontally(slide) { -it }
        forward -> slideInHorizontally(slide) { it } togetherWith slideOutHorizontally(slide) { -it }
        else -> slideInHorizontally(slide) { -it } togetherWith slideOutHorizontally(slide) { it }
    }.apply { targetContentZIndex = if (forward) 1f else -1f }
}
