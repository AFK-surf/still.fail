// Words a finger picks passages of (the annotate page, screens/Annotate.kt; web mobile/Annotate.tsx): each text in
// them (a paragraph of Markdown, a person's words) says where it is and what it holds; the page takes them, in the
// order they read, as one text, and each draws over itself what is picked and what has a note.
package fail.still.android.ui

import android.icu.text.BreakIterator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp

/** A passage: from `start` up to `end` (offsets in the words as one text). */
data class Span(val start: Int, val end: Int)

/** How the words draw a passage: picked (a ground), noted (a line under it), or the note open (a stronger line). */
enum class Drawn { Picked, Noted, Open }

/** The words of one message being picked from: the texts in them, and what to draw over them. */
@Stable
class PickedWords {
    /** A text in the words: what it holds and, once laid out, where. */
    class Piece(val text: String) {
        var layout: TextLayoutResult? = null
        var coords: LayoutCoordinates? = null
        /** Where it was last seen in the words' place (a scroll moves both: not a change). */
        internal var at: Offset? = null
    }

    internal val pieces = mutableStateListOf<Piece>()
    /** Where the words are laid out: the place everything is measured in. */
    var base: LayoutCoordinates? = null
    /** What is drawn over the words now. */
    var drawn by mutableStateOf<List<Pair<Span, Drawn>>>(emptyList())
    /** Bumped when a text is laid out again (what is placed over the words follows). */
    var laidOut by mutableStateOf(0)

    private fun placed() = pieces.filter { it.layout != null && it.coords?.isAttached == true && base?.isAttached == true }

    /** The texts laid out, in the order they read (top to bottom, then left to right), each with where it starts. */
    fun order(): List<Pair<Piece, Int>> {
        val b = base ?: return emptyList()
        var at = 0
        return placed().sortedWith(compareBy({ b.localPositionOf(it.coords!!, Offset.Zero).y }, { b.localPositionOf(it.coords!!, Offset.Zero).x }))
            .map { p -> (p to at).also { at += p.text.length + 1 } }
    }

    /** All of it as one text (its texts one to a line). */
    fun text(): String = order().joinToString("\n") { it.first.text }

    /** The text of a passage. */
    fun textOf(span: Span): String = text().let { it.substring(span.start.coerceIn(0, it.length), span.end.coerceIn(0, it.length)) }

    /** The boxes of a passage's lines, in the words' place. */
    fun rects(span: Span): List<Rect> {
        val b = base ?: return emptyList()
        return order().flatMap { (p, start) ->
            val l = p.layout!!
            val s = (span.start - start).coerceIn(0, p.text.length)
            val e = (span.end - start).coerceIn(0, p.text.length)
            val at = b.localPositionOf(p.coords!!, Offset.Zero)
            lineRects(l, s, e).map { it.translate(at) }
        }
    }

    /** The offset in the words of a point in their place; past the first or last text, their start or end. */
    fun offsetAt(point: Offset): Int? {
        val b = base ?: return null
        val order = order()
        if (order.isEmpty()) return null
        // The text whose lines hold the point's height (the nearest across, beside a table's cell); else the next one down.
        val boxes = order.map { (p, start) -> Triple(p, start, b.localPositionOf(p.coords!!, Offset.Zero)) }
        val row = boxes.filter { (p, _, at) -> point.y >= at.y && point.y < at.y + p.layout!!.size.height }
        val hit = row.minByOrNull { (p, _, at) -> if (point.x < at.x) at.x - point.x else if (point.x > at.x + p.layout!!.size.width) point.x - at.x - p.layout!!.size.width else 0f }
        if (hit == null) {
            val below = boxes.firstOrNull { (_, _, at) -> point.y < at.y } ?: return text().length
            return below.second
        }
        val (p, start, at) = hit
        return start + p.layout!!.getOffsetForPosition(point - at).coerceIn(0, p.text.length)
    }

    /** The word at an offset (as a phone picks one: a word as it is; a space or a mark, only that character). */
    fun wordAt(at: Int): Span {
        val text = text()
        if (text.isEmpty()) return Span(0, 0)
        val i = at.coerceIn(0, text.length - 1)
        val words = BreakIterator.getWordInstance().apply { setText(text) }
        val end = words.following(i)
        val status = words.ruleStatus
        val start = words.previous()
        val wordLike = status >= BreakIterator.WORD_NUMBER && text.substring(start, end).isNotBlank()
        return if (wordLike && end != BreakIterator.DONE && start != BreakIterator.DONE) Span(start, end) else Span(i, i + 1)
    }
}

/** The words being picked from, for the texts inside (none: they are only read). */
val LocalPickedWords = compositionLocalOf<PickedWords?> { null }

/**
 * The hook for a text in words that may be picked from: a modifier to put on the text (it says where it is and draws
 * what is picked and noted over it) and what to give the text's onTextLayout. Nothing outside such words.
 */
@Composable
fun pickable(text: String): Pair<Modifier, (TextLayoutResult) -> Unit> {
    val words = LocalPickedWords.current ?: return Modifier to {}
    val piece = remember(text) { PickedWords.Piece(text) }
    DisposableEffect(words, piece) {
        words.pieces += piece
        onDispose { words.pieces -= piece }
    }
    val accent = C.accent
    val modifier = Modifier
        .onGloballyPositioned { c ->
            piece.coords = c
            val at = words.base?.takeIf { it.isAttached }?.localPositionOf(c, Offset.Zero)
            if (at != piece.at) { piece.at = at; words.laidOut++ }
        }
        .drawBehind {
            val l = piece.layout ?: return@drawBehind
            val start = words.order().firstOrNull { it.first === piece }?.second ?: return@drawBehind
            for ((span, how) in words.drawn) {
                val s = (span.start - start).coerceIn(0, text.length)
                val e = (span.end - start).coerceIn(0, text.length)
                for (r in lineRects(l, s, e)) when (how) {
                    Drawn.Picked -> drawRect(accent.copy(alpha = 0.26f), r.topLeft, r.size)
                    Drawn.Noted, Drawn.Open -> {
                        val thick = if (how == Drawn.Open) 2.dp.toPx() else 1.5.dp.toPx()
                        val color = if (how == Drawn.Open) accent else accent.copy(alpha = 0.7f)
                        // Under the words, as the web's text-underline-offset: 3px below their baseline.
                        val y = l.getLineBaseline(l.getLineForVerticalPosition(r.center.y)) + 3.dp.toPx()
                        drawRect(color, Offset(r.left, y), androidx.compose.ui.geometry.Size(r.width, thick))
                    }
                }
            }
        }
    return modifier to { l -> if (piece.layout?.size != l.size || piece.layout?.layoutInput?.text != l.layoutInput.text) words.laidOut++; piece.layout = l }
}

/** A range's boxes in a text, a line each (none when it is empty). */
fun lineRects(l: TextLayoutResult, start: Int, end: Int): List<Rect> {
    if (start >= end) return emptyList()
    val first = l.getLineForOffset(start)
    val last = l.getLineForOffset(end - 1)
    return (first..last).mapNotNull { line ->
        val s = maxOf(start, l.getLineStart(line))
        val e = minOf(end, l.getLineEnd(line))
        if (e <= s) return@mapNotNull null
        val box = l.getPathForRange(s, e).getBounds()
        if (box.width <= 0f) null else Rect(box.left, l.getLineTop(line), box.right, l.getLineBottom(line))
    }
}
