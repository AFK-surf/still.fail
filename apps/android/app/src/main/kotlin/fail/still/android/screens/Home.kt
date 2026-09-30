// Home is the `chats` view as the web's sidebar lists it: one kind of item (an
// agent with its chat, or an agent with no chat yet), newest first and grouped
// by day. A fixed head (you → settings · workspace · stations) and one bottom
// toolbar (全部 / 我参与的 · new chat), like Mail.
package fail.still.android.screens

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
import fail.still.android.data.page
import fail.still.android.data.rememberTopic
import fail.still.android.data.state
import fail.still.android.ui.Avatar
import fail.still.android.ui.Badge
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Illustration
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.Mark
import fail.still.android.ui.NavButton
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.ui.SlackMark
import fail.still.android.ui.avatarColor
import kotlinx.coroutines.launch
import fail.still.android.ui.initial

@Composable
fun HomeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val scope = current.workspace.id
    // Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
    val all by rememberTopic<ChatsView>(app.core, Topics.chats(scope, false))
    val mine by rememberTopic<ChatsView>(app.core, Topics.chats(scope, true))
    val allList = rememberLazyListState()
    val mineList = rememberLazyListState()
    val shift by animateFloatAsState(if (app.onlyMine) 1f else 0f, tween(240, easing = FastOutSlowInEasing), label = "mine")
    // The lists run under both bars, which are frosted glass over them.
    val haze = remember { HazeState() }
    val density = LocalDensity.current
    var topBar by remember { mutableIntStateOf(0) }
    var bottomBar by remember { mutableIntStateOf(0) }
    val padding = with(density) { PaddingValues(top = topBar.toDp() + 8.dp, bottom = bottomBar.toDp() + 8.dp) }
    Box(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize().clipToBounds().hazeSource(haze)) {
            val width = constraints.maxWidth
            ChatPane(current, all, false, allList, padding, Modifier.width(maxWidth).offset { IntOffset((-shift * width).roundToInt(), 0) })
            ChatPane(current, mine, true, mineList, padding, Modifier.width(maxWidth).offset { IntOffset(((1 - shift) * width).roundToInt(), 0) })
        }
        Row(
            Modifier.align(Alignment.TopCenter).fillMaxWidth().onSizeChanged { topBar = it.height }.glass(haze)
                .windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Avatar(current.account.email, current.account.name.ifEmpty { current.account.email }, 34.dp, Modifier.clip(CircleShape).clickable { app.push(Screen.Me) }, picture = current.account.picture)
            Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { openWorkspaces(app) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(current.workspace.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (invitationsWaiting(app)) Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent).semantics { contentDescription = "有邀请" })
                IconIn(Icons.ChevronDown, 16.dp, C.muted)
            }
            // A newer build of the app: tapped, it is downloaded and handed to the installer (Updates.kt).
            val updates = app.updates
            if (updates.available != null) {
                // Quiet like the bar's other buttons: the icon with a dot; while it downloads, how far it is instead.
                val progress = updates.progress
                if (progress != null) {
                    Text(progress.substringAfter(' ', "…"), fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.semantics { contentDescription = progress })
                } else Box(Modifier.semantics { contentDescription = "更新到 ${updates.available?.versionName}" }) {
                    NavButton(Icons.Download, { app.scope.launch { updates.install()?.let { app.toast = it } } }, 20.dp)
                    Box(Modifier.align(Alignment.TopEnd).offset((-3).dp, 3.dp).size(13.dp).clip(CircleShape).background(C.bg).padding(2.dp).clip(CircleShape).background(C.accent))
                }
            }
            // The archive: chats put away by hand or by the station once idle (the wide screen has it in the list's filter menu).
            if (all.value?.stations?.isNotEmpty() == true) Box(Modifier.semantics { contentDescription = "已归档" }) { NavButton(Icons.Archive, { app.push(Screen.Archive) }, 20.dp) }
            // The stations at a glance (ui/StationGlyph.kt); its page says which is which. The core reaching nothing
            // at all (`status` in trouble) puts it to sleep.
            val status by rememberTopic<StatusView>(app.core, Topics.status(scope))
            val counts = glyphCounts(all.value, status.value?.state == "trouble")
            // Asleep, what the core cannot reach says it; else the stations in words (the core's), and what is wrong with them.
            val said = if (counts.asleep) status.value?.text.orEmpty() else all.value?.glyph?.label.orEmpty()
            val label = "Station：$said" + (all.value?.trouble?.let { "（${it.text}）" } ?: "")
            Box(Modifier.size(34.dp).clip(CircleShape).clickable { app.push(Screen.Stations) }.semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
                StationGlyph(counts)
            }
        }
        Toolbar(app, haze, Modifier.align(Alignment.BottomCenter).onSizeChanged { bottomBar = it.height })
    }
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days; an offline station's chats say so row by row. */
@Composable
private fun ChatPane(current: WorkspaceEntry, chats: Topic<ChatsView>, onlyMine: Boolean, list: LazyListState, padding: PaddingValues, modifier: Modifier) {
    val view = chats.value
    val app = LocalApp.current
    val status by rememberTopic<StatusView>(app.core, Topics.status(current.workspace.id))
    // "Reading", and what the core has been waiting on for a while if anything (the core's `status`).
    val reading = status.value?.text?.let { "正在读取会话… $it" } ?: "正在读取会话…"
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
        if (view == null) {
            item(key = "wait") { Note(chats.error?.message ?: reading, error = chats.error != null) }
        } else {
            val stations = view.stations
            // A station's link coming back is said on its rows; only with no rows to show does the list say it (the core's `note`).
            val note = view.note
            if (note?.reading == true) item(key = "loading") { Note(reading) }
            note?.failing?.forEach { s -> item(key = "e/${s.station}") { Note(s.text, error = true) } }
            if (note?.empty == true) item(key = "empty") { Empty(current, view, onlyMine) }
            // What is left up a long while on the stations (OpenJobs.kt): nothing while there is none.
            item(key = "open-jobs") { OpenJobs(current.workspace.id) }
            for (day in days) {
                item(key = dayKey(day)) { Moving(motion, dayKey(day), still) { SectionHeader(day.label) } }
                items(day.items, key = ::rowKey) { Moving(motion, rowKey(it), still) { ChatRow(it, view) } }
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
private fun Note(text: String, error: Boolean = false) =
    Text(text, color = if (error) C.red else C.muted, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))

@Composable
private fun Empty(current: WorkspaceEntry, view: ChatsView, onlyMine: Boolean) {
    val app = LocalApp.current
    // No station yet: nothing else works, so adding the first one is the page.
    if (view.stations.isEmpty() && !onlyMine) return FirstStation(current)
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 240.dp)
        if (onlyMine) Text("没有你参与的会话。", fontSize = 14.sp, color = C.muted)
        else {
            Text("还没有会话。在 Slack 里 @ ${if (view.stations.size > 1) "它们" else "它"}，或者", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            Text("新建对话", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { app.push(Screen.NewChat) })
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
private fun ChatRow(item: ChatItem, view: ChatsView, live: Boolean = true) {
    val app = LocalApp.current
    var held by remember { mutableStateOf(false) }
    ChatRowBody(item, view.leading ?: "agents", held, Modifier.then(if (!live) Modifier else Modifier.pointerInput(item.station, item.id) {
        detectTapGestures(
            onPress = { tryAwaitRelease(); held = false },
            onLongPress = { held = true },
            onTap = { app.push(Screen.Chat(item.station, item.page)) },
        )
    }))
}

/** What a row shows, `lead` leading who is in it (RowPicture.kt); the time while it is `held`. */
@Composable
internal fun ChatRowBody(item: ChatItem, lead: String, held: Boolean, modifier: Modifier = Modifier) {
    Box(
        Modifier.fillMaxWidth().height(66.dp).background(if (held) C.ink.copy(alpha = 0.05f) else androidx.compose.ui.graphics.Color.Transparent)
            .then(modifier),
    ) {
        // Its station offline: greyed, and marked where a Slack chat's mark goes (the core says so, row by row).
        val offline = item.offline
        val dim = if (offline != null) 0.45f else 1f
        Row(Modifier.fillMaxSize().padding(start = 22.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChatMark(item, Modifier)
                Text(
                    item.title, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = if (item.unread) FontWeight.SemiBold else FontWeight.Normal,
                    color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alpha(dim),
                )
                // Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too.
                Box(Modifier.width(14.dp), contentAlignment = Alignment.Center) {
                    val reconnecting = item.reconnecting
                    if (offline != null) Box(Modifier.semantics { contentDescription = offline }) { IconIn(Icons.Unplug, 13.dp, C.subtle) }
                    else if (reconnecting != null) Box(Modifier.semantics { contentDescription = reconnecting }) { Spinner(11.dp) }
                    else if (item.connect != null) Box(Modifier.semantics { contentDescription = item.originText ?: "Slack" }) { SlackMark(13.dp) }
                }
            }
            Row(Modifier.height(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(Modifier.weight(1f).alpha(dim), contentAlignment = Alignment.CenterStart) { item.last?.let { LastMessage(item) } }
                if (held) Text(item.time?.get("lastActiveAt")?.ago ?: "", fontSize = 12.sp, color = C.subtle, maxLines = 1)
                else RowAside(item, lead, Modifier.alpha(dim))
            }
        }
        }
    }
}

/** What a chat's row says of it (web/src/ChatMark.tsx): red when it wants someone now, yellow at work, blue ended well and unread. */
internal enum class RowTone { Busy, Done, Alert }

internal fun rowTone(item: ChatItem): RowTone? = when (item.state) {
    "block", "failed" -> RowTone.Alert
    "run" -> RowTone.Busy
    else -> if (item.unread) RowTone.Done else null
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
    val label = when (tone) { RowTone.Busy -> "工作中"; RowTone.Done -> "做完了，有新消息"; RowTone.Alert -> "需要处理" }
    // A mark that comes while the chat is in view pops in (web: ChatMark.tsx, 320 ms ease-out, 0 → 1.3 at 60 % → 1);
    // ones there when the list is first drawn do not.
    val still = reducedMotion()
    val pop = remember(tone) { if (!still && MarksSeen.fresh(rowKey(item))) Animatable(0f) else null }
    if (pop != null) LaunchedEffect(pop) { pop.animateTo(1f, tween(320, easing = CssEaseOut)) }
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

@Composable
private fun Toolbar(app: AppState, haze: HazeState, modifier: Modifier) {
    // One capsule floating over the list, round at both ends like what is in it: the switch fills it, the capsule being its track, and the new-chat button
    // closes it at the right, a disc in the accent (no line between them: shape and colour tell them apart).
    Row(
        modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars)
            .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp)
            .floating(haze, RoundedCornerShape(percent = 50)).padding(6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Seg(
            listOf("全部", "我参与的"), if (app.onlyMine) 1 else 0, { app.showOnlyMine(it == 1) },
            Modifier.weight(1f), height = 44.dp, fill = true, radius = 22.dp, inset = 0.dp, track = false,
        )
        Box(
            Modifier.size(44.dp).clip(CircleShape).background(C.accent).clickable { app.push(Screen.NewChat) },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Edit, 20.dp, Color.White) }
    }
}
