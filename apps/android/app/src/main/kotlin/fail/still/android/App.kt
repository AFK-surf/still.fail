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
import androidx.activity.BackEventCompat
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.SeekableTransitionState
import androidx.compose.animation.core.rememberTransition
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import androidx.compose.ui.MotionDurationScale
import androidx.compose.runtime.withFrameNanos
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.ui.draw.clipToBounds
import fail.still.android.screens.WideCorners
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.animation.core.Easing
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.Account
import fail.still.android.data.ChatOf
import fail.still.android.data.PrefsView
import fail.still.android.data.DoingItem
import fail.still.android.data.DoingView
import fail.still.android.data.errorText
import fail.still.android.data.decode
import fail.still.core.CoreException
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import fail.still.android.data.LinkTarget
import fail.still.android.data.StationApi
import fail.still.android.data.StillFailJson
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
import fail.still.android.data.NotifyView
import kotlinx.coroutines.MainScope

sealed interface Screen {
    val id: String
    data object Home : Screen { override val id = "home" }
    /** An item's page: its chat, or its agent before it has one. */
    data class Chat(val station: String, val of: ChatOf) : Screen {
        override val id = "chat/$station/" + when (of) { is ChatOf.Thread -> of.id.toString(); is ChatOf.Session -> of.key }
    }
    /** One message of a chat on a page of its own, to pick passages of and say something about (a long press on it). */
    data class Annotate(val station: String, val of: ChatOf, val ts: String) : Screen {
        override val id = "annotate/$station/" + (when (of) { is ChatOf.Thread -> of.id.toString(); is ChatOf.Session -> of.key }) + "/$ts"
    }
    /** Rises from the bottom rather than coming in from the side. */
    data object NewChat : Screen { override val id = "new" }
    data object Stations : Screen { override val id = "stations" }
    data class Station(val address: String) : Screen { override val id = "station/$address" }
    /** How an agent runs, changed: its model, how hard it thinks, who runs it. */
    data class RunSettings(val station: String, val of: ChatOf, val key: String) : Screen { override val id = "run/$station/$key" }
    /** A profile's models, to pick which may be used. */
    data class Profile(val address: String, val profile: String) : Screen { override val id = "profile/$address/$profile" }
    /** Settings, one page from the gear on Home (screens/SettingsHome.kt); it comes from the left. */
    data object Settings : Screen { override val id = "settings" }
    /** The account: who is signed in, where, and the other accounts on this device. */
    data object Me : Screen { override val id = "me" }
    /** How this device shows still.fail: its theme, whose pictures lead a chat's row. */
    data object Appearance : Screen { override val id = "appearance" }
    /** What changed in still.fail (screens/Changelog.kt). */
    data object Changelog : Screen { override val id = "changelog" }
    /** Every station's connects, profiles and memory, from settings. */
    /** Every station's connects, or (from a station's page) that station's only. */
    data class Connects(val station: String? = null) : Screen { override val id = "connects" + (station?.let { "/$it" } ?: "") }
    /** Every station's profiles, or (from a station's page) that station's only. */
    data class Profiles(val station: String? = null) : Screen { override val id = "profiles" + (station?.let { "/$it" } ?: "") }
    data object Memories : Screen { override val id = "memories" }
    /** What the agents spent (screens/Usage.kt). */
    data object Usage : Screen { override val id = "usage" }
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
    /** How much a station takes of its machine, and cleaning it up; its chats' directories on a page of their own. */
    /** A connect's Slack app: its name, icon, colour and permissions. */
    data class SlackApp(val station: String, val connect: String) : Screen { override val id = "slack-app/$station/$connect" }
}

class AppState(val core: StillFailCore, private val prefs: SharedPreferences, val cloudOrigin: String, val updates: Updates, kept: PrefsView = PrefsView()) {
    var stack by mutableStateOf(listOf<Screen>(Screen.Home)); private set
    /** Whether the last move went deeper, for the direction of the transition. */
    var forward by mutableStateOf(true); private set
    var sheet by mutableStateOf<SheetSpec?>(null)
    var menu by mutableStateOf<MenuSpec?>(null)
    var toast by mutableStateOf<String?>(null)
    /** One entry of an execution history in full, over everything (the sheet stays under it). */
    var reader by mutableStateOf<ReaderSpec?>(null)

    /** How its person likes it on this device, as the core keeps it (data/Prefs.kt). */
    var kept by mutableStateOf(kept); private set
    /** Changes sent and not answered yet; the core's values meanwhile wait, the latest shown once all are. */
    private var sending = 0
    private var waiting: PrefsView? = null
    /** The core's own, last heard: what a change it refused goes back to. */
    private var known: PrefsView = kept
    private var refused = false

    /** Changes them: shown at once (`shown`), then as the core has them (`patch`); refused, back as they were, and said. */
    private fun setPrefs(shown: PrefsView, patch: JsonObject) {
        kept = shown
        sending++
        scope.launch {
            try { core.call("prefs.set", patch) } catch (e: CoreException) { refused = true; toast = "没能保存设置：${errorText(e)}" }
            if (--sending == 0) {
                kept = waiting ?: if (refused) known else kept
                waiting = null; refused = false
            }
        }
    }

    /** Follows the core's prefs for the app's life. */
    suspend fun followPrefs() {
        core.topic(Topics.prefs).collect { state ->
            val value = state.value?.takeIf { it !is JsonNull }?.let { runCatching { decode(PrefsView.serializer(), it) }.getOrNull() } ?: return@collect
            known = value
            if (sending > 0) waiting = value else kept = value
        }
    }

    /** What people set going here and the core has not finished (the `doing` topic, client/core/src/doing.rs). */
    var doing by mutableStateOf(emptyList<DoingItem>()); private set

    /** Follows what is under way for the app's life. */
    suspend fun followDoing() {
        core.topic(Topics.doing).collect { state ->
            val value = state.value?.takeIf { it !is JsonNull }?.let { runCatching { decode(DoingView.serializer(), it) }.getOrNull() } ?: return@collect
            doing = value.doing
        }
    }

    /**
     * Whether one of `calls` is under way about what `on` names (its params, as words; null is any), wherever it was
     * asked: the row or button it is about shows it at once (a spinner, not pressed again), the menu that asked gone.
     */
    fun isDoing(calls: Set<String>, vararg on: Pair<String, Any?>): Boolean =
        doing.any { item -> item.stage != "failed" && item.matches(calls, on) }
    fun isDoing(call: String, vararg on: Pair<String, Any?>): Boolean = isDoing(setOf(call), *on)

    /** Why one of `calls` about what `on` names failed a moment ago (the core shows it a few seconds); null when none did. */
    fun failedOf(calls: Set<String>, vararg on: Pair<String, Any?>): String? =
        doing.lastOrNull { item -> item.stage == "failed" && item.matches(calls, on) }?.let { it.error ?: "失败了" }
    fun failedOf(call: String, vararg on: Pair<String, Any?>): String? = failedOf(setOf(call), *on)

    private fun DoingItem.matches(calls: Set<String>, on: Array<out Pair<String, Any?>>): Boolean =
        call in calls && on.all { (k, v) -> v == null || params[k] == v.toString() }

    /**
     * Lets what a person did go on by itself (past the page or menu that asked it), and says how it ended:
     * `没能<what>：<why>` when it failed, `done` (if any) when it went through.
     */
    fun act(what: String, done: String? = null, run: suspend () -> Unit) {
        scope.launch {
            try {
                run()
                done?.let { toast = it }
            } catch (e: CoreException) {
                toast = "没能$what：${errorText(e)}"
            }
        }
    }

    /** The workspace chosen last; the first one when it is gone. */
    val workspace: String? get() = kept.workspace
    fun pickWorkspace(id: String) { if (id != kept.workspace) setPrefs(kept.copy(workspace = id), buildJsonObject { put("workspace", id) }) }

    /** 外观: "system" (the default), "light" or "dark". */
    val theme: String get() = kept.appearance ?: "system"
    fun useTheme(value: String) = setPrefs(kept.copy(appearance = value), buildJsonObject { put("appearance", value) })

    val onlyMine: Boolean get() = kept.onlyMine ?: false

    /** What the chat list shows: "all", "mine" (我参与的) or "watching" (监控中); the core keeps the last two apart. */
    val chatFilter: String get() = if (kept.onlyWatching == true) "watching" else if (onlyMine) "mine" else "all"
    fun showChats(filter: String) = setPrefs(
        kept.copy(onlyMine = filter == "mine", onlyWatching = filter == "watching"),
        buildJsonObject { put("onlyMine", filter == "mine"); put("onlyWatching", filter == "watching") },
    )

    /** A Slack app made for a new connect on `station`, to go on with (screens/Connects.kt); null lets it go. */
    fun resume(station: String): String? = kept.resume?.get(station)
    fun setResume(station: String, app: String?) {
        if (resume(station) == app) return
        val shown = kept.resume.orEmpty() - station + listOfNotNull(app?.let { station to it })
        setPrefs(kept.copy(resume = shown), buildJsonObject { put("resume", buildJsonObject { put(station, app) }) })
    }

    /** 我 → 通知: local notices and pushes, on by default (Notices.kt, Push.kt), as the core keeps it (its `notify`). */
    var notify by mutableStateOf(true); private set
    /** Whether the system was asked to allow notifications; null until the core says. */
    var notifyAsked by mutableStateOf<Boolean?>(null); private set
    /** The MainActivity is started (on screen, maybe under another app's window). */
    var inFront by mutableStateOf(false)

    /**
     * Turns notifications on or off (the core takes this device's pushes off the accounts when off); answers whether the
     * core wants this device to hold pushes now.
     */
    suspend fun useNotify(on: Boolean): Boolean {
        val was = notify
        notify = on
        return try {
            val view = decode(NotifyView.serializer(), core.call("notify.set", buildJsonObject { put("on", on) }))
            notify = view.on
            view.push
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Refused (or not understood): as it was, and said.
            notify = was
            toast = "没能${if (on) "打开" else "关掉"}通知：${(e as? CoreException)?.let(::errorText) ?: e.message.orEmpty()}"
            was
        }
    }

    /** The system was asked to allow notifications (once). */
    suspend fun askedNotify() {
        notifyAsked = true
        try { core.call("notify.set", buildJsonObject { put("asked", true) }) } catch (_: CoreException) {}
    }

    /** The settings as the app kept them before the core did, into the core once. */
    suspend fun moveNotify() {
        if (!prefs.contains(Notifier.FLAG) && !prefs.contains("notifyAsked")) return
        try {
            core.call("notify.set", buildJsonObject { put("on", prefs.getBoolean(Notifier.FLAG, true)); put("asked", prefs.getBoolean("notifyAsked", false)) })
            prefs.edit().remove(Notifier.FLAG).remove("notifyAsked").apply()
        } catch (_: CoreException) {
            // Tried again on the next start; the old values stay where they are.
        }
    }

    /** Follows the core's `notify` (the settings shown in 我). */
    suspend fun followNotify() {
        core.topic(Topics.notify()).collect { state ->
            val view = state.value?.takeIf { it !is JsonNull }?.let { runCatching { decode(NotifyView.serializer(), it) }.getOrNull() } ?: return@collect
            notify = view.on
            notifyAsked = view.asked
        }
    }

    /** Looks for a newer build of the app: one found shows 更新 in the home page's top bar (and in 我). */
    suspend fun checkUpdates() { updates.check() }

    fun flag(name: String, default: Boolean) = prefs.getBoolean(name, default)
    fun setFlag(name: String, on: Boolean) = prefs.edit().putBoolean(name, on).apply()
    fun strings(name: String): List<String> = prefs.getString(name, null)?.split('\u0000')?.filter { it.isNotEmpty() } ?: emptyList()
    fun setStrings(name: String, values: List<String>) = prefs.edit().putString(name, values.joinToString("\u0000")).apply()

    fun push(screen: Screen) { sheet = null; menu = null; forward = true; if (screen == Screen.NewChat || screen == madeChat) madeChat = null; stack = stack + screen }
    fun pop() { if (stack.size > 1) { sheet = null; menu = null; forward = false; stack = stack.dropLast(1) } }
    /** The top page gives way to another (a new chat becomes the chat it made). */
    /** From the latest chats on a wide screen (screens/Wide.kt): in place of the page open, or over the list. */
    fun open(screen: Screen) {
        sheet = null; menu = null; forward = true
        // A chat a new chat made, opened again from the list, is a page of its own (it slides, not rises).
        if (screen == Screen.NewChat || screen == madeChat) madeChat = null
        stack = (if (stack.size > 1) stack.dropLast(1) else stack) + screen
    }
    fun replace(screen: Screen) { sheet = null; forward = true; stack = stack.dropLast(1) + screen }
    /**
     * The chat a new chat became (`made`): it is the same page as the new chat was (screens/ChatHost.kt), not another
     * pushed in over it; the page is the host's until the next new chat.
     */
    var madeChat by mutableStateOf<Screen.Chat?>(null); private set
    fun made(screen: Screen.Chat) { madeChat = screen; replace(screen) }
    /** The page a screen is drawn in: a new chat and the chat it became are one. */
    fun pageOf(screen: Screen): String = if (screen == Screen.NewChat || screen == madeChat) "new-chat" else screen.id
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
     * still.fail's own links in a chat open here, as pages over the one they are on: the core says what a link opens
     * (`link.parse`: an invitation, a chat's page, an item and its web service); a web service of one of this chat's
     * agents (`?service=<job>`) over the chat, another session as its chat (and its service over that). Any other link
     * goes to `orElse` (the system opens it). `outside`: a link from outside the app (a notification, the browser),
     * whose item opens over the list.
     */
    fun openLink(url: String, outside: Boolean = false, orElse: () -> Unit = {}) {
        scope.launch {
            val target = try {
                core.call("link.parse", buildJsonObject { put("url", url) }).takeIf { it !is JsonNull }
                    ?.let { StillFailJson.decodeFromJsonElement(LinkTarget.serializer(), it) }
            } catch (_: CoreException) { null }
            if (target == null || !open(target, outside)) orElse()
        }
    }

    private fun open(t: LinkTarget, outside: Boolean): Boolean {
        val ws = t.workspace.orEmpty()
        val station = t.station.orEmpty()
        when (t.opens) {
            // An invitation's link: what it leads to, in a sheet, before it is accepted.
            "invite" -> fail.still.android.screens.openInvite(this, t.token ?: return false)
            // A reference to another chat (web/src/chatRefs.ts), opened over this one.
            "chat" -> {
                val chat = t.chat ?: return false
                val top = stack.last()
                if (top is Screen.Chat && top.station == "$ws/$station" && (top.of as? ChatOf.Session)?.key == chat) return true
                if (ws != workspace) openItem(ws, station, chat)
                else { sheet = null; menu = null; forward = true; stack = stack + Screen.Chat("$ws/$station", ChatOf.Session(chat)) }
            }
            "item" -> {
                val session = t.session ?: return false
                val service = t.service
                val address = "$ws/$station"
                val top = stack.last()
                val here = top is Screen.Chat && top.station == address && ((top.of as? ChatOf.Session)?.key == session || chatAgents[top.id]?.contains(session) == true)
                when {
                    outside -> openItem(ws, station, session, service)
                    here -> if (service != null) push(Screen.Preview(address, service))
                    ws != workspace -> openItem(ws, station, session, service)
                    else -> {
                        sheet = null; menu = null; forward = true
                        stack = stack + Screen.Chat(address, ChatOf.Session(session)) + listOfNotNull(service?.let { Screen.Preview(address, it) })
                    }
                }
            }
            else -> return false
        }
        return true
    }

    fun api(station: String) = StationApi(core, station)
    /** For what outlives the page that started it (a message sent as the page moves to its new chat). */
    val scope = MainScope()

    /**
     * Where each chat was left: the message at the top of the list and how far below the top it sat; and, if it was
     * left at its end, the newest message then (`bottom`).
     */
    val places = HashMap<String, Place>()
    data class Place(val id: String, val offset: Int, val bottom: String?)
    /** The pages, as what a sheet over them frosts. */
    val haze = HazeState()

    init {
        // What a new chat ran on, kept here before the core kept it (newChat/<station's address>, newChat.lastIn/<scope>,
        // newChat.last): into the core once (newChat.migrate, by the stations' ids as the web keeps them), then gone.
        val kept = prefs.all.keys.filter { it.startsWith("newChat/") || it.startsWith("newChat.lastIn/") || it == "newChat.last" }
        if (kept.isNotEmpty()) scope.launch {
            val id = { address: String -> address.substringAfterLast('/') }
            val params = buildJsonObject {
                putJsonObject("choices") {
                    for (k in kept.filter { it.startsWith("newChat/") }) {
                        val v = strings(k)
                        if (v.size >= 3) putJsonObject(id(k.removePrefix("newChat/"))) {
                            put("runtime", v[0]); put("model", v[1])
                            put("effort", v[2].takeIf { it != "-" } ?: ""); put("profile", v.getOrNull(3)?.takeIf { it != "-" } ?: "")
                        }
                    }
                }
                putJsonObject("lastIn") {
                    for (k in kept.filter { it.startsWith("newChat.lastIn/") }) strings(k).firstOrNull()?.let { put(k.removePrefix("newChat.lastIn/"), id(it)) }
                }
                strings("newChat.last").firstOrNull()?.let { put("last", id(it)) }
            }
            // A core that refuses it: kept here, tried again next time.
            try { core.call("newChat.migrate", params); prefs.edit().apply { kept.forEach { remove(it) } }.apply() } catch (_: fail.still.core.CoreException) {}
        }
    }
}


val LocalApp = staticCompositionLocalOf<AppState> { error("no app") }

private val Ease = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

@Composable
fun StillFailApp(app: AppState) {
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val workspaces by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    // Links in what agents write go through here: still.fail's own open in the app (AppState.openLink), the rest as before.
    val system = LocalUriHandler.current
    // Nothing on the phone opens it (a bare file name, an unknown scheme): said, not a crash.
    val links = remember(system) { object : UriHandler { override fun openUri(uri: String) { app.openLink(uri) {
        try { system.openUri(uri) } catch (_: Exception) { app.toast = "打不开这个链接" }
    } } } }
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
                // The beta app, and an account not let into the beta (the core says so): said, with a way out.
                val blocked = all?.firstOrNull { it.blocked != null }
                if (current == null && blocked != null) fail.still.android.screens.Blocked(blocked)
                else if (current == null) {
                    if (entries == null || all == null || !all.all { it.loaded }) {
                        val failed = workspaces.error?.message ?: all?.firstNotNullOfOrNull { it.error }?.let { "没能读取你的 workspace" }
                        // What the core has been waiting on for a while, under it (the core's `status`), as the web's splash says.
                        val status by rememberTopic<fail.still.android.data.StatusView>(app.core, Topics.status())
                        Splash(failed ?: listOfNotNull("正在读取你的 workspace…", status.value?.text).joinToString("\n"), now = failed != null)
                    }
                    else Landing(signedIn, all)
                } else {
                    rememberNotificationAsk(app, once = true)
                    // The core hears which workspace the app is in: what it tells the viewer is of it (attend.rs).
                    LaunchedEffect(current.workspace.id) { app.core.focus(buildJsonObject { put("workspace", current.workspace.id) }) }
                    Pages(app, current)
                }
            }
        } }
        val top = app.stack.lastOrNull()
        // A chat opened: its notification is read (its tag, as Notices.kt shows it).
        val context = LocalContext.current
        LaunchedEffect(top) { if (top is Screen.Chat && top.of is ChatOf.Session) Notifier.cancel(context, "${top.station}/${top.of.key}") }
        // Looked at while in front with a chat on top (the chat itself says which, screens/Chat.kt): its notices are
        // not shown then (client/core/src/attend.rs).
        val lookedAt = app.inFront && top is Screen.Chat
        LaunchedEffect(app.inFront, lookedAt) { app.core.focus(buildJsonObject { put("visible", app.inFront); put("focused", lookedAt) }) }
        // An image or a video opened, over the pages (it grows out of its thumbnail in the chat); sheets and notes over it.
        fail.still.android.screens.ViewerHost()
        SheetHost(app)
        ReaderHost(app)
        MenuHost(app)
        ToastHost(app)
    } }
}

@Composable
private fun Pages(app: AppState, current: fail.still.android.data.WorkspaceEntry) {
    val top = app.stack.last()
    val pages = remember { SeekableTransitionState(top) }
    val transition = rememberTransition(pages, label = "pages")
    // Swiped back (the system's back gesture, predictive back): the page follows the finger and the one under it shows
    // a little behind (web mobile/app.tsx's own edge swipe); let go, it goes on from there, or back if the system says so.
    var swiped by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // The page's own width: a wide screen's column (screens/Wide.kt), so the page follows the finger there too.
    val window = LocalWindowInfo.current.containerSize.width
    val density = androidx.compose.ui.platform.LocalDensity.current
    val width = with(density) {
        val dp = window.toDp()
        if (dp >= fail.still.android.screens.WideAt) fail.still.android.screens.columnWidth(dp).toPx() else window.toFloat()
    }
    LaunchedEffect(top) {
        if (pages.currentState == top && pages.targetState == top) return@LaunchedEffect
        pages.animateTo(top, if (swiped) tween(300, easing = FastOutSlowInEasing) else null)
        swiped = false
    }
    PredictiveBackHandler(enabled = app.stack.size > 1 && app.sheet == null && app.menu == null && !fail.still.android.screens.FileViewers.open) { progress ->
        val under = app.stack.getOrNull(app.stack.size - 2)
        var start: Float? = null
        var following = false
        try {
            progress.collect { e ->
                // Only from a page at rest (not while one still moves in); by the finger's own way from where it began.
                if (under == null || pages.currentState != pages.targetState && !following) return@collect
                val x0 = start ?: e.touchX.also { start = it }
                val dx = if (e.swipeEdge == BackEventCompat.EDGE_RIGHT) x0 - e.touchX else e.touchX - x0
                if (!following) { swiped = true; following = true }
                pages.seekTo((dx / width.coerceAtLeast(1f)).coerceIn(0f, 1f), under)
            }
            // Let go: on from where the finger left it at once, moving as it was (out, easing to rest), and only then off
            // the stack. Popping first waited a frame or two for the pages to recompose, then started from still: a stop
            // where the finger let go.
            // Not called off once let go (another swipe meanwhile would run it backwards).
            if (following && under != null) withContext(NonCancellable) {
                val from = pages.fraction
                seekAlong(from, 1f, (280f * (1f - from)).coerceAtLeast(120f), EaseOut) { pages.seekTo(it, under) }
                pages.snapTo(under)
                swiped = false
            }
            app.pop()
        } catch (e: CancellationException) {
            // Called off: back along the same way (the seek run backwards to 0, 200ms), then at rest on the page again.
            if (following && under != null) scope.launch {
                seekAlong(pages.fraction, 0f, 200f, FastOutSlowInEasing) { pages.seekTo(it, under) }
                pages.snapTo(app.stack.last())
                swiped = false
            }
            throw e
        }
    }
    val saved = rememberSaveableStateHolder()
    // Each page's topics, followed while it is in the stack (data/Topics.kt: PageTopics); those of the pages gone from it
    // let go, once they are not drawn either (a page going away is drawn until it has).
    val followed = remember { HashMap<String, fail.still.android.data.PageTopics>() }
    val workspace = current.workspace.id
    fun keyOf(screen: Screen) = "$workspace|${app.pageOf(screen)}"
    fun letGo(keep: (String) -> Boolean) = followed.keys.filterNot(keep).forEach { followed.remove(it)?.close() }
    // A page's own state (its scroll place, what is open on it) is kept while it is in the stack, and forgotten once it
    // leaves: a chat closed and opened again starts afresh.
    val kept = remember { HashSet<String>() }
    LaunchedEffect(app.stack, workspace) {
        val stacked = app.stack.mapTo(HashSet(), ::keyOf) + keyOf(pages.currentState)
        letGo { it in stacked }
        val pagesIn = app.stack.mapTo(HashSet(), app::pageOf)
        kept.filterNot { it in pagesIn }.forEach { kept.remove(it); saved.removeState(it) }
    }
    // Wider than a phone (screens/Wide.kt): the pages in a column, the latest chats and the new-chat button at the screen's corners.
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
    val wide = maxWidth >= fail.still.android.screens.WideAt
    Box(Modifier.align(androidx.compose.ui.Alignment.TopCenter).fillMaxHeight()
        .then(if (wide) Modifier.width(fail.still.android.screens.columnWidth(maxWidth)).clipToBounds() else Modifier.fillMaxWidth())) {
    CompositionLocalProvider(fail.still.android.screens.LocalWide provides wide) {
    transition.AnimatedContent(
        transitionSpec = {
            // A message's page and its chat are one place (Annotate.kt): no slide either way, the page's own parts move.
            // Layered by depth in the stack, the deeper page over: a page's zIndex is fixed when it comes in (AnimatedContent
            // keeps the first spec's), so by the way it came it was wrong later (one come back to, then swiped away, went under).
            val z = app.stack.indexOfLast { app.pageOf(it) == app.pageOf(targetState) }.coerceAtLeast(0).toFloat()
            if (targetState is Screen.Annotate || initialState is Screen.Annotate) (EnterTransition.None togetherWith ExitTransition.KeepUntilTransitionsFinished)
                .apply { targetContentZIndex = z }
            else {
                // Sharing the host keeps the composer in place, but only an unsent new chat exits down.
                val rose = initialState == Screen.NewChat
                if (swiped) swipe(toLeft = initialState == Screen.Settings, z, rose) else transition(initialState, targetState, app.forward, z, rose)
            }
        },
        // A new chat and the chat it becomes are one page (ChatHost.kt): it stays, rather than slide in again.
        contentKey = { app.pageOf(it) },
    ) { screen ->
        val pageScope = this
        val page = keyOf(screen)
        val topics = followed.getOrPut(page) { fail.still.android.data.PageTopics() }
        DisposableEffect(page) {
            topics.drawn = true
            onDispose { topics.drawn = false; if (app.stack.none { keyOf(it) == page }) letGo { it != page } }
        }
        kept += app.pageOf(screen)
        saved.SaveableStateProvider(app.pageOf(screen)) { CompositionLocalProvider(fail.still.android.data.LocalPageTopics provides topics) {
            // A message's page draws its own ground, coming in over its chat (Annotate.kt).
            Box(Modifier.fillMaxSize().then(if (screen is Screen.Annotate) Modifier else Modifier.background(C.bg))) {
                when (screen) {
                    Screen.Home -> HomeScreen(current)
                    is Screen.Chat, Screen.NewChat -> fail.still.android.screens.ChatHost(current, screen)
                    Screen.Stations -> StationsScreen(current)
                    is Screen.Station -> StationScreen(current, screen.address)
                    is Screen.Profile -> ProfileScreen(current, screen.address, screen.profile)
                    is Screen.RunSettings -> fail.still.android.screens.RunSettingsScreen(screen.station, screen.of, screen.key)
                    Screen.Me -> MeScreen(current)
                    Screen.Settings -> fail.still.android.screens.SettingsScreen(current)
                    Screen.Appearance -> fail.still.android.screens.AppearanceScreen()
                    Screen.Changelog -> fail.still.android.screens.ChangelogScreen()
                    is Screen.Connects -> fail.still.android.screens.ConnectsScreen(current, screen.station)
                    is Screen.Profiles -> fail.still.android.screens.ProfilesScreen(current, screen.station)
                    Screen.Memories -> fail.still.android.screens.MemoriesScreen(current)
                    Screen.Usage -> fail.still.android.screens.UsageScreen(current)
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
                    is Screen.Annotate -> CompositionLocalProvider(fail.still.android.screens.LocalPageTransition provides pageScope.transition) {
                        fail.still.android.screens.AnnotateScreen(screen.station, screen.of, screen.ts)
                    }
                }
                // The page scrolls under the status bar; it keeps the paper behind its icons, moving with its page (the
                // list and a chat have frosted bars there instead, which show what runs under them).
                if (screen !is Screen.Home && screen !is Screen.Chat && screen != Screen.NewChat && screen !is Screen.Annotate)
                    Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(C.bg))
            }
        } }
    }
    }
    }
    if (wide) WideCorners(current, top)
    }
}

/** Out of a swipe let go: starts moving, no ease in (easeOutQuad). */
private val EaseOut = CubicBezierEasing(0.25f, 0.46f, 0.45f, 0.94f)

/** Seeks from `from` to `to` over `ms` frame by frame (the seek is what the pages draw), on the system's animation speed. */
private suspend fun seekAlong(from: Float, to: Float, ms: Float, easing: Easing, seek: suspend (Float) -> Unit) {
    val scale = kotlin.coroutines.coroutineContext[MotionDurationScale]?.scaleFactor ?: 1f
    val start = withFrameNanos { it }
    while (true) {
        val now = withFrameNanos { it }
        val t = if (scale <= 0f) 1f else ((now - start) / 1_000_000f / (ms * scale)).coerceAtMost(1f)
        seek(from + (to - from) * easing.transform(t))
        if (t >= 1f) break
    }
}

/**
 * Swiped back: the page goes right with the finger (linear in the seek, so it is where the finger is) and the one under
 * it comes along beside it, edge to edge, as a tapped back moves them. Settings came from the left (`toLeft`): they go
 * back that way, the list coming from the right. An unsent new chat (`rose`) rose from the bottom: it
 * sinks back down with the finger over the page under it, as a tapped back takes it.
 */
private fun swipe(toLeft: Boolean, z: Float, rose: Boolean): ContentTransform {
    val linear = tween<IntOffset>(300, easing = LinearEasing)
    val way = if (toLeft) -1 else 1
    return (if (rose) EnterTransition.None togetherWith slideOutVertically(linear) { it }
        else slideInHorizontally(linear) { -way * it } togetherWith slideOutHorizontally(linear) { way * it })
        .apply { targetContentZIndex = z }
}

/**
 * Pages move side by side, as the list's two panes do when switched: the new one pushes in whole from the right and
 * the old goes out whole to the left (and back the other way), nothing fading. Settings (from the gear at the top left)
 * come from the left instead; a new chat rises from the bottom.
 */
private fun transition(from: Screen, to: Screen, forward: Boolean, z: Float, rose: Boolean): ContentTransform {
    val time = 380
    val slide = tween<IntOffset>(300, easing = FastOutSlowInEasing)
    return when {
        forward && to == Screen.NewChat -> slideInVertically(tween(time, easing = Ease)) { it } togetherWith fadeOut(tween(time), 0.99f)
        // Only the new-chat screen sinks back down; a chat it made returns sideways.
        !forward && rose -> fadeIn(tween(1), 0.99f) togetherWith slideOutVertically(tween(time, easing = Ease)) { it }
        // Settings are to the left of the list (the gear is at the list's left): they come and go that way.
        forward && to == Screen.Settings -> slideInHorizontally(slide) { -it } togetherWith slideOutHorizontally(slide) { it }
        !forward && from == Screen.Settings -> slideInHorizontally(slide) { it } togetherWith slideOutHorizontally(slide) { -it }
        forward -> slideInHorizontally(slide) { it } togetherWith slideOutHorizontally(slide) { -it }
        else -> slideInHorizontally(slide) { -it } togetherWith slideOutHorizontally(slide) { it }
    }.apply { targetContentZIndex = z }
}
