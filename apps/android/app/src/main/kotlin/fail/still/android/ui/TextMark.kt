// A passage marked in a message's words, as the web marks where a quote leads (Chat.tsx → findText, flashRange; the
// ::highlight(quote-flash) in styles/global.css.ts): whatever text shows it (a paragraph of Markdown, a person's words,
// your bubble) finds it in its own words, whitespace taken as one space, and draws a ground behind just that range.
package fail.still.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * What to mark and how strongly now (`level`, the ground's opacity); `found` once some text holds it. With `words` (a
 * search's), each is bold with a hand-drawn stroke under it instead (web [data-search-marks]), drawn in as `drawn` goes
 * in ms (each stroke [STROKE_MS] long, the next [STROKE_GAP_MS] after it, as the web's).
 */
@Stable
class TextMark(passage: String, val color: Color, val words: List<String> = emptyList()) {
    val needle = passage.replace(Regex("\\s+"), " ").trim()
    var level by mutableFloatStateOf(0f)
    var drawn by mutableFloatStateOf(0f)
    var found by mutableStateOf(false)
    /** Where the marked range was last laid out: its text's coordinates and the range's box in them. */
    var where: Pair<LayoutCoordinates, Rect>? = null
}

/** A search's stroke: how long one takes to draw in, and how long after one the next starts (web global.css.ts). */
const val STROKE_MS = 520f
const val STROKE_GAP_MS = 180f

/** The mark for the words inside (a message a quote led to), if any. */
val LocalTextMark = compositionLocalOf<TextMark?> { null }

/** Where `needle` (whitespace as one space) is in `text`: its first and last character, or null. */
fun findPassage(text: String, needle: String): IntRange? {
    if (needle.isEmpty()) return null
    val flat = StringBuilder()
    val back = ArrayList<Int>()
    for (i in text.indices) {
        val c = if (text[i].isWhitespace()) ' ' else text[i]
        if (c == ' ' && flat.endsWith(" ")) continue
        flat.append(c); back += i
    }
    val at = flat.indexOf(needle)
    return if (at < 0) null else back[at]..back[at + needle.length - 1]
}

/** Where each of `words` (case aside) is in `text`, in order (a search's words, marked where it led). */
fun findWords(text: String, words: List<String>): List<IntRange> {
    val lower = text.lowercase()
    if (lower.length != text.length) return emptyList()
    val out = ArrayList<IntRange>()
    for (w in words.map { it.lowercase() }.filter { it.isNotEmpty() }) {
        var at = lower.indexOf(w)
        while (at >= 0) { out += at until at + w.length; at = lower.indexOf(w, at + w.length) }
    }
    return out.sortedBy { it.first }
}

/**
 * The hook for a text that may hold the marked passage: a modifier to put last on the text (it draws behind the range)
 * and what to give the text's onTextLayout. Nothing when no mark is asked for or the text does not hold it.
 */
@Composable
fun passageMark(text: String): Pair<Modifier, (TextLayoutResult) -> Unit> {
    val mark = LocalTextMark.current ?: return Modifier to {}
    val ranges = remember(text, mark.needle, mark.words) { if (mark.words.isNotEmpty()) findWords(text, mark.words) else listOfNotNull(findPassage(text, mark.needle)) }
    if (ranges.isEmpty()) return Modifier to {}
    if (!mark.found) mark.found = true
    val first = ranges.first()
    val layout = remember { arrayOfNulls<TextLayoutResult>(1) }
    val modifier = Modifier
        .onGloballyPositioned { c -> layout[0]?.let { l -> if (mark.where?.first?.isAttached != true || mark.where?.first == c) mark.where = c to l.getPathForRange(first.first, first.last + 1).getBounds() } }
        .drawBehind {
            val l = layout[0] ?: return@drawBehind
            if (mark.words.isNotEmpty()) {
                // Each word's stroke under it, a line at a time (one that wraps has two), drawn in as `drawn` reaches it.
                val width = 2.5.dp.toPx()
                var i = 0
                for (r in ranges) {
                    if (r.last >= l.layoutInput.text.length) continue
                    for (line in l.getLineForOffset(r.first)..l.getLineForOffset(r.last)) {
                        val from = maxOf(r.first, l.getLineStart(line))
                        val to = minOf(r.last + 1, l.getLineEnd(line, visibleEnd = true))
                        if (to <= from) continue
                        val left = l.getHorizontalPosition(from, true) - 2.dp.toPx()
                        val right = l.getHorizontalPosition(to, true) + 2.dp.toPx()
                        val y = l.getLineBaseline(line) + 4.dp.toPx()
                        val p = Ease.Standard.transform(((mark.drawn - i * STROKE_GAP_MS) / STROKE_MS).coerceIn(0f, 1f))
                        i++
                        if (p <= 0f) continue
                        val w = right - left
                        val stroke = Path().apply {
                            moveTo(left, y)
                            cubicTo(left + w * 0.25f, y - 3.dp.toPx(), left + w * 0.55f, y + 2.dp.toPx(), right, y - 2.dp.toPx())
                        }
                        val part = Path()
                        PathMeasure().apply { setPath(stroke, false); getSegment(0f, length * p, part, true) }
                        drawPath(part, mark.color, style = Stroke(width, cap = StrokeCap.Round))
                    }
                }
            } else if (mark.level > 0f) for (r in ranges) if (r.last < l.layoutInput.text.length) drawPath(l.getPathForRange(r.first, r.last + 1), mark.color.copy(alpha = mark.level))
        }
    return modifier to { layout[0] = it }
}

/** `text` with a search's words (the mark's, if any) in bold, as they are marked (web ::highlight(search-hit)). */
@Composable
fun markWeight(text: AnnotatedString): AnnotatedString {
    val mark = LocalTextMark.current ?: return text
    if (mark.words.isEmpty()) return text
    val ranges = remember(text.text, mark.words) { findWords(text.text, mark.words) }
    if (ranges.isEmpty()) return text
    return remember(text, ranges) {
        AnnotatedString.Builder(text).apply { for (r in ranges) addStyle(SpanStyle(fontWeight = FontWeight.SemiBold), r.first, r.last + 1) }.toAnnotatedString()
    }
}

/** The marked range's middle, in `pane`'s coordinates (null until laid out). */
fun TextMark.middleIn(pane: LayoutCoordinates): Offset? {
    val (c, box) = where?.takeIf { it.first.isAttached } ?: return null
    return pane.localPositionOf(c, box.center)
}
