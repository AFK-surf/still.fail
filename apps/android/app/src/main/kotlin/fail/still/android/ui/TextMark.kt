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
import androidx.compose.ui.text.TextLayoutResult

/** What to mark and how strongly now (`level`, the ground's opacity); `found` once some text holds it. */
@Stable
class TextMark(passage: String, val color: Color) {
    val needle = passage.replace(Regex("\\s+"), " ").trim()
    var level by mutableFloatStateOf(0f)
    var found by mutableStateOf(false)
    /** Where the marked range was last laid out: its text's coordinates and the range's box in them. */
    var where: Pair<LayoutCoordinates, Rect>? = null
}

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

/**
 * The hook for a text that may hold the marked passage: a modifier to put last on the text (it draws behind the range)
 * and what to give the text's onTextLayout. Nothing when no mark is asked for or the text does not hold it.
 */
@Composable
fun passageMark(text: String): Pair<Modifier, (TextLayoutResult) -> Unit> {
    val mark = LocalTextMark.current ?: return Modifier to {}
    val range = remember(text, mark.needle) { findPassage(text, mark.needle) } ?: return Modifier to {}
    if (!mark.found) mark.found = true
    val layout = remember { arrayOfNulls<TextLayoutResult>(1) }
    val modifier = Modifier
        .onGloballyPositioned { c -> layout[0]?.let { l -> mark.where = c to l.getPathForRange(range.first, range.last + 1).getBounds() } }
        .drawBehind {
            val l = layout[0] ?: return@drawBehind
            if (mark.level > 0f) drawPath(l.getPathForRange(range.first, range.last + 1), mark.color.copy(alpha = mark.level))
        }
    return modifier to { layout[0] = it }
}

/** The marked range's middle, in `pane`'s coordinates (null until laid out). */
fun TextMark.middleIn(pane: LayoutCoordinates): Offset? {
    val (c, box) = where?.takeIf { it.first.isAttached } ?: return null
    return pane.localPositionOf(c, box.center)
}
