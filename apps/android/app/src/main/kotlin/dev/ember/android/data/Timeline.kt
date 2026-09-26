// An agent's transcript read for people (after web/src/History.tsx and the
// activity in web/src/Chat.tsx): the execution history's items, and the few
// rows that say what a running turn is doing.
package dev.ember.android.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

fun toolName(tool: String?): String = (tool ?: "").replace(Regex("^mcp__ember__|^ember__|^ember\\."), "")

private enum class Category(val verb: String, val unit: String, val doing: String) {
    Read("读取", "个文件", "正在读取文件"), Search("搜索", "次", "正在搜索"), Edit("编辑", "个文件", "正在编辑文件"),
    Command("运行", "条命令", "正在运行命令"), Web("访问", "个网页", "正在访问网页"), Agent("派出", "个子 agent", "正在派出子 agent"),
    Thread("读取 thread", "次", "正在读取对话"), Other("其他", "项", "正在执行操作"),
}

private fun categorize(tool: String?): Category {
    val name = toolName(tool)
    return when {
        Regex("^(Read|NotebookRead|view_image)$").matches(name) -> Category.Read
        Regex("^(Glob|Grep|LS|ToolSearch)$").matches(name) -> Category.Search
        Regex("^(Edit|MultiEdit|Write|NotebookEdit|apply_patch)$").matches(name) -> Category.Edit
        Regex("^(Bash|BashOutput|KillShell|exec_command|shell|local_shell|write_stdin|unified_exec)$").matches(name) -> Category.Command
        Regex("^(WebFetch|WebSearch|web_search)$").matches(name) -> Category.Web
        Regex("^(Task|Agent|spawn_agent)$").matches(name) -> Category.Agent
        name == "chat_history" -> Category.Thread
        else -> Category.Other
    }
}

private fun args(text: String): JsonObject? = try {
    EmberJson.parseToJsonElement(text) as? JsonObject
} catch (_: IllegalArgumentException) {
    null
}

private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

/** A value being written as JSON, read before it is complete: the string at `field`, as far as it has arrived. */
fun partialString(json: String, field: String): String? {
    val m = Regex("\"$field\"\\s*:\\s*\"").find(json) ?: return null
    val out = StringBuilder()
    var i = m.range.last + 1
    while (i < json.length) {
        val c = json[i]
        if (c == '"') return out.toString()
        if (c != '\\') { out.append(c); i++; continue }
        val next = json.getOrNull(++i) ?: break
        when (next) {
            'n' -> out.append('\n')
            't' -> out.append('\t')
            'u' -> {
                if (i + 4 >= json.length) break
                out.append(json.substring(i + 1, i + 5).toInt(16).toChar())
                i += 4
            }
            else -> out.append(next)
        }
        i++
    }
    return out.toString()
}

/** What a running tool call is doing: its own description when it has one, else its kind. */
fun activityText(tool: String?, input: String): String {
    partialString(input, "description")?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
    if (toolName(tool) == "chat_post") return "正在写回复"
    return categorize(tool).doing
}

/** One line that says what a call did: the command, the file, the pattern. */
private fun hint(entry: TimelineEntry): String {
    val a = args(entry.text) ?: return entry.text.lineSequence().first().take(160)
    val value = listOf("command", "cmd", "file_path", "path", "pattern", "url", "query", "description", "prompt").firstNotNullOfOrNull { k ->
        when (val v = a[k]) {
            is JsonPrimitive -> v.content
            is JsonArray -> v.joinToString(" ") { (it as? JsonPrimitive)?.content ?: "" }
            else -> null
        }
    } ?: ""
    return value.lineSequence().first().take(160)
}

private fun describe(entry: TimelineEntry): String? = args(entry.text)?.string("description")?.trim()?.takeIf { it.isNotEmpty() }?.lineSequence()?.first()?.take(160)

private fun fileOf(entry: TimelineEntry): String? = args(entry.text)?.let { it.string("file_path") ?: it.string("path") ?: it.string("notebook_path") }

// ── the running turn's rows ────────────────────────────────────────────

data class ActivityRow(val key: String, val text: String, val live: Boolean)

/**
 * Execution history since the last message the agent received, then what is
 * still streaming. A reply being written shows as the message itself, not a
 * row; recording state is left out.
 */
fun activityRows(timeline: List<TimelineEntry>, live: List<LiveStep>, phase: ShownPhase?): List<ActivityRow> {
    var start = timeline.size
    while (start > 0 && !(timeline[start - 1].kind == "user" && !timeline[start - 1].subagent)) start--
    val rows = mutableListOf<ActivityRow>()
    timeline.drop(start).forEachIndexed { i, e ->
        if (e.subagent) return@forEachIndexed
        val text = when (e.kind) {
            "tool_call" -> when (toolName(e.tool)) {
                "chat_state" -> null
                "chat_post" -> "发出回复"
                "chat_history" -> "查看对话"
                else -> activityText(e.tool, e.text).removePrefix("正在")
            }
            "thinking" -> "思考"
            else -> null
        }
        if (text != null) rows += ActivityRow("t${start + i}", text, false)
    }
    for (s in live) {
        if (s.ended || s.subagent || s.step == "text") continue
        val name = toolName(s.tool)
        if (s.step == "tool" && (name == "chat_post" || name == "chat_state")) continue
        rows += ActivityRow(s.id, if (s.step == "thinking") "正在思考" else activityText(s.tool, s.input), true)
    }
    if (rows.none { it.live } && phase != null) {
        val waiting = when (phase.phase) { "starting" -> "正在启动"; "requesting" -> "等待模型响应"; "responding" -> "正在思考"; else -> null }
        if (waiting != null) rows += ActivityRow("phase-${phase.phase}-${phase.since}", waiting, true)
    }
    return rows
}

/** The reply the agent is writing to this chat right now, as far as it has streamed. */
fun writingNow(live: List<LiveStep>): String? =
    live.firstOrNull { it.step == "tool" && !it.ended && toolName(it.tool) == "chat_post" }?.let { partialString(it.input, "text") }?.takeIf { it.isNotEmpty() }

// ── the execution history ──────────────────────────────────────────────

data class Step(val call: TimelineEntry, var result: TimelineEntry?)

sealed interface HistoryItem {
    /** A message the agent received: who sent it and what it said. */
    data class Received(val from: String, val text: String) : HistoryItem
    data class Text(val text: String) : HistoryItem
    data class Post(val text: String, val kind: String?, val failed: Boolean) : HistoryItem
    data class Mark(val kind: String) : HistoryItem
    data class Group(val steps: List<Step>, val thinking: List<TimelineEntry>) : HistoryItem {
        /** Named by its latest call: its description, else what it did and to what. */
        val summary: String get() {
            val last = steps.lastOrNull() ?: return "思考：${thinking.firstOrNull()?.text?.lineSequence()?.firstOrNull { it.isNotBlank() }?.take(80) ?: ""}"
            val c = categorize(last.call.tool)
            val text = describe(last.call) ?: "${if (c == Category.Other) toolName(last.call.tool) else c.verb} ${hint(last.call)}".trim()
            return if (steps.size == 1) text else "$text · 共 ${steps.size} 项"
        }
        val counts: String get() {
            val seen = linkedMapOf<Category, MutableSet<String>>()
            steps.forEachIndexed { i, s ->
                val c = categorize(s.call.tool)
                seen.getOrPut(c) { mutableSetOf() } += (if (c == Category.Read || c == Category.Edit) fileOf(s.call) else null) ?: "#$i"
            }
            return seen.entries.joinToString("、") { (c, v) -> "${c.verb} ${v.size} ${c.unit}" }
        }
        val failed: Int get() = steps.count { it.result?.ok == false }
        val pending: Int get() = steps.count { it.result == null }
    }
}

private val MESSAGE = Regex("<message ([^>]*)>\\n?([\\s\\S]*?)\\n?</message>")

/** A prompt ember built, split into the chat messages it carried and ember's own words around them. */
fun parsePrompt(text: String, person: (String) -> String): List<HistoryItem.Received> {
    val out = mutableListOf<HistoryItem.Received>()
    val note = MESSAGE.replace(text) { m ->
        val from = Regex("from=\"([^\"]*)\"").find(m.groupValues[1])?.groupValues?.get(1)?.replace("&quot;", "\"")?.replace("&amp;", "&") ?: ""
        val id = Regex("\\(([^()\\s]+)\\)$").find(from)?.groupValues?.get(1) ?: from
        val name = Regex("^(.*) \\([^()]*\\)$").find(from)?.groupValues?.get(1)?.takeIf { it.isNotBlank() } ?: person(id)
        out += HistoryItem.Received(name, m.groupValues[2])
        ""
    }.replace(Regex("^\\(Thread \\S+ had messages before you were brought in;.*\\)$", RegexOption.MULTILINE), "").trim()
    return if (note.isNotEmpty()) listOf(HistoryItem.Received("ember", note)) + out else out
}

fun historyItems(entries: List<TimelineEntry>, person: (String) -> String): List<HistoryItem> {
    val items = mutableListOf<HistoryItem>()
    val steps = HashMap<String, Step>()
    var group: MutableList<Step>? = null
    var thinking: MutableList<TimelineEntry>? = null
    var lastStep: Step? = null
    fun openGroup() {
        if (group == null) {
            val g = mutableListOf<Step>(); val t = mutableListOf<TimelineEntry>()
            group = g; thinking = t
            items += HistoryItem.Group(g, t)
        }
    }
    val posts = mutableListOf<Pair<Int, Step>>()
    for (e in entries) {
        when (e.kind) {
            "tool_result" -> {
                val step = e.callId?.let { steps[it] } ?: lastStep?.takeIf { it.result == null }
                step?.result = e
            }
            "tool_call" -> {
                val step = Step(e, null)
                e.callId?.let { steps[it] = step }
                lastStep = step
                val name = toolName(e.tool)
                val a = args(e.text)
                if (name == "chat_post" && a?.string("text") != null && !e.subagent) {
                    posts += items.size to step
                    items += HistoryItem.Post(a.string("text")!!, a.string("kind"), false)
                    group = null
                } else if (name == "chat_state" && a?.string("kind") != null && !e.subagent) {
                    items += HistoryItem.Mark(a.string("kind")!!)
                    group = null
                } else {
                    openGroup(); group!! += step
                }
            }
            "thinking" -> { openGroup(); thinking!! += e }
            else -> {
                group = null
                if (e.kind == "user") items += parsePrompt(e.text, person) else items += HistoryItem.Text(e.text)
            }
        }
    }
    // A post that failed says so once its result is in.
    for ((i, step) in posts) (items[i] as HistoryItem.Post).let { items[i] = it.copy(failed = step.result?.ok == false) }
    return items
}

/** The steps of a group, for its expanded view: what each call said it does, or its tool and argument. */
fun stepLabel(step: Step): Pair<String, String?> = describe(step.call)?.let { it to null } ?: (toolName(step.call.tool) to hint(step.call))

