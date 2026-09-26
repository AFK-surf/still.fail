// An agent's execution history (web/src/History.tsx), as a sheet that drags
// between half and full height: what it received and what it sent, drawn
// alike (a line, then the words beside a bar); what it did in between,
// grouped, each group opening to its commands and output; and its details
// (model, allowance, the station it runs on).
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.WindowInsets
import dev.ember.android.ui.NavBar
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
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.Screen
import dev.ember.android.data.ChatAgentView
import dev.ember.android.data.ChatOf
import dev.ember.android.data.ChatView
import dev.ember.android.data.RunnableProfile
import dev.ember.android.data.maker
import dev.ember.android.data.Maker
import dev.ember.android.data.EFFORTS
import dev.ember.android.data.HistoryItem
import dev.ember.android.data.HostInfo
import dev.ember.android.data.LiveStep
import dev.ember.android.data.LiveView
import dev.ember.android.data.Overview
import dev.ember.android.data.PROCESS_LABEL
import dev.ember.android.data.RUNTIME_LABEL
import dev.ember.android.data.ShownPhase
import dev.ember.android.data.SourcedMessage
import dev.ember.android.data.Status
import dev.ember.android.data.Step
import dev.ember.android.data.Topics
import dev.ember.android.data.agentLabel
import dev.ember.android.data.compactNumber
import dev.ember.android.data.duration
import dev.ember.android.data.gb
import dev.ember.android.data.historyItems
import dev.ember.android.data.placeName
import dev.ember.android.data.rememberTopic
import dev.ember.android.data.splitThread
import dev.ember.android.data.state
import dev.ember.android.data.status
import dev.ember.android.data.stepLabel
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.MakerIcon
import dev.ember.android.ui.ProviderMark
import dev.ember.android.ui.QuotaRing
import dev.ember.android.ui.QuotaRings
import dev.ember.android.ui.quotaMark
import dev.ember.android.ui.Icons
import dev.ember.android.ui.Mark
import dev.ember.android.ui.Markdown
import dev.ember.android.ui.MenuItem
import dev.ember.android.ui.MenuSpec
import dev.ember.android.ui.ModelMark
import dev.ember.android.ui.Mono
import dev.ember.android.ui.ReaderSpec
import dev.ember.android.ui.Ring
import dev.ember.android.ui.Seg
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetSpec
import dev.ember.android.ui.SlackMark
import dev.ember.android.ui.rememberFollow
import dev.ember.core.CoreException
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.animation.core.tween
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Opens an agent's execution history, over the item's page it belongs to. */
/** `entry`: the transcript entry to open at (an activity row's), else its newest. */
fun openHistory(app: AppState, station: String, of: ChatOf, key: String, entry: Int? = null) {
    app.sheet = SheetSpec(0.55f, draggable = true) { HistorySheet(station, of, key, entry) }
}

@Composable
private fun ColumnScope.HistorySheet(station: String, of: ChatOf, key: String, entry: Int? = null) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
    val live by rememberTopic<LiveView>(app.core, Topics.live(station, key))
    val host by rememberTopic<HostInfo>(app.core, Topics.host(station))
    val agent = chat.value?.agents?.firstOrNull { it.session.key == key }
    var tab by rememberSaveable { mutableStateOf(0) }
    SheetGrab()
    if (agent == null) {
        Text(chat.error?.message ?: "正在读取…", color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(18.dp))
        return
    }
    val s = agent.session
    val model = live.value?.usage?.model ?: s.model
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ModelMark(model, s.runtime, 20.dp, agent.state)
        // The sheet is the agent's history; its head is the agent, with the room its name needs.
        Text(agentLabel(model, s.effort), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Actions(station, agent)
        Seg(listOf("步骤", "详情"), tab, { tab = it })
    }
    Summary(agent)
    Box(Modifier.weight(1f).fillMaxWidth()) {
        if (tab == 0) Steps(station, of, agent, live.value, entry) else Details(station, of, agent, live.value, host.value)
    }
}

/** What can be done to it right now: stop a turn, release an idle process. */
@Composable
private fun Actions(station: String, agent: ChatAgentView) {
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
private fun Summary(agent: ChatAgentView) {
    if (agent.attention.isEmpty()) return Box(Modifier.height(8.dp))
    Row(
        Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 6.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        agent.attention.forEach { a ->
            when (a.kind) {
                "quota" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    QuotaRing(100.0 - a.left)
                    Text(quotaMark(a.label).first, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = C.subtle)
                }
                "disk" -> Text("磁盘剩 ${gb(a.freeBytes.toLong())}", fontSize = 12.sp, color = C.warn)
                else -> Text(if (a.state == "login") "「${a.name}」要重新登录" else "「${a.name}」的 key 被拒绝", fontSize = 12.sp, color = C.red)
            }
        }
    }
}

private sealed interface Line {
    data class Item(val item: HistoryItem) : Line
    data class Live(val step: LiveStep) : Line
    data class Phase(val phase: ShownPhase) : Line
}

@Composable
private fun Steps(station: String, of: ChatOf, agent: ChatAgentView, live: LiveView?, entry: Int? = null) {
    val app = LocalApp.current
    val overview by rememberTopic<Overview>(app.core, Topics.overview(station))
    val person = rememberPeople(station)
    val timeline = live?.timeline
    val spans = remember(timeline) { mutableListOf<IntRange>() }
    val items = remember(timeline) { historyItems(timeline ?: emptyList(), spans) }
    val steps = live?.steps.orEmpty().filter { !it.subagent && it.step != "tool" }
    val phase = live?.phase
    if (live?.loaded != true && items.isEmpty()) return Edge("正在读取执行历史…")
    if (items.isEmpty() && steps.isEmpty() && phase == null) {
        return Edge(if (agent.session.runtimeSessionId != null) "找不到运行时记录，可能已归档。" else "运行时还没开始这个会话。")
    }
    val lines = items.map { Line.Item(it) } + steps.map { Line.Live(it) } + listOfNotNull(phase?.let { Line.Phase(it) })
    val list = rememberLazyListState()
    val follow = rememberFollow(list)
    // It opens at its newest, and follows new steps while the reader stays there.
    val density = LocalDensity.current
    // Opened at an entry (an activity row): that item, near the top, for a moment marked; else the newest, followed.
    var marked by remember { mutableStateOf(-1) }
    LaunchedEffect(Unit) {
        val at = entry?.let { e -> spans.indexOfFirst { e in it } }?.takeIf { it >= 0 }
        if (at != null) {
            list.scrollToItem(at + 1, -with(density) { 24.dp.roundToPx() })
            follow.placed = true; follow.on = false
            marked = at
            delay(1600); marked = -1
        } else {
            follow.toEnd(); follow.placed = true; follow.on = true
        }
    }
    val bot = agent.connect?.botUserId
    val mention = { text: String -> text.replace(Regex("<@([A-Z0-9]+)>")) { r -> val id = r.groupValues[1]; "@" + (if (id == bot) agent.connect?.name ?: id else person(id) ?: id) } }
    val bound = overview.value?.slackUsers.orEmpty()
    LazyColumn(Modifier.fillMaxWidth(), state = list, contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item(key = "edge") { Edge("已到 Session 开始处") }
        itemsIndexed(lines, key = { i, l -> if (l is Line.Live) "live/${l.step.id}" else if (l is Line.Phase) "phase" else "i$i" }) { i, line ->
            when (line) {
                is Line.Item -> {
                    val shade by androidx.compose.animation.animateColorAsState(if (i == marked) C.accent.copy(alpha = 0.10f) else androidx.compose.ui.graphics.Color.Transparent, tween(900), label = "marked")
                    Box(Modifier.clip(RoundedCornerShape(8.dp)).background(shade)) { Item(line.item, station, of, agent, mention, bound, person) }
                }
                is Line.Live -> LiveStepView(line.step)
                is Line.Phase -> PhaseLine(line.phase, RUNTIME_LABEL[agent.session.runtime] ?: agent.session.runtime)
            }
        }
    }
}

@Composable
private fun Edge(text: String) = Text(text, color = C.subtle, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp))

@Composable
private fun Item(item: HistoryItem, station: String, of: ChatOf, agent: ChatAgentView, mention: (String) -> String, bound: List<String>, person: (String) -> String?) {
    when (item) {
        is HistoryItem.Received -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (item.note.isNotEmpty()) Message(Icons.Received, { Text("收到来自 ", fontSize = 13.sp, color = C.muted); Strong("ember"); Text(" 的提醒", fontSize = 13.sp, color = C.muted) }, item.note) {
                Text(item.note, fontSize = 15.sp, lineHeight = 23.sp, color = C.ink)
            }
            item.messages.forEach { m ->
                val text = mention(m.text)
                Message(Icons.Received, {
                    Text("收到来自 ", fontSize = 13.sp, color = C.muted)
                    if (m.slack) SlackName(station, m, bound) else Strong(person(m.user) ?: m.name ?: m.user)
                    Text(" 的消息", fontSize = 13.sp, color = C.muted)
                    m.thread?.let { Text(" · ", fontSize = 13.sp, color = C.muted); Box(Modifier.weight(1f, fill = false)) { Place(station, of, agent, it) } }
                }, text) { Text(text, fontSize = 15.sp, lineHeight = 23.sp, color = C.ink) }
            }
        }
        is HistoryItem.Post -> Message(Icons.Send, {
            Text("发送到 ", fontSize = 13.sp, color = C.muted)
            Box(Modifier.weight(1f, fill = false)) {
                if (item.to != null) Place(station, of, agent, item.to) else Row(verticalAlignment = Alignment.CenterVertically) { SlackMark(12.dp); Strong(" Slack") }
            }
            if (item.kind == "block") Pill("Block", C.blue)
            if (item.failed) Pill("发送失败", C.red)
        }, item.text) { Markdown(item.text, size = 15) }
        is HistoryItem.Mark -> Text(
            when (item.kind) { "final" -> "标记为已完成"; "block" -> "进入 block 状态：agent 停下来等人处理"; else -> "标记为 ${item.kind}" },
            fontSize = 13.sp, color = C.muted,
        )
        is HistoryItem.Text -> Box(Modifier.let { if (item.subagent) it.padding(start = 12.dp) else it }) {
            val app = LocalApp.current
            val model = agentLabel(agent.session.model, null)
            Brief(item.text) { app.reader = ReaderSpec({ Text("$model 写道", fontSize = 13.sp, color = C.muted) }) { Markdown(item.text, size = 15) } }
        }
        is HistoryItem.Group -> Group(item)
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

/** A thread as a place: its platform's mark and its name; a chat on ember's page leads to it. */
@Composable
private fun Place(station: String, of: ChatOf, agent: ChatAgentView, address: String) {
    val app = LocalApp.current
    val (channel, ts) = splitThread(address) ?: return Strong(address)
    val thread = agent.threads.firstOrNull { it.channel == channel && it.threadTs == ts }
    // An ember chat is its agent's item: opened by the session it is bound to.
    val bound = thread?.takeIf { channel == "EMBER" }?.sessions?.firstOrNull()?.session
    val open = bound?.let { key -> { if (of != ChatOf.Session(key)) app.push(Screen.Chat(station, ChatOf.Session(key))) else app.sheet = null } }
    Row(
        Modifier.clip(RoundedCornerShape(4.dp)).let { if (open != null) it.clickable(onClick = open) else it },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (channel == "EMBER") Mark(12.dp) else SlackMark(12.dp)
        Text(placeName(agent.threads, channel, ts), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (open != null) C.accentInk else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * A Slack user's name: "你" once the viewer said it is them. A tap offers "这是我" (the station then takes that Slack
 * user for the viewer), or "不是我" once it does.
 */
@Composable
private fun SlackName(station: String, m: SourcedMessage, bound: List<String>) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val mine = m.user in bound
    var bounds by remember { mutableStateOf(Rect.Zero) }
    Text(
        if (mine) "你" else m.name ?: m.user, fontSize = 13.sp, color = C.accentInk, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.onGloballyPositioned { bounds = it.boundsInRoot() }.clip(RoundedCornerShape(4.dp)).clickable {
            app.menu = MenuSpec(bounds, listOf(MenuItem(if (mine) "不是我" else "这是我", if (mine) Icons.Close else Icons.Check) {
                scope.launch {
                    try {
                        app.api(station).slackIdentity(m.user, !mine)
                    } catch (e: CoreException) {
                        app.toast = "${if (mine) "解除" else "绑定"}没有成功：${e.message}"
                    }
                }
            }))
        },
    )
}

@Composable
private fun Group(g: HistoryItem.Group) {
    var open by remember { mutableStateOf(false) }
    Column {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).clickable { open = !open }.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            IconIn(if (open) Icons.ChevronDown else Icons.ChevronRight, 13.dp, C.subtle)
            Text(g.summary, color = if (g.failed > 0) C.red else C.muted, fontSize = 14.sp, maxLines = if (open) 3 else 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (g.failed > 0) Pill("${g.failed} 项失败", C.red)
            if (g.pending > 0) Pill("${g.pending} 项进行中", C.accentInk)
        }
        if (open) Column(Modifier.padding(start = 19.dp, top = 4.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            g.thinking.forEach { t ->
                if (g.steps.isEmpty()) Text(t.text, fontSize = 13.sp, lineHeight = 20.sp, color = C.muted)
                else Folding("思考", t.text.lineSequence().firstOrNull { it.isNotBlank() } ?: "", null, false) { Text(t.text, fontSize = 13.sp, lineHeight = 20.sp, color = C.muted) }
            }
            g.steps.forEach { StepRow(it) }
        }
    }
}

@Composable
private fun StepRow(step: Step) {
    val (label, hint) = stepLabel(step)
    val result = step.result
    val took = result?.at?.let { r -> step.call.at?.let { c -> parseIso(r) - parseIso(c) } }
    val meta = when {
        result == null -> "进行中"
        result.ok == false -> "失败"
        took != null && took >= 0 -> duration(took)
        else -> ""
    }
    Folding(label, hint, meta, result?.ok == false) {
        Code(step.call.text)
        result?.let { Code(it.text, failed = it.ok == false) }
    }
}

private fun parseIso(at: String): Long = try { java.time.Instant.parse(at).toEpochMilli() } catch (_: java.time.format.DateTimeParseException) { 0 }

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

@Composable
private fun Code(text: String, failed: Boolean = false) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (failed) C.red.copy(alpha = 0.08f) else C.surface2).horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 8.dp)) {
        Text(text.take(4000), style = Mono, color = C.ink, softWrap = false, maxLines = 40)
    }
}

/** A step in flight, as the station tells it (its turning points): writing or thinking; what it wrote comes with its entry. */
@Composable
private fun LiveStepView(step: LiveStep) {
    Text(if (step.step == "text") "正在输出…" else "正在思考…", fontSize = 13.sp, color = C.muted, maxLines = 1)
}

/** The turn's state with the model, with a running clock: starting up, waiting for the first token, working, or thinking. */
@Composable
private fun PhaseLine(phase: ShownPhase, runtime: String) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val text = when (phase.phase) { "starting" -> "正在启动 $runtime"; "requesting" -> "已发送请求，等待模型响应"; "working" -> "执行工具中"; else -> "Thinking" }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent))
        Text(text, fontSize = 13.sp, color = C.ink)
        Text("${((now - phase.since) / 1000).coerceAtLeast(0)}s", fontSize = 12.sp, color = C.subtle)
    }
}

/** How it runs (which can be changed here), what it has used, the station. */
@Composable
private fun Details(station: String, of: ChatOf, agent: ChatAgentView, live: LiveView?, host: HostInfo?) {
    val app = LocalApp.current
    val s = agent.session
    val usage = live?.usage
    val hit = usage?.takeIf { it.inputTokens > 0 }?.let { Math.round(it.cachedTokens * 100.0 / it.inputTokens) }
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
        // Changing how it runs is a screen of its own.
        RunRow(agent) { app.push(Screen.RunSettings(station, of, s.key)) }
        Column(Modifier.padding(top = 12.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Detail("运行时", RUNTIME_LABEL[s.runtime] ?: s.runtime)
            Detail("进程", PROCESS_LABEL[s.process] ?: s.process)
            if (usage != null) {
                Detail("调用", "${usage.modelCalls} 次")
                Detail("输入", compactNumber(usage.inputTokens) + (hit?.let { " · 缓存 $it%" } ?: ""))
                Detail("输出", compactNumber(usage.outputTokens))
            }
        }
        GroupLabel("Station")
        Column(Modifier.padding(top = 6.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Detail("名字", rememberStationName(station))
            if (host != null) Detail("机器", "${host.hostname} · ${host.cpus} 核 · ${gb(host.memory.totalBytes)}")
        }
        if (host != null) Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            Ring(host.cpuPercent, "CPU"); Ring(host.memPercent, "内存")
            if (host.disk.totalBytes > 0) Ring(host.diskPercent, "磁盘")
        }
    }
}

/** How it runs, in one line: the model (never cut short), how hard it thinks, the account (cut short first). */
@Composable
private fun RunRow(agent: ChatAgentView, onOpen: () -> Unit) {
    val s = agent.session
    val current = agent.profiles.firstOrNull { it.current }
    val name = current?.name ?: agent.profile?.name ?: s.profile
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp).clip(RoundedCornerShape(10.dp))
            .border(1.dp, C.line, RoundedCornerShape(10.dp)).clickable(onClick = onOpen).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        MakerIcon(s.model, s.runtime, 15.dp)
        Text(s.model ?: "选模型", fontSize = 14.sp, color = C.ink, maxLines = 1, softWrap = false)
        Text(
            " · ${s.effort ?: "默认深度"} · ${if (s.profilePinned) name else "自动 · $name"}",
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
        val current = agent.profiles.firstOrNull { it.current }
        val currentName = current?.name ?: agent.profile?.name ?: s.profile
        val kept = if (s.profilePinned) s.profile else null
        var model by remember { mutableStateOf(s.model) }
        var effort by remember { mutableStateOf(s.effort) }
        var profile by remember { mutableStateOf(kept) }
        var busy by remember { mutableStateOf(false) }
        val choice = agent.choices.firstOrNull { it.model == model }
        val accounts = choice?.profiles.orEmpty()
        val chosen = profile?.takeIf { p -> accounts.any { it.id == p } }
        val dropped = profile != null && chosen == null
        val efforts = listOf<String?>(null) + EFFORTS[s.runtime].orEmpty()
        val changed = model != s.model || effort != s.effort || chosen != kept
        val accountText = { id: String? -> if (id == null) "自动分配" else accounts.firstOrNull { it.id == id }?.name ?: id }
        if (list == "model") return ModelList(agent.choices.map { it.model }, s.runtime, model) { model = it; list = null }
        if (list == "account") return AccountList(accounts, s.runtime, chosen) { profile = it; list = null }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
            // Always on top: what it was, and what it becomes, the changes marked; and when the account must change, why.
            val was = listOf(s.model ?: "默认模型", s.effort ?: "默认深度", if (kept != null) currentName else "自动 · $currentName")
            // The station's pick moves off an account without the model (the one it is on now, when it has it).
            val movesOff = chosen == null && kept == null && model != null && current != null && accounts.none { it.id == current.id }
            val becomes = listOf(model ?: "默认模型", effort ?: "默认深度", when {
                chosen != null -> accountText(chosen)
                movesOff -> "自动（换账号）"
                current != null && accounts.any { it.id == current.id } -> "自动 · $currentName"
                else -> "自动分配"
            })
            val force = when {
                dropped -> "指定的账号「${accountText(profile)}」没有启用 $model，改成了自动分配"
                movesOff -> "现在的账号「$currentName」没有启用 $model，会自动换一个启用了的"
                else -> null
            }
            Column(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(14.dp)).background(C.chip).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("原来", fontSize = 13.sp, color = C.muted, modifier = Modifier.width(32.dp))
                    Text(was.joinToString(" · "), fontSize = 14.sp, color = C.ink)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("改成", fontSize = 13.sp, color = C.muted, modifier = Modifier.width(32.dp))
                    if (!changed && !movesOff) Text("不变", fontSize = 14.sp, color = C.muted)
                    else Text(
                        androidx.compose.ui.text.buildAnnotatedString {
                            becomes.forEachIndexed { i, part ->
                                if (i > 0) append(" · ")
                                if (part != was[i]) withStyle(androidx.compose.ui.text.SpanStyle(color = C.accent, fontWeight = FontWeight.SemiBold)) { append(part) } else append(part)
                            }
                        },
                        fontSize = 14.sp, color = C.ink,
                    )
                }
                if (force != null) Text(force, fontSize = 12.sp, color = C.warn)
                Text("改了以后从下一轮开始生效。", fontSize = 12.sp, color = C.subtle)
            }
            GroupLabel("模型")
            SettingRow(onClick = { list = "model" }, leading = { MakerIcon(model, s.runtime, 18.dp) }) { Text(model ?: "选一个模型", fontSize = 15.sp, color = C.ink) }
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
                        try { app.api(station).sessionSettings(s.key, choice!!.model, effort, chosen); app.toast = "已改，下一轮起生效"; app.pop() }
                        catch (err: CoreException) { app.toast = err.message }
                        finally { busy = false }
                    }
                }
                .padding(horizontal = 16.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (changed) "改成 ${model ?: "默认模型"} · ${effort ?: "默认深度"} · ${accountText(chosen)}" else "不变",
                fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (changed) C.bg else C.ink, maxLines = 2, textAlign = TextAlign.Center,
            )
        }
    }
}

/** A line that leads to a list: what is chosen, and an arrow. */
@Composable
private fun SettingRow(onClick: () -> Unit, leading: @Composable () -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.chip).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        leading()
        Column(Modifier.weight(1f), content = content)
        IconIn(Icons.ChevronRight, 16.dp, C.muted)
    }
}

/** Every model it can move to, by who made it; a filter once there are many. */
@Composable
private fun ModelList(models: List<String>, runtime: String, picked: String?, onPick: (String) -> Unit) {
    var filter by remember { mutableStateOf("") }
    val shown = models.filter { it.contains(filter.trim(), ignoreCase = true) }
    val groups = shown.groupBy { maker(it, runtime) }.toSortedMap(compareBy { it.name })
    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        if (models.size > 8) Field(filter, { filter = it }, "搜索模型", modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            groups.forEach { (who, list) ->
                if (groups.size > 1) GroupLabel(MAKER_NAME[who] ?: who.name)
                list.forEach { m -> PickLine(m, checked = m == picked, onClick = { onPick(m) }, leading = { MakerIcon(m, runtime, 18.dp) }) }
            }
            if (shown.isEmpty()) Text("没有叫这个的模型", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(vertical = 16.dp))
            Box(Modifier.windowInsetsPadding(WindowInsets.navigationBars).height(16.dp))
        }
    }
}

private val MAKER_NAME = mapOf(Maker.Anthropic to "Anthropic", Maker.OpenAI to "OpenAI", Maker.DeepSeek to "DeepSeek", Maker.Zhipu to "智谱")

/** Who can run the model picked: the station's pick, or one kept to, with its quota. */
@Composable
private fun AccountList(accounts: List<RunnableProfile>, runtime: String, picked: String?, onPick: (String?) -> Unit) {
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
private fun EffortChips(efforts: List<String?>, picked: String?, onPick: (String?) -> Unit) {
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
private fun PickLine(label: String, sub: String? = null, checked: Boolean, onClick: () -> Unit, leading: (@Composable () -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
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
