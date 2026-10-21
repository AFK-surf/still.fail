// The core's Markdown (client/core-ts/src/markdown.ts, its tree `Md`) of a fixture's words, for FakeCore's `markdown`:
// the app reads no Markdown itself, and the tests have no core to read it. Made with commonmark, words as themselves
// (not runs of the text): close enough to the core's for what the tests look at.
package fail.still.android.motion

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.ext.gfm.tables.TableBlock
import org.commonmark.ext.gfm.tables.TableCell
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
import org.commonmark.node.Image
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListBlock
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text
import org.commonmark.node.ThematicBreak
import org.commonmark.parser.Parser

private val parser = Parser.builder().extensions(listOf(TablesExtension.create(), StrikethroughExtension.create(), TaskListItemsExtension.create())).build()

/** `text` as the core's tree of it. */
fun fakeMd(text: String): JsonArray = JsonArray(parser.parse(text).kids().flatMap(::block))

private fun Node.kids(): List<Node> = generateSequence(firstChild) { it.next }.toList()
private fun s(v: String) = JsonPrimitive(v)
private fun node(kind: String, kids: List<JsonElement>? = null, attrs: Map<String, JsonElement>? = null): JsonElement =
    JsonArray(listOfNotNull(s(kind), kids?.let(::JsonArray), attrs?.let(::JsonObject)))

private fun block(n: Node): List<JsonElement> = when (n) {
    is Paragraph -> listOf(node("p", inlines(n.kids())))
    is Heading -> listOf(node("h", inlines(n.kids()), mapOf("depth" to JsonPrimitive(n.level))))
    is BlockQuote -> listOf(node("quote", n.kids().flatMap(::block)))
    is BulletList, is OrderedList -> {
        val list = n as ListBlock
        val items = list.kids().filterIsInstance<ListItem>().map { item ->
            val task = (item.firstChild as? TaskListItemMarker ?: (item.firstChild as? Paragraph)?.firstChild as? TaskListItemMarker)?.isChecked
            val inner = if (list.isTight) item.kids().flatMap { if (it is Paragraph) inlines(it.kids()) else block(it) } else item.kids().flatMap(::block)
            node("li", inner, task?.let { mapOf("checked" to JsonPrimitive(it)) })
        }
        val attrs = if (n is OrderedList) buildMap { put("ordered", JsonPrimitive(true)); (n.markerStartNumber ?: 1).takeIf { it != 1 }?.let { put("start", JsonPrimitive(it)) } } else null
        listOf(node("list", items, attrs))
    }
    is FencedCodeBlock -> {
        val lang = n.info?.trim()?.substringBefore(' ')?.ifEmpty { null }
        listOf(node("pre", attrs = buildMap { put("code", s(n.literal.removeSuffix("\n"))); lang?.let { put("lang", s(it)) } }))
    }
    is IndentedCodeBlock -> listOf(node("pre", attrs = mapOf("code" to s(n.literal.removeSuffix("\n")))))
    is TableBlock -> {
        val rows = n.kids().flatMap { it.kids() }.filterIsInstance<TableRow>()
        listOf(node("table", rows.map { r -> node("tr", r.kids().filterIsInstance<TableCell>().map { c -> node(if (c.isHeader) "th" else "td", inlines(c.kids())) }) }, mapOf("align" to JsonArray(emptyList()))))
    }
    is ThematicBreak -> listOf(node("hr"))
    else -> n.kids().flatMap(::block)
}

/** Words with their bare web addresses as links, as the core has them (bareLinks.ts). */
private fun linked(words: String): List<JsonElement> {
    val out = mutableListOf<JsonElement>()
    var at = 0
    for (r in fail.still.android.ui.bareLinks(words)) {
        if (r.first > at) out += s(words.substring(at, r.first))
        val url = words.substring(r)
        out += node("a", listOf(s(url)), mapOf("href" to s(url)))
        at = r.last + 1
    }
    if (at < words.length) out += s(words.substring(at))
    return out
}

private fun inlines(nodes: List<Node>, inLink: Boolean = false): List<JsonElement> = nodes.flatMap { n ->
    when (n) {
        is Text -> if (inLink) listOf(s(n.literal)) else linked(n.literal)
        is SoftLineBreak -> listOf(s("\n"))
        is HardLineBreak -> listOf(node("br"))
        is Code -> listOf(node("code", attrs = mapOf("content" to s(n.literal))))
        is Emphasis -> listOf(node("i", inlines(n.kids(), inLink)))
        is StrongEmphasis -> listOf(node("b", inlines(n.kids(), inLink)))
        is Strikethrough -> listOf(node("s", inlines(n.kids(), inLink)))
        is Link -> listOf(node("a", inlines(n.kids(), inLink = true), mapOf("href" to s(n.destination))))
        is Image -> listOf(node("img", attrs = buildMap { put("src", s(n.destination)); (n.firstChild as? Text)?.literal?.let { put("alt", s(it)) } }))
        is TaskListItemMarker -> emptyList()
        else -> inlines(n.kids(), inLink)
    }
}
