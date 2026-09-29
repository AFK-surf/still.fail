// An agent's execution history (web/src/History.tsx), as a sheet that drags
// between half and full height: what it received and what it sent, drawn
// alike (a line, then the words beside a bar); what it did in between,
// grouped, each group opening to its commands and output; and its details
// (model, allowance, the station it runs on).
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.WindowInsets
import fail.still.android.ui.NavBar
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatAgent
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.RunnableProfile
import fail.still.android.data.HistoryItem
import fail.still.android.data.HistoryBody
import fail.still.android.data.HistoryGroup
import fail.still.android.data.HistoryLive
import fail.still.android.data.HistoryPhase
import fail.still.android.data.HistoryStep
import fail.still.android.data.HistoryView
import fail.still.android.data.ModelOption
import fail.still.android.data.Host
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.state
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.ProviderMark
import fail.still.android.ui.QuotaRing
import fail.still.android.ui.QuotaRings
import fail.still.android.ui.Icons
import fail.still.android.ui.Mark
import fail.still.android.ui.Markdown
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.ModelMark
import fail.still.android.ui.Mono
import fail.still.android.ui.ReaderSpec
import fail.still.android.ui.Ring
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.android.ui.rememberFollow
import fail.still.core.CoreException
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.animation.core.tween
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Opens an agent's execution history, over the item's page it belongs to. */
/** `entry`: the transcript entry to open at (an activity row's), else its newest. */
fun openHistory(app: AppState, station: String, of: ChatOf, key: String, entry: Long? = null) {
    app.sheet = SheetSpec(0.55f, draggable = true) { HistorySheet(station, of, key, entry) }
}

@Composable
private fun ColumnScope.HistorySheet(station: String, of: ChatOf, key: String, entry: Long? = null) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
    val history by rememberTopic<HistoryView>(app.core, Topics.history(station, key))
    val host by rememberTopic<Host>(app.core, Topics.host(station))
    val agent = chat.value?.agents?.firstOrNull { it.session.key == key }
    var tab by rememberSaveable { mutableStateOf(0) }
    SheetGrab()
    if (agent == null) {
        Text(chat.error?.message ?: "正在读取…", color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(18.dp))
        return
    }
    val s = agent.session
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ModelMark(s.maker, s.runtime, 20.dp, agent.state)
        // The sheet is the agent's history; its head is the agent, with the room its name needs.
        Text(s.agentText, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Actions(station, agent)
        Seg(listOf("步骤", "详情"), tab, { tab = it })
    }
    Summary(agent)
    Box(Modifier.weight(1f).fillMaxWidth()) {
        if (tab == 0) Steps(station, of, agent, history.value, entry) else Details(station, of, agent, history.value, host.value)
    }
}

/** What can be done to it right now: stop a turn, release an idle process. */
@Composable
private fun Actions(station: String, agent: ChatAgent) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val s = agent.session
    val st = agent.status
    @Composable
    fun act(icon: androidx.compose.ui.graphics.vector.ImageVector, done: String, call: suspend () -> Unit) {
        var busy by remember { mutableStateOf(false) }
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(C.chip).clickable(enabled = !busy) {
                busy = true
                scope.launch {
                    try { call(); app.toast = done } catch (e: CoreException) { app.toast = e.message } finally { busy = false }
                }
            },
            contentAlignment = Alignment.Center,
        ) { IconIn(icon, 14.dp, if (busy) C.subtle else C.ink) }
    }
    if (st == "running" || st == "queued") act(Icons.Stop, "已请求停止") { app.api(station).stop(s.key) }
    if (s.process == "warm") act(Icons.Unplug, "已释放进程") { app.api(station).evict(s.key) }
}

/** The head's short line: only what is worth a look now (an account signed out, a quota running out, the disk filling up). */
@Composable
private fun Summary(agent: ChatAgent) {
    if (agent.attention.isEmpty()) return Box(Modifier.height(8.dp))
    Row(
        Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 6.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        agent.attention.forEach { a ->
            val quota = a.quota
            when {
                quota != null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    QuotaRing(quota.left, quota.level)
                    Text(quota.mark, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = C.subtle)
                }
                a.kind == "disk" -> Text(a.text, fontSize = 12.sp, color = C.warn)
                else -> Text(a.text, fontSize = 12.sp, color = C.red)
            }
        }
    }
}

private sealed interface Line {
    data class Item(val item: HistoryItem) : Line
    data class Live(val step: HistoryLive) : Line
    data class Phase(val phase: HistoryPhase) : Line
}

@Composable
private fun Steps(station: String, of: ChatOf, agent: ChatAgent, history: HistoryView?, entry: Long? = null) {
    if (history == null) return Edge("正在读取执行历史…")
    if (history.empty) return Edge(history.edge)
    val items = history.items
    val lines = items.map { Line.Item(it) } + history.live.map { Line.Live(it) } + listOfNotNull(history.phase?.let { Line.Phase(it) })
    val list = rememberLazyListState()
    val follow = rememberFollow(list)
    val api = LocalApp.current.api(station)
    // Only its latest entries come first: near the top, the page before comes in (once per page).
    val more = history.more == true
    val first = items.firstOrNull()?.key
    val asked = remember { mutableStateOf<String?>(null) }
    LaunchedEffect(more, first, follow.placed) {
        if (!more || !follow.placed) return@LaunchedEffect
        snapshotFlow { list.firstVisibleItemIndex }.collect { index ->
            if (index <= 2 && asked.value != first) {
                asked.value = first
                try { api.historyOlder(agent.session.key) } catch (_: CoreException) { asked.value = null }
            }
        }
    }
    // It opens at its newest, and follows new steps while the reader stays there.
    val density = LocalDensity.current
    // Opened at an entry (an activity row): that item, near the top, for a moment marked; else the newest, followed.
    // One before what is loaded: the pages before come first.
    var marked by remember { mutableStateOf<String?>(null) }
    val before = entry != null && more && entry < (items.firstOrNull()?.entries?.firstOrNull() ?: 0L)
    LaunchedEffect(before, first) {
        if (follow.placed) return@LaunchedEffect
        if (before) {
            try { api.historyOlder(agent.session.key); return@LaunchedEffect } catch (_: CoreException) {}
        }
        val at = entry?.let { e -> items.indexOfFirst { it.entries.size == 2 && e in it.entries[0]..it.entries[1] } }?.takeIf { it >= 0 }
        if (at != null) {
            list.scrollToItem(at + 1, -with(density) { 24.dp.roundToPx() })
            follow.placed = true; follow.on = false
            marked = items[at].key
            delay(1600); marked = null
        } else {
            follow.toEnd(); follow.placed = true; follow.on = true
        }
    }
    LazyColumn(Modifier.fillMaxWidth(), state = list, contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item(key = "edge") { Edge(history.edge) }
        itemsIndexed(lines, key = { _, l -> when (l) { is Line.Live -> "live/${l.step.id}"; is Line.Phase -> "phase"; is Line.Item -> l.item.key } }) { _, line ->
            when (line) {
                is Line.Item -> {
                    val shade by androidx.compose.animation.animateColorAsState(if (line.item.key == marked) C.accent.copy(alpha = 0.10f) else androidx.compose.ui.graphics.Color.Transparent, tween(900), label = "marked")
                    Box(Modifier.clip(RoundedCornerShape(8.dp)).background(shade)) { Item(line.item, station, of, agent) }
                }
                is Line.Live -> Text(line.step.text, fontSize = 13.sp, color = C.muted, maxLines = 1)
                is Line.Phase -> PhaseLine(line.phase)
            }
        }
    }
}

@Composable
private fun Edge(text: String) = Text(text, color = C.subtle, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp))

@Composable
private fun Item(item: HistoryItem, station: String, of: ChatOf, agent: ChatAgent) {
    when (val body = item.body) {
        is HistoryBody.Received -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            body.content.note?.let { note ->
                Message(Icons.Received, { Text("收到来自 ", fontSize = 13.sp, color = C.muted); Strong("still.fail"); Text(" 的提醒", fontSize = 13.sp, color = C.muted) }, note) {
                    Text(note, fontSize = 15.sp, lineHeight = 23.sp, color = C.ink)
                }
            }
            body.content.messages.forEach { m ->
                Message(Icons.Received, {
                    Text("收到来自 ", fontSize = 13.sp, color = C.muted)
                    val user = m.from.slackUser
                    if (user != null) SlackName(station, user, m.from.name, m.from.bound) else Strong(m.from.name)
                    Text(" 的消息", fontSize = 13.sp, color = C.muted)
                    m.place?.let { Text(" · ", fontSize = 13.sp, color = C.muted); Box(Modifier.weight(1f, fill = false)) { Place(station, of, it) } }
                }, m.text) { Text(m.text, fontSize = 15.sp, lineHeight = 23.sp, color = C.ink) }
            }
        }
        is HistoryBody.Post -> {
            val post = body.content
            Message(Icons.Send, {
                Text("发送到 ", fontSize = 13.sp, color = C.muted)
                Box(Modifier.weight(1f, fill = false)) {
                    val place = post.place
                    if (place != null) Place(station, of, place) else Row(verticalAlignment = Alignment.CenterVertically) { SlackMark(12.dp); Strong(" Slack") }
                }
                if (post.block) Pill("Block", C.blue)
                if (post.failed) Pill("发送失败", C.red)
            }, post.text) { Markdown(post.text, size = 15) }
        }
        is HistoryBody.Mark -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            val wait = body.content.wait
            if (wait != null) IconIn(Icons.Hourglass, 14.dp, C.muted)
            // A wait: how long it waited, said by the core once it is over; still waiting, it counts on here.
            if (wait != null && wait.until == null) {
                var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
                LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
                val waited = ((now - wait.since) / 1000).coerceAtLeast(0).let { s -> wait.seconds?.let { minOf(s, it) } ?: s }
                Text("等待中 ${shortSpan(waited)}" + (wait.seconds?.let { " / ${shortSpan(it)}" } ?: ""), fontSize = 13.sp, color = C.muted)
            } else Text(body.content.text, fontSize = 13.sp, color = C.muted)
        }
        is HistoryBody.Text -> Box(Modifier.let { if (body.content.subagent) it.padding(start = 12.dp) else it }) {
            val app = LocalApp.current
            val text = body.content.text
            Brief(text) { app.reader = ReaderSpec({ Text("${agent.session.agentText} 写道", fontSize = 13.sp, color = C.muted) }) { Markdown(text, size = 15) } }
        }
        is HistoryBody.Group -> Group(body.content)
    }
}

/** What an entry says, in brief: its words as plain text, two lines at most. A tap opens it in full. */
@Composable
private fun Brief(text: String, open: () -> Unit) {
    Text(
        plain(text), fontSize = 14.sp, lineHeight = 21.sp, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable(onClick = open),
    )
}

/** Markdown as one run of plain words, for a brief: no fences, headings, emphasis or line breaks. */
private fun plain(text: String): String = text
    .replace(Regex("```[^\\n]*"), " ")
    .replace(Regex("(?m)^\\s{0,3}(#{1,6}|>|[-*+]|\\d+\\.)\\s+"), "")
    .replace(Regex("\\*\\*|__|`"), "")
    .replace(Regex("\\s+"), " ")
    .trim()

@Composable
private fun Strong(text: String) = Text(text, fontSize = 13.sp, color = C.ink, fontWeight = FontWeight.SemiBold)

/**
 * A message in or out, drawn alike: a line saying what and where, then its words in brief beside a bar (they answer
 * each other). A tap on the words opens the whole of it on its own page, under the same line.
 */
@Composable
private fun Message(icon: androidx.compose.ui.graphics.vector.ImageVector, label: @Composable RowScope.() -> Unit, text: String, full: @Composable () -> Unit) {
    val app = LocalApp.current
    val line: @Composable RowScope.() -> Unit = {
        IconIn(icon, 14.dp, C.muted, Modifier.padding(end = 5.dp))
        label()
    }
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, content = line)
        Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(2.dp).fillMaxHeight().clip(RoundedCornerShape(1.dp)).background(C.line))
            Box(Modifier.padding(start = 10.dp).weight(1f)) { Brief(text) { app.reader = ReaderSpec(line, full) } }
        }
    }
}

@Composable
private fun Pill(text: String, color: androidx.compose.ui.graphics.Color) =
    Text(text, fontSize = 11.sp, color = color, modifier = Modifier.padding(start = 6.dp).clip(RoundedCornerShape(6.dp)).background(color.copy(alpha = 0.12f)).padding(horizontal = 6.dp, vertical = 1.dp))

/**
 * A place, as the core names it: its platform's mark and its name; a chat on still.fail's page leads to it, a Slack thread
 * opens in Slack (its link, while a connect is signed in to its workspace).
 */
@Composable
private fun Place(station: String, of: ChatOf, place: fail.still.android.data.Place) {
    val app = LocalApp.current
    val context = androidx.compose.ui.platform.LocalContext.current
    // A still.fail chat (surface "ember") is its agent's item: opened by the session it is bound to.
    val chat = place.session?.let { key -> { if (of != ChatOf.Session(key)) app.push(Screen.Chat(station, ChatOf.Session(key))) else app.sheet = null } }
    // A Slack thread by its link: the Slack app takes it when installed, the browser otherwise.
    val slack = place.url?.takeIf { place.surface == "slack" }?.let { url ->
        {
            try { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))) }
            catch (_: android.content.ActivityNotFoundException) { app.toast = "打不开这个链接" }
        }
    }
    val open = chat ?: slack
    Row(
        Modifier.clip(RoundedCornerShape(4.dp)).let { if (open != null) it.clickable(onClick = open) else it },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (place.surface == "ember") Mark(12.dp) else SlackMark(12.dp)
        Text(place.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (open != null) C.accentInk else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * A Slack user's name (你 once the viewer said it is them, the core says). A tap offers "这是我" (the station then takes
 * that Slack user for the viewer), or "不是我" once it does.
 */
@Composable
private fun SlackName(station: String, user: String, name: String, mine: Boolean) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Text(
        name, fontSize = 13.sp, color = C.accentInk, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.onGloballyPositioned { bounds = it.boundsInRoot() }.clip(RoundedCornerShape(4.dp)).clickable {
            app.menu = MenuSpec(bounds, listOf(MenuItem(if (mine) "不是我" else "这是我", if (mine) Icons.Close else Icons.Check) {
                scope.launch {
                    try {
                        app.api(station).slackIdentity(user, !mine)
                    } catch (e: CoreException) {
                        app.toast = "${if (mine) "解除" else "绑定"}没有成功：${e.message}"
                    }
                }
            }))
        },
    )
}

@Composable
private fun Group(g: HistoryGroup) {
    var open by remember { mutableStateOf(false) }
    Column {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable { open = !open }.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            IconIn(if (open) Icons.ChevronDown else Icons.ChevronRight, 13.dp, C.subtle)
            Text(g.summary, color = if (g.failures > 0) C.red else C.muted, fontSize = 14.sp, maxLines = if (open) 3 else 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (g.failures > 0) Pill("${g.failures} 项失败", C.red)
            if (g.pending > 0) Pill("${g.pending} 项进行中", C.accentInk)
        }
        if (open) Column(Modifier.padding(start = 19.dp, top = 4.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            g.thinking.forEach { t ->
                if (g.steps.isEmpty()) Text(t.text, fontSize = 13.sp, lineHeight = 20.sp, color = C.muted)
                else Folding("思考", t.first, null, false) { Text(t.text, fontSize = 13.sp, lineHeight = 20.sp, color = C.muted) }
            }
            g.steps.forEach { StepRow(it) }
        }
    }
}

@Composable
private fun StepRow(step: HistoryStep) {
    // Opened: the call drawn by what it is (a command, a diff, code, a plan, its fields), then what came back (ui/ToolStep.kt).
    Folding(step.said ?: step.name, if (step.said == null) step.hint else null, step.meta, step.failed) {
        fail.still.android.ui.ToolStepBody(step.name, step.call, step.said != null, step.result, step.failed)
    }
}

/** A line that opens to what is behind it. */
@Composable
private fun Folding(name: String, hint: String?, meta: String?, failed: Boolean, body: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(name, fontSize = 13.sp, color = if (failed) C.red else C.ink, fontWeight = if (hint != null) FontWeight.Medium else null, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = hint == null))
            if (hint != null) Text(hint, fontSize = 12.sp, style = Mono, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (!meta.isNullOrEmpty()) Text(meta, fontSize = 11.sp, color = if (failed) C.red else C.subtle)
        }
        if (open) body()
    }
}

/** The turn's state with the model (the core's words), with a running clock. */
@Composable
private fun PhaseLine(phase: HistoryPhase) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent))
        Text(phase.text, fontSize = 13.sp, color = C.ink)
        Text("${((now - phase.since) / 1000).coerceAtLeast(0)}s", fontSize = 12.sp, color = C.subtle)
    }
}

/** How it runs (which can be changed here), what it has used, the station. */
@Composable
private fun Details(station: String, of: ChatOf, agent: ChatAgent, history: HistoryView?, host: Host?) {
    val app = LocalApp.current
    val s = agent.session
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
        // Changing how it runs is a screen of its own.
        RunRow(agent) { app.push(Screen.RunSettings(station, of, s.key)) }
        Column(Modifier.padding(top = 12.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Detail("运行时", s.runtimeText)
            s.processText?.let { Detail("进程", it) }
            history?.usage?.forEach { Detail(it.label, it.value) }
        }
        GroupLabel("Station")
        Column(Modifier.padding(top = 6.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Detail("名字", rememberStationName(station))
            if (host != null) Detail("机器", "${host.hostname} · ${host.summary}")
        }
        if (host != null) Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            host.meters.forEach { Ring(it.percent, it.short, it.level) }
        }
    }
}

/** How it runs, in one line: the model (never cut short), how hard it thinks, the account (cut short first). */
@Composable
private fun RunRow(agent: ChatAgent, onOpen: () -> Unit) {
    val s = agent.session
    // The account it runs on now, as the core says.
    val name = agent.account?.name ?: ""
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp).clip(RoundedCornerShape(10.dp))
            .border(1.dp, C.line, RoundedCornerShape(10.dp)).clickable(onClick = onOpen).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        MakerIcon(s.maker, s.runtime, 15.dp)
        Text(s.model?.let { s.modelName ?: it } ?: "选模型", fontSize = 14.sp, color = C.ink, maxLines = 1, softWrap = false)
        Text(
            " · ${s.effort ?: "默认深度"} · ${if (s.profilePinned == true) name else "自动 · $name"}",
            fontSize = 14.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        IconIn(Icons.ChevronDown, 14.dp, C.muted)
    }
}

/**
 * Changing how an agent runs, full screen: what it is now, then the model, how hard it thinks and who runs it (the
 * station's pick, or one profile kept to), each said in plain words. Picks are a draft; the button at the bottom says
 * what it becomes (不变 when nothing changed); back leaves it as it was. A profile kept to that does not run the model
 * picked gives way to the station's pick, said so.
 */
@Composable
fun RunSettingsScreen(station: String, of: ChatOf, key: String) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
    val agent = chat.value?.agents?.firstOrNull { it.session.key == key }
    // A long list (the models, the accounts) is a list of its own, picked from and back.
    var list by remember { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler(enabled = list != null) { list = null }
    Column(Modifier.fillMaxSize()) {
        NavBar(if (list != null) "换模型" else "返回", { if (list != null) list = null else app.pop() }, when (list) { "model" -> "选模型"; "account" -> "选账号"; else -> "换模型" })
        if (agent == null) return Text(chat.error?.message ?: "正在读取…", color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(18.dp))
        val s = agent.session
        val current = agent.account
        val currentName = current?.name ?: ""
        val kept = if (s.profilePinned == true) s.profile else null
        var model by remember { mutableStateOf(s.model) }
        var effort by remember { mutableStateOf(s.effort) }
        var profile by remember { mutableStateOf(kept) }
        var busy by remember { mutableStateOf(false) }
        val choice = agent.choices.optionOf(model)
        val named = { m: String? -> m?.let { if (it == s.model) s.modelName ?: it else agent.choices.optionOf(it)?.name ?: it } }
        val accounts = choice?.accounts?.get(s.runtime).orEmpty()
        val chosen = profile?.takeIf { p -> accounts.any { it.id == p } }
        val dropped = profile != null && chosen == null
        val efforts = listOf<String?>(null) + s.efforts
        // Another spelling of its model is its model.
        val changed = (model != s.model && (choice == null || choice != agent.choices.optionOf(s.model))) || effort != s.effort || chosen != kept
        val accountText = { id: String? -> if (id == null) "自动分配" else accounts.firstOrNull { it.id == id }?.name ?: id }
        if (list == "model") return ModelList(agent.choices, s.runtime, model) { model = it; list = null }
        if (list == "account") return AccountList(accounts, s.runtime, chosen) { profile = it; list = null }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
            // Always on top: what it was, and what it becomes, the changes marked; and when the account must change, why.
            val was = listOf(named(s.model) ?: "默认模型", s.effort ?: "默认深度", if (kept != null) currentName else "自动 · $currentName")
            // The station's pick moves off an account without the model (the one it is on now, when it has it).
            val movesOff = chosen == null && kept == null && model != null && current != null && accounts.none { it.id == current.id }
            val becomes = listOf(named(model) ?: "默认模型", effort ?: "默认深度", when {
                chosen != null -> accountText(chosen)
                movesOff -> "自动（换账号）"
                current != null && accounts.any { it.id == current.id } -> "自动 · $currentName"
                else -> "自动分配"
            })
            val force = when {
                dropped -> "指定的账号「${accountText(profile)}」没有启用 ${named(model)}，改成了自动分配"
                movesOff -> "现在的账号「$currentName」没有启用 ${named(model)}，会自动换一个启用了的"
                else -> null
            }
            Column(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(14.dp)).background(C.chip).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                // Each property on its line: what it was, and, when it changes, an arrow to what it becomes.
                listOf("模型", "深度", "账号").forEachIndexed { i, label ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(label, fontSize = 13.sp, color = C.muted, modifier = Modifier.width(32.dp))
                        val moved = becomes[i] != was[i]
                        Text(was[i], fontSize = 14.sp, color = if (moved) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = !moved))
                        if (moved) {
                            IconIn(Icons.ArrowRight, 14.dp, C.accent)
                            Text(becomes[i], fontSize = 14.sp, color = C.accent, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        }
                    }
                }
                if (force != null) Text(force, fontSize = 12.sp, color = C.warn)
                Text("改了以后从下一轮开始生效。", fontSize = 12.sp, color = C.subtle)
            }
            GroupLabel("模型")
            SettingRow(onClick = { list = "model" }, leading = { MakerIcon(choice?.maker, s.runtime, 18.dp) }) { Text(named(model) ?: "选一个模型", fontSize = 15.sp, color = C.ink) }
            GroupLabel("思考深度")
            Text("想得越深越慢，也越费额度。", fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(bottom = 8.dp))
            EffortChips(efforts, effort) { effort = it }
            GroupLabel("账号")
            SettingRow(onClick = { list = "account" }, leading = { chosen?.let { id -> accounts.firstOrNull { it.id == id } }?.let { ProviderMark(it.runtime ?: s.runtime, it.kind, 18.dp) } }) {
                Text(accountText(chosen), fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(if (chosen == null) "额度用完或登录失效时换一个" else "固定用它", fontSize = 12.sp, color = C.muted)
                if (dropped || (chosen == null && kept == null && current != null && model != null && accounts.none { it.id == current.id })) Text("这个模型要换账号", fontSize = 12.sp, color = C.warn)
            }
            Box(Modifier.height(16.dp))
        }
        val go = changed && choice != null && !busy
        Box(
            Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp, vertical = 12.dp).fillMaxWidth().heightIn(min = 52.dp)
                .clip(RoundedCornerShape(16.dp)).background(if (changed) C.ink else C.chip)
                .clickable(enabled = !busy) {
                    if (!go) { app.pop(); return@clickable }
                    busy = true
                    scope.launch {
                        try { app.api(station).sessionSettings(s.key, if (choice == agent.choices.optionOf(s.model)) s.model ?: choice!!.model else choice!!.model, effort, chosen); app.toast = "已改，下一轮起生效"; app.pop() }
                        catch (err: CoreException) { app.toast = err.message }
                        finally { busy = false }
                    }
                }
                .padding(horizontal = 16.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (changed) "改成 ${named(model) ?: "默认模型"} · ${effort ?: "默认深度"} · ${accountText(chosen)}" else "不变",
                fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (changed) C.bg else C.ink, maxLines = 2, textAlign = TextAlign.Center,
            )
        }
    }
}

/** A line that leads to a list: what is chosen, and an arrow. */
@Composable
internal fun SettingRow(onClick: () -> Unit, leading: @Composable () -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.chip).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        leading()
        Column(Modifier.weight(1f), content = content)
        IconIn(Icons.ChevronRight, 16.dp, C.muted)
    }
}

/** The option a model is, however it is spelled (openai/gpt-6-astra is gpt-6-astra). */
internal fun List<ModelOption>.optionOf(model: String?): ModelOption? =
    if (model == null) null else firstOrNull { it.model == model } ?: firstOrNull { model in it.ids }

/** Every model it can move to, by series (the core says); a filter once there are many. */
@Composable
internal fun ModelList(models: List<ModelOption>, runtime: String, picked: String?, onPick: (String) -> Unit) {
    var filter by remember { mutableStateOf("") }
    val shown = models.filter { m -> (listOf(m.name, m.model) + m.ids).any { it.contains(filter.trim(), ignoreCase = true) } }
    val on = models.optionOf(picked)
    // By series, in the core's order.
    val groups = shown.groupBy { it.family ?: "其他" }
    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        if (models.size > 8) Field(filter, { filter = it }, "搜索模型", modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            groups.forEach { (who, list) ->
                if (groups.size > 1) GroupLabel(who)
                list.forEach { m -> PickLine(m.name, checked = m == on, onClick = { onPick(m.model) }, leading = { MakerIcon(m.maker, runtime, 18.dp) }) }
            }
            if (shown.isEmpty()) Text("没有叫这个的模型", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(vertical = 16.dp))
            Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(16.dp))
        }
    }
}

/** Who can run the model picked: the station's pick, or one kept to, with its quota. */
@Composable
internal fun AccountList(accounts: List<RunnableProfile>, runtime: String, picked: String?, onPick: (String?) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
        Text("自动分配时，额度用完或登录失效会换一个；指定了就一直用它。", fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
        PickLine("自动分配", checked = picked == null, onClick = { onPick(null) })
        accounts.forEach { p ->
            PickLine(p.name, checked = picked == p.id, onClick = { onPick(p.id) },
                leading = { ProviderMark(p.runtime ?: runtime, p.kind, 18.dp) }, trailing = { QuotaRings(p.quota) })
        }
        Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(16.dp))
    }
}

/** How hard it thinks, as chips as wide as their words, wrapping when they do not fit a line. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
internal fun EffortChips(efforts: List<String?>, picked: String?, onPick: (String?) -> Unit) {
    androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        efforts.forEach { e ->
            val on = e == picked
            Text(
                e ?: "默认", fontSize = 14.sp, color = if (on) C.bg else C.ink, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                modifier = Modifier.clip(RoundedCornerShape(18.dp)).background(if (on) C.ink else C.chip).clickable { onPick(e) }.padding(horizontal = 16.dp, vertical = 9.dp),
            )
        }
    }
}

/** A choice in a list: what it is, a note under it, and a check when it is the one chosen. */
@Composable
internal fun PickLine(label: String, sub: String? = null, checked: Boolean, onClick: () -> Unit, leading: (@Composable () -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        leading?.invoke()
        Column(Modifier.weight(1f)) {
            Text(label, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, fontSize = 12.sp, color = C.muted)
        }
        trailing?.invoke()
        Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) { if (checked) IconIn(Icons.Check, 16.dp, C.accent) }
    }
}

@Composable
private fun Detail(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, fontSize = 14.sp, color = C.muted, modifier = Modifier.width(64.dp))
        Text(value, fontSize = 14.sp, color = C.ink)
    }
}

/** Seconds in short, as the chat's activity says them: 45s, 3m 20s, 10m, 1h 5m. */
private fun shortSpan(s: Long): String = when {
    s < 60 -> "${s}s"
    s < 3600 -> if (s % 60 != 0L) "${s / 60}m ${s % 60}s" else "${s / 60}m"
    else -> if (s % 3600 / 60 != 0L) "${s / 3600}h ${s % 3600 / 60}m" else "${s / 3600}h"
}
