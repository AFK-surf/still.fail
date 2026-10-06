// A chat's web services and background jobs, as the web shows them (web/src/Jobs.tsx, mobile/Chat.tsx → JobInfoRow,
// JobSheet). Jobs are mostly long-running watchers (a CI run followed, a deploy kept an eye on): what matters is whether
// each is still alive and what it last said (`stillfail-job notify`), not how long it took. Status is a small dot before the
// name and a word on the line under it; a service opens its page (Preview.kt), a job its sheet.
package fail.still.android.screens

import fail.still.android.data.t
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Job
import fail.still.android.data.ChatJobsView
import fail.still.android.data.JobLogView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Mono
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec

// What a job's dot says, its word, the line under its name and every time in words are the core's (client/core-ts/src/
// jobs.ts): `tone`, `meta`, `detail`, a notice's `ago` and `clock`; a chat's all together, what matters first, is its
// `chatJobs` view.

/** What a job's dot says: a service up, a job alive, a service restarting, one that died, one that is over. */
enum class Tone { Up, Live, Restart, Fail, Off }

/** The core's word for a dot as drawn here. */
fun toneOf(word: String?): Tone = when (word) { "up" -> Tone.Up; "live" -> Tone.Live; "restart" -> Tone.Restart; "fail" -> Tone.Fail; else -> Tone.Off }

val Job.dot: Tone get() = toneOf(tone)

/** A chat's jobs before the core has said: none. */
val NoJobs = ChatJobsView(jobs = emptyList(), servicesNote = "", jobsNote = "", current = 0, ended = 0, clear = emptyList(), allText = "", clearText = "", hiddenText = "")

/** A tone's colour, for its dot and its word; null: the text's own. */
@Composable
private fun toneTint(t: Tone): Color? = when (t) { Tone.Up, Tone.Live -> C.green; Tone.Restart -> C.warn; Tone.Fail -> C.red; Tone.Off -> null }

/** The line under a job's name: what it is up to, in a few words (its state's word coloured as its dot). */
@Composable
fun metaOf(job: Job): AnnotatedString {
    val color = toneTint(job.dot)
    val ink = C.ink
    return buildAnnotatedString {
        job.meta.orEmpty().forEach { part ->
            when (part.kind) {
                "word" -> if (color != null) withStyle(SpanStyle(color = color)) { append(part.text) } else append(part.text)
                "notice" -> withStyle(SpanStyle(color = ink)) { append(part.text) }
                else -> append(part.text)
            }
        }
    }
}

/** A job's status: a small dot, on its name's line (a restarting service's breathes). */
@Composable
fun JobDot(tone: Tone, modifier: Modifier = Modifier) {
    val breath = if (tone == Tone.Restart) {
        rememberInfiniteTransition(label = "restart").animateFloat(1f, 0.35f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "breath").value
    } else 1f
    Box(modifier.size(8.dp).alpha(breath).clip(CircleShape).background(toneTint(tone) ?: C.subtle))
}

/** A job's output as it grows: its last `lines`, as the core keeps it; `id` null reads nothing. */
@Composable
fun rememberJobLog(station: String, id: String?, lines: Int): JobLogView? {
    val app = LocalApp.current
    val log by rememberTopic<JobLogView>(app.core, id?.let { Topics.jobLog(station, it, lines) })
    return log.value
}

/** Stops a job from the app; a failure is said in a toast. */
fun AppState.stopJob(station: String, job: Job) {
    if (!stopping(station, job)) act(t("android-misc.jobs.stopWhat", "name" to job.name)) { api(station).stopJob(job.id) }
}

/** Whether a job's stop was asked and not answered yet: its 停止 shows a spinner, not pressed again. */
fun AppState.stopping(station: String, job: Job): Boolean = isDoing("job.stop", "station" to station, "id" to job.id)

/** Why a job's stop failed a moment ago, if it did: its 停止 shows a red mark (DoingMark). */
fun AppState.stopFailed(station: String, job: Job): String? = failedOf("job.stop", "station" to station, "id" to job.id)

/** Clears a chat's jobs that are over (each session's, as the station keeps them: `clear`); a failure in a toast. */
fun AppState.clearEnded(station: String, sessions: List<String>) {
    if (!clearing(station)) act(t("android-misc.jobs.clearWhat")) { sessions.forEach { api(station).clearEndedJobs(it) } }
}

fun AppState.clearing(station: String): Boolean = isDoing("job.clearEnded", "station" to station)
fun AppState.clearFailed(station: String): String? = failedOf("job.clearEnded", "station" to station)

/** A job's row: its dot on its name's line, what it is up to under it; over ones faded. */
@Composable
fun JobInfoRow(job: Job, onClick: (() -> Unit)?) {
    InfoRow(onClick = onClick) {
        val off = job.dot == Tone.Off
        // The dot sits on the name's line: (its line height − the dot) / 2 down.
        JobDot(job.dot, Modifier.align(Alignment.Top).padding(top = 7.dp).alpha(if (off) 0.55f else 1f))
        Column(Modifier.weight(1f).alpha(if (off) 0.55f else 1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(job.name, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(metaOf(job), fontSize = 12.5.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onClick != null) IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/**
 * Services, then background jobs. A service up or restarting opens its page; one that did not start (or is over), and
 * any job, opens what it said and its output. With `notes` each group's head says how many are up or alive.
 */
@Composable
fun JobGroups(app: AppState, station: String, of: ChatOf, view: ChatJobsView, jobs: List<Job> = view.jobs, notes: Boolean = false) {
    val services = jobs.filter { it.service == true }
    val plain = jobs.filter { it.service != true }
    if (services.isNotEmpty()) {
        GroupLabel(t("android-misc.jobs.services") + if (notes && view.servicesNote.isNotEmpty()) " · ${view.servicesNote}" else "")
        InfoList {
            services.forEach { j ->
                val up = j.dot == Tone.Up || j.dot == Tone.Restart
                JobInfoRow(j) { if (up) app.push(Screen.Preview(station, j.id)) else openJob(app, station, of, j.id) }
            }
        }
    }
    if (plain.isNotEmpty()) {
        GroupLabel(t("android-misc.jobs.jobs") + if (notes && view.jobsNote.isNotEmpty()) " · ${view.jobsNote}" else "")
        InfoList { plain.forEach { j -> JobInfoRow(j) { openJob(app, station, of, j.id) } } }
    }
}

/** What matters now of the chat's services and jobs, from the bar's button; the rest a tap away, the ended cleared. */
fun openJobs(app: AppState, station: String, of: ChatOf) {
    app.sheet = SheetSpec(0.62f, draggable = true) {
        val topic by rememberTopic<ChatJobsView>(app.core, Topics.chatJobs(station, of))
        val view = topic.value ?: NoJobs
        val jobs = view.jobs
        var all by remember { mutableStateOf(false) }
        val shown = if (all) jobs else jobs.filter { it.current == true }
        SheetGrab()
        SheetHead(t("android-misc.jobs.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            if (topic.value != null && jobs.isEmpty()) Column(Modifier.padding(horizontal = 2.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(t("android-misc.jobs.none"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(t("android-misc.jobs.none.text"), fontSize = 13.sp, color = C.muted)
            }
            if (jobs.isNotEmpty() && shown.isEmpty()) Text(t("android-misc.jobs.noneNow"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            JobGroups(app, station, of, view, shown, notes = true)
            if (jobs.size > view.current) SheetLink({ all = !all }) {
                if (all) Text(t("android-misc.jobs.onlyNow"), fontSize = 14.sp, color = C.accent)
                else {
                    Text(view.allText, fontSize = 14.sp, color = C.accent)
                    Text(view.hiddenText, fontSize = 12.sp, color = C.muted)
                }
            }
            if (view.ended > 0) SheetLink({ app.clearEnded(station, view.clear) }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(view.clearText, fontSize = 14.sp, color = C.accent)
                    DoingMark(app.clearing(station), app.clearFailed(station), 12.dp)
                }
            }
        }
    }
}

/** A quiet text button under the groups (web mobile's mJobsAll). */
@Composable
private fun SheetLink(onClick: () -> Unit, content: @Composable ColumnScope.() -> Unit) =
    Column(
        Modifier.padding(top = 14.dp).clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(horizontal = 2.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp), content = content,
    )

/** A job, from the chat's sheet: what it said, or its output as it grows; stopped from here. */
fun openJob(app: AppState, station: String, of: ChatOf, id: String) {
    app.sheet = SheetSpec(0.8f, draggable = true) {
        val topic by rememberTopic<ChatJobsView>(app.core, Topics.chatJobs(station, of))
        val job = topic.value?.jobs?.firstOrNull { it.id == id }
        var picked by remember { mutableIntStateOf(0) }
        val tab = if (job?.service == true) 1 else picked
        val log = rememberJobLog(station, if (job != null && tab == 1) id else null, 300)
        // The last line it wrote, as it grows.
        val last = rememberJobLog(station, if (job != null && tab == 0) id else null, 1)
        SheetGrab()
        if (job == null) {
            SheetHead(t("android-misc.jobs.job"))
            if (topic.value != null) Text(t("android-misc.jobs.gone"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 18.dp))
        } else JobBody(app, station, job, tab, { picked = it }, log, last)
    }
}

/** A job's sheet under its grabber: its name and state, what it said or its output, and stop while it runs. */
@Composable
private fun ColumnScope.JobBody(app: AppState, station: String, job: Job, tab: Int, onTab: (Int) -> Unit, log: JobLogView?, last: JobLogView?) {
    val running = job.state == "running"
    Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 22.dp, top = 4.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        JobDot(job.dot, Modifier.padding(top = 8.dp))
        Column(Modifier.weight(1f)) {
            Text(job.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(metaOf(job), fontSize = 12.5.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    Column(Modifier.weight(1f).padding(start = 18.dp, end = 18.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        job.command?.takeIf { it.isNotBlank() }?.let { Text(it, style = Mono, fontSize = 11.5.sp, lineHeight = 17.sp, color = C.muted) }
        // A service has only its output to show.
        if (job.service != true) Seg(listOf(t("android-misc.jobs.notices"), t("android-misc.jobs.output")), tab, onTab, Modifier.fillMaxWidth(), height = 34.dp, fill = true)
        if (tab == 0) {
            val notices = job.notices ?: emptyList()
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (notices.isEmpty()) Text(t("android-misc.jobs.noNotices"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
                notices.forEach { n ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(n.clock ?: "", fontSize = 14.sp, color = C.subtle, modifier = Modifier.width(48.dp))
                        Text(n.text, fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    }
                }
            }
            val said = if (last != null) last.said else job.outputSaid
            val line = last?.last
            if (said != null) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(said, fontSize = 11.sp, color = C.subtle)
                line?.let { Text(it, style = Mono, fontSize = 11.5.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
        } else {
            // Its output, kept at its end as it grows unless scrolled up from there.
            val scroll = rememberScrollState()
            val text = log?.text
            LaunchedEffect(text) {
                val follow = scroll.maxValue - scroll.value < 60
                withFrameNanos { }
                if (follow) scroll.scrollTo(scroll.maxValue)
            }
            Box(
                Modifier.fillMaxWidth().weight(1f, fill = false).heightIn(min = 120.dp).clip(RoundedCornerShape(16.dp)).background(C.ink.copy(alpha = 0.05f))
                    .verticalScroll(scroll).padding(horizontal = 14.dp, vertical = 12.dp),
            ) {
                Text(if (log == null) t("android-misc.reading") else text?.ifEmpty { t("android-misc.jobs.noOutput") } ?: "", style = Mono, fontSize = 11.5.sp, color = C.ink, fontFamily = FontFamily.Monospace)
            }
        }
        if (running) Row(
            Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(23.dp)).background(C.red.copy(alpha = 0.12f)).clickable(enabled = !app.stopping(station, job)) { app.stopJob(station, job) },
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically,
        ) {
            val stopFailed = app.stopFailed(station, job)
            if (app.stopping(station, job) || stopFailed != null) DoingMark(app.stopping(station, job), stopFailed, 16.dp) else IconIn(Icons.Stop, 16.dp, C.red)
            Text(t("android-misc.jobs.stop"), fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.red)
        }
    }
}
