package fail.still.android.drive

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/**
 * The text side of the reader: decoding, line reflow, chunking, chapter
 * markers, search and the offset arithmetic the rendered blocks are drawn
 * with.
 *
 * Everything here is plain Kotlin over a String — no Android, no Compose — so
 * the part of the reader that decides *what* is shown can be checked on the JVM
 * without a device. The screen only decides how it looks.
 */

/** A decoded file, with the encoding that produced it. */
data class DecodedText(val text: String, val encoding: String)

/** A chapter heading, as an offset into the text the reader renders. */
data class ChapterMark(val title: String, val offset: Int)

/** A heading the table of contents can jump to. [offset] is inside [chunk]. */
data class NovelChapter(val title: String, val chunk: Int, val offset: Int)

/** A substring of the text the reader renders, tagged with the chunk it belongs to. */
data class TextMatch(val chunk: Int, val start: Int, val length: Int)

/** The text cut into blocks small enough to lay out one at a time. */
data class ChunkedText(val chunks: List<String>, val starts: IntArray)

/**
 * How much text one block holds.
 *
 * A block has to be small enough that laying it out is cheap and big enough
 * that the list does not hold thousands of blocks; ~1k characters is 2–3 phone
 * pages, which also keeps "where I left off" honest to within a page or two.
 */
const val CHUNK_CHARS = 1000

/** Two ideographic spaces, which is what a Chinese paragraph is indented by. */
const val INDENT = "\u3000\u3000"

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/**
 * Decodes raw file bytes.
 *
 * Strict UTF-8 is tried before GB18030, and in that order on purpose: a GB18030
 * novel is very often valid UTF-8 for hundreds of bytes before the first bad
 * sequence, so asking GB18030 first would mojibake every file that really is
 * UTF-8, while strict UTF-8 can only fail a file that really is GB18030. The
 * fallback decodes leniently, so no byte sequence can throw — a novel with a
 * corrupt page still opens, with replacement characters where the damage is.
 *
 * [truncated] means these bytes are the front of a larger file. A multi-byte
 * character cut in half at the end is then dropped rather than treated as
 * evidence that the whole file is not UTF-8.
 */
fun decodeText(
    bytes: ByteArray,
    offset: Int = 0,
    length: Int = bytes.size,
    truncated: Boolean = false,
): DecodedText {
    if (length <= 0 || offset >= bytes.size) return DecodedText("", "UTF-8")
    val end = minOf(offset + length, bytes.size)
    val bom = sniffBom(bytes, offset, end - offset)
    if (bom != null) {
        val from = offset + bom.bytes
        // A byte order mark settles the encoding; there is nothing to guess.
        val text = decodeBlocks(bytes, from, end, bom.charset, strict = true, dropTail = truncated)
            ?: decodeBlocks(bytes, from, end, bom.charset, strict = false, dropTail = truncated)
            ?: ""
        return DecodedText(text, bom.label)
    }
    val strict = decodeBlocks(bytes, offset, end, Charsets.UTF_8, strict = true, dropTail = truncated)
    if (strict != null) return DecodedText(strict, "UTF-8")
    if (!truncated) {
        // A file whose own last character is incomplete — a half-copied
        // download — is still UTF-8, and must not be re-read as GB18030.
        val cutTail = decodeBlocks(bytes, offset, end, Charsets.UTF_8, strict = true, dropTail = true)
        if (cutTail != null) return DecodedText(cutTail, "UTF-8")
    }
    // Not UTF-8. GB18030 is a superset of GBK and the usual answer for older
    // Chinese text; ISO-8859-1 is the floor that cannot fail.
    val gb = runCatching { Charset.forName("GB18030") }.getOrNull()
        ?: return DecodedText(String(bytes, offset, end - offset, Charsets.ISO_8859_1), "ISO-8859-1")
    val text = decodeBlocks(bytes, offset, end, gb, strict = false, dropTail = truncated)
    return DecodedText(text ?: "", "GB18030")
}

private class Bom(val charset: Charset, val bytes: Int, val label: String)

private fun sniffBom(bytes: ByteArray, offset: Int, length: Int): Bom? = when {
    length >= 3 && bytes[offset] == 0xEF.toByte() &&
        bytes[offset + 1] == 0xBB.toByte() && bytes[offset + 2] == 0xBF.toByte() ->
        Bom(Charsets.UTF_8, 3, "UTF-8 BOM")
    length >= 2 && bytes[offset] == 0xFF.toByte() && bytes[offset + 1] == 0xFE.toByte() ->
        Bom(Charsets.UTF_16LE, 2, "UTF-16LE")
    length >= 2 && bytes[offset] == 0xFE.toByte() && bytes[offset + 1] == 0xFF.toByte() ->
        Bom(Charsets.UTF_16BE, 2, "UTF-16BE")
    else -> null
}

/**
 * Decodes through one streaming decoder, drained into a StringBuilder.
 *
 * The output is collected in fixed windows so a 16 MiB file never needs a
 * second 16 MiB buffer, and the input is wrapped rather than copied. Returns
 * null only when [strict] decoding hits a byte it cannot map.
 */
private fun decodeBlocks(
    bytes: ByteArray,
    from: Int,
    to: Int,
    charset: Charset,
    strict: Boolean,
    dropTail: Boolean,
): String? {
    if (from >= to) return ""
    val decoder = charset.newDecoder()
    if (strict) {
        decoder.onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
    } else {
        decoder.onMalformedInput(CodingErrorAction.REPLACE).onUnmappableCharacter(CodingErrorAction.REPLACE)
    }
    val input = ByteBuffer.wrap(bytes, from, to - from)
    val text = StringBuilder(to - from + 16)
    val out = CharBuffer.allocate(64 * 1024)
    val complete = !dropTail
    while (true) {
        val result = decoder.decode(input, out, complete)
        if (result.isError) return null
        out.flip()
        text.append(out)
        out.clear()
        if (result.isUnderflow) break
    }
    // With a cut tail the decoder is deliberately left holding the incomplete
    // character, so flushing would only turn it into a replacement character.
    if (complete) {
        decoder.flush(out)
        out.flip()
        text.append(out)
    }
    return text.toString()
}

// ---------------------------------------------------------------------------
// Line reflow
// ---------------------------------------------------------------------------

/** Line endings normalised to `\n`; the same string when there is nothing to do. */
fun normaliseLineEndings(text: String): String {
    if (text.indexOf('\r') < 0) return text
    return text.replace("\r\n", "\n").replace('\r', '\n')
}

/**
 * The column a hard-wrapped file was broken at, or 0 when it was not.
 *
 * Downloaded Chinese novels are commonly wrapped at a fixed width (40
 * characters is typical) rather than one paragraph per line. Laid out on a
 * phone, every one of those source lines would become a short ragged line of
 * its own, and pages would end a third of the way down. Wrapping is recognised
 * by the signature it leaves: most non-empty lines sit right at the maximum
 * width. Paragraph-per-line files spread their line lengths out, so they do not
 * match, which matters because joining *their* lines would merge paragraphs.
 */
fun detectWrapWidth(text: String): Int {
    val sampleChars = 200_000
    val sampleLines = 2_000
    var widest = 0
    var lines = 0
    var index = 0
    while (index < text.length && index < sampleChars && lines < sampleLines) {
        val newline = text.indexOf('\n', index)
        val end = if (newline < 0) text.length else newline
        if (end > index) {
            lines++
            if (end - index > widest) widest = end - index
        }
        if (newline < 0) break
        index = newline + 1
    }
    if (lines < 12 || widest < 20 || widest > 160) return 0
    val band = widest * 4 / 5
    var seen = 0
    var full = 0
    var atMax = 0
    var terminal = 0
    index = 0
    while (index < text.length && index < sampleChars && seen < lines) {
        val newline = text.indexOf('\n', index)
        val end = if (newline < 0) text.length else newline
        val length = end - index
        if (length > 0) {
            seen++
            if (length >= band) full++
            if (length >= widest - 2) atMax++
            // A paragraph ends in punctuation; a wrapped line usually does not.
            if (end > index && endsSentence(text[end - 1])) terminal++
        }
        if (newline < 0) break
        index = newline + 1
    }
    // Deliberately tight, in both directions: a false positive joins real
    // paragraphs together, which reads far worse than a wrapped file left alone.
    return if (full * 5 >= seen * 2 && atMax >= 5 && terminal * 2 <= seen) widest else 0
}

/**
 * Joins the line breaks that the source put there, keeping the ones that mean
 * a paragraph.
 *
 * [keepLineStarts] are offsets of lines that must start a paragraph regardless
 * (chapter headings, which would otherwise be swallowed by the paragraph above
 * them). A join stops after [MAX_JOINED] characters, so a file that only looks
 * wrapped cannot be welded into one enormous line.
 */
fun reflow(text: String, wrapWidth: Int, keepLineStarts: Set<Int>): String {
    if (wrapWidth <= 0) return text
    val band = wrapWidth * 4 / 5
    val out = StringBuilder(text.length)
    var index = 0
    var previousFull = false
    var joined = 0
    while (index < text.length) {
        val newline = text.indexOf('\n', index)
        val end = if (newline < 0) text.length else newline
        val length = end - index
        val blank = length == 0
        val keep = keepLineStarts.contains(index)
        val continuation = !blank && !keep && previousFull && out.isNotEmpty() && joined < MAX_JOINED
        if (continuation) {
            // The break replaced a space in Latin text; Chinese needs no space.
            if (needsSpace(out, text, index)) out.append(' ')
        } else {
            if (out.isNotEmpty()) out.append('\n')
            joined = 0
        }
        out.append(text, index, end)
        joined += length
        previousFull = length >= band
        if (newline < 0) break
        index = newline + 1
    }
    return out.toString()
}

private const val MAX_JOINED = 4000

private fun needsSpace(out: StringBuilder, text: String, next: Int): Boolean {
    if (next >= text.length) return false
    val last = out[out.length - 1]
    if (last == ' ' || last == '\n' || last == '-') return false
    return !isCjk(last) && !isCjk(text[next])
}

/** Rough CJK test: the ranges a Chinese novel lives in, plus full-width punctuation. */
private fun isCjk(char: Char): Boolean = when (char.code) {
    in 0x2E80..0x303F -> true     // radicals, kangxi, CJK punctuation
    in 0x3040..0x30FF -> true     // kana
    in 0x3400..0x4DBF -> true     // extension A
    in 0x4E00..0x9FFF -> true     // unified ideographs
    in 0xF900..0xFAFF -> true     // compatibility ideographs
    in 0xFE30..0xFE4F -> true     // vertical forms
    in 0xFF00..0xFFEF -> true     // full-width forms
    else -> false
}

// ---------------------------------------------------------------------------
// Chapters
// ---------------------------------------------------------------------------

private const val NUMERALS = "0-9０-９零〇一二三四五六七八九十百千万两"

/** `第一章`, `第 12 节`, `第三卷`: the marker most Chinese novels actually use. */
private val CJK_HEADING = Regex(
    "^(?:正文[\\s:：·　]*)?第\\s*[$NUMERALS]{1,12}\\s*[章卷回节篇部集话](?:[\\s:：.、·　\\-—]?[^\\n]{0,36})?$",
)

/** The front and back matter of a novel, which is a heading with no number. */
private val FRONT_MATTER = Regex("^(?:序章|序言|楔子|引子|前言|序幕|尾声|终章|番外\\d{0,3}|后记|外传|附录).{0,36}$")

private val LATIN_HEADING = Regex("^(?:Chapter|CHAPTER|chapter)\\s{0,2}[0-9]{1,4}[^\\n]{0,30}$")

/**
 * Finds headings, best effort.
 *
 * Real files are unreliable about this: a 1.5 MB novel often carries only a
 * handful of `第…章` lines, or none at all, so this is a bonus index and never
 * the primary navigation. [weak] adds "short line that looks like a title",
 * which needs the paragraphs to be real ones — call it after [reflow] — and is
 * kept strict, because a heading list full of dialogue is worse than a short
 * one. A wrong entry only costs a bad row in the table of contents; nothing
 * here changes what the pages look like.
 */
fun findChapters(text: String, weak: Boolean = true, limit: Int = 2000): List<ChapterMark> {
    val found = ArrayList<ChapterMark>(64)
    var index = 0
    var previousBlank = true
    var previousSentence = true
    var lastAccepted = -WEAK_GAP
    while (index < text.length && found.size < limit) {
        val newline = text.indexOf('\n', index)
        val end = if (newline < 0) text.length else newline
        var begin = index
        var finish = end
        while (begin < finish && isBlank(text[begin])) begin++
        while (finish > begin && isBlank(text[finish - 1])) finish--
        val length = finish - begin
        if (length in 2..48) {
            val first = text[begin]
            val heading = when {
                first == '第' || first == '正' || first == '序' || first == '楔' || first == '引' ||
                    first == '前' || first == '尾' || first == '终' || first == '番' || first == '后' ||
                    first == '外' || first == '附' ->
                    CJK_HEADING.matchesAt(text, begin, finish) || FRONT_MATTER.matchesAt(text, begin, finish)

                first == 'C' || first == 'c' -> LATIN_HEADING.matchesAt(text, begin, finish)
                else -> false
            }
            if (heading) {
                found.add(ChapterMark(text.substring(begin, finish), index))
                lastAccepted = index
            } else if (weak && length in 2..20 && looksLikeTitle(text, begin, finish) &&
                (previousBlank || previousSentence) && index - lastAccepted >= WEAK_GAP
            ) {
                found.add(ChapterMark(text.substring(begin, finish), index))
                lastAccepted = index
            }
        }
        previousBlank = length == 0
        previousSentence = length > 0 && (isBlank(text[finish - 1]) || endsSentence(text[finish - 1]))
        if (newline < 0) break
        index = newline + 1
    }
    return found
}

/**
 * How far a title-like line has to sit from the previous entry.
 *
 * Without it, a chapter opening of three short unpunctuated lines becomes three
 * table-of-contents rows.
 */
private const val WEAK_GAP = 200

private fun Regex.matchesAt(text: String, start: Int, end: Int): Boolean =
    matches(text.substring(start, end))

private fun isBlank(char: Char): Boolean =
    char == ' ' || char == '\t' || char == '\u3000' || char == '\uFEFF'

private fun endsSentence(char: Char): Boolean =
    char == '。' || char == '！' || char == '？' || char == '…' || char == '"' || char == '”' ||
        char == '」' || char == '』' || char == ')' || char == '）'

/** A title-like line: no sentence punctuation, no brackets, nothing quoted. */
private fun looksLikeTitle(text: String, start: Int, end: Int): Boolean {
    for (position in start until end) {
        if (text[position] in TITLE_STOP_CHARS) return false
    }
    return true
}

private const val TITLE_STOP_CHARS =
    "。！？；，、：…—～·\"'“”‘’()（）[]【】《》〈〉「」『』"

// ---------------------------------------------------------------------------
// Chunking
// ---------------------------------------------------------------------------

/**
 * Cuts the text into contiguous blocks of at most [budget] characters.
 *
 * Blocks break at paragraph ends, so scrolling shows whole paragraphs and a
 * page never starts mid-sentence for no reason. A paragraph longer than the
 * budget is the one exception — it has to be cut somewhere, and it is cut after
 * punctuation where there is any within reach, so the break at least looks like
 * a break. [ChunkedText.starts] carries where each block begins in the source,
 * which is what chapter and search offsets are translated through.
 */
fun chunkText(text: String, budget: Int = CHUNK_CHARS): ChunkedText {
    require(budget > 0)
    val chunks = ArrayList<String>(text.length / budget + 2)
    val starts = ArrayList<Int>(text.length / budget + 2)
    var chunkStart = 0
    var index = 0
    while (index < text.length) {
        val newline = text.indexOf('\n', index)
        val end = if (newline < 0) text.length else newline + 1
        if (chunkStart < index && end - chunkStart > budget) {
            chunks.add(text.substring(chunkStart, index))
            starts.add(chunkStart)
            chunkStart = index
        }
        while (end - chunkStart > budget) {
            val cut = cutPoint(text, chunkStart, budget)
            chunks.add(text.substring(chunkStart, cut))
            starts.add(chunkStart)
            chunkStart = cut
        }
        index = end
    }
    if (chunkStart < text.length) {
        chunks.add(text.substring(chunkStart))
        starts.add(chunkStart)
    }
    return ChunkedText(chunks, starts.toIntArray())
}

/**
 * Where to cut a paragraph that is longer than a block: at the last sentence
 * end within reach, otherwise exactly at the budget.
 */
private fun cutPoint(text: String, start: Int, budget: Int): Int {
    val target = minOf(start + budget, text.length)
    val floor = maxOf(start + budget * 3 / 4, start + 8)
    var position = target
    while (position > floor) {
        if (text[position - 1] in CUT_CHARS) return position
        position--
    }
    return target
}

private const val CUT_CHARS = "。！？；…\n\"”」』"

/** The block that holds [offset], by binary search over the block starts. */
fun chunkIndexFor(starts: IntArray, offset: Int): Int {
    if (starts.isEmpty()) return 0
    var low = 0
    var high = starts.size - 1
    var answer = 0
    while (low <= high) {
        val middle = (low + high) / 2
        if (starts[middle] <= offset) {
            answer = middle
            low = middle + 1
        } else {
            high = middle - 1
        }
    }
    return answer
}

// ---------------------------------------------------------------------------
// Rendering helpers
// ---------------------------------------------------------------------------

/** Spacing a file already put in front of a paragraph. */
private fun isLeadingSpace(c: Char): Boolean = c == ' ' || c == '\t' || c == '\u3000'

/** How many characters of [chunk] from [start] up to [end] are leading spacing. */
private fun leadingSpace(chunk: String, start: Int, end: Int): Int {
    var lead = 0
    while (start + lead < end && isLeadingSpace(chunk[start + lead])) lead++
    return lead
}

/**
 * Whether a paragraph is a chapter heading by the strict rules alone (`第…章`,
 * front and back matter, `Chapter N`). Headings are not indented: an indented
 * title reads as the first line of a paragraph.
 */
private fun isHeadingLine(chunk: String, begin: Int, end: Int): Boolean {
    var finish = end
    while (finish > begin && isBlank(chunk[finish - 1])) finish--
    if (finish - begin !in 2..48) return false
    return CJK_HEADING.matchesAt(chunk, begin, finish) ||
        FRONT_MATTER.matchesAt(chunk, begin, finish) ||
        LATIN_HEADING.matchesAt(chunk, begin, finish)
}

/**
 * The text as it is laid out: paragraph indent is part of the string rather
 * than a paragraph style, because Compose has no first-line indent and a
 * two-space prefix is how every Chinese e-book does it anyway.
 *
 * Most Chinese text files already start their paragraphs with two ideographic
 * spaces, and adding ours on top indented every paragraph by four. So whatever
 * spacing a paragraph arrives with is replaced by the indent, not added to, and
 * a line that is nothing but spacing is drawn empty.
 */
fun renderChunk(chunk: String, indent: Boolean): String {
    if (!indent) return chunk
    val out = StringBuilder(chunk.length + 16)
    var index = 0
    while (index < chunk.length) {
        val newline = chunk.indexOf('\n', index)
        val end = if (newline < 0) chunk.length else newline
        val lead = leadingSpace(chunk, index, end)
        if (end > index + lead) {
            if (!isHeadingLine(chunk, index + lead, end)) out.append(INDENT)
            out.append(chunk, index + lead, end)
        }
        if (newline < 0) break
        out.append('\n')
        index = newline + 1
    }
    return out.toString()
}

/**
 * Maps an offset in the raw block to the same position in [renderChunk]'s
 * output: each paragraph before it gained an indent and lost its own leading
 * spacing. An offset inside that spacing lands where the paragraph's text
 * starts.
 */
fun renderOffset(chunk: String, raw: Int, indent: Boolean): Int {
    if (!indent || raw <= 0) return raw
    var start = 0
    var shift = 0
    // `<=`: an offset at the very start of a paragraph belongs after that
    // paragraph's indent, on its first character.
    while (start <= raw && start < chunk.length) {
        val newline = chunk.indexOf('\n', start)
        val end = if (newline < 0) chunk.length else newline
        val lead = leadingSpace(chunk, start, end)
        val gained = if (end > start + lead && !isHeadingLine(chunk, start + lead, end)) INDENT.length else 0
        if (raw < start + lead) return start + shift + gained
        shift += gained - lead
        if (newline < 0) break
        start = newline + 1
    }
    return raw + shift
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/**
 * Every occurrence of [query], over the raw blocks.
 *
 * Offsets are into the raw block, not into the indented text, so a result stays
 * valid when the paragraph indent is toggled; the caller maps them with
 * [renderOffset]. Latin queries match case-insensitively as a second pass, only
 * when the first pass found nothing.
 */
fun searchChunks(chunks: List<String>, query: String, limit: Int = 400): List<TextMatch> {
    if (query.isEmpty()) return emptyList()
    val matches = ArrayList<TextMatch>()
    for ((chunk, text) in chunks.withIndex()) {
        var from = 0
        while (matches.size < limit) {
            val at = text.indexOf(query, from)
            if (at < 0) break
            matches.add(TextMatch(chunk, at, query.length))
            from = at + query.length
        }
        if (matches.size >= limit) break
    }
    if (matches.isNotEmpty() || query.none { it.isLetter() }) return matches
    val lowered = query.lowercase()
    // Folding can change a string's length in a handful of locales, and the
    // offsets it reports would then be wrong; those queries stay case sensitive.
    if (lowered.length != query.length) return matches
    for ((chunk, text) in chunks.withIndex()) {
        val folded = text.lowercase()
        if (folded.length != text.length) continue
        var from = 0
        while (matches.size < limit) {
            val at = folded.indexOf(lowered, from)
            if (at < 0) break
            matches.add(TextMatch(chunk, at, query.length))
            from = at + query.length
        }
        if (matches.size >= limit) break
    }
    return matches
}

/** The first match at or after a position, for "find the next one". */
fun firstMatchAfter(matches: List<TextMatch>, chunk: Int, offset: Int): Int {
    val at = matches.indexOfFirst { it.chunk > chunk || (it.chunk == chunk && it.start >= offset) }
    return if (at >= 0) at else 0
}
