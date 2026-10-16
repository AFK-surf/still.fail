// Picking a passage of a message where it is, in its chat (web mobile/pick.tsx): a finger held still on its words picks
// the word under it and, sliding on, widens it by words (the list holds still meanwhile); lifted, the passage has
// handles at its ends to move, and a bar over it to quote it into the chat's draft, copy it, or take all of the message.
// A tap anywhere else lets go of it, as going back does.
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.Drawn
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LocalUi
import fail.still.android.ui.PickedWords
import fail.still.android.ui.Span
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.roundToInt

/** What is picked in a list of messages: one passage of one message at a time; quoted into `draft` (none: only copied). */
@Stable
class MessagePick(private val draft: Draft?) {
    /** The message picked from. */
    var ts by mutableStateOf<String?>(null)
        private set
    /** Its words. */
    var words by mutableStateOf<PickedWords?>(null)
        private set
    var picked by mutableStateOf<Span?>(null)
        private set
    /** A finger is widening it or moving one of its ends (its bar goes meanwhile). */
    var dragging by mutableStateOf(false)
    /** Who said it, as a quote names them, and as what ("agent" or "person"). */
    private var author = ""
    private var role = "person"

    val quotes get() = draft != null

    fun start(ts: String, words: PickedWords, author: String, role: String, span: Span) {
        if (this.words !== words) this.words?.drawn = emptyList()
        this.ts = ts
        this.words = words
        this.author = author
        this.role = role
        set(span)
    }

    fun set(span: Span) {
        picked = span
        words?.drawn = listOf(span to Drawn.Picked)
    }

    fun clear() {
        words?.drawn = emptyList()
        ts = null
        words = null
        picked = null
        dragging = false
    }

    /** Into the draft as a quote, its comment line taking the focus (Composer.kt); then let go. */
    fun quote() {
        val text = picked?.let { words?.textOf(it)?.trim() }
        if (!text.isNullOrEmpty()) draft?.quote(author, text, ts, role)
        clear()
    }
}

/** The list's picking, for the messages in it (none: their words are only read). */
val LocalMessagePick = staticCompositionLocalOf<MessagePick?> { null }

/**
 * The hook for one message's words where passages are picked in place (LocalMessagePick): a modifier for what holds
 * them (a finger held still there picks), and the words to give the texts inside (LocalPickedWords). Nothing for a
 * message without words; a hold on a link in them is the link's menu (ui/Links.kt).
 */
@Composable
internal fun messagePick(ts: String, author: String, role: String, text: String): Pair<Modifier, PickedWords?> {
    val pick = LocalMessagePick.current
    if (pick == null || text.isBlank()) return Modifier to null
    val words = remember(ts) { PickedWords() }
    val ui = LocalUi.current
    val haptics = LocalHapticFeedback.current
    val said by rememberUpdatedState(author to role)
    // Out of the list (scrolled far off, gone): what was picked in it goes too.
    DisposableEffect(words) { onDispose { if (pick.words === words) pick.clear() } }
    val modifier = Modifier.onGloballyPositioned { words.base = it }.pointerInput(words) {
        awaitEachGesture {
            val down = awaitFirstDown()
            val from = down.position
            // Lifted, moved (the list scrolls) or taken by something in it before a long press's time: not a hold.
            val lifted = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                while (true) {
                    val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                    if (c == null || !c.pressed || c.isConsumed || (c.position - from).getDistance() > viewConfiguration.touchSlop) break
                }
            }
            if (lifted != null || ui.menu != null) return@awaitEachGesture
            val anchor = words.offsetAt(from)?.let { words.wordAt(it) } ?: return@awaitEachGesture
            pick.start(ts, words, said.first, said.second, anchor)
            pick.dragging = true
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            while (true) {
                val c = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                c.consume()
                if (!c.pressed) break
                val w = words.offsetAt(c.position)?.let { words.wordAt(it) } ?: continue
                pick.set(if (w.start >= anchor.start) Span(anchor.start, maxOf(anchor.end, w.end)) else Span(w.start, anchor.end))
            }
            pick.dragging = false
        }
    }
    return modifier to words
}

/** A tap nothing under it took, anywhere in it: what is picked is let go of. */
internal fun Modifier.letsGoOfPick(pick: MessagePick) = pointerInput(pick) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Final)
        if (pick.picked == null) return@awaitEachGesture
        var tap = !down.isConsumed
        while (tap) {
            val c = awaitPointerEvent(PointerEventPass.Final).changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
            if (c.isConsumed || (c.position - down.position).getDistance() > viewConfiguration.touchSlop) tap = false
            else if (!c.pressed) break
        }
        if (tap) pick.clear()
    }
}

/**
 * Over the list: the picked passage's handles and its bar (over it; under it when the bar over the list is too near),
 * the bar gone while the list moves or the passage is being changed. `follow` reads where the list is scrolled to (this
 * follows it); `top` and `bottom` are what the bar and the composer cover of it.
 */
@Composable
internal fun PickLayer(pick: MessagePick, follow: () -> Unit, moving: Boolean, top: Dp, bottom: Dp, modifier: Modifier = Modifier) {
    BackHandler(enabled = pick.picked != null) { pick.clear() }
    val words = pick.words
    val picked = pick.picked
    if (words == null || picked == null) return
    val app = LocalApp.current
    val context = LocalContext.current
    val density = LocalDensity.current
    var layer by remember { mutableStateOf<LayoutCoordinates?>(null) }
    Box(modifier.onGloballyPositioned { layer = it }) {
        follow()
        @Suppress("UNUSED_EXPRESSION") words.laidOut
        val at = layer?.takeIf { it.isAttached } ?: return@Box
        val base = words.base?.takeIf { it.isAttached } ?: return@Box
        // The words' place to this one's.
        val shift = at.localPositionOf(base, Offset.Zero)
        val lines = words.rects(picked)
        if (lines.isEmpty()) return@Box
        Handles(words, lines, shift, picked, { pick.set(it) }, { pick.dragging = it })
        if (pick.dragging || moving) return@Box
        with(density) {
            val first = lines.first().translate(shift)
            val last = lines.last().translate(shift)
            val width = at.size.width.toFloat()
            // Over the passage; under it (clear of the end's knob) when the bar over the list is too near; on the screen
            // when the passage runs past it.
            val over = first.top - 52.dp.toPx()
            val y = (if (over < top.toPx() + 8.dp.toPx()) last.bottom + 28.dp.toPx() else over)
                .coerceIn(top.toPx() + 8.dp.toPx(), (at.size.height - bottom.toPx() - 48.dp.toPx()).coerceAtLeast(top.toPx() + 8.dp.toPx()))
            val x = (if (lines.size > 1) width / 2 else first.center.x).coerceIn(130.dp.toPx(), (width - 130.dp.toPx()).coerceAtLeast(130.dp.toPx()))
            val everything = picked.start == 0 && picked.end >= words.text().length
            PickBar(
                Modifier.offset { IntOffset(x.roundToInt(), y.roundToInt()) }, quotes = pick.quotes, everything = everything,
                onQuote = { pick.quote() },
                onCopy = {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", words.textOf(picked)))
                    app.toast = t("android-chat.annotate.copied")
                    pick.clear()
                },
                onAll = { pick.set(Span(0, words.text().length)) },
            )
        }
    }
}

/**
 * What to do with the picked passage, over it: on the ground every panel that pops up stands on (web styles/glass.ts
 * panel: opaque, a line round it; glass over the messages would let their words read through).
 */
@Composable
private fun PickBar(modifier: Modifier, quotes: Boolean, everything: Boolean, onQuote: () -> Unit, onCopy: () -> Unit, onAll: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    // Placed by its middle (the offset is where its middle goes).
    Box(modifier.layoutCentred()) {
        Row(
            Modifier.pop().height(40.dp).shadow(8.dp, shape).clip(shape).background(C.surface).border(1.dp, C.line, shape)
                // A touch between its buttons stays on it (not a tap on the list, which lets go of the passage).
                .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } }
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (quotes) BarButton(t("android-chat.pick.quote"), Icons.Quote, onQuote)
            BarButton(t("common.copy"), Icons.Copy, onCopy)
            if (!everything) BarButton(t("android-chat.annotate.selectAll"), null, onAll)
        }
    }
}

/** Laid out with its middle where it is placed. */
private fun Modifier.layoutCentred() = this.layout { measurable, constraints ->
    val p = measurable.measure(constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity))
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

/**
 * The picked passage's two ends, each a handle a finger moves: a line down its side with a knob. `lines` are the
 * passage's in the words' place, `shift` takes them to where the handles are placed.
 */
@Composable
private fun Handles(words: PickedWords, lines: List<Rect>, shift: Offset, picked: Span, setPicked: (Span) -> Unit, setDragging: (Boolean) -> Unit) {
    val density = LocalDensity.current
    val accent = C.accent
    val now by rememberUpdatedState(picked)
    val ends by rememberUpdatedState(lines.first() to lines.last())
    for (start in listOf(true, false)) {
        val line = if (start) lines.first() else lines.last()
        val x = (if (start) line.left else line.right) + shift.x
        var box by remember { mutableStateOf<LayoutCoordinates?>(null) }
        with(density) {
            // The finger's room: 36dp round the knob; the knob over the start's line, under the end's.
            val room = 36.dp.toPx()
            val top = (if (start) line.top - 28.dp.toPx() else line.top) + shift.y
            Box(
                Modifier.offset { IntOffset((x - room / 2).roundToInt(), top.roundToInt()) }.size(36.dp, (line.height + 28.dp.toPx()).toDp())
                    .onGloballyPositioned { box = it }
                    .pointerInput(start) {
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            down.consume()
                            val base = words.base ?: return@awaitEachGesture
                            val within = { c: PointerInputChange -> box?.takeIf { it.isAttached && base.isAttached }?.let { base.localPositionOf(it, c.position) } }
                            val finger = within(down) ?: return@awaitEachGesture
                            // Where the finger is off the end's middle, kept, so that the end does not jump to under it.
                            val (first, last) = ends
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
