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
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.ArchiveItem
import fail.still.android.data.ArchiveView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.SectionHeader

@Composable
fun ArchiveScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    // Every station's archive as the core puts it together, and takes a chat out of once restored or deleted.
    val archive by rememberTopic<ArchiveView>(app.core, Topics.archive(current.workspace.id))
    val restore = { item: ArchiveItem -> app.act("恢复", "已恢复到列表") { app.api(item.station).setArchived(item.thread, item.session, false) } }
    val delete = { item: ArchiveItem ->
        confirm(app, "删除「${item.title}」？", "它的会话、对话记录和 workspace 目录都会删掉，不能恢复。", "删除", danger = true) {
            app.api(item.station).deleteSession(item.session)
            app.toast = "已删除"
        }
    }
    val view = archive.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 24.dp)) {
        TopBack("会话", app::pop)
        LargeTitle(current.workspace.name, "已归档")
        // No hover to explain it on a phone: said at the top instead.
        Text(
            "手动归档的对话，和空闲超过一天、已经做完的对话（没在跑、没停在 block、没有未读）。对话里有新消息时会自动回到列表。",
            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        val note = if (view != null) view.note else archive.error?.message ?: "正在读取 station…"
        view?.errors?.forEach { Text(it.text, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
        if (note != null) Text(note, fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))
        view?.days?.forEach { day ->
            SectionHeader(day.label)
            day.items.forEach { item ->
                // Restoring or deleting it under way: a spinner in place of its actions; failed: a red mark beside them a moment.
                val busy = app.isDoing("chat.archive", "station" to item.station, "session" to item.session) ||
                    app.isDoing("session.delete", "station" to item.station, "key" to item.session)
                val failed = app.failedOf("chat.archive", "station" to item.station, "session" to item.session)
                    ?: app.failedOf("session.delete", "station" to item.station, "key" to item.session)
                ArchiveRow(item, busy, failed, { restore(item) }, { delete(item) })
            }
        }
    }
}

@Composable
private fun ArchiveRow(item: ArchiveItem, busy: Boolean, failed: String?, onRestore: () -> Unit, onDelete: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 10.dp, top = 6.dp, bottom = 6.dp)) {
        Row(Modifier.height(34.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(item.title, fontSize = 16.sp, lineHeight = 22.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            // When (and where), then what can be done: no pointer to point with, so always there.
            Text(
                listOfNotNull(item.place, item.clock).joinToString("  "),
                fontSize = 12.sp, color = C.subtle, maxLines = 1,
                modifier = Modifier.semantics { contentDescription = item.how },
            )
            if (busy) Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { Spinner(14.dp) }
            else Row(verticalAlignment = Alignment.CenterVertically) {
                if (failed != null) Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { DoingMark(false, failed) }
                Action(Icons.Retry, "恢复「${item.title}」", onRestore)
                if (item.deletable) Action(Icons.Trash, "删除「${item.title}」", onDelete)
            }
        }
        Text(
            item.last, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
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
