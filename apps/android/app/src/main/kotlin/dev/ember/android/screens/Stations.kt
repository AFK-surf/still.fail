// The workspace's stations: each with the buddy's face for its state and its
// load as rings; one station's profiles (which models may be used) and
// connections.
package dev.ember.android.screens

import androidx.compose.foundation.Image
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
import dev.ember.android.LocalApp
import dev.ember.android.R
import dev.ember.android.Screen
import dev.ember.android.data.Profile
import dev.ember.android.ui.QuotaRings
import dev.ember.android.data.available
import dev.ember.android.data.StationView
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.C
import dev.ember.android.ui.Card
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.Illustration
import dev.ember.android.ui.LargeTitle
import dev.ember.android.ui.ListCard
import dev.ember.android.ui.ListRow
import dev.ember.android.ui.Loading
import dev.ember.android.ui.Mark
import dev.ember.android.ui.NavBack
import dev.ember.android.ui.NavBar
import dev.ember.android.ui.NavButton
import dev.ember.android.ui.Ring
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.SlackMark
import dev.ember.core.CoreException
import kotlinx.coroutines.launch

/** The buddy's face for a station: at work, idle, or asleep. */
@Composable
private fun Buddy(s: StationView, size: Int = 40) {
    val dark = C.dark
    val face = when {
        !s.online -> if (dark) R.drawable.buddy_offline_dark else R.drawable.buddy_offline
        (s.overview?.counts?.running ?: 0) > 0 -> if (dark) R.drawable.buddy_working_dark else R.drawable.buddy_working
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
                    } else if (!s.online) {
                        Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                            Text("这台机器很久没联系 ember 了", fontSize = 13.sp, color = C.muted)
                        }
                    }
                }
            }
        }
        ListCard {
            ListRow(onClick = { app.push(Screen.Connects) }) {
                Text("连接", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                Text("Slack app 和它们绑定的模型", fontSize = 13.sp, color = C.muted)
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
            if (list != null && isManager(current)) ListRow(onClick = { openAddStation(app, current, list.map { it.id }) }) { Text("＋ 添加 station", fontSize = 15.sp, color = C.accent) }
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
            { Text(st.host?.cpuModel?.ifEmpty { null } ?: if (st.online) "在线" else "离线", fontSize = 11.sp, color = C.muted, maxLines = 1) }
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
                    s.overview?.processesText?.takeIf { it.isNotEmpty() }?.let { Text(it, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp)) }
                }
            } else if (!s.online) {
                Card {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                        Text("离线：在这台机器上打开 ember 就会重新连上", fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center)
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
                SectionHeader("连接", start = 24.dp)
                ListCard {
                    overview.connects.forEach { c ->
                        ListRow(onClick = { app.push(Screen.Connect(address, c.id)) }) {
                            if (c.kind == "slack") SlackMark(14.dp) else Mark(14.dp)
                            Text(c.name, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                            Text(connectionText(c.connection.state), fontSize = 13.sp, color = C.muted)
                        }
                    }
                    ListRow {
                        Mark(14.dp)
                        Text("ember 对话", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                        Text("内置", fontSize = 13.sp, color = C.muted)
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

private fun connectionText(state: String) = when (state) {
    "connected" -> "在线"; "reconnecting" -> "重连中"; "starting" -> "连接中"; "error" -> "连接失败"; "no_tokens" -> "未连接 Slack"; else -> "已停用"
}


/** A profile on its station's page: its allowance and how many of its models are enabled; its page picks them. */
@Composable
private fun ProfileRow(station: String, p: Profile) {
    val app = LocalApp.current
    ListRow(onClick = { app.push(Screen.Profile(station, p.id)) }) {
        Column(Modifier.weight(1f)) {
            Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(p.modelsText, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        QuotaRings(p.quota)
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

