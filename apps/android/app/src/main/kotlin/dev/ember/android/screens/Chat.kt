// A chat: your messages sit right in a bubble; everyone else (people and
// agents) gets a face, a name and the time over their words. An agent's name,
// mark or activity opens its execution history; "…" is the chat's own page.
// Long-press quotes or copies a message; ＋ adds files.
package dev.ember.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.LruCache
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.data.Agent
import dev.ember.android.data.Attachment
import dev.ember.android.data.Author
import dev.ember.android.data.ChatState
import dev.ember.android.data.ChatView
import dev.ember.android.data.LiveView
import dev.ember.android.data.Message
import dev.ember.android.data.Quote
import dev.ember.android.data.Thread
import dev.ember.android.data.Topics
import dev.ember.android.data.activityRows
import dev.ember.android.data.elapsed
import dev.ember.android.data.relativeTime
import dev.ember.android.data.rememberTopic
import dev.ember.android.data.thread
import dev.ember.android.data.writingNow
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.Loading
import dev.ember.android.ui.MakerIcon
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
import dev.ember.android.ui.Toggle
import dev.ember.core.CoreException
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val STATE_LABEL = mapOf(ChatState.Block to "在 block", ChatState.Running to "进行中", ChatState.Done to "空闲", ChatState.Failed to "失败")

/** The station part of an address ("ws/studio" → "studio"). */
fun stationName(address: String) = address.substringAfter('/')

/** The web page of a chat, for links and "在电脑上打开". */
fun chatUrl(app: AppState, station: String, key: String): String {
    val (ws, st) = station.split('/', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
    return app.web("/w/$ws/s/$st/sessions/${Uri.encode(key)}")
}

@Composable
fun ChatScreen(station: String, key: String) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, key))
    val live by rememberTopic<LiveView>(app.core, Topics.live(station, key))
    val view = chat.value
    if (view == null) {
        Column(Modifier.fillMaxSize()) {
            NavBar("会话", app::pop, "")
            Loading(chat.error?.let { "读不到这个会话：${it.message}" } ?: "正在读取会话…")
        }
        return
    }
    val thread = view.thread(station)
    val composer = remember(key) { Draft() }
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
        ChatBar(thread, app)
        Messages(thread, view, live.value, composer, Modifier.weight(1f))
        Composer(thread, composer)
    }
}

/** The chat's bar, as on the computer: its title from the left, then its people, then its agents' marks; "…" is the chat's own page. */
@Composable
private fun ChatBar(thread: Thread, app: AppState) {
    Column(Modifier.fillMaxWidth().background(C.bg).windowInsetsPadding(WindowInsets.statusBars)) {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 6.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).clip(CircleShape).clickable(onClick = app::pop), contentAlignment = Alignment.Center) { IconIn(Icons.Back, 22.dp, C.accent) }
            Row(Modifier.weight(1f).padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(thread.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                PeopleStack(thread.people, 16.dp)
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) { thread.agents.forEach { MakerIcon(it.model, 14.dp) } }
            }
            NavButton(Icons.More, { openChatInfo(app, thread) })
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(C.line))
    }
}

// ── the list ───────────────────────────────────────────────────────────

private sealed interface Row {
    val id: String
    data class Said(val m: Message) : Row { override val id get() = m.id }
    data class Writing(val agent: Agent, val text: String) : Row { override val id get() = "writing" }
    data class Working(val agent: Agent) : Row { override val id get() = "activity" }
}

@Composable
private fun Messages(thread: Thread, view: ChatView, live: LiveView?, draft: Draft, modifier: Modifier) {
    val app = LocalApp.current
    val main = thread.agents.first()
    val writing = live?.let { writingNow(it.steps) }
    val running = thread.state == ChatState.Running
    // Newest at the bottom: the list is laid out from the end, so it stays there as things arrive.
    val rows = buildList {
        thread.messages.forEach { add(Row.Said(it)) }
        if (writing != null) add(Row.Writing(main, writing))
        // The activity is always last.
        if (running) add(Row.Working(main))
    }.asReversed()
    val list = rememberLazyListState()
    val api = app.api(thread.station)
    LaunchedEffect(rows.size) { if (list.firstVisibleItemIndex <= 1) list.animateScrollToItem(0) }
    // What is shown is read.
    LaunchedEffect(thread.lastSeq) { if (thread.lastSeq > 0) try { api.read(thread.key, thread.lastSeq) } catch (_: CoreException) {} }
    // Scrolled up to the oldest message shown: the page before it comes in.
    val atOldest by remember(rows.size) { derivedStateOf { list.layoutInfo.visibleItemsInfo.lastOrNull()?.index == rows.size - 1 } }
    LaunchedEffect(atOldest, thread.more, rows.size) { if (atOldest && thread.more) try { api.older(thread.key) } catch (_: CoreException) {} }
    if (thread.messages.isEmpty() && !running) {
        Box(modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) {
            Text("在这里给这个会话发消息，agent 会在这里回复。", color = C.muted, fontSize = 14.sp)
        }
        return
    }
    LazyColumn(modifier.fillMaxWidth(), state = list, reverseLayout = true, contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.Bottom)) {
        items(rows, key = { it.id }) { row ->
            Box(Modifier.animateItem(fadeInSpec = tween(250), placementSpec = tween(250), fadeOutSpec = tween(200))) {
                when (row) {
                    is Row.Said -> Said(thread, row.m, draft)
                    // The reply being written, above the activity (which stays while the agent works).
                    is Row.Writing -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        AgentHead(row.agent, "正在输入") { openHistory(app, thread, row.agent) }
                        Markdown(row.text)
                    }
                    is Row.Working -> Activity(thread, row.agent, view, live)
                }
            }
        }
    }
}

@Composable
private fun AgentHead(agent: Agent, note: String, badge: ChatState? = null, onOpen: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onOpen)) {
        ModelMark(agent.model, 20.dp, badge)
        Text(agent.model ?: "默认模型", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Text(note, fontSize = 11.sp, color = C.subtle)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Said(thread: Thread, m: Message, draft: Draft) {
    val app = LocalApp.current
    val context = LocalContext.current
    var pressed by remember { mutableStateOf(false) }
    var bounds by remember { mutableStateOf(Rect.Zero) }
    val hold = Modifier.onGloballyPositioned { bounds = it.boundsInRoot() }.combinedClickable(
        interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = {},
        onLongClick = {
            pressed = true
            app.menu = MenuSpec(bounds, listOf(
                MenuItem("引用", Icons.Quote) {
                    val flat = m.text.replace(Regex("[`*#>]"), "").replace(Regex("\\s+"), " ").trim()
                    draft.quote = Quote(m.name, flat.take(60) + if (flat.length > 60) "…" else "", "", m.id, if (m.author == Author.Agent) "agent" else "person")
                    draft.focus++
                },
                MenuItem("拷贝", Icons.Copy) {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("ember", m.text))
                },
            ), onDismiss = { pressed = false })
        },
    )
    val press = if (pressed && app.menu != null) C.accent.copy(alpha = 0.12f) else Color.Transparent
    if (app.menu == null && pressed) pressed = false
    when (m.author) {
        Author.Me -> Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            m.quotes.forEach { QuoteCard(it) }
            if (m.text.isNotEmpty()) BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                Text(
                    m.text, fontSize = 15.sp, lineHeight = 22.sp, color = C.ink,
                    modifier = Modifier.widthIn(max = maxWidth * 0.82f).then(hold)
                        .clip(RoundedCornerShape(20.dp, 20.dp, 6.dp, 20.dp)).background(C.bubble).background(press).padding(horizontal = 14.dp, vertical = 9.dp),
                )
            }
            Files(thread, m.attachments)
            when {
                m.failed != null -> Failed(thread, m)
                m.sending -> Text("发送中…", fontSize = 11.sp, color = C.subtle)
                else -> Text(relativeTime(m.createdAt), fontSize = 11.sp, color = C.subtle)
            }
        }
        Author.Ember -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Mark(18.dp)
                Text("ember", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(relativeTime(m.createdAt), fontSize = 11.sp, color = C.subtle)
            }
            Text(m.text, fontSize = 14.sp, lineHeight = 21.sp, color = C.muted, modifier = hold)
        }
        Author.Person -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Avatar(m.personId, m.name, 20.dp)
                Text(m.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(relativeTime(m.createdAt), fontSize = 11.sp, color = C.subtle)
            }
            m.quotes.forEach { QuoteCard(it) }
            if (m.text.isNotEmpty()) Text(m.text, fontSize = 15.sp, lineHeight = 23.sp, color = C.ink, modifier = hold.clip(RoundedCornerShape(12.dp)).background(press))
            Files(thread, m.attachments)
        }
        Author.Agent -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val agent = m.agent!!
            AgentHead(agent, if (m.declared == "block") "block" else relativeTime(m.createdAt)) { openHistory(app, thread, agent) }
            m.quotes.forEach { QuoteCard(it) }
            Box(hold.clip(RoundedCornerShape(12.dp)).background(press)) { Markdown(m.text) }
            Files(thread, m.attachments)
            if (m.declared == "block" && thread.state == ChatState.Block) BlockCard(thread)
        }
    }
}

/** A message of yours that did not go: why, and what to do about it. */
@Composable
private fun Failed(thread: Thread, m: Message) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(thread.station)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("没发出去：${m.failed}", fontSize = 11.sp, color = C.red, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        Text("重试", fontSize = 12.sp, color = C.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { scope.launch { try { api.retry(thread.key, m.id) } catch (_: CoreException) {} } })
        Text("丢弃", fontSize = 12.sp, color = C.muted, modifier = Modifier.clickable { scope.launch { try { api.discard(thread.key, m.id) } catch (_: CoreException) {} } })
    }
}

/** The agent waits on people: its question is the message above; answers are one tap. */
@Composable
private fun BlockCard(thread: Thread) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    Column(
        Modifier.padding(top = 6.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.accentBg).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(C.accent))
            Text("agent 停下来等你决定", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = C.accentInk)
        }
        QuickReplies(QUICK, onMore = null) { text -> scope.launch { answer(app, thread.station, thread.key, text, toast = false) } }
    }
}

@Composable
private fun QuoteCard(q: Quote) {
    Column(Modifier.widthIn(max = 260.dp).clip(RoundedCornerShape(12.dp)).background(C.chip).padding(horizontal = 10.dp, vertical = 6.dp)) {
        Text(buildQuote(q.author, q.text), fontSize = 12.sp, color = C.muted, maxLines = 3, overflow = TextOverflow.Ellipsis)
        if (q.comment.isNotEmpty()) Text(q.comment, fontSize = 13.sp, color = C.ink)
    }
}

@Composable
private fun buildQuote(who: String, text: String) = androidx.compose.ui.text.buildAnnotatedString {
    pushStyle(androidx.compose.ui.text.SpanStyle(color = C.ink, fontWeight = FontWeight.Medium)); append("$who："); pop()
    append(text)
}

// ── the running turn ───────────────────────────────────────────────────

/**
 * An agent at work: its last three rows in three fixed lines, the newest
 * coming in from below and pushing the oldest out above. The whole block
 * opens the execution history: it is a glimpse of it.
 */
@Composable
private fun Activity(thread: Thread, agent: Agent, view: ChatView, live: LiveView?) {
    val app = LocalApp.current
    val rows = activityRows(live?.timeline ?: emptyList(), live?.steps ?: emptyList(), live?.phase)
        .ifEmpty { listOf(dev.ember.android.data.ActivityRow("idle", "正在处理", true)) }
    val since = view.turns.lastOrNull()?.takeIf { it.endedAt == null }?.startedAt ?: live?.phase?.since
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).clickable { openHistory(app, thread, agent) }.padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AgentHead(agent, "工作中" + (since?.let { " · ${elapsed(now - it)}" } ?: ""), ChatState.Running) { openHistory(app, thread, agent) }
        // One row more than fits sits above the window, so the oldest can slide out as the rest move up.
        val shown = rows.takeLast(4)
        val shift = remember { Animatable(0f) }
        val newest = shown.last().key
        var seen by remember { mutableStateOf(newest) }
        LaunchedEffect(newest) {
            if (newest != seen && rows.size > 3) { shift.snapTo(1f); shift.animateTo(0f, tween(450, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) }
            seen = newest
        }
        // Rows fill from the top; once there are more than fit, the newest sits at the bottom.
        Box(Modifier.fillMaxWidth().height(66.dp).clipToBounds(), contentAlignment = if (shown.size > 3) Alignment.BottomStart else Alignment.TopStart) {
            Column(Modifier.wrapContentHeight(if (shown.size > 3) Alignment.Bottom else Alignment.Top, unbounded = true).graphicsLayer { translationY = shift.value * 22.dp.toPx() }) {
                shown.forEach { r ->
                    Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.width(9.dp), contentAlignment = Alignment.Center) {
                            Box(Modifier.size(if (r.live) 7.dp else 5.dp).clip(CircleShape).background(if (r.live) C.accent else C.line))
                        }
                        Text(if (r.live) r.text + "…" else r.text, fontSize = 13.sp, color = if (r.live) C.ink else C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

// ── files ──────────────────────────────────────────────────────────────

private val IMAGE = Regex("\\.(png|jpe?g|gif|webp)$", RegexOption.IGNORE_CASE)

/** Files sent never change: each is fetched once and the most recent are kept. */
private val images = LruCache<String, ImageBitmap>(40)

@Composable
private fun Files(thread: Thread, files: List<Attachment>) {
    if (files.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        files.forEach { f -> if (IMAGE.containsMatchIn(f.name)) StationImage(thread, f) else FileCard(f.name, f.size) }
    }
}

@Composable
private fun StationImage(thread: Thread, file: Attachment) {
    val app = LocalApp.current
    val id = "${thread.station}/${thread.key}/${file.path}"
    val image by produceState(images.get(id), id) {
        if (value != null) return@produceState
        value = try {
            val bytes = app.api(thread.station).file(thread.key, file.path.substringAfterLast('/'))
            withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }?.also { images.put(id, it) }
        } catch (_: CoreException) {
            null
        }
    }
    // The box is known before the image loads: its own proportions within 240×200.
    val (w, h) = if (file.width != null && file.height != null) {
        val scale = minOf(1f, 240f / file.width, 200f / file.height)
        (file.width * scale).dp to (file.height * scale).dp
    } else 170.dp to 120.dp
    Box(Modifier.size(w, h).clip(RoundedCornerShape(14.dp)).background(C.chip)) {
        image?.let { Image(it, file.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
    }
}

@Composable
private fun FileCard(name: String, size: Long, note: String? = null, onRemove: (() -> Unit)? = null) {
    Row(
        Modifier.widthIn(max = 260.dp).clip(RoundedCornerShape(12.dp)).background(C.chip).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconIn(Icons.File, 18.dp, C.muted)
        Column(Modifier.weight(1f, fill = false)) {
            Text(name, fontSize = 13.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(note ?: fileSize(size), fontSize = 11.sp, color = C.muted)
        }
        if (onRemove != null) Box(Modifier.size(20.dp).clickable(onClick = onRemove), contentAlignment = Alignment.Center) { IconIn(Icons.Close, 12.dp, C.subtle) }
    }
}

fun fileSize(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${bytes / 1024} KB"
    else -> String.format(java.util.Locale.ROOT, "%.1f MB", bytes / 1024.0 / 1024.0)
}

// ── the composer ───────────────────────────────────────────────────────

/** A file on its way to the station: uploading, uploaded, or failed. */
class Pending(val id: Long, val name: String, val size: Long, val preview: ImageBitmap?) {
    var done by mutableStateOf<Attachment?>(null)
    var error by mutableStateOf<String?>(null)
}

/** What is being written: text, a quote, files. Kept while the chat is open. */
class Draft {
    var text by mutableStateOf("")
    var quote by mutableStateOf<Quote?>(null)
    val files = mutableStateListOf<Pending>()
    var sending by mutableStateOf(false)
    /** Bumped to put the cursor in the field (after quoting). */
    var focus by mutableStateOf(0)
    var warmed = 0L
    val uploading get() = files.any { it.done == null && it.error == null }
    val ready get() = (text.isNotBlank() || quote != null || files.any { it.done != null }) && !uploading && !sending
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
fun AppState.upload(draft: Draft, station: String, key: suspend () -> String, picked: Picked, scope: kotlinx.coroutines.CoroutineScope) {
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

/** What waits to go with the message: the quote, then the files. */
@Composable
fun DraftExtras(draft: Draft) {
    draft.quote?.let { q ->
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.chip).padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconIn(Icons.Quote, 14.dp, C.accent)
            Text(buildQuote(q.author, q.text), fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Box(Modifier.size(22.dp).clickable { draft.quote = null }, contentAlignment = Alignment.Center) { IconIn(Icons.Close, 14.dp, C.subtle) }
        }
    }
    if (draft.files.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        draft.files.forEach { f ->
            val remove = { draft.files.remove(f); Unit }
            if (f.preview != null) Box(Modifier.size(56.dp).clip(RoundedCornerShape(12.dp)).background(C.chip)) {
                Image(f.preview, f.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                if (f.done == null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (f.error != null) 0.5f else 0.25f)), contentAlignment = Alignment.Center) {
                    if (f.error != null) Text("失败", color = Color.White, fontSize = 11.sp)
                }
                Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(18.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).clickable(onClick = remove), contentAlignment = Alignment.Center) {
                    IconIn(Icons.Close, 10.dp, Color.White)
                }
            } else FileCard(f.name, f.size, f.error ?: if (f.done == null) "正在上传…" else null, remove)
        }
    }
}

/** The bar: ＋, a field that grows with the text, and a round send button. */
@Composable
fun ComposerBar(draft: Draft, placeholder: String, onPlus: () -> Unit, onType: () -> Unit, onSend: () -> Unit) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(C.chip).clickable(onClick = onPlus), contentAlignment = Alignment.Center) { IconIn(Icons.Plus, 18.dp) }
        Box(
            Modifier.weight(1f).heightIn(min = 36.dp).clip(RoundedCornerShape(18.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(18.dp))
                .padding(horizontal = 14.dp, vertical = 7.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (draft.text.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp)
            val focus = remember { FocusRequester() }
            LaunchedEffect(draft.focus) { if (draft.focus > 0) focus.requestFocus() }
            BasicTextField(
                draft.text, { draft.text = it; onType() }, textStyle = TextStyle(color = C.ink, fontSize = 15.sp, lineHeight = 21.sp),
                cursorBrush = SolidColor(C.accent), maxLines = 6, modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
        }
        val ready = draft.ready
        Box(
            Modifier.size(36.dp).clip(CircleShape).background(if (ready) C.ink else C.line).clickable(enabled = ready, onClick = onSend),
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Up, 18.dp, if (ready) C.bg else C.surface) }
    }
}

@Composable
private fun Composer(thread: Thread, draft: Draft) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(thread.station)
    val launchers = AttachLaunchers { app.upload(draft, thread.station, { thread.key }, it, scope) }
    Column(Modifier.fillMaxWidth().background(C.bg).padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        DraftExtras(draft)
        ComposerBar(draft, "给这个会话发消息", onPlus = { openAttach(app, launchers) },
            // Typing starts the session's runtime, so a cold start overlaps the writing.
            onType = {
                if (System.currentTimeMillis() - draft.warmed > 60_000) {
                    draft.warmed = System.currentTimeMillis()
                    scope.launch { try { api.warm(thread.key) } catch (_: CoreException) {} }
                }
            },
            // The message shows at once from the chat's outbox; one that fails stays there with a way to retry.
            onSend = {
                val text = draft.text.trim()
                val files = draft.files.mapNotNull { it.done }
                val quotes = listOfNotNull(draft.quote)
                draft.text = ""; draft.quote = null; draft.files.clear()
                scope.launch { try { api.send(thread.key, text, files, quotes) } catch (_: CoreException) {} }
            })
    }
}

// ── the chat's own page ────────────────────────────────────────────────

/** Who takes part (each agent leads to its history), notifications, actions. */
fun openChatInfo(app: AppState, thread: Thread) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        SheetGrab()
        SheetHead("对话信息")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            GroupLabel("参与的 agent · 点开看它的执行历史")
            InfoList {
                thread.agents.forEachIndexed { i, a ->
                    InfoRow(i == 0, onClick = { openHistory(app, thread, a) }) {
                        ModelMark(a.model, 36.dp, a.state, around = C.surface2)
                        Column(Modifier.weight(1f)) {
                            Text(a.model ?: "默认模型", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                            Text("${stationName(a.station)} · ${STATE_LABEL[a.state]}", fontSize = 12.sp, color = C.muted)
                        }
                        IconIn(Icons.Chevron, 14.dp, C.subtle)
                    }
                }
            }
            GroupLabel("参与的人")
            InfoList {
                thread.people.forEachIndexed { i, p ->
                    InfoRow(i == 0) {
                        Avatar(p.id, p.name, 28.dp)
                        Column(Modifier.weight(1f)) {
                            Text(p.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                            if (thread.isMe(p)) Text("你", fontSize = 12.sp, color = C.muted)
                            else if (p.via == "slack") Text("Slack", fontSize = 12.sp, color = C.muted)
                        }
                    }
                }
            }
            GroupLabel("通知")
            InfoList {
                InfoRow(true) {
                    Column(Modifier.weight(1f)) {
                        Text("这个对话的推送", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                        Text("agent block 时通知我", fontSize = 12.sp, color = C.muted)
                    }
                    var on by remember { mutableStateOf(app.flag("push/${thread.station}/${thread.key}", true)) }
                    Toggle(on) { on = it; app.setFlag("push/${thread.station}/${thread.key}", it) }
                }
            }
            Spacer(Modifier.height(14.dp))
            InfoList {
                var first = true
                thread.slackUrl?.let { url ->
                    InfoRow(true, onClick = { openUrl(context, url) }) { SlackMark(14.dp); Text("在 Slack 中打开", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink) }
                    first = false
                }
                InfoRow(first, onClick = {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("ember", chatUrl(app, thread.station, thread.key)))
                    app.toast = "链接已拷贝"
                }) { Text("拷贝链接", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink) }
                InfoRow(false, onClick = { openUrl(context, chatUrl(app, thread.station, thread.key)) }) {
                    Text("在电脑上打开", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.weight(1f))
                    IconIn(Icons.External, 14.dp, C.subtle)
                }
                InfoRow(false, onClick = {
                    scope.launch {
                        try {
                            app.api(thread.station).archive(thread.key)
                            app.pop()
                            app.toast = "已归档"
                        } catch (e: CoreException) {
                            app.toast = "没能归档：${e.message}"
                        }
                    }
                }) { Text("归档对话", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.red) }
            }
        }
    }
}

@Composable
fun GroupLabel(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))

@Composable
fun InfoList(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.surface2).border(1.dp, C.line, RoundedCornerShape(14.dp))) { content() }
}

@Composable
fun InfoRow(first: Boolean, onClick: (() -> Unit)? = null, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    if (!first) Box(Modifier.fillMaxWidth().height(1.dp).background(C.line))
    Row(
        Modifier.fillMaxWidth().let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}
