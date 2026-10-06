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
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.ui.draw.alpha
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
import fail.still.android.data.t
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
        TopBack(t("android-settings.title"), app::pop, trailing = if (list != null && list.isNotEmpty() && isManager(current)) ({ NavButton(Icons.Plus, { openAddStation(app, current, list.map { it.id }) }, 20.dp) }) else null)
        // No station yet: adding the first one is the page.
        if (list != null && list.isEmpty()) { FirstStation(current); return@Column }
        LargeTitle(if (list != null) t("android-settings.stations.online", "name" to ws.name, "online" to list.count { it.online }, "total" to list.size) else ws.name, "Station")
        if (list == null) {
            Text(stations.error?.message ?: t("android-settings.stations.reading"), color = C.muted, fontSize = 14.sp, modifier = Modifier.padding(20.dp))
        } else {
            list.forEach { s ->
                Card(onClick = { app.push(Screen.Station(s.station)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Buddy(s)
                        Column(Modifier.weight(1f)) {
                            // Line heights set: a line in Chinese is otherwise a little taller than one in Latin.
                            Text(s.name, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(s.summary, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        if (s.reconnecting == true) Reconnecting()
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                    StationBody(s)
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** Laid out unseen while a station has no network to show, so that its card keeps the room (its path in Chinese, as tall as a real one). */
private val noNet = StationNet(path = "直连", rtt = NetFigure("0 ms", "ok"), rttHistory = emptyList(), down = " ", up = " ", total = "")

/**
 * Under a station's name in the list: what of its load runs low (as the web's cards: none while all is well) and its network, in the same room whatever state it is in —
 * online, offline, or not yet read — so no card grows, shrinks or pushes the ones below it as states change.
 * Offline, a small picture of it asleep and a line saying so are there; not read yet, grey bars where the figures go.
 */
@Composable
private fun StationBody(s: StationView) {
    val host = s.host?.takeIf { s.online }
    val net = s.net?.takeIf { s.online }
    Box(Modifier.fillMaxWidth().padding(top = 10.dp)) {
        // Reconnecting: the figures as last heard, faded.
        Column(Modifier.fillMaxWidth().alpha(if (s.reconnecting == true) 0.45f else 1f)) {
            Box(Modifier.height(20.dp).alpha(if (host != null) 1f else 0f)) { MeterChips(host?.meters.orEmpty(), alerts = true) }
            NetLine(net ?: noNet, Modifier.padding(top = 10.dp).alpha(if (net != null) 1f else 0f))
        }
        if (!s.online) {
            Row(Modifier.matchParentSize(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Image(painterResource(if (C.dark) R.drawable.illus_station_offline_dark else R.drawable.illus_station_offline), null, Modifier.fillMaxHeight())
                Text(t("android-settings.stations.silent", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        } else {
            if (host == null) Row(Modifier.height(20.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) { listOf(46, 52, 50).forEach { Bar(it.dp, 20.dp, 6.dp) } }
            if (net == null) Row(Modifier.matchParentSize().padding(top = 30.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) { Bar(34.dp); Bar(96.dp) }
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) { Bar(132.dp); Bar(132.dp) }
            }
        }
    }
}

/**
 * An online station's machine on its page: its load, what it is, its memory and disk in figures, its network, its agents' processes, each in its room
 * whether known yet or not (grey bars until it is); reconnecting, as last heard, faded.
 */
@Composable
private fun StationFigures(s: StationView) {
    val host = s.host
    val net = s.net
    val processes = s.overview?.processesText?.takeIf { it.isNotEmpty() }
    Column(Modifier.alpha(if (s.reconnecting == true) 0.45f else 1f)) {
        Box(Modifier.padding(vertical = 4.dp).height(20.dp)) {
            if (host != null) MeterChips(host.meters)
            else Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { listOf(46, 52, 50).forEach { Bar(it.dp, 20.dp, 6.dp) } }
        }
        Line(host?.line, 180.dp, Modifier.padding(top = 8.dp))
        Line(host?.usage, 220.dp, Modifier.padding(top = 4.dp))
        Box(Modifier.padding(top = 6.dp)) {
            NetLine(net ?: noNet, Modifier.alpha(if (net != null) 1f else 0f))
            if (net == null) Row(Modifier.matchParentSize(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) { Bar(34.dp); Bar(96.dp) }
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) { Bar(132.dp); Bar(132.dp) }
            }
        }
        Line(processes, 120.dp, Modifier.padding(top = 4.dp))
    }
}

/** A grey line of text, one line however long; a grey bar `bar` wide in its room while it is not known. */
@Composable
private fun Line(text: String?, bar: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) = Box(modifier, contentAlignment = Alignment.CenterStart) {
    // Its room, as tall as a line in Chinese (a line in Latin is a little shorter), whatever it says.
    Text("直连", fontSize = 13.sp, lineHeight = 18.sp, maxLines = 1, modifier = Modifier.alpha(0f))
    if (text != null) Text(text, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) else Bar(bar)
}

/** The station is up but not reached just now: what shows of it is from before. */
@Composable
private fun Reconnecting() = Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
    Spinner(11.dp)
    Text(t("android-settings.stations.reconnecting"), fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1)
}

/** A grey bar where a figure would be, not known now. */
@Composable
private fun Bar(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp = 10.dp, radius: androidx.compose.ui.unit.Dp = 5.dp) =
    Box(Modifier.width(width).height(height).clip(RoundedCornerShape(radius)).background(C.line.copy(alpha = 0.7f)))

@Composable
fun StationScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    val shared by rememberTopic<fail.still.android.data.AdbShareView>(app.core, Topics.adbShare)
    Column(Modifier.fillMaxSize()) {
        val manager = isManager(current)
        NavBar("Station", app::pop, s?.name ?: stationName(address), sub = s?.let { st ->
            // As tall either way: the title does not move as the station comes and goes.
            { Box(Modifier.height(16.dp), contentAlignment = Alignment.CenterStart) { if (st.reconnecting == true) Reconnecting() else Text(st.line.orEmpty(), fontSize = 11.sp, color = C.muted, maxLines = 1) } }
        }, trailing = if (s != null && manager) ({ NavButton(Icons.More, { openStationMenu(app, current, s) }) }) else null)
        if (s == null) return Loading(stations.error?.message ?: t("android-settings.reading"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            // Every part keeps its room as what it shows comes and goes (not read yet: grey bars); only being online or
            // offline changes what the page is.
            if (s.online) Card { StationFigures(s) }
            else Card {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                    Text(t("android-settings.stations.offline", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center)
                    RetryPill(Modifier.padding(top = 6.dp))
                }
            }
            val overview = s.overview
            // What runs on it is in settings' lists, every station's together; here, how much of it there is (once read).
            SectionHeader(t("android-settings.stations.onIt"), start = 24.dp)
            ListCard {
                GoRow(t("android-settings.connects.title"), overview?.let { t("android-settings.count", "n" to it.connects.size) }) { app.push(Screen.Connects(address)) }
                GoRow("Profile", overview?.let { t("android-settings.count", "n" to it.profiles.size) }) { app.push(Screen.Profiles(address)) }
                GoRow(t("android-settings.memory")) { app.push(Screen.Memory(address)) }
                // This phone's adb, lent to its agents (AdbShare.kt).
                GoRow(t("android-misc.adb.title"), if (shared.value?.let { it.sharing && it.station == address } == true) t("android-misc.adb.sharing") else null) { app.push(Screen.AdbShare(address)) }
            }
            if (s.online && overview != null) Versions(address, overview.updates, manager, beta = s.betaOffered == true)
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
                    Text(t("android-settings.stations.rtt"), Modifier.alignByBaseline(), fontSize = 13.sp, color = C.muted, maxLines = 1)
                    Text(rtt.text, Modifier.alignByBaseline(), style = figure, color = tone(rtt), maxLines = 1)
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            listOf(Triple("↑", net.up, net.upTotal), Triple("↓", net.down, net.downTotal)).forEach { (arrow, rate, total) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(arrow, fontSize = 13.sp, color = C.muted)
                    Text(rate, Modifier.padding(start = 5.dp).width(68.dp), style = figure, color = C.ink, maxLines = 1)
                    total?.let { Text(t("android-settings.stations.total", "total" to it), Modifier.widthIn(min = 60.dp), style = figure.copy(fontWeight = FontWeight.Normal), color = C.muted, maxLines = 1) }
                }
            }
        }
    }
}

/** A check's tone as a presence dot: green up, red failing, the rest on its way or unknown. */
internal fun toneDot(tone: String): String = when (tone) { "green" -> "online"; "red" -> "error"; "neutral" -> "offline"; else -> "busy" }
