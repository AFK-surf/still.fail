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

fun status(s: SessionSummary): Status = when {
    s.process == "running" -> Status.Running
    s.pending > 0 -> Status.Queued
    else -> turnResult(s.lastTurn).let { if (it == Status.Running) Status.Unexpected else it } // a turn left open by a crash
}

private val SLACK_MENTION = Regex("<@[A-Z0-9]+>")

/** What a chat is called: its given title, else its first message. */
fun sessionTitle(s: SessionSummary): String =
    s.title?.takeIf { it.isNotBlank() } ?: s.firstText?.replace(SLACK_MENTION, "")?.replace(Regex("\\s+"), " ")?.trim()?.takeIf { it.isNotEmpty() } ?: "（还没有消息）"

private fun hhmm(ms: Long) = Calendar.getInstance().apply { timeInMillis = ms }.let { String.format(Locale.ROOT, "%02d:%02d", it.get(Calendar.HOUR_OF_DAY), it.get(Calendar.MINUTE)) }

fun relativeTime(ms: Long, now: Long = System.currentTimeMillis()): String {
    val seconds = (now - ms) / 1000
    if (seconds < 45) return "刚刚"
    val minutes = (seconds + 30) / 60
    if (minutes < 60) return "$minutes 分钟前"
    val hours = (minutes + 30) / 60
    if (hours < 24) return "$hours 小时前"
    val c = Calendar.getInstance().apply { timeInMillis = ms }
    return if (hours < 48) "昨天 ${hhmm(ms)}" else "${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日 ${hhmm(ms)}"
}

/** A row's time: minutes ago within the hour, then the clock, then the day. */
fun rowTime(ms: Long, daysAgo: Int, now: Long = System.currentTimeMillis()): String = when {
    now - ms < 3_600_000 -> relativeTime(ms, now)
    daysAgo == 0 -> hhmm(ms)
    else -> dayLabel(daysAgo, ms)
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

fun maker(model: String?): Maker {
    val m = model?.lowercase() ?: ""
    return when {
        Regex("gpt|codex|astra|o\\d").containsMatchIn(m) -> Maker.OpenAI
        Regex("claude|opus|sonnet|haiku").containsMatchIn(m) -> Maker.Anthropic
        "glm" in m -> Maker.Zhipu
        else -> Maker.DeepSeek
    }
}

val RUNTIME_LABEL = mapOf("claude" to "Claude Code", "codex" to "Codex")
val EFFORTS = mapOf("claude" to listOf("low", "medium", "high", "xhigh", "max"), "codex" to listOf("minimal", "low", "medium", "high", "xhigh"))
val EFFORT_LABEL = mapOf("minimal" to "最低", "low" to "低", "medium" to "中", "high" to "高", "xhigh" to "很高", "max" to "最高")
