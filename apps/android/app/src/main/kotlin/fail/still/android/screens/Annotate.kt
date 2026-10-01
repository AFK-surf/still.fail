// One message on a page of its own (a long press on it in the chat opens it; web mobile/Annotate.tsx): its words to
// pick passages from and say something about, or to copy. A short hold picks the word under the finger and sliding on
// widens it (moving at once scrolls); the ends then have handles to move. What is said about each passage goes into
// the chat's draft as a quote with its comment.
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.core.Transition
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.layout.requiredWidthIn
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.positionInRoot
import fail.still.android.ui.ComposerCorner
import fail.still.android.ui.ComposerInset
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import fail.still.android.ui.Ease
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import fail.still.android.LocalApp
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Drawn
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LocalPickedWords
import fail.still.android.ui.Markdown
import fail.still.android.ui.NavBar
import fail.still.android.ui.PickedWords
import fail.still.android.ui.Span
import fail.still.android.ui.floating
import fail.still.android.ui.floatingStill
import fail.still.android.ui.pickable
import fail.still.android.ui.withRefs
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** How long a finger holds still before it picks rather than scrolls. */
private const val HOLD = 260L

/** A numbered note, as its box and card show it (NoteBox, Card): a passage of a message's, or a mark on an image (ImageMarks.kt). */
interface NoteLike {
    val n: Int
    /** What it is about, in a line under what is said. */
    val text: String
    var comment: String
    /** Its pin's colour (none: the accent). */
    val color: Color? get() = null
}

private class Note(override val n: Int, val span: Span, override val text: String) : NoteLike {
    override var comment by mutableStateOf("")
}

/** The page's own way in and out: App.kt gives it the pages' transition (nothing slides; the page's parts move). */
val LocalPageTransition = staticCompositionLocalOf<Transition<EnterExitState>?> { null }

/**
 * What moves between a chat and one of its messages' pages, found by where it is laid out: the message's words there
 * and back (hidden in the chat meanwhile: one of them on the screen at a time), and the notes into the composer's
 * quotes (hidden there till they land).
 */
object AnnotateFlight {
    /**
     * Where each message's words were last laid out in its chat ("<station>/<ts>"), on the screen. Kept as a place, not
     * the layout: a list lays its rows out again now and then, and what flies must not lose its way meanwhile.
     */
    internal val sources = HashMap<String, Rect>()
    /** The message whose words are on its page, not in the chat (from the page's first frame to its last). */
    var away by mutableStateOf<String?>(null)
    /** Where the composer's quote cards were last laid out, by their draft quote's id. */
    internal val quotes = HashMap<Long, Rect>()
    /** The quotes on their way into the composer. */
    val landing = mutableStateListOf<Long>()
}

@Composable
fun AnnotateScreen(station: String, of: ChatOf, ts: String) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
    val view = chat.value
    val m = view?.messages?.firstOrNull { it.ts == ts }
    val author = m?.let { if (it.mine) "你" else it.by.name } ?: ""
    // In and out: 0 in the chat, 1 here (on the pages' transition, so a swipe back takes it back with the finger). Eased
    // in as well as out: the words start from where they are, not off at once.
    val page = LocalPageTransition.current
    val shown = page?.animateFloat({ tween(380, easing = Ease.Standard) }, label = "annotate") { if (it == EnterExitState.Visible) 1f else 0f }
        ?: remember { mutableFloatStateOf(1f) }
    val p = { shown.value }
    // Gone for good (the way out over): the words are the chat's again, and the quotes that flew in are there.
    DisposableEffect(Unit) { onDispose { AnnotateFlight.away = null; AnnotateFlight.landing.clear() } }
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.matchParentSize().graphicsLayer { alpha = p() }.background(C.bg))
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.graphicsLayer { alpha = p() }) {
                NavBar("对话", { app.pop() }, "批注", sub = if (m != null) { { Text(author, fontSize = 12.sp, color = C.muted) } } else null)
            }
            when {
                view == null -> Text("正在读取…", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
                m == null -> Text("找不到这条消息", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
                else -> Annotating(station, of, m, author, p)
            }
        }
    }
}

@Composable
private fun Annotating(station: String, of: ChatOf, m: ChatMessage, author: String, p: () -> Float) {
    val app = LocalApp.current
    val context = LocalContext.current
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val draft = rememberDraft(station, of)
    val words = remember(m.ts) { PickedWords() }
    val scroll = rememberScrollState()
    val haze = remember { HazeState() }
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Span?>(null) }
    var dragging by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Int?>(null) }
    val notes = remember { androidx.compose.runtime.mutableStateListOf<Note>() }
    var counter by remember { mutableIntStateOf(0) }
    // Where things are, for what flies between them: the page, the note box, the tray's cards, the send button.
    val placed = remember { PagePlaces() }
    // A note just written, its box on its way into its card (from where the box was).
    var landingNote by remember { mutableStateOf<Pair<Int, Rect>?>(null) }
    // The quotes put into the chat, on their way into its composer as the page goes (each from where it was here).
    var sending by remember { mutableStateOf<List<SentQuote>>(emptyList()) }
    val role = if (m.authorKind == "agent") "agent" else "person"

    // What the words draw over themselves: the passage being picked, those with notes, the one whose note is open.
    words.drawn = buildList {
        notes.forEach { add(it.span to if (it.n == editing) Drawn.Open else Drawn.Noted) }
        picked?.let { add(it to Drawn.Picked) }
    }

    fun copy(text: String) {
        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", text))
        app.toast = "已拷贝"
    }
    fun note() {
        val span = picked ?: return
        val n = ++counter
        notes += Note(n, span, words.textOf(span).trim())
        picked = null
        editing = n
    }
    fun remove(n: Int) { notes.removeAll { it.n == n }; editing = null }
    fun send() {
        if (draft.locked) { app.toast = "这个对话现在不能发消息"; return }
        val quotes = if (notes.isEmpty()) listOf(DraftQuote(System.nanoTime(), author, plainWords(m.text), m.ts, role))
        else notes.sortedWith(compareBy({ it.span.start }, { it.n })).map { x ->
            DraftQuote(System.nanoTime(), author, x.text, m.ts, role).also { it.comment = x.comment.trim() }
        }
        // Each from its card in the tray (the whole message, from the button).
        sending = if (notes.isEmpty()) listOfNotNull(placed.send.bounds()?.let { SentQuote(quotes[0], null, it) })
        else notes.sortedWith(compareBy({ it.span.start }, { it.n })).zip(quotes).mapNotNull { (x, q) -> placed.cards[x.n].bounds()?.let { SentQuote(q, x.n, it) } }
        AnnotateFlight.landing += sending.map { it.quote.id }
        draft.quotes += quotes
        draft.save()
        app.pop()
    }
    val tray = rememberLazyListState()
    LaunchedEffect(notes.size) { if (notes.isNotEmpty()) tray.animateScrollToItem(notes.size - 1) }

    BoxWithConstraints(Modifier.fillMaxSize().onGloballyPositioned { placed.page = it }.windowInsetsPadding(WindowInsets.ime)) {
        val width = constraints.maxWidth.toFloat()
        Column(Modifier.fillMaxSize().hazeSource(haze).verticalScroll(scroll)) {
            Box(Modifier.fillMaxWidth()) {
                // The words: picked from by a finger held on them (a tap on a noted passage opens its note; elsewhere, lets go).
                Box(
                    Modifier.fillMaxWidth().onGloballyPositioned { words.base = it }
                        .pointerInput(words) {
                            awaitEachGesture {
                                val down = awaitFirstDown()
                                val from = down.position
                                val slop = 8.dp.toPx()
                                // 0: lifted (a tap); 1: moved (a scroll); null: held (picking).
                                val outcome = withTimeoutOrNull(HOLD) {
                                    var r = -1
                                    while (r < 0) {
                                        val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                                        r = when {
                                            c == null -> 1
                                            !c.pressed -> { c.consume(); 0 }
                                            (c.position - from).getDistance() > slop -> 1
                                            else -> -1
                                        }
                                    }
                                    r
                                }
                                when (outcome) {
                                    0 -> {
                                        val at = words.offsetAt(from)
                                        val hit = at?.let { a -> notes.lastOrNull { a >= it.span.start && a < it.span.end } }
                                        if (hit != null) { picked = null; editing = hit.n } else { picked = null; editing = null }
                                    }
                                    1 -> {}
                                    else -> {
                                        val at = words.offsetAt(from) ?: return@awaitEachGesture
                                        val anchor = words.wordAt(at)
                                        picked = anchor
                                        editing = null
                                        dragging = true
                                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                        while (true) {
                                            val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                                            c.consume()
                                            if (!c.pressed) break
                                            val to = words.offsetAt(c.position) ?: continue
                                            val w = words.wordAt(to)
                                            picked = if (w.start >= anchor.start) Span(anchor.start, maxOf(anchor.end, w.end)) else Span(w.start, anchor.end)
                                        }
                                        dragging = false
                                    }
                                }
                            }
                        }
                        .padding(start = 32.dp, end = 14.dp, top = 12.dp, bottom = 24.dp),
                ) {
                    // From where they were in the chat to here, and back (by the page's way in and out). Laid out as they are
                    // there (its size of type, its width: the same lines), drawn smaller only where the page is narrower, so
                    // what flies is one picture from end to end, its lines never broken again.
                    val key = "$station/${m.ts}"
                    val chatWidth = remember(key) { AnnotateFlight.sources[key]?.width } ?: (width - with(density) { 28.dp.toPx() })
                    val room = width - with(density) { (32 + 14).dp.toPx() }
                    Box(Modifier.flown(key, p).scaledFrom(chatWidth.roundToInt(), (room / chatWidth).coerceAtMost(1f))) { CompositionLocalProvider(LocalPickedWords provides words) {
                        if (m.authorKind == "person") {
                            val text = withRefs(m.text)
                            val (pick, picking) = pickable(text.text)
                            Text(text, pick, fontSize = 15.sp, lineHeight = 23.sp, color = C.ink, onTextLayout = picking)
                        } else Markdown(m.text)
                    } }
                }
                // What is placed over the words follows where they are laid out, and comes and goes with the page.
                @Suppress("UNUSED_EXPRESSION") words.laidOut
                Box(Modifier.matchParentSize().graphicsLayer { alpha = p() }) {
                val px = { v: Float -> with(density) { v.toDp() } }
                val pickedRects = picked?.let { words.rects(it) }.orEmpty()
                // The notes' pins, in the margin beside their passage's first line: never over the words.
                notes.forEach { x ->
                    val first = words.rects(x.span).firstOrNull() ?: return@forEach
                    Box(Modifier.width(30.dp).offset(y = px(first.center.y) - 14.dp), contentAlignment = Alignment.CenterEnd) {
                        Pin(x.n, open = x.n == editing) { picked = null; editing = if (x.n == editing) null else x.n }
                    }
                }
                if (picked != null && pickedRects.isNotEmpty()) {
                    Handles(words, pickedRects, picked!!, { picked = it }, { dragging = it })
                    if (!dragging) {
                        val first = pickedRects.first()
                        val last = pickedRects.last()
                        // Over the passage; under it when the top of the page is too near.
                        val room = first.top - scroll.value
                        val top = if (room < with(density) { 60.dp.toPx() }) last.bottom + with(density) { 28.dp.toPx() } else first.top - with(density) { 52.dp.toPx() }
                        val centre = if (pickedRects.size > 1) width / 2 else first.center.x
                        val x = centre.coerceIn(with(density) { 110.dp.toPx() }, width - with(density) { 110.dp.toPx() })
                        val everything = picked!!.start == 0 && picked!!.end >= words.text().length
                        PickBar(Modifier.offset { IntOffset(x.roundToInt(), top.roundToInt()) }, everything,
                            onNote = { note() },
                            onCopy = { copy(words.textOf(picked!!)); picked = null },
                            onAll = { picked = Span(0, words.text().length) })
                    }
                }
                val open = notes.firstOrNull { it.n == editing }
                val openRects = open?.let { words.rects(it.span) }.orEmpty()
                if (open != null && openRects.isNotEmpty()) {
                    androidx.compose.runtime.key(open.n) {
                        NoteBox(open, Modifier.padding(horizontal = 12.dp).offset(y = px(openRects.last().bottom) + 10.dp).onGloballyPositioned { placed.note = it },
                            onDone = { landingNote = placed.note.bounds()?.let { open.n to it }; editing = null }, onRemove = { remove(open.n) })
                    }
                }
                }
            }
            Spacer(Modifier.height(if (notes.isNotEmpty()) 160.dp else 84.dp))
            Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars))
        }
        // Copying all of it, and putting the notes (or the whole message, as a quote) into the chat; the notes as they
        // are made gathered over them (a tap goes back to one).
        Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .graphicsLayer { alpha = p(); translationY = (1f - p()) * 16.dp.toPx() }
                .windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (notes.isNotEmpty()) {
                LazyRow(state = tray, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(notes, key = { _, x -> x.n }) { _, x ->
                        // Hidden while its note's box is on its way into it (that is it, coming).
                        val arriving = landingNote?.first == x.n
                        Card(x, x.n == editing, haze, Modifier.animateItem().onGloballyPositioned { placed.cards[x.n] = it }.graphicsLayer { alpha = if (arriving || sending.any { it.n == x.n }) 0f else 1f }) {
                            picked = null
                            editing = x.n
                            val first = words.rects(x.span).firstOrNull()
                            if (first != null) scope.launch { scroll.animateScrollTo((first.top - with(density) { 96.dp.toPx() }).roundToInt().coerceAtLeast(0)) }
                        }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val pill = RoundedCornerShape(22.dp)
                Row(
                    Modifier.height(44.dp).floating(haze, pill).clickable { copy(m.text) }.padding(horizontal = 18.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) { IconIn(Icons.Copy, 16.dp, C.ink); Text("复制全文", fontSize = 15.sp, color = C.ink) }
                Row(
                    Modifier.weight(1f).height(44.dp).onGloballyPositioned { placed.send = it }.floating(haze, pill).clickable { send() }.padding(horizontal = 18.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                ) {
                    IconIn(if (notes.isEmpty()) Icons.Quote else Icons.Send, 15.dp, C.accent)
                    Text(if (notes.isEmpty()) "引用全文" else "放进对话 · ${notes.size}", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.accent)
                }
            }
        }
        // What flies, over all of it (and not fading with the page).
        landingNote?.let { (n, from) ->
            val note = notes.firstOrNull { it.n == n }
            if (note == null) landingNote = null
            else androidx.compose.runtime.key(n) { NoteLanding(note, from, placed) { landingNote = null } }
        }
        sending.forEach { s -> androidx.compose.runtime.key(s.quote.id) { QuoteFlight(s, notes.firstOrNull { it.n == s.n }, placed, p) } }
    }
}

/** Where the page's parts are laid out (not state: what flies reads them as it draws). */
private class PagePlaces {
    var page: LayoutCoordinates? = null
    var note: LayoutCoordinates? = null
    var send: LayoutCoordinates? = null
    val cards = HashMap<Int, LayoutCoordinates>()
}

/** A quote put into the chat: its draft quote, its note's number (none: the whole message), where it was here. */
private class SentQuote(val quote: DraftQuote, val n: Int?, val from: Rect)

private fun LayoutCoordinates?.bounds(): Rect? = this?.takeIf { it.isAttached }?.boundsInRoot()

/**
 * The words, moved from where they were in the chat (`key`'s box there, scaled to its width) to where they are here as
 * `p` goes from 0 to 1, and back as it goes back. With no place in the chat to go to (scrolled out), they fade instead.
 */
@Composable
private fun Modifier.flown(key: String, p: () -> Float): Modifier {
    val rest = remember { arrayOfNulls<LayoutCoordinates>(1) }
    return onGloballyPositioned { rest[0] = it }.graphicsLayer {
        val t = p()
        if (t >= 1f) return@graphicsLayer
        // Not laid out yet (the first frame in): not shown till it can be where it comes from.
        val at = rest[0]?.takeIf { it.isAttached } ?: run { alpha = 0f; return@graphicsLayer }
        // Shown here from now on, where they are in the chat: away from there, so they are never gone from both.
        if (AnnotateFlight.away != key) AnnotateFlight.away = key
        val from = AnnotateFlight.sources[key]
        if (from == null) { alpha = t; return@graphicsLayer }
        val scale = from.width / at.size.width.coerceAtLeast(1)
        val to = at.positionInRoot()
        val k = 1f - t
        transformOrigin = TransformOrigin(0f, 0f)
        translationX = (from.left - to.x) * k
        translationY = (from.top - to.y) * k
        val s = scale + (1f - scale) * t
        scaleX = s; scaleY = s
    }
}

/** Laid out `width` wide (in px) and drawn at `scale` of that from its top left; as big as it is drawn. */
private fun Modifier.scaledFrom(width: Int, scale: Float) = layout { measurable, constraints ->
    val p = measurable.measure(constraints.copy(minWidth = width, maxWidth = width))
    layout((p.width * scale).roundToInt(), (p.height * scale).roundToInt()) {
        p.placeWithLayer(0, 0) { scaleX = scale; scaleY = scale; transformOrigin = TransformOrigin(0f, 0f) }
    }
}

/** A rectangle between two, `t` of the way. */
private fun lerpRect(a: Rect, b: Rect, t: Float) = Rect(a.left + (b.left - a.left) * t, a.top + (b.top - a.top) * t, a.right + (b.right - a.right) * t, a.bottom + (b.bottom - a.bottom) * t)

/** Laid out as `rect` says (in the screen's place), inside the page. */
private fun Modifier.placedAt(placed: PagePlaces, rect: () -> Rect) = layout { measurable, _ ->
    val r = rect()
    val origin = placed.page.bounds()?.topLeft ?: Offset.Zero
    val w = r.width.roundToInt().coerceAtLeast(0)
    val h = r.height.roundToInt().coerceAtLeast(0)
    val p = measurable.measure(androidx.compose.ui.unit.Constraints.fixed(w, h))
    layout(0, 0) { p.place((r.left - origin.x).roundToInt(), (r.top - origin.y).roundToInt()) }
}

/**
 * A note written: its box, from where it was, becomes its card in the tray: its frame goes there and takes the card's
 * size and corners while what it held gives way to what the card holds. At rest it is the card (shown then, in its place).
 */
@Composable
private fun NoteLanding(note: Note, from: Rect, placed: PagePlaces, done: () -> Unit) {
    val t = remember { Animatable(0f) }
    LaunchedEffect(Unit) { t.animateTo(1f, tween(360, easing = Ease.Arrive)); done() }
    val density = LocalDensity.current
    val rect = { placed.cards[note.n].bounds()?.let { lerpRect(from, it, t.value) } ?: from }
    val corner = with(density) { (26.dp + (16.dp - 26.dp) * t.value) }
    Box(Modifier.placedAt(placed, rect).floatingStill(RoundedCornerShape(corner))) {
        // What the box held, going; what the card holds, coming (it is laid out at the card's own size throughout).
        Box(Modifier.graphicsLayer { alpha = (1f - t.value * 2.5f).coerceIn(0f, 1f) }.padding(start = 16.dp, end = 16.dp, top = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Pin(note.n, small = true)
                Text(note.text, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Box(Modifier.graphicsLayer { alpha = ((t.value - 0.3f) / 0.7f).coerceIn(0f, 1f) }.requiredWidthIn(160.dp)) { CardContent(note) }
    }
}

/**
 * A quote put into the chat, on its way into the composer as the page goes (`p` from 1 to 0): from its card here (or
 * the button, for the whole message) into its card there, taking that card's size, ground and corners; what it shows
 * becomes what the composer shows. Where the composer's card is not laid out yet, it waits where it was.
 */
@Composable
private fun QuoteFlight(sent: SentQuote, note: Note?, placed: PagePlaces, p: () -> Float) {
    val raised = fail.still.android.ui.Raised.copy(alpha = 0.72f).compositeOver(C.bg)
    val ground = quoteGround().compositeOver(C.bg)
    val density = LocalDensity.current
    val t = { 1f - p() }
    val rect = { AnnotateFlight.quotes[sent.quote.id]?.let { lerpRect(sent.from, it, t()) } ?: sent.from }
    val corner = with(density) { 16.dp + (ComposerCorner - ComposerInset - 16.dp) * t() }
    Box(
        Modifier.placedAt(placed, rect).clip(RoundedCornerShape(corner))
            .drawBehind { drawRect(androidx.compose.ui.graphics.lerp(raised, ground, t())) },
    ) {
        if (note != null) Box(Modifier.graphicsLayer { alpha = (1f - t() * 2.5f).coerceIn(0f, 1f) }.requiredWidthIn(160.dp)) { CardContent(note) }
        Column(Modifier.graphicsLayer { alpha = ((t() - 0.3f) / 0.7f).coerceIn(0f, 1f) }) {
            Text(
                quoteLine(sent.quote.author, sent.quote.text), inlineContent = quoteMark(), fontSize = 13.sp, lineHeight = 19.5.sp, color = chatMuted(), maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 16.dp, end = 34.dp, top = 9.dp),
            )
            val said = sent.quote.comment
            Text(said.ifEmpty { "对这段说点什么（可以不写）" }, color = if (said.isEmpty()) chatSubtle() else C.ink, fontSize = 15.sp, lineHeight = 22.sp, maxLines = 1,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 3.dp, bottom = 10.dp))
        }
    }
}

/** A note's number, as a web page's marks show theirs: a pin, its point at the bottom right. */
@Composable
private fun Pin(n: Int, open: Boolean = false, small: Boolean = false, color: Color? = null, onClick: (() -> Unit)? = null) {
    val size = if (small) 16.dp else 20.dp
    val shape = if (small) RoundedCornerShape(8.dp, 8.dp, 2.dp, 8.dp) else RoundedCornerShape(10.dp, 10.dp, 2.dp, 10.dp)
    // In the margin: pops in from its point, and grows a little while its note is open (160ms, as the web's).
    val grown by animateFloatAsState(if (open) 1.12f else 1f, tween(160, easing = Ease.Arrive), label = "pin")
    Box(
        Modifier.heightIn(min = size).widthIn(min = size)
            .then(if (small) Modifier else Modifier.pop(160, TransformOrigin(1f, 1f)).graphicsLayer { scaleX = grown; scaleY = grown; transformOrigin = TransformOrigin(1f, 1f) })
            .then(if (small) Modifier else Modifier.border(2.dp, Color.White, shape))
            .clip(shape).background(color ?: C.accent)
            .then(if (onClick != null) Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick) else Modifier)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) { Text("$n", fontSize = if (small) 10.sp else 11.sp, fontWeight = FontWeight(650), color = Color.White, lineHeight = 16.sp) }
}

/** What to do with the picked passage, over it (frosted without a blur: it is part of what the foot blurs). */
@Composable
private fun PickBar(modifier: Modifier, everything: Boolean, onNote: () -> Unit, onCopy: () -> Unit, onAll: () -> Unit) {
    // PagePlaces by its middle (the offset is where its middle goes).
    Box(modifier.layoutCentred()) {
        Row(Modifier.pop().height(40.dp).floatingStill(RoundedCornerShape(20.dp)).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            BarButton("批注", Icons.Edit, onNote)
            BarButton("复制", Icons.Copy, onCopy)
            if (!everything) BarButton("全选", null, onAll)
        }
    }
}

/** Laid out with its middle where it is placed. */
private fun Modifier.layoutCentred() = this.layout { measurable, constraints ->
    val p = measurable.measure(constraints.copy(minWidth = 0, maxWidth = androidx.compose.ui.unit.Constraints.Infinity))
    layout(0, 0) { p.place(-p.width / 2, 0) }
}

@Composable
private fun BarButton(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector?, onClick: () -> Unit) {
    Row(
        Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (icon != null) IconIn(icon, 15.dp, C.ink)
        Text(label, fontSize = 14.sp, color = C.ink)
    }
}

/** The picked passage's two ends, each a handle a finger moves: a line down its side with a knob. */
@Composable
private fun Handles(words: PickedWords, rects: List<Rect>, picked: Span, setPicked: (Span) -> Unit, setDragging: (Boolean) -> Unit) {
    val density = LocalDensity.current
    val accent = C.accent
    val now by rememberUpdatedState(picked)
    val lines by rememberUpdatedState(rects.first() to rects.last())
    for (start in listOf(true, false)) {
        val line = if (start) rects.first() else rects.last()
        val x = if (start) line.left else line.right
        var box by remember { mutableStateOf<LayoutCoordinates?>(null) }
        with(density) {
            // The finger's room: 36dp round the knob; the knob over the start's line, under the end's.
            val room = 36.dp.toPx()
            val top = if (start) line.top - 28.dp.toPx() else line.top
            Box(
                Modifier.offset { IntOffset((x - room / 2).roundToInt(), top.roundToInt()) }.size(36.dp, (line.height + 28.dp.toPx()).toDp())
                    .onGloballyPositioned { box = it }
                    .pointerInput(start) {
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            down.consume()
                            val base = words.base ?: return@awaitEachGesture
                            val within = { c: androidx.compose.ui.input.pointer.PointerInputChange -> box?.let { base.localPositionOf(it, c.position) } }
                            val finger = within(down) ?: return@awaitEachGesture
                            // Where the finger is off the end's middle, kept, so that the end does not jump to under it.
                            val (first, last) = lines
                            val end = if (start) Offset(first.left, first.center.y) else Offset(last.right, last.center.y)
                            val grab = end - finger
                            var held = now
                            setDragging(true)
                            while (true) {
                                val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                                c.consume()
                                if (!c.pressed) break
                                val at = within(c)?.let { words.offsetAt(it + grab) } ?: continue
                                held = if (start) held.copy(start = minOf(at, held.end - 1)) else held.copy(end = maxOf(at, held.start + 1))
                                setPicked(held)
                            }
                            setDragging(false)
                        }
                    }
                    .drawBehind {
                        val mid = size.width / 2
                        val knob = 6.dp.toPx()
                        val w = 2.dp.toPx()
                        val lineTop = if (start) size.height - line.height else 0f
                        drawRect(accent, Offset(mid - w / 2, lineTop), Size(w, line.height))
                        drawCircle(accent, knob, Offset(mid, if (start) lineTop - knob + 1.dp.toPx() else lineTop + line.height + knob - 1.dp.toPx()))
                    },
            )
        }
    }
}

/** Saying something about a passage: a frosted composer floating under it, as the chat's is, the passage over what is written. */
@Composable
internal fun NoteBox(note: NoteLike, modifier: Modifier, onDone: () -> Unit, onRemove: () -> Unit) {
    val focus = remember { FocusRequester() }
    val into = remember { BringIntoViewRequester() }
    LaunchedEffect(Unit) { focus.requestFocus(); into.bringIntoView() }
    Column(
        modifier.fillMaxWidth().bringIntoViewRequester(into).pop().floatingStill(RoundedCornerShape(26.dp)).padding(start = 8.dp, end = 8.dp, top = 10.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Pin(note.n, small = true, color = note.color)
            Text(note.text, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Box(Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onRemove).semantics { contentDescription = "删掉这条批注" }, contentAlignment = Alignment.Center) { IconIn(Icons.Trash, 17.dp, C.muted) }
            Box(Modifier.weight(1f).heightIn(min = 36.dp).padding(horizontal = 8.dp, vertical = 7.dp), contentAlignment = Alignment.CenterStart) {
                if (note.comment.isEmpty()) Text("写批注（可以不写）", fontSize = 16.sp, lineHeight = 21.sp, color = C.subtle)
                BasicTextField(
                    note.comment, { note.comment = it }, Modifier.fillMaxWidth().focusRequester(focus),
                    textStyle = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, color = C.ink), cursorBrush = SolidColor(C.accent), maxLines = 8,
                )
            }
            Box(Modifier.size(36.dp).clip(CircleShape).background(C.ink).clickable(onClick = onDone).semantics { contentDescription = "写好了" }, contentAlignment = Alignment.Center) { IconIn(Icons.Check, 18.dp, C.bg) }
        }
    }
}

/** A note in the tray at the foot: its number and what is said, over the passage. */
@Composable
internal fun Card(note: NoteLike, open: Boolean, haze: HazeState, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier.width(160.dp).pop().floating(haze, shape).then(if (open) Modifier.border(1.5.dp, C.accent, shape) else Modifier)
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 9.dp),
    ) { CardContent(note, padded = false) }
}

/** What a note's card holds: its number and what is said, over the passage. */
@Composable
private fun CardContent(note: NoteLike, padded: Boolean = true) {
    Column(if (padded) Modifier.padding(horizontal = 12.dp, vertical = 9.dp) else Modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Pin(note.n, small = true, color = note.color)
            val said = note.comment.trim()
            Text(said.ifEmpty { "只引用" }, fontSize = 14.sp, lineHeight = 20.sp, color = if (said.isEmpty()) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(note.text, fontSize = 12.sp, lineHeight = 17.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Coming in as the web's pop does (keyframes.css.ts popKeyframes over --m-ease): from nothing and 97% of its size to
 * itself, `ms` long, from `origin` (its middle by default).
 */
@Composable
private fun Modifier.pop(ms: Int = 140, origin: TransformOrigin = TransformOrigin.Center): Modifier {
    val p = remember { Animatable(0f) }
    LaunchedEffect(Unit) { p.animateTo(1f, tween(ms, easing = Ease.Arrive)) }
    return graphicsLayer {
        alpha = p.value
        val s = 0.97f + 0.03f * p.value
        scaleX = s; scaleY = s
        transformOrigin = origin
    }
}

/** A message's words as read, without markdown's marks: what a quote of the whole of it carries. */
private fun plainWords(text: String) = text.replace(Regex("[`*#>]"), "").replace(Regex("\\s+"), " ").trim()
