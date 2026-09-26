// Home is the `chats` view as the web's sidebar lists it: one kind of item (an
// agent with its chat, or an agent with no chat yet), newest first and grouped
// by day. A fixed head (you → settings · workspace · stations) and one bottom
// toolbar (全部 / 我参与的 · new chat), like Mail.
package dev.ember.android.screens

import androidx.compose.foundation.background
import dev.ember.android.data.Topic
import kotlin.math.roundToInt
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
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
import dev.ember.android.data.badgeState
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
import dev.ember.android.ui.Badge
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
    // Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
    val all by rememberTopic<ChatsView>(app.core, Topics.chats(scope, false))
    val mine by rememberTopic<ChatsView>(app.core, Topics.chats(scope, true))
    val allList = rememberLazyListState()
    val mineList = rememberLazyListState()
    val shift by animateFloatAsState(if (app.onlyMine) 1f else 0f, tween(240, easing = FastOutSlowInEasing), label = "mine")
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Avatar(current.account.email, current.account.name.ifEmpty { current.account.email }, 34.dp, Modifier.clip(CircleShape).clickable { app.push(Screen.Me) }, picture = current.account.picture)
            Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { openWorkspaces(app) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(current.workspace.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (invitationsWaiting(app)) Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent).semantics { contentDescription = "有邀请" })
                IconIn(Icons.ChevronDown, 16.dp, C.muted)
            }
            NavButton(Icons.Server, { app.push(Screen.Stations) }, 20.dp)
        }
        Box(Modifier.weight(1f)) {
            BoxWithConstraints(Modifier.fillMaxSize().clipToBounds()) {
                val width = constraints.maxWidth
                ChatPane(all, false, allList, Modifier.width(maxWidth).offset { IntOffset((-shift * width).roundToInt(), 0) })
                ChatPane(mine, true, mineList, Modifier.width(maxWidth).offset { IntOffset(((1 - shift) * width).roundToInt(), 0) })
            }
            Toolbar(app, Modifier.align(Alignment.BottomCenter))
        }
    }
}

/** One of the two lists, all or the viewer's: its states (connecting, offline, empty) and its days. */
@Composable
private fun ChatPane(chats: Topic<ChatsView>, onlyMine: Boolean, list: LazyListState, modifier: Modifier) {
    val view = chats.value
    LazyColumn(modifier.fillMaxHeight(), state = list) {
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
            if (view.days.isEmpty() && !view.loading && failed.isEmpty() && connecting.isEmpty()) item(key = "empty") { Empty(view, onlyMine) }
            for (day in view.days) {
                item(key = "h/${day.daysAgo}") { SectionHeader(dayLabel(day.daysAgo, day.at)) }
                items(day.items, key = { "${it.station}/${it.id}" }) { ChatRow(it, view) }
            }
        }
        item(key = "pad") { Spacer(Modifier.height(96.dp)) }
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

/**
 * A row: its title (bold while something in it is unread, a blue dot in the
 * margin) and, for an agent that came from Slack, the connect's mark; under
 * it the last thing said, the agent's state on its picture when it said it. Two lines, always
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
                // The state rides on the agent's picture, when the agent said the last thing; nowhere else.
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) { item.last?.let { LastMessage(item) } }
                if (held) Text(relativeTime(item.lastActiveAt), fontSize = 12.sp, color = C.subtle, maxLines = 1)
            }
        }
    }
}

/** The last thing said, on one line: a small picture of who said it, then what, in the secondary colour. */
@Composable
private fun LastMessage(item: ChatItem) {
    // Who said it, and an agent's state on its picture, are the core's (present.rs).
    val last = item.last!!
    val by = last.by
    val name = by?.name ?: last.authorName ?: last.author
    val text = cleanText(last.text).ifEmpty { "（文件）" }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "$name：$text" }) {
        when (by?.kind) {
            "ember" -> Mark(13.dp)
            "agent" -> Box {
                MakerIcon(by.model, by.runtime, 13.dp)
                badgeState(by.state)?.let { state -> Box(Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp)) { Badge(state, 8.dp, 1.5.dp, C.bg) } }
            }
            else -> Avatar(last.author, name, 13.dp, picture = by?.picture)
        }
        // The line's own height, its glyphs centred in it: level with the picture and the state's dot.
        Text(
            text, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
            style = androidx.compose.ui.text.TextStyle(lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
                androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center, androidx.compose.ui.text.style.LineHeightStyle.Trim.Both,
            )),
        )
    }
}

@Composable
private fun Toolbar(app: AppState, modifier: Modifier) {
    Row(
        modifier.fillMaxWidth().background(C.bg).windowInsetsPadding(WindowInsets.navigationBars)
            .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Seg(listOf("全部", "我参与的"), if (app.onlyMine) 1 else 0, { app.showOnlyMine(it == 1) }, Modifier.width(200.dp), height = 36.dp, fill = true)
        // The switch keeps its own width (a weight would stretch it up to the button); the room left goes between them.
        Spacer(Modifier.weight(1f).widthIn(min = 16.dp))
        Box(
            // Ink on the paper in the light; in the dark a raised surface, not a white disc.
            Modifier.size(48.dp).shadow(10.dp, CircleShape).clip(CircleShape).background(if (C.dark) C.surface2 else C.ink).clickable { app.push(Screen.NewChat) },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Pen, 20.dp, if (C.dark) C.ink else C.bg) }
    }
}
