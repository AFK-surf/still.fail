// Home is the `chats` view as the web's sidebar lists it: one kind of item (an
// agent with its chat, or an agent with no chat yet), newest first and grouped
// by day. A fixed head (you → settings · workspace · stations) and one bottom
// toolbar (全部 / 我参与的 · new chat), like Mail.
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.R
import dev.ember.android.Screen
import dev.ember.android.data.ChatItem
import dev.ember.android.data.ChatState
import dev.ember.android.data.ChatsView
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.cleanText
import dev.ember.android.data.dayLabel
import dev.ember.android.data.isMe
import dev.ember.android.data.originLabel
import dev.ember.android.data.page
import dev.ember.android.data.relativeTime
import dev.ember.android.data.rememberTopic
import dev.ember.android.data.state
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.Illustration
import dev.ember.android.ui.MakerIcon
import dev.ember.android.ui.Mark
import dev.ember.android.ui.NavButton
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.Seg
import dev.ember.android.ui.SlackMark
import dev.ember.android.ui.avatarColor
import dev.ember.android.ui.initial

@Composable
fun HomeScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val scope = current.workspace.id
    val chats by rememberTopic<ChatsView>(app.core, Topics.chats(scope, app.onlyMine))
    val list = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(34.dp).clip(CircleShape).background(avatarColor(current.account.email)).clickable { app.push(Screen.Me) }, contentAlignment = Alignment.Center) {
                Text(initial(current.account.name.ifEmpty { current.account.email }), color = androidx.compose.ui.graphics.Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
            Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { openWorkspaces(app) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(current.workspace.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (invitationsWaiting(app)) Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent).semantics { contentDescription = "有邀请" })
                IconIn(Icons.ChevronDown, 16.dp, C.muted)
            }
            NavButton(Icons.Server, { app.push(Screen.Stations) }, 20.dp)
        }
        Box(Modifier.weight(1f)) {
            val view = chats.value
            LazyColumn(Modifier.fillMaxSize(), state = list) {
                if (view == null) {
                    item(key = "wait") { Note(chats.error?.message ?: "正在读取会话…", error = chats.error != null) }
                } else {
                    val stations = view.stations
                    val connecting = stations.filter { it.state == "connecting" }
                    val failed = stations.filter { it.state == "error" }
                    val offline = stations.filter { it.state == "offline" }
                    connecting.forEach { s -> item(key = "c/${s.station}") { Note("正在连接 ${s.name}…") } }
                    failed.forEach { s -> item(key = "e/${s.station}") { Note("连不上「${s.name}」，正在重试…", error = true) } }
                    if (view.days.isEmpty() && view.loading) item(key = "loading") { Note("正在读取会话…") }
                    if (offline.isNotEmpty()) item(key = "offline") { Note("${offline.joinToString("、") { it.name }} 离线，它们的会话暂时看不到。") }
                    if (view.days.isEmpty() && !view.loading && failed.isEmpty() && connecting.isEmpty()) item(key = "empty") { Empty(view, app.onlyMine) }
                    for (day in view.days) {
                        item(key = "h/${day.daysAgo}") { SectionHeader(dayLabel(day.daysAgo, day.at)) }
                        items(day.items, key = { "${it.station}/${it.id}" }) { ChatRow(it, view) }
                    }
                }
                item(key = "pad") { Spacer(Modifier.height(96.dp)) }
            }
            Toolbar(app, Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
private fun Note(text: String, error: Boolean = false) =
    Text(text, color = if (error) C.red else C.muted, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))

@Composable
private fun Empty(view: ChatsView, onlyMine: Boolean) {
    val app = LocalApp.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val any = view.stations.isNotEmpty()
        Illustration(if (any) R.drawable.illus_new_chat else R.drawable.illus_station_offline, if (any) R.drawable.illus_new_chat_dark else R.drawable.illus_station_offline_dark, 240.dp)
        when {
            onlyMine -> Text("没有你参与的会话。", fontSize = 14.sp, color = C.muted)
            any -> {
                Text("还没有会话。在 Slack 里 @ ${if (view.stations.size > 1) "它们" else "它"}，或者", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
                Text("新建对话", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { app.push(Screen.NewChat) })
            }
            else -> {
                Text("还没有 station。", fontSize = 14.sp, color = C.muted)
                Text("看看 Station", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { app.push(Screen.Stations) })
            }
        }
    }
}

/** An agent's state as a dot: solid orange block, a hollow ring at work, red failed; done has none. */
@Composable
fun StateDot(state: ChatState) {
    val shape = CircleShape
    val dot = Modifier.size(8.dp).clip(shape)
    when (state) {
        ChatState.Block -> Box(dot.background(C.accent))
        ChatState.Running -> Box(dot.border(2.dp, C.accent, shape))
        ChatState.Failed -> Box(dot.background(C.red))
        ChatState.Done -> {}
    }
}

/**
 * A row: its title (bold while something in it is unread, a blue dot in the
 * margin) and, for an agent that came from Slack, the connect's mark; under
 * it the last thing said, and the agents' state as a dot. Two lines, always
 * the same height. The time shows only while the row is held.
 */
@Composable
private fun ChatRow(item: ChatItem, view: ChatsView) {
    val app = LocalApp.current
    var held by remember { mutableStateOf(false) }
    Box(
        Modifier.fillMaxWidth().height(62.dp).background(if (held) C.ink.copy(alpha = 0.05f) else androidx.compose.ui.graphics.Color.Transparent)
            .pointerInput(item.station, item.id) {
                detectTapGestures(
                    onPress = { tryAwaitRelease(); held = false },
                    onLongPress = { held = true },
                    onTap = { app.push(Screen.Chat(item.station, item.page)) },
                )
            },
    ) {
        if (item.unread) Box(Modifier.padding(start = 8.dp, top = 19.dp).size(7.dp).clip(CircleShape).background(C.blue).semantics { contentDescription = "有未读消息" })
        Column(Modifier.fillMaxSize().padding(start = 22.dp, end = 16.dp), verticalArrangement = Arrangement.Center) {
            Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    item.title, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = if (item.unread) FontWeight.SemiBold else FontWeight.Normal,
                    color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                )
                // Only an agent that came from elsewhere (Slack, the only kind of connect) says so.
                Box(Modifier.width(14.dp), contentAlignment = Alignment.Center) {
                    if (item.connect != null) Box(Modifier.semantics { contentDescription = item.originLabel() }) { SlackMark(13.dp) }
                }
            }
            Row(Modifier.height(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f)) { item.last?.let { LastMessage(item, view) } }
                if (held) Text(relativeTime(item.lastActiveAt), fontSize = 12.sp, color = C.subtle, maxLines = 1)
                Box(Modifier.width(14.dp), contentAlignment = Alignment.Center) { StateDot(item.state()) }
            }
        }
    }
}

/** The last thing said, on one line: a small picture of who said it, then what, in the secondary colour. */
@Composable
private fun LastMessage(item: ChatItem, view: ChatsView) {
    val last = item.last!!
    val agent = if (last.authorKind == "agent") item.agents.firstOrNull { it.key == last.author } else null
    val mine = last.authorKind == "person" && view.me.isMe(last.author)
    val name = when {
        last.authorKind == "ember" -> "ember"
        last.authorKind == "agent" -> agent?.model ?: last.authorName ?: "agent"
        mine -> "你"
        else -> last.authorName ?: last.author
    }
    val text = cleanText(last.text).ifEmpty { "（文件）" }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "$name：$text" }) {
        when (last.authorKind) {
            "ember" -> Mark(13.dp)
            "agent" -> MakerIcon(agent?.model, agent?.runtime ?: "claude", 13.dp)
            else -> Avatar(last.author, name, 13.dp)
        }
        Text(text, fontSize = 14.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Toolbar(app: AppState, modifier: Modifier) {
    Row(
        modifier.fillMaxWidth().background(C.bg).windowInsetsPadding(WindowInsets.navigationBars)
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
