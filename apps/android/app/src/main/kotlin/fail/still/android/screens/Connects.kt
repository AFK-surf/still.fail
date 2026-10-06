// Connects (as the narrow web's web/src/mobile/Connects.tsx, from the desktop's Connects.tsx and Connect.tsx): the
// list of every station's, all or the viewer's; a connect's page (how it runs, how its conversations become sessions, its Slack link, what
// is done to it less often under "…"); how it runs, picked on a page of its own; a new one, a step a screen.
package fail.still.android.screens

import fail.still.android.BuildConfig
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
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
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.Connect
import fail.still.android.data.ConnectItem
import fail.still.android.data.ConnectsView
import fail.still.android.data.MODE_LABEL
import fail.still.android.data.MODE_TEXT
import fail.still.android.data.MadeSlackApp
import fail.still.android.data.ModelOption
import fail.still.android.data.Overview
import fail.still.android.data.RUNTIME_LABEL
import fail.still.android.data.SlackTokenForm
import fail.still.android.data.StillFailJson
import fail.still.android.data.SlackTokensView
import fail.still.android.data.StationView
import fail.still.android.data.PickView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.android.data.t
import fail.still.core.CoreException
import fail.still.android.data.errorText
import kotlinx.coroutines.launch
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
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

/** A connect as its people see it in Slack: its bot's picture; Slack's mark until Slack has said what that is. */
@Composable
fun ConnectAvatar(c: Connect, size: androidx.compose.ui.unit.Dp) {
    val image = c.botImage
    if (image != null) Avatar(c.id, c.name, size, picture = image)
    else Box(Modifier.size(size), contentAlignment = Alignment.Center) { SlackMark(size * 0.55f) }
}

/** A connect in its station's list: its bot's picture and name, how it runs, and its presence. */
@Composable
fun ConnectRow(station: String, c: Connect) {
    val app = LocalApp.current
    ListRow(onClick = { app.push(Screen.Connect(station, c.id)) }) {
        ConnectAvatar(c, 30.dp)
        Column(Modifier.weight(1f)) {
            Text(c.name + (c.team?.let { " · $it" } ?: ""), fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(listOfNotNull(c.modeText, c.runtimeText, c.bind.model?.let { c.modelName ?: it }).joinToString(" · "), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) { PresenceDot(c.presence); fail.still.android.ui.StatusText(c.statusText, fontSize = 12.sp, color = C.muted) }
    }
}

/** A connect by its station and id, as the workspace's connects view has it. */
@Composable
private fun rememberConnect(station: String, id: String): Pair<ConnectItem?, String?> {
    val app = LocalApp.current
    val connects by rememberTopic<ConnectsView>(app.core, Topics.connects(station.substringBefore('/'), false))
    val item = connects.value?.items?.firstOrNull { it.station == station && it.connect.id == id }
    val note = if (item != null) null else connects.error?.message ?: if (connects.value == null || connects.value!!.loading) t("android-settings.connects.reading") else t("android-settings.connects.none")
    return item to note
}

/**
 * Every station's connects on one page, from settings (SettingsHome.kt), as the narrow web's ConnectsScreen: all or those
 * the viewer made, each station's under its name with the Slack apps made there and not connected yet; a station offline
 * says so. A new one is added on a station picked (the only one online, without asking).
 */
@Composable
fun ConnectsScreen(current: WorkspaceEntry, only: String? = null) {
    val app = LocalApp.current
    var mine by rememberSaveable { mutableStateOf(false) }
    val connects by rememberTopic<ConnectsView>(app.core, Topics.connects(current.workspace.id, mine))
    val topic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    // From a station's page: that station's only, back to it.
    val stations = topic.value?.let { all -> if (only == null) all else all.filter { it.station == only } }
    val one = if (only != null) stations?.firstOrNull() else null
    val online = stations.orEmpty().filter { it.online }
    val view = connects.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(one?.name ?: t("android-settings.title"), app::pop, trailing = if (online.isNotEmpty()) ({
            NavButton(Icons.Plus, {
                if (online.size == 1) openNewConnect(app, online[0].station)
                else openPickStation(app, t("android-settings.flow.title"), online) { openNewConnect(app, it.station) }
            }, 20.dp)
        }) else null)
        LargeTitle(one?.let { t("android-settings.connects.on", "name" to it.name) } ?: "", t("android-settings.connects.title"))
        PageNote(t("android-settings.connects.note", "app" to BuildConfig.APP_NAME))
        Seg(listOf(t("android-settings.connects.all"), t("android-settings.connects.mine")), if (mine) 1 else 0, { mine = it == 1 }, Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 2.dp).fillMaxWidth(), height = 34.dp, fill = true)
        if (stations == null || view == null) Text(connects.error?.message ?: t("android-settings.connects.reading"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(20.dp))
        else stations.forEach { s ->
            val here = view.items.filter { it.station == s.station }
            val waiting = s.overview?.slackApps.orEmpty()
            if (s.online && here.isEmpty() && waiting.isEmpty() && mine && one == null) return@forEach
            if (one == null) SectionHeader(if (s.online) s.name else t("android-settings.connects.offline", "name" to s.name), start = 24.dp)
            ListCard {
                if (!s.online && here.isEmpty()) ListRow { Text(t("android-settings.connects.stationOffline"), fontSize = 15.sp, color = C.muted) }
                else if (here.isEmpty() && waiting.isEmpty()) ListRow { Text(if (s.overview != null) t("android-settings.connects.empty") else t("android-settings.reading"), fontSize = 15.sp, color = C.muted) }
                here.forEach { ConnectRow(it.station, it.connect) }
                // The Slack apps made here that no connect has taken yet: to be finished any time.
                waiting.forEach { a -> WaitingApp(app, s.station, a, s.online) }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
fun ConnectScreen(station: String, id: String) {
    val app = LocalApp.current
    val (item, note) = rememberConnect(station, id)
    if (item == null) return Column(Modifier.fillMaxSize()) { NavBar(t("android-settings.connects.title"), app::pop, t("android-settings.connects.title")); Loading(note ?: "") }
    val connect = item.connect
    val c = connect.connection
    Column(Modifier.fillMaxSize()) {
        NavBar(t("android-settings.connects.title"), app::pop, connect.name, sub = { PresenceDot(connect.presence); fail.still.android.ui.StatusText(connect.statusText, fontSize = 11.sp, color = C.muted) },
            trailing = { NavButton(Icons.More, { openConnectMenu(app, station, connect) }) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            // Who it is in Slack: its bot's picture, its Slack workspace, whose it is.
            fail.still.android.ui.Card {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ConnectAvatar(connect, 44.dp)
                    Column(Modifier.weight(1f)) {
                        Text(connect.team ?: "Slack", fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(item.stationName + (connect.createdBy?.let { t("android-settings.connect.owner", "name" to (it.shown?.display ?: it.name)) } ?: ""), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    // A change asked from its menu or sheets (they close at once): a spinner until the station has it, a red mark a moment if it failed.
                    val calls = setOf("connect.reconnect", "connect.put")
                    DoingMark(app.isDoing(calls, "station" to station, "id" to connect.id), app.failedOf(calls, "station" to station, "id" to connect.id))
                }
            }
            if (c.state == "no_tokens" || c.state == "error" || (c.state == "reconnecting" && c.lastError != null)) Callout {
                if (c.state == "no_tokens") Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(t("android-settings.connect.noTokens"), fontSize = 13.sp, color = C.ink)
                    Text(t("android-settings.connect.fillTokens"), fontSize = 13.sp, color = C.accent, modifier = Modifier.clickable { openTokens(app, station, connect) })
                } else Text(if (c.state == "error") c.error ?: "" else t("android-settings.connect.reconnecting", "error" to c.lastError), fontSize = 13.sp, color = C.ink)
            }
            SectionHeader(t("android-settings.connect.run"), start = 24.dp)
            ListCard {
                ListRow(onClick = { app.push(Screen.ConnectRun(station, connect.id)) }) {
                    Text(t("android-settings.connect.model"), fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.widthIn(min = 32.dp))
                    Text(
                        listOf(connect.bind.model?.let { connect.modelName ?: it } ?: t("android-settings.connect.pickModel"), connect.bind.effort?.ifEmpty { null } ?: t("android-settings.connect.defaultEffort"), if (connect.bind.profile != null) t("android-settings.connect.fixedAccount") else t("android-settings.connect.autoAccount")).joinToString(" · "),
                        fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                ListRow(onClick = { app.sheet = SheetSpec(0.8f, draggable = true) { ModeSheet(station, item) } }) {
                    Text(t("android-settings.connect.sessions"), fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.widthIn(min = 32.dp))
                    Column(Modifier.weight(1f)) {
                        Text(MODE_LABEL[connect.mode] ?: connect.mode, fontSize = 15.sp, color = C.ink)
                        Text((MODE_TEXT[connect.mode] ?: "") + if (connect.mode == "single-session") (if (connect.requireMention) t("android-settings.connect.mentionOnly") else t("android-settings.connect.everyMessage")) else "", fontSize = 13.sp, color = C.muted)
                    }
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                if (connect.mode == "single-session") ListRow(onClick = { app.sheet = SheetSpec(0.7f, draggable = true) { SessionSheet(station, item) } }) {
                    Text(t("android-settings.connect.current"), fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.widthIn(min = 32.dp))
                    Text(item.bound?.titleText ?: t("android-settings.connect.noSession"), fontSize = 15.sp, color = if (item.bound != null) C.ink else C.muted, modifier = Modifier.weight(1f))
                    DoingMark(app.isDoing("connect.bindSession", "station" to station, "connect" to connect.id), app.failedOf("connect.bindSession", "station" to station, "connect" to connect.id))
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
            }
            Text(t("android-settings.connect.runtime", "runtime" to connect.runtimeText), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp))
            // Its Slack app, changed now and then: name, picture, colour, permissions (the desktop's SlackAppSection).
            SectionHeader("Slack app", start = 24.dp)
            ListCard {
                ListRow(onClick = { app.push(Screen.SlackApp(station, connect.id)) }) {
                    SlackMark(16.dp)
                    Column(Modifier.weight(1f)) {
                        Text(t("android-settings.slack.sub"), fontSize = 15.sp, color = C.ink)
                        Text(t("android-settings.connect.slackAppNote"), fontSize = 13.sp, color = C.muted)
                    }
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
            }
            SectionHeader(t("android-settings.connect.recent"), start = 24.dp)
            ListCard {
                if (item.sessions.isEmpty()) ListRow { Text(t("android-settings.connect.noSessions", "name" to connect.name), fontSize = 15.sp, color = C.muted) }
                item.sessions.forEach { s ->
                    ListRow(onClick = { app.push(Screen.Chat(station, fail.still.android.data.ChatOf.Session(s.key))) }) {
                        Text(s.titleText, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        fail.still.android.ui.StatusText(s.statusText, fontSize = 13.sp, color = C.muted)
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
        val context = LocalContext.current
        // Closes at once and goes on by itself: the connect's page marks it under way, a toast says how it ended.
        val act = { what: String, done: String, call: suspend () -> Unit -> app.sheet = null; app.act(what, done) { call() } }
        // Under way (asked a moment ago, the sheet opened again): a spinner on its row, and neither tapped again.
        val reconnecting = app.isDoing("connect.reconnect", "station" to station, "id" to connect.id)
        val switching = app.isDoing("connect.put", "station" to station, "id" to connect.id)
        // Failed a moment ago (the sheet may have been closed meanwhile): a red mark on its row, a tap says why.
        val reconnectFailed = app.failedOf("connect.reconnect", "station" to station, "id" to connect.id)
        val switchFailed = app.failedOf("connect.put", "station" to station, "id" to connect.id)
        SheetGrab()
        SheetHead(connect.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow(t("android-settings.connect.reconnect"), enabled = !switching, busy = reconnecting, failed = reconnectFailed) { act(t("android-settings.connect.reconnectWhat"), t("android-settings.connect.reconnected")) { api.reconnect(connect.id) } }
            PickRow(t("android-settings.connect.changeTokens")) { openTokens(app, station, connect) }
            connect.connection.workspace?.url?.let { url -> PickRow(t("android-settings.connect.openSlack")) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }
            if (connect.enabled) PickRow(t("android-settings.connect.disable"), t("android-settings.connect.disableNote"), enabled = !reconnecting, busy = switching, failed = switchFailed) { act(t("android-settings.connect.disableWhat"), t("android-settings.connect.disabled")) { api.putConnect(connect.id, buildJsonObject { put("enabled", false) }) } }
            else PickRow(t("android-settings.connect.enable"), enabled = !reconnecting, busy = switching, failed = switchFailed) { act(t("android-settings.connect.enableWhat"), t("android-settings.connect.enabled")) { api.putConnect(connect.id, buildJsonObject { put("enabled", true) }) } }
            PickRow(t("android-settings.connect.changeOwner"), connect.createdBy?.shown?.display ?: connect.createdBy?.name) { app.sheet = SheetSpec(0.6f) { OwnerSheet(station, connect) } }
            PickRow(t("android-settings.connect.delete"), color = C.red) {
                confirm(app, t("android-settings.connect.deleteTitle", "name" to connect.name),
                    if (connect.sessions > 0) t("android-settings.connect.deleteTextSessions", "n" to connect.sessions) else t("android-settings.connect.deleteText"),
                    t("android-settings.connect.delete"), danger = true, what = t("android-settings.connect.deleteWhat"), then = app::pop) { api.deleteConnect(connect.id); app.toast = t("android-settings.connect.deleted") }
            }
        }
    }
}

/** Hands a connect to another person of the workspace. */
@Composable
private fun ColumnScope.OwnerSheet(station: String, connect: Connect) {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(station.substringBefore('/')))
    SheetGrab()
    SheetHead(t("android-settings.connect.changeOwner"))
    // The one picked closes the sheet at once; the connect's page marks it under way until the station has it.
    val busy = app.isDoing("connect.put", "station" to station, "id" to connect.id)
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Text(t("android-settings.connect.ownerNote"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp))
        ws.value?.members.orEmpty().forEach { m ->
            val current = m.email.equals(connect.createdBy?.id, ignoreCase = true)
            PickRow(m.name.ifEmpty { m.email }, m.email, checked = current, enabled = !busy) {
                app.sheet = null
                if (!current) app.act(t("android-settings.connect.ownerWhat"), t("android-settings.connect.ownerChanged")) {
                    app.api(station).putConnect(connect.id, buildJsonObject { putJsonObject("owner") { put("id", m.email); put("name", m.name.ifEmpty { m.email }) } })
                }
            }
        }
    }
}

/** What switching a connect to `next` does to its conversations, in plain words (web/src/pages/Connect.tsx → consequences). */
private fun consequences(connect: Connect, mode: String, requireMention: Boolean, running: Long): List<String> {
    val out = mutableListOf<String>()
    if (connect.mode == "multi-session" && mode == "single-session") {
        out += t("android-settings.mode.toSingle")
        out += if (connect.session != null) t("android-settings.mode.keepSession") else t("android-settings.mode.newSession")
        if (!requireMention) out += t("android-settings.mode.noMention")
    } else if (connect.mode == "single-session" && mode == "multi-session") {
        out += t("android-settings.mode.toMulti")
        out += t("android-settings.mode.oldThreads")
        out += t("android-settings.mode.back")
    } else if (requireMention != connect.requireMention) {
        out += if (requireMention) t("android-settings.mode.mention") else t("android-settings.mode.noMention")
    }
    if (running > 0) out += t("android-settings.mode.running", "n" to running)
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
                Text(t("android-settings.mode.mentionTitle"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(if (requireMention) t("android-settings.mode.mentionOn") else t("android-settings.mode.mentionOff"), fontSize = 13.sp, color = C.muted)
            }
            Switch(requireMention)
        }
    }
}

@Composable
internal fun Switch(on: Boolean) {
    Box(Modifier.size(44.dp, 26.dp).clip(RoundedCornerShape(13.dp)).background(if (on) C.green else C.line), contentAlignment = Alignment.CenterStart) {
        Box(Modifier.offset(x = if (on) 21.dp else 3.dp).size(20.dp).clip(CircleShape).background(androidx.compose.ui.graphics.Color.White))
    }
}

/** How its conversations become sessions: picked, with what changing it does said before it is done. */
@Composable
private fun ColumnScope.ModeSheet(station: String, item: ConnectItem) {
    val app = LocalApp.current
    val connect = item.connect
    var mode by remember { mutableStateOf(connect.mode) }
    var mention by remember { mutableStateOf(connect.requireMention) }
    val busy = app.isDoing("connect.put", "station" to station, "id" to connect.id)
    val changed = mode != connect.mode || (mode == "single-session" && mention != connect.requireMention)
    val effects = if (changed) consequences(connect, mode, mention, item.running) else emptyList()
    SheetGrab()
    SheetHead(t("android-settings.mode.title"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ModeChoices(mode, mention) { m, r -> mode = m; mention = r }
        if (effects.isNotEmpty()) Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(t("android-settings.mode.after"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            effects.forEach { Text("· $it", fontSize = 13.sp, color = C.ink) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(if (mode == connect.mode) t("android-settings.mode.confirm") else if (mode == "single-session") t("android-settings.mode.toSingleButton") else t("android-settings.mode.toMultiButton"), primary = true, enabled = changed && !busy) {
                val (m, r) = mode to mention
                app.sheet = null
                app.act(t("android-settings.mode.changeWhat"), t("android-settings.mode.changed")) { app.api(station).putConnect(connect.id, buildJsonObject { put("mode", m); put("requireMention", r) }) }
            }
        }
    }
}

/** A single-session connect's session: the one its messages go into, switched, or a new one. */
@Composable
private fun ColumnScope.SessionSheet(station: String, item: ConnectItem) {
    val app = LocalApp.current
    val connect = item.connect
    var choice by remember { mutableStateOf(connect.session ?: "new") }
    var title by remember { mutableStateOf("") }
    val busy = app.isDoing("connect.bindSession", "station" to station, "connect" to connect.id)
    SheetGrab()
    SheetHead(t("android-settings.session.title"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(t("android-settings.session.note", "name" to connect.name), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp))
        PickRow(t("android-settings.session.new"), t("android-settings.session.newNote"), checked = choice == "new") { choice = "new" }
        if (choice == "new") Box(Modifier.padding(horizontal = 20.dp)) { Field(title, { title = it }, t("android-settings.session.namePlaceholder")) }
        item.candidates.forEach { s -> PickRow(s.titleText, s.agentText, checked = choice == s.key) { choice = s.key } }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(if (choice == "new") t("android-settings.session.createUse") else t("android-settings.session.use"), primary = true, enabled = choice != connect.session && !busy) {
                val (picked, name) = choice to title
                app.sheet = null
                app.act(if (picked == "new") t("android-settings.session.createWhat") else t("android-settings.session.switchWhat"), if (picked == "new") t("android-settings.session.created") else t("android-settings.session.switched")) {
                    app.api(station).bindSession(connect.id, if (picked == "new") null else picked, name)
                }
            }
        }
    }
}

// ── tokens ─────────────────────────────────────────────────────────────

/** The form is owned by the shared core; this adapter only binds its values to Compose. */
private class Tokens(private val owner: AppState, private val station: String, val form: String) {
    var view by mutableStateOf(SlackTokensView(appToken = "", botToken = "", errors = emptyList(), ready = false))
    // Immediate text-field echo; readiness, validation and the draft itself belong to core.
    private var appEcho by mutableStateOf("")
    private var botEcho by mutableStateOf("")
    var app: String
        get() = appEcho
        set(value) { appEcho = value; edit(buildJsonObject { put("appToken", value) }) }
    var bot: String
        get() = botEcho
        set(value) { botEcho = value; edit(buildJsonObject { put("botToken", value) }) }
    val verified get() = if (view.appToken == appEcho && view.botToken == botEcho) view.verified else null
    val errors get() = view.errors
    val checking get() = owner.isDoing("slack.tokens.verify", "station" to station, "form" to form)
    val ready get() = view.ready
    val address = StillFailJson.encodeToJsonElement(SlackTokenForm.serializer(), SlackTokenForm(station, form)).jsonObject
    suspend fun call(action: String, input: JsonObject? = null) = owner.core.call("slack.tokens.$action", buildJsonObject {
        address.forEach { (key, value) -> put(key, value) }; input?.let { put("input", it) }
    })
    private fun edit(input: JsonObject) { owner.act(t("android-settings.tokens.edit")) { call("edit", input) } }
    fun reset() { edit(buildJsonObject { put("clear", true) }) }
    fun then(go: suspend () -> Unit) {
        if (checking) return
        owner.act(t("android-settings.tokens.verify")) { if (call("verify").jsonPrimitive.booleanOrNull == true) go() }
    }
}

@Composable
private fun rememberTokens(app: AppState, station: String, connect: String? = null, install: String? = null, form: String? = null): Tokens {
    val tokens = remember(app.core, station, form) { Tokens(app, station, form ?: java.util.UUID.randomUUID().toString()) }
    val topic by rememberTopic<SlackTokensView>(app.core, buildJsonObject { put("topic", "slackTokens"); tokens.address.forEach { (key, value) -> put(key, value) } })
    tokens.view = topic.value ?: SlackTokensView(appToken = "", botToken = "", errors = emptyList(), ready = false)
    LaunchedEffect(tokens, connect, install) {
        try { tokens.call("edit", buildJsonObject { put("connect", connect); put("install", install) }) }
        catch (e: CoreException) { app.toast = e.message }
    }
    DisposableEffect(tokens) {
        onDispose { app.act(t("android-settings.tokens.drop")) { tokens.call("drop") } }
    }
    return tokens
}

/** Replaces a connect's Slack tokens (either one; the other kept), verified before they are saved. */
private fun openTokens(app: AppState, station: String, connect: Connect) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val tokens = rememberTokens(app, station, connect = connect.id)
        val busy = app.isDoing("connect.put", "station" to station, "id" to connect.id)
        SheetGrab()
        SheetHead("Slack token")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("android-settings.tokens.note"), fontSize = 12.sp, color = C.muted)
            TokenFields(tokens, masked = connect.slack.appToken to connect.slack.botToken)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(t("android-settings.tokens.save"), primary = true, busy = busy || tokens.checking, enabled = tokens.ready) {
                    tokens.then {
                        try { app.api(station).putConnect(connect.id, buildJsonObject { putJsonObject("slack") { put("appToken", tokens.app); put("botToken", tokens.bot) } }); app.toast = t("android-settings.tokens.saved"); app.sheet = null }
                        catch (e: CoreException) { app.toast = e.message }
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
 * The two tokens, checked by the button that goes on (`Tokens.then`), whose failures are said under them. For an
 * existing connect a blank field keeps the stored token. An app installed through Slack's OAuth (`install`) has its bot
 * token on the station already: only the app-level token is asked for.
 */
@Composable
private fun TokenFields(tokens: Tokens, masked: Pair<String, String>? = null, install: String? = null) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("App-Level Token", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        SecretField(tokens.app, { tokens.app = it }, masked?.first?.ifEmpty { null }?.let { t("android-settings.tokens.kept", "token" to it) } ?: "xapp-…")
        if (install == null) {
            Text("Bot Token", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            SecretField(tokens.bot, { tokens.bot = it }, masked?.second?.ifEmpty { null }?.let { t("android-settings.tokens.kept", "token" to it) } ?: "xoxb-…")
        }
        tokens.verified?.let { Text(t("android-settings.tokens.verified", "team" to it.team, "bot" to it.botName), fontSize = 12.sp, color = C.green) }
        tokens.errors.forEach { Text(it, fontSize = 13.sp, color = C.red) }
    }
}

// ── how it runs ────────────────────────────────────────────────────────

/** The model a connect runs, how hard it thinks and who runs it: picked like an agent's (History.kt), saved for new sessions. */
@Composable
fun ConnectRunScreen(station: String, id: String) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val (item, note) = rememberConnect(station, id)
    val pickOf = "connect:$id"
    val picking by rememberTopic<PickView>(app.core, Topics.pick(station, pickOf))
    val v = picking.value
    val pick = { fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit -> app.act(t("android-settings.flow.choose")) { app.api(station).pickSet(pickOf, fill) }; Unit }
    LaunchedEffect(station, id) { pick { put("open", true) } }
    var list by remember { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler(enabled = list != null) { list = null }
    Column(Modifier.fillMaxSize()) {
        NavBar(if (list != null) t("android-settings.run.title") else t("common.back"), { if (list != null) list = null else app.pop() }, when (list) { "model" -> t("android-settings.connect.pickModel"); "account" -> t("android-settings.run.pickAccount"); else -> t("android-settings.run.title") })
        if (item == null || v == null) return Loading(note ?: t("android-settings.reading"))
        val connect = item.connect
        val runtime = connect.bind.runtime
        val models = v.options
        val model = v.draft.model
        val effort = v.draft.effort
        val profile = v.draft.profile
        val busy = app.isDoing("pick.save", "station" to station, "of" to pickOf)
        val accounts = v.accounts
        val efforts = v.efforts
        val changed = v.changed
        if (list == "model") return ModelList(models, runtime, model) { m -> pick { put("model", m) }; list = null }
        if (list == "account") return AccountList(accounts, runtime, profile) { p -> pick { put("profile", p) }; list = null }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp)) {
            if (models.isEmpty()) Text(t("android-settings.run.noModels", "runtime" to connect.runtimeText), fontSize = 13.sp, color = C.warn, modifier = Modifier.padding(top = 8.dp))
            GroupLabel(t("android-settings.connect.model"))
            SettingRow(onClick = { list = "model" }, leading = { MakerIcon(v.maker, runtime, 18.dp) }) { Text(v.modelText, fontSize = 15.sp, color = C.ink) }
            GroupLabel(t("android-settings.run.effort"))
            EffortChips(listOf<String?>(null) + efforts, effort) { e -> pick { put("effort", e) } }
            GroupLabel(t("android-settings.run.account"))
            SettingRow(onClick = { list = "account" }) {
                Text(v.accountText, fontSize = 15.sp, color = C.ink)
                Text(v.accountNote, fontSize = 12.sp, color = C.muted)
            }
            Text(t("android-settings.run.note"), fontSize = 12.sp, color = C.subtle, modifier = Modifier.padding(vertical = 12.dp))
        }
        Box(
            Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp, vertical = 12.dp).fillMaxWidth().heightIn(min = 52.dp)
                .clip(RoundedCornerShape(16.dp)).background(if (changed) C.ink else C.chip)
                .clickable(enabled = !busy && !(changed && model == null)) {
                    // Back at once, not waiting on the station; failed, a toast says why.
                    app.pop()
                    if (!changed) return@clickable
                    app.scope.launch {
                        try {
                            app.api(station).pickSave(pickOf)
                            app.toast = t("android-settings.run.saved")
                        } catch (e: CoreException) { app.toast = t("android-settings.run.saveFailed", "error" to errorText(e)) }
                    }
                }.padding(horizontal = 16.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (busy) androidx.compose.material3.CircularProgressIndicator(Modifier.size(14.dp), color = if (changed) C.bg else C.muted, strokeWidth = 1.5.dp)
                Text(v.saveText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (changed) C.bg else C.ink)
            }
        }
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
    val resume = remember { app.resume(station).also { app.setResume(station, null) } }
    val flow = rememberConnectFlow(app, station, resume)
    val tokens = rememberTokens(app, station, install = flow.view?.made?.state, form = flow.form)
    val view = flow.view
    if (view == null) { NavBar(t("common.cancel"), { app.pop() }, t("android-settings.flow.title")); return }
    val step = view.step
    val teams = view.teams
    val chosen = view.chosen
    val models = view.pick?.options.orEmpty()
    val entry = view.pick?.valueOption
    val rt = view.pick?.value?.runtime ?: "claude"
    val made = view.made
    val mode = view.mode
    val mention = view.requireMention
    val busy = flow.busy
    val error = flow.error
    val draft = remember(flow) { AppDraft(SlackAppSettings(view.settings.name, view.settings.displayName, view.settings.description, view.settings.longDescription, view.settings.backgroundColor, view.settings.groups)) { settings -> flow.edit { put("settings", settings) } } }
    // Bitmap decoding/rendering is platform work; the chosen image and its error are in the core draft.
    var icon by remember { mutableStateOf<IconPick?>(null) }
    val iconError = view.iconError
    val back = { flow.go("back") { app.pop() } }
    androidx.activity.compose.BackHandler(enabled = step != "team") { back() }
    val open = { url: String -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    Column(Modifier.fillMaxSize()) {
        NavBar(if (view.back == "close") t("common.cancel") else t("android-settings.flow.previous"), back, t("android-settings.flow.title"), sub = { Text("${view.title} · ${view.number} / ${view.total}", fontSize = 11.sp, color = C.muted) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // A connect runs a profile's model: with none on this station, that comes first.
            val noProfile = view.noProfile
            if (step == "team" && noProfile) Column(Modifier.fillMaxWidth().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                fail.still.android.ui.Illustration(fail.still.android.R.drawable.illus_no_profile, fail.still.android.R.drawable.illus_no_profile_dark, 240.dp)
                Text(t("android-settings.flow.noProfile"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(t("android-settings.flow.noProfileNote"), fontSize = 14.sp, color = C.muted, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Button(t("android-settings.flow.addProfile"), primary = true) { app.replace(Screen.NewProfile(station)) }
            }
            else when (step) {
                "team" -> if (teams.isEmpty()) {
                    Text(t("android-settings.flow.tokenNote", "app" to BuildConfig.APP_NAME), fontSize = 14.sp, color = C.muted)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button(t("android-settings.slack.addToken"), primary = true) { flow.go("token") } }
                    Text(t("android-settings.flow.manualInSlack"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { flow.go("manual") })
                } else {
                    Text(t("android-settings.flow.whichTeam"), fontSize = 14.sp, color = C.muted)
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                        teams.forEach { t -> PickRow(t.name, t.owner?.let { o -> o.user + (o.teamDomain?.let { " · $it.slack.com" } ?: "") }, checked = chosen?.teamId == t.teamId) { flow.edit { put("team", t.teamId) } } }
                    }
                    Text(t("android-settings.flow.addTeamToken"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { flow.go("token") })
                    chosen?.let { team ->
                        Text(t("android-settings.flow.removeToken", "name" to team.name), fontSize = 14.sp, color = C.muted, modifier = Modifier.clickable {
                            confirm(app, t("android-settings.flow.removeTokenTitle", "name" to team.name), t("android-settings.flow.removeTokenText", "app" to BuildConfig.APP_NAME), t("android-settings.members.remove"), danger = true,
                                what = t("android-settings.flow.removeTokenWhat"), then = { flow.edit { put("team", null as String?) } }) {
                                api.removeConfigToken(team.teamId); app.toast = t("android-settings.flow.tokenRemoved")
                            }
                        })
                    }
                    Text(t("android-settings.flow.manual"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { flow.go("manual") })
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button(t("android-settings.flow.next"), primary = true, enabled = chosen != null) { flow.go("app") } }
                }
                "token" -> ConfigTokenSteps(station, flow) {}
                "app" -> {
                    FormLabel(t("android-settings.slack.name"))
                    Field(draft.name, { draft.name = it }, BuildConfig.APP_NAME)
                    FormLabel(t("android-settings.flow.description"))
                    Field(draft.description, { draft.description = it }, "Coding agent in your threads")
                    AppLook(draft, icon, { i, e -> icon = i; flow.edit { put("icon", i?.data); put("iconError", e) } }, fresh = true)
                    iconError?.let { Text(it, fontSize = 13.sp, color = C.red) }
                    Text(t("android-settings.flow.permsNote"), fontSize = 13.sp, color = C.muted)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button(t("android-settings.flow.make"), primary = true, busy = busy, enabled = view.canMake) {
                            flow.act("make")
                        }
                    }
                }
                "install" -> if (made == null) Text(t("android-settings.flow.readingApp"), fontSize = 13.sp, color = C.muted) else {
                    val m = made
                    val install = m.install
                    iconError?.let { Text(t("android-settings.flow.iconFailed", "error" to it), fontSize = 13.sp, color = C.red) }
                    Steps(listOf(
                        (if (install != null) (if (m.installed) t("android-settings.flow.installed", "team" to (m.installedTeam ?: m.team ?: t("android-settings.flow.team"))) else t("android-settings.flow.installOauth"))
                        else t("android-settings.flow.installManual")) to (if (m.installed) null else ({ open(install ?: m.links.install) })),
                        t("android-settings.flow.appToken") to { open(m.links.appToken) },
                        (if (install != null) t("android-settings.flow.pasteAppToken") else t("android-settings.flow.pasteTokens")) to null,
                    ))
                    if (install == null) Text(t("android-settings.flow.oauthPage"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { open(m.links.oauth) })
                    TokenFields(tokens, install = m.state)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button(t("android-settings.flow.next"), primary = true, busy = busy, enabled = tokens.ready) { flow.act("verify") }
                    }
                }
                "manual" -> {
                    Steps(listOf(
                        t("android-settings.flow.manual1", "app" to BuildConfig.APP_NAME) to { app.act(t("android-settings.flow.openSlack")) { open(api.createAppUrl(BuildConfig.APP_NAME)) } },
                        t("android-settings.flow.manual2") to null,
                        t("android-settings.flow.manual3") to null,
                        t("android-settings.flow.pasteTokens") to null,
                    ))
                    TokenFields(tokens)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button(t("android-settings.flow.next"), primary = true, busy = busy, enabled = tokens.ready) { flow.act("verify") }
                    }
                }
                else -> {
                    GroupLabel(t("android-settings.connect.model"))
                    if (models.isEmpty()) Text(t("android-settings.flow.noModels"), fontSize = 13.sp, color = C.warn)
                    else Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                        models.forEach { m -> PickRow(m.name, m.runtimes.joinToString(" · ") { RUNTIME_LABEL[it] ?: it }, checked = entry?.model == m.model, leading = { MakerIcon(m.maker, m.runtimes.first(), 18.dp) }) { flow.choose { put("model", m.model) } } }
                    }
                    if (entry != null && entry.runtimes.size > 1) {
                        GroupLabel(t("android-settings.flow.runtime"))
                        Seg(entry.runtimes.map { RUNTIME_LABEL[it] ?: it }, entry.runtimes.indexOf(rt).coerceAtLeast(0), { flow.choose { put("runtime", entry.runtimes[it]) } }, Modifier.fillMaxWidth(), height = 36.dp, fill = true)
                    }
                    GroupLabel(t("android-settings.mode.title"))
                    ModeChoices(mode, mention) { m, r -> flow.edit { put("mode", m); put("requireMention", r) } }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button(t("android-settings.flow.create"), primary = true, busy = busy, enabled = entry != null) {
                            flow.act("create") { result ->
                                app.toast = t("android-settings.flow.created")
                                app.replace(Screen.Connect(station, result["id"]!!.jsonPrimitive.content))
                            }
                        }
                    }
                }
            }
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
        }
    }
}

/** The new-connect page, from the start or (`resume`) going on with a Slack app made before; a screen carries only its station. */
fun openNewConnect(app: AppState, station: String, resume: String? = null) {
    app.setResume(station, resume)
    app.push(Screen.NewConnect(station))
}

/**
 * A Slack app made on a station that no connect has taken yet (the viewer's): where it stands (to install, or only its
 * app-level token left), going on from there while the station is online, or dropping it (it stays in Slack).
 */
@Composable
internal fun WaitingApp(app: AppState, station: String, a: MadeSlackApp, online: Boolean) {
    val where = if (a.installed) t("android-settings.waiting.installed", "team" to (a.installedTeam ?: a.team ?: t("android-settings.flow.team"))) else if (a.install != null) t("android-settings.waiting.notInstalled") else t("android-settings.waiting.noTokens")
    ListRow(onClick = if (online) ({ openWaitingMenu(app, station, a) }) else null) {
        Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) { SlackMark(16.dp) }
        Column(Modifier.weight(1f)) {
            Text(a.name + (a.team?.let { " · $it" } ?: ""), fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(where, fontSize = 13.sp, color = C.muted, maxLines = 2)
        }
        // Being dropped (the sheet that asked gone): a spinner until the station has it, a red mark a moment if it failed.
        DoingMark(app.isDoing("slack.dropApp", "station" to station, "appId" to a.appId), app.failedOf("slack.dropApp", "station" to station, "appId" to a.appId))
        if (online) Text(t("android-settings.waiting.continue"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { openNewConnect(app, station, a.appId) })
        else Text(t("android-settings.waiting.offline"), fontSize = 12.sp, color = C.muted)
    }
}

/** Going on with a waiting app, or dropping it from still.fail (it stays in Slack). */
private fun openWaitingMenu(app: AppState, station: String, a: MadeSlackApp) {
    app.sheet = SheetSpec(0.36f) {
        SheetGrab()
        SheetHead(a.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow(t("android-settings.waiting.continueRow")) { openNewConnect(app, station, a.appId) }
            PickRow(t("android-settings.waiting.remove"), color = C.red) {
                confirm(app, t("android-settings.station.removeTitle", "name" to a.name), t("android-settings.waiting.removeText", "app" to BuildConfig.APP_NAME), t("android-settings.members.remove"), danger = true,
                    what = t("android-settings.waiting.removeWhat")) {
                    app.api(station).dropSlackApp(a.appId); app.toast = t("android-settings.members.removed")
                }
            }
        }
    }
}

/** Numbered steps, each a line; one with a link opens it. */
@Composable
internal fun Steps(steps: List<Pair<String, (() -> Unit)?>>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        steps.forEachIndexed { i, (text, open) ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${i + 1}.", fontSize = 14.sp, color = C.muted)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text, fontSize = 14.sp, color = C.ink)
                    if (open != null) Text(t("android-settings.open"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { open() })
                }
            }
        }
    }
}

