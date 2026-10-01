// The workspace's stations: each with the buddy's face for its state and its
// load as rings; one station's page is the machine (its load, network,
// versions), with how many connects and profiles run on it (settings' lists
// have them, SettingsHome.kt).
package fail.still.android.screens

import fail.still.android.BuildConfig
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
import fail.still.android.data.StationView
import fail.still.android.data.StationNet
import fail.still.android.data.NetFigure
import fail.still.android.data.NetMeasured
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
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
import fail.still.android.ui.Loading
import fail.still.android.ui.NavBack
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.MeterChips
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

/** Back, at the top of a large-title page; `trailing`, an action at its other end (a ＋). */
@Composable
fun TopBack(label: String, onBack: () -> Unit, trailing: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 10.dp, end = 10.dp, top = 6.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        NavBack(label, onBack)
        trailing?.invoke()
    }
}

@Composable
fun StationsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(ws.id))
    val list = stations.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("设置", app::pop, trailing = if (list != null && list.isNotEmpty() && isManager(current)) ({ NavButton(Icons.Plus, { openAddStation(app, current, list.map { it.id }) }, 20.dp) }) else null)
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
                        MeterChips(host.meters, Modifier.padding(top = 10.dp))
                        s.net?.let { NetLine(it, Modifier.padding(top = 10.dp)) }
                    } else if (!s.online) {
                        Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                            Text("这台机器很久没联系 ${BuildConfig.APP_NAME} 了", fontSize = 13.sp, color = C.muted)
                        }
                    }
                }
            }
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
                    MeterChips(host.meters, Modifier.padding(vertical = 4.dp))
                    Text(host.line, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp))
                    s.net?.let { NetLine(it, Modifier.padding(top = 6.dp)) }
                    s.net?.let { Ways(address, it.measured, Modifier.padding(top = 6.dp)) }
                    s.overview?.processesText?.takeIf { it.isNotEmpty() }?.let { Text(it, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp)) }
                }
            } else if (!s.online) {
                Card {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                        Text("离线：在这台机器上打开 ${BuildConfig.APP_NAME} 就会重新连上", fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center)
                        RetryPill(Modifier.padding(top = 6.dp))
                    }
                }
            }
            val overview = s.overview
            if (overview != null) {
                // What runs on it is in settings' lists, every station's together; here, how much of it there is.
                SectionHeader("在这台上", start = 24.dp)
                ListCard {
                    GoRow("连接", "${overview.connects.size} 个") { app.push(Screen.Connects(address)) }
                    GoRow("Profile", "${overview.profiles.size} 个") { app.push(Screen.Profiles(address)) }
                    GoRow("记忆") { app.push(Screen.Memory(address)) }
                    // A station older than the footprint page has no line of it.
                    val usage = overview.footprint
                    if (s.online && usage != null) GoRow("占用", usage.text) { app.push(Screen.Footprint(address)) }
                }
                if (s.online) Versions(address, overview.updates, manager, beta = s.betaOffered == true)
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
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(net.path, Modifier.alignByBaseline(), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                net.loss?.let { Text(it.text, Modifier.alignByBaseline().weight(1f, fill = false), style = figure, color = tone(it), maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            net.rtt?.let { rtt ->
                Row {
                    Text("当前延时 ", Modifier.alignByBaseline(), fontSize = 13.sp, color = C.muted, maxLines = 1)
                    Text(rtt.text, Modifier.alignByBaseline(), style = figure, color = tone(rtt), maxLines = 1)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            listOf(Triple("↑", net.up, net.upTotal), Triple("↓", net.down, net.downTotal)).forEach { (arrow, rate, total) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(arrow, fontSize = 13.sp, color = C.muted)
                    Text(rate, Modifier.padding(start = 5.dp).width(68.dp), style = figure, color = C.ink, maxLines = 1)
                    total?.let { Text("共 $it", Modifier.width(60.dp), style = figure.copy(fontWeight = FontWeight.Normal), color = C.muted, maxLines = 1) }
                }
            }
        }
    }
}

/**
 * The round trip to a station through each relay as last measured, the one it goes through now underlined, and
 * 重新测量: the core moves the connection to one clearly quicker (`station.measure`; web/src/cloud/StationCards.tsx Ways).
 */
@Composable
internal fun Ways(station: String, measured: NetMeasured?, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val c = C
    val measuring = app.isDoing("station.measure", "station" to station) || measured?.measuring == true
    val tone = { f: NetFigure -> when (f.level) { "red" -> c.red; "amber" -> c.warn; else -> c.ink } }
    val said = buildAnnotatedString {
        if (measured == null) append("各中继还没测过")
        if (measured != null) append("${measured.whenText ?: "上次检测"}  ")
        measured?.relays?.forEachIndexed { i, r ->
            if (i > 0) append("   ")
            withStyle(SpanStyle(textDecoration = if (r.current) TextDecoration.Underline else null)) { append(r.name) }
            append(" ")
            val rtt = r.rtt
            withStyle(SpanStyle(fontWeight = FontWeight.Medium, color = if (rtt == null) c.red else tone(rtt))) { append(rtt?.text ?: "未测通") }
        }
        measured?.moved?.let { append("   已换到$it") }
    }
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(said, Modifier.weight(1f), fontSize = 12.sp, color = C.muted, style = TextStyle(fontFeatureSettings = "tnum"))
        Row(
            Modifier.height(22.dp).clip(RoundedCornerShape(50)).background(C.chip).clickable(enabled = !measuring) {
                app.act("重新测量") { app.core.call("station.measure", buildJsonObject { put("station", station) }) }
            }.padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            if (measuring) Spinner(10.dp)
            Text(if (measuring) "正在测量" else "重新测量", color = if (measuring) C.muted else C.ink, fontSize = 12.sp)
        }
    }
}

/** A check's tone as a presence dot: green up, red failing, the rest on its way or unknown. */
internal fun toneDot(tone: String): String = when (tone) { "green" -> "online"; "red" -> "error"; "neutral" -> "offline"; else -> "busy" }
