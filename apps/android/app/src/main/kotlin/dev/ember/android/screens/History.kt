// An agent's execution history, as a sheet that drags between half and full
// height: what it received, what it did (grouped, each group opening to its
// commands and output), what it posted; and its details (model, quota, the
// station it runs on).
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.data.Agent
import dev.ember.android.data.ChatState
import dev.ember.android.data.ChatView
import dev.ember.android.data.EFFORT_LABEL
import dev.ember.android.data.HistoryItem
import dev.ember.android.data.LiveView
import dev.ember.android.data.StationView
import dev.ember.android.data.Thread
import dev.ember.android.data.Topics
import dev.ember.android.data.activityText
import dev.ember.android.data.compactNumber
import dev.ember.android.data.historyItems
import dev.ember.android.data.rememberTopic
import dev.ember.android.data.stepLabel
import dev.ember.android.ui.C
import dev.ember.android.ui.Markdown
import dev.ember.android.ui.ModelMark
import dev.ember.android.ui.Mono
import dev.ember.android.ui.Ring
import dev.ember.android.ui.Seg
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetSpec
import kotlinx.coroutines.delay

fun openHistory(app: AppState, thread: Thread, agent: Agent) {
    app.sheet = SheetSpec(0.55f, draggable = true) { HistorySheet(thread, agent) }
}

@Composable
private fun ColumnScope.HistorySheet(thread: Thread, agent: Agent) {
    val app = LocalApp.current
    val chat by rememberTopic<ChatView>(app.core, Topics.chat(agent.station, agent.key))
    val live by rememberTopic<LiveView>(app.core, Topics.live(agent.station, agent.key))
    var tab by rememberSaveable { mutableStateOf(0) }
    SheetGrab()
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ModelMark(agent.model, 20.dp)
        Text(agent.model ?: "默认模型", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1)
        // On a narrow screen the words give way before the model's name does.
        Text("执行历史", fontSize = 13.sp, color = C.muted, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip, modifier = Modifier.weight(1f))
        Seg(listOf("步骤", "详情"), tab, { tab = it })
    }
    val view = chat.value
    Box(Modifier.weight(1f).fillMaxWidth()) {
        when {
            view == null -> Text(chat.error?.message ?: "正在读取…", color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(18.dp))
            tab == 0 -> Steps(view, live.value, agent.state == ChatState.Running || view.session.process == "running")
            else -> Details(view, live.value, agent)
        }
    }
}

@Composable
private fun Steps(view: ChatView, live: LiveView?, running: Boolean) {
    val names = (view.session.participants + listOfNotNull(view.session.creator)).associate { it.id to it.name }
    val timeline = live?.timeline
    val items = remember(timeline) { historyItems(timeline ?: emptyList()) { names[it] ?: it } }
    if (timeline == null || timeline.isEmpty()) {
        Text(if (live == null || !live.loaded) "正在读取…" else if (view.turns.isEmpty()) "运行时还没开始这个会话。" else "找不到运行时记录，可能已归档。", color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(18.dp))
        return
    }
    // Newest at the bottom, where the sheet opens.
    LazyColumn(Modifier.fillMaxWidth(), reverseLayout = true, contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
        item(key = "note") {
            Text("工具调用按它自己的描述显示；展开一组能看到命令和输出", color = C.subtle, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 16.dp))
        }
        if (running) item(key = "live") { LiveLine(live) }
        itemsIndexed(items.asReversed(), key = { i, _ -> items.size - i }) { _, item -> Item(item) }
        item(key = "edge") { Text("已到 Session 开始处", color = C.subtle, fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) }
    }
}

@Composable
private fun Item(item: HistoryItem) {
    when (item) {
        is HistoryItem.Received -> Column(Modifier.padding(vertical = 6.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.chip).padding(horizontal = 10.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(if (item.from == "ember") "收到来自 ember 的提醒" else "收到来自 ${item.from} 的消息", fontSize = 12.sp, color = C.subtle)
            Text(item.text, fontSize = 14.sp, color = C.ink, maxLines = 6, overflow = TextOverflow.Ellipsis)
        }
        is HistoryItem.Group -> Group(item)
        is HistoryItem.Post -> Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                "↗ 发出回复" + when { item.failed -> " · 发送失败"; item.kind == "block" -> " · block"; item.kind == "final" -> " · 已完成"; else -> "" },
                fontSize = 12.sp, color = if (item.failed) C.red else C.accentInk,
            )
            Text(item.text, fontSize = 14.sp, color = C.ink, maxLines = 8, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 16.dp))
        }
        is HistoryItem.Mark -> Text(
            when (item.kind) { "final" -> "标记为已完成"; "block" -> "进入 block 状态：agent 停下来等人处理"; else -> "标记为 ${item.kind}" },
            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(vertical = 8.dp),
        )
        is HistoryItem.Text -> Column(Modifier.padding(vertical = 8.dp)) { Markdown(item.text, size = 14) }
    }
}

@Composable
private fun Group(g: HistoryItem.Group) {
    var open by remember { mutableStateOf(false) }
    Column {
        Row(Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 9.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (open) "⌄" else "›", color = C.subtle, fontSize = 14.sp, modifier = Modifier.width(10.dp))
            Text(g.summary, color = C.muted, fontSize = 14.sp, maxLines = if (open) 3 else 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (g.failed > 0) Pill("${g.failed} 项失败", C.red)
            if (g.pending > 0) Pill("${g.pending} 项进行中", C.accentInk)
        }
        if (open) Column(Modifier.padding(start = 18.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (g.steps.isNotEmpty()) Text(g.counts, fontSize = 12.sp, color = C.subtle)
            g.thinking.forEach { Text(it.text, fontSize = 13.sp, color = C.muted, maxLines = 8, overflow = TextOverflow.Ellipsis) }
            g.steps.forEach { s ->
                val (label, hint) = stepLabel(s)
                Text(if (hint != null) "$label  $hint" else label, fontSize = 13.sp, color = if (s.result?.ok == false) C.red else C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Code(s.call.text)
                s.result?.let { Code(it.text) }
            }
        }
    }
}

@Composable
private fun Code(text: String) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(C.surface2).horizontalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 8.dp)) {
        Text(text.take(2000), style = Mono, color = C.ink, softWrap = false, maxLines = 12)
    }
}

@Composable
private fun Pill(text: String, color: androidx.compose.ui.graphics.Color) =
    Text(text, fontSize = 11.sp, color = color, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(C.chip).padding(horizontal = 6.dp, vertical = 2.dp))

/** The turn in flight: its newest step and how long the model has been at it. */
@Composable
private fun LiveLine(live: LiveView) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    val step = live.steps.lastOrNull { !it.ended && !it.subagent }
    val text = step?.let { if (it.step == "thinking") "正在思考" else activityText(it.tool, it.input) } ?: "正在处理"
    val phase = live.phase
    Column(Modifier.padding(vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.width(6.dp).height(6.dp).clip(RoundedCornerShape(3.dp)).background(C.accent))
            Text("$text…", fontSize = 14.sp, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (phase != null) {
            val what = when (phase.phase) { "starting" -> "正在启动"; "requesting" -> "等待模型响应"; "working" -> "执行工具中"; else -> "Thinking" }
            Text("$what ${((now - phase.since) / 1000).coerceAtLeast(0)}s", fontSize = 12.sp, color = C.subtle)
        }
    }
}

@Composable
private fun Details(view: ChatView, live: LiveView?, agent: Agent) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(agent.station.substringBefore('/')))
    val s = view.session
    val usage = live?.usage
    val hit = usage?.takeIf { it.inputTokens > 0 }?.let { (it.cachedTokens * 100 / it.inputTokens).toInt() }
    val st = stations.value?.firstOrNull { it.station == agent.station }
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
        GroupLabel("模型")
        Column(Modifier.padding(top = 6.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Detail("模型", usage?.model ?: s.model ?: "默认模型")
            Detail("思考深度", s.effort?.let { EFFORT_LABEL[it] ?: it } ?: "默认")
            Detail("Profile", view.profile?.name ?: s.profile)
            if (usage != null) Detail("消耗", "${compactNumber(usage.inputTokens + usage.outputTokens)} tokens" + (hit?.let { " · 缓存 $it%" } ?: ""))
        }
        GroupLabel("额度")
        val quota = view.profile?.quota
        if (quota?.state == "ok" && quota.windows.isNotEmpty()) {
            Row(Modifier.padding(vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) { quota.windows.forEach { Ring(it.usedPercent.toInt(), it.label) } }
        } else {
            Text("额度：${quota?.detail ?: if (quota != null) "查不到" else "还没查过"}", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(vertical = 10.dp))
        }
        GroupLabel("Station · ${st?.name ?: stationName(agent.station)}")
        val host = st?.host
        if (host != null) {
            Row(Modifier.padding(vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                Ring(host.cpuPercent, "CPU"); Ring(host.memPercent, "内存"); Ring(host.diskPercent, "磁盘")
            }
        } else {
            Text(if (st?.online == false) "离线" else "正在读取…", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(vertical = 10.dp))
        }
    }
}

@Composable
private fun Detail(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, fontSize = 14.sp, color = C.muted, modifier = Modifier.width(64.dp))
        Text(value, fontSize = 14.sp, color = C.ink)
    }
}
