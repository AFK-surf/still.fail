// What the pages share of the app: where it is (its stack of pages, Screen), what is over it (a sheet, a menu, a toast),
// and the ways to the core and the stations (AppState). Below the pages (2026-10-17), so that a page reaches the app
// through this and not through the app's module; the app draws it (App.kt).
package fail.still.android

import fail.still.android.data.t
import fail.still.android.ui.Splash
import androidx.compose.ui.unit.IntOffset
import androidx.compose.animation.core.FastOutSlowInEasing
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.HazeState
import android.content.SharedPreferences
import fail.still.android.data.AppRelease
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
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.first
import androidx.compose.runtime.snapshotFlow
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.ime
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
import fail.still.android.ui.C
import fail.still.android.ui.UiHost
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
    /** `at`: a message (seq) to show once it opens, flashing (a row's state line: what it is about). */
    data class Chat(val station: String, val of: ChatOf, val at: Long? = null, val words: List<String>? = null) : Screen {
        override val id = "chat/$station/" + when (of) { is ChatOf.Thread -> of.id.toString(); is ChatOf.Session -> of.key }
    }
    /** Rises from the bottom rather than coming in from the side. */
    data object NewChat : Screen { override val id = "new" }
    data object Stations : Screen { override val id = "stations" }
    /** A station's page; `login`: the login a link pointed to (its card brought into view and marked). */
    data class Station(val address: String, val login: String? = null) : Screen { override val id = "station/$address" }
    /** This phone's adb lent to a station's agents (screens/AdbShare.kt). */
    data class AdbShare(val address: String) : Screen { override val id = "adb/$address" }
    /** An agent’s execution history, opened as a page over its chat. */
    data class History(val station: String, val of: ChatOf, val key: String, val entry: Long? = null) : Screen { override val id = "history/${Chat(station, of).id}/$key/$entry" }
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
    /** Files opened in the app and kept on this device, to delete (screens/KeptFiles.kt). */
    data object KeptFiles : Screen { override val id = "kept-files" }
    /** What is kept of a chat (null: files of no chat known), from KeptFiles. */
    data class KeptChat(val station: String?, val thread: Long?) : Screen { override val id = "kept-files/${station ?: ""}/${thread ?: ""}" }
    /** What changed in still.fail (screens/Changelog.kt). */
    data object Changelog : Screen { override val id = "changelog" }
    /** Every station's connects, profiles and memory, from settings. */
    /** Every station's connects, or (from a station's page) that station's only. */
    data class Connects(val station: String? = null) : Screen { override val id = "connects" + (station?.let { "/$it" } ?: "") }
    /** Every station's profiles, or (from a station's page) that station's only. */
    data class Profiles(val station: String? = null) : Screen { override val id = "profiles" + (station?.let { "/$it" } ?: "") }
    /** An account on several stations: what they have in common, and each station's part. */
    data class ProfileAccount(val key: String) : Screen { override val id = "profile-account/$key" }
    data object AutomaticDecisions : Screen { override val id = "automatic-decisions" }
    data object AutomaticDecisionCompletion : Screen { override val id = "automatic-decisions/completion" }
    /** A station's archive policy, from its row under the completion rule. */
    data class AutomaticDecisionPolicy(val station: String) : Screen { override val id = "automatic-decisions/completion/$station" }
    data object Memories : Screen { override val id = "memories" }
    /** What the agents spent (screens/Usage.kt). */
    data object Usage : Screen { override val id = "usage" }
    data class UsagePrices(val days: Int) : Screen { override val id = "usage-prices-$days" }
    /** A web service an agent started, full screen: by its job (people know it by its name, never its port). */
    data class Preview(val station: String, val job: String) : Screen { override val id = "preview/$station/$job" }
    /** A visualization an agent posted, as a page of its own in the preview (web mobile's 在侧边打开 on a phone). */
    data class PreviewFile(val station: String, val session: String, val path: String, val name: String) : Screen { override val id = "preview-file/$station/$session/$path" }
    /** The workspace itself: its name, its people, leaving it. */
    data object Workspace : Screen { override val id = "workspace" }
    /** The workspace's security mode (its lock), and turning it on. */
    data object Security : Screen { override val id = "security" }
    data object SecurityOpen : Screen { override val id = "security/open" }
    /** The workspace's vault: its items, the agents' requests waiting, turning it on (screens/Vault.kt). */
    data object Vault : Screen { override val id = "vault" }
    /** A secret of the library: what it is, its content shown, how agents may use it and when they did (screens/Vault.kt). */
    data class VaultItem(val vault: String, val item: String) : Screen { override val id = "vault/$vault/$item" }
    /** A connect of a station; how it runs; a new one on a station. */
    data class Connect(val station: String, val connect: String) : Screen { override val id = "connect/$station/$connect" }
    data class ConnectRun(val station: String, val connect: String) : Screen { override val id = "connect-run/$station/$connect" }
    data class NewConnect(val station: String) : Screen { override val id = "new-connect/$station" }
    data class NewProfile(val station: String) : Screen { override val id = "new-profile/$station" }
    /** Chats archived, of every station online: put back in the list, or deleted for good. */
    data object Archive : Screen { override val id = "archive" }
    /** The decisions waiting for the viewer in the workspace's chats, one at a time (奏 N on the home page). */
    data object Decisions : Screen { override val id = "decisions" }
    /** Every station's lent folders in one list (the bottom bar's 文件, drive/Files.kt). */
    data object Files : Screen { override val id = "files" }
    /** This device's bottom bars, to change (screens/BarSettings.kt). */
    data object BarSettings : Screen { override val id = "bar-settings" }

    /** The agents' memory on a station. */
    data class Memory(val station: String) : Screen { override val id = "memory/$station" }
    /** A page of a station's memory: a skill (`skill`, with its files), or the global memory's parts from `at`. */
    data class MemoryDoc(val station: String, val skill: String?, val at: Int = 0) : Screen { override val id = "memory/$station/${skill?.let { "skill/$it" } ?: "global"}" }
    /**
     * A station's drive (drive/DriveScreen.kt), a page per folder: `root` null is the drive itself (its one root's
     * contents, or its roots), else the folder `path` under `root`.
     */
    data class Drive(val station: String, val root: String?, val path: String) : Screen { override val id = "drive/$station/${root ?: ""}/$path" }
    /** A text or Markdown file of a drive, read (drive/Reader.kt). */
    data class DriveRead(val station: String, val root: String, val path: String) : Screen { override val id = "drive-read/$station/$root/$path" }
    /** A video or a song of a drive, played as it streams (drive/Player.kt). */
    data class DrivePlay(val station: String, val root: String, val path: String) : Screen { override val id = "drive-play/$station/$root/$path" }
    /** How much a station takes of its machine, and cleaning it up; its chats' directories on a page of their own. */
    /** A connect's Slack app: its name, icon, colour and permissions. */
    data class SlackApp(val station: String, val connect: String) : Screen { override val id = "slack-app/$station/$connect" }
}

class AppState(override val core: StillFailCore, private val prefs: SharedPreferences, val cloudOrigin: String, val updates: AppUpdates, kept: PrefsView = PrefsView()) : UiHost {
    override fun follow(url: String, orElse: () -> Unit) = openLink(url, orElse = orElse)
    override fun note(text: String) { toast = text }

    var stack by mutableStateOf(listOf<Screen>(Screen.Home)); private set
    /** Whether the last move went deeper, for the direction of the transition. */
    var forward by mutableStateOf(true); private set
    var sheet by mutableStateOf<SheetSpec?>(null)
    override var menu by mutableStateOf<MenuSpec?>(null)
    var toast by mutableStateOf<String?>(null)
    /** One entry of an execution history in full, over everything (the sheet stays under it). */
    var reader by mutableStateOf<ReaderSpec?>(null)

    /** How its person likes it on this device, as the core keeps it (data/Prefs.kt); its `motion` the app's clock (ui/Motion.kt). */
    var kept: PrefsView
        get() = keptNow.value
        private set(value) { keptNow.value = value; fail.still.android.ui.Motion.chosen = value.motion }
    private val keptNow = mutableStateOf(kept).also { fail.still.android.ui.Motion.chosen = kept.motion }
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
            try { core.call("prefs.set", patch) } catch (e: CoreException) { refused = true; toast = t("android-misc.prefs.saveFailed", "error" to errorText(e)) }
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
            fail.still.android.data.I18n.follow(value.lang)
            KeptLang.keep(prefs, value.lang)
        }
    }

    /** What people set going here and the core has not finished (the `doing` topic, client/core-ts/src/doing.ts). */
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
        doing.lastOrNull { item -> item.stage == "failed" && item.matches(calls, on) }?.let { it.error ?: t("android-misc.failed") }
    fun failedOf(call: String, vararg on: Pair<String, Any?>): String? = failedOf(setOf(call), *on)

    private fun DoingItem.matches(calls: Set<String>, on: Array<out Pair<String, Any?>>): Boolean =
        call in calls && on.all { (k, v) -> v == null || params[k] == v.toString() }

    /**
     * Lets what a person did go on by itself (past the page or menu that asked it), and says how it ended:
     * `没能<what>：<why>` when it failed (and `failed`, if any, is run), `done` (if any) when it went through.
     */
    fun act(what: String, done: String? = null, failed: (() -> Unit)? = null, run: suspend () -> Unit) {
        scope.launch {
            try {
                run()
                done?.let { toast = it }
            } catch (e: CoreException) {
                toast = t(if (e.code == "unconfirmed") "android-misc.act.unconfirmed" else "android-misc.act.failed", "what" to what, "error" to errorText(e))
                failed?.invoke()
            }
        }
    }

    /** The workspace chosen last; the first one when it is gone. */
    val workspace: String? get() = kept.workspace
    fun pickWorkspace(id: String) { if (id != kept.workspace) setPrefs(kept.copy(workspace = id), buildJsonObject { put("workspace", id) }) }

    /**
     * The bottom bars (Places.kt, ui/Bar.kt) of the workspace in view, whole: its own (`barsBy`), else the ones all had
     * before each had its own, else the default ones before the core says.
     */
    val bars: fail.still.android.data.BarPrefs get() =
        (kept.workspace?.let { kept.barsBy?.get(it) } ?: kept.bars)?.let { barsOf(it.sets, it.current.toInt()) } ?: DEFAULT_BARS
    /** The bars changed (`sets`, `current` the one in view): shown at once, kept whole, the workspace in view's (`prefs.set {barsBy}`). */
    fun setBars(sets: List<List<String>>, current: Int) {
        val whole = barsOf(sets, current)
        val json = buildJsonObject {
            put("sets", kotlinx.serialization.json.JsonArray(whole.sets.map { set -> kotlinx.serialization.json.JsonArray(set.map { kotlinx.serialization.json.JsonPrimitive(it) }) }))
            put("current", whole.current)
        }
        val ws = kept.workspace
        if (ws == null) setPrefs(kept.copy(bars = whole), buildJsonObject { put("bars", json) })
        else setPrefs(kept.copy(barsBy = (kept.barsBy ?: emptyMap()) + (ws to whole)), buildJsonObject { putJsonObject("barsBy") { put(ws, json) } })
    }

    /** 外观: "system" (the default), "light" or "dark". */
    val theme: String get() = kept.appearance ?: "system"
    fun useTheme(value: String) = setPrefs(kept.copy(appearance = value), buildJsonObject { put("appearance", value) })

    /** 动画: "reduce" or "full" as chosen; null follows the system's (ui/Motion.kt). */
    val motion: String? get() = kept.motion
    fun setMotion(value: String?) = setPrefs(kept.copy(motion = value), buildJsonObject { put("motion", value) })

    /** How the drive's reader lays text out on this device (the core's `prefs.reader`, whole; its defaults before it says). */
    val readerPrefs: fail.still.android.data.ReaderPrefs get() = kept.reader ?: fail.still.android.data.ReaderPrefs(size = 18, line = 1.7, margin = 22, face = "sans", indent = true, paper = "follow")
    /** One setting of the reader changed (`prefs.set {reader: {field: value}}`): shown at once, kept in its bounds by the core. */
    fun setReader(shown: fail.still.android.data.ReaderPrefs, field: String, value: kotlinx.serialization.json.JsonPrimitive) =
        setPrefs(kept.copy(reader = shown), buildJsonObject { putJsonObject("reader") { put(field, value) } })

    /** How a station's files are listed on this device, as the web's (prefs `driveViews`): their order (`sort`: name, time,
     *  size or kind, `-down` the other way) and whether hidden ones show (`hidden`: shown). */
    val driveSort: String get() = kept.driveViews?.get("sort") ?: "name"
    val driveHidden: Boolean get() = kept.driveViews?.get("hidden") == "shown"
    /** One of them changed (null: back to how it is when never said). */
    fun setDriveView(key: String, value: String?) = setPrefs(
        kept.copy(driveViews = (kept.driveViews ?: emptyMap()).let { if (value == null) it - key else it + (key to value) }),
        buildJsonObject { putJsonObject("driveViews") { if (value == null) put(key, kotlinx.serialization.json.JsonNull) else put(key, value) } },
    )

    /** Whether files of a station's put into the chat `key` ("<station>:<chat>") go as files, not named by their path: the
     *  chat's own say (`prefs.dropFiles`), else the settings' (`dropAs`). */
    fun dropsAsFiles(key: String): Boolean = kept.dropFiles?.get(key) ?: (kept.dropAs == "file")
    /** The chat `key` takes such files as files, or not (the same as the settings say: its own say dropped). */
    fun setDropsAsFiles(key: String, on: Boolean) {
        val own = if (on == (kept.dropAs == "file")) null else on
        val files = (kept.dropFiles.orEmpty() - key).let { if (own == null) it else it + (key to own) }
        setPrefs(kept.copy(dropFiles = files), buildJsonObject { putJsonObject("dropFiles") { put(key, own) } })
    }

    /** 语言: "zh" or "en" as chosen; null follows the phone. The words change at once, then as the core says (its `lang`). */
    val language: String? get() = kept.language
    fun setLanguage(value: String?) {
        val shown = kept.copy(language = value, lang = value ?: fail.still.android.data.I18n.langOf(java.util.Locale.getDefault().toLanguageTag()))
        fail.still.android.data.I18n.follow(shown.lang)
        setPrefs(shown, buildJsonObject { put("language", value) })
    }

    /**
     * What `workspace`'s chat list shows: "all", "mine" (我参与的) or "watching" (监控中). Each workspace keeps its own;
     * one never chosen in goes by the one filter kept for all before (奏 in the wide screen's sidebar: all here).
     */
    fun chatFilter(workspace: String): String {
        val mode = kept.listFilter?.get(workspace)
            ?: if (kept.onlyDecisions == true) "decisions" else if (kept.onlyWatching == true) "watching" else if (kept.onlyMine == true) "mine" else "all"
        return if (mode == "mine" || mode == "watching") mode else "all"
    }
    fun showChats(workspace: String, filter: String) = setPrefs(
        kept.copy(listFilter = kept.listFilter.orEmpty() + (workspace to filter)),
        buildJsonObject { put("listFilter", buildJsonObject { put(workspace, filter) }) },
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
            toast = t(if (on) "android-misc.notify.onFailed" else "android-misc.notify.offFailed", "error" to ((e as? CoreException)?.let(::errorText) ?: e.message.orEmpty()))
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
        if (!prefs.contains(NOTIFY_FLAG) && !prefs.contains("notifyAsked")) return
        try {
            core.call("notify.set", buildJsonObject { put("on", prefs.getBoolean(NOTIFY_FLAG, true)); put("asked", prefs.getBoolean("notifyAsked", false)) })
            prefs.edit().remove(NOTIFY_FLAG).remove("notifyAsked").apply()
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

    /**
     * Starts the core reading a chat ahead of its page (its row pressed), kept a moment for it: the page then has it as
     * it comes in, instead of a frame of its loading look first (web core/react.ts prime).
     */
    fun prime(station: String, of: ChatOf) {
        val topic = Topics.chat(station, of)
        scope.launch { withTimeoutOrNull(PRIME_MS) { core.topic(topic).first { it.value != null || it.error != null } } }
    }

    /**
     * A place from the bottom bar: its page takes the bottom of the stack, in place (no slide, nothing to go back to);
     * the same place again changes nothing.
     */
    fun place(screen: Screen) {
        if (stack.size == 1 && stack[0] == screen) return
        sheet = null; menu = null; forward = false
        val to = listOf(screen)
        AppHooks.placed(stack.firstOrNull(), screen)
        placed = to
        stack = to
    }
    /** The stack as a place from the bar last made it: while it is that very list, the page shown was switched to, not pushed. */
    private var placed: List<Screen>? = null
    val switched: Boolean get() = stack === placed
    /** Something over a place's top page (Home's search) has the bottom bar out of the way. */
    var barAway by mutableStateOf(false)
    /** Each place's primary action as its top page last said it, for the bar's notch (Places.kt PlaceAction): by "<workspace>|<place>", null for none. */
    val placeActions = androidx.compose.runtime.mutableStateMapOf<String, fail.still.android.ui.BarAction?>()

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
     * (`?service=<job>`) has the service over its chat. `at`: the message it opens at (a notification's).
     */
    fun openItem(workspace: String, station: String, session: String, service: String? = null, at: Long? = null) {
        pickWorkspace(workspace)
        sheet = null; menu = null; forward = true
        val address = "$workspace/$station"
        stack = listOf(Screen.Home, Screen.Chat(address, ChatOf.Session(session), at = at)) + listOfNotNull(service?.let { Screen.Preview(address, it) })
    }

    /** A new chat's page from outside (what is shared, in its composer): over the workspace's list. */
    fun openNew(workspace: String) {
        pickWorkspace(workspace)
        sheet = null; menu = null; forward = true
        stack = listOf(Screen.Home, Screen.NewChat)
    }

    /** An agent's execution history, over the chat it is in (at `entry`, else its newest): not twice over itself. */
    private fun pushHistory(address: String, of: ChatOf, key: String, entry: Long?) {
        val page = Screen.History(address, of, key, entry)
        if (stack.last() != page) push(page)
    }

    /** The agents of each chat page (by its id) as last shown: whether a link names one of them. */
    val chatAgents = HashMap<String, Set<String>>()

    /**
     * still.fail's own links in a chat open here, as pages over the one they are on: the core says what a link opens
     * (`link.parse`: an invitation, a chat's page, an item and its web service); a web service of one of this chat's
     * agents (`?service=<job>`) over the chat, another session as its chat (and its service over that). Any other link
     * goes to `orElse` (the system opens it). `outside`: a link from outside the app (a notification, the browser),
     * whose item opens over the list; `at`: the message a notification is about, its chat opened there.
     */
    fun openLink(url: String, outside: Boolean = false, at: Long? = null, orElse: () -> Unit = {}) {
        scope.launch {
            val target = try {
                core.call("link.parse", buildJsonObject { put("url", url) }).takeIf { it !is JsonNull }
                    ?.let { StillFailJson.decodeFromJsonElement(LinkTarget.serializer(), it) }
            } catch (_: CoreException) { null }
            if (target == null || !open(target, outside, at)) orElse()
        }
    }

    private fun open(t: LinkTarget, outside: Boolean, at: Long? = null): Boolean {
        val ws = t.workspace.orEmpty()
        val station = t.station.orEmpty()
        // One of its agents' execution history the link names, over the chat once it is open (`?history=`, `entry`).
        val history = t.history?.let { h -> { address: String, session: String -> pushHistory(address, ChatOf.Session(session), h, t.entry) } }
        when (t.opens) {
            // `?history=…` alone, as a chat's notes link to it: in the chat it is in.
            "history" -> {
                val top = stack.last() as? Screen.Chat ?: return false
                pushHistory(top.station, top.of, t.history ?: return false, t.entry)
            }
            // An invitation's link: what it leads to, in a sheet, before it is accepted.
            "invite" -> AppHooks.invite(this, t.token ?: return false)
            // A reference to another chat (web/src/chatRefs.ts), opened over this one.
            "chat" -> {
                val chat = t.chat ?: return false
                val top = stack.last()
                if (top is Screen.Chat && top.station == "$ws/$station" && (top.of as? ChatOf.Session)?.key == chat) { history?.invoke("$ws/$station", chat); return true }
                if (ws != workspace) openItem(ws, station, chat)
                else { sheet = null; menu = null; forward = true; stack = stack + Screen.Chat("$ws/$station", ChatOf.Session(chat)) }
                history?.invoke("$ws/$station", chat)
            }
            "item" -> {
                val session = t.session ?: return false
                val service = t.service
                val address = "$ws/$station"
                val top = stack.last()
                val here = top is Screen.Chat && top.station == address && ((top.of as? ChatOf.Session)?.key == session || chatAgents[top.id]?.contains(session) == true)
                when {
                    outside -> openItem(ws, station, session, service, at)
                    here -> if (service != null) push(Screen.Preview(address, service))
                    ws != workspace -> openItem(ws, station, session, service)
                    else -> {
                        sheet = null; menu = null; forward = true
                        stack = stack + Screen.Chat(address, ChatOf.Session(session)) + listOfNotNull(service?.let { Screen.Preview(address, it) })
                    }
                }
                // Here: over this chat, whose agent it is.
                if (here && top is Screen.Chat) t.history?.let { pushHistory(top.station, top.of, it, t.entry) } else history?.invoke(address, session)
            }
            // A station's 共享调试, as its agent asks for it (adb_devices): the page, sharing only once its person taps.
            "adbShare" -> {
                if (station.isEmpty()) return false
                val address = "$ws/$station"
                if (stack.last() == Screen.AdbShare(address)) return true
                if (ws != workspace) pickWorkspace(ws)
                sheet = null; menu = null; forward = true
                stack = (if (outside || ws != workspace) listOf(Screen.Home) else stack) + Screen.AdbShare(address)
            }
            // A login an agent started on a station (docs/remote-login.md): its card on the station's page.
            "login" -> {
                val login = t.login ?: return false
                if (station.isEmpty()) return false
                val address = "$ws/$station"
                if (ws != workspace) pickWorkspace(ws)
                sheet = null; menu = null; forward = true
                stack = (if (outside || ws != workspace) listOf(Screen.Home) else stack) + Screen.Station(address, login)
            }
            // One of a station's screens, as its agent asks a person to take over (docs/remote-screens.md): the viewer
            // over whatever page is open (back comes back to it).
            "screen" -> {
                val screen = t.screen ?: return false
                if (station.isEmpty()) return false
                openScreen("$ws/$station", screen, null)
            }
            else -> return false
        }
        return true
    }

    /**
     * Opens one of a station's screens in the viewer (remote/ScreenActivity.kt: an activity over the app, set by
     * MainActivity); `title`, the row's, until the core says one.
     */
    var openScreen: (station: String, screen: String, title: String?) -> Unit = { _, _, _ -> }

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

/** How long a chat read ahead of its page (`AppState.prime`) is kept for it. */
const val PRIME_MS = 3_000L

/** Where the app kept 我 → 通知 before the core did (AppState.moveNotify). */
private const val NOTIFY_FLAG = "notify"

/** What the app's updates are to the pages (Updates, in the app): a newer build found, getting it, installing it. */
interface AppUpdates {
    /** A build newer than this one, once a check found it. */
    val available: AppRelease?
    /** What an update under way is doing ("下载中 40%"), null when none is. */
    val progress: String?
    /** Whether a check asked for (checkNow) is under way. */
    val checking: Boolean
    /** Asks the core for a newer build (at most once an hour unless `now`); the one it finds, if any. */
    suspend fun check(now: Boolean = false): AppRelease?
    /** Checks now, for a person who asked; what to tell them, if anything. */
    suspend fun checkNow(): String?
    /** Gets the newer build and has the system install it; what went wrong, if anything. */
    suspend fun install(): String?
}

/**
 * What the app's state tells the app, which this module does not see; the app says where each goes as it starts
 * (BarTiming.start, StillFailApp); before that, nowhere.
 */
object AppHooks {
    /** A place taken from the bottom bar, from the place before (BarTiming.placed). */
    var placed: (from: Screen?, to: Screen) -> Unit = { _, _ -> }
    /** An invitation's link opened: what it leads to, in a sheet (screens/Workspaces.kt openInvite). */
    var invite: (app: AppState, token: String) -> Unit = { _, _ -> }
    /**
     * This phone listens for a login's browser to come back (screens/LoginCards.kt), the browser about to open: the app
     * holds itself up meanwhile (LoginRelay.kt). `title`: 在 Studio 上登录 gcloud.
     */
    var relaying: (title: String) -> Unit = {}
}

/**
 * The language the core last said, kept for a push that wakes the app with no core to ask (Notices.kt Notifier.words);
 * in the app's prefs.
 */
object KeptLang {
    private const val KEY = "lang"
    /** Whether this process has followed the core's language (keep): then it is the one. */
    @Volatile var followed = false; private set

    fun keep(prefs: SharedPreferences, lang: String?) {
        if (lang == null) return
        followed = true
        if (prefs.getString(KEY, null) != lang) prefs.edit().putString(KEY, lang).apply()
    }

    /** The language kept, for a process that has not followed the core's. */
    fun kept(prefs: SharedPreferences): String? = prefs.getString(KEY, null)

    /** The words, in the language last followed (a push, an installer's answer, may come with no app started). */
    fun words(context: android.content.Context) {
        fail.still.android.data.I18n.load(context)
        if (!followed) kept(context.getSharedPreferences("stillfail", android.content.Context.MODE_PRIVATE))?.let(fail.still.android.data.I18n::follow)
    }
}
