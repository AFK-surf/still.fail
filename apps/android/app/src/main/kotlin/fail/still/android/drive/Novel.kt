// A text file of a drive made ready to read (zdrive's Novel.kt): fetched whole through the core (drive.read, a part at a
// time), decoded (UTF-8, else GB18030), a hard-wrapped novel reflowed into paragraphs, its chapters found, and cut into
// blocks a list lays out one at a time. Where the reader is, is an offset into the text it shows (drivePlace's `at`).
package fail.still.android.drive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import fail.still.android.data.ReaderPrefs
import fail.still.android.data.t
import fail.still.android.ui.Dark
import fail.still.android.ui.Light

/**
 * A text, ready to show in pieces: [chunks] are contiguous blocks of the text shown (each starts at [starts] of it), a
 * list virtualises them; [length] is the whole text's. [bytes] were read of [sourceBytes] (fewer when cut at
 * [MAX_NOVEL_BYTES]).
 */
class Novel(
    val title: String,
    val chunks: List<String>,
    val starts: IntArray,
    val length: Int,
    val charCount: Int,
    val bytes: Int,
    val chapters: List<NovelChapter>,
    val encoding: String,
    val sourceBytes: Long,
    val truncated: Boolean,
    /** Drawn as Markdown, not as its source (`.md`). */
    val markdown: Boolean,
) {
    /** The block an offset of the text is in, and how far into it. */
    fun at(offset: Int): Pair<Int, Int> {
        if (chunks.isEmpty()) return 0 to 0
        val i = chunkIndexFor(starts, offset.coerceIn(0, length))
        return i to (offset - starts[i]).coerceIn(0, chunks[i].length)
    }

    /** The offset of the text a block and a share of it is at. */
    fun offsetOf(chunk: Int, within: Float): Int {
        val c = chunk.coerceIn(0, (chunks.size - 1).coerceAtLeast(0))
        return (starts.getOrElse(c) { 0 } + (chunks.getOrElse(c) { "" }.length * within).toInt()).coerceIn(0, length)
    }
}

/**
 * The most of a text the reader holds: the bytes, the decoded text (two bytes a character) and its blocks are all in
 * memory at once, about four times the file at the peak. A bigger file opens with its first 16 MB and says so.
 */
const val MAX_NOVEL_BYTES = 16 * 1024 * 1024

/**
 * Decoding and indexing, on bytes already in memory (off the main thread). Headings are found twice: before the
 * reflow, so a heading line is not welded into the paragraph above it, and after it, where lines really are paragraphs.
 */
fun buildNovel(name: String, bytes: ByteArray, size: Long, truncated: Boolean): Novel {
    val decoded = decodeText(bytes, truncated = truncated)
    val normalised = normaliseLineEndings(decoded.text)
    val markdown = name.lowercase().let { it.endsWith(".md") || it.endsWith(".markdown") }
    // Markdown is laid out line by line already: reflowing it would weld a heading into the paragraph under it.
    val wrap = if (markdown) 0 else detectWrapWidth(normalised)
    val protectedHeadings = if (wrap > 0) findChapters(normalised, weak = false) else emptyList()
    val text = if (wrap > 0) reflow(normalised, wrap, protectedHeadings.map { it.offset }.toSet()) else normalised
    val chunked = chunkText(text)
    val chapters = (if (markdown) markdownChapters(text) else findChapters(text)).map { mark ->
        val chunk = chunkIndexFor(chunked.starts, mark.offset)
        NovelChapter(mark.title, chunk, mark.offset - chunked.starts[chunk])
    }
    return Novel(
        title = name, chunks = chunked.chunks, starts = chunked.starts, length = text.length, charCount = decoded.text.length,
        bytes = bytes.size, chapters = chapters, encoding = decoded.encoding, sourceBytes = size.coerceAtLeast(0), truncated = truncated, markdown = markdown,
    )
}

// ── how it is drawn ─────────────────────────────────────────────────────

/** What a page of the reader is drawn on: its ground, its text, what is quieter, the bars floating over it. */
data class PaperInk(val ground: Color, val ink: Color, val muted: Color, val bar: Color, val accent: Color, val dark: Boolean)

/**
 * The papers a reader can pick (zdrive's), in still.fail's colours: the app's own light and dark page, a green and a
 * grey one; `Follow` (the default) is the app's light or dark as it is now. Kept by the core (`prefs.reader.paper`).
 */
enum class Paper(val key: String) {
    Follow("follow"), White("white"), Green("green"), Grey("grey"), Night("night");

    val label: String get() = t("android-misc.drive.reader.paper.$key")

    fun ink(appDark: Boolean): PaperInk = when (this) {
        Follow -> (if (appDark) Night else White).ink(appDark)
        White -> PaperInk(Light.bg, Light.ink, Light.muted, Color.White, Light.accent, false)
        Green -> PaperInk(Color(0xFFE4ECDB), Color(0xFF24301F), Color(0xFF58654F), Color(0xFFF4F7EF), Light.accent, false)
        Grey -> PaperInk(Color(0xFFECECEC), Light.ink, Color(0xFF66686C), Color(0xFFF8F8F8), Light.accent, false)
        Night -> PaperInk(Dark.bg, Dark.ink, Dark.muted, Color(0xFF2A2C31), Dark.accent, true)
    }

    companion object {
        fun of(key: String?): Paper = entries.firstOrNull { it.key == key } ?: Follow
    }
}

/** The two faces a phone reader offers (`prefs.reader.face`). */
enum class ReaderFamily(val key: String, val family: FontFamily) {
    Serif("serif", FontFamily.Serif), Sans("sans", FontFamily.SansSerif);

    val label: String get() = t("android-misc.drive.reader.font.$key")

    companion object {
        fun of(key: String?): ReaderFamily = entries.firstOrNull { it.key == key } ?: Serif
    }
}

/** Everything the reader lays text out with, as the core keeps it (`prefs.reader`): the sheet changes it, the page is drawn with it. */
data class ReaderTypography(val fontSp: Int, val lineSpacing: Float, val marginDp: Int, val family: ReaderFamily, val indent: Boolean) {
    fun style(color: Color): TextStyle = TextStyle(
        color = color, fontSize = fontSp.sp, lineHeight = (fontSp * lineSpacing).sp, fontFamily = family.family, textAlign = TextAlign.Start,
    )

    companion object {
        /** Each setting's range (the core keeps them within it): where the sheet's steps stop. */
        const val MIN_FONT_SP = 12
        const val MAX_FONT_SP = 32
        const val MIN_LINE_SPACING = 1.2f
        const val MAX_LINE_SPACING = 2.4f
        const val MIN_MARGIN_DP = 8
        const val MAX_MARGIN_DP = 44

        fun of(p: ReaderPrefs) = ReaderTypography(p.size.toInt(), p.line.toFloat(), p.margin.toInt(), ReaderFamily.of(p.face), p.indent)
    }
}

/**
 * Where a jump lands: a block and an offset in it; `serial` makes the same place asked twice two jumps; `lead`: a little of
 * what is before it shown too (not when going back to where the reader was).
 */
data class ReaderJump(val chunk: Int, val offset: Int, val serial: Long = 0, val lead: Boolean = true)
