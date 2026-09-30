// The workspace's stations: each with the buddy's face for its state and its
// load as rings; one station's profiles (which models may be used) and
// connections.
package fail.still.android.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
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
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.Screen
import fail.still.android.data.ACCESS_LABEL
import fail.still.android.data.Profile
import fail.still.android.ui.QuotaRings
import fail.still.android.data.StationView
import fail.still.android.data.StationNet
import fail.still.android.data.NetFigure
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Illustration
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.Mark
import fail.still.android.ui.NavBack
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.Ring
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SlackMark
import fail.still.core.CoreException
import kotlinx.coroutines.launch

/** The buddy's face for a station: at work, idle, or asleep. */
@Composable
internal fun Buddy(s: StationView, size: Int = 40) {
    val dark = C.dark
    val face = when (s.face) {
        "offline" -> if (dark) R.drawable.buddy_offline_dark else R.drawable.buddy_offline
        "working" -> if (dark) R.drawable.buddy_working_dark else R.drawable.buddy_working
        else -> if (dark) R.drawable.buddy_idle_dark else R.drawable.buddy_idle
    }
    Image(painterResource(face), null, Modifier.size(size.dp))
}

/** Back to the chats, at the top of a large-title page. */
@Composable
fun TopBack(label: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 10.dp, top = 6.dp, bottom = 4.dp)) { NavBack(label, onBack) }
}

@Composable
fun StationsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(ws.id))
    val list = stations.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("会话", app::pop)
        // No station yet: adding the first one is the page.
        if (list != null && list.isEmpty()) { FirstStation(current); return@Column }
        LargeTitle(if (list != null) "${ws.name} · ${list.count { it.online }}/${list.size} 在线" else ws.name, "Station")
        if (list == null) {
            Text(stations.error?.message ?: "正在读取 station…", color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(20.dp))
        } else {
            list.forEach { s ->
                Card(onClick = { app.push(Screen.Station(s.station)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Buddy(s)
                        Column(Modifier.weight(1f)) {
                            Text(s.name, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink)
                            Text(s.summary, fontSize = 13.sp, color = C.muted)
                        }
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                    val host = s.host
                    if (s.online && host != null) {
                        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            host.meters.forEach { Ring(it.percent, it.short, it.level, 40.dp) }
                        }
                        s.net?.let { NetLine(it, Modifier.padding(top = 10.dp)) }
                    } else if (!s.online) {
                        Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                            Text("这台机器很久没联系 still.fail 了", fontSize = 13.sp, color = C.muted)
                        }
                    }
                }
            }
        }
        if (!list.isNullOrEmpty() && isManager(current)) ListCard {
            ListRow(onClick = { openAddStation(app, current, list.map { it.id }) }) { Text("＋ 添加 station", fontSize = 15.sp, color = C.accent) }
        }
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
fun StationScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    Column(Modifier.fillMaxSize()) {
        val manager = isManager(current)
        NavBar("Station", app::pop, s?.name ?: stationName(address), sub = s?.let { st ->
            { Text(st.line.orEmpty(), fontSize = 11.sp, color = C.muted, maxLines = 1) }
        }, trailing = if (s != null && manager) ({ NavButton(Icons.More, { openStationMenu(app, current, s) }) }) else null)
        if (s == null) return Loading(stations.error?.message ?: "正在读取…")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            val host = s.host
            if (s.online && host != null) {
                Card {
                    Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                        host.meters.forEach { Ring(it.percent, it.short, it.level) }
                    }
                    Text(host.line, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp))
                    s.net?.let { NetLine(it, Modifier.padding(top = 6.dp)) }
                    s.overview?.processesText?.takeIf { it.isNotEmpty() }?.let { Text(it, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp)) }
                }
            } else if (!s.online) {
                Card {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                        Text("离线：在这台机器上打开 still.fail 就会重新连上", fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center)
                        RetryPill(Modifier.padding(top = 6.dp))
                    }
                }
            }
            val overview = s.overview
            if (overview != null) {
                SectionHeader("Profile", start = 24.dp)
                ListCard {
                    if (overview.profiles.isEmpty()) ListRow { Text("这台机器还没有 Profile。", fontSize = 15.sp, color = C.muted) }
                    overview.profiles.forEach { ProfileRow(address, it) }
                    if (s.online) ListRow(onClick = { app.push(Screen.NewProfile(address)) }) { Text("＋ 添加 Profile", fontSize = 15.sp, color = C.accent) }
                }
                // The machine's own logins not used yet: each one offered as the first ones were.
                if (s.online) MachineLoginOffers(address, overview)
                SectionHeader("连接", start = 24.dp)
                ListCard {
                    overview.connects.forEach { c -> ConnectRow(address, c) }
                    ListRow {
                        Mark(14.dp)
                        Text("still.fail 对话", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                        Text("内置", fontSize = 13.sp, color = C.muted)
                    }
                    // A connect runs a profile's model: with none, its page says to add one first.
                    if (s.online) ListRow(onClick = { openNewConnect(app, address) }) {
                        Column(Modifier.weight(1f)) {
                            Text("＋ 添加连接", fontSize = 15.sp, color = C.accent)
                            if (overview.profiles.isEmpty()) Text("连接要用 Profile 来跑模型，先添加一个 Profile", fontSize = 13.sp, color = C.muted)
                        }
                    }
                }
                // Slack apps made here and not connected yet: to be finished any time.
                WaitingApps(address, overview, s.online)
                // The agents' memory on this machine, and its software's versions (none from a station older than them).
                SectionHeader("记忆", start = 24.dp)
                ListCard {
                    ListRow(onClick = { app.push(Screen.Memory(address)) }) {
                        IconIn(Icons.Brain, 18.dp, C.muted)
                        Column(Modifier.weight(1f)) {
                            Text("agent 的记忆", fontSize = 15.sp, color = C.ink)
                            Text("全局记忆和每个项目的记忆，由 agent 自己维护", fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
                if (s.online) Versions(address, overview.updates, manager)
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}



/**
 * This device's connection to a station: how it goes (and packets lost, when some were) over its round trip on the
 * left; on the right, ↑ over ↓, the speed each way and what went that way since it opened, each in a column of its own.
 * Grey, but for what the core says is off. Every line is one line, the figures in fixed-width digits with room kept for
 * them: nothing wraps or moves as the figures change.
 */
@Composable
internal fun NetLine(net: StationNet, modifier: Modifier = Modifier) {
    val c = C
    val tone = { f: NetFigure -> when (f.level) { "red" -> c.red; "amber" -> c.warn; else -> c.ink } }
    val figure = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum")
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(net.path, Modifier.weight(1f, fill = false), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                net.loss?.let { Text(it.text, style = figure, color = tone(it), maxLines = 1) }
            }
            net.rtt?.let { rtt ->
                Row {
                    Text("延时 ", fontSize = 13.sp, color = C.muted, maxLines = 1)
                    Text(rtt.text, style = figure, color = tone(rtt), maxLines = 1)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            listOf(Triple("↑", net.up, net.upTotal), Triple("↓", net.down, net.downTotal)).forEach { (arrow, rate, total) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(arrow, fontSize = 13.sp, color = C.muted)
                    Text(rate, Modifier.padding(start = 6.dp).width(72.dp), style = figure, color = C.ink, maxLines = 1)
                    total?.let { Text("共 $it", Modifier.width(64.dp), fontSize = 13.sp, fontFeatureSettings = "tnum", color = C.muted, maxLines = 1) }
                }
            }
        }
    }
}

/**
 * A profile on its station's page: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
@Composable
private fun ProfileRow(station: String, p: Profile) {
    val app = LocalApp.current
    val trouble = quotaTrouble(p.quota)
    ListRow(onClick = { app.push(Screen.Profile(station, p.id)) }) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PresenceDot(toneDot(p.checkTone))
                Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(listOf(p.checkText, if (p.machine == true) "本机登录" else ACCESS_LABEL[p.access.kind] ?: p.access.kind, p.modelsText).joinToString(" · "),
                fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            trouble?.let { Text(it, fontSize = 13.sp, color = C.muted) }
        }
        QuotaRings(p.quota)
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/** A check's tone as a presence dot: green up, red failing, the rest on its way or unknown. */
internal fun toneDot(tone: String): String = when (tone) { "green" -> "online"; "red" -> "error"; "neutral" -> "offline"; else -> "busy" }
