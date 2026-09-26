// Turning ember's records into words people read (after web/src/format.ts).
package dev.ember.android.data

import java.util.Calendar
import java.util.Locale

enum class Status { Running, Queued, Final, Block, Failed, Aborted, Unexpected, Idle }

fun turnResult(turn: TurnSummary?): Status = when {
    turn == null -> Status.Idle
    turn.declared == "final" -> Status.Final
    turn.declared == "block" -> Status.Block
    turn.outcome == "failed" -> Status.Failed
    turn.outcome == "aborted" -> Status.Aborted
    turn.outcome == null -> if (turn.endedAt == null) Status.Running else Status.Unexpected
    else -> Status.Unexpected // completed without saying final or block
}

fun status(process: String, pending: Int, lastTurn: TurnSummary?): Status = when {
    process == "running" -> Status.Running
    pending > 0 -> Status.Queued
    else -> turnResult(lastTurn).let { if (it == Status.Running) Status.Unexpected else it } // a turn left open by a crash
}

fun status(s: SessionSummary): Status = status(s.process, s.pending, s.lastTurn)

val PROCESS_LABEL = mapOf("running" to "运行中", "warm" to "保温中", "cold" to "已释放")

/** Slack mentions and spacing removed, for use as a title or a one-line preview. */
fun cleanText(text: String?): String = (text ?: "").replace(Regex("<@[A-Z0-9]+>"), "").replace(Regex("\\s+"), " ").trim()

/** How an agent is named: it has no name, only its model and how hard it thinks. */
fun agentLabel(model: String?, effort: String?): String =
    listOfNotNull(model?.takeIf { it.isNotEmpty() } ?: "默认模型", effort?.let { "思考${EFFORT_LABEL[it] ?: it}" }).joinToString(" · ")

private fun hhmm(ms: Long) = Calendar.getInstance().apply { timeInMillis = ms }.let { String.format(Locale.ROOT, "%02d:%02d", it.get(Calendar.HOUR_OF_DAY), it.get(Calendar.MINUTE)) }

fun relativeTime(ms: Long, now: Long = System.currentTimeMillis()): String {
    val seconds = Math.round((now - ms) / 1000.0)
    if (seconds < 45) return "刚刚"
    val minutes = Math.round(seconds / 60.0)
    if (minutes < 60) return "$minutes 分钟前"
    val hours = Math.round(minutes / 60.0)
    if (hours < 24) return "$hours 小时前"
    val c = Calendar.getInstance().apply { timeInMillis = ms }
    return if (hours < 48) "昨天 ${hhmm(ms)}" else "${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日 ${hhmm(ms)}"
}

fun duration(ms: Long): String {
    if (ms < 1000) return "${ms}ms"
    val s = Math.round(ms / 1000.0)
    if (s < 60) return "$s 秒"
    val m = s / 60
    return if (m < 60) "$m 分 ${s % 60} 秒" else "${m / 60} 小时 ${m % 60} 分"
}

/** Groups by calendar day, as the web's chat list does: 今天, 昨天, 星期三, 9月20日. */
fun dayLabel(daysAgo: Int, at: Long): String {
    if (daysAgo == 0) return "今天"
    if (daysAgo == 1) return "昨天"
    val c = Calendar.getInstance().apply { timeInMillis = at }
    if (daysAgo < 7) return listOf("星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六")[c.get(Calendar.DAY_OF_WEEK) - 1]
    return "${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日"
}

/** Seconds, then minutes and seconds. */
fun elapsed(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return if (s < 60) "${s}s" else "${s / 60}m ${s % 60}s"
}

fun compactNumber(n: Long): String = when {
    n >= 1_000_000 -> String.format(Locale.ROOT, "%.1fM", n / 1_000_000.0).replace(".0M", "M")
    n >= 1000 -> String.format(Locale.ROOT, "%.1fK", n / 1000.0).replace(".0K", "K")
    else -> n.toString()
}

fun gb(bytes: Long) = "${bytes / (1024L * 1024 * 1024)} GB"

/** Agents are their model: the maker's mark, as on the web. */
enum class Maker { OpenAI, Anthropic, Zhipu, DeepSeek }

/** A model the marks here do not know (or none) shows its runtime's maker. */
fun maker(model: String?, runtime: String): Maker {
    val m = model?.lowercase() ?: ""
    return when {
        Regex("claude|opus|sonnet|haiku|fable").containsMatchIn(m) -> Maker.Anthropic
        Regex("gpt|^o\\d|codex|openai").containsMatchIn(m) -> Maker.OpenAI
        "deepseek" in m -> Maker.DeepSeek
        Regex("glm|zhipu").containsMatchIn(m) -> Maker.Zhipu
        runtime == "codex" -> Maker.OpenAI
        else -> Maker.Anthropic
    }
}

val RUNTIME_LABEL = mapOf("claude" to "Claude Code", "codex" to "Codex")
val EFFORTS = mapOf("claude" to listOf("low", "medium", "high", "xhigh", "max"), "codex" to listOf("minimal", "low", "medium", "high", "xhigh"))
val EFFORT_LABEL = mapOf("minimal" to "最低", "low" to "低", "medium" to "中", "high" to "高", "xhigh" to "很高", "max" to "最高")
