// A tool call in the execution history, drawn by what it is rather than as its arguments' JSON (web/src/ToolStep.tsx):
// a command as a command, an edit as a diff, a file written or read as highlighted code, a patch as its lines, a plan
// as a list; anything else as its fields, one to a row. The core gives each step its call (the arguments, pretty JSON
// or the tool's own free text) and its result as text.
package fail.still.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

@OptIn(ExperimentalSerializationApi::class)
private val pretty = Json { prettyPrint = true; prettyPrintIndent = "  " }
private val lenient = Json { isLenient = false }

private fun parse(text: String): JsonElement? {
    val t = text.trim()
    if (!t.startsWith("{") && !t.startsWith("[")) return null
    try { return lenient.parseToJsonElement(t) } catch (_: Exception) { /* cut short, perhaps */ }
    val cut = Regex("\\n… \\(\\d+ more characters\\)$").find(t) ?: return null
    return try { lenient.parseToJsonElement(close(t.substring(0, cut.range.first))) } catch (_: Exception) { null }
}

/**
 * JSON the station cut short (a long call is kept to its first 4000 characters, then `… (n more characters)`), closed
 * where it stops: the string it was in ends with an ellipsis, and what was open is closed.
 */
private fun close(json: String): String {
    val open = ArrayDeque<Char>()
    var quoted = false
    var escaped = false
    for (c in json) {
        when {
            escaped -> escaped = false
            quoted -> if (c == '\\') escaped = true else if (c == '"') quoted = false
            c == '"' -> quoted = true
            c == '{' -> open.addLast('}')
            c == '[' -> open.addLast(']')
            c == '}' || c == ']' -> open.removeLastOrNull()
        }
    }
    var out = json
    if (quoted) out = "${if (escaped) out.dropLast(1) else out}…\""
    out = out.trimEnd()
    if (out.endsWith(":")) out += "null" else if (out.endsWith(",")) out = out.dropLast(1)
    return out + open.reversed().joinToString("")
}

private fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonElement?.num(): Double? = (this as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
private fun JsonElement.isScalar() = this is JsonPrimitive && this !is JsonNull

/** A scalar as written: a string's words, a number or true as JSON has them. */
private fun JsonPrimitive.text(): String = if (isString) content else content

/** The language a file is in, by its extension. */
private fun languageOf(path: String?): String? {
    val ext = Regex("\\.(\\w+)$").find(path ?: "")?.groupValues?.get(1)?.lowercase() ?: return null
    return mapOf("mjs" to "js", "cjs" to "js", "mts" to "ts", "yml" to "yaml", "zsh" to "sh", "bash" to "sh", "h" to "c", "hpp" to "cpp")[ext] ?: ext
}

/** A command as it would be typed: `["bash", "-lc", "ls"]` is `ls`. */
private fun commandOf(a: JsonObject): String? {
    val c = a["command"] ?: a["cmd"]
    c.str()?.let { return it }
    if (c is JsonArray && c.all { it.str() != null }) {
        val parts = c.map { it.str()!! }
        return if (Regex("^(ba|z)?sh$").matches(parts.firstOrNull()?.substringAfterLast('/') ?: "") && parts.getOrNull(1) == "-lc") parts.drop(2).joinToString(" ") else parts.joinToString(" ")
    }
    return null
}

// ── the parts (ToolStep.css.ts) ────────────────────────────────────────

private val red @Composable get() = if (C.dark) Color(0xFFF68482) else Color(0xFFA12F35)
private val redBg @Composable get() = if (C.dark) Color(0xFF442322) else Color(0xFFFFF0EF)
private val green @Composable get() = if (C.dark) Color(0xFF68C894) else Color(0xFF006A3F)
private val greenBg @Composable get() = if (C.dark) Color(0xFF1B3426) else Color(0xFFE7F6ED)

/** The quiet tinted box code and output sit in, kept to `max` high (it scrolls within). */
@Composable
private fun Boxed(max: Dp = 360.dp, ground: Color = codeGround, vertical: Dp = 8.dp, horizontal: Dp = 12.dp, content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(ground).heightIn(max = max).verticalScroll(rememberScrollState()).padding(horizontal = horizontal, vertical = vertical)) { content() }
}

private val mono = FontFamily.Monospace

/** Highlighted code (a command, a file written, a file read), as markdown shows it but wrapping and capped in height. */
@Composable
private fun Block(text: String, language: String?) {
    val dark = C.dark
    val colored = remember(text, language, dark) { highlight(text, language, dark) }
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(codeGround).heightIn(max = 360.dp).verticalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 8.dp)) {
        Text(colored, fontFamily = mono, fontSize = 12.sp, lineHeight = 18.6.sp, color = C.ink)
    }
}

@Composable
private fun Prose(text: String) {
    Boxed(max = 100000.dp) { Markdown(text, size = 12) }
}

/** The small facts beside the main thing (a timeout, a directory, a flag), as `key value`. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Facts(a: JsonObject, skip: List<String>) {
    val rest = a.entries.filter { (k, v) -> k !in skip && v.isScalar() && (v as JsonPrimitive).booleanOrNull != false }
    if (rest.isEmpty()) return
    FactRow(rest.map { (k, v) -> k to (v as JsonPrimitive).let { p -> if (p.booleanOrNull == true) null else p.text() } })
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FactRow(facts: List<Pair<String, String?>>) {
    val subtle = webSubtle
    val muted = webMuted
    FlowRow(Modifier.padding(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        facts.forEach { (k, v) ->
            Text(buildAnnotatedString {
                append(k)
                if (v != null) { append(" "); withStyle(SpanStyle(fontWeight = FontWeight.Medium, color = muted, fontFamily = mono)) { append(v) } }
            }, fontSize = 11.sp, color = subtle)
        }
    }
}

@Composable
private fun PathLine(path: String, extra: String? = null) {
    Row(Modifier.padding(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
        Text(path, fontFamily = mono, fontSize = 12.sp, lineHeight = 18.sp, color = C.ink, modifier = Modifier.weight(1f, fill = false))
        if (extra != null) Text(extra, fontSize = 11.sp, lineHeight = 18.sp, color = webSubtle)
    }
}

/** Lines taken out and put in, with the lines both share at the ends as context. */
@Composable
private fun Diff(from: String, to: String) {
    val a = from.split("\n")
    val b = to.split("\n")
    var head = 0
    while (head < a.size && head < b.size && a[head] == b[head]) head++
    var tail = 0
    while (tail < a.size - head && tail < b.size - head && a[a.size - 1 - tail] == b[b.size - 1 - tail]) tail++
    val rows = a.take(head).map { ' ' to it } + a.subList(head, a.size - tail).map { '-' to it } + b.subList(head, b.size - tail).map { '+' to it } + a.takeLast(tail).map { ' ' to it }
    Lines(rows)
}

@Composable
private fun Lines(rows: List<Pair<Char, String>>) {
    Boxed(vertical = 6.dp, horizontal = 0.dp) {
        Column {
            rows.forEach { (mark, text) ->
                val ground = when (mark) { '-' -> redBg; '+' -> greenBg; else -> Color.Transparent }
                val ink = when (mark) { '-', '+' -> C.ink; '@' -> C.blue; else -> webMuted }
                Box(Modifier.fillMaxWidth().padding(top = if (mark == '@') 4.dp else 0.dp).background(ground)) {
                    if (mark == '-' || mark == '+') Text(mark.toString(), fontFamily = mono, fontSize = 12.sp, lineHeight = 18.6.sp, color = if (mark == '-') red else green, modifier = Modifier.padding(start = 9.dp))
                    Text(text.ifEmpty { " " }, fontFamily = mono, fontSize = 12.sp, lineHeight = 18.6.sp, color = ink, fontWeight = if (mark == '@') FontWeight.Medium else null, modifier = Modifier.padding(start = 22.dp, end = 12.dp))
                }
            }
        }
    }
}

/** A patch as apply_patch takes it: file headers, and lines put in and taken out. */
@Composable
private fun Patch(text: String) {
    val rows = text.removeSuffix("\n").split("\n").mapNotNull { line ->
        when {
            Regex("^\\*\\*\\* (Add|Update|Delete) File:|^\\*\\*\\* Move to:|^@@").containsMatchIn(line) -> '@' to line
            Regex("^\\*\\*\\* (Begin|End) Patch").containsMatchIn(line) -> null
            line.startsWith("+") -> '+' to line.drop(1)
            line.startsWith("-") -> '-' to line.drop(1)
            else -> ' ' to line.removePrefix(" ")
        }
    }
    Lines(rows)
}

/** A list of things to do, as TodoWrite and update_plan give it. */
@Composable
private fun Plan(items: List<Pair<String, String>>) {
    val accent = C.accent
    val greenMark = green
    val subtle = webSubtle
    val muted = webMuted
    Column(Modifier.padding(horizontal = 2.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        items.forEach { (text, status) ->
            Row {
                Text(
                    when (status) { "completed" -> "✓"; "in_progress" -> "›"; else -> "·" }, fontSize = 12.sp, lineHeight = 18.sp,
                    color = when (status) { "completed" -> greenMark; "in_progress" -> accent; else -> subtle }, modifier = Modifier.width(16.dp),
                )
                Text(
                    text, fontSize = 12.sp, lineHeight = 18.sp,
                    color = if (status == "completed") muted else C.ink,
                    fontWeight = if (status == "in_progress") FontWeight.SemiBold else null,
                    textDecoration = if (status == "completed") TextDecoration.LineThrough else null,
                )
            }
        }
    }
}

/** Fields one to a row: short ones inline, long text as a block, nested data as compact JSON. */
@Composable
private fun Fields(a: JsonObject, skip: List<String> = emptyList()) {
    val rows = a.entries.filter { (k, v) -> k !in skip && v !is JsonNull && v.str() != "" }
    if (rows.isEmpty()) return None(t("android-misc.tool.noArgs"))
    Column(Modifier.padding(horizontal = 2.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        rows.forEach { (k, v) ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(k, fontSize = 11.sp, lineHeight = 18.sp, color = webSubtle, modifier = Modifier.widthIn(min = 64.dp, max = 120.dp))
                Box(Modifier.weight(1f)) {
                    val s = v.str()
                    when {
                        s != null && (s.contains('\n') || s.length > 120) -> Boxed(max = 240.dp) { Text(s, fontSize = 12.sp, lineHeight = 19.2.sp, color = C.ink) }
                        s != null -> Text(s, fontFamily = mono, fontSize = 12.sp, lineHeight = 18.sp, color = C.ink)
                        v is JsonObject || v is JsonArray -> JsonBlock(v)
                        else -> Text((v as JsonPrimitive).text(), fontFamily = mono, fontSize = 12.sp, lineHeight = 18.sp, color = C.ink)
                    }
                }
            }
        }
    }
}

@Composable
private fun JsonBlock(v: JsonElement) {
    Boxed(max = 240.dp) { Text(pretty.encodeToString(JsonElement.serializer(), v), fontFamily = mono, fontSize = 12.sp, lineHeight = 18.6.sp, color = C.ink) }
}

@Composable
private fun None(text: String) = Text(text, fontSize = 11.sp, color = webSubtle, modifier = Modifier.padding(horizontal = 2.dp))

/** A step opened: what the call asked for, then what came back. */
@Composable
fun ToolStepBody(name: String, call: String, said: Boolean, result: String?, failed: Boolean) {
    Column(Modifier.fillMaxWidth().padding(start = 6.dp, end = 6.dp, top = 4.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { ToolCall(name, call, said) }
        if (result != null) ToolResult(name, call, result, failed)
    }
}

/** What a call asked for. `said`: its description already shows as the step's name. */
@Composable
fun ToolCall(name: String, call: String, said: Boolean) {
    val a = parse(call) as? JsonObject
    if (a == null) {
        if (Regex("^\\*\\*\\* Begin Patch").containsMatchIn(call.trim())) return Patch(call.trim())
        if (call.isNotBlank()) Block(call, if (name == "exec") "js" else null)
        return
    }
    val skip = if (said) listOf("description") else emptyList()
    val command = commandOf(a)
    val file = a["file_path"].str() ?: a["notebook_path"].str() ?: a["path"].str()
    val edits = a["edits"] as? JsonArray
    val list = (a["todos"] as? JsonArray) ?: (a["plan"] as? JsonArray)
    val prompt = a["prompt"].str()
    val text = a["text"].str()
    when {
        command != null -> { Block(command, "sh"); Facts(a, skip + listOf("command", "cmd")) }
        file != null && a["old_string"].str() != null && a["new_string"].str() != null -> {
            PathLine(file, if ((a["replace_all"] as? JsonPrimitive)?.booleanOrNull == true) t("android-misc.tool.replaceAll") else null)
            Diff(a["old_string"].str()!!, a["new_string"].str()!!)
        }
        file != null && edits != null -> {
            PathLine(file)
            edits.filterIsInstance<JsonObject>().forEach { e -> Diff(e["old_string"].str() ?: "", e["new_string"].str() ?: "") }
        }
        file != null && a["content"].str() != null -> { PathLine(file); Block(a["content"].str()!!, languageOf(file)) }
        list != null -> {
            a["explanation"].str()?.let { Prose(it) }
            Plan(list.filterIsInstance<JsonObject>().map { t -> (t["content"].str() ?: t["step"].str() ?: "") to (t["status"].str() ?: "") })
        }
        prompt != null && (name == "Agent" || name == "Task" || prompt.length > 200) -> { Facts(a, skip + "prompt"); Prose(prompt) }
        text != null && text.isNotEmpty() && a.values.count { (it.str()?.length ?: 0) > 120 } <= 1 -> { Facts(a, skip + "text"); Prose(text) }
        file != null && a.keys.all { it in listOf("file_path", "path", "notebook_path", "offset", "limit") + skip } -> {
            val from = a["offset"].num()?.toLong()
            val count = a["limit"].num()?.toLong()
            val range = if (from != null && count != null) t("android-misc.tool.linesFrom", "from" to from, "n" to count)
                else from?.let { t("android-misc.tool.from", "from" to it) } ?: count?.let { t("android-misc.tool.lines", "n" to it) }
            PathLine(file, range)
        }
        a["pattern"].str() != null || a["query"].str() != null || a["url"].str() != null -> {
            val key = listOf("pattern", "query", "url").first { a[it].str() != null }
            Text(a[key].str()!!, fontFamily = mono, fontSize = 12.sp, lineHeight = 18.sp, color = C.ink, modifier = Modifier.padding(horizontal = 2.dp))
            Fields(a, skip + key)
        }
        else -> Fields(a, skip)
    }
}

/** Codex's command output: how it ended in a header, then the output. */
private fun commandOutput(text: String): Pair<List<String>, String>? {
    val m = Regex("^(?:Chunk ID: .*\\n)?(?:Wall time: (.*)\\n)?(?:Process exited with code (-?\\d+)\\n)?(?:Original token count: .*\\n)?Output:\\n?").find(text) ?: return null
    val wall = m.groups[1]?.value
    val code = m.groups[2]?.value
    if (wall == null && code == null) return null
    return listOfNotNull(code?.let { t("android-misc.tool.exitCode", "code" to it) }, wall?.let { t("android-misc.tool.took", "time" to it) }) to text.substring(m.range.last + 1)
}

/** Claude Code's Read: `cat -n` lines (`   12→text` or `   12\ttext`), without their numbers; what follows them is left out. */
private fun readLines(text: String): String? {
    val lines = text.split("\n")
    val numbered = Regex("^\\s*\\d+(→|\\t)")
    val end = lines.indexOfFirst { !numbered.containsMatchIn(it) }.let { if (it < 0) lines.size else it }
    if (end == 0) return null
    return lines.take(end).joinToString("\n") { it.replaceFirst(numbered, "") }
}

@Composable
private fun Output(text: String, failed: Boolean) {
    Boxed(ground = if (failed) redBg else codeGround) {
        Text(text, fontFamily = mono, fontSize = 12.sp, lineHeight = 18.6.sp, color = if (failed) C.ink else webMuted)
    }
}

/** What a call gave back. */
@Composable
fun ToolResult(name: String, call: String, result: String, failed: Boolean) {
    if (result.isBlank()) return None(t("android-misc.tool.noOutput"))
    val args = parse(call) as? JsonObject
    val file = args?.let { it["file_path"].str() ?: it["path"].str() }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val codex = commandOutput(result)
        val read = if (!failed && (name == "Read" || name == "NotebookRead")) readLines(result) else null
        val parsed = if (failed || codex != null || read != null) null else parse(result)
        when {
            codex != null -> {
                if (codex.first.isNotEmpty()) FactRow(codex.first.map { it to null })
                if (codex.second.isNotBlank()) Output(codex.second, failed) else None(t("android-misc.tool.noOutput"))
            }
            read != null -> Block(read, languageOf(file))
            parsed is JsonObject -> Fields(parsed)
            parsed != null -> JsonBlock(parsed)
            else -> Output(result, failed)
        }
    }
}
