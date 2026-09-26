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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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
        is Paragraph -> Text(inline(node), color = C.ink, fontSize = size.sp, lineHeight = (size * 1.6).sp)
        // Headings are the body's size, bolder, with room above (as the web draws h1–h4).
        is Heading -> Text(inline(node), color = C.ink, fontSize = (size + 1).sp, lineHeight = (size * 1.5).sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
        is BulletList -> ListBlock(node, size) { _, item -> taskMark(item) ?: "•" }
        is OrderedList -> ListBlock(node, size) { i, item -> taskMark(item) ?: "${(node.markerStartNumber ?: 1) + i}." }
        is BlockQuote -> Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(2.dp).fillMaxHeight().clip(RoundedCornerShape(1.dp)).background(C.line))
            Box(Modifier.padding(start = 10.dp)) { Blocks(node.children(), size) }
        }
        is FencedCodeBlock -> CodeBlock(node.literal.trimEnd('\n'))
        is IndentedCodeBlock -> CodeBlock(node.literal.trimEnd('\n'))
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

@Composable
private fun CodeBlock(code: String) {
    val context = LocalContext.current
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface2).border(1.dp, C.line, RoundedCornerShape(12.dp))) {
        Box(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = 12.dp, end = 40.dp, top = 10.dp, bottom = 10.dp)) {
            Text(code, style = Mono, color = C.ink, softWrap = false)
        }
        Box(
            Modifier.align(Alignment.TopEnd).padding(4.dp).size(30.dp).clip(RoundedCornerShape(8.dp)).clickable {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("code", code))
            },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Copy, 14.dp, C.subtle) }
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
                        Text(
                            cell?.let { inline(it) } ?: AnnotatedString(""), fontSize = 13.sp, color = C.ink, softWrap = false,
                            fontWeight = if (cell?.isHeader == true) FontWeight.SemiBold else null,
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
    val code = SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 0.88.em(), background = C.chip)
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

private fun Double.em() = androidx.compose.ui.unit.TextUnit(this.toFloat(), androidx.compose.ui.unit.TextUnitType.Em)
