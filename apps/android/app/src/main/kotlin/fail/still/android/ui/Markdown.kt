// Agents write Markdown; the phone reads it as the web phone does (web/src/Prose.tsx, Prose.css.ts and the message's
// `.markdown` in styles/conversation.css.ts, at the phone's sizes: 15 with a 1.65 line). GFM: paragraphs with
// emphasis, inline code, links and strikethrough; headings; lists (bulleted, numbered, tasks, nested) with hanging
// indents; quotes beside a bar; code blocks with their language and a copy button on a row of their own (a finger
// has no hover), scrolling sideways; tables that wrap between words and scroll sideways when they still do not fit;
// rules. A link to another chat is a reference to it (chatRefs.ts), `@its title` in the accent; a ```mermaid block is
// drawn as its chart (Viz.kt). With `placing`, the message's files its text names are drawn where it names them.
//
// Spacing is the web's: each block keeps the margins the browser gives it, and two blocks next to each other are as
// far apart as the larger of the two margins between them (CSS margins collapse, through a list item or a quote too).
package fail.still.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.data.Attachment
import kotlinx.coroutines.delay
import org.commonmark.ext.autolink.AutolinkExtension
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableBody
import org.commonmark.ext.gfm.tables.TableCell
import org.commonmark.ext.gfm.tables.TableHead
import org.commonmark.ext.gfm.tables.TableRow
import org.commonmark.ext.gfm.tables.TablesExtension
import org.commonmark.ext.task.list.items.TaskListItemMarker
import org.commonmark.ext.task.list.items.TaskListItemsExtension
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListBlock as MdList
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text as TextNode
import org.commonmark.node.ThematicBreak
import org.commonmark.parser.Parser
import kotlin.math.max
import kotlin.math.roundToInt

private fun markdownParser(): Parser = Parser.builder()
    .extensions(listOf(TablesExtension.create(), StrikethroughExtension.create(), AutolinkExtension.create(), TaskListItemsExtension.create()))
    .build()

/** A table's delimiter row: `|---|:--:|`, or `--- | ---` without the outer pipes. */
private val tableDelimiter = Regex("""^ {0,3}\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$""")

/**
 * GFM (and the web's parser) starts a table on a paragraph's last line (`**这些**` and then the table, no blank line
 * between); commonmark-java only on a paragraph of its own, and prints the table as text. So a blank line goes before
 * such a table's header (outside fenced code).
 */
internal fun tablesApart(text: String): String {
    if ('|' !in text || '-' !in text) return text
    val lines = text.split('\n')
    val out = StringBuilder(text.length + 8)
    var fence: String? = null
    lines.forEachIndexed { i, line ->
        val lead = line.trimStart()
        val open = fence
        if (open == null && (lead.startsWith("```") || lead.startsWith("~~~"))) fence = lead.take(3)
        else if (open != null && lead.startsWith(open)) fence = null
        else if (open == null && i > 0 && i < lines.lastIndex && '|' in line && '|' in lines[i + 1] && tableDelimiter.matches(lines[i + 1]) &&
            lines[i - 1].isNotBlank() && '|' !in lines[i - 1]) out.append('\n')
        out.append(line)
        if (i < lines.lastIndex) out.append('\n')
    }
    return out.toString()
}

private val documents = object : android.util.LruCache<String, Node>(256 * 1024) {
    override fun sizeOf(key: String, value: Node) = key.length.coerceAtLeast(1)
}

/**
 * Parses `text` into the documents a message draws from, if not there yet: done off the UI thread as a chat's messages
 * are decoded (data/ChatDecoder.kt), so they are drawn whole as the chat first shows, not "laying out" first.
 */
fun prepareMarkdown(text: String) {
    if (text.isEmpty() || documents.get(text) != null) return
    documents.put(text, markdownParser().parse(text))
}

private fun Node.children(): List<Node> = generateSequence(firstChild) { it.next }.toList()

/**
 * A message's files its text places (placeFiles), and how they are drawn: `shown` draws one on a line of its own
 * (an HTML file as its visualization, an image whole, any other as its card) or several images in a row (`row`, each
 * given the modifier that sizes it); `open` opens one a link within a sentence names.
 */
class Placing(
    val files: Map<String, Attachment>,
    val shown: @Composable (Attachment) -> Unit,
    val row: @Composable (Attachment, Modifier) -> Unit,
    val open: (Attachment) -> Unit,
)

/** The file a link or image in the text names, by its file name (the last part of its path): `shot.png`, `/w/shot.png`, `ember-file://…/shot.png`. */
fun fileNameOf(url: String): String {
    var u = url.trim().replace(Regex("^(ember-)?file://"), "")
    u = try { java.net.URLDecoder.decode(u.replace("+", "%2B"), "UTF-8") } catch (_: Exception) { u }
    return u.substringAfterLast('/')
}

private val FENCE = Regex("(?ms)^ {0,3}(`{3,}|~{3,}).*?(^ {0,3}\\1|\\z)")
private val TICKS = Regex("(`+)[\\s\\S]*?\\1")
private val TARGET = Regex("\\]\\(\\s*<?([^)\\s>]+)>?(?:\\s+(?:\"[^\"]*\"|'[^']*'))?\\s*\\)")

/**
 * Which of a message's files its text places, by the name its links and images give (`![](shot.png)`,
 * `[the report](report.pdf)`), and the rest, shown below the text. Code is passed over: a name in it places nothing.
 */
fun placeFiles(text: String, files: List<Attachment>): Pair<Map<String, Attachment>, List<Attachment>> {
    if (files.isEmpty() || text.isEmpty()) return emptyMap<String, Attachment>() to files
    val prose = text.replace(FENCE, "").replace(TICKS, "")
    val placed = LinkedHashMap<String, Attachment>()
    for (m in TARGET.findAll(prose)) {
        val name = fileNameOf(m.groupValues[1])
        files.firstOrNull { it.name == name }?.let { placed[name] = it }
    }
    val used = placed.values.toSet()
    return placed to files.filter { it !in used }
}

// ── references to chats (chatRefs.ts) ─────────────────────────────────

/** A link to a chat's page (…/chats/<key>, or still.fail cloud's /o/<workspace>/<station>/<key>). */
fun isChatLink(href: String?): Boolean =
    href != null && (Regex("/chats/[^/?#\\s]+/?(?:[?#]|$)").containsMatchIn(href) || Regex("^https?://[^/]+/o/[^/]+/[^/]+/[^/?#]+/?(?:#|$)").containsMatchIn(href))

/** A reference as sent: `[its title](its page)`. */
private val REF_LINK = Regex("\\[([^\\]\\n]{1,120})\\]\\((\\S*?/chats/[^\\s)]+)\\)")

/** A reference in a message: `@` (a little lighter) and the chat's title, in the accent; a tap opens the chat (AppState.openLink). */
fun AnnotatedString.Builder.appendRef(title: AnnotatedString, href: String, accent: Color) {
    withLink(LinkAnnotation.Url(href, TextLinkStyles(SpanStyle(color = accent, textDecoration = TextDecoration.None)))) {
        withStyle(SpanStyle(color = accent.copy(alpha = accent.alpha * 0.7f))) { append("@") }
        append(title)
    }
}

/** Plain text (what a person wrote) with its references to chats drawn as the chips a message draws. */
@Composable
fun withRefs(text: String): AnnotatedString {
    val accent = C.accent
    return remember(text, accent) {
        buildAnnotatedString {
            var at = 0
            for (m in REF_LINK.findAll(text)) {
                append(text, at, m.range.first)
                appendRef(AnnotatedString(m.groupValues[1]), m.groupValues[2], accent)
                at = m.range.last + 1
            }
            append(text, at, text.length)
        }
    }
}

// ── the web's own tones (styles/global.css.ts), where the message's parts use them ──

/** The web's --line-strong (a quote's bar). */
private val lineStrong @Composable get() = if (C.dark) Color(0xFF3D3F44) else Color(0xFFC1C4C9)
/** The web's --muted (a quote's words). */
internal val webMuted @Composable get() = if (C.dark) Color(0xFFA3A5A9) else Color(0xFF646970)
/** The web's --subtle. */
internal val webSubtle @Composable get() = if (C.dark) Color(0xFF8C8F94) else Color(0xFF73787D)
/** The web's --line (a table's rules). */
internal val webLine @Composable get() = if (C.dark) Color(0xFF2D2E32) else Color(0xFFE3E1DE)
/** A table's ground: the text at 2% in the canvas. */
private val tableGround @Composable get() = if (C.dark) Color(0xFF232427) else Color(0xFFFAFAFA)
/** A code block's ground: the text at 4% in the canvas; a table's header row too. */
internal val codeGround @Composable get() = if (C.dark) Color(0xFF26272A) else Color(0xFFF5F5F5)
private val codeInline @Composable get() = if (C.dark) Color(0xFFC9A2E6) else Color(0xFF7C3FA0)

// ── blocks ──────────────────────────────────────────────────────────────

/** A block with the margins the web gives it, above and below. */
private class Piece(val top: Float, val bottom: Float, val draw: @Composable () -> Unit)

private class Ctx(val size: Int, val placing: Placing?, val fillTables: Boolean)

@Composable
fun Markdown(text: String, modifier: Modifier = Modifier, size: Int = 15, placing: Placing? = null, fillTables: Boolean = false) {
    val cached = remember(text) { documents.get(text) }
    val ready by androidx.compose.runtime.produceState(cached?.let { text to it }, text) {
        value = cached?.let { text to it }
        if (cached == null) {
            val doc = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { markdownParser().parse(tablesApart(text)) }
            documents.put(text, doc)
            value = text to doc
        }
    }
    val doc = ready?.takeIf { it.first == text }?.second
    val blocks = remember(doc, size, placing, fillTables) { doc?.let { pieces(it.children(), Ctx(size, placing, fillTables), tight = false) } }
    Box(modifier) {
        if (blocks == null) Text(t("android-misc.markdown.laying"), color = webSubtle, fontSize = size.sp)
        else Stack(blocks)
    }
}

/** Pieces one under another, as far apart as the larger margin between each two; the outer margins are the parent's. */
@Composable
private fun Stack(pieces: List<Piece>) {
    Column {
        pieces.forEachIndexed { i, p ->
            if (i > 0) {
                val gap = max(pieces[i - 1].bottom, p.top)
                if (gap > 0f) Box(Modifier.height(gap.dp))
            }
            p.draw()
        }
    }
}

private fun pieces(nodes: List<Node>, ctx: Ctx, tight: Boolean, task: Boolean? = null): List<Piece> =
    nodes.flatMapIndexed { i, n -> if (n is TaskListItemMarker) emptyList() else piecesOf(n, ctx, tight, if (i == nodes.indexOfFirst { it is Paragraph }) task else null) }

private fun piecesOf(node: Node, ctx: Ctx, tight: Boolean, task: Boolean?): List<Piece> {
    val s = ctx.size.toFloat()
    return when (node) {
        is Paragraph -> paragraph(node, ctx, if (tight) 0f else s, task)
        is Heading -> {
            val (em, margin) = when (node.level) {
                5 -> 0.83f to 1.67f * 0.83f * s
                6 -> 0.67f to 2.33f * 0.67f * s
                else -> 1f to -1f
            }
            val fs = s * em
            val top = if (margin < 0) 14f else margin
            val bottom = if (margin < 0) 6f else margin
            listOf(Piece(top, bottom) { Words(node, ctx, fs, FontWeight.Bold) })
        }
        is BulletList, is OrderedList -> listOf(list(node as MdList, ctx, 1 + generateSequence(node.parent) { it.parent }.count { it is MdList }))
        is BlockQuote -> {
            val inner = pieces(node.children(), ctx, tight = false)
            listOf(Piece(max(0f, inner.firstOrNull()?.top ?: 0f), max(8f, inner.lastOrNull()?.bottom ?: 0f)) {
                Row(Modifier.height(IntrinsicSize.Min)) {
                    Box(Modifier.width(2.dp).fillMaxHeight().background(lineStrong))
                    Box(Modifier.padding(start = 10.dp)) { androidx.compose.runtime.CompositionLocalProvider(LocalMdInk provides webMuted) { Stack(inner) } }
                }
            })
        }
        is FencedCodeBlock -> {
            val language = node.info?.trim()?.substringBefore(' ')?.ifEmpty { null }
            val code = node.literal.removeSuffix("\n")
            if (language?.lowercase() == "mermaid" && code.isNotBlank()) listOf(Piece(0f, 4f) { Mermaid(code) })
            else listOf(Piece(0f, 8f) { CodeBlock(code, language) })
        }
        is IndentedCodeBlock -> listOf(Piece(0f, 8f) { CodeBlock(node.literal.removeSuffix("\n"), null) })
        is TableBlock -> listOf(Piece(0f, 8f) { Table(node, ctx) })
        is ThematicBreak -> listOf(Piece(s / 2, s / 2) { Box(Modifier.fillMaxWidth().height(1.dp).background(webLine)) })
        // Raw HTML is shown as written (react-markdown does not draw it).
        is HtmlBlock -> listOf(Piece(s, s) { MdText(AnnotatedString(node.literal.trimEnd()), ctx.size.sp, lh(ctx.size.toFloat())) })
        else -> pieces(node.children(), ctx, tight)
    }
}

private fun lh(size: Float): TextUnit = (size * 1.65f).sp

/** The ink of the words here: a quote's words are the web's muted. */
internal val LocalMdInk = androidx.compose.runtime.compositionLocalOf<Color?> { null }

/**
 * A paragraph; with files placed, one that is only a link to one of them is that file shown (a line of its own), and
 * one of only their images is them in a row. An image of theirs among words is shown between the words around it.
 */
private fun paragraph(node: Paragraph, ctx: Ctx, margin: Float, task: Boolean?): List<Piece> {
    val placing = ctx.placing
    if (placing != null && placing.files.isNotEmpty()) {
        val parts = node.children().filter { !(it is TextNode && it.literal.isBlank()) && it !is SoftLineBreak && it !is TaskListItemMarker }
        fun fileOf(n: Node): Attachment? = when (n) {
            is Link -> placing.files[fileNameOf(n.destination)]
            is Image -> placing.files[fileNameOf(n.destination)]
            else -> null
        }
        val only = parts.singleOrNull()
        if (only is Link && task == null) fileOf(only)?.let { f -> return listOf(Piece(8f, 8f) { placing.shown(f) }) }
        val images = parts.map { if (it is Image) fileOf(it) else null }
        if (images.size > 1 && images.all { it != null } && task == null) return listOf(Piece(8f, 8f) { ImageRow(images.filterNotNull(), placing) })
        // Images of the message's among words: the words before, the image on a line of its own, the words after.
        if (parts.any { it is Image && fileOf(it) != null }) {
            val out = mutableListOf<Piece>()
            var run = mutableListOf<Node>()
            fun flush() {
                val nodes = run
                val box = task.takeIf { out.isEmpty() }
                if (nodes.any { !(it is TextNode && it.literal.isBlank()) && it !is SoftLineBreak }) out += Piece(margin, margin) { Words(nodes, ctx, ctx.size.toFloat(), null, box) }
                run = mutableListOf()
            }
            for (n in node.children()) {
                val f = if (n is Image) fileOf(n) else null
                if (f != null) { flush(); out += Piece(margin, margin) { Box(Modifier.padding(vertical = 8.dp)) { placing.shown(f) } } } else run += n
            }
            flush()
            return out
        }
    }
    return listOf(Piece(margin, margin) { Words(node, ctx, ctx.size.toFloat(), null, task) })
}

/**
 * Images written in one paragraph: side by side, wrapping onto the next line when a line is full. Each is as wide as
 * its shape asks (a line's images share one height, 120 or a little more, 200 at most), as the web's flex row has it.
 */
@Composable
private fun ImageRow(files: List<Attachment>, placing: Placing) {
    val ratios = files.map { f -> if (f.width != null && f.height != null && f.height > 0) (f.width.toFloat() / f.height).coerceIn(0.25f, 4f) else 1.5f }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val full = maxWidth.value
        val gap = 8f
        // Lines as flex-wrap fills them: by each image's basis (120 × its ratio).
        val lines = mutableListOf<MutableList<Int>>()
        var used = 0f
        ratios.forEachIndexed { i, r ->
            val basis = r * 120f
            if (lines.isEmpty() || (used + gap + basis > full && lines.last().isNotEmpty())) { lines += mutableListOf(i); used = basis }
            else { lines.last() += i; used += gap + basis }
        }
        Column(verticalArrangement = Arrangement.spacedBy(gap.dp)) {
            lines.forEach { line ->
                // Grown in proportion to their ratios, each kept to 200 × its ratio at most.
                val free = full - gap * (line.size - 1)
                val basis = line.sumOf { (ratios[it] * 120f).toDouble() }.toFloat()
                val grow = line.sumOf { ratios[it].toDouble() }.toFloat()
                val extra = ((free - basis) / grow).coerceAtLeast(0f)
                Row(horizontalArrangement = Arrangement.spacedBy(gap.dp)) {
                    line.forEach { i ->
                        val r = ratios[i]
                        val w = minOf(r * 120f + r * extra, r * 200f, free)
                        placing.row(files[i], Modifier.width(w.dp).height((w / r).dp))
                    }
                }
            }
        }
    }
}

/** Items with their markers in the list's 20 of indent, so wrapped lines hang under the words. */
private fun list(node: MdList, ctx: Ctx, depth: Int): Piece {
    val tight = node.isTight
    val items = node.children().filterIsInstance<ListItem>().mapIndexed { i, item ->
        val task = taskOf(item)
        val inner = pieces(item.children(), ctx, tight, task)
        Piece(inner.firstOrNull()?.top ?: 0f, inner.lastOrNull()?.bottom ?: 0f) {
            Row {
                val ink = LocalMdInk.current ?: C.ink
                if (node is OrderedList) Text(
                    "${(node.markerStartNumber ?: 1) + i}.", color = ink, fontSize = ctx.size.sp, lineHeight = lh(ctx.size.toFloat()), textAlign = TextAlign.End, maxLines = 1, softWrap = false,
                    modifier = Modifier.width(20.dp).padding(end = 5.dp),
                ) else Bullet(depth, ctx.size.toFloat(), ink)
                Box(Modifier.weight(1f)) { Stack(inner) }
            }
        }
    }
    return Piece(max(0f, items.firstOrNull()?.top ?: 0f), max(8f, items.lastOrNull()?.bottom ?: 0f)) { Stack(items) }
}

/**
 * A bulleted item's marker as the browser draws it outside the item (`disc`, then `circle`, then `square`): a third
 * of the text's size across, its middle 15 of the indent's 20 before the words, on the first line's middle.
 */
@Composable
private fun Bullet(depth: Int, textSize: Float, ink: Color) {
    Box(Modifier.width(20.dp).height(with(androidx.compose.ui.platform.LocalDensity.current) { lh(textSize).toDp() }), contentAlignment = Alignment.CenterStart) {
        val side = (textSize / 3f).dp
        Canvas(Modifier.padding(start = 5.dp - side / 2).size(side)) {
            when (depth) {
                1 -> drawCircle(ink)
                2 -> drawCircle(ink, radius = size.minDimension / 2 - 0.5.dp.toPx(), style = Stroke(1.dp.toPx()))
                else -> drawRect(ink)
            }
        }
    }
}

/** A task item's box: checked or not, or null when the item is no task. */
private fun taskOf(item: ListItem): Boolean? {
    val direct = item.firstChild as? TaskListItemMarker
    val inPara = (item.firstChild as? Paragraph)?.firstChild as? TaskListItemMarker
    return (direct ?: inPara)?.isChecked
}

/**
 * A code block as the web phone draws it: a quiet tinted block with no frame; above the code, on a row of its own
 * (there is no hover to bring the corner forward), its language and a copy button; highlighted when its language is
 * named. It scrolls sideways rather than wrapping.
 */
@Composable
fun CodeBlock(code: String, language: String?, bar: Boolean = true, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(1500); copied = false } }
    val dark = C.dark
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(codeGround)) {
        if (bar) Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 4.dp).height(24.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            Text(language ?: "text", fontSize = 10.sp, letterSpacing = 0.2.sp, color = webSubtle, modifier = Modifier.padding(horizontal = 6.dp))
            Row(
                Modifier.height(24.dp).clip(RoundedCornerShape(6.dp)).background(C.surface.copy(alpha = 0.8f)).clickable {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("code", code))
                    copied = true
                }.padding(horizontal = 7.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                IconIn(if (copied) Icons.Check else Icons.Copy, 12.dp, webMuted)
                Text(if (copied) t("common.copied") else t("common.copy"), fontSize = 11.sp, color = webMuted)
            }
        }
        Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 12.dp)) {
            // The system's mono face is thin next to the web's (SF Mono, Menlo): drawn a little bolder to have its colour.
            CodeInk(code, language, dark)
        }
    }
}

/** Android's mono face has one weight; asking for more draws it emboldened (the system's fake bold). */
val CodeWeight = FontWeight.SemiBold

/**
 * A table as the web draws it: in a card's frame (20 round, a faint ground), small type (13), the header row tinted
 * and its words muted (12), rows ruled between them only, their words kept whole (a cell wraps between words), at
 * least 4em wide. Columns are as wide as their content until the message is full (the browser's automatic layout);
 * past what its words allow, it scrolls sideways within the message.
 */
@Composable
private fun Table(table: TableBlock, ctx: Ctx) {
    val rows = table.children().flatMap { part -> if (part is TableHead || part is TableBody) part.children() else emptyList() }.filterIsInstance<TableRow>()
    val cells = rows.map { r -> r.children().filterIsInstance<TableCell>() }
    val columns = cells.maxOfOrNull { it.size } ?: 0
    if (columns == 0) return
    val line = webLine
    val head = codeGround
    val muted = webMuted
    val frame = RoundedCornerShape(20.dp)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val avail = constraints.maxWidth - with(androidx.compose.ui.platform.LocalDensity.current) { 2.dp.roundToPx() }
        Box(Modifier.clip(frame).border(1.dp, line, frame).background(tableGround).padding(1.dp).horizontalScroll(rememberScrollState())) {
            Layout(
                content = {
                    cells.forEachIndexed { r, row ->
                        val header = row.firstOrNull()?.isHeader == true
                        for (c in 0 until columns) {
                            val cell = row.getOrNull(c)
                            // Middle-aligned, as the browser's cells are; a rule under every row but the last.
                            Box(
                                Modifier.then(if (header) Modifier.background(head) else Modifier)
                                    .then(if (r < cells.lastIndex) Modifier.drawBehind { drawLine(line, Offset(0f, size.height - 0.5.dp.toPx()), Offset(size.width, size.height - 0.5.dp.toPx()), 1.dp.toPx()) } else Modifier)
                                    .padding(horizontal = 12.dp, vertical = 7.dp),
                                contentAlignment = Alignment.CenterStart,
                            ) {
                                val images = cell?.let { cellImages(it, ctx) }
                                if (images != null) CellImageRow(images, ctx.placing!!)
                                else if (cell != null && header) androidx.compose.runtime.CompositionLocalProvider(LocalMdInk provides muted) { Words(cell, ctx, 12f, FontWeight.Medium) }
                                else if (cell != null) Words(cell, ctx, 13f, null)
                            }
                        }
                    }
                },
            ) { measurables, _ ->
                val least = (4 * 13).dp.roundToPx() + 24.dp.roundToPx()
                val mins = IntArray(columns); val maxs = IntArray(columns)
                measurables.forEachIndexed { i, m ->
                    val c = i % columns
                    mins[c] = max(mins[c], max(least, m.minIntrinsicWidth(Int.MAX_VALUE)))
                    maxs[c] = max(maxs[c], max(least, m.maxIntrinsicWidth(Int.MAX_VALUE)))
                }
                val sumMin = mins.sum(); val sumMax = maxs.sum()
                val widths = when {
                    sumMax <= avail && ctx.fillTables -> {
                        val extra = avail - sumMax
                        IntArray(columns) { c -> maxs[c] + extra / columns + if (c < extra % columns) 1 else 0 }
                    }
                    sumMax <= avail -> maxs
                    sumMin >= avail -> mins
                    else -> IntArray(columns) { c -> mins[c] + ((maxs[c] - mins[c]).toFloat() * (avail - sumMin) / (sumMax - sumMin)).roundToInt() }
                }
                val heights = measurables.chunked(columns).map { row -> row.withIndex().maxOf { (c, m) -> m.minIntrinsicHeight(widths[c]) } }
                // Each cell as tall as its row, so the rules line up.
                val cellsPlaced = measurables.mapIndexed { i, m -> m.measure(Constraints.fixed(widths[i % columns], heights[i / columns])) }
                layout(widths.sum(), heights.sum()) {
                    var y = 0
                    cellsPlaced.chunked(columns).forEachIndexed { r, row ->
                        var x = 0
                        row.forEachIndexed { c, p -> p.place(x, y); x += widths[c] }
                        y += heights[r]
                    }
                }
            }
        }
    }
}

/**
 * A cell of only the message's images (`| ![](before.png) | ![](after.png) |`): them, side by side, each 160 wide at
 * most (the web's cell has the image fill it, as the table lets it); null for any other cell, drawn as words.
 */
private fun cellImages(cell: TableCell, ctx: Ctx): List<Attachment>? {
    val placing = ctx.placing ?: return null
    val parts = cell.children().filter { !(it is TextNode && it.literal.isBlank()) && it !is SoftLineBreak }
    val files = parts.map { n -> if (n is Image) placing.files[fileNameOf(n.destination)] else null }
    return files.takeIf { it.isNotEmpty() && it.all { f -> f != null } }?.filterNotNull()
}

@Composable
private fun CellImageRow(files: List<Attachment>, placing: Placing) {
    Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        files.forEach { f ->
            val r = if (f.width != null && f.height != null && f.height > 0) (f.width.toFloat() / f.height).coerceIn(0.25f, 4f) else 1.5f
            // As wide as 160 for a wide image, as tall as 240 for a tall one.
            val w = minOf(160f, 240f * r)
            placing.row(f, Modifier.width(w.dp).height((w / r).dp))
        }
    }
}

// ── words ───────────────────────────────────────────────────────────────

private const val TASK = "task"

/** A block's words: its inline parts drawn (and, for a task item's first paragraph, its box ahead of them). */
@Composable
private fun Words(node: Node, ctx: Ctx, size: Float, weight: FontWeight?, task: Boolean? = null) = Words(node.children(), ctx, size, weight, task)

@Composable
private fun Words(nodes: List<Node>, ctx: Ctx, size: Float, weight: FontWeight?, task: Boolean? = null) {
    val text = inline(nodes, ctx, task)
    val inline = if (task == null) emptyMap() else mapOf(TASK to InlineTextContent(Placeholder(25.sp, 13.sp, PlaceholderVerticalAlign.TextCenter)) { TaskBox(task) })
    MdText(text, size.sp, lh(size), weight, inline = inline)
}

/**
 * A task's box, as the browser draws a disabled checkbox (13 across, 4 before it and 3 after, then the space before
 * the words): faint grey, filled and ticked when done.
 */
@Composable
private fun TaskBox(checked: Boolean) {
    Box(Modifier.fillMaxHeight().padding(start = 4.dp, end = 8.dp), contentAlignment = Alignment.Center) {
        val faint = if (C.dark) Color(0x66A0A0A0) else Color(0x4D767676)
        Box(
            Modifier.size(13.dp).clip(RoundedCornerShape(2.dp))
                .let { if (checked) it.background(faint) else it.background(C.surface.copy(alpha = 0.6f)).border(1.dp, faint, RoundedCornerShape(2.dp)) },
            contentAlignment = Alignment.Center,
        ) { if (checked) IconIn(Icons.Check, 11.dp, if (C.dark) C.ink.copy(alpha = 0.7f) else Color.White) }
    }
}

@Composable
private fun inline(nodes: List<Node>, ctx: Ctx, task: Boolean?): AnnotatedString {
    // Inline code as the web has it: no box, the code face in its own colour, a little smaller.
    val code = SpanStyle(fontFamily = FontFamily.Monospace, fontSize = TextUnit(0.9f, TextUnitType.Em), color = codeInline)
    val link = TextLinkStyles(SpanStyle(color = C.blue))
    val accent = C.accent
    val placing = ctx.placing
    return buildAnnotatedString {
        if (task != null) appendInlineContent(TASK, if (task) "[x]" else "[ ]")
        fun walk(n: Node) {
            when (n) {
                is TextNode -> append(n.literal)
                is Code -> withStyle(code) { append(n.literal) }
                is Emphasis -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { n.children().forEach(::walk) }
                is StrongEmphasis -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { n.children().forEach(::walk) }
                is Strikethrough -> withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { n.children().forEach(::walk) }
                is Link -> {
                    val file = placing?.files?.get(fileNameOf(n.destination))
                    when {
                        // A link within a sentence to one of the message's files: looks like any link, opens the file.
                        file != null -> withLink(LinkAnnotation.Clickable("file:${file.path}", link) { placing.open(file) }) { n.children().forEach(::walk) }
                        isChatLink(n.destination) -> appendRef(buildAnnotatedString { n.children().forEach { c -> append(inlineText(c)) } }, n.destination, accent)
                        // Opened through LocalUriHandler: still.fail's own links in the app (App.kt → AppState.openLink), the rest by the system.
                        else -> withLink(LinkAnnotation.Url(n.destination, link)) { n.children().forEach(::walk) }
                    }
                }
                // An image the app cannot fetch (only the message's own files are fetched, through the station): its words, leading to it.
                is Image -> {
                    val words = buildAnnotatedString { n.children().forEach { c -> append(inlineText(c)) } }.ifEmpty { AnnotatedString(fileNameOf(n.destination)) }
                    // One of the message's files (drawn as words only where it cannot be drawn itself): opens it.
                    val file = placing?.files?.get(fileNameOf(n.destination))
                    if (file != null) withLink(LinkAnnotation.Clickable("file:${file.path}", link) { placing.open(file) }) { append(words) }
                    else withLink(LinkAnnotation.Url(n.destination, link)) { append(words) }
                }
                is SoftLineBreak -> append(' ')
                is HardLineBreak -> append('\n')
                is HtmlInline -> append(n.literal)
                is TaskListItemMarker -> Unit
                else -> n.children().forEach(::walk)
            }
        }
        nodes.forEach(::walk)
    }
}

private fun AnnotatedString.ifEmpty(other: () -> AnnotatedString) = if (isEmpty()) other() else this

/** A node's words, plain. */
private fun inlineText(n: Node): String = when (n) {
    is TextNode -> n.literal
    is Code -> n.literal
    is SoftLineBreak, is HardLineBreak -> " "
    else -> n.children().joinToString("") { inlineText(it) }
}

@Composable
private fun MdText(text: AnnotatedString, fontSize: TextUnit, lineHeight: TextUnit, fontWeight: FontWeight? = null, inline: Map<String, InlineTextContent> = emptyMap()) {
    // A passage a quote led to, marked in these words (TextMark.kt).
    val (mark, laid) = passageMark(text.text)
    // On the annotate page, a passage picked from them or noted (Pick.kt).
    val (pick, picking) = pickable(text.text)
    Text(text, mark.then(pick), color = LocalMdInk.current ?: C.ink, fontSize = fontSize, lineHeight = lineHeight, fontWeight = fontWeight, inlineContent = inline, onTextLayout = { laid(it); picking(it) })
}
