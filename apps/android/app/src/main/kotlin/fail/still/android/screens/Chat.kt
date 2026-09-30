// An item's page, one for every item (web/src/pages/ChatPage.tsx, Chat.tsx):
// its chat's messages (none before its agent has a chat), the composer, and
// each agent's execution history as a sheet opened from its mark or name.
// Your messages sit right in a bubble; everyone else gets a face, a name and
// the time over their words. Long-press quotes or copies a message; ＋ adds files.
package fail.still.android.screens

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.togetherWith
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
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
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.ui.graphics.compositeOver
import fail.still.android.ui.MakerIcon
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ActivityNow
import fail.still.android.data.AgentWait
import fail.still.android.data.Attachment
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.Maker
import fail.still.android.data.Live
import fail.still.android.data.ChatMessage
import fail.still.android.data.Outgoing
import fail.still.android.data.Quote
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.data.state
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.LocalTextMark
import fail.still.android.ui.middleIn
import fail.still.android.ui.passageMark
import fail.still.android.ui.Ease
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Mark
import fail.still.android.ui.Markdown
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.ModelMark
import fail.still.android.ui.NavButton
import fail.still.android.ui.PeopleStack
import fail.still.android.ui.awayFromEnd
import fail.still.android.ui.endInView
import fail.still.android.ui.floating
import fail.still.android.ui.glass
import fail.still.android.ui.rememberFollow
import fail.still.core.CoreException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The station part of an address ("ws/studio" → "studio"). */
fun stationName(address: String) = address.substringAfter('/')

/** A station's name in its workspace. */
@Composable
fun rememberStationName(station: String): String {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(station.substringBefore('/')))
    return ws.value?.stations?.firstOrNull { it.id == stationName(station) }?.name ?: stationName(station)
}

/** An agent of this chat as its messages and activity show it: who it is, and its execution history as it runs. */
class AgentHere(val view: ChatAgent, val live: Live?) {
    val key get() = view.session.key
    val runtime get() = view.session.runtime
    val maker get() = view.session.maker
    val who get() = view.session.agentText
    val state get() = view.state
}

/**
 * The chat's own colours, as web mobile draws its messages: with the wide screen's tokens (web/src/styles/global.css.ts,
 * inside mobile/styles/root.css.ts → wide), over the phone's paper; neutral is the phone's bubble (--m-bubble, Theme.kt bubble).
 */
internal class ChatInk(
    val text: Color, val muted: Color, val subtle: Color, val neutral: Color, val name: Color, val card: Color,
    val accent: Color, val amber: Color, val canvas: Color,
)

private val LightInk = ChatInk(
    text = Color(0xFF24272B), muted = Color(0xFF646970), subtle = Color(0xFF73787D), neutral = Color(0xFFE8E4DC), name = Color(0xFFA23203),
    card = Color(0xFFF6F6F7), accent = Color(0xFFEF6A3C), amber = Color(0xFF7F5306), canvas = Color(0xFFFFFFFF),
)
private val DarkInk = ChatInk(
    text = Color(0xFFE9E9EA), muted = Color(0xFFA3A5A9), subtle = Color(0xFF8C8F94), neutral = Color(0xFF313237), name = Color(0xFFFC9B6F),
    card = Color(0xFF27282B), accent = Color(0xFFF57E4D), amber = Color(0xFFE6B55D), canvas = Color(0xFF1F2023),
)

@Composable
internal fun chatInk(): ChatInk = if (C.dark) DarkInk else LightInk
@Composable
internal fun chatMuted() = chatInk().muted
@Composable
internal fun chatSubtle() = chatInk().subtle
/** A quote's card: the ink faint over the canvas. */
@Composable
internal fun quoteGround() = chatInk().card

/** Times in messages say how long ago; a tap on one says when, in all of them (web ui.tsx → Time), until tapped again. */
private var absoluteTimes by mutableStateOf(false)

@Composable
private fun MessageTime(stamp: fail.still.android.data.Stamp?, modifier: Modifier = Modifier) {
    if (stamp == null) return
    Text(
        if (absoluteTimes) stamp.full else stamp.ago, fontSize = 10.sp, lineHeight = 16.sp, color = chatMuted(), maxLines = 1,
        modifier = modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { absoluteTimes = !absoluteTimes },
    )
}

/** A chat's page, above its host's composer (ChatHost.kt), which it says what to write to. */
@Composable
fun ChatScreen(station: String, of: ChatOf, host: Host) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
    val view = chat.value
    // The chat's own draft, kept as the chat is left and the app closed (Composer.kt → Drafts).
    val draft = rememberDraft(station, of)
    if (view == null) {
        // Until the core has the chat, the page is already a chat's page (its bar, empty): what comes fills it in
        // place instead of replacing another page. Its composer is there, not sending yet.
        host.spec = ComposerSpec(station, null, draft, "发消息", onPlus = {}, onSend = {})
        Column(Modifier.fillMaxSize()) {
            BarFrame("", more = false) {}
            val error = chat.error
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (error != null) Text("读不到这个对话：${error.message}", color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(32.dp))
            }
        }
        return
    }
    val agents = view.agents.map { a ->
        key(a.session.key) { AgentHere(a, rememberTopic<Live>(app.core, Topics.live(station, a.session.key)).value.value) }
    }
    // Who is in this chat, for the links in it: one naming an agent here opens over this page (AppState.openLink).
    SideEffect { app.chatAgents[Screen.Chat(station, of).id] = view.agents.map { it.session.key }.toSet() }
    // What a preview's marks put into this chat's draft (Preview.kt).
    TakeDraftOffers(station, view.agents.map { it.session.key }, draft)
    host.spec = chatComposer(host, station, of, view, agents, draft)
    // The messages run under the bar and the composer, which are frosted glass over them.
    val haze = host.haze
    val density = LocalDensity.current
    var topBar by remember { mutableIntStateOf(0) }
    // Its own paper under all of it: the bars are see-through, and what is under the page must not show in them.
    Box(Modifier.fillMaxSize().background(C.bg)) {
        Messages(station, of, view, agents, draft, haze, Modifier.fillMaxSize().background(C.bg), with(density) { topBar.toDp() }, with(density) { host.composerHeight.toDp() }, host)
        ChatBar(station, of, view, agents, Modifier.align(Alignment.TopCenter).onSizeChanged { topBar = it.height }.glass(haze))
        ConnectionPill(rememberStationName(station), view.link, haze, Modifier.align(Alignment.TopCenter).padding(top = with(density) { topBar.toDp() } + 8.dp))
    }
}

/**
 * The chat's bar: its title from the left, then its people, then its agents' marks (each opens its history); its
 * services and jobs (with a dot when one died lately or a service restarts), and "…", the chat's own page.
 */
@Composable
private fun ChatBar(station: String, of: ChatOf, view: ChatView, agents: List<AgentHere>, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val thread = view.thread
    val jobs = jobsOf(view)
    val alarm = alarmOf(jobs, rememberNow(30_000))
    BarFrame(view.title, more = thread != null, onMore = { if (thread != null) openChatInfo(app, station, of, thread) }, modifier = modifier, trailing = {
        if (jobs.isNotEmpty()) Box {
            NavButton(Icons.Web, { openJobs(app, station, of) })
            if (alarm != null) Box(Modifier.align(Alignment.TopEnd).padding(top = 6.dp, end = 6.dp).size(11.dp).clip(CircleShape).background(C.bg).padding(2.dp).clip(CircleShape).background(if (alarm == Tone.Fail) C.red else C.warn))
        }
    }) {
        if (view.people.isNotEmpty()) PeopleStack(view.people.take(5), 16.dp)
        agents.forEach { a ->
            // Not clipped: the state's dot sits over the mark's corner, partly outside it.
            Box(Modifier.clickable { openHistory(app, station, of, a.key) }) { ModelMark(a.maker, a.runtime, 22.dp, a.state, listMark = true) }
        }
    }
}

/** The bar's frame, the same while the chat loads and once it has: back, the title, what follows it, what is at its end, and "…". */
@Composable
private fun BarFrame(title: String, more: Boolean, onMore: () -> Unit = {}, modifier: Modifier = Modifier.background(C.bg), trailing: @Composable () -> Unit = {}, after: @Composable RowScope.() -> Unit) {
    val app = LocalApp.current
    Column(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars)) {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 6.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).clip(CircleShape).clickable(onClick = app::pop), contentAlignment = Alignment.Center) { IconIn(Icons.ChevronLeft, 22.dp, C.accent) }
            Row(Modifier.weight(1f).padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                after()
            }
            trailing()
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

/** An item new to the list comes up a little as it fades in (web mRise: 14px and opacity together, 320ms --m-standard). */
@Composable
private fun Modifier.rise(on: Boolean): Modifier {
    if (!on) return this
    val from = with(LocalDensity.current) { 14.dp.toPx() }
    val y = remember { Animatable(1f) }
    LaunchedEffect(Unit) { y.animateTo(0f, tween(320, easing = FastOutSlowInEasing)) }
    return graphicsLayer { translationY = y.value * from; alpha = 1f - y.value }
}

private sealed interface Entry {
    val id: String
    data object Older : Entry { override val id = "older" }
    data object Empty : Entry { override val id = "empty" }
    data object Line : Entry { override val id = "line" }
    /** `sent`: the outbox entry it was sent from here as, whose row it goes on being (its key kept: not a row leaving and another coming). */
    data class Said(val m: ChatMessage, val sent: String? = null) : Entry {
        override val id get() = sent?.let { "o:$it" } ?: "m:${m.ts}"
    }
    data class Out(val o: Outgoing) : Entry { override val id get() = "o:${o.id}" }
    data class Working(val agent: AgentAtWork) : Entry { override val id get() = "act:${agent.key}" }
    /** The room an activity that folded away leaves behind (as the web's floor): what is above it does not drop. */
    data class Floor(val px: Int) : Entry { override val id get() = "floor" }
}

/** How a place in the chat is kept (Messages → places) and a message found: by the message, however its row is keyed. */
private val Entry.place get() = if (this is Entry.Said) "m:${m.ts}" else id

/** An agent at work: who it is, its transcript and steps in flight, since when its turn runs, and while it waits on work
 * it started, since when and for how long at most. */
class AgentAtWork(val key: String, val who: String, val runtime: String, val maker: Maker?, val live: Live?, val since: Long?, val wait: AgentWait? = null)

/** What the messages need to know about the chat: who is who, and whose workspace keeps a file. */
internal class Here(val station: String, val of: ChatOf, val view: ChatView, val agents: List<AgentHere>) {
    fun agent(key: String) = agents.firstOrNull { it.key == key }
    fun mine(m: ChatMessage) = m.mine
    /** Files are kept in a session's workspace: the agent whose workspace holds it, else the first. */
    fun owner(file: Attachment): String? = agents.firstOrNull { file.path.startsWith("${it.view.session.workspace}/") }?.key ?: agents.firstOrNull()?.key
}

/** The list's gap between messages (web mobile: --list-gap 20px). */
private val GAP = 20.dp

/** `top` and `bottom`: the bars over it, which the list keeps its ends clear of. */
@Composable
private fun Messages(station: String, of: ChatOf, view: ChatView, agents: List<AgentHere>, draft: Draft, haze: HazeState, modifier: Modifier, top: Dp = 0.dp, bottom: Dp = 0.dp, host: Host) {
    val app = LocalApp.current
    val ctx = Here(station, of, view, agents)
    val thread = view.thread
    val api = app.api(station)
    val messages = view.messages

    // Where the viewer had read up to when the chat opened, and when that was; it stays put for the visit. The line
    // goes over the first message after it that is not theirs and was said before the chat opened, whether it came
    // from what the device kept or from the station a moment later.
    val open = remember { (thread?.read ?: 0L) to System.currentTimeMillis() }
    val (readAt, openedAt) = open
    val unread = { m: ChatMessage -> m.seq > readAt && m.createdAt <= openedAt && !ctx.mine(m) }
    val first = view.messages.firstOrNull()?.seq
    // Those not loaded yet may hold it: the pages before are loaded first.
    val above = view.more && first != null && first > readAt + 1 && messages.any(unread)
    val lineAt = if (above) null else messages.firstOrNull(unread)?.seq
    LaunchedEffect(above, first) { if (above && thread != null) try { api.older(thread.id) } catch (_: CoreException) {} }

    // Messages the agents have not taken yet (the core says which): after a second, yours say they wait.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val youngest = messages.filter { it.waiting }.maxOfOrNull { it.createdAt } ?: 0
    LaunchedEffect(youngest) {
        val wait = youngest + 1000 - System.currentTimeMillis()
        if (youngest > 0 && wait > 0) { delay(wait + 20); now = System.currentTimeMillis() }
    }

    // Agents' messages coming out of their activity's avatar (ChatMotion.kt), and a quoted message flashing.
    val reduced = fail.still.android.ui.reducedMotion()
    val motion = remember { ChatMotion(reduced) }
    // When the turn ends, the activity stays a moment to fade and fold away instead of vanishing.
    val lastBusy = remember { mutableStateOf<List<AgentAtWork>>(emptyList()) }
    // Only an agent that has taken a message and runs is at work (not one with messages waiting for it): until then
    // the message itself says it waits. One whose messages are still coming out of its avatar stays too.
    val keeps = motion.keeps()
    val busy = agents.filter { it.view.status == "running" }.map { a -> AgentAtWork(a.key, a.who, a.runtime, a.maker, a.live, a.view.since, a.view.wait) }
        .let { now -> now + lastBusy.value.filter { k -> k.key in keeps && now.none { it.key == k.key } } }
    var leaving by remember { mutableStateOf(false) }
    if (busy.isNotEmpty()) lastBusy.value = busy
    LaunchedEffect(busy.isEmpty()) {
        leaving = false
        if (busy.isEmpty() && lastBusy.value.isNotEmpty()) {
            delay(600); leaving = true; delay(220)
            lastBusy.value = emptyList(); leaving = false
        }
    }
    val atWork = busy.ifEmpty { lastBusy.value }
    // The list never gets shorter under the reader: an activity that folds away leaves its height as a floor, which
    // what comes next (a message, another activity) takes back as it arrives.
    val heights = remember { HashMap<String, Int>() }
    var floor by remember { mutableIntStateOf(0) }
    val gapPx = with(LocalDensity.current) { GAP.roundToPx() }
    val shownAtWork = atWork.isNotEmpty()
    // Taken in the same composition the activity leaves in (an effect would leave a frame without either, the list
    // shorter by it, and its end pulled up), and exactly its room: each activity and the gap before it, less the gap
    // the floor itself brings when it comes in.
    val wasAtWork = remember { booleanArrayOf(false) }
    if (wasAtWork[0] != shownAtWork) {
        val acts = heights.filterKeys { it.startsWith("act:") }.values
        if (!shownAtWork && acts.isNotEmpty()) floor += acts.sum() + acts.size * gapPx - (if (floor == 0) gapPx else 0)
        heights.keys.removeAll { it.startsWith("act:") }
        wasAtWork[0] = shownAtWork
    }

    // Messages new since the chat opened, from an agent whose activity shows, wait their turn out of the list.
    val since = remember { messages.lastOrNull()?.seq ?: 0L }
    motion.take(messages, since, atWork.map { it.key }.toSet())
    // A message sent from here stays the row it was in the outbox once the chat shows it: by the seq the station gave
    // it (Outgoing.seq), which the outbox says before it lets the message go.
    val sentAs = remember { HashMap<Long, String>() }
    view.outbox.forEach { o -> o.seq?.let { sentAs[it] = o.id } }
    val all = buildList {
        if (view.more) add(Entry.Older)
        if (messages.isEmpty() && view.outbox.isEmpty()) add(Entry.Empty)
        messages.forEach { m ->
            if (motion.held(m.seq)) return@forEach
            if (m.seq == lineAt) add(Entry.Line)
            add(Entry.Said(m, sentAs[m.seq]))
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
    host.rows = all.mapTo(HashSet()) { it.id }
    // What was in the list the last time it was drawn: an item new to it rises in; one scrolled to does not, nor one
    // caught up on rather than said while the chat is open (web Chat.tsx → useMessageList): messages up to where the
    // core says it caught up (read after what was kept, or once the link is back), and the activity of an agent
    // already at work when first seen.
    val known = remember { HashSet<String>() }
    SideEffect { rows.forEach { known += it.id } }
    val caughtUp = view.caught ?: 0L
    val statuses = remember { HashMap<String, String>() }
    val started = remember { HashSet<String>() }
    agents.forEach { a ->
        val was = statuses[a.key]
        if (a.view.status != "running") started -= a.key
        else if (was != null && was != "running") started += a.key
        statuses[a.key] = a.view.status
    }
    val caught = { row: Entry ->
        when (row) {
            is Entry.Said -> row.m.seq <= caughtUp
            is Entry.Working -> row.agent.key !in started
            else -> false
        }
    }
    val density = LocalDensity.current
    // The unread line near the top, below the bar, with about four lines of what came before it still in view (web
    // Chat.tsx → useUnreadLine: the bar's room and four of the list's 23px lines).
    val lineOffset = with(density) { -85.dp.roundToPx() }
    // The list starts where it is going (the unread line, where the chat was left, or the newest), rather than
    // composing its top only to jump away from it.
    val list = rememberLazyListState(
        initialFirstVisibleItemIndex = rows.indexOfFirst { it is Entry.Line }.takeIf { it >= 0 }
            ?: app.places[placeKey]?.let { (id, _) -> rows.indexOfFirst { it.place == id } }?.takeIf { it >= 0 } ?: rows.lastIndex.coerceAtLeast(0),
    )
    val follow = rememberFollow(list)
    motion.follow = follow
    motion.scope = rememberCoroutineScope()
    // Put in place once: at the unread line (even coming back: something unread goes over where the chat was left),
    // else back where the chat was left, else at the newest.
    val lineShown = remember { mutableStateOf(false) }
    LaunchedEffect(above, messages.isNotEmpty()) {
        if (follow.placed || above) return@LaunchedEffect
        val saved = app.places[placeKey]
        val back = saved?.let { (id, _) -> rows.indexOfFirst { it.place == id } }?.takeIf { it >= 0 }
        val line = rows.indexOfFirst { it is Entry.Line }.takeIf { it >= 0 }
        when {
            line != null -> list.scrollToItem(line, lineOffset)
            back != null -> list.scrollToItem(back, -saved.second)
            else -> follow.toEnd()
        }
        lineShown.value = line != null
        follow.placed = true
        follow.on = !list.canScrollForward
    }
    // Something unread that shows only after opening (from the station, after what was kept): the chat jumps to it once.
    val lineIndex = rows.indexOfFirst { it is Entry.Line }
    LaunchedEffect(lineIndex, follow.placed) {
        if (!follow.placed || lineShown.value || lineIndex < 0) return@LaunchedEffect
        lineShown.value = true
        follow.anchor = null
        list.scrollToItem(lineIndex, lineOffset)
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
    val rowsNow by rememberUpdatedState(rows)
    DisposableEffect(placeKey) {
        onDispose {
            list.layoutInfo.visibleItemsInfo.firstNotNullOfOrNull { item -> rowsNow.firstOrNull { it.id == item.key && it is Entry.Said }?.let { it.place to item.offset } }?.let { app.places[placeKey] = it }
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
    // Only what is watched comes out of an avatar: the page in front, the reader at the end; else all shows at once.
    val watched = follow.on && resumed.isAtLeast(Lifecycle.State.RESUMED)
    SideEffect { motion.watched = watched; motion.start() }
    LaunchedEffect(watched) { if (!watched) motion.release() }
    LaunchedEffect(motion.current) { motion.current?.let { motion.play(it) } }
    val newest = view.messages.lastOrNull()?.seq ?: 0
    val sent = remember { mutableLongStateOf(0L) }
    LaunchedEffect(seen, newest, thread?.read) {
        if (!seen || thread == null || newest <= thread.read || sent.longValue >= newest) return@LaunchedEffect
        sent.longValue = newest
        try { api.read(thread.id, newest) } catch (_: CoreException) { sent.longValue = 0 }
    }

    // A new chat's first words on their way (ChatHost.kt): the list comes up after them, out of the composer's top edge.
    val flight = host.flight
    var box by remember { mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null) }
    Box(modifier.fillMaxWidth().onGloballyPositioned { motion.pane = it; box = it }) {
      CompositionLocalProvider(LocalChatMotion provides motion) {
        // The list is what the bars and capsules over it frost (the button over it too, so it is not in it).
        LazyColumn(
            Modifier.fillMaxSize()
                .let { m ->
                    if (flight?.carried != true) m else m.drawWithContent {
                        val cut = host.overlayY(box)?.let { flight.top - it } ?: size.height
                        clipRect(bottom = cut) { this@drawWithContent.drawContent() }
                    }.graphicsLayer { translationY = flight.shift() }
                }
                .hazeSource(haze).background(C.bg), state = list,
            contentPadding = PaddingValues(start = 14.dp, end = 14.dp, top = top + 14.dp, bottom = bottom + 10.dp), verticalArrangement = Arrangement.spacedBy(GAP, if (reveal.revealing) Alignment.Bottom else Alignment.Top),
        ) {
            items(rows, key = { it.id }) { row ->
                val fresh = remember(row.id) { row.id !in known && !caught(row) }
                // What was just sent from here flies in from the composer instead (ChatHost.kt); an activity opens in its
                // own way, and a message out of an avatar comes out of it instead.
                val flies = host.takes(row.id, row is Entry.Out || (row is Entry.Said && row.m.mine && !row.m.system))
                val f = if (flies) host.flight else null
                val eases = fresh && !flies && row !is Entry.Working && !(row is Entry.Said && motion.emits(row.m.seq))
                Box(Modifier.animateItem(fadeInSpec = null, placementSpec = null, fadeOutSpec = tween(200)).rise(eases).flying(host, f).onSizeChanged { size ->
                    if (row is Entry.Floor) return@onSizeChanged
                    val before = heights.put(row.id, size.height)
                    // Something new took its place at the bottom: the floor gives that much back.
                    if (before == null && fresh && floor > 0) floor = (floor - size.height - gapPx).coerceAtLeast(0)
                }) {
                    CompositionLocalProvider(LocalFlight provides f, LocalFlightHost provides host) { when (row) {
                        Entry.Older -> Box(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 8.dp), contentAlignment = Alignment.Center) { Spinner(16.dp) }
                        Entry.Empty -> Text("在这里发消息，这个对话里的 agent 会在这里回复。", color = chatMuted(), fontSize = 15.sp, lineHeight = 24.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 30.dp, horizontal = 24.dp))
                        Entry.Line -> UnreadLine()
                        is Entry.Said -> Said(ctx, row.m, draft, list, rows, waitingNow = row.m.waiting && now - row.m.createdAt > 1000)
                        is Entry.Out -> Out(ctx, row.o)
                        is Entry.Working -> Activity(ctx, row.agent, leaving, opening = fresh)
                        is Entry.Floor -> Spacer(Modifier.fillMaxWidth().height(with(LocalDensity.current) { row.px.toDp() }))
                    } }
                }
            }
        }
        // Over the send button, in line with it (the composer's capsule insets it 18dp from the edge); it comes up
        // growing and goes the way it came (web mobile/Chat.css.ts → mJump: from translateY(18px) scale(.6), its
        // opacity 180ms and the rest 220ms --m-standard; going, 150ms and 180ms; turned back mid-way from where it is).
        JumpToLatest(awayFromEnd(list), haze, Modifier.align(Alignment.BottomEnd).padding(end = 18.dp, bottom = bottom + 2.dp)) { follow.jump() }
      }
        // The avatar flying with a message out of it: over the list, under the bars and the composer (as the web's, in
        // the pane).
        Flyer(motion, atWork)
    }
}

/** The copy of an activity's avatar (with its ring) that flies to where its message goes and back. */
@Composable
private fun Flyer(motion: ChatMotion, atWork: List<AgentAtWork>) {
    val turn = motion.current ?: return
    if (turn.pose == ChatMotion.Pose.Fold) return
    val agent = atWork.firstOrNull { it.key == turn.agent } ?: return
    val density = LocalDensity.current
    val ring = with(density) { 3.dp.toPx() }
    Box(
        Modifier.offset {
            val at = motion.flight(density)?.first ?: Offset(-10_000f, 0f)
            IntOffset((at.x - ring).roundToInt(), (at.y - ring).roundToInt())
        }.graphicsLayer {
            val swell = motion.flight(density)?.second ?: 1f
            scaleX = swell; scaleY = swell
        }.size(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        AgentAvatar(agent.maker, agent.runtime)
        WorkRing(waiting = agent.wait != null, leaving = false)
    }
}

@Composable
private fun JumpToLatest(shown: Boolean, haze: HazeState, modifier: Modifier, onJump: suspend () -> Unit) {
    val scope = rememberCoroutineScope()
    val fade by animateFloatAsState(if (shown) 1f else 0f, tween(if (shown) 180 else 150, easing = Ease.Css), label = "jump-fade")
    val grow by animateFloatAsState(if (shown) 1f else 0f, tween(if (shown) 220 else 180, easing = Ease.Standard), label = "jump-grow")
    val rise = with(LocalDensity.current) { 18.dp.toPx() }
    if (fade == 0f && grow == 0f) return
    Box(
        modifier.graphicsLayer {
            alpha = fade
            translationY = rise * (1f - grow)
            scaleX = 0.6f + 0.4f * grow; scaleY = scaleX
        }.size(36.dp).floating(haze, CircleShape)
            .clickable(enabled = shown) { scope.launch { onJump() } }
            .semantics { contentDescription = "跳到最新" },
        contentAlignment = Alignment.Center,
    ) { IconIn(Icons.ArrowDown, 18.dp, C.ink) }
}

/** Over the first message that was unread when the chat opened: the accent, a rule each side (web Chat.css.ts → chatUnreadLine). */
@Composable
private fun UnreadLine() {
    val accent = chatInk().accent
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.weight(1f).height(1.dp).background(accent.copy(alpha = 0.5f)))
        Text("以下是新消息", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = accent)
        Box(Modifier.weight(1f).height(1.dp).background(accent.copy(alpha = 0.5f)))
    }
}

@Composable
fun Spinner(size: androidx.compose.ui.unit.Dp) = CircularProgressIndicator(Modifier.size(size), color = C.subtle, strokeWidth = 1.5.dp)

/** A message's picture (web Chat.tsx → MessageAvatar): an agent's model maker in the agents' ground, still.fail's mark, or a person's face. */
@Composable
private fun MessageAvatar(m: ChatMessage) {
    when (m.authorKind) {
        "agent" -> AgentAvatar(m.by.maker, m.by.runtime)
        "ember" -> AgentAvatar(null, null)
        else -> Avatar(m.author, m.by.name, 18.dp, picture = m.by.picture)
    }
}

/** An agent's picture in a chat: its model's maker (still.fail's mark without one), small on a round grey ground. */
@Composable
private fun AgentAvatar(maker: Maker?, runtime: String?) {
    Box(Modifier.size(18.dp).clip(CircleShape).background(chatInk().neutral), contentAlignment = Alignment.Center) {
        if (runtime != null) MakerIcon(maker, runtime, 12.dp) else Mark(12.dp)
    }
}

/** Long-press on a message: quote it, or copy it; while its menu is open its words are marked. */
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
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", text))
                    app.toast = "已拷贝"
                },
            ), onDismiss = { pressed = false })
        },
    )
    return modifier to if (pressed && app.menu != null) C.accent.copy(alpha = 0.12f) else Color.Transparent
}

/** A message's words as read, without markdown's marks: what a quote carries. */
private fun plain(text: String) = text.replace(Regex("[`*#>]"), "").replace(Regex("\\s+"), " ").trim()

@Composable
private fun Said(ctx: Here, m: ChatMessage, draft: Draft, list: androidx.compose.foundation.lazy.LazyListState, rows: List<Entry>, waitingNow: Boolean) {
    // A quote led here: the passage it quotes is marked where these words hold it (TextMark.kt).
    val motion = LocalChatMotion.current
    val mark = motion?.mark?.takeIf { motion.flashed == m.ts }
    CompositionLocalProvider(LocalTextMark provides mark) { SaidRow(ctx, m, draft, list, rows, waitingNow) }
}

@Composable
private fun SaidRow(ctx: Here, m: ChatMessage, draft: Draft, list: androidx.compose.foundation.lazy.LazyListState, rows: List<Entry>, waitingNow: Boolean) {
    val app = LocalApp.current
    val jump = rememberJump(list, rows)
    val ink = chatInk()
    // What still.fail itself says (role "ember", as the core sends it): a notice across the chat, apart from people's and agents' messages.
    if (m.system) { SystemNotice(m.text, m.time?.get("createdAt")); return }
    val motion = LocalChatMotion.current
    val flash = accentBg()
    if (ctx.mine(m)) {
        val (hold, press) = holdMenu(m.text, "你", m.ts, "person", draft)
        Column(Modifier.fillMaxWidth().flashed(motion, m.ts, flash), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            QuoteCards(m.quotes, jump, Alignment.End)
            if (m.text.isNotEmpty()) Bubble(m.text, hold, press)
            Files(ctx, m.attachments, mine = true)
            // Not taken by its agents yet: after a second it says it waits.
            if (waitingNow) Waiting("等待 agent 接收")
            // Coming in with the words, when they fly here from the composer.
            else LocalFlight.current.let { f -> MessageTime(m.time?.get("createdAt"), if (f == null) Modifier else Modifier.graphicsLayer { alpha = f.e() }) }
        }
        return
    }
    // Someone else's: the avatar and name in line over what they say (web: the phone's inline heads), the name an
    // agent's opens its history.
    val agent = m.by.agent?.let { ctx.agent(it) }
    val who = m.by.name
    val (hold, press) = holdMenu(m.text, who, m.ts, if (m.authorKind == "agent") "agent" else "person", draft)
    Box(Modifier.fillMaxWidth().flashed(motion, m.ts, flash)) {
        // Where a message out of an agent's avatar lands: its own avatar, hidden while the flying one is over it.
        Box(
            Modifier.padding(top = 3.dp).onGloballyPositioned { motion?.landings?.set(m.seq, it) }
                .graphicsLayer { alpha = if (motion?.emitting(m.seq) == true) 0f else 1f },
        ) { MessageAvatar(m) }
        Column(Modifier.fillMaxWidth().emitOut(motion, m.seq), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.padding(start = 25.dp).heightIn(min = 24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    who, fontSize = 15.sp, fontWeight = FontWeight(650), color = ink.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.widthIn(max = 240.dp).let { mod -> if (agent != null) mod.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { openHistory(app, ctx.station, ctx.of, agent.key) } else mod },
                )
                MessageTime(m.time?.get("createdAt"))
            }
            QuoteCards(m.quotes, jump, Alignment.Start)
            Box(hold.clip(RoundedCornerShape(12.dp)).background(press)) {
                // A person's words as yours are drawn: a reference to another chat as its chip (web Chat.tsx → PersonWords).
                if (m.authorKind == "person") { if (m.text.isNotEmpty()) { val words = fail.still.android.ui.withRefs(m.text); val (mark, laid) = passageMark(words.text); Text(words, mark, fontSize = 15.sp, lineHeight = 23.sp, color = ink.text, onTextLayout = laid) } }
                else AgentWords(ctx, m.text, m.attachments, draft)
            }
            // An agent's files are placed in its words (Prose.kt), the rest below them there.
            if (m.authorKind == "person") Files(ctx, m.attachments)
        }
    }
}

/**
 * What still.fail itself says (web Chat.tsx → SystemNotice): a pill across the chat, in one line and no time, cut short
 * where it does not fit. A tap opens it: all its words, wrapped, and its time under it. The station begins its failures
 * with ⚠️; here a failure is the pill in red instead. A notice is a line of the UI, not prose: no 。 at its end.
 */
@Composable
private fun SystemNotice(text: String, time: fail.still.android.data.Stamp?) {
    val failed = remember(text) { Regex("^⚠️\\s*").find(text) }
    val said = remember(text) { (failed?.let { text.substring(it.range.last + 1) } ?: text).replace(Regex("。\\s*$"), "") }
    var open by remember { mutableStateOf(false) }
    val dark = C.dark
    // The web's --hover (the offline notice's grey), --red-bg and --red.
    val ground = if (failed != null) (if (dark) Color(0xFF442322) else Color(0xFFFFF0EF)) else if (dark) Color.White.copy(alpha = 0.05f) else Color(0xFF262117).copy(alpha = 0.065f)
    val ink = if (failed != null) (if (dark) Color(0xFFF68482) else Color(0xFFA12F35)) else chatInk().text
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val shape = RoundedCornerShape(if (open) 16.dp else 999.dp)
        Box(
            Modifier.clip(shape).background(ground)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { open = !open }
                .padding(horizontal = 14.dp, vertical = 6.dp),
        ) {
            if (open) CompositionLocalProvider(fail.still.android.ui.LocalMdInk provides ink) { Markdown(said) }
            else Text(
                plain(said.lineSequence().firstOrNull { it.isNotBlank() } ?: said), fontSize = 15.sp, lineHeight = 24.75.sp, color = ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        if (open) MessageTime(time)
    }
}

/** A spinner and a word, small, under a message of yours: waiting for its agents, or on its way. */
@Composable
private fun Waiting(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Spinner(10.dp); Text(text, fontSize = 10.sp, lineHeight = 16.sp, color = chatMuted())
    }
}

/** Your words, in their bubble on the right, a reference to another chat as its chip (ui/Markdown.kt → withRefs). */
@Composable
private fun Bubble(text: String, hold: Modifier, press: Color) {
    val ink = chatInk()
    // Words flying here from the composer (ChatHost.kt): their bubble forms round them as they come.
    val flight = LocalFlight.current
    val host = LocalFlightHost.current
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        val words = fail.still.android.ui.withRefs(text)
        val (mark, laid) = passageMark(words.text)
        Text(
            words, fontSize = 15.sp, lineHeight = 23.sp, color = ink.text, onTextLayout = laid,
            modifier = Modifier.widthIn(max = maxWidth * 0.78f).then(hold)
                .let { m ->
                    if (flight == null || host == null) m else m.onGloballyPositioned {
                        with(density) { flight.bubbleAt(it, host, androidx.compose.ui.geometry.Offset(14.dp.toPx(), 8.dp.toPx()), 23.sp.toPx(), 15.sp.toPx()) }
                    }
                }
                .clip(RoundedCornerShape(18.dp)).drawBehind { drawRect(ink.neutral, alpha = flight?.e() ?: 1f) }.background(press).padding(horizontal = 14.dp, vertical = 8.dp).then(mark),
        )
    }
}

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
@Composable
private fun Out(ctx: Here, o: Outgoing) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val thread = ctx.view.thread
    // A chat made here has no thread until its station makes it: what failed in it goes by its key.
    val pending = (ctx.of as? ChatOf.Session)?.key?.takeIf { it.startsWith("new:") }
    val failed = o.state == "failed"
    val ink = chatInk()
    // On its way, it says so only if that takes a moment.
    var slow by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(800); slow = true }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Not sent: what was written faded.
        Column(Modifier.fillMaxWidth().alpha(if (failed) 0.55f else 1f), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            QuoteCards(o.quotes, null, Alignment.End)
            if (o.text.isNotEmpty()) Bubble(o.text, Modifier, Color.Transparent)
            Files(ctx, o.attachments, mine = true)
        }
        // Said briefly (a tap says why); sending it again or dropping it right beside.
        if (failed) Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(
                Modifier.padding(end = 6.dp).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { app.toast = o.error?.let { "没发出去：$it" } ?: "没发出去" },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                IconIn(Icons.Info, 12.dp, C.red); Text("未发送", fontSize = 13.sp, color = C.red)
            }
            UnsentButton(Icons.Retry, "重试", enabled = !ctx.view.offline && ctx.view.archived != true) {
                scope.launch { try { if (thread != null) app.api(ctx.station).retry(thread.id, o.id) else pending?.let { app.api(ctx.station).retryIn(it, o.id) } } catch (_: CoreException) {} }
            }
            UnsentButton(Icons.Trash, "删除") {
                scope.launch { try { if (thread != null) app.api(ctx.station).discard(thread.id, o.id) else pending?.let { app.api(ctx.station).discardIn(it, o.id) } } catch (_: CoreException) {} }
            }
        } else if (slow) Waiting("正在发送")
    }
}

@Composable
private fun UnsentButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    val muted = chatMuted()
    Row(
        Modifier.alpha(if (enabled) 1f else 0.5f).clip(RoundedCornerShape(7.dp)).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        IconIn(icon, 12.dp, muted); Text(label, fontSize = 13.sp, color = muted)
    }
}

/**
 * Goes to a quoted message by its ts, as the web does (Chat.tsx → Quotes → jump): at once, its middle in the middle of
 * the list, then it flashes (a reader's move: the list follows the newest again only if that leaves it at the end).
 */
@Composable
private fun rememberJump(list: androidx.compose.foundation.lazy.LazyListState, rows: List<Entry>): (String, String) -> Unit {
    val motion = LocalChatMotion.current
    val accent = chatInk().accent
    return { ts, passage ->
        val index = rows.indexOfFirst { it is Entry.Said && it.m.ts == ts }
        if (index >= 0 && motion != null) motion.scope?.launch {
            val follow = motion.follow
            follow?.anchor = null
            motion.lead(ts, passage, accent)
            list.scrollToItem(index)
            val info = list.layoutInfo
            info.visibleItemsInfo.firstOrNull { it.index == index }?.let { item ->
                list.scrollBy((item.offset + item.size / 2 - (info.viewportStartOffset + info.viewportEndOffset) / 2).toFloat())
            }
            // The passage, found in its words, is what goes in the middle (web: the range's middle at the pane's).
            val pane = motion.pane
            val mid = pane?.let { p -> motion.mark?.middleIn(p) }
            if (pane != null && mid != null) list.scrollBy(mid.y - pane.size.height / 2f)
            follow?.on = !list.canScrollForward
            motion.flash()
        }
    }
}

/** A quote's passage as a card shows it: the mark in the accent, whose it is, what it says. */
@Composable
internal fun quoteLine(who: String, text: String) = androidx.compose.ui.text.buildAnnotatedString {
    appendInlineContent("quote", "❝")
    pushStyle(androidx.compose.ui.text.SpanStyle(color = chatInk().text, fontWeight = FontWeight.Medium)); append("$who："); pop()
    append(text)
}

/** The mark before a quote's passage (quoteLine's inline "quote"). */
@Composable
internal fun quoteMark(): Map<String, androidx.compose.foundation.text.InlineTextContent> {
    val accent = chatInk().accent
    return mapOf("quote" to androidx.compose.foundation.text.InlineTextContent(
        androidx.compose.ui.text.Placeholder(15.sp, 13.sp, androidx.compose.ui.text.PlaceholderVerticalAlign.TextCenter),
    ) { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) { IconIn(Icons.Quote, 11.dp, accent) } })
}

/**
 * Quotes as sent, each a card of its own ahead of the message (web Chat.tsx → Quotes, QuoteCard): the passage, small and
 * grey, leading back to it; then what was said about it.
 */
@Composable
private fun QuoteCards(quotes: List<Quote>, onJump: ((String, String) -> Unit)?, side: Alignment.Horizontal) {
    if (quotes.isEmpty()) return
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val most = minOf(380.dp, maxWidth * 0.88f)
        Column(Modifier.fillMaxWidth(), horizontalAlignment = side, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            quotes.forEach { q -> QuoteCard(q, onJump, Modifier.widthIn(max = most)) }
        }
    }
}

@Composable
private fun QuoteCard(q: Quote, onJump: ((String, String) -> Unit)?, modifier: Modifier) {
    val ink = chatInk()
    Column(modifier.clip(RoundedCornerShape(12.dp)).background(ink.card)) {
        val ts = q.ts
        Text(
            quoteLine(q.author, q.text), inlineContent = quoteMark(), fontSize = 13.sp, lineHeight = 19.5.sp, color = ink.muted, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.let { if (ts != null && onJump != null) it.clickable { onJump(ts, q.text) } else it }
                .padding(start = 11.dp, end = 11.dp, top = 7.dp, bottom = if (q.comment.isEmpty()) 7.dp else 0.dp),
        )
        if (q.comment.isNotEmpty()) Text(q.comment, fontSize = 15.sp, lineHeight = 22.5.sp, color = ink.text, modifier = Modifier.padding(start = 11.dp, end = 11.dp, top = 3.dp, bottom = 8.dp))
    }
}

// ── the running turn ───────────────────────────────────────────────────

/**
 * An agent at work, in one line (as the web's): its avatar, ringed while it works, and what it does now (as the core
 * says), with how long its turn has run. No name: the avatar says whose. A new thing crossfades in once the shown one
 * has stayed a moment, so a passing 请求中 does not flicker by; the same thing's new words (its rate) show at once.
 */
@Composable
private fun Activity(ctx: Here, agent: AgentAtWork, leaving: Boolean, opening: Boolean = false) {
    val app = LocalApp.current
    val motion = LocalChatMotion.current
    // A message coming out of its avatar: the line folds to its avatar (what it does, 200ms --ease-out; faded by 160ms),
    // and the avatar is away while its copy flies (ChatMotion.kt).
    val folded = motion?.folded(agent.key) == true
    val away = motion?.away(agent.key) == true
    val tail by animateFloatAsState(if (folded) 0f else 1f, tween(200, easing = Ease.Out), label = "tail")
    val tailFade by animateFloatAsState(if (folded) 0f else 1f, tween(160, easing = Ease.Out), label = "tail-fade")
    // Coming in, it opens from nothing and fades in (web activityIn: grid rows 0fr → 1fr and opacity, 220ms --ease-out).
    val open = remember { Animatable(if (opening) 0f else 1f) }
    LaunchedEffect(Unit) { open.animateTo(1f, tween(220, easing = Ease.Out)) }
    val wait = agent.wait
    val ink = chatInk()
    val shown = steady(if (wait != null) ActivityNow(key = "wait", text = "等待中") else agent.live?.activity?.now ?: ActivityNow(key = "busy", text = "处理中"))
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val fade by animateFloatAsState(if (leaving) 0f else 1f, tween(220), label = "leaving")
    Row(
        Modifier.fillMaxWidth()
            .layout { measurable, constraints ->
                val p = measurable.measure(constraints)
                layout(p.width, (p.height * open.value).roundToInt()) { p.place(0, 0) }
            }
            .clipToBounds().graphicsLayer { alpha = open.value }
            .onGloballyPositioned { motion?.activityRows?.set(agent.key, it) }
            .alpha(fade).clip(RoundedCornerShape(6.dp)).clickable { openHistory(app, ctx.station, ctx.of, agent.key) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        // The avatar where its message lands (the messages' 18dp), its ring 3dp round it.
        Box(Modifier.size(24.dp).offset(x = (-3).dp).graphicsLayer { alpha = if (away) 0f else 1f }, contentAlignment = Alignment.Center) {
            Box(Modifier.onGloballyPositioned { motion?.activityAvatars?.set(agent.key, it) }) { AgentAvatar(agent.maker, agent.runtime) }
            WorkRing(waiting = wait != null, leaving = leaving)
        }
      Row(
          Modifier.weight(1f, fill = false)
              .layout { measurable, constraints ->
                  val p = measurable.measure(constraints)
                  layout((p.width * tail).roundToInt(), p.height) { p.place(0, 0) }
              }
              .clipToBounds().graphicsLayer { alpha = tailFade },
          verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
      ) {
        AnimatedContent(
            targetState = shown, contentKey = { it.key }, modifier = Modifier.weight(1f, fill = false),
            transitionSpec = { (fadeIn(tween(240)) + slideInVertically(tween(240)) { it / 4 }) togetherWith (fadeOut(tween(240)) + slideOutVertically(tween(240)) { -it / 4 }) },
            label = "now",
        ) { said -> Text(said.text, fontSize = 15.sp, color = ink.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        Spacer(Modifier.width(3.dp))
        if (wait != null) {
            val most = wait.seconds?.let { " / ${elapsed(it * 1000)}" } ?: ""
            val waited = wait.seconds?.let { minOf(now, wait.since + it * 1000) } ?: now
            Text(elapsed(waited - wait.since) + most, fontSize = 15.sp, color = ink.subtle, maxLines = 1)
        } else agent.since?.let { Text(elapsed(now - it), fontSize = 15.sp, color = ink.subtle, maxLines = 1) }
      }
    }
}

/** The ring round an agent at work: half of it in the accent, turning; waiting on work it started, a still, quiet one. */
@Composable
private fun WorkRing(waiting: Boolean, leaving: Boolean) {
    val accent = chatInk().accent
    val line = C.line
    val turning = androidx.compose.animation.core.rememberInfiniteTransition(label = "ring")
    val angle by turning.animateFloat(0f, 360f, androidx.compose.animation.core.infiniteRepeatable(tween(1100, easing = androidx.compose.animation.core.LinearEasing)), label = "angle")
    val shown by animateFloatAsState(if (leaving) 0f else 1f, tween(160), label = "ring-out")
    androidx.compose.foundation.Canvas(Modifier.size(24.dp).alpha(shown)) {
        val w = 1.5.dp.toPx()
        val inset = w / 2
        val box = androidx.compose.ui.geometry.Size(size.width - w, size.height - w)
        val at = androidx.compose.ui.geometry.Offset(inset, inset)
        if (waiting) drawArc(line, 0f, 360f, false, at, box, style = androidx.compose.ui.graphics.drawscope.Stroke(w))
        else drawArc(accent, -135f + angle, 180f, false, at, box, style = androidx.compose.ui.graphics.drawscope.Stroke(w))
    }
}

/** What an activity shows, steadied: another thing replaces the shown one after it has stayed 700 ms. */
@Composable
private fun steady(said: ActivityNow): ActivityNow {
    var shown by remember { mutableStateOf(said) }
    var at by remember { mutableLongStateOf(0L) }
    val latest by rememberUpdatedState(said)
    LaunchedEffect(said.key, said.text) {
        if (said.key == shown.key || said.text == shown.text) { shown = said; return@LaunchedEffect }
        delay(maxOf(0L, at + 700 - System.currentTimeMillis()))
        shown = latest
        at = System.currentTimeMillis()
    }
    return shown
}

/** A running clock's reading in short, as the web's: 45s, 3m 20s, 1h 5m. */
private fun elapsed(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return when {
        s < 60 -> "${s}s"
        s < 3600 -> if (s % 60 != 0L) "${s / 60}m ${s % 60}s" else "${s / 60}m"
        else -> if (s % 3600 / 60 != 0L) "${s / 3600}h ${s % 3600 / 60}m" else "${s / 3600}h"
    }
}
