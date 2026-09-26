// Home is an inbox: chats where an agent is blocked first (with quick
// replies), then running ones (one line of what they are doing), then the
// rest by day. A fixed head (you → settings · workspace · stations) and one
// bottom toolbar (全部 / 我参与的 · new chat), like Mail.
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.R
import dev.ember.android.Screen
import dev.ember.android.data.AccountWorkspaces
import dev.ember.android.data.ChatItem
import dev.ember.android.data.ChatState
import dev.ember.android.data.ChatsView
import dev.ember.android.data.LiveView
import dev.ember.android.data.Me
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.activityRows
import dev.ember.android.data.dayLabel
import dev.ember.android.data.entries
import dev.ember.android.data.inbox
import dev.ember.android.data.isMe
import dev.ember.android.data.relativeTime
import dev.ember.android.data.rememberTopic
import dev.ember.android.data.rowTime
import dev.ember.android.data.sessionTitle
import dev.ember.android.data.state
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.Illustration
import dev.ember.android.ui.ModelStack
import dev.ember.android.ui.NavButton
import dev.ember.android.ui.Seg
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.android.ui.avatarColor
import dev.ember.android.ui.hairlineTop
import dev.ember.android.ui.initial
import dev.ember.core.CoreException
import kotlinx.coroutines.launch

/**
 * Quick answers to a block. The agent's question carries no choices yet, so
 * these are the answers that fit most questions; the last opens the chat.
 */
internal val QUICK = listOf("可以，继续", "先别")

@Composable
fun HomeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val scope = current.workspace.id
    val chats by rememberTopic<ChatsView>(app.core, Topics.chats(scope, app.onlyMine))
    var query by rememberSaveable { mutableStateOf("") }
    val list = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        // The head stays put; search scrolls away with the chats.
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(34.dp).clip(CircleShape).background(avatarColor(current.account.email)).clickable { app.push(Screen.Me) }, contentAlignment = Alignment.Center) {
                Text(initial(current.account.name.ifEmpty { current.account.email }), color = androidx.compose.ui.graphics.Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
            Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { openWorkspaces(app) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(current.workspace.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                IconIn(Icons.ChevronDown, 16.dp, C.muted)
            }
            NavButton(Icons.Server, { app.push(Screen.Stations) }, 20.dp)
        }
        Box(Modifier.weight(1f)) {
            val view = chats.value
            val inbox = view?.inbox()
            val match = { c: ChatItem -> query.isBlank() || sessionTitle(c.session).contains(query.trim(), ignoreCase = true) }
            LazyColumn(Modifier.fillMaxSize(), state = list) {
                item(key = "search") { Search(query) { query = it } }
                if (view == null) {
                    item(key = "wait") { Quiet(chats.error?.message ?: "正在读取会话…") }
                } else if (inbox != null) {
                    val needs = inbox.needs.filter(match)
                    val running = inbox.running.filter(match)
                    if (needs.isNotEmpty()) {
                        item(key = "h-needs") { SectionHeader("需要你处理", "${needs.size} 个 agent 在 block") }
                        items(needs, key = { "n/${it.station}/${it.session.key}" }) { NeedCard(it, view.me) }
                    }
                    if (running.isNotEmpty()) {
                        item(key = "h-running") { SectionHeader("进行中", "${running.size}") }
                        items(running, key = { "r/${it.station}/${it.session.key}" }) { c ->
                            ChatRow(c, view.me, first = c == running.first()) { RunningLine(c) }
                        }
                    }
                    for ((day, rows) in inbox.rest) {
                        val shown = rows.filter(match)
                        if (shown.isEmpty()) continue
                        item(key = "h-${day.daysAgo}") { SectionHeader(dayLabel(day.daysAgo, day.at)) }
                        items(shown, key = { "d/${it.station}/${it.session.key}" }) { c ->
                            ChatRow(c, view.me, first = c == shown.first(), time = rowTime(c.session.lastActiveAt, day.daysAgo))
                        }
                    }
                    if (inbox.needs.isEmpty() && inbox.running.isEmpty() && inbox.rest.isEmpty()) item(key = "empty") { Empty(view, app.onlyMine) }
                }
                item(key = "pad") { Spacer(Modifier.height(96.dp)) }
            }
            Toolbar(app, Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun Search(query: String, onChange: (String) -> Unit) {
    Row(
        Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 10.dp).fillMaxWidth().height(36.dp).clip(RoundedCornerShape(11.dp)).background(C.chip).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconIn(Icons.Search, 16.dp, C.subtle)
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text("搜索会话", color = C.subtle, fontSize = 15.sp)
            BasicTextField(query, onChange, singleLine = true, textStyle = TextStyle(color = C.ink, fontSize = 15.sp), cursorBrush = SolidColor(C.accent), modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun Quiet(text: String) = Text(text, color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp))

@Composable
private fun Empty(view: ChatsView, onlyMine: Boolean) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val online = view.stations.any { it.state == "online" }
        Illustration(if (online) R.drawable.illus_new_chat else R.drawable.illus_station_offline, if (online) R.drawable.illus_new_chat_dark else R.drawable.illus_station_offline_dark, 240.dp)
        Text(if (onlyMine) "你还没有参与的会话" else "还没有会话", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Text(if (online) "点右下角的笔，让 agent 做点什么。" else "这个 workspace 的 station 都不在线。", fontSize = 14.sp, color = C.muted)
    }
}

/** Someone else's chat carries its starter's face before the title. */
@Composable
private fun Starter(c: ChatItem, me: Me) {
    val creator = c.session.creator
    if (creator != null && !me.isMe(creator)) Avatar(creator.id, creator.name, 16.dp, Modifier.padding(end = 6.dp))
}

@Composable
private fun NeedCard(c: ChatItem, me: Me) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val shape = RoundedCornerShape(22.dp)
    Column(
        Modifier.padding(horizontal = 12.dp).padding(top = 2.dp, bottom = 10.dp).fillMaxWidth()
            .shadow(8.dp, shape, ambientColor = C.accent.copy(alpha = 0.3f), spotColor = C.accent.copy(alpha = 0.25f))
            .clip(shape).background(Brush.verticalGradient(0f to lerp(C.surface, C.accentBg, 0.55f), 0.7f to C.surface))
            .clickable { app.push(Screen.Chat(c.station, c.session.key)) }.padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            ModelStack(c.models, ChatState.Block, around = C.surface)
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Starter(c, me)
                Text(sessionTitle(c.session), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Text(relativeTime(c.session.lastActiveAt), fontSize = 12.sp, color = C.muted, modifier = Modifier.align(Alignment.Top))
        }
        val question = c.last?.takeIf { it.declared == "block" }?.text
        Text(question ?: "agent 停下来等你决定", fontSize = 15.sp, lineHeight = 22.sp, color = if (question != null) C.ink else C.muted, maxLines = 4, overflow = TextOverflow.Ellipsis)
        QuickReplies(QUICK, onMore = { app.push(Screen.Chat(c.station, c.session.key)) }) { text ->
            scope.launch { answer(app, c.station, c.session.key, text) }
        }
    }
}

suspend fun answer(app: AppState, station: String, key: String, text: String, toast: Boolean = true) {
    try {
        app.api(station).send(key, text)
        if (toast) app.toast = "已回复：$text"
    } catch (e: CoreException) {
        app.toast = "没发出去：${e.message}"
    }
}

/** Answers in a row, the first one filled; "我来看看" opens the chat. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QuickReplies(answers: List<String>, onMore: (() -> Unit)?, onAnswer: (String) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        answers.forEachIndexed { i, q -> QuickButton(q, primary = i == 0) { onAnswer(q) } }
        if (onMore != null) QuickButton("我来看看", primary = false, onClick = onMore)
    }
}

@Composable
private fun QuickButton(text: String, primary: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).background(if (primary) C.ink else C.chip).clickable(onClick = onClick).padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) { Text(text, fontSize = 14.sp, color = if (primary) C.bg else C.ink) }
}

@Composable
private fun ChatRow(c: ChatItem, me: Me, first: Boolean, time: String? = null, line: (@Composable () -> Unit)? = null) {
    val app = LocalApp.current
    val state = c.session.state()
    if (!first) Box(Modifier.padding(start = 68.dp).fillMaxWidth().height(1.dp).background(C.line))
    Row(
        Modifier.fillMaxWidth().clickable { app.push(Screen.Chat(c.station, c.session.key)) }.padding(start = 20.dp, end = 16.dp, top = 12.dp, bottom = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        ModelStack(c.models, state)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Starter(c, me)
                Text(
                    sessionTitle(c.session), fontSize = 15.sp, fontWeight = if (c.unread > 0) FontWeight.SemiBold else FontWeight.Medium,
                    color = if (state == ChatState.Failed) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
            line?.invoke()
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (time != null) Text(time, fontSize = 12.sp, color = if (c.unread > 0) C.ink else C.subtle)
            // Unread is not "needs you": ink, not the ember orange.
            if (c.unread > 0) Text(
                "${c.unread}", fontSize = 11.sp, color = C.bg, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clip(CircleShape).background(C.ink).padding(horizontal = 6.dp),
            )
        }
    }
}

/** A running chat's one line: what its agent is doing now. */
@Composable
private fun RunningLine(c: ChatItem) {
    val app = LocalApp.current
    val live by rememberTopic<LiveView>(app.core, Topics.live(c.station, c.session.key))
    val now = live.value?.let { activityRows(emptyList(), it.steps, it.phase).lastOrNull()?.text }
    Text(now ?: "进行中", fontSize = 13.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

@Composable
private fun Toolbar(app: AppState, modifier: Modifier) {
    Row(
        modifier.fillMaxWidth().background(C.bg).hairlineTop(C.line).windowInsetsPadding(WindowInsets.navigationBars)
            .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Seg(listOf("全部", "我参与的"), if (app.onlyMine) 1 else 0, { app.showOnlyMine(it == 1) }, Modifier.weight(1f).widthIn(max = 220.dp), height = 36.dp, fill = true)
        Spacer(Modifier.weight(0.001f).widthIn(min = 12.dp))
        Box(
            Modifier.size(48.dp).shadow(10.dp, CircleShape).clip(CircleShape).background(C.ink).clickable { app.push(Screen.NewChat) },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Pen, 20.dp, C.bg) }
    }
}

private fun openWorkspaces(app: AppState) {
    app.sheet = SheetSpec(0.6f) { WorkspacesSheet(app) }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.WorkspacesSheet(app: AppState) {
    val all by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    val context = LocalContext.current
    SheetGrab()
    SheetHead("切换 workspace")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        all.value?.entries()?.forEach { e ->
            // Workspaces are their names; which account reaches one is said only here.
            PickRow(e.workspace.name, "${e.account.email} · ${e.workspace.stations} 台 station", checked = e.workspace.id == app.workspace) {
                app.pickWorkspace(e.workspace.id); app.sheet = null
            }
        }
        PickRow("＋ 新建 workspace", "在电脑上打开", color = C.accent) { openUrl(context, app.web("/")) }
    }
}
