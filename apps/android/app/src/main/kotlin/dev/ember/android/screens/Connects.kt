// Connects (as the narrow web's web/src/mobile/Connects.tsx, from the desktop's Connects.tsx and Connect.tsx): the
// list, all or the viewer's; a connect's page (how it runs, how its conversations become sessions, its Slack link, what
// is done to it less often under "…"); how it runs, picked on a page of its own; a new one, a step a screen.
package dev.ember.android.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.Screen
import dev.ember.android.data.Connect
import dev.ember.android.data.ConnectItem
import dev.ember.android.data.ConnectsView
import dev.ember.android.data.MODE_LABEL
import dev.ember.android.data.MODE_TEXT
import dev.ember.android.data.MadeApp
import dev.ember.android.data.ModelOption
import dev.ember.android.data.Overview
import dev.ember.android.data.RUNTIME_LABEL
import dev.ember.android.data.SlackIdentity
import dev.ember.android.data.StationView
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.WorkspaceView
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.LargeTitle
import dev.ember.android.ui.ListCard
import dev.ember.android.ui.ListRow
import dev.ember.android.ui.Loading
import dev.ember.android.ui.MakerIcon
import dev.ember.android.ui.NavBar
import dev.ember.android.ui.NavButton
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.Seg
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.android.ui.SlackMark
import dev.ember.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** A connect's presence as a dot: online green, at work orange, failing red, offline hollow. */
@Composable
fun PresenceDot(state: String) {
    val m = Modifier.size(7.dp).clip(CircleShape)
    Box(when (state) {
        "online" -> m.background(C.green)
        "busy" -> m.background(C.accent)
        "error" -> m.background(C.red)
        else -> m.border(1.5.dp, C.subtle, CircleShape)
    })
}

/** A connect in its station's list: its mark and name, how it runs, and its presence. */
@Composable
fun ConnectRow(station: String, c: Connect) {
    val app = LocalApp.current
    ListRow(onClick = { app.push(Screen.Connect(station, c.id)) }) {
        SlackMark(16.dp)
        Column(Modifier.weight(1f)) {
            Text(c.name + (c.team?.let { " · $it" } ?: ""), fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(listOfNotNull(c.modeText, c.runtimeText, c.bind.model).joinToString(" · "), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) { PresenceDot(c.presence); Text(c.statusText, fontSize = 12.sp, color = C.muted) }
    }
}

/** A connect by its station and id, as the workspace's connects view has it. */
@Composable
private fun rememberConnect(station: String, id: String): Pair<ConnectItem?, String?> {
    val app = LocalApp.current
    val connects by rememberTopic<ConnectsView>(app.core, Topics.connects(station.substringBefore('/'), false))
    val item = connects.value?.items?.firstOrNull { it.station == station && it.connect.id == id }
    val note = if (item != null) null else connects.error?.message ?: if (connects.value == null || connects.value!!.loading) "正在读取连接…" else "没有这个连接。"
    return item to note
}

@Composable
fun ConnectScreen(station: String, id: String) {
    val app = LocalApp.current
    val (item, note) = rememberConnect(station, id)
    if (item == null) return Column(Modifier.fillMaxSize()) { NavBar("连接", app::pop, "连接"); Loading(note ?: "") }
    val connect = item.connect
    val c = connect.connection
    Column(Modifier.fillMaxSize()) {
        NavBar("连接", app::pop, connect.name, sub = { PresenceDot(connect.presence); Text(connect.statusText, fontSize = 11.sp, color = C.muted) },
            trailing = { NavButton(Icons.More, { openConnectMenu(app, station, connect) }) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            if (c.state == "no_tokens" || c.state == "error" || (c.state == "reconnecting" && c.lastError != null)) Callout {
                if (c.state == "no_tokens") Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("这个连接还没接上 Slack。", fontSize = 13.sp, color = C.ink)
                    Text("填 token", fontSize = 13.sp, color = C.accent, modifier = Modifier.clickable { openTokens(app, station, connect) })
                } else Text(if (c.state == "error") c.error ?: "" else "正在重连：${c.lastError}", fontSize = 13.sp, color = C.ink)
            }
            SectionHeader("怎么跑", start = 24.dp)
            ListCard {
                ListRow(onClick = { app.push(Screen.ConnectRun(station, connect.id)) }) {
                    Text("模型", fontSize = 13.sp, color = C.muted, modifier = Modifier.width(32.dp))
                    Text(
                        "${connect.bind.model ?: "选模型"} · ${connect.bind.effort?.ifEmpty { null } ?: "默认深度"} · ${if (connect.bind.profile != null) "固定账号" else "自动分配"}",
                        fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                ListRow(onClick = { app.sheet = SheetSpec(0.8f, draggable = true) { ModeSheet(station, item) } }) {
                    Text("会话", fontSize = 13.sp, color = C.muted, modifier = Modifier.width(32.dp))
                    Column(Modifier.weight(1f)) {
                        Text(MODE_LABEL[connect.mode] ?: connect.mode, fontSize = 15.sp, color = C.ink)
                        Text((MODE_TEXT[connect.mode] ?: "") + if (connect.mode == "single-session") (if (connect.requireMention) "只在被 @ 时唤醒。" else "它能看到的每条消息都会送进会话。") else "", fontSize = 13.sp, color = C.muted)
                    }
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                if (connect.mode == "single-session") ListRow(onClick = { app.sheet = SheetSpec(0.7f, draggable = true) { SessionSheet(station, item) } }) {
                    Text("当前", fontSize = 13.sp, color = C.muted, modifier = Modifier.width(32.dp))
                    Text(item.bound?.titleText ?: "还没有会话；下一条消息会开始一个新的。", fontSize = 15.sp, color = if (item.bound != null) C.ink else C.muted, modifier = Modifier.weight(1f))
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
            }
            Text("跑在 ${connect.runtimeText} 上，创建后不能换；要用另一种运行时，新建一个连接。进行中的会话继续用开始时的设置。", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp))
            SectionHeader("最近的会话", start = 24.dp)
            ListCard {
                if (item.sessions.isEmpty()) ListRow { Text("还没有会话。在 Slack 里 @${connect.name} 就会开始。", fontSize = 15.sp, color = C.muted) }
                item.sessions.forEach { s ->
                    ListRow(onClick = { app.push(Screen.Chat(station, dev.ember.android.data.ChatOf.Session(s.key))) }) {
                        Text(s.titleText, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Text(s.statusText, fontSize = 13.sp, color = C.muted)
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

@Composable
private fun Callout(content: @Composable () -> Unit) {
    Box(Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(horizontal = 12.dp, vertical = 10.dp)) { content() }
}

/** What is done to a connect less often: reconnecting, its tokens, Slack, turning it off or on, its owner, deleting it. */
private fun openConnectMenu(app: AppState, station: String, connect: Connect) {
    val api = app.api(station)
    app.sheet = SheetSpec(0.6f) {
        val scope = rememberCoroutineScope()
        val context = LocalContext.current
        val act = { done: String, call: suspend () -> Unit ->
            scope.launch { try { call(); app.toast = done; app.sheet = null } catch (e: CoreException) { app.toast = e.message } }; Unit
        }
        SheetGrab()
        SheetHead(connect.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("重新连接") { act("已重新连接") { api.reconnect(connect.id) } }
            PickRow("更换 token") { openTokens(app, station, connect) }
            connect.connection.workspace?.url?.let { url -> PickRow("打开 Slack") { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
            if (connect.enabled) PickRow("停用", "Slack 连接会断开") { act("已停用，Slack 连接已断开") { api.putConnect(connect.id, buildJsonObject { put("enabled", false) }) } }
            else PickRow("启用") { act("已启用") { api.putConnect(connect.id, buildJsonObject { put("enabled", true) }) } }
            PickRow("更改所属用户", connect.createdBy?.shown?.display ?: connect.createdBy?.name) { app.sheet = SheetSpec(0.6f) { OwnerSheet(station, connect) } }
            PickRow("删除连接", color = C.red) {
                confirm(app, "删除「${connect.name}」？",
                    "Slack 连接会断开" + (if (connect.sessions > 0) "；它的 ${connect.sessions} 个会话的记录会保留，但不再接收消息" else "") + "。Slack 里的 app 需要你自己去删除。",
                    "删除连接", danger = true) { api.deleteConnect(connect.id); app.toast = "已删除连接"; app.pop() }
            }
        }
    }
}

/** Hands a connect to another person of the workspace. */
@Composable
private fun ColumnScope.OwnerSheet(station: String, connect: Connect) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(station.substringBefore('/')))
    SheetGrab()
    SheetHead("更改所属用户")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Text("连接属于谁，决定它出现在谁的「我添加的」里。", fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        ws.value?.members.orEmpty().forEach { m ->
            PickRow(m.name.ifEmpty { m.email }, m.email, checked = m.email.equals(connect.createdBy?.id, ignoreCase = true)) {
                scope.launch {
                    try {
                        app.api(station).putConnect(connect.id, buildJsonObject { putJsonObject("owner") { put("id", m.email); put("name", m.name.ifEmpty { m.email }) } })
                        app.toast = "已更改所属用户"; app.sheet = null
                    } catch (e: CoreException) { app.toast = e.message }
                }
            }
        }
    }
}

/** What switching a connect to `next` does to its conversations, in plain words (web/src/pages/Connect.tsx → consequences). */
private fun consequences(connect: Connect, mode: String, requireMention: Boolean, running: Long): List<String> {
    val out = mutableListOf<String>()
    if (connect.mode == "multi-session" && mode == "single-session") {
        out += "之后它收到的消息都进同一个会话；已有的每个 thread 的会话不再收到新消息，包括这些 thread 里的回复。记录会保留。"
        out += if (connect.session != null) "会接着使用之前绑定的单会话。" else "下一条消息会开始一个新的单会话；也可以在切换后选一个已有会话。"
        if (!requireMention) out += "不需要 @：它能看到的所有频道和私信里的每条消息都会送给 agent，消耗会明显增加。"
    } else if (connect.mode == "single-session" && mode == "multi-session") {
        out += "当前绑定的会话不再收到新消息。之后每个 thread 被 @ 时各开一个新会话。"
        out += "在单会话里进行过的 thread，要继续就需要重新 @，会开一个新会话，不带之前的上下文。"
        out += "以后切回单会话，会接着用原来的那个会话。"
    } else if (requireMention != connect.requireMention) {
        out += if (requireMention) "之后只有被 @ 的 thread 会进会话；已经进来的 thread 里的回复仍然会送到。" else "不需要 @：它能看到的所有频道和私信里的每条消息都会送给 agent，消耗会明显增加。"
    }
    if (running > 0) out += "现在有 $running 个会话正在运行，它们会跑完当前这一轮。"
    return out
}

/** The mode picker: each way with what it means, and in single-session whether it waits for an @. */
@Composable
private fun ModeChoices(mode: String, requireMention: Boolean, onChange: (String, Boolean) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("multi-session", "single-session").forEach { m ->
            val on = mode == m
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.surface).border(if (on) 2.dp else 1.dp, if (on) C.accent else C.line, RoundedCornerShape(14.dp))
                    .clickable { onChange(m, if (m == "multi-session") true else requireMention) }.padding(horizontal = 14.dp, vertical = 12.dp),
            ) {
                Text(MODE_LABEL[m] ?: m, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(MODE_TEXT[m] ?: "", fontSize = 13.sp, color = C.muted)
            }
        }
        if (mode == "single-session") Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.chip).clickable { onChange(mode, !requireMention) }.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text("只在被 @ 时唤醒", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(if (requireMention) "被 @ 的 thread 之后的回复不用再 @。" else "频道里它能看到的每条消息都会送进会话。", fontSize = 13.sp, color = C.muted)
            }
            Switch(requireMention)
        }
    }
}

@Composable
private fun Switch(on: Boolean) {
    Box(Modifier.size(44.dp, 26.dp).clip(RoundedCornerShape(13.dp)).background(if (on) C.green else C.line), contentAlignment = Alignment.CenterStart) {
        Box(Modifier.offset(x = if (on) 21.dp else 3.dp).size(20.dp).clip(CircleShape).background(androidx.compose.ui.graphics.Color.White))
    }
}

/** How its conversations become sessions: picked, with what changing it does said before it is done. */
@Composable
private fun ColumnScope.ModeSheet(station: String, item: ConnectItem) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val connect = item.connect
    var mode by remember { mutableStateOf(connect.mode) }
    var mention by remember { mutableStateOf(connect.requireMention) }
    var busy by remember { mutableStateOf(false) }
    val changed = mode != connect.mode || (mode == "single-session" && mention != connect.requireMention)
    val effects = if (changed) consequences(connect, mode, mention, item.running) else emptyList()
    SheetGrab()
    SheetHead("会话方式")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ModeChoices(mode, mention) { m, r -> mode = m; mention = r }
        if (effects.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("更改之后", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            effects.forEach { Text("· $it", fontSize = 13.sp, color = C.ink) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("取消", primary = false) { app.sheet = null }
            Button(if (mode == connect.mode) "确认更改" else "改为${if (mode == "single-session") "单会话" else "多会话"}", primary = true, busy = busy, enabled = changed) {
                busy = true
                scope.launch {
                    try { app.api(station).putConnect(connect.id, buildJsonObject { put("mode", mode); put("requireMention", mention) }); app.toast = "已更改会话方式"; app.sheet = null }
                    catch (e: CoreException) { app.toast = e.message } finally { busy = false }
                }
            }
        }
    }
}

/** A single-session connect's session: the one its messages go into, switched, or a new one. */
@Composable
private fun ColumnScope.SessionSheet(station: String, item: ConnectItem) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val connect = item.connect
    var choice by remember { mutableStateOf(connect.session ?: "new") }
    var title by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    SheetGrab()
    SheetHead("选择会话")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("之后「${connect.name}」收到的消息都进选中的会话。原来的会话保留，但不再收到这个连接的新消息。", fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp))
        PickRow("新建会话", "从空白上下文开始", checked = choice == "new") { choice = "new" }
        if (choice == "new") Box(Modifier.padding(horizontal = 20.dp)) { Field(title, { title = it }, "给它起个名字（可选），例如：值班") }
        item.candidates.forEach { s -> PickRow(s.titleText, s.agentText, checked = choice == s.key) { choice = s.key } }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("取消", primary = false) { app.sheet = null }
            Button(if (choice == "new") "新建并使用" else "使用这个会话", primary = true, busy = busy, enabled = choice != connect.session) {
                busy = true
                scope.launch {
                    try { app.api(station).bindSession(connect.id, if (choice == "new") null else choice, title); app.toast = if (choice == "new") "已新建会话" else "已换成这个会话"; app.sheet = null }
                    catch (e: CoreException) { app.toast = e.message } finally { busy = false }
                }
            }
        }
    }
}

// ── tokens ─────────────────────────────────────────────────────────────

/** The two tokens and who they were verified as (null until verified, and after any edit). */
private class Tokens {
    var app by mutableStateOf("")
    var bot by mutableStateOf("")
    var verified by mutableStateOf<SlackIdentity?>(null)
}

/** Replaces a connect's Slack tokens (either one; the other kept), verified before they are saved. */
private fun openTokens(app: AppState, station: String, connect: Connect) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val scope = rememberCoroutineScope()
        val tokens = remember { Tokens() }
        var busy by remember { mutableStateOf(false) }
        SheetGrab()
        SheetHead("Slack token")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("只换其中一个也可以，另一个留空会沿用已保存的。保存前先验证。", fontSize = 12.sp, color = C.muted)
            TokenFields(station, tokens, connect = connect.id, masked = connect.slack.appToken to connect.slack.botToken)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button("保存并连接", primary = true, busy = busy, enabled = tokens.verified != null) {
                    busy = true
                    scope.launch {
                        try { app.api(station).putConnect(connect.id, buildJsonObject { putJsonObject("slack") { put("appToken", tokens.app); put("botToken", tokens.bot) } }); app.toast = "已保存 token，正在连接"; app.sheet = null }
                        catch (e: CoreException) { app.toast = e.message } finally { busy = false }
                    }
                }
            }
        }
    }
}

/** A token's line: shown as dots, pasted into. */
@Composable
internal fun SecretField(value: String, onChange: (String) -> Unit, placeholder: String) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
        if (value.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
        BasicTextField(value, { onChange(it.trim()) }, singleLine = true, cursorBrush = SolidColor(C.accent), visualTransformation = PasswordVisualTransformation(),
            textStyle = TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = FontFamily.Monospace), modifier = Modifier.fillMaxWidth())
    }
}

/**
 * The two tokens with a verify step. For an existing connect a blank field keeps the stored token. An app installed
 * through Slack's OAuth (`install`) has its bot token on the station already: only the app-level token is asked for.
 */
@Composable
private fun TokenFields(station: String, tokens: Tokens, connect: String? = null, masked: Pair<String, String>? = null, install: String? = null) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var errors by remember { mutableStateOf<List<String>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("App-Level Token", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        SecretField(tokens.app, { tokens.app = it; tokens.verified = null; errors = emptyList() }, masked?.first?.ifEmpty { null }?.let { "已保存 $it，留空不变" } ?: "xapp-…")
        if (install == null) {
            Text("Bot Token", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            SecretField(tokens.bot, { tokens.bot = it; tokens.verified = null; errors = emptyList() }, masked?.second?.ifEmpty { null }?.let { "已保存 $it，留空不变" } ?: "xoxb-…")
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button("验证 token", primary = false, busy = busy, enabled = tokens.app.isNotEmpty() || tokens.bot.isNotEmpty() || connect != null) {
                busy = true
                scope.launch {
                    try {
                        val (identity, found) = app.api(station).verifySlack(connect, install, tokens.app, tokens.bot)
                        errors = found; tokens.verified = if (found.isEmpty()) identity else null
                    } catch (e: CoreException) { errors = listOf(e.message) } finally { busy = false }
                }
            }
            tokens.verified?.let { Text("连接到「${it.team}」，bot 是 @${it.botName}", fontSize = 12.sp, color = C.green, modifier = Modifier.weight(1f)) }
        }
        errors.forEach { Text(it, fontSize = 13.sp, color = C.red) }
    }
}

// ── how it runs ────────────────────────────────────────────────────────

/** The model a connect runs, how hard it thinks and who runs it: picked like an agent's (History.kt), saved for new sessions. */
@Composable
fun ConnectRunScreen(station: String, id: String) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val (item, note) = rememberConnect(station, id)
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(station.substringBefore('/')))
    var list by remember { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler(enabled = list != null) { list = null }
    Column(Modifier.fillMaxSize()) {
        NavBar(if (list != null) "换模型" else "返回", { if (list != null) list = null else app.pop() }, when (list) { "model" -> "选模型"; "account" -> "选账号"; else -> "换模型" })
        if (item == null) return Loading(note ?: "")
        val connect = item.connect
        val runtime = connect.bind.runtime
        val models = stations.value?.firstOrNull { it.station == station }?.models.orEmpty().filter { runtime in it.runtimes }
        var model by remember { mutableStateOf(connect.bind.model) }
        var effort by remember { mutableStateOf(connect.bind.effort ?: "") }
        var profile by remember { mutableStateOf(connect.bind.profile) }
        var busy by remember { mutableStateOf(false) }
        val choice = models.firstOrNull { it.model == model }
        val accounts = choice?.accounts?.get(runtime).orEmpty()
        val efforts = choice?.efforts?.get(runtime).orEmpty()
        val changed = model != connect.bind.model || effort != (connect.bind.effort ?: "") || profile != connect.bind.profile
        if (list == "model") return ModelList(models, runtime, model) { model = it; profile = null; list = null }
        if (list == "account") return AccountList(accounts, runtime, profile) { profile = it; list = null }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
            if (models.isEmpty()) Text("${connect.runtimeText} 的 Profile 还没有启用模型，先在 Station 页的 Profile 里勾选。", fontSize = 13.sp, color = C.warn, modifier = Modifier.padding(top = 8.dp))
            GroupLabel("模型")
            SettingRow(onClick = { list = "model" }, leading = { MakerIcon(choice?.maker, runtime, 18.dp) }) { Text(model ?: "选一个模型", fontSize = 15.sp, color = C.ink) }
            GroupLabel("思考深度")
            EffortChips(listOf<String?>(null) + efforts, effort.ifEmpty { null }) { effort = it ?: "" }
            GroupLabel("账号")
            SettingRow(onClick = { list = "account" }) {
                Text(profile?.let { p -> accounts.firstOrNull { it.id == p }?.name ?: p } ?: "自动分配", fontSize = 15.sp, color = C.ink)
                Text(if (profile == null) "额度用完或登录失效时换一个" else "固定用它", fontSize = 12.sp, color = C.muted)
            }
            Text("新开的会话会用新的设置；进行中的会话继续用开始时的。", fontSize = 12.sp, color = C.subtle, modifier = Modifier.padding(vertical = 12.dp))
        }
        Box(
            Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp, vertical = 12.dp).fillMaxWidth().heightIn(min = 52.dp)
                .clip(RoundedCornerShape(16.dp)).background(if (changed) C.ink else C.chip)
                .clickable(enabled = !busy && !(changed && model == null)) {
                    if (!changed) { app.pop(); return@clickable }
                    busy = true
                    scope.launch {
                        try {
                            app.api(station).putConnect(connect.id, buildJsonObject { putJsonObject("bind") { put("model", model ?: ""); put("effort", effort); put("profile", profile) } })
                            app.toast = "已保存，新会话会用新的设置"; app.pop()
                        } catch (e: CoreException) { app.toast = e.message } finally { busy = false }
                    }
                }.padding(horizontal = 16.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center,
        ) { Text(if (changed) "改成 ${model ?: "默认模型"} · ${effort.ifEmpty { "默认深度" }}" else "不变", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (changed) C.bg else C.ink) }
    }
}

// ── a new connect ──────────────────────────────────────────────────────

/**
 * A new Slack connect, a step a screen: the Slack workspace to make its app in (a configuration token each, or a new
 * one); the app's name and description; making and installing it, then the app-level token; last, the model it runs and
 * how its conversations become sessions. Without a configuration token the app is made in Slack by hand and both
 * tokens are pasted.
 */
@Composable
fun NewConnectScreen(station: String) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    val overview by rememberTopic<Overview>(app.core, Topics.overview(station))
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(station.substringBefore('/')))
    val teams = overview.value?.slackTeams.orEmpty()
    val models = stations.value?.firstOrNull { it.station == station }?.models.orEmpty()
    var step by remember { mutableStateOf("team") }
    var team by remember { mutableStateOf<String?>(null) }
    var name by remember { mutableStateOf("ember") }
    var description by remember { mutableStateOf("Coding agent in your threads (ember)") }
    var made by remember { mutableStateOf<MadeApp?>(null) }
    val tokens = remember { Tokens() }
    var config by remember { mutableStateOf("") }
    var model by remember { mutableStateOf<ModelOption?>(null) }
    var runtime by remember { mutableStateOf<String?>(null) }
    var mode by remember { mutableStateOf("multi-session") }
    var mention by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val chosen = teams.firstOrNull { it.teamId == team } ?: teams.singleOrNull()
    val entry = model ?: models.firstOrNull()
    val rt = entry?.runtimes?.firstOrNull { it == runtime } ?: entry?.runtimes?.firstOrNull() ?: "claude"
    val order = if (step == "manual" || (step == "bind" && made == null)) listOf("manual", "bind") else listOf("team", "app", "install", "bind")
    val titles = mapOf("team" to "选 Slack 工作区", "token" to "加配置 token", "app" to "配置 app", "install" to "安装", "manual" to "连接 Slack", "bind" to "绑定模型")
    val run = { work: suspend () -> Unit -> busy = true; error = null; scope.launch { try { work() } catch (e: CoreException) { error = e.message } finally { busy = false } }; Unit }
    val back = { when (step) { "team" -> app.pop(); "token", "app", "manual" -> step = "team"; "install" -> step = "app"; else -> step = if (made != null) "install" else "manual" } }
    androidx.activity.compose.BackHandler(enabled = step != "team") { back() }
    val open = { url: String -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    Column(Modifier.fillMaxSize()) {
        NavBar(if (step == "team") "取消" else "上一步", back, "添加连接", sub = { Text("${titles[step]} · ${(order.indexOf(step) + 1).coerceAtLeast(1)} / ${order.size}", fontSize = 11.sp, color = C.muted) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (step) {
                "team" -> if (teams.isEmpty()) {
                    Text("有了 Slack 的配置 token，ember 替你在 Slack 建好 app：名字、权限都在这里填，不用去 Slack 后台一项项配。它只归你用。", fontSize = 14.sp, color = C.muted)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button("添加配置 token", primary = true) { step = "token" } }
                    Text("不用配置 token，自己在 Slack 建 app", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { step = "manual" })
                } else {
                    Text("用哪个 Slack 工作区的配置 token 建 app。", fontSize = 14.sp, color = C.muted)
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                        teams.forEach { t -> PickRow(t.name, t.owner?.let { o -> o.user + (o.teamDomain?.let { " · $it.slack.com" } ?: "") }, checked = chosen?.teamId == t.teamId) { team = t.teamId } }
                    }
                    Text("＋ 添加工作区的配置 token", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { step = "token" })
                    Text("不用配置 token，自己建 app", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { step = "manual" })
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button("下一步", primary = true, enabled = chosen != null) { step = "app" } }
                }
                "token" -> {
                    Steps(listOf(
                        "打开 api.slack.com/apps，用要放 bot 的那个 Slack 工作区的账号登录。" to { open("https://api.slack.com/apps") },
                        "拉到页面最下面的「Your App Configuration Tokens」，点 Generate Token，选这个工作区。" to null,
                        "把以 xoxe-1- 开头的 Refresh Token 粘贴到下面。ember 会自己续期，以后不用再管。" to null,
                    ))
                    SecretField(config, { config = it }, "xoxe-1-…")
                    if (config.startsWith("xoxe.xoxp-")) Text("这是 Access Token。要的是它下面那个 Refresh Token，以 xoxe-1- 开头。", fontSize = 13.sp, color = C.red)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button("加上", primary = true, busy = busy, enabled = config.startsWith("xoxe-1-") && config.length > 20) {
                            run { team = api.addConfigToken(config); config = ""; step = "app" }
                        }
                    }
                }
                "app" -> {
                    Text("名字", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Field(name, { name = it }, "ember")
                    Text("描述", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Field(description, { description = it }, "Coding agent in your threads")
                    Text("头像、颜色和权限用默认的；建好以后可以在电脑上改。", fontSize = 12.sp, color = C.muted)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button("创建 app", primary = true, busy = busy, enabled = name.isNotBlank() && chosen != null) {
                            run { made = api.makeSlackApp(chosen!!.teamId, name.trim(), description.trim()); step = "install" }
                        }
                    }
                }
                "install" -> made?.let { m ->
                    val installed = overview.value?.slackInstalls?.firstOrNull { it.state == m.state }
                    Steps(listOf(
                        (if (m.install != null) (if (installed?.installed == true) "已装进「${installed.team ?: "工作区"}」。" else "app 已经建好。安装到工作区：在 Slack 里点「允许」，bot token 会自动交给 station。")
                        else "app 已经建好。安装到工作区，然后在 OAuth 页复制 Bot User OAuth Token（xoxb- 开头）。") to (if (installed?.installed == true) null else ({ open(m.install ?: m.installLink) })),
                        "在 Basic Information 页生成 App-Level Token 并复制（xapp- 开头；权限 Slack 已经勾好）。" to { open(m.appTokenLink) },
                        (if (m.install != null) "把 App-Level Token 填在下面。" else "把两个 token 填在下面。") to null,
                    ))
                    TokenFields(station, tokens, install = m.state)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button("下一步", primary = true, enabled = tokens.verified != null) { step = "bind" } }
                }
                "manual" -> {
                    Steps(listOf(
                        "用 ember 的配置在 Slack 新建一个 app。" to { scope.launch { try { open(api.createAppUrl("ember")) } catch (e: CoreException) { error = e.message } }; Unit },
                        "在 app 的 Basic Information 页生成 App-Level Token（权限 Slack 已经勾好）。" to null,
                        "在 Install App 页安装到工作区，复制 Bot User OAuth Token。" to null,
                        "把两个 token 填在下面。" to null,
                    ))
                    TokenFields(station, tokens)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button("下一步", primary = true, enabled = tokens.verified != null) { step = "bind" } }
                }
                else -> {
                    GroupLabel("模型")
                    if (models.isEmpty()) Text("这台 station 的 Profile 还没有启用模型，先在 Station 页的 Profile 里勾选。", fontSize = 13.sp, color = C.warn)
                    else Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                        models.forEach { m -> PickRow(m.model, m.runtimes.joinToString(" · ") { RUNTIME_LABEL[it] ?: it }, checked = entry?.model == m.model, leading = { MakerIcon(m.maker, m.runtimes.first(), 18.dp) }) { model = m } }
                    }
                    if (entry != null && entry.runtimes.size > 1) {
                        GroupLabel("运行时（创建后不能换）")
                        Seg(entry.runtimes.map { RUNTIME_LABEL[it] ?: it }, entry.runtimes.indexOf(rt).coerceAtLeast(0), { runtime = entry.runtimes[it] }, Modifier.fillMaxWidth(), height = 36.dp, fill = true)
                    }
                    GroupLabel("会话方式")
                    ModeChoices(mode, mention) { m, r -> mode = m; mention = r }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button("添加并连接", primary = true, busy = busy, enabled = entry != null) {
                            run {
                                val m = made
                                val id = api.createConnect(buildJsonObject {
                                    put("kind", "slack"); put("mode", mode); put("requireMention", mention)
                                    putJsonObject("bind") { put("runtime", rt); put("model", entry?.model ?: ""); put("effort", ""); put("profile", null as String?) }
                                    putJsonObject("slack") {
                                        put("appToken", tokens.app)
                                        if (m?.state != null) put("install", m.state) else { put("botToken", tokens.bot); if (m != null) put("appId", m.appId) }
                                    }
                                })
                                app.toast = "已添加连接，正在连接 Slack"
                                app.replace(Screen.Connect(station, id))
                            }
                        }
                    }
                }
            }
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
        }
    }
}

/** Numbered steps, each a line; one with a link opens it. */
@Composable
private fun Steps(steps: List<Pair<String, (() -> Unit)?>>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        steps.forEachIndexed { i, (text, open) ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${i + 1}.", fontSize = 14.sp, color = C.muted)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text, fontSize = 14.sp, color = C.ink)
                    if (open != null) Text("打开", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { open() })
                }
            }
        }
    }
}

