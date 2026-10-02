// Home is the `chats` view as the web's sidebar lists it: one kind of item (an
// agent with its chat, or an agent with no chat yet), newest first and grouped
// by day. A fixed head (settings · workspace · the filter · stations) and
// the new-chat button floating at the bottom.
package fail.still.android.screens

import fail.still.android.ui.t
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.layout.boundsInRoot
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import androidx.compose.foundation.background
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.zIndex
import kotlinx.coroutines.delay
import androidx.compose.foundation.Canvas
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import fail.still.android.ui.reducedMotion
import fail.still.android.ui.StationGlyph
import fail.still.android.ui.glyphCounts
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import fail.still.android.ui.floating
import fail.still.android.ui.glass
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.HazeState
import fail.still.android.data.Topic
import kotlin.math.roundToInt
import kotlin.math.abs
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.runtime.rememberCoroutineScope
import fail.still.android.ui.MoveSpring
import fail.still.android.ui.Ease
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.Screen
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatState
import fail.still.android.data.badgeState
import fail.still.android.data.ChatsView
import fail.still.android.data.StatusView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceMarksView
import fail.still.android.data.page
import fail.still.android.data.rememberTopic
import fail.still.android.data.state
import fail.still.android.ui.Badge
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Illustration
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.Mark
import fail.still.android.ui.NavButton
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SlackMark
import fail.still.android.ui.avatarColor
import kotlinx.coroutines.launch
import fail.still.android.ui.initial

@Composable
fun HomeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val scope = current.workspace.id
    // The lists (all, mine, watching) are followed at once, side by side: switching slides from one to another with
    // nothing to wait for.
    val all by rememberTopic<ChatsView>(app.core, Topics.chats(scope, false))
    val mine by rememberTopic<ChatsView>(app.core, Topics.chats(scope, true))
    val watching by rememberTopic<ChatsView>(app.core, Topics.chats(scope, false, watching = true))
    val allList = rememberLazyListState()
    val mineList = rememberLazyListState()
    val watchingList = rememberLazyListState()
    val filter = app.chatFilter
    val shift by animateFloatAsState(when (filter) { "mine" -> 1f; "watching" -> 2f; else -> 0f }, tween(240, easing = FastOutSlowInEasing), label = "filter")
    // The lists run under both bars, which are frosted glass over them.
    val haze = remember { HazeState() }
    val density = LocalDensity.current
    // Their heights kept with the page's state: coming back to the list, it is laid out with them at once, so a list
    // left at its end is not first clamped short of it (with no room under the bars) and stays there.
    // The first time, the top bar as it is laid out (the status bar, 8 + 34 + 8dp) rather than none: a note at the
    // list's top is not drawn under the bar until it has been measured (which a busy start can take a while to do).
    val statusTop = WindowInsets.statusBars.getTop(density)
    var topBar by rememberSaveable { mutableIntStateOf(statusTop + with(density) { 50.dp.roundToPx() }) }
    var bottomBar by rememberSaveable { mutableIntStateOf(0) }
    val padding = with(density) { PaddingValues(top = topBar.toDp() + 8.dp, bottom = bottomBar.toDp() + 8.dp) }
    Box(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize().clipToBounds().hazeSource(haze)) {
            val width = constraints.maxWidth
            ChatPane(current, all, "all", allList, padding, Modifier.width(maxWidth).offset { IntOffset((-shift * width).roundToInt(), 0) })
            ChatPane(current, mine, "mine", mineList, padding, Modifier.width(maxWidth).offset { IntOffset(((1 - shift) * width).roundToInt(), 0) })
            ChatPane(current, watching, "watching", watchingList, padding, Modifier.width(maxWidth).offset { IntOffset(((2 - shift) * width).roundToInt(), 0) })
        }
        Row(
            Modifier.align(Alignment.TopCenter).fillMaxWidth().onSizeChanged { topBar = it.height }.glass(haze)
                .windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Settings, at the top left (SettingsHome.kt): the account, the workspace's things, this device's.
            Box(Modifier.semantics { contentDescription = t("android-chat.home.settings") }) { NavButton(Icons.Settings, { app.push(Screen.Settings) }, 22.dp) }
            Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { openWorkspaces(app) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(current.workspace.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                // The other workspaces have something waiting: its dot by the name, before an invitation's.
                val marks by rememberTopic<WorkspaceMarksView>(app.core, Topics.workspaceMarks(current.workspace.id))
                val others = marks.value?.others
                if (others != null) WorkspaceMark(others, marks.value?.othersLabel.orEmpty())
                else if (invitationsWaiting(app)) Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent).semantics { contentDescription = t("android-chat.home.invited") })
                IconIn(Icons.ChevronDown, 16.dp, C.muted)
            }
            // A newer build of the app: tapped, it is downloaded and handed to the installer (Updates.kt).
            val updates = app.updates
            if (updates.available != null) {
                // Quiet like the bar's other buttons: the icon with a dot; while it downloads, how far it is instead.
                val progress = updates.progress
                if (progress != null) {
                    Text(progress.substringAfter(' ', "…"), fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.semantics { contentDescription = progress })
                } else Box(Modifier.semantics { contentDescription = t("android-chat.home.update", "version" to updates.available?.versionName) }) {
                    NavButton(Icons.Download, { app.scope.launch { updates.install()?.let { app.toast = it } } }, 20.dp)
                    Box(Modifier.align(Alignment.TopEnd).offset((-3).dp, 3.dp).size(13.dp).clip(CircleShape).background(C.bg).padding(2.dp).clip(CircleShape).background(C.accent))
                }
            }
            // The filter, and the archive in its menu, as on the wide screen (web mobile/Home.tsx FilterButton): nothing
            // to narrow or look back on with no station. The accent while it narrows the list.
            if (all.value?.stations?.isNotEmpty() == true) {
                var at by remember { mutableStateOf(Rect.Zero) }
                Box(
                    Modifier.size(34.dp).onGloballyPositioned { at = it.boundsInRoot() }.clip(CircleShape).clickable {
                        // The menu is 180 wide (Sheet.kt MenuHost): its right edge under the button's.
                        val left = at.right - with(density) { 180.dp.toPx() }
                        app.menu = MenuSpec(Rect(left, at.top, left, at.bottom), listOf(
                            MenuItem(t("android-chat.home.filter.all"), if (filter == "all") Icons.Check else null) { app.showChats("all") },
                            MenuItem(t("android-chat.home.filter.mine"), if (filter == "mine") Icons.Check else null) { app.showChats("mine") },
                            MenuItem(t("android-chat.home.filter.watching"), if (filter == "watching") Icons.Check else null) { app.showChats("watching") },
                            MenuItem(t("android-chat.home.filter.archived"), Icons.Archive) { app.push(Screen.Archive) },
                        ))
                    }.semantics { contentDescription = t("android-chat.home.filter.label", "filter" to when (filter) { "mine" -> t("android-chat.home.filter.mine"); "watching" -> t("android-chat.home.filter.watching"); else -> t("android-chat.home.filter.all") }) },
                    contentAlignment = Alignment.Center,
                ) { IconIn(Icons.Filter, 20.dp, if (filter != "all") C.accent else C.ink) }
            }
            // The stations at a glance (ui/StationGlyph.kt); its page says which is which. The core reaching nothing
            // at all (`status` in trouble) puts it to sleep.
            val status by rememberTopic<StatusView>(app.core, Topics.status(scope))
            val counts = glyphCounts(all.value, status.value?.state == "trouble")
            // Asleep, what the core cannot reach says it; else the stations in words (the core's), and what is wrong with them.
            val said = if (counts.asleep) status.value?.text.orEmpty() else all.value?.glyph?.label.orEmpty()
            val label = all.value?.trouble?.let { t("android-chat.home.stations.trouble", "said" to said, "trouble" to it.text) } ?: t("android-chat.home.stations", "said" to said)
            Box(Modifier.size(34.dp).clip(CircleShape).clickable { app.push(Screen.Stations) }.semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
                StationGlyph(counts)
            }
        }
        // Wide (Wide.kt), the new-chat button is at the screen's corner instead, not the column's.
        if (!LocalWide.current) Toolbar(app, decisionsWaiting(current), haze, Modifier.align(Alignment.BottomCenter).onSizeChanged { bottomBar = it.height })
    }
}

/** One of the lists, all, the viewer's or the watching ones: its states (connecting, failing, empty) and its days; an offline station's chats say so row by row. */
@Composable
private fun ChatPane(current: WorkspaceEntry, chats: Topic<ChatsView>, filter: String, list: LazyListState, padding: PaddingValues, modifier: Modifier) {
    val view = chats.value
    val app = LocalApp.current
    // The rows move as the list changes (ListMotion.kt); while a finger is on the list or it scrolls, they keep their
    // places (the web holds them while the mouse is over the list), and move when it is let go.
    val still = reducedMotion()
    val motion = remember(current.workspace.id) { ListMotion() }
    val order = remember(current.workspace.id) { HeldOrder() }
    var pressed by remember { mutableStateOf(false) }
    val hold = pressed || list.isScrollInProgress
    val days = view?.days?.let { raw ->
        for (day in raw) for (item in day.items) MarksSeen.note(rowKey(item), rowTone(item))
        order.of(raw, hold)
    }.orEmpty()
    motion.update(days, Snapshot.withoutReadObservation { list.layoutInfo.visibleItemsInfo.mapNotNullTo(HashSet()) { it.key as? String } }, still)
    Box(modifier.fillMaxHeight().pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            pressed = true
            try {
                do { val e = awaitPointerEvent(PointerEventPass.Initial) } while (e.changes.any { it.pressed })
            } finally { pressed = false }
        }
    }) {
        // Rows gone, each drawn where it was as it goes, under the rows closing over it.
        if (view != null) for (g in motion.ghosts) key(g.key, g.at) { Leaving(g, view, motion) }
    LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = padding) {
        // What the last update brought (Changelog.kt), until it is seen: even while the list is being read.
        item(key = "changelog-news") { ChangelogNews() }
        if (view == null) {
            // Not even the stations known yet: the rows to come, and what is wrong if the list cannot be read (Loading.kt).
            item(key = "wait") { LoadingPill(chats.error?.message ?: t("android-chat.home.loading"), error = chats.error != null) }
            item(key = "placeholders") { PlaceholderRows(7, still = chats.error != null) }
        } else {
            val stations = view.stations
            // A station's link coming back is said on its rows; only with no rows to show does the list say it (the core's
            // `note`): what it waits on over the rows to come, or the stations it cannot read over faded ones.
            val note = view.note
            if (note?.reading == true) item(key = "loading") { LoadingPill(note.text ?: t("android-chat.home.loading")) }
            note?.failing?.forEach { s -> item(key = "e/${s.station}") { LoadingPill(s.text, error = true) } }
            val waiting = note?.reading == true
            if (waiting || note?.failing?.isNotEmpty() == true) item(key = "placeholders") { PlaceholderRows(if (waiting) 7 else 4, still = !waiting) }
            if (note?.empty == true) item(key = "empty") { Empty(current, view, filter) }
            // What is left up a long while on the stations (OpenJobs.kt): nothing while there is none.
            item(key = "open-jobs") { OpenJobs(current.workspace.id) }
            for (day in days) {
                item(key = dayKey(day)) { Moving(motion, dayKey(day), still) { SectionHeader(day.label) } }
                items(day.items, key = ::rowKey) { Moving(motion, rowKey(it), still) { ChatRow(it, view, motion = motion) } }
            }
        }
    }
    }
}

/**
 * A row (or day heading) of the list as it moves: from where it was to where it is (the web's MOVE spring, a little
 * late when closing over one gone), growing in when new, and on a ground of its own over the rest when it overtakes
 * them on its way up (web: listMotion.ts).
 */
@Composable
private fun LazyItemScope.Moving(motion: ListMotion, key: String, still: Boolean, content: @Composable () -> Unit) {
    val arrive = remember { if (!still && motion.arriving(key)) Animatable(0f) else null }
    if (arrive != null) LaunchedEffect(Unit) { delay(100); arrive.animateTo(1f, tween(240, easing = ArriveEasing)) }
    val lift = motion.liftedAt(key)
    val raise = remember { Animatable(1f) }
    LaunchedEffect(lift) {
        if (lift == null) return@LaunchedEffect
        try { raise.snapTo(0f); raise.animateTo(1f, tween(480, easing = LinearEasing)) } finally { if (motion.lifted[key] == lift) motion.lifted.remove(key) }
    }
    val lifting = lift != null && !still
    val ground = lerp(C.bg, C.ink, 0.06f)
    val placement = remember(key) { motion.placement(key) }
    Box(
        Modifier.animateItem(fadeInSpec = null, placementSpec = if (still) null else placement, fadeOutSpec = null)
            .zIndex(if (lifting) 1f else 0f)
            .onGloballyPositioned { motion.placed[key] = it.positionInParent().y }
            .graphicsLayer { arrive?.value?.let { alpha = it; scaleX = 0.9f + 0.1f * it; scaleY = scaleX } }
            .drawBehind {
                if (!lifting) return@drawBehind
                // Held to 60 %, then fading as it arrives (the web's keyframes: ground, ground at 0.6, transparent).
                val p = raise.value
                val a = if (p < 0.6f) 1f else 1f - (p - 0.6f) / 0.4f
                if (a > 0f) drawRect(ground.copy(alpha = a))
            },
    ) { content() }
}

/** A row gone from the list: a copy of it where it was shrinks and fades (200 ms, ease-out), then is dropped. */
@Composable
private fun Leaving(g: Ghost, view: ChatsView, motion: ListMotion) {
    val p = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        try { p.animateTo(1f, tween(LEAVE_MS, easing = CssEaseOut)) } finally { motion.ghosts.remove(g) }
    }
    Box(
        Modifier.fillMaxWidth().offset { IntOffset(0, g.y.roundToInt()) }
            .graphicsLayer { alpha = 1f - p.value; scaleX = 1f - 0.1f * p.value; scaleY = scaleX }
            .semantics { hideFromAccessibility() },
    ) {
        if (g.item != null) ChatRow(g.item, view, live = false) else if (g.label != null) SectionHeader(g.label)
    }
}

@Composable
private fun Empty(current: WorkspaceEntry, view: ChatsView, filter: String) {
    val app = LocalApp.current
    // No station yet: nothing else works, so adding the first one is the page.
    if (view.stations.isEmpty() && filter == "all") return FirstStation(current)
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 240.dp)
        if (filter == "mine") Text(t("android-chat.home.empty.mine"), fontSize = 14.sp, color = C.muted)
        else if (filter == "watching") Text(t("android-chat.home.empty.watching"), fontSize = 14.sp, color = C.muted)
        else {
            Text(if (view.stations.size > 1) t("android-chat.home.empty.many") else t("android-chat.home.empty.one"), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            Text(t("android-chat.newChat"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { app.push(Screen.NewChat) })
        }
    }
}

/**
 * A row: its title (bold while something in it is unread) and, for an agent that came from Slack, the connect's mark;
 * under it the last thing said; the chat's state a dot before its title (ChatMark), who is in it small at
 * the second line's end (RowPicture.kt). Two lines, always the same height. The
 * time shows only while the row is held.
 */
@Composable
private fun ChatRow(item: ChatItem, view: ChatsView, live: Boolean = true, motion: ListMotion? = null) {
    val app = LocalApp.current
    val haptics = LocalHapticFeedback.current
    var held by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    // Its state line (in the root, as `bounds`): tapped while it names a message (`stateAbout`), the chat opens there.
    var line by remember { mutableStateOf(Rect.Zero) }
    if (app.menu == null && menuOpen) menuOpen = false
    // Nothing left in it: archived with one tap on the 归档 at its start (as its menu's 归档), or swiped away to the left.
    val archivable = live && item.archivable == true && item.offline == null && item.pending != true
    val onArchive = if (archivable) ({ if (!rowBusy(app, item)) archiveRow(app, item) }) else null
    val body = Modifier.onGloballyPositioned { bounds = it.boundsInRoot() }.then(if (!live) Modifier else Modifier.pointerInput(item.station, item.id, item.pinned, item.title, item.offline, item.pending, item.stateAbout) {
        detectTapGestures(
            onPress = { tryAwaitRelease(); held = false },
            onLongPress = { at ->
                held = true
                // Held long, what can be done to the chat, as the wide screen's right click: always just below the row (over it
                // when there is no room below), centred on the finger across (the menu is 180 wide, Sheet.kt MenuHost, which keeps it on the screen).
                val items = rowMenu(app, item) ?: return@detectTapGestures
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                menuOpen = true
                val x = bounds.left + at.x - 90.dp.toPx()
                app.menu = MenuSpec(Rect(x, bounds.top, x, bounds.bottom), items, onDismiss = { menuOpen = false })
            },
            onTap = { at ->
                val about = item.stateAbout?.takeIf { line.contains(bounds.topLeft + at) }
                app.push(Screen.Chat(item.station, item.page, at = about))
            },
        )
    })
    if (!archivable) return ChatRowBody(item, view.leading ?: "agents", held || menuOpen, busy = rowBusy(app, item), failed = rowFailed(app, item), onStateLine = { line = it }, modifier = body)
    SwipeToArchive(item, motion) {
        ChatRowBody(item, view.leading ?: "agents", held || menuOpen, busy = rowBusy(app, item), failed = rowFailed(app, item), onArchive = onArchive, onStateLine = { line = it }, modifier = body)
    }
}

/** Let go past this share of its width (or flung left), a row is archived. */
private const val ARCHIVE_AT = 0.35f

/**
 * An archivable row, swiped left to archive it (web mobile/Home.tsx): it follows the finger, uncovering 归档 at the
 * right edge (filled in ink once letting go would archive it); let go past [ARCHIVE_AT] of its width or flung left, it
 * goes off to the left and is archived (no copy left behind as it leaves the list, ListMotion.swiped), else it springs
 * back. Archiving refused, it comes back. The drag is read on the row's frame, which does not move, before the row
 * itself (PointerEventPass.Initial): across first it is the swipe and the row's tap and hold let go; up or down first
 * it is the list's (it scrolls). One keeping watch springs back and asks first, as its menu's 归档.
 */
@Composable
private fun SwipeToArchive(item: ChatItem, motion: ListMotion?, content: @Composable () -> Unit) {
    val app = LocalApp.current
    val haptics = LocalHapticFeedback.current
    val still = reducedMotion()
    val scope = rememberCoroutineScope()
    val key = rowKey(item)
    val drag = remember { Animatable(0f) }
    var width by remember { mutableIntStateOf(1) }
    var gone by remember { mutableStateOf(false) }
    val past = drag.value < -width * ARCHIVE_AT
    val fill by animateFloatAsState(if (past) 1f else 0f, tween(140), label = "archive-fill")

    fun back(v: Float = 0f) { scope.launch { if (still) drag.snapTo(0f) else drag.animateTo(0f, MoveSpring, v) } }
    fun archive(v: Float) {
        if (gone || rowBusy(app, item)) return back(v)
        if (item.watch != null) { back(v); archiveRow(app, item); return }
        gone = true
        motion?.swiped?.add(key)
        scope.launch {
            if (!still) drag.animateTo(-width.toFloat(), tween(200, easing = Ease.Standard), v) else drag.snapTo(-width.toFloat())
            app.act(t("android-chat.archive.verb"), failed = { motion?.swiped?.remove(key); gone = false; back() }) {
                app.api(item.station).setArchived(item.thread, item.session, true); app.toast = t("android-chat.archived")
            }
        }
    }

    Box(
        Modifier.fillMaxWidth().clipToBounds().onSizeChanged { width = it.width.coerceAtLeast(1) }
            .pointerInput(key) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    if (gone) return@awaitEachGesture
                    val tracker = VelocityTracker()
                    var pos = drag.value
                    var across = 0f
                    var upDown = 0f
                    var swiping = false
                    var wasPast = false
                    while (true) {
                        val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) {
                            if (swiping) {
                                change.consume()
                                val v = tracker.calculateVelocity().x
                                val at = drag.value
                                val fling = v < -500.dp.toPx() && at < -16.dp.toPx()
                                if (at < -width * ARCHIVE_AT || fling) archive(v) else back(v)
                            }
                            break
                        }
                        val dx = change.position.x - change.previousPosition.x
                        if (!swiping) {
                            across += dx
                            upDown += change.position.y - change.previousPosition.y
                            // Up or down first: the list's (it scrolls), not a swipe.
                            if (abs(upDown) > viewConfiguration.touchSlop && abs(upDown) > abs(across)) break
                            if (abs(across) <= viewConfiguration.touchSlop) continue
                            // Right from where it rests: nothing there.
                            if (across > 0 && pos >= 0f) break
                            swiping = true
                            tracker.resetTracking()
                        }
                        change.consume()
                        tracker.addPosition(change.uptimeMillis, change.position)
                        pos = (pos + dx).coerceIn(-width.toFloat(), 0f)
                        val to = pos
                        val nowPast = to < -width * ARCHIVE_AT
                        if (nowPast != wasPast) { wasPast = nowPast; if (nowPast) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
                        scope.launch { drag.snapTo(to) }
                    }
                }
            }
            .semantics { customActions = listOf(CustomAccessibilityAction(t("android-chat.archive")) { archive(0f); true }) },
    ) {
        // Under it, at the right edge it uncovers: 归档, quiet until letting go would archive it, then filled in ink.
        if (drag.value != 0f) Box(
            Modifier.matchParentSize().background(lerp(C.chip, C.ink, fill)).padding(horizontal = 22.dp),
            contentAlignment = Alignment.CenterEnd,
        ) {
            Text(t("android-chat.archive"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = lerp(C.muted, C.bg, fill), modifier = Modifier.semantics { hideFromAccessibility() })
        }
        Box(Modifier.fillMaxWidth().graphicsLayer { translationX = drag.value }.background(if (drag.value != 0f) C.bg else Color.Transparent)) { content() }
    }
}

/**
 * What can be done to a chat from its row (web mobile/Home.tsx useRowMenu): pin it, rename it, archive it. None for a
 * new chat its station has not made yet, or one on a station offline.
 */
private fun rowMenu(app: AppState, item: ChatItem): List<MenuItem>? {
    // Pinning or archiving under way (a spinner on the row): not asked again meanwhile.
    if (item.offline != null || item.pending == true || rowBusy(app, item)) return null
    val api = app.api(item.station)
    fun run(what: String, block: suspend () -> Unit) = app.act(what) { block() }
    return listOfNotNull(
        // A station from before pins says nothing of them: its chats are not pinned from here.
        item.pinned?.let { pinned -> MenuItem(if (pinned) t("android-chat.unpin") else t("android-chat.pin"), Icons.Pin) { run(if (pinned) t("android-chat.unpin.verb") else t("android-chat.pin.verb")) { api.setPinned(item.session, !pinned) } } },
        MenuItem(t("android-chat.rename"), Icons.Edit) { askTitle(app, item.station, item.thread, item.session, item.title) },
        MenuItem(t("android-chat.archive"), Icons.Archive) { archiveRow(app, item) },
    )
}

/** Archives a row's chat; one keeping watch only once asked: its watch runs on in the archive (the core's words). */
private fun archiveRow(app: AppState, item: ChatItem) {
    val api = app.api(item.station)
    val watch = item.watch
    if (watch != null) confirm(app, t("android-chat.archive.ask", "title" to item.title), watch.ask, t("android-chat.archive"), what = t("android-chat.archive.verb")) { api.setArchived(item.thread, item.session, true); app.toast = t("android-chat.archived") }
    else app.act(t("android-chat.archive.verb")) { api.setArchived(item.thread, item.session, true); app.toast = t("android-chat.archived") }
}

/** Whether the row's menu set its chat's pin or archive going, not answered yet. */
private fun rowBusy(app: AppState, item: ChatItem): Boolean =
    app.isDoing(setOf("chat.pin", "chat.archive"), "station" to item.station, "session" to item.session)

/** Why the row's menu's pin or archive failed a moment ago, if it did. */
private fun rowFailed(app: AppState, item: ChatItem): String? =
    app.failedOf(setOf("chat.pin", "chat.archive"), "station" to item.station, "session" to item.session)

/** What a row shows, `lead` leading who is in it (RowPicture.kt); the time while it is `held`; `busy`: a spinner where its mark goes; `failed`: a red mark there a moment (DoingMark). */
@Composable
internal fun ChatRowBody(item: ChatItem, lead: String, held: Boolean, busy: Boolean = false, failed: String? = null, onArchive: (() -> Unit)? = null, onStateLine: (Rect) -> Unit = {}, modifier: Modifier = Modifier) {
    Box(
        Modifier.fillMaxWidth().height(66.dp).background(if (held) C.ink.copy(alpha = 0.05f) else androidx.compose.ui.graphics.Color.Transparent)
            .then(modifier),
    ) {
        // Its station offline: greyed, and marked where a Slack chat's mark goes (the core says so, row by row).
        val offline = item.offline
        val dim = if (offline != null) 0.45f else 1f
        // Nothing left in it (its agents all done, nothing at work, waiting or unread): the row faded (the core says so),
        // its 归档 at its start not.
        Row(Modifier.fillMaxSize().padding(start = 22.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        // A small 归档 at its start (a tap archives it; swiping it left does too, SwipeToArchive).
        if (onArchive != null) Box(
            Modifier.clip(RoundedCornerShape(50)).background(C.chip).clickable(enabled = !busy, onClick = onArchive)
                .padding(horizontal = 10.dp, vertical = 4.dp).semantics { contentDescription = t("android-chat.archive.named", "title" to item.title) },
            contentAlignment = Alignment.Center,
        ) { Text(t("android-chat.archive"), fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, color = C.muted) }
        Column(Modifier.weight(1f).alpha(if (item.settled == true) 0.45f else 1f), verticalArrangement = Arrangement.Center) {
            Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChatMark(item, Modifier)
                Text(
                    item.title, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = if (item.unread) FontWeight.SemiBold else FontWeight.Normal,
                    color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alpha(dim),
                )
                // Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too.
                Box(Modifier.width(14.dp), contentAlignment = Alignment.Center) {
                    val reconnecting = item.reconnecting
                    if (busy || failed != null) DoingMark(busy, failed, 11.dp)
                    // Its station offline, or its link coming back: unplugged (a spinner is only something its person did).
                    else if (offline != null) Box(Modifier.semantics { contentDescription = offline }) { IconIn(Icons.Unplug, 13.dp, C.subtle) }
                    else if (reconnecting != null) Box(Modifier.semantics { contentDescription = reconnecting }) { IconIn(Icons.Unplug, 13.dp, C.subtle) }
                    else if (item.connect != null) Box(Modifier.semantics { contentDescription = item.originText ?: "Slack" }) { SlackMark(13.dp) }
                }
            }
            Row(Modifier.height(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(Modifier.weight(1f).alpha(dim), contentAlignment = Alignment.CenterStart) {
                    // Where it stands (奏 · …, 在等：…, 做完了), from a station that says; else what was said last.
                    val state = item.stateText ?: item.decision?.text
                    if (state != null) StateLine(state, Modifier.fillMaxWidth().onGloballyPositioned { onStateLine(it.boundsInRoot()) }) else item.last?.let { LastMessage(item) }
                }
                if (held) Text(item.time?.get("lastActiveAt")?.ago ?: "", fontSize = 12.sp, color = C.subtle, maxLines = 1)
                else RowAside(item, lead, Modifier.alpha(dim))
            }
        }

        }
    }
}

/**
 * What a chat's row says of it (web/src/ChatMark.tsx): red when it wants someone now, yellow at work, blue ended well
 * and unread; a blue ring when something in it waits on the viewer, a grey one when only on others.
 */
internal enum class RowTone { Busy, Done, Alert, Wait, Other }

/** The core's `tone` when it says one (a station with pieces of work); otherwise from the row's state, as before. */
internal fun rowTone(item: ChatItem): RowTone? = when (item.tone) {
    "alert" -> RowTone.Alert
    "busy" -> RowTone.Busy
    "done" -> RowTone.Done
    "wait" -> RowTone.Wait
    "other" -> RowTone.Other
    else -> when (item.state) {
        "block", "failed" -> RowTone.Alert
        "run" -> RowTone.Busy
        else -> if (item.unread) RowTone.Done else null
    }
}

private val MarkBlue = Color(0xFF3B82F6)
private val MarkRed = Color(0xFFE5484D)
private val MarkYellow = Color(0xFFF2B01E)

/**
 * A chat's state, a dot before its title (web: ChatMark.css.ts chatMarkInline): a blue dot done and unread, a red one
 * with a soft halo to be seen now, a turning yellow ring with a gap at work. Nothing otherwise.
 */
@Composable
private fun ChatMark(item: ChatItem, modifier: Modifier) {
    val tone = rowTone(item) ?: return
    val label = when (tone) {
        RowTone.Busy -> t("android-chat.home.mark.busy"); RowTone.Done -> t("android-chat.home.mark.done"); RowTone.Alert -> t("android-chat.home.mark.alert")
        RowTone.Wait -> t("android-chat.home.mark.wait"); RowTone.Other -> t("android-chat.home.mark.other")
    }
    // A mark that comes while the chat is in view pops in (web: ChatMark.tsx, 320 ms ease-out, 0 → 1.3 at 60 % → 1);
    // ones there when the list is first drawn do not.
    val still = reducedMotion()
    val pop = remember(tone) { if (!still && MarksSeen.fresh(rowKey(item))) Animatable(0f) else null }
    if (pop != null) LaunchedEffect(pop) { pop.animateTo(1f, tween(320, easing = CssEaseOut)) }
    val subtle = C.subtle
    val turn = if (tone == RowTone.Busy && !still) rememberInfiniteTransition(label = "mark")
        .animateFloat(0f, 360f, infiniteRepeatable(tween(1200, easing = LinearEasing)), label = "turn").value else 0f
    Canvas(modifier.size(10.dp).graphicsLayer {
        pop?.value?.let { p -> val k = if (p < 0.6f) 1.3f * p / 0.6f else 1.3f - 0.3f * (p - 0.6f) / 0.4f; scaleX = k; scaleY = k }
    }.semantics { contentDescription = label }) {
        val r = size.minDimension / 2
        val ring = 2.dp.toPx()
        if (tone == RowTone.Alert) drawCircle(MarkRed.copy(alpha = 0.25f), r - 1.dp.toPx() + 3.dp.toPx())
        when (tone) {
            RowTone.Done -> drawCircle(MarkBlue, r - 1.dp.toPx())
            RowTone.Alert -> drawCircle(MarkRed, r - 1.dp.toPx())
            // A hollow ring, 2dp, 9dp across: blue when it waits on the viewer, grey when only on others.
            RowTone.Wait, RowTone.Other -> drawCircle(if (tone == RowTone.Wait) MarkBlue else subtle, 4.5.dp.toPx() - ring / 2, style = Stroke(ring))
            RowTone.Busy -> {
                val inset = ring / 2
                val box = androidx.compose.ui.geometry.Size(size.width - ring, size.height - ring)
                val at = androidx.compose.ui.geometry.Offset(inset, inset)
                // A faint track, a solid three-quarter arc on it; turning.
                drawArc(MarkYellow.copy(alpha = 0.25f), 0f, 360f, false, at, box, style = Stroke(ring))
                // Round ends (web: styles/busyRing.ts), the arc shortened by the half stroke they add so the gap stays a quarter.
                val cap = Math.toDegrees((ring / box.width).toDouble()).toFloat()
                drawArc(MarkYellow, turn + 45f + cap, 270f - 2 * cap, false, at, box, style = Stroke(ring, cap = StrokeCap.Round))
            }
        }
    }
}

/**
 * What a workspace has waiting, as the core says (views/marks.rs): `alert` a red dot with a soft halo, `wait` a blue
 * ring (a card or an agent waits on them), `done` a blue dot; as a chat's mark (ChatMark), still. `label` says it in words.
 */
@Composable
internal fun WorkspaceMark(tone: String, label: String) {
    Canvas(Modifier.size(10.dp).semantics { contentDescription = label }) {
        val r = size.minDimension / 2 - 1.dp.toPx()
        val ring = 2.dp.toPx()
        if (tone == "alert") drawCircle(MarkRed.copy(alpha = 0.25f), r + 3.dp.toPx())
        if (tone == "wait") drawCircle(MarkBlue, 4.5.dp.toPx() - ring / 2, style = Stroke(ring))
        else drawCircle(if (tone == "alert") MarkRed else MarkBlue, r)
    }
}

/**
 * What a workspace has waiting, after its name in the switcher (web: ChatMark.tsx MarkCounts): a red dot and how many
 * of the chats its person takes part in want them, a blue ring and how many wait on them, a blue dot and how many are
 * unread; nothing for none.
 */
@Composable
internal fun MarkCounts(mark: fail.still.android.data.WorkspaceMark) {
    if (mark.tone == null) return
    Row(Modifier.semantics(mergeDescendants = true) { contentDescription = mark.label.orEmpty() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("alert" to mark.alert, "wait" to (mark.wait ?: 0u), "done" to mark.unread).filter { it.second > 0u }.forEach { (tone, n) ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                WorkspaceMark(tone, "")
                Text("$n", fontSize = 12.sp, color = C.muted)
            }
        }
    }
}

/**
 * Where the chat stands, in its last message's place (the core's `stateText`): a decision waiting for the viewer
 * (奏 · …) in ink with its 奏 bold; anything else (在等：…, 做完了) in the secondary colour.
 */
@Composable
private fun StateLine(state: String, modifier: Modifier = Modifier) {
    if (fail.still.android.ui.doneLead.containsMatchIn(state)) {
        fail.still.android.ui.StatusText(
            state, modifier, fontSize = 14.sp, lineHeight = 20.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = androidx.compose.ui.text.TextStyle(lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
                androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center, androidx.compose.ui.text.style.LineHeightStyle.Trim.Both,
            )),
        )
        return
    }
    // The core's lead in either language: 奏 · …, Decision · ….
    val lead = listOf("奏", "Decision").firstOrNull { state == it || state.startsWith("$it · ") }
    val text = androidx.compose.ui.text.buildAnnotatedString {
        if (lead != null) { pushStyle(androidx.compose.ui.text.SpanStyle(fontWeight = FontWeight.Bold)); append(lead); pop(); append(state.substring(lead.length)) }
        else append(state)
    }
    Text(
        text, modifier, fontSize = 14.sp, lineHeight = 20.sp, color = if (lead != null) C.ink else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
        style = androidx.compose.ui.text.TextStyle(lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
            androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center, androidx.compose.ui.text.style.LineHeightStyle.Trim.Both,
        )),
    )
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
@Composable
private fun LastMessage(item: ChatItem) {
    Text(
        item.last!!.preview, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
        style = androidx.compose.ui.text.TextStyle(lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
            androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center, androidx.compose.ui.text.style.LineHeightStyle.Trim.Both,
        )),
    )
}

/** How many decisions wait for the viewer in the workspace (the core's marks: the home page's 奏 N); 0 from a core before them. */
@Composable
internal fun decisionsWaiting(current: WorkspaceEntry): Int {
    val app = LocalApp.current
    val marks by rememberTopic<WorkspaceMarksView>(app.core, Topics.workspaceMarks(current.workspace.id))
    return marks.value?.workspaces?.get(current.workspace.id)?.decisions?.toInt() ?: 0
}

/** 奏 N: the decisions page's way in, there at 0 too (奏 alone then, its padding even), a capsule of the new-chat button's glass (`ground`) beside it, as tall. */
@Composable
internal fun DecisionsCapsule(n: Int, ground: Modifier) {
    val app = LocalApp.current
    Row(
        ground.height(56.dp).clickable { app.push(Screen.Decisions) }.padding(start = 10.dp, end = if (n > 0) 20.dp else 10.dp)
            .semantics(mergeDescendants = true) { contentDescription = t("android-chat.home.decisions", "n" to n) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        IconIn(Icons.Zou, 40.dp, C.ink)
        // How many, drawn (design/icons num-*): 1 to 9, and + past that; 奏 alone at 0.
        if (n > 0) IconIn(if (n in 1..9) listOf(Icons.Num1, Icons.Num2, Icons.Num3, Icons.Num4, Icons.Num5, Icons.Num6, Icons.Num7, Icons.Num8, Icons.Num9)[n - 1] else Icons.NumMore, 24.dp, C.ink)
    }
}

@Composable
private fun Toolbar(app: AppState, decisions: Int, haze: HazeState, modifier: Modifier) {
    // Floating over the list at the bottom right: 奏 N (奏 alone at 0), and the new-chat button, a disc in the
    // accent, no ring.
    Row(
        modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars)
            .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically,
    ) {
        DecisionsCapsule(decisions, Modifier.floating(haze, CircleShape))
        Box(
            Modifier.size(56.dp).shadow(4.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.35f), spotColor = Color.Black.copy(alpha = 0.35f)).clip(CircleShape).background(C.accent)
                .clickable { app.push(Screen.NewChat) }.semantics { contentDescription = t("android-chat.newChat") },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Ling, 44.dp, Color.White) }
    }
}
