// The archive (web/src/pages/Archive.tsx): chats archived by hand or by the station once they idled (a day by
// default), of every station online in one list, newest first and grouped by the day they were archived. Each can be
// put back in the list, and one archived with its session deleted for good. Anything new said in a chat brings it
// back by itself. A row: its title with when (and where) at the end of its line, then what can be done with it; its
// last message the whole line under it. No lines between.
package fail.still.android.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.ArchivedChat
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.SectionHeader
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** An archived chat and the station it is on. */
private class ArchiveRow(val chat: ArchivedChat, val view: StationView)

/** One station's archive as read: its rows, or why it could not be. */
private sealed interface Loaded {
    class Rows(val rows: List<ArchiveRow>) : Loaded
    class Failed(val error: String) : Loaded
}

@Composable
fun ArchiveScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val online = stations.value.orEmpty().filter { it.online }
    val loaded = remember { mutableStateMapOf<String, Loaded>() }
    // Each station's archive, read once it is online (the list is not a topic: it is read when the page opens).
    for (view in online) {
        LaunchedEffect(view.station) {
            loaded[view.station] = try {
                Loaded.Rows(app.api(view.station).archivedChats().map { ArchiveRow(it, view) })
            } catch (e: CoreException) {
                Loaded.Failed(e.message)
            }
        }
    }
    val gone = { row: ArchiveRow ->
        (loaded[row.view.station] as? Loaded.Rows)?.let { of -> loaded[row.view.station] = Loaded.Rows(of.rows.filter { it !== row }) }
    }
    val restore = { row: ArchiveRow ->
        app.scope.launch {
            try {
                app.api(row.view.station).setArchived(row.chat.thread, row.chat.session, false)
                gone(row)
                app.toast = "已恢复到列表"
            } catch (e: CoreException) {
                app.toast = "没能恢复：${e.message}"
            }
        }
        Unit
    }
    val delete = { row: ArchiveRow ->
        confirm(app, "删除「${row.chat.title}」？", "它的会话、对话记录和 workspace 目录都会删掉，不能恢复。", "删除", danger = true) {
            app.api(row.view.station).deleteSession(row.chat.session)
            gone(row)
            app.toast = "已删除"
        }
    }
    val of = online.map { loaded[it.station] }
    val rows = of.flatMap { (it as? Loaded.Rows)?.rows.orEmpty() }.sortedByDescending { archivedAt(it.chat) }
    val errors = online.zip(of).mapNotNull { (view, got) -> (got as? Loaded.Failed)?.let { view to it.error } }
    val reading = of.any { it == null }
    // Which station a chat is on is said only where there is more than one to tell apart.
    val named = online.size > 1
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 24.dp)) {
        TopBack("会话", app::pop)
        LargeTitle(current.workspace.name, "已归档")
        // No hover to explain it on a phone: said at the top instead.
        Text(
            "手动归档的对话，和空闲超过一天、已经做完的对话（没在跑、没停在 block、没有未读）。对话里有新消息时会自动回到列表。",
            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        val note = when {
            stations.value == null -> stations.error?.message ?: "正在读取 station…"
            online.isEmpty() -> "没有在线的 station。"
            rows.isEmpty() && reading -> "正在读取…"
            rows.isEmpty() && errors.isEmpty() -> "没有归档的对话。"
            else -> null
        }
        errors.forEach { (view, error) -> Text((if (named) "${view.name}：" else "") + error, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
        if (note != null) Text(note, fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))
        days(rows).forEach { (label, items) ->
            SectionHeader(label)
            items.forEach { row -> ArchiveItem(row, named, { restore(row) }, { delete(row) }) }
        }
    }
}

@Composable
private fun ArchiveItem(row: ArchiveRow, named: Boolean, onRestore: () -> Unit, onDelete: () -> Unit) {
    val chat = row.chat
    Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 10.dp, top = 6.dp, bottom = 6.dp)) {
        Row(Modifier.height(34.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(chat.title, fontSize = 16.sp, lineHeight = 22.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            // When (and where), then what can be done: no pointer to point with, so always there.
            Text(
                listOfNotNull(if (named) row.view.name else null, clock(archivedAt(chat))).joinToString("  "),
                fontSize = 12.sp, color = C.subtle, maxLines = 1,
                modifier = Modifier.semantics { contentDescription = if (chat.archived?.by == "auto") "空闲后自动归档" else "手动归档" },
            )
            Row {
                Action(Icons.Retry, "恢复「${chat.title}」", onRestore)
                // A chat archived alone has agents still at work elsewhere: nothing of theirs is deleted from here.
                if (chat.archived?.alone != true) Action(Icons.Trash, "删除「${chat.title}」", onDelete)
            }
        }
        Text(
            chat.last?.text ?: "", fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(end = 10.dp),
        )
    }
}

@Composable
private fun Action(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(34.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        IconIn(icon, 16.dp, C.muted)
    }
}

private fun archivedAt(chat: ArchivedChat) = chat.archived?.at ?: chat.lastActiveAt

private val CLOCK = DateTimeFormatter.ofPattern("HH:mm")
private fun clock(at: Long) = CLOCK.format(Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()))

private val WEEKDAY = listOf("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")

/** Rows (newest first) by the day they were archived, as the chat list has its days: 今天, 昨天, 星期三, 9月20日. */
private fun days(rows: List<ArchiveRow>): List<Pair<String, List<ArchiveRow>>> {
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val out = mutableListOf<Pair<String, MutableList<ArchiveRow>>>()
    for (row in rows) {
        val day = Instant.ofEpochMilli(archivedAt(row.chat)).atZone(zone).toLocalDate()
        val ago = ChronoUnit.DAYS.between(day, today)
        val label = when {
            ago <= 0 -> "今天"
            ago == 1L -> "昨天"
            ago < 7 -> WEEKDAY[day.dayOfWeek.value - 1]
            day.year == today.year -> "${day.monthValue}月${day.dayOfMonth}日"
            else -> "${day.year}年${day.monthValue}月${day.dayOfMonth}日"
        }
        val last = out.lastOrNull()
        if (last != null && last.first == label) last.second.add(row) else out.add(label to mutableListOf(row))
    }
    return out
}
