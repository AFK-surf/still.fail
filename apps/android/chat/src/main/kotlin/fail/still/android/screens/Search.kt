// The search at the top of the home lists (web mobile/Home.tsx SearchField, SearchPage): a field there once a list is
// scrolled to its top; tapped, the list goes up and away with the bars, the field comes up from where it was to the
// top (narrowing as 取消 comes in beside it), and under it what the words find in the workspace (the core's `search`,
// as ⌘K's on the wide screen, docs/search.md): the chats, the messages that have them (newest first, each opening its
// chat at it), then what the stations found besides, a section per kind (execution history, services and tasks,
// skills, memory, profiles, stations). 查看更多 under a section lists that kind alone; 全部结果 (or back) every kind
// again. Under it all, the stations still answering and what the core says of the rest. 取消 (or back) puts the field
// back in the list.
package fail.still.android.screens

import androidx.activity.compose.BackHandler
import fail.still.android.ui.Smooth
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import fail.still.android.ui.STROKE_MS
import fail.still.android.ui.STROKE_GAP_MS
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.draw.drawBehind
import androidx.compose.animation.core.LinearEasing
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import fail.still.android.ui.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.AppState
import fail.still.android.data.ChatItem
import fail.still.android.data.ChatOf
import fail.still.android.data.SearchItem
import fail.still.android.data.SearchView
import fail.still.android.data.StationView
import fail.still.android.data.TextMark
import fail.still.android.data.FoundMessage
import fail.still.android.data.Topics
import fail.still.android.data.page
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Ease
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.StationMark
import fail.still.android.ui.WaitLine
import fail.still.android.data.t
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** The field's height, and the room over it in the search's bar (as the home bar's: 8dp under the status bar). */
private val FIELD = 38.dp
private val BAR_TOP = 8.dp

/** At a list's top: tapped, the search opens from it (`onOpen`, with its top in the root and its width, px). `hidden`
 *  while the search's field is it (one field at a time, flying from and back to here). */
@Composable
internal fun SearchField(onOpen: (Float, Float) -> Unit, hidden: Boolean) {
    var at by remember { mutableStateOf(Rect.Zero) }
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 6.dp).height(FIELD).onGloballyPositioned { at = it.boundsInRoot() }
            .graphicsLayer { alpha = if (hidden) 0f else 1f }.clip(Smooth(FIELD / 2)).background(C.ink.copy(alpha = 0.06f)).clickable { onOpen(at.top, at.width) }.padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconIn(Icons.Search, 17.dp, C.muted)
        Text(t("android-chat.search.field"), fontSize = 15.sp, color = C.muted, maxLines = 1)
    }
}

/**
 * The search over the home lists, its field come up from `from` (its top in the list, px) to the bar, from `wide` (its
 * width there, px) to the room 取消 leaves it; `onLeave` as it starts going back, `onClose` once it is back there. The words typed stay while a chat opened from it is read.
 */
@Composable
internal fun SearchPage(scope: String, from: Float, wide: Float, onLeave: () -> Unit = {}, onClose: () -> Unit) {
    val app = LocalApp.current
    val density = LocalDensity.current
    var query by rememberSaveable { mutableStateOf("") }
    // One kind alone (查看更多), more of it; null: every kind, a few of each.
    var kind by rememberSaveable { mutableStateOf<String?>(null) }
    val search by rememberTopic<SearchView>(app.core, Topics.search(scope, query, kind))
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(scope))
    val several = (stations.value?.size ?: 0) > 1
    // While the next words are looked up, what the last ones found stays.
    val kept = remember { arrayOfNulls<SearchView>(1) }
    search.value?.let { kept[0] = it }
    val view = search.value ?: kept[0]
    val words = query.isNotBlank()
    val chats = if (words) view?.items.orEmpty() else emptyList()
    val messages = if (words) view?.messages.orEmpty() else emptyList()
    val groups = if (words) view?.groups.orEmpty() else emptyList()
    val none = chats.isEmpty() && messages.isEmpty() && groups.all { it.items.isEmpty() }
    val list = rememberLazyListState()
    // Into one kind or back out of it: from the top.
    LaunchedEffect(kind) { list.scrollToItem(0) }
    // Where the field is laid out (under the status bar, as the home bar's top), so its move is known before it is drawn.
    val to = WindowInsets.statusBars.getTop(density) + with(density) { BAR_TOP.toPx() }
    val up = remember { Animatable(0f) }
    var leaving by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val coroutines = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        focus.requestFocus()
        up.animateTo(1f, tween(280, easing = Ease.Arrive))
    }
    val close = {
        if (!leaving) {
            leaving = true
            keyboard?.hide()
            onLeave()
            coroutines.launch {
                up.animateTo(0f, tween(240, easing = Ease.Standard))
                onClose()
            }
        }
    }
    BackHandler(enabled = !leaving) { close() }
    // Over one kind alone, back goes to every kind first (registered after, so asked first).
    BackHandler(enabled = !leaving && kind != null) { kind = null }
    // Over the lists (faded away, still there): nothing under it is touched through it.
    Column(Modifier.fillMaxSize().clickable(interactionSource = null, indication = null) {}.imePadding()) {
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = BAR_TOP, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // As wide as the list's while there, narrowing to its room as it comes up (and back as it goes): 取消 comes in
            // with its right edge, not the field jumping between the two widths.
            Row(
                Modifier.weight(1f).layout { measurable, constraints ->
                    val room = constraints.maxWidth
                    val now = if (wide > 0f) (wide + (room - wide) * up.value).roundToInt().coerceAtLeast(0) else room
                    val placeable = measurable.measure(constraints.copy(minWidth = now, maxWidth = now))
                    layout(room, placeable.height) { placeable.place(0, 0) }
                }.height(FIELD).graphicsLayer { translationY = (from - to) * (1f - up.value) }
                    .clip(Smooth(FIELD / 2)).background(C.ink.copy(alpha = 0.06f)).padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                IconIn(Icons.Search, 17.dp, C.muted)
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (query.isEmpty()) Text(t("android-chat.search.field"), fontSize = 16.sp, color = C.muted, maxLines = 1)
                    BasicTextField(
                        query, { query = it }, singleLine = true, cursorBrush = SolidColor(C.accent),
                        textStyle = TextStyle(fontSize = 16.sp, color = C.ink),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        modifier = Modifier.fillMaxWidth().focusRequester(focus).semantics { contentDescription = t("android-chat.search.field") },
                    )
                }
            }
            Text(
                t("android-chat.search.cancel"), fontSize = 16.sp, color = C.link,
                modifier = Modifier.graphicsLayer { alpha = up.value; translationX = (size.width + 12.dp.toPx()) * (1f - up.value) }.clickable(enabled = !leaving) { close() },
            )
        }
        LazyColumn(Modifier.fillMaxWidth().weight(1f).graphicsLayer { alpha = up.value }, state = list) {
            if (words && kind != null) item(key = "all") { BackRow { kind = null } }
            if (words && view == null && search.error != null) item(key = "update") { SearchNote(t("android-chat.search.update")) }
            if (chats.isNotEmpty()) {
                item(key = "chats") { SectionHeader(t("android-chat.search.chats")) }
                items(chats, key = { "c/${it.station}/${it.id}" }) { item ->
                    val found = item.foundText
                    if (found != null) FoundChatRow(item, found)
                    else ChatRowBody(item, "agents", held = false, modifier = Modifier.clickable { app.push(Screen.Chat(item.station, item.page)) })
                }
                if (kind == null && view?.chatsMore == true) item(key = "more/chat") { MoreRow { kind = "chat" } }
            }
            if (messages.isNotEmpty()) {
                item(key = "messages") { SectionHeader(t("android-chat.search.messages")) }
                items(messages, key = { "m/${it.station}/${it.thread}/${it.seq}" }) { FoundRow(it, view?.words) }
                if (kind == null && view?.messagesMore == true) item(key = "more/message") { MoreRow { kind = "message" } }
            }
            for (group in groups) {
                item(key = "g/${group.kind}") { SectionHeader(group.title) }
                items(group.items, key = { "i/${it.key}" }) { ItemRow(it, several) { openFound(app, it) } }
                if (kind == null && group.more) item(key = "more/${group.kind}") { MoreRow { kind = group.kind } }
            }
            // Under what was found: the stations still answering (or that could not be searched), and what the core
            // says of the rest (offline, too old to search, an index still being built).
            if (words && view != null) {
                val wait = view.wait
                if (none && !wait.reading) item(key = "none") { SearchNote(t("android-chat.search.none")) }
                if (wait.reading) item(key = "reading") { WaitLine(wait.text ?: t("common.reading"), modifier = Modifier.padding(horizontal = 22.dp, vertical = 12.dp)) }
                items(wait.failing, key = { "failing/${it.station}" }) { WaitLine(it.text, error = true, modifier = Modifier.padding(horizontal = 22.dp, vertical = 6.dp)) }
                view.note?.let { note -> item(key = "note") { Text(note, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 12.dp)) } }
            }
        }
    }
}

/** 查看更多 under a kind: that kind alone. */
@Composable
private fun MoreRow(onClick: () -> Unit) {
    Text(
        t("android-chat.search.more"), fontSize = 14.sp, color = C.link, maxLines = 1,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = 22.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
    )
}

/** Over one kind alone: back to every kind (as back does). */
@Composable
private fun BackRow(onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        IconIn(Icons.ChevronLeft, 16.dp, C.accent)
        Text(t("android-chat.search.all"), fontSize = 14.sp, color = C.link, maxLines = 1)
    }
}

/** What a kind is drawn with (web Switcher.tsx's KIND_ICON). */
private fun kindIcon(kind: String): ImageVector = when (kind) {
    "file" -> Icons.File
    "job" -> Icons.Web
    "station" -> Icons.Server
    "member" -> Icons.User
    else -> Icons.Search
}

/**
 * Something found besides a chat or a message: its kind's icon (a station its own mark), what it is, where (its
 * station, with several) and when, over its line that has the words.
 */
@Composable
private fun ItemRow(item: SearchItem, several: Boolean, onClick: () -> Unit) {
    val ink = C.ink
    val line = remember(item.text, item.marks, ink) { marked(item.text, item.marks, ink) }
    Row(
        Modifier.fillMaxWidth().height(if (item.text.isEmpty()) 50.dp else 66.dp).clickable(onClick = onClick).padding(start = 22.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) {
            if (item.kind == "station") StationMark(item.stationEmoji, item.stationIcon, 18.dp, C.muted, none = Icons.Server)
            else IconIn(if (item.kind == "file" && item.dir == true) Icons.Folder else kindIcon(item.kind), 18.dp, C.muted)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(item.title, fontSize = 15.sp, lineHeight = 22.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                val meta = listOfNotNull(item.stationName.takeIf { several && item.kind != "station" && it.isNotEmpty() }, item.time?.get("createdAt")?.ago).joinToString(" · ")
                if (meta.isNotEmpty()) Text(meta, fontSize = 12.sp, color = C.muted, maxLines = 1)
            }
            if (item.text.isNotEmpty()) StrokedLine(line, item.marks, 14.sp, 20.sp, C.muted, Modifier.height(20.dp))
        }
    }
}

/**
 * Where something found opens (as the web's, Switcher.tsx openOf): a service its chat and its page, a task its chat; a
 * station its page; a member the workspace's page; anything else its chat.
 */
internal fun openFound(app: AppState, item: SearchItem) {
    val chat = item.chat?.let { Screen.Chat(item.station, ChatOf.Session(it)) }
    when (item.kind) {
        "job" -> {
            if (chat == null) return
            app.push(chat)
            val job = item.job
            if (item.port != null && job != null) app.push(Screen.Preview(item.station, job))
        }
        "station" -> app.push(Screen.Station(item.station))
        "member" -> app.push(Screen.Workspace)
        "file" -> fileScreen(item)?.let(app::push)
        else -> chat?.let(app::push)
    }
}

/**
 * Where a file found opens in its station's files (as the web's searchOpen.ts): a folder entered, a text read, a video or
 * song played, anything else shown in its folder; under the folder a read-only member's workspace pinned (`root`) when
 * found there, else from its own folder.
 */
internal fun fileScreen(item: SearchItem): Screen? {
    val path = item.path ?: return null
    val cut = maxOf(path.lastIndexOf('/'), path.lastIndexOf('\\'))
    val folder = if (cut > 0) path.substring(0, cut) else path
    val name = if (cut > 0) path.substring(cut + 1) else ""
    val dir = item.dir == true
    val root = item.root ?: if (dir) path else folder
    val rel = if (item.root != null) item.rel ?: "" else if (dir) "" else name
    val parent = if (rel.contains('/')) rel.substring(0, rel.lastIndexOf('/')) else ""
    return when (if (dir) "folder" else item.fileKind) {
        "folder" -> Screen.Drive(item.station, root, rel)
        "text", "markdown" -> Screen.DriveRead(item.station, root, rel)
        "video", "audio" -> Screen.DrivePlay(item.station, root, rel)
        else -> Screen.Drive(item.station, root, parent)
    }
}

/** `text` with the words found (`marks`) in ink and bold, the rest as the line's colour. */
private fun marked(text: String, marks: List<TextMark>, ink: Color): AnnotatedString = buildAnnotatedString {
    var at = 0
    for (m in marks) {
        val from = m.from.toInt()
        val to = m.to.toInt()
        if (from < at || to > text.length || from > to) continue
        append(text.substring(at, from))
        withStyle(SpanStyle(color = ink, fontWeight = FontWeight.SemiBold)) { append(text.substring(from, to)) }
        at = to
    }
    append(text.substring(at))
}

/**
 * A found line, one line cut at its end, with a hand-drawn stroke in the accent under each of its words (as a message a
 * search opened marks them, ui/TextMark.kt), drawn in from the left one after another.
 */
@Composable
private fun StrokedLine(line: AnnotatedString, marks: List<TextMark>, size: TextUnit, height: TextUnit, color: Color, modifier: Modifier) {
    val accent = C.accent
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val drawn = remember(line) { Animatable(0f) }
    LaunchedEffect(line) { drawn.animateTo(STROKE_MS + STROKE_GAP_MS * marks.size, tween((STROKE_MS + STROKE_GAP_MS * marks.size).toInt(), easing = LinearEasing)) }
    Text(
        line, fontSize = size, lineHeight = height, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, onTextLayout = { layout = it },
        modifier = modifier.drawBehind {
            val l = layout ?: return@drawBehind
            val end = l.getLineEnd(0, visibleEnd = true)
            marks.forEachIndexed { i, m ->
                val from = m.from.toInt()
                val to = minOf(m.to.toInt(), end)
                if (from >= to) return@forEachIndexed
                val p = Ease.Standard.transform(((drawn.value - i * STROKE_GAP_MS) / STROKE_MS).coerceIn(0f, 1f))
                if (p <= 0f) return@forEachIndexed
                // The glyphs' own boxes (a position between two characters falls short of a bold one's).
                val left = l.getBoundingBox(from).left - 2.dp.toPx()
                val right = l.getBoundingBox(to - 1).right + 2.dp.toPx()
                val y = l.getLineBaseline(0) + 3.dp.toPx()
                val w = right - left
                val stroke = Path().apply {
                    moveTo(left, y)
                    cubicTo(left + w * 0.25f, y - 2.dp.toPx(), left + w * 0.55f, y + 1.5.dp.toPx(), right, y - 1.5.dp.toPx())
                }
                val part = Path()
                PathMeasure().apply { setPath(stroke, false); getSegment(0f, length * p, part, true) }
                drawPath(part, accent, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
            }
        },
    )
}

@Composable
private fun SearchNote(text: String) {
    Text(text, fontSize = 14.sp, color = C.muted, modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 16.dp))
}

/** A message the words found: the line that has them (they bold), who said it and when, over its chat; tapped, its chat
 *  opens at it, the words marked there. */
@Composable
private fun FoundRow(found: FoundMessage, words: List<String>?) {
    val app = LocalApp.current
    val meta = listOfNotNull(found.by.takeIf { it.isNotEmpty() }, found.time?.get("createdAt")?.ago).joinToString(" · ")
    HitRow(found.text, found.marks, meta, found.chat.title) { app.push(Screen.Chat(found.station, found.chat.page, at = found.seq, words = words)) }
}

/** A chat found by words its title shows late or not at all: the part of it that has them first, its title under it. */
@Composable
private fun FoundChatRow(item: ChatItem, found: String) {
    val app = LocalApp.current
    val meta = listOfNotNull(if (item.archived == true) t("android-chat.search.archived") else null, item.time?.get("lastActiveAt")?.ago).joinToString(" · ")
    HitRow(found, item.foundMarks.orEmpty(), meta, item.title) { app.push(Screen.Chat(item.station, item.page)) }
}

/** What has the words, on its first line the row's width (they bold); where it is (its chat) under it, who and when beside
 *  that. */
@Composable
private fun HitRow(text: String, marks: List<TextMark>, meta: String, under: String, onClick: () -> Unit) {
    val ink = C.ink
    val line = remember(text, marks, ink) { marked(text, marks, ink) }
    Column(
        Modifier.fillMaxWidth().height(66.dp).clickable(onClick = onClick).padding(start = 22.dp, end = 16.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        StrokedLine(line, marks, 15.sp, 22.sp, C.ink, Modifier.height(22.dp))
        Row(Modifier.height(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(under, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (meta.isNotEmpty()) Text(meta, fontSize = 12.sp, color = C.muted, maxLines = 1)
        }
    }
}
