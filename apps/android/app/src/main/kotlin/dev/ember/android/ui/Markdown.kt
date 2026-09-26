// Agents write Markdown; the phone reads it as the web does (GFM, web/src/app.css
// `.markdown`): paragraphs with emphasis, inline code, links and strikethrough;
// headings; lists (bulleted, numbered, tasks, nested) with hanging indents;
// quotes beside a bar; code blocks that scroll sideways and copy; tables that
// scroll sideways; rules. Parsed by commonmark, drawn here.
package dev.ember.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.draw.alpha
import kotlinx.coroutines.delay
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text as TextNode
import org.commonmark.node.ThematicBreak
import org.commonmark.parser.Parser

private val parser: Parser = Parser.builder()
    .extensions(listOf(TablesExtension.create(), StrikethroughExtension.create(), AutolinkExtension.create(), TaskListItemsExtension.create()))
    .build()

private fun Node.children(): List<Node> = generateSequence(firstChild) { it.next }.toList()

@Composable
fun Markdown(text: String, modifier: Modifier = Modifier, size: Int = 15) {
    val doc = remember(text) { parser.parse(text) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) { doc.children().forEach { Block(it, size) } }
}

@Composable
private fun Blocks(nodes: List<Node>, size: Int, gap: Int = 8) {
    Column(verticalArrangement = Arrangement.spacedBy(gap.dp)) { nodes.forEach { Block(it, size) } }
}

@Composable
private fun Block(node: Node, size: Int) {
    when (node) {
        is Paragraph -> MdText(inline(node), size.sp, (size * 1.6).sp)
        // Headings are the body's size, bolder, with room above (as the web draws h1–h4).
        is Heading -> MdText(inline(node), (size + 1).sp, (size * 1.5).sp, FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
        is BulletList -> ListBlock(node, size) { _, item -> taskMark(item) ?: "•" }
        is OrderedList -> ListBlock(node, size) { i, item -> taskMark(item) ?: "${(node.markerStartNumber ?: 1) + i}." }
        is BlockQuote -> Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(2.dp).fillMaxHeight().clip(RoundedCornerShape(1.dp)).background(C.line))
            Box(Modifier.padding(start = 10.dp)) { Blocks(node.children(), size) }
        }
        is FencedCodeBlock -> CodeBlock(node.literal.trimEnd('\n'), node.info?.trim()?.substringBefore(' ')?.lowercase()?.ifEmpty { null })
        is IndentedCodeBlock -> CodeBlock(node.literal.trimEnd('\n'), null)
        is TableBlock -> Table(node)
        is ThematicBreak -> Box(Modifier.fillMaxWidth().padding(vertical = 4.dp).height(1.dp).background(C.line))
        is HtmlBlock -> Text(node.literal.trimEnd(), color = C.muted, fontSize = size.sp, lineHeight = (size * 1.6).sp)
        else -> Blocks(node.children(), size)
    }
}

/** A task item's box ("☐" / "☑"), in place of its bullet or number. */
private fun taskMark(item: Node): String? =
    (item.firstChild?.firstChild as? TaskListItemMarker)?.let { if (it.isChecked) "☑" else "☐" }

/** Items with their markers in a column of their own, so wrapped lines hang under the words. */
@Composable
private fun ListBlock(list: Node, size: Int, marker: (Int, Node) -> String) {
    val tight = (list as? BulletList)?.isTight ?: (list as? OrderedList)?.isTight ?: true
    Column(verticalArrangement = Arrangement.spacedBy(if (tight) 3.dp else 8.dp)) {
        list.children().filterIsInstance<ListItem>().forEachIndexed { i, item ->
            Row {
                Text(marker(i, item), color = C.muted, fontSize = size.sp, lineHeight = (size * 1.6).sp, modifier = Modifier.widthIn(min = 18.dp).padding(end = 6.dp))
                Box(Modifier.weight(1f)) { Blocks(item.children(), size, gap = if (tight) 3 else 8) }
            }
        }
    }
}

/**
 * A code block as the web draws it (web/src/Prose.tsx): a quiet tinted block with no frame; its language and a
 * copy button in the corner; highlighted when its language is named. It scrolls sideways rather than wrapping.
 */
@Composable
private fun CodeBlock(code: String, language: String?) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(1500); copied = false } }
    val dark = C.dark
    val colored = remember(code, language, dark) { highlight(code, language, dark) }
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.ink.copy(alpha = 0.04f))) {
        Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 12.dp)) {
            Text(colored, fontFamily = FontFamily.Monospace, fontSize = 12.5.sp, lineHeight = 20.sp, color = C.ink, softWrap = false)
        }
        Row(Modifier.align(Alignment.TopEnd).padding(4.dp).alpha(0.75f), verticalAlignment = Alignment.CenterVertically) {
            Text(language ?: "text", fontSize = 10.sp, color = C.subtle, modifier = Modifier.padding(horizontal = 6.dp))
            Row(
                Modifier.height(26.dp).clip(RoundedCornerShape(6.dp)).background(C.bg.copy(alpha = 0.8f)).clickable {
                    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("code", code))
                    copied = true
                }.padding(horizontal = 7.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                IconIn(if (copied) Icons.Check else Icons.Copy, 12.dp, C.muted)
                Text(if (copied) "已复制" else "复制", fontSize = 11.sp, color = C.muted)
            }
        }
    }
}

/** A table as the web draws it: small type, ruled cells; it scrolls sideways when wider than the screen. */
@Composable
private fun Table(table: TableBlock) {
    val rows = table.children().flatMap { part -> if (part is TableHead || part is TableBody) part.children() else emptyList() }.filterIsInstance<TableRow>()
    val cells = rows.map { r -> r.children().filterIsInstance<TableCell>() }
    val columns = cells.maxOfOrNull { it.size } ?: 0
    Box(Modifier.horizontalScroll(rememberScrollState())) {
        Row(Modifier.border(1.dp, C.line)) {
            // Column by column, each cell one line, so the rows line up.
            for (c in 0 until columns) {
                Column(Modifier.width(IntrinsicSize.Max)) {
                    cells.forEachIndexed { r, row ->
                        val cell = row.getOrNull(c)
                        MdText(
                            cell?.let { inline(it) } ?: AnnotatedString(""), 13.sp, 20.sp, if (cell?.isHeader == true) FontWeight.SemiBold else null, softWrap = false,
                            modifier = Modifier.fillMaxWidth().border(0.5.dp, C.line).padding(horizontal = 8.dp, vertical = 4.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun inline(node: Node): AnnotatedString {
    val code = SpanStyle(fontFamily = FontFamily.Monospace, fontSize = CODE_EM.em())
    val link = TextLinkStyles(SpanStyle(color = C.blue))
    return buildAnnotatedString {
        fun walk(n: Node) {
            when (n) {
                is TextNode -> append(n.literal)
                is Code -> withStyle(code) { append(" ${n.literal} ") }
                is Emphasis -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { n.children().forEach(::walk) }
                is StrongEmphasis -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { n.children().forEach(::walk) }
                is Strikethrough -> withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { n.children().forEach(::walk) }
                is Link -> withLink(LinkAnnotation.Url(n.destination, link)) { n.children().forEach(::walk) }
                is Image -> n.children().forEach(::walk)
                is SoftLineBreak -> append(' ')
                is HardLineBreak -> append('\n')
                is HtmlInline -> append(n.literal)
                is TaskListItemMarker -> Unit
                else -> n.children().forEach(::walk)
            }
        }
        node.children().forEach(::walk)
    }
}

private const val CODE = "code"
private const val CODE_EM = 0.88

/**
 * Text whose inline code sits on a small rounded box, as on the web (`.markdown :not(pre) > code`): the box
 * follows the code's own glyphs, not the line's height, and a span that wraps gets a box on each line.
 */
@Composable
private fun MdText(text: AnnotatedString, fontSize: TextUnit, lineHeight: TextUnit, fontWeight: FontWeight? = null, softWrap: Boolean = true, modifier: Modifier = Modifier) {
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val codes = remember(text) { text.getStringAnnotations(CODE, 0, text.length) }
    val fill = C.ink.copy(alpha = 0.07f)
    Text(
        text, color = C.ink, fontSize = fontSize, lineHeight = lineHeight, fontWeight = fontWeight, softWrap = softWrap, onTextLayout = { layout = it },
        modifier = modifier.drawBehind {
            val l = layout ?: return@drawBehind
            val em = fontSize.toPx() * CODE_EM.toFloat()
            val corner = CornerRadius(5.dp.toPx())
            for (a in codes) {
                var start = a.start
                while (start < a.end) {
                    val line = l.getLineForOffset(start)
                    val end = minOf(a.end, l.getLineEnd(line))
                    val left = l.getHorizontalPosition(start, true)
                    val right = if (end < a.end) l.getLineRight(line) else l.getHorizontalPosition(end, true).let { if (it <= left) l.getLineRight(line) else it }
                    val base = l.getLineBaseline(line)
                    drawRoundRect(fill, Offset(left, base - em * 1.02f), Size(right - left, em * 1.36f), corner)
                    if (end <= start) break
                    start = end
                }
            }
        },
    )
}

private fun Double.em() = androidx.compose.ui.unit.TextUnit(this.toFloat(), androidx.compose.ui.unit.TextUnitType.Em)
