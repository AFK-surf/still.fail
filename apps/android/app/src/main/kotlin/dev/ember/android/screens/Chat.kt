// An item's page, one for every item (web/src/pages/ChatPage.tsx, Chat.tsx):
// its chat's messages (none before its agent has a chat), the composer, and
// each agent's execution history as a sheet opened from its mark or name.
// Your messages sit right in a bubble; everyone else gets a face, a name and
// the time over their words. Long-press quotes or copies a message; ＋ adds files.
package dev.ember.android.screens

import androidx.compose.ui.graphics.Shape
import dev.ember.android.ui.InComposer
import dev.ember.android.ui.ComposerInset
import dev.ember.android.ui.ComposerCorner
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.LruCache
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.Screen
import dev.ember.android.data.ActivityRowView
import dev.ember.android.data.Attachment
import dev.ember.android.data.ChatAgentView
import dev.ember.android.data.ChatOf
import dev.ember.android.data.ChatState
import dev.ember.android.data.ChatView
import dev.ember.android.data.ChatsView
import dev.ember.android.data.LiveView
import dev.ember.android.data.MessageView
import dev.ember.android.data.OutboxItem
import dev.ember.android.data.PROCESS_LABEL
import dev.ember.android.data.Quote
import dev.ember.android.data.ThreadView
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceView
import dev.ember.android.data.agentLabel
import dev.ember.android.data.elapsed
import dev.ember.android.data.isMe
import dev.ember.android.data.relativeTime
import dev.ember.android.data.rememberTopic
import dev.ember.android.data.state
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.Edge
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.Loading
import dev.ember.android.ui.Mark
import dev.ember.android.ui.Markdown
import dev.ember.android.ui.MenuItem
import dev.ember.android.ui.MenuSpec
import dev.ember.android.ui.ModelMark
import dev.ember.android.ui.NavBar
import dev.ember.android.ui.NavButton
import dev.ember.android.ui.PeopleStack
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.android.ui.SlackMark
import dev.ember.android.ui.awayFromEnd
import dev.ember.android.ui.endInView
import dev.ember.android.ui.floating
import dev.ember.android.ui.glass
import dev.ember.android.ui.rememberFollow
import dev.ember.core.CoreException
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The station part of an address ("ws/studio" → "studio"). */
fun stationName(address: String) = address.substringAfter('/')

/** People by email, from the workspace's members: how the web names people too. */
@Composable
fun rememberPeople(station: String): (String) -> String? {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(station.substringBefore('/')))
    val members = ws.value?.members.orEmpty().associate { it.email.lowercase() to it.name }
    return { id -> members[id.lowercase()]?.takeIf { it.isNotEmpty() } }
}

/** A station's name in its workspace. */
@Composable
fun rememberStationName(station: String): String {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(station.substringBefore('/')))
    return ws.value?.stations?.firstOrNull { it.id == stationName(station) }?.name ?: stationName(station)
}

/** An agent of this chat as its messages and activity show it: who it is, and its execution history as it runs. */
class ChatAgent(val view: ChatAgentView, val live: LiveView?) {
    val key get() = view.session.key
    val runtime get() = view.session.runtime
    val model get() = live?.usage?.model ?: view.session.model
    val who get() = agentLabel(model, view.session.effort)
    val state get() = view.state
}

@Composable
fun ChatScreen(station: String, of: ChatOf) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
    val view = chat.value
    if (view == null) {
        // Until the core has the chat, the page is already a chat's page (its bar, empty): what comes fills it in
        // place instead of replacing another page.
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
            BarFrame("", more = false) {}
            val error = chat.error
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (error != null) Text("读不到这个对话：${error.message}", color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(32.dp))
            }
        }
        return
    }
    val agents = view.agents.map { a ->
        key(a.session.key) { ChatAgent(a, rememberTopic<LiveView>(app.core, Topics.live(station, a.session.key)).value.value) }
    }
    val draft = remember { Draft() }
    // The messages run under the bar and the composer, which are frosted glass over them.
    val haze = remember { HazeState() }
    val density = LocalDensity.current
    var topBar by remember { mutableIntStateOf(0) }
    var bottomBar by remember { mutableIntStateOf(0) }
    // Its own paper under all of it: the bars are see-through, and what is under the page must not show in them.
    Box(Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
        Messages(station, of, view, agents, draft, haze, Modifier.fillMaxSize().background(C.bg), with(density) { topBar.toDp() }, with(density) { bottomBar.toDp() })
        ChatBar(station, of, view, agents, Modifier.align(Alignment.TopCenter).onSizeChanged { topBar = it.height }.glass(haze, Edge.Top))
        Composer(station, of, view, agents, draft, haze, Modifier.align(Alignment.BottomCenter).onSizeChanged { bottomBar = it.height })
    }
}

/** The chat's bar: its title from the left, then its people, then its agents' marks (each opens its history); "…" is the chat's own page. */
@Composable
private fun ChatBar(station: String, of: ChatOf, view: ChatView, agents: List<ChatAgent>, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val thread = view.thread
    BarFrame(view.title, more = thread != null, onMore = { if (thread != null) openChatInfo(app, station, of, thread) }, modifier = modifier) {
        if (view.people.isNotEmpty()) PeopleStack(view.people.take(5), 16.dp)
        agents.forEach { a ->
            // Not clipped: the state's dot sits over the mark's corner, partly outside it.
            Box(Modifier.clickable { openHistory(app, station, of, a.key) }) { ModelMark(a.model, a.runtime, 22.dp, a.state) }
        }
    }
}

/** The bar's frame, the same while the chat loads and once it has: back, the title, what follows it, and "…". */
@Composable
private fun BarFrame(title: String, more: Boolean, onMore: () -> Unit = {}, modifier: Modifier = Modifier.background(C.bg), after: @Composable RowScope.() -> Unit) {
    val app = LocalApp.current
    Column(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars)) {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 6.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).clip(CircleShape).clickable(onClick = app::pop), contentAlignment = Alignment.Center) { IconIn(Icons.Back, 22.dp, C.accent) }
            Row(Modifier.weight(1f).padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                after()
            }
            if (more) NavButton(Icons.More, onMore)
        }
    }
}

// ── the list ───────────────────────────────────────────────────────────

/** A long chat coming in from its newest: how many of its last rows are in the list so far. */
private class Reveal {
    var decided = false
    var count by mutableIntStateOf(Int.MAX_VALUE)
    val revealing get() = count != Int.MAX_VALUE
}

/** An item new to the list comes up a little as it fades in. */
@Composable
private fun Modifier.rise(on: Boolean): Modifier {
    if (!on) return this
    val from = with(LocalDensity.current) { 14.dp.toPx() }
    val y = remember { Animatable(1f) }
    LaunchedEffect(Unit) { y.animateTo(0f, tween(320, easing = FastOutSlowInEasing)) }
    return graphicsLayer { translationY = y.value * from }
}

private sealed interface Entry {
    val id: String
    data object Older : Entry { override val id = "older" }
    data object Empty : Entry { override val id = "empty" }
    data object Line : Entry { override val id = "line" }
    data class Said(val m: MessageView) : Entry { override val id get() = "m:${m.ts}" }
    data class Out(val o: OutboxItem) : Entry { override val id get() = "o:${o.id}" }
    data class Working(val agent: AgentAtWork) : Entry { override val id get() = "act:${agent.key}" }
    /** The room an activity that folded away leaves behind (as the web's floor): what is above it does not drop. */
    data class Floor(val px: Int) : Entry { override val id get() = "floor" }
}

/** An agent at work: who it is, its transcript and steps in flight, and since when its turn runs. */
class AgentAtWork(val key: String, val who: String, val runtime: String, val model: String?, val live: LiveView?, val since: Long?)

/** What the messages need to know about the chat: who is who, and whose workspace keeps a file. */
private class Here(val station: String, val of: ChatOf, val view: ChatView, val agents: List<ChatAgent>, val person: (String) -> String?) {
    val mentions: Map<String, String> = view.agents.mapNotNull { a -> a.connect?.let { c -> c.botUserId?.let { it to c.name } } }.toMap()
    fun agent(key: String) = agents.firstOrNull { it.key == key }
    fun mine(m: MessageView) = m.mine
    fun name(m: MessageView) = person(m.author) ?: m.authorName ?: if (m.author == "local") "本机" else m.author
    /** Slack's <@U…> mentions by name: an agent's bot by its connect's, a person by theirs where known. */
    fun mention(text: String) = text.replace(Regex("<@([A-Z0-9]+)>")) { r -> "@" + (mentions[r.groupValues[1]] ?: person(r.groupValues[1]) ?: r.groupValues[1]) }
    /** Files are kept in a session's workspace: the agent whose workspace holds it, else the first. */
    fun owner(file: Attachment): String? = agents.firstOrNull { file.path.startsWith("${it.view.session.workspace}/") }?.key ?: agents.firstOrNull()?.key
}

/** `top` and `bottom`: the bars over it, which the list keeps its ends clear of. */
@Composable
private fun Messages(station: String, of: ChatOf, view: ChatView, agents: List<ChatAgent>, draft: Draft, haze: HazeState, modifier: Modifier, top: Dp = 0.dp, bottom: Dp = 0.dp) {
    val app = LocalApp.current
    val ctx = Here(station, of, view, agents, rememberPeople(station))
    val thread = view.thread
    val api = app.api(station)
    val messages = view.messages

    // Where the viewer had read up to when the chat opened, and when that was; it stays put for the visit. The line
    // goes over the first message after it that is not theirs and was said before the chat opened, whether it came
    // from what the device kept or from the station a moment later.
    val open = remember { (thread?.read ?: 0L) to System.currentTimeMillis() }
    val (readAt, openedAt) = open
    val unread = { m: MessageView -> m.seq > readAt && m.createdAt <= openedAt && !ctx.mine(m) }
    val first = view.messages.firstOrNull()?.seq
    // Those not loaded yet may hold it: the pages before are loaded first.
    val above = view.more && first != null && first > readAt + 1 && messages.any(unread)
    val lineAt = if (above) null else messages.firstOrNull(unread)?.seq
    LaunchedEffect(above, first) { if (above && thread != null) try { api.older(thread.id) } catch (_: CoreException) {} }

    // Messages the agents have not taken yet are the last people wrote; after a second, yours say they wait.
    val waiting = agents.maxOfOrNull { it.view.session.pending } ?: 0
    val pending = if (waiting > 0) messages.filter { it.authorKind == "person" }.takeLast(waiting).map { it.seq }.toSet() else emptySet()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val youngest = messages.filter { it.seq in pending }.maxOfOrNull { it.createdAt } ?: 0
    LaunchedEffect(youngest) {
        val wait = youngest + 1000 - System.currentTimeMillis()
        if (youngest > 0 && wait > 0) { delay(wait + 20); now = System.currentTimeMillis() }
    }

    // Agents at work; a message on its way already counts, for every agent it goes to.
    val working = agents.filter { it.state == ChatState.Running }
    val sendingNow = view.outbox.any { it.state == "sending" }
    val busy = working.ifEmpty { if (sendingNow) agents else emptyList() }.map { a ->
        val last = a.view.turns.lastOrNull()
        AgentAtWork(a.key, a.who, a.runtime, a.model, a.live, last?.takeIf { it.endedAt == null }?.startedAt)
    }
    // When the turn ends, the activity stays a moment to fade and fold away instead of vanishing.
    val lastBusy = remember { mutableStateOf<List<AgentAtWork>>(emptyList()) }
    var leaving by remember { mutableStateOf(false) }
    if (busy.isNotEmpty()) lastBusy.value = busy
    LaunchedEffect(busy.isEmpty()) {
        leaving = false
        if (busy.isEmpty() && lastBusy.value.isNotEmpty()) {
            delay(1200); leaving = true; delay(520)
            lastBusy.value = emptyList(); leaving = false
        }
    }
    val atWork = busy.ifEmpty { lastBusy.value }
    // The list never gets shorter under the reader: an activity that folds away leaves its height as a floor, which
    // what comes next (a message, another activity) takes back as it arrives.
    val heights = remember { HashMap<String, Int>() }
    var floor by remember { mutableIntStateOf(0) }
    val gapPx = with(LocalDensity.current) { 14.dp.roundToPx() }
    val shownAtWork = atWork.isNotEmpty()
    LaunchedEffect(shownAtWork) {
        if (!shownAtWork) floor += heights.filterKeys { it.startsWith("act:") }.values.sum().let { if (it > 0) it + gapPx else 0 }
        heights.keys.removeAll { it.startsWith("act:") }
    }

    val all = buildList {
        if (view.more) add(Entry.Older)
        if (messages.isEmpty() && view.outbox.isEmpty()) add(Entry.Empty)
        messages.forEach { m ->
            if (m.seq == lineAt) add(Entry.Line)
            add(Entry.Said(m))
        }
        view.outbox.forEach { add(Entry.Out(it)) }
        // The activity is always the last thing in the chat (a reply comes whole, as a message).
        atWork.forEach { add(Entry.Working(it)) }
        if (floor > 0) add(Entry.Floor(floor))
    }

    val placeKey = "$station:${thread?.id ?: agents.firstOrNull()?.key ?: ""}"
    // A long chat opened at its newest: the newest few first, at the bottom, and the rest rising in above them a
    // few a frame, rather than one frame building a screenful. (Opened elsewhere, at a place or the unread line,
    // it is all there at once, to be put in place.)
    val reveal = remember { Reveal() }
    if (!reveal.decided && messages.isNotEmpty()) {
        reveal.decided = true
        if (all.size > 8 && app.places[placeKey] == null && all.none { it is Entry.Line }) reveal.count = 3
    }
    val allSize by rememberUpdatedState(all.size)
    LaunchedEffect(reveal.decided) {
        while (reveal.decided && reveal.revealing) {
            withFrameNanos { }
            reveal.count = if (reveal.count + 2 >= allSize) Int.MAX_VALUE else reveal.count + 2
        }
    }
    val rows = if (reveal.count < all.size) all.takeLast(reveal.count) else all
    // What was in the list the last time it was drawn: an item new to it rises in; one scrolled to does not.
    val known = remember { HashSet<String>() }
    SideEffect { rows.forEach { known += it.id } }
    // The list starts where it is going (where the chat was left, the unread line, or the newest), rather than
    // composing its top only to jump away from it.
    val list = rememberLazyListState(
        initialFirstVisibleItemIndex = app.places[placeKey]?.let { (id, _) -> rows.indexOfFirst { it.id == id } }?.takeIf { it >= 0 }
            ?: rows.indexOfFirst { it is Entry.Line }.takeIf { it >= 0 } ?: rows.lastIndex.coerceAtLeast(0),
    )
    val follow = rememberFollow(list)
    val density = LocalDensity.current
    // Put in place once: back where the chat was left, else at the unread line, else at the newest.
    val lineShown = remember { mutableStateOf(false) }
    LaunchedEffect(above, messages.isNotEmpty()) {
        if (follow.placed || above) return@LaunchedEffect
        val saved = app.places[placeKey]
        val back = saved?.let { (id, _) -> rows.indexOfFirst { it.id == id } }?.takeIf { it >= 0 }
        val line = rows.indexOfFirst { it is Entry.Line }.takeIf { it >= 0 }
        when {
            back != null -> list.scrollToItem(back, -saved.second)
            line != null -> list.scrollToItem(line, -with(density) { 12.dp.roundToPx() })
            else -> follow.toEnd()
        }
        // Coming back goes to where the chat was left, not to the line.
        lineShown.value = back != null || line != null
        follow.placed = true
        follow.on = !list.canScrollForward
    }
    // Something unread that shows only after opening (from the station, after what was kept): the chat jumps to it once.
    val lineIndex = rows.indexOfFirst { it is Entry.Line }
    LaunchedEffect(lineIndex, follow.placed) {
        if (!follow.placed || lineShown.value || lineIndex < 0) return@LaunchedEffect
        lineShown.value = true
        follow.anchor = null
        list.scrollToItem(lineIndex, -with(density) { 12.dp.roundToPx() })
        follow.on = !list.canScrollForward
    }
    // A message arriving at the end while it is followed is kept in view from its top (the activity never is: it folds away).
    follow.indexOf = { key -> rows.indexOfFirst { it.id == key } }
    val newestKey = rows.lastOrNull { it !is Entry.Working && it !is Entry.Floor }?.id
    val knownNewest = remember { mutableStateOf<String?>(null) }
    LaunchedEffect(newestKey, follow.placed) {
        if (!follow.placed) return@LaunchedEffect
        if (knownNewest.value != null && newestKey != knownNewest.value && follow.on) follow.anchor = newestKey
        knownNewest.value = newestKey
    }
    // Remember where the chat is left: the message at the top and its offset, so what arrives below does not move it.
    DisposableEffect(placeKey) {
        onDispose {
            list.layoutInfo.visibleItemsInfo.firstOrNull { (it.key as? String)?.startsWith("m:") == true }?.let { app.places[placeKey] = (it.key as String) to it.offset }
        }
    }
    // Near the top: the page before comes in (once per page); what is on screen stays put.
    val asked = remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(view.more, first, follow.placed, reveal.revealing) {
        if (!view.more || thread == null || !follow.placed || reveal.revealing) return@LaunchedEffect
        snapshotFlow { list.firstVisibleItemIndex }.collect { index ->
            if (index <= 2 && asked.value != first) {
                asked.value = first
                try { api.older(thread.id) } catch (_: CoreException) { asked.value = null }
            }
        }
    }
    // What is shown is read: up to the newest message, once the end is in view on a page in front.
    val resumed by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val seen = endInView(list) && follow.placed && resumed.isAtLeast(Lifecycle.State.RESUMED)
    val newest = view.messages.lastOrNull()?.seq ?: 0
    val sent = remember { mutableLongStateOf(0L) }
    LaunchedEffect(seen, newest, thread?.read) {
        if (!seen || thread == null || newest <= thread.read || sent.longValue >= newest) return@LaunchedEffect
        sent.longValue = newest
        try { api.read(thread.id, newest) } catch (_: CoreException) { sent.longValue = 0 }
    }

    Box(modifier.fillMaxWidth()) {
        // The list is what the bars and capsules over it frost (the button over it too, so it is not in it).
        LazyColumn(
            Modifier.fillMaxSize().hazeSource(haze).background(C.bg), state = list,
            contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = top, bottom = bottom + 10.dp), verticalArrangement = Arrangement.spacedBy(14.dp, if (reveal.revealing) Alignment.Bottom else Alignment.Top),
        ) {
            items(rows, key = { it.id }) { row ->
                val fresh = remember(row.id) { row.id !in known }
                Box(Modifier.animateItem(fadeInSpec = tween(250), placementSpec = null, fadeOutSpec = tween(200)).rise(fresh).onSizeChanged { size ->
                    if (row is Entry.Floor) return@onSizeChanged
                    val before = heights.put(row.id, size.height)
                    // Something new took its place at the bottom: the floor gives that much back.
                    if (before == null && fresh && floor > 0) floor = (floor - size.height - gapPx).coerceAtLeast(0)
                }) {
                    when (row) {
                        Entry.Older -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Spinner(16.dp) }
                        Entry.Empty -> Text("在这里发消息，这个对话里的 agent 会在这里回复。", color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 30.dp, horizontal = 24.dp))
                        Entry.Line -> UnreadLine()
                        is Entry.Said -> Said(ctx, row.m, draft, list, rows, waitingNow = row.m.seq in pending && now - row.m.createdAt > 1000)
                        is Entry.Out -> Out(ctx, row.o)
                        is Entry.Working -> Activity(ctx, row.agent, leaving)
                        is Entry.Floor -> Spacer(Modifier.fillMaxWidth().height(with(LocalDensity.current) { row.px.toDp() }))
                    }
                }
            }
        }
        // Over the send button, in line with it (the composer's capsule insets it 18dp from the edge); it comes up
        // growing and goes the way it came.
        val scope = rememberCoroutineScope()
        AnimatedVisibility(
            awayFromEnd(list), Modifier.align(Alignment.BottomEnd).padding(end = 10.dp, bottom = (bottom - 6.dp).coerceAtLeast(0.dp)),
            enter = fadeIn(tween(180)) + scaleIn(tween(220, easing = FastOutSlowInEasing), initialScale = 0.6f) + slideInVertically(tween(220, easing = FastOutSlowInEasing)) { it / 2 },
            exit = fadeOut(tween(150)) + scaleOut(tween(180), targetScale = 0.6f) + slideOutVertically(tween(180)) { it / 2 },
        ) {
            Box(
                // Room round it for its shadow, which the animation's bounds would cut.
                Modifier.padding(8.dp).size(36.dp).floating(haze, CircleShape)
                    .clickable { scope.launch { follow.jump() } },
                contentAlignment = Alignment.Center,
            ) { IconIn(Icons.Down, 18.dp, C.ink) }
        }
    }
}

@Composable
private fun UnreadLine() {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.weight(1f).height(1.dp).background(C.blue.copy(alpha = 0.5f)))
        Text("以下是新消息", fontSize = 12.sp, color = C.blue)
        Box(Modifier.weight(1f).height(1.dp).background(C.blue.copy(alpha = 0.5f)))
    }
}

@Composable
fun Spinner(size: androidx.compose.ui.unit.Dp) = CircularProgressIndicator(Modifier.size(size), color = C.subtle, strokeWidth = 1.5.dp)

/** An agent's line over its words: its mark and name (both open its history), and a note. */
@Composable
private fun AgentHead(key: String, who: String, model: String?, runtime: String, note: String, ctx: Here, trailing: (@Composable RowScope.() -> Unit)? = null) {
    val app = LocalApp.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            Modifier.clip(RoundedCornerShape(6.dp)).clickable { openHistory(app, ctx.station, ctx.of, key) },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            ModelMark(model, runtime, 20.dp)
            Text(who, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(note, fontSize = 11.sp, color = C.subtle, maxLines = 1)
        trailing?.invoke(this)
    }
}

/** Long-press on a message: quote it, or copy it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun holdMenu(text: String, who: String, ts: String?, role: String, draft: Draft): Pair<Modifier, Color> {
    val app = LocalApp.current
    val context = LocalContext.current
    var pressed by remember { mutableStateOf(false) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    if (app.menu == null && pressed) pressed = false
    val modifier = Modifier.onGloballyPositioned { bounds = it.boundsInRoot() }.combinedClickable(
        interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = {},
        onLongClick = {
            pressed = true
            app.menu = MenuSpec(bounds, listOf(
                MenuItem("引用", Icons.Quote) { draft.quote(who, plain(text), ts, role) },
                MenuItem("拷贝", Icons.Copy) {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("ember", text))
                },
            ), onDismiss = { pressed = false })
        },
    )
    return modifier to if (pressed && app.menu != null) C.accent.copy(alpha = 0.12f) else Color.Transparent
}

/** A message's words as read, without markdown's marks: what a quote carries. */
private fun plain(text: String) = text.replace(Regex("[`*#>]"), "").replace(Regex("\\s+"), " ").trim()

@Composable
private fun Said(ctx: Here, m: MessageView, draft: Draft, list: androidx.compose.foundation.lazy.LazyListState, rows: List<Entry>, waitingNow: Boolean) {
    val jump = rememberJump(list, rows)
    if (ctx.mine(m)) {
        val (hold, press) = holdMenu(m.text, "你", m.ts, "person", draft)
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            m.quotes.forEach { QuoteCard(it, jump) }
            if (m.text.isNotEmpty()) Bubble(m.text, hold, press)
            Files(ctx, m.attachments)
            if (waitingNow) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Spinner(10.dp); Text("等待 agent 接收", fontSize = 11.sp, color = C.subtle)
            } else Text(relativeTime(m.createdAt), fontSize = 11.sp, color = C.subtle)
        }
        return
    }
    val agent = if (m.authorKind == "agent") ctx.agent(m.author) else null
    val who = when (m.authorKind) { "agent" -> agent?.who ?: m.authorName ?: "agent"; "ember" -> "ember"; else -> ctx.name(m) }
    val (hold, press) = holdMenu(m.text, who, m.ts, if (m.authorKind == "agent") "agent" else "person", draft)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (agent != null) AgentHead(agent.key, who, agent.model, agent.runtime, relativeTime(m.createdAt), ctx)
        else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            when (m.authorKind) {
                "agent", "ember" -> Mark(18.dp)
                else -> Avatar(m.author, who, 18.dp)
            }
            Text(who, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(relativeTime(m.createdAt), fontSize = 11.sp, color = C.subtle)
        }
        m.quotes.forEach { QuoteCard(it, jump) }
        Box(hold.clip(RoundedCornerShape(12.dp)).background(press)) {
            if (m.authorKind == "person") { if (m.text.isNotEmpty()) Text(ctx.mention(m.text), fontSize = 15.sp, lineHeight = 23.sp, color = C.ink) }
            else Markdown(m.text)
        }
        Files(ctx, m.attachments)
    }
}

@Composable
private fun Bubble(text: String, hold: Modifier, press: Color) {
    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        Text(
            text, fontSize = 15.sp, lineHeight = 22.sp, color = C.ink,
            modifier = Modifier.widthIn(max = maxWidth * 0.82f).then(hold)
                .clip(RoundedCornerShape(20.dp, 20.dp, 6.dp, 20.dp)).background(C.bubble).background(press).padding(horizontal = 14.dp, vertical = 9.dp),
        )
    }
}

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
@Composable
private fun Out(ctx: Here, o: OutboxItem) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val thread = ctx.view.thread
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        o.quotes.forEach { QuoteCard(it, null) }
        if (o.text.isNotEmpty()) Bubble(o.text, Modifier, Color.Transparent)
        Files(ctx, o.attachments)
        if (o.state == "failed") Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("发送失败" + (o.error?.let { "：$it" } ?: ""), fontSize = 11.sp, color = C.red, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            Text("重试", fontSize = 12.sp, color = C.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable {
                if (thread != null) scope.launch { try { app.api(ctx.station).retry(thread.id, o.id) } catch (_: CoreException) {} }
            })
            Text("删除", fontSize = 12.sp, color = C.muted, modifier = Modifier.clickable {
                if (thread != null) scope.launch { try { app.api(ctx.station).discard(thread.id, o.id) } catch (_: CoreException) {} }
            })
        } else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Spinner(10.dp); Text("正在发送", fontSize = 11.sp, color = C.subtle)
        }
    }
}

/** Scrolls the chat to a message by its ts. */
@Composable
private fun rememberJump(list: androidx.compose.foundation.lazy.LazyListState, rows: List<Entry>): (String) -> Unit {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    return { ts ->
        val index = rows.indexOfFirst { it.id == "m:$ts" }
        if (index >= 0) scope.launch { list.animateScrollToItem(index, -with(density) { 80.dp.roundToPx() }) }
    }
}

/** A quote as sent: the quoted part on a warm ground (whose message, the passage) leading back to it, then what was said about it. */
@Composable
private fun QuoteCard(q: Quote, onJump: ((String) -> Unit)?) {
    Column(Modifier.widthIn(max = 280.dp).clip(RoundedCornerShape(12.dp)).background(C.chip)) {
        val ts = q.ts
        Row(
            Modifier.fillMaxWidth().background(C.accentBg.copy(alpha = 0.6f)).let { if (ts != null && onJump != null) it.clickable { onJump(ts) } else it }
                .padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            IconIn(Icons.Quote, 11.dp, C.accentInk, Modifier.padding(top = 3.dp))
            Text(quoteText(q.author, q.text), fontSize = 12.sp, color = C.muted, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (q.comment.isNotEmpty()) Text(q.comment, fontSize = 13.sp, color = C.ink, modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp))
    }
}

@Composable
private fun quoteText(who: String, text: String) = androidx.compose.ui.text.buildAnnotatedString {
    pushStyle(androidx.compose.ui.text.SpanStyle(color = C.ink, fontWeight = FontWeight.Medium)); append("$who："); pop()
    append(text)
}

// ── the running turn ───────────────────────────────────────────────────

/**
 * An agent at work: its last three rows in three fixed lines (or the newest
 * in one), the newest coming in from below and pushing the oldest out above.
 */
@Composable
private fun Activity(ctx: Here, agent: AgentAtWork, leaving: Boolean) {
    val app = LocalApp.current
    var collapsed by remember { mutableStateOf(app.flag("activityCollapsed", false)) }
    // As the core puts it together (after Zork's): a status line and this turn's rows.
    val activity = agent.live?.activity
    val rows = activity?.rows.orEmpty().ifEmpty { listOf(ActivityRowView("idle", "other", "处理中", true)) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val fade by animateFloatAsState(if (leaving) 0f else 1f, tween(520), label = "leaving")
    val count = if (collapsed) 1 else 3
    Column(Modifier.fillMaxWidth().alpha(fade), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        AgentHead(agent.key, agent.who, agent.model, agent.runtime, (activity?.status ?: "处理中") + (agent.since?.let { " · ${elapsed(now - it)}" } ?: ""), ctx) {
            Box(Modifier.size(22.dp).clip(CircleShape).clickable { collapsed = !collapsed; app.setFlag("activityCollapsed", collapsed) }, contentAlignment = Alignment.Center) {
                IconIn(if (collapsed) Icons.ChevronDown else Icons.ChevronUp, 13.dp, C.subtle)
            }
        }
        // One row more than fits sits above the window, so the oldest can slide out as the rest move up.
        val shown = rows.takeLast(count + 1)
        val overflowing = shown.size > count
        val shift = remember { Animatable(0f) }
        val newest = shown.last().key
        var seen by remember { mutableStateOf(newest) }
        LaunchedEffect(newest) {
            if (newest != seen && overflowing) { shift.snapTo(1f); shift.animateTo(0f, tween(450, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) }
            seen = newest
        }
        // Rows fill from the top; once there are more than fit, the newest sits at the bottom.
        Box(Modifier.fillMaxWidth().height(22.dp * count).clipToBounds(), contentAlignment = if (overflowing) Alignment.BottomStart else Alignment.TopStart) {
            Column(Modifier.wrapContentHeight(if (overflowing) Alignment.Bottom else Alignment.Top, unbounded = true).graphicsLayer { translationY = shift.value * 22.dp.toPx() }) {
                shown.forEach { r ->
                    Row(
                        Modifier.height(22.dp).fillMaxWidth().clickable { openHistory(app, ctx.station, ctx.of, agent.key, r.entry) },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(Modifier.width(14.dp), contentAlignment = Alignment.Center) {
                            if (r.live) Spinner(11.dp) else IconIn(activityIcon(r.kind), 13.dp, C.subtle)
                        }
                        Text(r.text, fontSize = 13.sp, color = if (r.live) C.ink else C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/** A row's icon, by what kind of thing it does. */
private fun activityIcon(kind: String) = when (kind) {
    "read" -> Icons.File; "search" -> Icons.Search; "edit" -> Icons.Pen; "command" -> Icons.Terminal; "web" -> Icons.Globe
    "agent" -> Icons.Spark; "thread" -> Icons.Quote; "think" -> Icons.Spark; else -> Icons.Wrench
}

// ── files ──────────────────────────────────────────────────────────────

private val IMAGE = Regex("\\.(png|jpe?g|gif|webp)$", RegexOption.IGNORE_CASE)

/** Files sent never change: each is fetched once and the most recent are kept. */
private val files = LruCache<String, ByteArray>(40)

private suspend fun fileBytes(app: AppState, station: String, key: String, file: Attachment): ByteArray? {
    val id = "$station/$key/${file.path}"
    files.get(id)?.let { return it }
    return try {
        app.api(station).file(key, file.path.substringAfterLast('/')).also { files.put(id, it) }
    } catch (_: CoreException) {
        null
    }
}

@Composable
private fun Files(ctx: Here, list: List<Attachment>) {
    if (list.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        list.forEach { f -> val owner = ctx.owner(f); if (IMAGE.containsMatchIn(f.name) && owner != null) StationImage(ctx.station, owner, f) else FileCard(f.name, f.size) }
    }
}

/** An image at its own proportions within 240×200 (known before it loads); a tap shows it whole. */
@Composable
private fun StationImage(station: String, key: String, file: Attachment) {
    val app = LocalApp.current
    val image by produceState<ImageBitmap?>(null, station, key, file.path) {
        val bytes = fileBytes(app, station, key, file) ?: return@produceState
        value = withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
    }
    var open by remember { mutableStateOf(false) }
    val (w, h) = if (file.width != null && file.height != null) {
        val scale = minOf(1f, 240f / file.width, 200f / file.height)
        (file.width * scale).coerceAtLeast(40f).dp to (file.height * scale).coerceAtLeast(40f).dp
    } else 170.dp to 120.dp
    Box(Modifier.size(w, h).clip(RoundedCornerShape(14.dp)).background(C.chip).clickable(enabled = image != null) { open = true }) {
        image?.let { Image(it, file.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
    }
    val shown = image
    if (open && shown != null) Lightbox(station, key, file, shown) { open = false }
}

/** An image at full size over a dimmed page, with its name, size and a download; a tap outside closes it. */
@Composable
private fun Lightbox(station: String, key: String, file: Attachment, image: ImageBitmap, onClose: () -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.9f)).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClose)) {
            Box(Modifier.weight(1f).fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                Image(image, file.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            }
            Row(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(file.name, color = Color.White, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(fileSize(file.size), color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
                Text("下载", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable {
                    scope.launch {
                        val bytes = fileBytes(app, station, key, file)
                        app.toast = if (bytes != null && download(context, file.name, bytes)) "已存到「下载」" else "没能下载"
                    }
                })
                Text("关闭", color = Color.White, fontSize = 13.sp, modifier = Modifier.clickable(onClick = onClose))
            }
        }
    }
}

/** Puts a file in the phone's Downloads. */
private suspend fun download(context: Context, name: String, bytes: ByteArray): Boolean = withContext(Dispatchers.IO) {
    val values = ContentValues().apply { put(MediaStore.Downloads.DISPLAY_NAME, name) }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return@withContext false
    context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null
}

@Composable
private fun FileCard(name: String, size: Long, note: String? = null, busy: Boolean = false, onRemove: (() -> Unit)? = null, shape: Shape = RoundedCornerShape(12.dp)) {
    Row(
        Modifier.widthIn(max = 260.dp).clip(shape).background(C.chip).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (busy) Spinner(16.dp) else IconIn(Icons.File, 18.dp, C.muted)
        Column(Modifier.weight(1f, fill = false)) {
            Text(name, fontSize = 13.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(note ?: fileSize(size), fontSize = 11.sp, color = if (note != null && !busy) C.red else C.muted)
        }
        if (onRemove != null) Box(Modifier.size(20.dp).clickable(onClick = onRemove), contentAlignment = Alignment.Center) { IconIn(Icons.Close, 12.dp, C.subtle) }
    }
}

fun fileSize(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${Math.round(bytes / 1024.0)} KB"
    else -> String.format(java.util.Locale.ROOT, "%.1f MB", bytes / 1024.0 / 1024.0)
}

// ── the composer ───────────────────────────────────────────────────────

/** A file on its way to the station: uploading, uploaded, or failed. */
class Pending(val id: Long, val name: String, val size: Long, val preview: ImageBitmap?) {
    var done by mutableStateOf<Attachment?>(null)
    var error by mutableStateOf<String?>(null)
}

/** A passage quoted in the message being written, with what is said about it. */
class DraftQuote(val id: Long, val author: String, val text: String, val ts: String?, val role: String) {
    var comment by mutableStateOf("")
    fun sent() = Quote(author, text, comment.trim(), ts, role)
}

/** What is being written: text, quotes, files. Kept while the chat is open. */
class Draft {
    var text by mutableStateOf("")
    val quotes = mutableStateListOf<DraftQuote>()
    val files = mutableStateListOf<Pending>()
    /** A new chat is being made for the first message. */
    var starting by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    /** The quote whose comment line takes the focus. */
    var focusQuote by mutableStateOf<Long?>(null)
    /** Bumped to put the cursor in the text. */
    var focus by mutableIntStateOf(0)
    var warmed = 0L
    val uploading get() = files.any { it.done == null && it.error == null }
    val ready get() = (text.isNotBlank() || files.any { it.done != null } || quotes.isNotEmpty()) && !uploading && !starting

    fun quote(author: String, text: String, ts: String?, role: String) {
        val q = DraftQuote(System.nanoTime(), author, text, ts, role)
        quotes += q
        focusQuote = q.id
    }
}

private const val MAX_FILE = 50L * 1024 * 1024

/** A file picked on the phone, read whole; images also get their size and a preview. */
class Picked(val name: String, val bytes: ByteArray, val width: Int?, val height: Int?, val preview: ImageBitmap?)

suspend fun readPicked(context: Context, uri: Uri): Picked? = withContext(Dispatchers.IO) {
    val resolver = context.contentResolver
    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "file"
    val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext null
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }.also { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, it) }
    val image = bounds.outWidth > 0
    val preview = if (image) BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = maxOf(1, bounds.outWidth / 160) })?.asImageBitmap() else null
    Picked(name, bytes, bounds.outWidth.takeIf { image }, bounds.outHeight.takeIf { image }, preview)
}

fun photoPicked(bitmap: Bitmap): Picked {
    val bytes = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
    return Picked("photo-${System.currentTimeMillis()}.jpg", bytes, bitmap.width, bitmap.height, bitmap.asImageBitmap())
}

/** Files go to the station as soon as they are added, into the session `key()` names (a new chat makes it then). */
fun AppState.upload(draft: Draft, station: String, key: suspend () -> String, picked: Picked, scope: CoroutineScope) {
    val p = Pending(System.nanoTime(), picked.name, picked.bytes.size.toLong(), picked.preview)
    draft.files += p
    if (picked.bytes.size > MAX_FILE) { p.error = "超过 50 MB"; return }
    scope.launch {
        try {
            p.done = api(station).upload(key(), picked.name, picked.bytes, picked.width, picked.height)
        } catch (e: CoreException) {
            p.error = e.message
        }
    }
}

@Composable
fun AttachLaunchers(onPicked: (Picked) -> Unit): Triple<() -> Unit, () -> Unit, () -> Unit> {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap -> bitmap?.let { onPicked(photoPicked(it)) } }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        scope.launch { uris.forEach { u -> readPicked(context, u)?.let(onPicked) } }
    }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        scope.launch { uris.forEach { u -> readPicked(context, u)?.let(onPicked) } }
    }
    return Triple(
        { camera.launch(null) },
        { photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        { files.launch(arrayOf("*/*")) },
    )
}

/** ＋: take a photo, pick photos, pick files. */
fun openAttach(app: AppState, launchers: Triple<() -> Unit, () -> Unit, () -> Unit>) {
    app.sheet = SheetSpec(0.32f) {
        SheetGrab()
        SheetHead("添加到消息")
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(Triple("拍照", Icons.Camera, launchers.first), Triple("照片", Icons.Photo, launchers.second), Triple("文件", Icons.File, launchers.third)).forEach { (label, icon, go) ->
                Column(
                    Modifier.weight(1f).clip(RoundedCornerShape(18.dp)).background(C.chip).clickable { app.sheet = null; go() }.padding(top = 16.dp, bottom = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    IconIn(icon, 24.dp)
                    Text(label, fontSize = 13.sp, color = C.ink)
                }
            }
        }
    }
}

/** What waits to go with the message: the quotes (each with a line for a comment), then the files. */
@Composable
fun DraftExtras(draft: Draft) {
    // In the composer's capsule: corners concentric with it.
    draft.quotes.forEach { q ->
        Column(Modifier.fillMaxWidth().clip(InComposer).background(C.chip)) {
            Row(
                Modifier.fillMaxWidth().background(C.accentBg.copy(alpha = 0.6f)).padding(start = 10.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                IconIn(Icons.Quote, 12.dp, C.accentInk)
                Text(quoteText(q.author, q.text), fontSize = 12.sp, color = C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Box(Modifier.size(24.dp).clickable { draft.quotes.remove(q) }, contentAlignment = Alignment.Center) { IconIn(Icons.Close, 13.dp, C.subtle) }
            }
            val focus = remember { FocusRequester() }
            LaunchedEffect(draft.focusQuote) { if (draft.focusQuote == q.id) { focus.requestFocus(); draft.focusQuote = null } }
            Box(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp)) {
                if (q.comment.isEmpty()) Text("对这段说点什么（可以不写）", color = C.subtle, fontSize = 13.sp)
                BasicTextField(
                    q.comment, { q.comment = it }, singleLine = true, textStyle = TextStyle(color = C.ink, fontSize = 13.sp), cursorBrush = SolidColor(C.accent),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next), keyboardActions = KeyboardActions(onNext = { draft.focus++ }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
        }
    }
    if (draft.files.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        draft.files.forEach { f ->
            val remove = { draft.files.remove(f); Unit }
            if (f.preview != null) Box(Modifier.size(56.dp).clip(InComposer).background(C.chip)) {
                Image(f.preview, f.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                if (f.done == null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (f.error != null) 0.5f else 0.25f)), contentAlignment = Alignment.Center) {
                    if (f.error != null) Text("失败", color = Color.White, fontSize = 11.sp) else CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 1.5.dp)
                }
                Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(18.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).clickable(onClick = remove), contentAlignment = Alignment.Center) {
                    IconIn(Icons.Close, 10.dp, Color.White)
                }
            } else FileCard(f.done?.name ?: f.name, f.done?.size ?: f.size, f.error ?: if (f.done == null) "正在上传…" else null, busy = f.done == null && f.error == null, onRemove = remove, shape = InComposer)
        }
    }
}

/** The bar, inside a floating capsule that is its frame: ＋, a field that grows with the text right after it, and a round send
 * button (a spinner while a new chat is made). */
@Composable
fun ComposerBar(draft: Draft, placeholder: String, onPlus: () -> Unit, onType: () -> Unit, onSend: () -> Unit) {
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    // One style for what is typed and the placeholder: the field is as tall empty as with a line in it.
    val style = TextStyle(color = C.ink, fontSize = 15.sp, lineHeight = 21.sp)
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        // The attach sheet comes up in the keyboard's place: the keyboard goes first.
        Box(
            Modifier.size(36.dp).clip(CircleShape).clickable { focusManager.clearFocus(); keyboard?.hide(); onPlus() },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Plus, 18.dp) }
        Box(
            Modifier.weight(1f).heightIn(min = 36.dp).padding(end = 14.dp, top = 7.dp, bottom = 7.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (draft.text.isEmpty()) Text(placeholder, style = style.copy(color = C.subtle))
            val focus = remember { FocusRequester() }
            LaunchedEffect(draft.focus) { if (draft.focus > 0) focus.requestFocus() }
            BasicTextField(
                draft.text, { draft.text = it; onType() }, textStyle = style,
                cursorBrush = SolidColor(C.accent), maxLines = 6, modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
        }
        val ready = draft.ready
        Box(
            Modifier.size(36.dp).clip(CircleShape).background(if (ready) C.ink else C.line).clickable(enabled = ready, onClick = onSend),
            contentAlignment = Alignment.Center,
        ) {
            if (draft.starting) CircularProgressIndicator(Modifier.size(16.dp), color = C.surface, strokeWidth = 2.dp)
            else IconIn(Icons.Up, 18.dp, if (ready) C.bg else C.surface)
        }
    }
}

/**
 * Where people write to the chat. The composer empties at once: the message
 * lives in the chat's outbox until the station has it (a failure shows there
 * too). Before the agent has a chat, the first message makes one, bound to
 * the agent, and the page moves to it.
 */
@Composable
private fun Composer(station: String, of: ChatOf, view: ChatView, agents: List<ChatAgent>, draft: Draft, haze: HazeState, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    // Files are kept in a session's workspace: what is sent here goes to the first agent's.
    val keeper = agents.firstOrNull()?.key
    val launchers = AttachLaunchers { picked ->
        app.upload(draft, station, { keeper ?: throw CoreException("no_agent", "这个对话里没有 agent，文件无处可放", null) }, picked, scope)
    }
    val thread = view.thread
    // A capsule floating over the list, which runs on around it.
    Column(
        modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp)
            .floating(haze, RoundedCornerShape(ComposerCorner))
            // A tap on the capsule's own room is a tap on the field.
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { draft.focus++ }.padding(ComposerInset),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        DraftExtras(draft)
        ComposerBar(draft, "发消息", onPlus = { openAttach(app, launchers) },
            // Typing starts the session's runtime, so a cold start overlaps the writing.
            onType = {
                if (keeper != null && System.currentTimeMillis() - draft.warmed > 60_000) {
                    draft.warmed = System.currentTimeMillis()
                    scope.launch { try { api.warm(keeper) } catch (_: CoreException) {} }
                }
            },
            onSend = {
                val text = draft.text.trim()
                val files = draft.files.toList()
                val quotes = draft.quotes.toList()
                draft.text = ""; draft.files.clear(); draft.quotes.clear(); draft.error = null
                scope.launch {
                    val to = thread?.id ?: try {
                        draft.starting = true
                        api.chatFor((of as ChatOf.Session).key)
                    } catch (e: CoreException) {
                        // No chat to send into: the draft comes back.
                        draft.text = text; draft.files.addAll(files); draft.quotes.addAll(quotes)
                        draft.error = e.message
                        return@launch
                    } finally {
                        draft.starting = false
                    }
                    // Sent from the app's scope: the page may move to the new chat before the station answers.
                    app.scope.launch { try { api.send(to, text, files.mapNotNull { it.done }, quotes.map { it.sent() }) } catch (_: CoreException) {} }
                }
            })
        draft.error?.let { Text(it, fontSize = 12.sp, color = C.red, modifier = Modifier.padding(horizontal = 6.dp)) }
    }
}

// ── the chat's own page ────────────────────────────────────────────────

/** The chat itself: where it came from, who started it and takes part, its agents (each leads to its history). */
fun openChatInfo(app: AppState, station: String, of: ChatOf, thread: ThreadView) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val view = chat.value
        SheetGrab()
        SheetHead("对话信息")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            InfoList {
                Detail("来自", if (thread.surface == "ember") "ember 对话" else "Slack · " + if (thread.channel.startsWith("D")) "私信" else "#${thread.channelName ?: thread.channel}")
                Detail("发起", thread.creator?.let { c -> if (view?.me?.isMe(c) == true) "你" else c.name } ?: "未记录")
                Detail("参与", "${view?.people?.size ?: 0} 人") { view?.people?.let { if (it.isNotEmpty()) PeopleStack(it.take(8), 16.dp, C.surface2) } }
                Detail("创建", relativeTime(thread.createdAt))
                (view?.thread ?: thread).lastMessage?.let { Detail("最近消息", relativeTime(it.createdAt)) }
            }
            if (view != null && view.agents.isNotEmpty()) {
                GroupLabel("参与的 agent · 点开看它的执行历史")
                InfoList {
                    view.agents.forEach { a ->
                        val s = a.session
                        // The model is the one actually running, as everywhere.
                        val model = key(s.key) { rememberTopic<LiveView>(app.core, Topics.live(station, s.key)).value.value?.usage?.model } ?: s.model
                        InfoRow(onClick = { openHistory(app, station, of, s.key) }) {
                            ModelMark(model, s.runtime, 36.dp, a.state, around = C.surface2)
                            Column(Modifier.weight(1f)) {
                                Text(agentLabel(model, s.effort), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                // One line: it gives way with an ellipsis rather than wrapping.
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    if (a.connect != null) SlackMark(11.dp)
                                    Text(
                                        listOfNotNull(a.connect?.name, PROCESS_LABEL[s.process] ?: s.process, relativeTime(s.lastActiveAt)).joinToString(" · "),
                                        fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                            IconIn(Icons.Chevron, 14.dp, C.subtle)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Detail(label: String, value: String, extra: (@Composable () -> Unit)? = null) {
    InfoRow {
        Text(label, fontSize = 14.sp, color = C.muted, modifier = Modifier.width(72.dp))
        extra?.invoke()
        Text(value, fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
    }
}

@Composable
fun GroupLabel(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))

@Composable
fun InfoList(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.ink.copy(alpha = 0.05f))) { content() }
}

@Composable
fun InfoRow(onClick: (() -> Unit)? = null, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}
