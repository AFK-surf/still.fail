// The services and background jobs left up a long while, across the chats of the workspace's stations, so none is
// forgotten running (web/src/OpenJobs.tsx, at the desktop sidebar's foot; here at the top of the list, which is what a
// phone sees first): web services and background jobs, each under its heading. Only those up for more than LONG;
// nothing at all while there are none. Each leads to its chat (a service opens over it) and stops from here. The core
// keeps the lists (the `jobs` topic of each station, current with its events).
package fail.still.android.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
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
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Job
import fail.still.android.data.StationState
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.android.data.rememberTopic
import fail.still.core.CoreException
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** Up this long, a service or job is worth a reminder. */
private const val LONG = 3600_000L
/** Rows shown before the rest folds under「还有 N 个」. */
private const val SHOWN = 3

/** The chat a job still up is in, as the viewer's list has it. */
@Serializable
private data class JobChat(val id: String, val title: String = "", val archived: Boolean = false)

/** A job still up, of `station` (named when there are several to tell apart), with its chat when there is one. */
private class Held(val job: Job, val chat: JobChat?, val station: String, val stationName: String?)

/** Those of the workspace's online stations, as the core keeps them; a station too old to know the list has none. */
@Composable
private fun rememberOpenJobs(stations: List<StationState>): List<Held> {
    val app = LocalApp.current
    val online = stations.filter { it.state == "online" }
    val several = stations.size > 1
    return online.flatMap { s ->
        key(s.station) {
            val topic by rememberTopic<List<JsonElement>>(app.core, Topics.jobs(s.station))
            (topic.value ?: emptyList()).mapNotNull { j ->
                val job = try { decode(Job.serializer(), j) } catch (_: CoreException) { return@mapNotNull null }
                val chat = (j as? JsonObject)?.get("chat")?.let { runCatching { StillFailJson.decodeFromJsonElement(JobChat.serializer(), it) }.getOrNull() }
                Held(job, chat, s.station, s.name.takeIf { several })
            }
        }
    }
}

/** The list's reminder of what is left up: nothing while there is none. */
@Composable
fun OpenJobs(stations: List<StationState>) {
    val now = rememberNow(60_000)
    val jobs = rememberOpenJobs(stations)
    val all = remember { mutableStateMapOf<String, Boolean>() }
    val long = jobs.filter { now - it.job.startedAt >= LONG }.sortedBy { it.job.startedAt }
    if (long.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 4.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OpenGroup("services", "开了很久的网页服务", long.filter { it.job.isService }, now, all)
        OpenGroup("jobs", "一直在跑的后台任务", long.filter { !it.job.isService }, now, all)
    }
}

@Composable
private fun OpenGroup(key: String, head: String, list: List<Held>, now: Long, all: MutableMap<String, Boolean>) {
    if (list.isEmpty()) return
    val shown = if (all[key] == true || list.size <= SHOWN + 1) list else list.take(SHOWN)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("$head · ${list.size}", fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 10.dp, vertical = 2.dp))
        shown.forEach { OpenRow(it, now) }
        if (shown.size < list.size) Text(
            "还有 ${list.size - shown.size} 个", fontSize = 12.sp, color = C.muted,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { all[key] = true }.padding(horizontal = 10.dp, vertical = 3.dp),
        )
    }
}

/** A job: the row leads to its chat (a service opens over it); stop at its end (no hover here: it always shows). */
@Composable
private fun OpenRow(held: Held, now: Long) {
    val app = LocalApp.current
    val job = held.job
    val chat = held.chat
    val where = listOfNotNull(held.stationName, chat?.title?.ifEmpty { null } ?: if (chat == null) "不在任何对话里" else "对话", if (chat?.archived == true) "已归档" else null).joinToString(" · ")
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
            .then(if (chat != null) Modifier.clickable {
                app.push(Screen.Chat(held.station, ChatOf.Session(chat.id)))
                if (job.isService) app.push(Screen.Preview(held.station, job.id))
            } else Modifier)
            .padding(start = 10.dp, end = 4.dp, top = 5.dp, bottom = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // The dot, in the column the rows' icons take.
        Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { JobDot(job.tone) }
        Column(Modifier.weight(1f)) {
            Text(job.name, fontSize = 14.sp, lineHeight = 18.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("$where · ${span(now - job.startedAt)}", fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(
            Modifier.size(32.dp).clip(CircleShape).clickable { app.stopJob(held.station, job) }.semantics { contentDescription = "停止「${job.name}」" },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Stop, 15.dp, C.muted) }
    }
}
