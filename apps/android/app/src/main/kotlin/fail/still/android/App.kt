// The app: signed out it is the sign-in page; signed in, the chats of one
// workspace are home, and everything else is a page pushed over it (no tab
// bar), or a sheet from the bottom.
package fail.still.android

import fail.still.android.ui.Splash
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.CubicBezierEasing
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.Account
import fail.still.android.data.ChatOf
import fail.still.android.data.StationApi
import fail.still.android.data.Topics
import fail.still.android.data.entries
import fail.still.android.data.rememberTopic
import fail.still.android.screens.ChatScreen
import fail.still.android.screens.HomeScreen
import fail.still.android.screens.ProfileScreen
import fail.still.android.screens.Landing
import fail.still.android.screens.MeScreen
import fail.still.android.screens.NewChatScreen
import fail.still.android.screens.SignInScreen
import fail.still.android.screens.StationScreen
import fail.still.android.screens.StationsScreen
import fail.still.android.ui.C
import fail.still.android.ui.Loading
import fail.still.android.ui.MenuHost
import fail.still.android.ui.ReaderHost
import fail.still.android.ui.ReaderSpec
import fail.still.android.ui.SheetHost
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.ToastHost
import fail.still.core.StillFailCore
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
    /** A web service an agent started, full screen: by its job (people know it by its name, never its port). */
    data class Preview(val station: String, val job: String) : Screen { override val id = "preview/$station/$job" }
    /** A visualization an agent posted, as a page of its own in the preview (web mobile's 在侧边打开 on a phone). */
    data class PreviewFile(val station: String, val session: String, val path: String, val name: String) : Screen { override val id = "preview-file/$station/$session/$path" }
    /** The workspace itself: its name, its people, leaving it. */
    data object Workspace : Screen { override val id = "workspace" }
    /** A connect of a station; how it runs; a new one on a station. */
    data class Connect(val station: String, val connect: String) : Screen { override val id = "connect/$station/$connect" }
    data class ConnectRun(val station: String, val connect: String) : Screen { override val id = "connect-run/$station/$connect" }
    data class NewConnect(val station: String) : Screen { override val id = "new-connect/$station" }
    data class NewProfile(val station: String) : Screen { override val id = "new-profile/$station" }
    /** Chats archived, of every station online: put back in the list, or deleted for good. */
    data object Archive : Screen { override val id = "archive" }

    /** The agents' memory on a station. */
    data class Memory(val station: String) : Screen { override val id = "memory/$station" }
    /** A connect's Slack app: its name, icon, colour and permissions. */
    data class SlackApp(val station: String, val connect: String) : Screen { override val id = "slack-app/$station/$connect" }
}

class AppState(val core: StillFailCore, private val prefs: SharedPreferences, val cloudOrigin: String, val updates: Updates) {
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

    /** 我 → 通知: local notices and pushes, on by default (Notices.kt, Push.kt). */
    var notify by mutableStateOf(prefs.getBoolean(Notifier.FLAG, true)); private set
    fun useNotify(on: Boolean) { notify = on; prefs.edit().putBoolean(Notifier.FLAG, on).apply() }

    /** Looks for a newer build of the app: one found shows 更新 in the home page's top bar (and in 我). */
    suspend fun checkUpdates() { updates.check() }

    fun flag(name: String, default: Boolean) = prefs.getBoolean(name, default)
    fun setFlag(name: String, on: Boolean) = prefs.edit().putBoolean(name, on).apply()
    fun strings(name: String): List<String> = prefs.getString(name, null)?.split('\u0000')?.filter { it.isNotEmpty() } ?: emptyList()
    fun setStrings(name: String, values: List<String>) = prefs.edit().putString(name, values.joinToString("\u0000")).apply()

    fun push(screen: Screen) { sheet = null; menu = null; forward = true; stack = stack + screen }
    fun pop() { if (stack.size > 1) { sheet = null; menu = null; forward = false; stack = stack.dropLast(1) } }
    /** The top page gives way to another (a new chat becomes the chat it made). */
    fun replace(screen: Screen) { sheet = null; forward = true; stack = stack.dropLast(1) + screen }
    fun home() { sheet = null; forward = false; stack = listOf(Screen.Home) }
    /**
     * An item's link from outside: its workspace, and its page over the list (back goes to the list); a service's link
     * (`?service=<job>`) has the service over its chat.
     */
    fun openItem(workspace: String, station: String, session: String, service: String? = null) {
        pickWorkspace(workspace)
        sheet = null; menu = null; forward = true
        val address = "$workspace/$station"
        stack = listOf(Screen.Home, Screen.Chat(address, ChatOf.Session(session))) + listOfNotNull(service?.let { Screen.Preview(address, it) })
    }

    /** The agents of each chat page (by its id) as last shown: whether a link names one of them. */
    val chatAgents = HashMap<String, Set<String>>()

    /**
     * still.fail's own links in a chat (cloud origin /o/<workspace>/<station>/<session>, as agents post them) open here, as
     * pages over the one they are on: a web service of one of this chat's agents (`?service=<job>`) over the chat,
     * another session as its chat (and its service over that). Answers false for any other link (the system opens it).
     */
    fun openLink(url: String): Boolean {
        val uri = android.net.Uri.parse(url)
        val origin = android.net.Uri.parse(cloudOrigin)
        val parts = uri.pathSegments
        val same = uri.scheme == origin.scheme && uri.host == origin.host && uri.port == origin.port
        // The production cloud answers on its new host and its old one alike: a link with either opens here.
        val sameCloud = origin.host in CLOUD_HOSTS && uri.scheme == "https" && uri.host in CLOUD_HOSTS && uri.port == -1
        // An invitation's link (<cloud>/invite#<token>): what it leads to, in a sheet, before it is accepted.
        if ((same || sameCloud) && parts == listOf("invite") && !uri.fragment.isNullOrEmpty()) {
            fail.still.android.screens.openInvite(this, uri.fragment!!)
            return true
        }
        // A reference to another chat (web/src/chatRefs.ts): its page, /w/<workspace>/s/<station>/chats/<key>, opened over this one.
        if ((same || sameCloud) && parts.size == 6 && parts[0] == "w" && parts[2] == "s" && parts[4] == "chats") {
            val (ws, station, chat) = Triple(parts[1], parts[3], parts[5])
            val top = stack.last()
            if (top is Screen.Chat && top.station == "$ws/$station" && (top.of as? ChatOf.Session)?.key == chat) return true
            if (ws != workspace) openItem(ws, station, chat)
            else { sheet = null; menu = null; forward = true; stack = stack + Screen.Chat("$ws/$station", ChatOf.Session(chat)) }
            return true
        }
        if (!(same || sameCloud) || parts.size != 4 || parts[0] != "o") return false
        val (ws, station, session) = Triple(parts[1], parts[2], parts[3])
        val service = uri.getQueryParameter("service")?.takeIf { it.isNotEmpty() }
        val address = "$ws/$station"
        val top = stack.last()
        val here = top is Screen.Chat && top.station == address && ((top.of as? ChatOf.Session)?.key == session || chatAgents[top.id]?.contains(session) == true)
        when {
            here -> if (service != null) push(Screen.Preview(address, service))
            ws != workspace -> openItem(ws, station, session, service)
            else -> {
                sheet = null; menu = null; forward = true
                stack = stack + Screen.Chat(address, ChatOf.Session(session)) + listOfNotNull(service?.let { Screen.Preview(address, it) })
            }
        }
        return true
    }

    fun api(station: String) = StationApi(core, station)
    /** For what outlives the page that started it (a message sent as the page moves to its new chat). */
    val scope = MainScope()

    /** Where each chat was left: the message at the top of the list and how far below the top it sat. */
    val places = HashMap<String, Pair<String, Int>>()
    /** The pages, as what a sheet over them frosts. */
    val haze = HazeState()
}

/** The production cloud's hosts: app.still.fail, and ember.3720.org from before the rename (kept, not redirected). */
private val CLOUD_HOSTS = setOf("app.still.fail", "ember.3720.org")

val LocalApp = staticCompositionLocalOf<AppState> { error("no app") }

private val Ease = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

@Composable
fun StillFailApp(app: AppState) {
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val workspaces by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    // Links in what agents write go through here: still.fail's own open in the app (AppState.openLink), the rest as before.
    val system = LocalUriHandler.current
    val links = remember(system) { object : UriHandler { override fun openUri(uri: String) { if (!app.openLink(uri)) system.openUri(uri) } } }
    CompositionLocalProvider(LocalUriHandler provides links) { Box(Modifier.fillMaxSize().background(C.bg)) {
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
                        // What the core has been waiting on for a while, under it (the core's `status`), as the web's splash says.
                        val status by rememberTopic<fail.still.android.data.StatusView>(app.core, Topics.status)
                        Splash(failed ?: listOfNotNull("正在读取你的 workspace…", status.value?.text).joinToString("\n"), now = failed != null)
                    }
                    else Landing(signedIn, all)
                } else {
                    rememberNotificationAsk(app, once = true)
                    Pages(app, current)
                }
            }
        } }
        // Pages scroll under the status bar; it keeps the paper behind its icons (the list and a chat have frosted bars
        // there instead, which show what runs under them).
        val top = app.stack.lastOrNull()
        // A chat opened: its notification is read (its tag, as Notices.kt shows it).
        val context = LocalContext.current
        LaunchedEffect(top) { if (top is Screen.Chat && top.of is ChatOf.Session) Notifier.cancel(context, "${top.station}/${top.of.key}") }
        if (top !is Screen.Home && top !is Screen.Chat) Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(C.bg))
        SheetHost(app)
        ReaderHost(app)
        MenuHost(app)
        ToastHost(app)
    } }
}

@Composable
private fun Pages(app: AppState, current: fail.still.android.data.WorkspaceEntry) {
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
                    Screen.NewChat -> NewChatScreen(current)
                    Screen.Stations -> StationsScreen(current)
                    is Screen.Station -> StationScreen(current, screen.address)
                    is Screen.Profile -> ProfileScreen(current, screen.address, screen.profile)
                    is Screen.RunSettings -> fail.still.android.screens.RunSettingsScreen(screen.station, screen.of, screen.key)
                    Screen.Me -> MeScreen(current)
                    Screen.Workspace -> fail.still.android.screens.WorkspaceScreen(current)
                    is Screen.Preview -> fail.still.android.screens.PreviewScreen(screen.station, screen.job)
                    is Screen.PreviewFile -> fail.still.android.screens.PreviewFileScreen(screen.station, screen.session, screen.path, screen.name)
                    is Screen.Connect -> fail.still.android.screens.ConnectScreen(screen.station, screen.connect)
                    is Screen.ConnectRun -> fail.still.android.screens.ConnectRunScreen(screen.station, screen.connect)
                    is Screen.NewConnect -> fail.still.android.screens.NewConnectScreen(screen.station)
                    is Screen.NewProfile -> fail.still.android.screens.NewProfileScreen(current, screen.station)
                    Screen.Archive -> fail.still.android.screens.ArchiveScreen(current)
                    is Screen.Memory -> fail.still.android.screens.MemoryScreen(current, screen.station)
                    is Screen.SlackApp -> fail.still.android.screens.SlackAppScreen(screen.station, screen.connect)
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
