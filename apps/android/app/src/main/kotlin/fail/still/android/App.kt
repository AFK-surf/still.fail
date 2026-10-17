// The app: signed out it is the sign-in page; signed in, the chats of one
// workspace are home, and everything else is a page pushed over it (no tab
// bar), or a sheet from the bottom.
package fail.still.android


import fail.still.android.data.t
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
import fail.still.android.screens.WideCorners
import fail.still.android.screens.openInvite
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
import fail.still.android.screens.Elsewhere
import fail.still.android.screens.openStationPeek
import fail.still.android.screens.openWorkspaces
import fail.still.android.screens.invitationsWaiting
import fail.still.android.screens.FirstStation
import fail.still.android.screens.MachineLoginOffers
import fail.still.android.screens.VaultApproval
import fail.still.android.screens.FilePreview
import fail.still.android.screens.Gallery


private val Ease = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

@Composable
fun StillFailApp(app: AppState) {
    // An invitation's link opens its sheet, a page of the app's (AppState.openLink).
    AppHooks.invite = ::openInvite
    // What a page of one module shows or opens of another's (screens/Elsewhere.kt).
    Elsewhere.stationPeek = ::openStationPeek
    Elsewhere.workspaces = ::openWorkspaces
    Elsewhere.invitationsWaiting = { invitationsWaiting(it) }
    Elsewhere.firstStation = { FirstStation(it) }
    Elsewhere.machineLoginOffers = { station, overview, inset -> MachineLoginOffers(station, overview, inset) }
    Elsewhere.vaultApproval = { workspace, request, mine, modifier -> VaultApproval(workspace, request, mine, modifier) }
    Elsewhere.preview = { station, shown, folder, onClose -> FilePreview(station, shown.key, shown.file, gallery = folder?.let { Gallery.Folder(it) }, canDraft = false, onClose = onClose) }
    // Where files of a drive are kept once read (the reader, the viewer and the player find it there).
    fail.still.android.data.DriveCache.start(LocalContext.current)
    fail.still.android.ui.KeyboardInsets { AppContent(app) }
}

@Composable
private fun AppContent(app: AppState) {
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val workspaces by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    // Links in what agents write go through here: still.fail's own open in the app (AppState.openLink), the rest as before.
    val system = LocalUriHandler.current
    // Nothing on the phone opens it (a bare file name, an unknown scheme): said, not a crash.
    val links = remember(system) { object : UriHandler { override fun openUri(uri: String) { app.openLink(uri) {
        try { system.openUri(uri) } catch (_: Exception) { app.toast = t("android-misc.link.cantOpen") }
    } } } }
    CompositionLocalProvider(LocalUriHandler provides links) { Box(Modifier.fillMaxSize().background(C.bg)) {
        val signedIn = accounts.value
        Box(Modifier.fillMaxSize().hazeSource(app.haze).background(C.bg)) { when {
            signedIn == null -> Splash(accounts.error?.message, now = accounts.error != null)
            signedIn.isEmpty() -> SignInScreen()
            else -> {
                val entries = workspaces.value?.entries()
                // Only once every account has answered does "no workspace" mean none: not before, not after a failure.
                val all = workspaces.value
                // The one last open, or one just joined, may not be in what was kept yet: until the accounts answer (or
                // fail), it is waited for rather than another put in its place.
                val answered = all != null && all.all { it.loaded || it.error != null }
                val target = entries?.firstOrNull { it.workspace.id == app.workspace }
                    ?: entries?.firstOrNull()?.takeIf { app.workspace == null || answered }
                LaunchedEffect(target?.workspace?.id) { target?.let { if (it.workspace.id != app.workspace) app.pickWorkspace(it.workspace.id) } }
                // Switched to another workspace, the one shown stays until the core has given what its list shows, from
                // what is on the device (LOCAL_MS at most, as a page opening): not its list swapped for the loading look
                // and placeholders, then the rows a few frames later (a flash, under the switcher closing).
                var shown by remember { mutableStateOf<String?>(null) }
                LaunchedEffect(target?.workspace?.id) {
                    val id = target?.workspace?.id
                    if (id != null && shown != null && id != shown) {
                        // What is by the list (its marks, status, what is left up) read ahead too, but only the list waited for.
                        fail.still.android.data.preread(app.scope, app.core, homeExtras(id), 0, PRIME_MS)
                        fail.still.android.data.preread(app.scope, app.core, homeLists(id), LOCAL_MS, PRIME_MS)
                    }
                    shown = id
                }
                val current = if (target == null) null else entries?.firstOrNull { it.workspace.id == shown } ?: target
                // The beta app, and an account not let into the beta (the core says so): said, with a way out.
                val blocked = all?.firstOrNull { it.blocked != null }
                if (current == null && blocked != null) fail.still.android.screens.Blocked(blocked)
                else if (current == null) {
                    if (entries == null || all == null || !all.all { it.loaded }) {
                        val failed = workspaces.error?.message ?: all?.firstNotNullOfOrNull { it.error }?.let { t("android-misc.workspaces.loadFailed") }
                        // What the core has been waiting on for a while, under it (the core's `status`), as the web's splash says.
                        val status by rememberTopic<fail.still.android.data.StatusView>(app.core, Topics.status())
                        Splash(failed ?: listOfNotNull(t("android-misc.workspaces.loading"), status.value?.text).joinToString("\n"), now = failed != null)
                    }
                    else Landing(signedIn, all)
                } else {
                    rememberNotificationAsk(app, once = true)
                    // The core hears which workspace the app is in: what it tells the viewer is of it (attend.ts).
                    LaunchedEffect(current.workspace.id) { app.core.focus(buildJsonObject { put("workspace", current.workspace.id) }) }
                    Pages(app, current)
                }
            }
        } }
        val top = app.stack.lastOrNull()
        // A chat opened: its notification is read (its tag, as Notices.kt shows it).
        val context = LocalContext.current
        LaunchedEffect(top) { if (top is Screen.Chat) (top.of as? ChatOf.Session)?.let { Notifier.cancel(context, "${top.station}/${it.key}") } }
        // Looked at while in front with a chat on top (the chat itself says which, screens/Chat.kt): its notices are
        // not shown then (client/core-ts/src/attend.ts).
        val lookedAt = app.inFront && top is Screen.Chat
        LaunchedEffect(app.inFront, lookedAt) { app.core.focus(buildJsonObject { put("visible", app.inFront); put("focused", lookedAt) }) }
        // An image or a video opened, over the pages (it grows out of its thumbnail in the chat); sheets and notes over it.
        fail.still.android.screens.ViewerHost()
        SheetHost(app.sheet, app.haze) { app.sheet?.onClose?.invoke(); app.sheet = null }
        ReaderHost(app.reader) { app.reader = null }
        MenuHost(app.menu) { app.menu = null }
        ToastHost(app.toast) { app.toast = null }
    } }
}

/** How long an opening page waits for what the core has on the device (web motion.ts LOCAL_MS): never for a station. */
private const val LOCAL_MS = 100L

/** A workspace's lists (screens/Home.kt), as it follows them: read ahead of switching to it. */
private fun homeLists(workspace: String): List<Pair<JsonObject, kotlinx.serialization.KSerializer<*>>> = listOf(
    Topics.chats(workspace, false) to fail.still.android.data.ChatsView.serializer(),
    Topics.chats(workspace, true) to fail.still.android.data.ChatsView.serializer(),
    Topics.chats(workspace, false, watching = true) to fail.still.android.data.ChatsView.serializer(),
)

/** What is shown by a workspace's lists (screens/Home.kt, OpenJobs.kt), as they follow it. */
private fun homeExtras(workspace: String): List<Pair<JsonObject, kotlinx.serialization.KSerializer<*>>> = listOf(
    Topics.workspaceMarks(workspace) to fail.still.android.data.WorkspaceMarksView.serializer(),
    Topics.status(workspace) to fail.still.android.data.StatusView.serializer(),
    Topics.longJobs(workspace) to fail.still.android.data.LongJobsView.serializer(),
)

/** What a page shows first, which it waits for as it opens (Pages): its main topics, as its screen follows them. */
private fun opening(screen: Screen, workspace: String): List<Pair<JsonObject, kotlinx.serialization.KSerializer<*>>> = when (screen) {
    is Screen.Chat -> listOf(Topics.chat(screen.station, screen.of) to fail.still.android.data.ChatView.serializer())
    is Screen.History -> listOf(
        Topics.chat(screen.station, screen.of) to fail.still.android.data.ChatView.serializer(),
        Topics.history(screen.station, screen.key) to fail.still.android.data.HistoryView.serializer(),
    )
    is Screen.Preview -> listOf(Topics.job(screen.station, screen.job) to fail.still.android.data.Job.serializer())
    is Screen.Station -> listOf(Topics.stations(workspace) to kotlinx.serialization.builtins.ListSerializer(fail.still.android.data.StationView.serializer()))
    // A folder as it was last read (held on the device): the page slides in with its rows.
    is Screen.Drive -> listOfNotNull(screen.root?.let { Topics.drive(screen.station, it, screen.path) to fail.still.android.data.DriveFolder.serializer() })
    // A secret's page: what it is (its row), its uses after.
    is Screen.VaultItem -> listOf(Topics.vaultItems(workspace, screen.vault) to fail.still.android.data.VaultItemsView.serializer())
    Screen.Archive -> listOf(Topics.archive(workspace) to fail.still.android.data.ArchiveView.serializer())
    Screen.Decisions -> listOf(Topics.decisions(workspace) to fail.still.android.data.DecisionsView.serializer())
    Screen.Files, Screen.Stations -> listOf(Topics.stations(workspace) to kotlinx.serialization.builtins.ListSerializer(fail.still.android.data.StationView.serializer()))
    else -> emptyList()
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
    // The page's own width: the screen's.
    val width = LocalWindowInfo.current.containerSize.width.toFloat()
    // What is over the pages takes back first: its own handlers were added before this one (they are there from the
    // splash; the pages only once the workspaces are read), and the last added is asked first, so this one steps aside.
    PredictiveBackHandler(enabled = app.stack.size > 1 && app.sheet == null && app.menu == null && app.reader == null && !fail.still.android.screens.FileViewers.open) { progress ->
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
    // A place's top page other than the chats, with nothing over it: back goes to the chats (the app's first place),
    // in place as the bar switches, rather than out of the app.
    val root = app.stack.singleOrNull()
    androidx.activity.compose.BackHandler(enabled = root != null && root != Screen.Home && placeOf(root) != null && app.sheet == null && app.menu == null && app.reader == null && !fail.still.android.screens.FileViewers.open) {
        app.place(Screen.Home)
    }
    val saved = rememberSaveableStateHolder()
    val still = fail.still.android.ui.reducedMotion()
    val density = androidx.compose.ui.platform.LocalDensity.current
    // Each page's topics, followed while it is in the stack (data/Topics.kt: PageTopics); those of the pages gone from it
    // let go, once they are not drawn either (a page going away is drawn until it has).
    val followed = remember { HashMap<String, fail.still.android.data.PageTopics>() }
    val workspace = current.workspace.id
    fun keyOf(screen: Screen) = "$workspace|${app.pageOf(screen)}"
    // A place's top page of this workspace, switched away from on the bar, keeps its state (PLACE_PAGES, below), and
    // its topics: still followed while its place is in one of the bars (coming back, what it shows is there and up to
    // date at once); paused otherwise, what they showed kept, so it comes back drawn as it was left and followed again
    // from there. Any other page's are let go.
    fun letGo(keep: (String) -> Boolean) = followed.keys.filterNot(keep).forEach { key ->
        val place = if (key.startsWith("$workspace|")) PLACE_OF_PAGE[key.removePrefix("$workspace|")] else null
        when {
            place == null -> followed.remove(key)?.close()
            app.bars.sets.none { place in it } -> followed[key]?.pause()
        }
    }
    // A page's own state (its scroll place, what is open on it) is kept while it is in the stack, and forgotten once it
    // leaves: a chat closed and opened again starts afresh.
    val kept = remember { HashSet<String>() }
    LaunchedEffect(app.stack, workspace) {
        val stacked = app.stack.mapTo(HashSet(), ::keyOf) + keyOf(pages.currentState)
        letGo { it in stacked }
        val pagesIn = app.stack.mapTo(HashSet(), app::pageOf)
        // The places' top pages keep theirs (where the list was scrolled to), switched away from and back on the bar.
        kept.filterNot { it in pagesIn || it in PLACE_PAGES }.forEach { kept.remove(it); saved.removeState(it) }
    }
    LaunchedEffect(top) {
        if (pages.currentState == top && pages.targetState == top) return@LaunchedEffect
        // A place switched to on the bar: in place, no slide, at once (the frame after the tap): what it shows is there
        // if it was shown before (its topics kept, above), else it comes in on the page; not waited for (up to LOCAL_MS,
        // which could hold the page back while the ball was on its way).
        if (app.switched) {
            BarTiming.effect()
            val topics = followed.getOrPut(keyOf(top)) { fail.still.android.data.PageTopics() }
            @Suppress("UNCHECKED_CAST") opening(top, workspace).forEach { (topic, serializer) -> topics.of(app.core, topic, serializer as kotlinx.serialization.KSerializer<Any?>) }
            BarTiming.snapped(waited = false, timedOut = false)
            swiped = false
            // In at once, with the switch's own short motion (placeSwitch, below), not a push's.
            pages.animateTo(top)
            return@LaunchedEffect
        }
        // A page opened slides in once the core has given what it shows, from what is on the device (LOCAL_MS at most,
        // as web mobile/Chat.tsx useReady): not first as its loading look swapped for it a frame or two later. What has
        // to come from a station is not waited for: the page slides in, showing it coming.
        val shows = if (app.forward && !swiped && app.pageOf(top) != "new-chat") opening(top, workspace) else emptyList()
        if (shows.isNotEmpty()) {
            val topics = followed.getOrPut(keyOf(top)) { fail.still.android.data.PageTopics() }
            @Suppress("UNCHECKED_CAST") val states = shows.map { (topic, serializer) -> topics.of(app.core, topic, serializer as kotlinx.serialization.KSerializer<Any?>) }
            withTimeoutOrNull(LOCAL_MS) { snapshotFlow { states.all { it.value.value != null || it.value.error != null } }.first { it } }
        }
        pages.animateTo(top, if (swiped) tween(300, easing = FastOutSlowInEasing) else null)
        swiped = false
    }
    // Wider than a phone (screens/Wide.kt): the pages the screen's whole width, the latest chats and the new-chat button at its corners.
    // What the bottom bar frosts: the pages (and, for the ball and 令, the bar's own glass: ui/Bar.kt).
    val barHaze = remember { dev.chrisbanes.haze.HazeState() }
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
    val wide = maxWidth >= fail.still.android.screens.WideAt
    Box(Modifier.fillMaxSize()) {
    Box(Modifier.fillMaxSize().hazeSource(barHaze)) {
    CompositionLocalProvider(fail.still.android.ui.LocalWide provides wide) {
    transition.AnimatedContent(
        transitionSpec = {
            // Switched on the bar: in place, nothing slides.
            if (app.switched) return@AnimatedContent placeSwitch(initialState, targetState, app.bars, still, with(density) { 30.dp.roundToPx() })
            // Layered by depth in the stack, the deeper page over: a page's zIndex is fixed when it comes in (AnimatedContent
            // keeps the first spec's), so by the way it came it was wrong later (one come back to, then swiped away, went under).
            val z = app.stack.indexOfLast { app.pageOf(it) == app.pageOf(targetState) }.coerceAtLeast(0).toFloat()
            // Sharing the host keeps the composer in place, but only an unsent new chat exits down.
            val rose = initialState == Screen.NewChat
            if (swiped) swipe(toLeft = initialState == Screen.Settings, z, rose) else transition(initialState, targetState, app.forward, z, rose)
        },
        // A new chat and the chat it becomes are one page (ChatHost.kt): it stays, rather than slide in again.
        contentKey = { app.pageOf(it) },
    ) { screen ->
        val page = keyOf(screen)
        val topics = followed.getOrPut(page) { fail.still.android.data.PageTopics() }
        DisposableEffect(page) {
            topics.drawn = true
            onDispose { topics.drawn = false; if (app.stack.none { keyOf(it) == page }) letGo { it != page } }
        }
        kept += app.pageOf(screen)
        // A place's top page: no back with the bar under it (room kept for the bar at its foot); on a wide screen, which
        // has no bar, back to the chats.
        // A page going (switched away from on the bar, still drawn until the one coming has what it shows) stays as it
        // was: not a pushed page all at once, its back showing and its foot's room gone for a moment.
        val now = when {
            app.stack.firstOrNull() != screen || placeOf(screen) == null -> PlaceRoot.None
            wide -> PlaceRoot.Wide
            else -> PlaceRoot.Bar
        }
        val held = remember { arrayOf(now) }
        if (app.stack.contains(screen)) held[0] = now
        val placeRoot = held[0]
        saved.SaveableStateProvider(app.pageOf(screen)) { CompositionLocalProvider(
            fail.still.android.data.LocalPageTopics provides topics,
            LocalPlaceRoot provides placeRoot,
            LocalBarRoom provides if (placeRoot != PlaceRoot.Bar) 0.dp else BAR_ROOM,
        ) {
            Box(Modifier.fillMaxSize().background(C.bg).then(BarTiming.page(screen))) {
                when (screen) {
                    Screen.Home -> fail.still.android.screens.LockGate(current) { HomeScreen(current) }
                    is Screen.Chat, Screen.NewChat -> fail.still.android.screens.ChatHost(current, screen)
                    Screen.Stations -> StationsScreen(current)
                    is Screen.Station -> StationScreen(current, screen.address)
                    is Screen.AdbShare -> fail.still.android.screens.AdbShareScreen(current, screen.address)
                    is Screen.Profile -> ProfileScreen(current, screen.address, screen.profile)
                    is Screen.History -> fail.still.android.screens.HistoryScreen(screen.station, screen.of, screen.key, screen.entry)
                    is Screen.RunSettings -> fail.still.android.screens.RunSettingsScreen(screen.station, screen.of, screen.key)
                    Screen.Me -> MeScreen(current)
                    Screen.Settings -> fail.still.android.screens.SettingsScreen(current)
                    Screen.Appearance -> fail.still.android.screens.AppearanceScreen()
                    Screen.KeptFiles -> fail.still.android.screens.KeptFilesScreen()
                    is Screen.KeptChat -> fail.still.android.screens.KeptChatScreen(screen.station, screen.thread)
                    Screen.Changelog -> fail.still.android.screens.ChangelogScreen()
                    is Screen.Connects -> fail.still.android.screens.ConnectsScreen(current, screen.station)
                    is Screen.Profiles -> fail.still.android.screens.ProfilesScreen(current, screen.station)
                    is Screen.ProfileAccount -> fail.still.android.screens.ProfileAccountScreen(current, screen.key)
                    Screen.AutomaticDecisions -> fail.still.android.screens.AutomaticDecisionsScreen()
                    Screen.AutomaticDecisionCompletion -> fail.still.android.screens.AutomaticDecisionCompletionScreen(current)
                    is Screen.AutomaticDecisionPolicy -> fail.still.android.screens.AutomaticDecisionPolicyScreen(current, screen.station)
                    Screen.Memories -> fail.still.android.screens.MemoriesScreen(current)
                    Screen.Usage -> fail.still.android.screens.UsageScreen(current)
                    is Screen.UsagePrices -> fail.still.android.screens.UsagePricesScreen(current, screen.days)
                    Screen.Workspace -> fail.still.android.screens.WorkspaceScreen(current)
                    Screen.Security -> fail.still.android.screens.SecurityScreen(current)
                    Screen.SecurityOpen -> fail.still.android.screens.SecurityOpenScreen(current)
                    Screen.Vault -> fail.still.android.screens.VaultScreen(current)
                    is Screen.VaultItem -> fail.still.android.screens.VaultItemScreen(current, screen.vault, screen.item)
                    is Screen.Preview -> fail.still.android.screens.PreviewScreen(screen.station, screen.job)
                    is Screen.PreviewFile -> fail.still.android.screens.PreviewFileScreen(screen.station, screen.session, screen.path, screen.name)
                    is Screen.Connect -> fail.still.android.screens.ConnectScreen(screen.station, screen.connect)
                    is Screen.ConnectRun -> fail.still.android.screens.ConnectRunScreen(screen.station, screen.connect)
                    is Screen.NewConnect -> fail.still.android.screens.NewConnectScreen(screen.station)
                    is Screen.NewProfile -> fail.still.android.screens.NewProfileScreen(current, screen.station)
                    Screen.Archive -> fail.still.android.screens.ArchiveScreen(current)
                    Screen.Decisions -> fail.still.android.screens.DecisionsScreen(current)
                    Screen.Files -> fail.still.android.drive.FilesScreen(current)
                    Screen.BarSettings -> fail.still.android.screens.BarSettingsScreen()
                    is Screen.Memory -> fail.still.android.screens.MemoryScreen(current, screen.station)
                    is Screen.MemoryDoc -> fail.still.android.screens.MemoryDocScreen(current, screen.station, screen.skill, screen.at)
                    is Screen.SlackApp -> fail.still.android.screens.SlackAppScreen(screen.station, screen.connect)
                    is Screen.Drive -> fail.still.android.drive.DriveScreen(current, screen.station, screen.root, screen.path)
                    is Screen.DriveRead -> fail.still.android.drive.ReaderScreen(screen.station, screen.root, screen.path)
                    is Screen.DrivePlay -> fail.still.android.drive.PlayerScreen(screen.station, screen.root, screen.path)
                }
                // The page scrolls under the status bar; it keeps the paper behind its icons, moving with its page (the
                // list, a place's top page with the bar and a chat have frosted bars there instead, which show what runs
                // under them). A book and a film draw their own paper (or black) there.
                if (screen !is Screen.Home && placeRoot != PlaceRoot.Bar && screen !is Screen.Chat && screen != Screen.NewChat && screen !is Screen.DriveRead && screen !is Screen.DrivePlay)
                    Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(C.bg))
            }
        } }
    }
    }
    }
    // The bottom bar (Places.kt): a phone's, on a place's top page with nothing over it.
    if (!wide) {
        // The keyboard up (a field on the page): out of its way.
        val density = androidx.compose.ui.platform.LocalDensity.current
        val ime = androidx.compose.foundation.layout.WindowInsets.ime
        val keyboardUp by remember(density) { androidx.compose.runtime.derivedStateOf { ime.getBottom(density) > 0 } }
        val root = app.stack.singleOrNull()
        PlaceBar(app, current, barHaze, shown = root != null && placeOf(root) != null && !keyboardUp && !app.barAway)
    }
    }
    if (wide) WideCorners(current, top)
    }
}

/** The places' top pages (Places.kt): their state is kept while they are not in the stack, as the bar switches between them. */
private val PLACE_PAGES = PLACES.map { screenOf(it).id }.toSet()
/** Each place's top page's id, to its place. */
private val PLACE_OF_PAGE = PLACES.associateBy { screenOf(it).id }

/**
 * Switched on the bar from one place's page to another's (not a push: nothing to go back to): a shared axis along the
 * bar. The page coming in moves 30dp in from the side the ball goes to, fading in (220 ms); the one going fades out in
 * the first 90 ms, moving 30dp the other way. To a place not in the bar in view (chosen through the panel of the other
 * bars), no side to come from: it only fades in over the page going (180 ms). Reduced motion: at once.
 */
private fun placeSwitch(from: Screen, to: Screen, bars: fail.still.android.data.BarPrefs, still: Boolean, shift: Int): ContentTransform {
    if (still) return (EnterTransition.None togetherWith ExitTransition.None).apply { targetContentZIndex = 0f }
    val bar = bars.sets.getOrNull(bars.current.toInt()).orEmpty()
    val a = bar.indexOf(placeOf(from))
    val b = bar.indexOf(placeOf(to))
    if (a < 0 || b < 0 || a == b) return (fadeIn(tween(180, easing = fail.still.android.ui.Ease.Arrive)) togetherWith fadeOut(tween(180), 0.99f)).apply { targetContentZIndex = 0f }
    val way = if (b > a) 1 else -1
    val move = tween<IntOffset>(220, easing = fail.still.android.ui.Ease.Arrive)
    return ((slideInHorizontally(move) { way * shift } + fadeIn(tween(220, easing = fail.still.android.ui.Ease.Arrive))) togetherWith
        (slideOutHorizontally(move) { -way * shift } + fadeOut(tween(90, easing = LinearEasing)))).apply { targetContentZIndex = 0f }
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
