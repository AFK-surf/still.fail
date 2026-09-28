// Home is the `chats` view as the web's sidebar lists it: one kind of item (an
// agent with its chat, or an agent with no chat yet), newest first and grouped
// by day. A fixed head (you → settings · workspace · stations) and one bottom
// toolbar (全部 / 我参与的 · new chat), like Mail.
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import dev.ember.android.ui.floating
import dev.ember.android.ui.glass
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.HazeState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.draw.alpha
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
import dev.ember.android.data.page
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
    // The lists run under both bars, which are frosted glass over them.
    val haze = remember { HazeState() }
    val density = LocalDensity.current
    var topBar by remember { mutableIntStateOf(0) }
    var bottomBar by remember { mutableIntStateOf(0) }
    val padding = with(density) { PaddingValues(top = topBar.toDp() + 8.dp, bottom = bottomBar.toDp() + 8.dp) }
    Box(Modifier.fillMaxSize()) {
        BoxWithConstraints(Modifier.fillMaxSize().clipToBounds().hazeSource(haze)) {
            val width = constraints.maxWidth
            ChatPane(current, all, false, allList, padding, Modifier.width(maxWidth).offset { IntOffset((-shift * width).roundToInt(), 0) })
            ChatPane(current, mine, true, mineList, padding, Modifier.width(maxWidth).offset { IntOffset(((1 - shift) * width).roundToInt(), 0) })
        }
        Row(
            Modifier.align(Alignment.TopCenter).fillMaxWidth().onSizeChanged { topBar = it.height }.glass(haze)
                .windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Avatar(current.account.email, current.account.name.ifEmpty { current.account.email }, 34.dp, Modifier.clip(CircleShape).clickable { app.push(Screen.Me) }, picture = current.account.picture)
            Row(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { openWorkspaces(app) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(current.workspace.name, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (invitationsWaiting(app)) Box(Modifier.size(7.dp).clip(CircleShape).background(C.accent).semantics { contentDescription = "有邀请" })
                IconIn(Icons.ChevronDown, 16.dp, C.muted)
            }
            // A station not working marks it: grey offline, orange coming back, red failing (the core's `trouble`); its page says which.
            Box {
                NavButton(Icons.Server, { app.push(Screen.Stations) }, 20.dp)
                all.value?.trouble?.let { t ->
                    val dot = when (t.state) { "reconnecting" -> C.accent; "error" -> C.red; else -> C.subtle }
                    Box(Modifier.align(Alignment.TopEnd).offset((-3).dp, 3.dp).size(13.dp).clip(CircleShape).background(C.bg).padding(2.dp).clip(CircleShape).background(dot).semantics { contentDescription = t.text })
                }
            }
        }
        Toolbar(app, haze, Modifier.align(Alignment.BottomCenter).onSizeChanged { bottomBar = it.height })
    }
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days; an offline station's chats say so row by row. */
@Composable
private fun ChatPane(current: WorkspaceEntry, chats: Topic<ChatsView>, onlyMine: Boolean, list: LazyListState, padding: PaddingValues, modifier: Modifier) {
    val view = chats.value
    LazyColumn(modifier.fillMaxHeight(), state = list, contentPadding = padding) {
        if (view == null) {
            item(key = "wait") { Note(chats.error?.message ?: "正在读取会话…", error = chats.error != null) }
        } else {
            val stations = view.stations
            val connecting = stations.filter { it.state == "connecting" }
            val failed = stations.filter { it.state == "error" }
            // A station's link coming back is said on its rows; only with no rows to show does the list say it.
            if (view.days.isEmpty() && (view.loading || connecting.isNotEmpty())) item(key = "loading") { Note("正在读取会话…") }
            if (view.days.isEmpty() && !view.loading) failed.forEach { s -> item(key = "e/${s.station}") { Note("连不上「${s.name}」，正在重试…", error = true) } }
            if (view.days.isEmpty() && !view.loading && failed.isEmpty() && connecting.isEmpty()) item(key = "empty") { Empty(current, view, onlyMine) }
            for (day in view.days) {
                item(key = "h/${day.daysAgo}") { SectionHeader(day.label) }
                items(day.items, key = { "${it.station}/${it.id}" }) { ChatRow(it, view) }
            }
        }
    }
}

@Composable
private fun Note(text: String, error: Boolean = false) =
    Text(text, color = if (error) C.red else C.muted, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))

@Composable
private fun Empty(current: WorkspaceEntry, view: ChatsView, onlyMine: Boolean) {
    val app = LocalApp.current
    // No station yet: nothing else works, so adding the first one is the page.
    if (view.stations.isEmpty() && !onlyMine) return FirstStation(current)
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 240.dp)
        if (onlyMine) Text("没有你参与的会话。", fontSize = 14.sp, color = C.muted)
        else {
            Text("还没有会话。在 Slack 里 @ ${if (view.stations.size > 1) "它们" else "它"}，或者", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            Text("新建对话", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { app.push(Screen.NewChat) })
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
        Modifier.fillMaxWidth().height(66.dp).background(if (held) C.ink.copy(alpha = 0.05f) else androidx.compose.ui.graphics.Color.Transparent)
            .pointerInput(item.station, item.id) {
                detectTapGestures(
                    onPress = { tryAwaitRelease(); held = false },
                    onLongPress = { held = true },
                    onTap = { app.push(Screen.Chat(item.station, item.page)) },
                )
            },
    ) {
        if (item.unread) Box(Modifier.padding(start = 8.dp, top = 19.dp).size(7.dp).clip(CircleShape).background(C.blue).semantics { contentDescription = "有未读消息" })
        // Its station offline: greyed, and marked where a Slack chat's mark goes (the core says so, row by row).
        val offline = item.offline
        val dim = if (offline != null) 0.45f else 1f
        Row(Modifier.fillMaxSize().padding(start = 22.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AgentsPicture(item, Modifier.alpha(dim))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    item.title, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = if (item.unread) FontWeight.SemiBold else FontWeight.Normal,
                    color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alpha(dim),
                )
                // Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too.
                Box(Modifier.width(14.dp), contentAlignment = Alignment.Center) {
                    val reconnecting = item.reconnecting
                    if (offline != null) Box(Modifier.semantics { contentDescription = offline }) { IconIn(Icons.Unplug, 13.dp, C.subtle) }
                    else if (reconnecting != null) Box(Modifier.semantics { contentDescription = reconnecting }) { Spinner(11.dp) }
                    else if (item.connect != null) Box(Modifier.semantics { contentDescription = item.originText ?: "Slack" }) { SlackMark(13.dp) }
                }
            }
            Row(Modifier.height(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // The state rides on the agent's picture, when the agent said the last thing; nowhere else.
                Box(Modifier.weight(1f).alpha(dim), contentAlignment = Alignment.CenterStart) { item.last?.let { LastMessage(item) } }
                if (held) Text(item.time?.get("lastActiveAt")?.ago ?: "", fontSize = 12.sp, color = C.subtle, maxLines = 1)
            }
        }
        }
    }
}

/**
 * Who is in a chat, as its row's picture: its agent's mark, or two of its agents' overlapping, with its state (the
 * core's) at the corner. A chat with no agent yet shows ember's.
 */
@Composable
private fun AgentsPicture(item: ChatItem, modifier: Modifier) {
    val agents = item.agents.take(2)
    Box(modifier.size(40.dp)) {
        when {
            agents.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Mark(26.dp) }
            agents.size == 1 -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { MakerIcon(agents[0].maker, agents[0].runtime, 28.dp) }
            else -> agents.forEachIndexed { i, a ->
                Box(Modifier.align(if (i == 0) Alignment.TopStart else Alignment.BottomEnd).size(21.dp), contentAlignment = Alignment.Center) { MakerIcon(a.maker, a.runtime, 18.dp) }
            }
        }
        badgeState(item.state)?.let { state -> Box(Modifier.align(Alignment.BottomEnd).offset(2.dp, 2.dp)) { Badge(state, 10.dp, 2.dp, C.bg) } }
    }
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
@Composable
private fun LastMessage(item: ChatItem) {
    Text(
        item.last!!.preview, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
        style = androidx.compose.ui.text.TextStyle(lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(
            androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center, androidx.compose.ui.text.style.LineHeightStyle.Trim.Both,
        )),
    )
}

@Composable
private fun Toolbar(app: AppState, haze: HazeState, modifier: Modifier) {
    // One capsule floating over the list, round at both ends like what is in it: the switch fills it, the capsule being its track, and the new-chat button
    // closes it at the right, a disc in the accent (no line between them: shape and colour tell them apart).
    Row(
        modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars)
            .padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 10.dp)
            .floating(haze, RoundedCornerShape(percent = 50)).padding(6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Seg(
            listOf("全部", "我参与的"), if (app.onlyMine) 1 else 0, { app.showOnlyMine(it == 1) },
            Modifier.weight(1f), height = 44.dp, fill = true, radius = 22.dp, inset = 0.dp, track = false,
        )
        Box(
            Modifier.size(44.dp).clip(CircleShape).background(C.accent).clickable { app.push(Screen.NewChat) },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Edit, 20.dp, Color.White) }
    }
}
