// A chat's web services and background jobs, as the web shows them (web/src/Jobs.tsx, mobile/Chat.tsx → JobInfoRow,
// JobSheet). Jobs are mostly long-running watchers (a CI run followed, a deploy kept an eye on): what matters is whether
// each is still alive and what it last said (`stillfail-job notify`), not how long it took. Status is a small dot before the
// name and a word on the line under it; a service opens its page (Preview.kt), a job its sheet.
package fail.still.android.screens

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
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.produceState
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
import fail.still.android.data.ChatView
import fail.still.android.data.Job
import fail.still.android.data.JobLog
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
import fail.still.core.CoreException
import java.util.Calendar
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What a job's dot says: a service up, a job alive, a service restarting, one that died, one that is over. */
enum class Tone { Up, Live, Restart, Fail, Off }

/** A job that ended by itself or failed this long ago is no longer news: no alarm in the bar for it. */
private const val NEWS = 24 * 3600_000L

val Job.isService: Boolean get() = port != null

val Job.tone: Tone get() = when {
    state == "failed" -> Tone.Fail
    state == "stopped" -> Tone.Off
    isService -> if (state == "running") Tone.Up else Tone.Restart
    state == "running" -> Tone.Live
    else -> if (exitCode == 0L) Tone.Off else Tone.Fail
}

/** Whether it matters now: up, alive, restarting, or died lately. */
fun Job.isCurrent(now: Long): Boolean = tone != Tone.Off && (tone != Tone.Fail || now - (endedAt ?: startedAt) < NEWS)

/** What the bar's button says of them: red when one died lately, amber while a service restarts. */
fun alarmOf(jobs: List<Job>, now: Long): Tone? {
    val current = jobs.filter { it.isCurrent(now) }
    return when {
        current.any { it.tone == Tone.Fail } -> Tone.Fail
        current.any { it.tone == Tone.Restart } -> Tone.Restart
        else -> null
    }
}

private fun rank(t: Tone) = when (t) { Tone.Fail -> 0; Tone.Restart -> 1; Tone.Up, Tone.Live -> 2; Tone.Off -> 3 }

/** The chat's agents' jobs: died first, then restarting, then up and alive, then what is over; newest first within each. */
fun jobsOf(view: ChatView): List<Job> =
    view.agents.flatMap { it.jobs }.sortedWith(compareBy<Job> { rank(it.tone) }.thenByDescending { it.startedAt })

/** A time span in words: 12 秒, 4 分钟, 3 小时, 2 天. */
fun span(ms: Long): String {
    val s = maxOf(0L, Math.round(ms / 1000.0))
    return when {
        s < 60 -> "$s 秒"
        s < 3600 -> "${s / 60} 分钟"
        s < 86400 -> "${s / 3600} 小时"
        else -> "${s / 86400} 天"
    }
}

/** How long ago: 刚刚, 12 秒前, 4 分钟前, 3 小时前, 昨天, 2 天前. */
fun ago(at: Long, now: Long): String {
    val s = Math.round((now - at) / 1000.0)
    if (s < 5) return "刚刚"
    if (s in 86400 until 2 * 86400) return "昨天"
    return "${span(now - at)}前"
}

/** A clock time for a notice: 13:04 today, 9/27 13:04 before. */
fun clock(at: Long, now: Long): String {
    val d = Calendar.getInstance().apply { timeInMillis = at }
    val today = Calendar.getInstance().apply { timeInMillis = now }
    val hm = String.format(java.util.Locale.ROOT, "%02d:%02d", d.get(Calendar.HOUR_OF_DAY), d.get(Calendar.MINUTE))
    val same = d.get(Calendar.YEAR) == today.get(Calendar.YEAR) && d.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
    return if (same) hm else "${d.get(Calendar.MONTH) + 1}/${d.get(Calendar.DAY_OF_MONTH)} $hm"
}

/** Now, again every `every` ms: for the times in words. */
@Composable
fun rememberNow(every: Long = 1000): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(every) { while (true) { delay(every); now = System.currentTimeMillis() } }
    return now
}

/** A tone's colour, for its dot and its word; null: the text's own. */
@Composable
private fun toneTint(t: Tone): Color? = when (t) { Tone.Up, Tone.Live -> C.green; Tone.Restart -> C.warn; Tone.Fail -> C.red; Tone.Off -> null }

/** A job's state in a word. */
private fun word(job: Job): String {
    val t = job.tone
    if (job.isService) return when (t) { Tone.Up -> "在线"; Tone.Restart -> "正在重启"; Tone.Fail -> "没能启动"; else -> "已停止" }
    return when (t) {
        Tone.Live -> "在盯着"
        Tone.Fail -> if (job.state == "failed") "没能启动" else "意外退出"
        else -> if (job.state == "stopped") "已停止" else "已结束"
    }
}

/** The line under a job's name: what it is up to, in a few words (its state's word coloured as its dot). */
@Composable
fun metaOf(job: Job, now: Long): AnnotatedString {
    val t = job.tone
    val color = toneTint(t)
    val ink = C.ink
    val ended = job.endedAt?.let { ago(it, now) }
    return buildAnnotatedString {
        fun said() { if (color != null) withStyle(SpanStyle(color = color)) { append(word(job)) } else append(word(job)) }
        when {
            job.isService && t == Tone.Up -> { said(); append(" · ${span(now - job.startedAt)}") }
            job.isService && t == Tone.Restart -> { said(); job.restarts?.takeIf { it > 0 }?.let { append(" · 第 $it 次") } }
            job.isService -> { said(); ended?.let { append(" · $it") } }
            t == Tone.Live -> {
                val last = job.notices?.firstOrNull()
                when {
                    last != null -> { withStyle(SpanStyle(color = ink)) { append(last.text) }; append(" · ${ago(last.at, now)}") }
                    job.outputAt != null -> append("还没通知过 · 最后输出 ${ago(job.outputAt, now)}")
                    else -> { said(); append(" · ${span(now - job.startedAt)}") }
                }
            }
            t == Tone.Fail && job.state != "failed" -> {
                said(); append(" · " + (job.exitCode?.let { "退出码 $it" } ?: "被信号结束")); ended?.let { append(" · $it") }
            }
            else -> { said(); ended?.let { append(" · $it") } }
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

/** A job's output as it grows: its last `lines`, read again every `every` ms while shown; `id` null reads nothing. */
@Composable
fun rememberJobLog(station: String, id: String?, lines: Int, every: Long): JobLog? {
    val app = LocalApp.current
    val log by produceState<JobLog?>(null, station, id, lines, every) {
        if (id == null) return@produceState
        while (true) {
            try { value = app.api(station).jobLog(id, lines) } catch (_: CoreException) {}
            delay(every)
        }
    }
    return log?.takeIf { it.job == id }
}

/** Stops a job from the app; a failure is said in a toast. */
fun AppState.stopJob(station: String, job: Job) {
    scope.launch {
        try { api(station).stopJob(job.id) } catch (e: CoreException) { toast = "没能停下「${job.name}」：${e.message}" }
    }
}

/** A job's row: its dot on its name's line, what it is up to under it; over ones faded. */
@Composable
fun JobInfoRow(job: Job, now: Long, onClick: (() -> Unit)?) {
    InfoRow(onClick = onClick) {
        val off = job.tone == Tone.Off
        // The dot sits on the name's line: (its line height − the dot) / 2 down.
        JobDot(job.tone, Modifier.align(Alignment.Top).padding(top = 7.dp).alpha(if (off) 0.55f else 1f))
        Column(Modifier.weight(1f).alpha(if (off) 0.55f else 1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(job.name, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(metaOf(job, now), fontSize = 12.5.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onClick != null) IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/** The chat's services (each opens its page while up) and background jobs (each opens its sheet), as two groups. */
@Composable
fun JobGroups(app: AppState, station: String, of: ChatOf, jobs: List<Job>) {
    val now = rememberNow()
    val services = jobs.filter { it.isService }
    val plain = jobs.filter { !it.isService }
    if (services.isNotEmpty()) {
        GroupLabel("服务")
        InfoList {
            services.forEach { j ->
                val up = j.tone == Tone.Up || j.tone == Tone.Restart
                JobInfoRow(j, now, if (up) ({ app.push(Screen.Preview(station, j.id)) }) else null)
            }
        }
    }
    if (plain.isNotEmpty()) {
        GroupLabel("后台任务")
        InfoList { plain.forEach { j -> JobInfoRow(j, now) { openJob(app, station, of, j.id) } } }
    }
}

/** The chat's services and jobs alone, from the bar's button. */
fun openJobs(app: AppState, station: String, of: ChatOf) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val jobs = chat.value?.let(::jobsOf) ?: emptyList()
        SheetGrab()
        SheetHead("服务和后台任务")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            if (jobs.isEmpty()) Text("还没有服务或后台任务。agent 开网页、或挂上长期盯着的任务时，会列在这里。", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp))
            else JobGroups(app, station, of, jobs)
        }
    }
}

/** A job, from the chat's sheet: what it said, or its output as it grows; stopped from here. */
fun openJob(app: AppState, station: String, of: ChatOf, id: String) {
    app.sheet = SheetSpec(0.8f, draggable = true) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val job = chat.value?.agents?.flatMap { it.jobs }?.firstOrNull { it.id == id }
        val now = rememberNow()
        var tab by remember { mutableIntStateOf(0) }
        val running = job?.state == "running"
        val log = rememberJobLog(station, if (job != null && tab == 1) id else null, 300, if (running) 2000 else 60_000)
        // The last line it wrote: again and again while it runs, once when it is over.
        val last = rememberJobLog(station, if (job != null && tab == 0) id else null, 1, if (running) 3000 else 600_000)
        SheetGrab()
        if (job == null) {
            SheetHead("任务")
            if (chat.value != null) Text("这个任务已经不在了。", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 18.dp))
        } else JobBody(app, station, job, now, tab, { tab = it }, log, last)
    }
}

/** A job's sheet under its grabber: its name and state, what it said or its output, and stop while it runs. */
@Composable
private fun ColumnScope.JobBody(app: AppState, station: String, job: Job, now: Long, tab: Int, onTab: (Int) -> Unit, log: JobLog?, last: JobLog?) {
    val running = job.state == "running"
    Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 22.dp, top = 4.dp, bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        JobDot(job.tone, Modifier.padding(top = 8.dp))
        Column(Modifier.weight(1f)) {
            Text(job.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(metaOf(job, now), fontSize = 12.5.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    Column(Modifier.weight(1f).padding(start = 18.dp, end = 18.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Seg(listOf("通知", "输出"), tab, onTab, Modifier.fillMaxWidth(), height = 34.dp, fill = true)
        if (tab == 0) {
            val notices = job.notices ?: emptyList()
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (notices.isEmpty()) Text("还没有通知。它用 stillfail-job notify 说的话会列在这里。", fontSize = 14.sp, color = C.muted)
                notices.forEach { n ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(clock(n.at, now), fontSize = 14.sp, color = C.subtle, modifier = Modifier.width(48.dp))
                        Text(n.text, fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    }
                }
            }
            val at = last?.outputAt ?: job.outputAt
            val line = last?.text?.trim()?.takeIf { it.isNotEmpty() }
            if (at != null || line != null) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("最后输出" + (at?.let { " · ${ago(it, now)}" } ?: ""), fontSize = 11.sp, color = C.subtle)
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
                Text(if (log == null) "正在读取…" else text?.ifEmpty { "（还没有输出）" } ?: "", style = Mono, fontSize = 11.5.sp, color = C.ink, fontFamily = FontFamily.Monospace)
            }
        }
        if (running) Row(
            Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(23.dp)).background(C.red.copy(alpha = 0.12f)).clickable { app.stopJob(station, job) },
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically,
        ) {
            IconIn(Icons.Stop, 16.dp, C.red)
            Text("停止", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.red)
        }
    }
}
