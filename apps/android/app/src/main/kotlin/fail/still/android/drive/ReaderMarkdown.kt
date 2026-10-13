package fail.still.android.drive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.sp

/** The colours a Markdown page needs on top of the body text. */
internal data class MarkdownColors(
    val muted: Color,
    val accent: Color,
    val code: Color,
)

/**
 * One chunk of Markdown, drawn.
 *
 * [rawIndexOf] is what makes search and "jump to here" work in a file whose
 * syntax is not shown: character *n* of [styled] came from character
 * `rawIndexOf[n]` of the file, so a hit found in the raw text can be highlighted
 * where it ended up on screen.
 */
internal class MarkdownChunk(
    val styled: AnnotatedString,
    private val rawIndexOf: IntArray,
    /** Space to leave above this block, which is how headings get their air. */
    val leadingDp: Int,
) {
    val length: Int get() = styled.length

    /** Where a raw offset lands in what is drawn. */
    fun renderedIndex(raw: Int): Int {
        if (rawIndexOf.isEmpty()) return 0
        if (raw >= rawIndexOf[rawIndexOf.size - 1]) return rawIndexOf.size
        var low = 0
        var high = rawIndexOf.size - 1
        while (low < high) {
            val mid = (low + high) / 2
            if (rawIndexOf[mid] < raw) low = mid + 1 else high = mid
        }
        return low
    }
}

private val BULLET = "\u2022 "
private val QUOTE_BAR = "\u258E "
private val RULE = "\u2500"

/**
 * Draws one block of Markdown.
 *
 * Deliberately small: headings, quotes, lists, rules, fenced code, and the
 * inline forms that turn up in prose — bold, italic, strikethrough, code and
 * links. Tables, images and nested lists are not rendered; a novel is prose, and
 * a parser that tries to be a browser is one that breaks on a stray asterisk.
 */
internal fun renderMarkdown(chunk: String, bodySp: Float, colors: MarkdownColors): MarkdownChunk {
    val out = AnnotatedString.Builder()
    val map = ArrayList<Int>(chunk.length)
    val muted = SpanStyle(color = colors.muted)
    val code = SpanStyle(fontFamily = FontFamily.Monospace, color = colors.code)

    /**
     * Appends what will be drawn for a raw span, keeping the map one entry per
     * drawn character.
     *
     * The two lengths differ wherever a marker becomes a glyph — `- ` becomes
     * `• `, `> ` becomes `▎ `, `---` becomes a rule — and the map has to stay
     * exactly as long as the text or every later offset is wrong. That is what
     * put search highlights on the wrong words.
     */
    fun put(text: String, rawFrom: Int, rawTo: Int, style: SpanStyle?) {
        if (text.isEmpty()) return
        val start = out.length
        out.append(text)
        if (style != null) out.addStyle(style, start, out.length)
        val span = (rawTo - rawFrom).coerceAtLeast(1)
        for (i in text.indices) map.add(rawFrom + (i * span) / text.length)
    }

    fun putOne(rawIndex: Int, style: SpanStyle?, text: Char = chunk[rawIndex]) {
        val start = out.length
        out.append(text.toString())
        if (style != null) out.addStyle(style, start, out.length)
        map.add(rawIndex)
    }

    /** The inline forms, longest marker first so `**` is not read as two `*`. */
    fun inline(base: Int, text: String, style: SpanStyle?) {
        var i = 0
        while (i < text.length) {
            val at = base + i
            when {
                text[i] == '\\' && i + 1 < text.length -> {
                    putOne(at + 1, style)
                    i += 2
                }

                text.startsWith("**", i) || text.startsWith("__", i) -> {
                    val marker = text.substring(i, i + 2)
                    val close = text.indexOf(marker, i + 2)
                    if (close > i + 2) {
                        inline(base + i + 2, text.substring(i + 2, close), bold(style))
                        i = close + 2
                    } else {
                        putOne(at, style); i++
                    }
                }

                text.startsWith("~~", i) -> {
                    val close = text.indexOf("~~", i + 2)
                    if (close > i + 2) {
                        inline(
                            base + i + 2,
                            text.substring(i + 2, close),
                            (style ?: SpanStyle()).copy(textDecoration = TextDecoration.LineThrough),
                        )
                        i = close + 2
                    } else {
                        putOne(at, style); i++
                    }
                }

                text[i] == '`' -> {
                    val close = text.indexOf('`', i + 1)
                    if (close > i) {
                        inline(base + i + 1, text.substring(i + 1, close), merge(style, code))
                        i = close + 1
                    } else {
                        putOne(at, style); i++
                    }
                }

                text[i] == '*' || text[i] == '_' -> {
                    val marker = text[i].toString()
                    val close = text.indexOf(marker, i + 1)
                    if (close > i + 1) {
                        inline(
                            base + i + 1,
                            text.substring(i + 1, close),
                            merge(style, SpanStyle(fontStyle = FontStyle.Italic)),
                        )
                        i = close + 1
                    } else {
                        putOne(at, style); i++
                    }
                }

                text[i] == '[' -> {
                    val mid = text.indexOf("](", i)
                    val close = if (mid < 0) -1 else text.indexOf(')', mid + 2)
                    if (mid > i && close > mid) {
                        // The label is what a reader needs; the address is not
                        // something a phone reader can follow usefully here.
                        inline(
                            base + i + 1,
                            text.substring(i + 1, mid),
                            merge(style, SpanStyle(color = colors.accent, textDecoration = TextDecoration.Underline)),
                        )
                        i = close + 1
                    } else {
                        putOne(at, style); i++
                    }
                }

                else -> {
                    putOne(at, style); i++
                }
            }
        }
    }

    val lines = chunk.split('\n')
    var at = 0
    var fenced = false
    var leading: Int? = null

    for ((number, line) in lines.withIndex()) {
        val lineStart = at
        at += line.length + 1

        val fence = line.trimStart().startsWith("```") || line.trimStart().startsWith("~~~")
        if (fence) {
            fenced = !fenced
            if (leading == null) leading = 4
            if (number < lines.size - 1) putOne(lineStart + line.length, null, '\n')
            continue
        }
        if (fenced) {
            put(line, lineStart, lineStart + line.length, code)
            if (number < lines.size - 1) putOne(lineStart + line.length, null, '\n')
            continue
        }

        val heading = HEADING.matchEntire(line)
        val rule = RULE_LINE.matches(line.trim())
        val quote = QUOTE.matchEntire(line)
        val bullet = BULLET_ITEM.matchEntire(line)
        val ordered = ORDERED_ITEM.matchEntire(line)

        when {
            heading != null -> {
                val level = heading.groupValues[1].length
                val scale = when (level) {
                    1 -> 1.55f
                    2 -> 1.34f
                    3 -> 1.18f
                    else -> 1.08f
                }
                if (leading == null) leading = if (level <= 2) 16 else 8
                val text = heading.groupValues[2].trim()
                val start = out.length
                inline(lineStart + line.indexOf(text).coerceAtLeast(0), text, SpanStyle(fontWeight = FontWeight.SemiBold))
                out.addStyle(SpanStyle(fontSize = (bodySp * scale).sp, fontWeight = FontWeight.SemiBold), start, out.length)
            }

            rule -> {
                if (leading == null) leading = 14
                val start = out.length
                put(RULE.repeat(18), lineStart, lineStart + line.length, muted)
                out.addStyle(muted, start, out.length)
            }

            quote != null -> {
                if (leading == null) leading = 6
                put(QUOTE_BAR, lineStart, lineStart + 1, SpanStyle(color = colors.accent))
                val text = quote.groupValues[1]
                inline(lineStart + line.indexOf(text).coerceAtLeast(0), text, muted)
            }

            bullet != null -> {
                if (leading == null) leading = 2
                put(BULLET, lineStart, lineStart + bullet.groupValues[1].length, muted)
                val text = bullet.groupValues[2]
                inline(lineStart + line.indexOf(text).coerceAtLeast(0), text, null)
            }

            ordered != null -> {
                if (leading == null) leading = 2
                val marker = ordered.groupValues[1]
                put("$marker ", lineStart, lineStart + marker.length, muted)
                val text = ordered.groupValues[3]
                inline(lineStart + line.indexOf(text).coerceAtLeast(0), text, null)
            }

            line.isBlank() -> {
                if (number < lines.size - 1) putOne(lineStart, null, '\n')
            }

            else -> {
                inline(lineStart, line, null)
            }
        }

        if (number < lines.size - 1 && !line.isBlank() && !fence) {
            putOne(lineStart + line.length, null, '\n')
        }
    }

    return MarkdownChunk(out.toAnnotatedString(), map.toIntArray(), leading ?: 0)
}

private val HEADING = Regex("""^(#{1,6})\s+(.*?)\s*#*\s*$""")
private val RULE_LINE = Regex("""^(-{3,}|\*{3,}|_{3,})$""")
private val QUOTE = Regex("""^>\s?(.*)$""")
private val BULLET_ITEM = Regex("""^\s*([-*+])\s+(.*)$""")
private val ORDERED_ITEM = Regex("""^\s*(\d{1,3}([.)]))\s+(.*)$""")

private fun bold(style: SpanStyle?): SpanStyle =
    (style ?: SpanStyle()).copy(fontWeight = FontWeight.SemiBold)

private fun merge(style: SpanStyle?, extra: SpanStyle): SpanStyle = (style ?: SpanStyle()).merge(extra)

/**
 * Heading lines as a table of contents.
 *
 * Markdown says where its sections begin, so this does not have to guess the
 * way the plain-text hunt does: `#` to `###` is a chapter, deeper is a subtitle
 * and is left out of the list.
 */
internal fun markdownChapters(text: String, maxLevel: Int = 3, limit: Int = 2000): List<ChapterMark> {
    val marks = ArrayList<ChapterMark>()
    var at = 0
    var fenced = false
    for (line in text.split('\n')) {
        val start = at
        at += line.length + 1
        if (line.trimStart().startsWith("```") || line.trimStart().startsWith("~~~")) {
            fenced = !fenced
            continue
        }
        if (fenced) continue
        val heading = HEADING.matchEntire(line) ?: continue
        if (heading.groupValues[1].length > maxLevel) continue
        val title = heading.groupValues[2].trim()
        if (title.isEmpty()) continue
        marks.add(ChapterMark(title, start))
        if (marks.size >= limit) break
    }
    return marks
}
