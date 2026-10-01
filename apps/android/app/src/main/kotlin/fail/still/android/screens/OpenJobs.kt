// The services and background jobs left up a long while (an hour), across the chats of the workspace's stations, so
// none is forgotten running (web/src/OpenJobs.tsx, at the desktop sidebar's foot; here at the top of the list, which is
// what a phone sees first): web services and background jobs, each under its heading; nothing at all while there are
// none. Each leads to its chat (a service opens over it) and stops from here. The core puts them together (its
// `longJobs` view, from each station's `jobs`, current with its events).
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
import fail.still.android.data.LongJobsGroup
import fail.still.android.data.LongJobsView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons

/** Rows shown before the rest folds under「还有 N 个」. */
private const val SHOWN = 3

/** The list's reminder of what is left up on the workspace's (`scope`) stations: nothing while there is none. */
@Composable
fun OpenJobs(scope: String) {
    val app = LocalApp.current
    val view by rememberTopic<LongJobsView>(app.core, Topics.longJobs(scope))
    val groups = view.value?.groups.orEmpty()
    val all = remember { mutableStateMapOf<String, Boolean>() }
    if (groups.isEmpty()) return
    Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 4.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        groups.forEach { OpenGroup(it, all) }
    }
}

@Composable
private fun OpenGroup(group: LongJobsGroup, all: MutableMap<String, Boolean>) {
    val list = group.jobs
    val shown = if (all[group.key] == true || list.size <= SHOWN + 1) list else list.take(SHOWN)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(group.head, fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 10.dp, vertical = 2.dp))
        shown.forEach { OpenRow(it) }
        if (shown.size < list.size) Text(
            "还有 ${list.size - shown.size} 个", fontSize = 12.sp, color = C.muted,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { all[group.key] = true }.padding(horizontal = 10.dp, vertical = 3.dp),
        )
    }
}

/** A job: the row leads to its chat (a service opens over it); stop at its end (no hover here: it always shows). */
@Composable
private fun OpenRow(job: Job) {
    val app = LocalApp.current
    val chat = job.chat
    val station = job.station ?: return
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
            .then(if (chat != null) Modifier.clickable {
                app.push(Screen.Chat(station, ChatOf.Session(chat.id)))
                if (job.service == true) app.push(Screen.Preview(station, job.id))
            } else Modifier)
            .padding(start = 10.dp, end = 4.dp, top = 5.dp, bottom = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // The dot, in the column the rows' icons take.
        Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { JobDot(job.dot) }
        Column(Modifier.weight(1f)) {
            Text(job.name, fontSize = 14.sp, lineHeight = 18.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${job.whereText.orEmpty()} · ${job.age.orEmpty()}", fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        val stopping = app.stopping(station, job)
        Box(
            Modifier.size(32.dp).clip(CircleShape).clickable(enabled = !stopping) { app.stopJob(station, job) }.semantics { contentDescription = "停止「${job.name}」" },
            contentAlignment = Alignment.Center,
        ) { if (stopping) Spinner(14.dp) else IconIn(Icons.Stop, 15.dp, C.muted) }
    }
}
