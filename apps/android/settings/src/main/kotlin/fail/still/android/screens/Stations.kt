// The workspace's stations: each with its mark and what it is doing, and its
// load as rings; one station's page is the machine (its load, network,
// versions), with how many connects and profiles run on it (settings' lists
// have them, SettingsHome.kt).
package fail.still.android.screens

import fail.still.android.ui.Spinner
import androidx.compose.foundation.border
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import fail.still.android.AppState
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.shared.BuildConfig
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.asPaddingValues
import fail.still.android.ui.LazyColumn
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
import androidx.compose.foundation.layout.wrapContentSize
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
import androidx.compose.ui.unit.Dp
import androidx.compose.foundation.Canvas
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.shared.R
import fail.still.android.Screen
import fail.still.android.data.StationView
import fail.still.android.data.EnvVar
import fail.still.android.data.AgentEnvDraft
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import fail.still.android.ui.Smooth
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.CodeFont
import fail.still.android.ui.Button
import fail.still.android.ui.DoingMark
import fail.still.android.data.MembershipsView
import fail.still.android.data.StationNet
import fail.still.android.data.NetFigure
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.StationMark
import fail.still.android.ui.hasStationMark
import fail.still.android.ui.AgentStateMark
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.ModelMark
import fail.still.android.data.ChatState
import fail.still.android.data.Maker
import androidx.compose.foundation.layout.offset
import fail.still.android.ui.Icons
import fail.still.android.ui.Illustration
import fail.still.android.ui.ListCard
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.ListRow
import fail.still.android.ui.Waiting
import fail.still.android.ui.WaitShape
import fail.still.android.ui.breathing
import fail.still.android.ui.rememberBreath
import fail.still.android.ui.NavBack
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.MeterChips
import fail.still.android.ui.MeterDials
import fail.still.android.ui.HostDetails
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SlackMark
import fail.still.android.data.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import fail.still.android.ui.stationName

/** Where a station this workspace joined is at home (docs/multi-workspace.md), as grey words before what is said of it; null for one at home here. */
internal fun joinedMark(s: StationView): String? =
    if (s.joined != true) null else s.home?.let { t("web-pages.stations.joinedFrom", "name" to it) } ?: t("web-pages.stations.joinedElsewhere")

/** Back, at the top of a large-title page (settings' own); `trailing`, an action at its other end (a ＋). */
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

/** The room a place's top page keeps at its foot for the bottom bar (none elsewhere). */
@Composable
fun BarRoom() = Spacer(Modifier.height(fail.still.android.LocalBarRoom.current))

@Composable
fun StationsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(ws.id))
    val list = stations.value
    val manager = managerOf(current)
    // Adding a station: the workspace's owners and admins.
    val add = if (list != null && manager == true) fail.still.android.ui.BarAction("add-station", t("android-misc.bar.action.stations"), Icons.Plus) { openAddStation(app, current, list.map { it.id }) } else null
    PlacePage(current, "stations", add, known = (list != null || stations.error != null) && manager != null) { top ->
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = top)) {
        // No station yet: adding the first one is the page.
        if (list != null && list.isEmpty()) { FirstStation(current); BarRoom(); return@Column }
        if (list == null) {
            Waiting(WaitShape.Cards, text = t("common.readingStations"), error = stations.error?.message)
        } else {
            list.forEach { s ->
                Card(onClick = { app.push(Screen.Station(s.station)) }) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        // Its own mark leads, the server's where it has none (what it is doing is said under its name).
                        // In a box as large whatever it is: an emoji is drawn wider than an icon, and the names line up.
                        Box(Modifier.size(MARK_SIZE), contentAlignment = Alignment.Center) {
                            StationMark(s.emoji, s.icon, MARK_SIZE, C.ink, Modifier.wrapContentSize(unbounded = true), none = Icons.Server)
                        }
                        Column(Modifier.weight(1f)) {
                            // Line heights set: a line in Chinese is otherwise a little taller than one in Latin.
                            Text(s.name, fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            // A station this workspace joined: where it is at home first (the line is cut short at its end).
                            Text(listOfNotNull(joinedMark(s), s.summary.takeIf { it.isNotEmpty() }).joinToString(" · "), fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        if (s.reconnecting == true) Reconnecting()
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                    StationBody(s)
                }
            }
        }
        Spacer(Modifier.height(30.dp))
        BarRoom()
    }
    }
}

/** A station's mark at the head of its card in the list. */
private val MARK_SIZE = 28.dp

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
    val net = rememberStationNet(s.station.takeIf { s.online })
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
 * An online station's machine on its page, as the web's MachineDetails (web/src/cloud/StationCards.tsx): what it is,
 * what is left of it large, its network, the rest a row each, its agents' processes; in its room whether known yet or
 * not (grey bars until it is); reconnecting, as last heard, faded. `peek` (a chat's station card): what it is, what is
 * left of it in the allowance's boxes and its network, the rest on its page.
 */
@Composable
private fun StationFigures(s: StationView, peek: Boolean = false) {
    val host = s.host
    val net = rememberStationNet(s.station)
    val running = s.overview?.processesText?.takeIf { it.isNotEmpty() }
    Column(Modifier.alpha(if (s.reconnecting == true) 0.45f else 1f)) {
        // What it is: on its page, under the page's title; in a chat's card, in the line above.
        if (peek) Box(Modifier.padding(vertical = 4.dp).height(20.dp)) {
            if (host != null) MeterChips(host.meters)
            else Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { listOf(46, 52, 50).forEach { Bar(it.dp, 20.dp, 6.dp) } }
        }
        // Not read yet: laid out unseen as when it is, grey bars over it, so nothing below moves as it comes.
        else Box(Modifier.padding(top = 4.dp)) {
            MeterDials((host ?: unreadHost).meters, Modifier.alpha(if (host != null) 1f else 0f))
            if (host == null) Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.spacedBy(16.dp)) { repeat(3) { Bar(90.dp, 76.dp, 6.dp) } }
        }
        Box(Modifier.padding(top = if (peek) 6.dp else 14.dp)) {
            NetLine(net ?: noNet, Modifier.alpha(if (net != null) 1f else 0f))
            if (net == null) Row(Modifier.matchParentSize(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) { Bar(34.dp); Bar(96.dp) }
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) { Bar(132.dp); Bar(132.dp) }
            }
        }
        if (!peek) {
            Box(Modifier.padding(top = 16.dp)) {
                HostDetails((host ?: unreadHost).details, Modifier.alpha(if (host != null) 1f else 0f))
                if (host == null) Column(Modifier.matchParentSize(), verticalArrangement = Arrangement.SpaceEvenly) { repeat(4) { Bar(180.dp) } }
            }
            Line(running, 120.dp, Modifier.padding(top = 8.dp))
        }
    }
}

/** This device's connection to a station with its figures (null: none, or `station` null), followed only where they are
 *  drawn: the core samples it while it is. */
@Composable
private fun rememberStationNet(station: String?): StationNet? {
    val app = LocalApp.current
    val net by rememberTopic<StationNet?>(app.core, station?.let { Topics.stationNet(it) })
    return net.value
}

/** What a machine not read yet is laid out as, unseen: its figures and rows as tall as a real one's (their words in Chinese). */
private val unreadHost = fail.still.android.data.Host(
    hostname = "", os = "", arch = "", cpus = 0, cpuModel = "", load = 0.0, uptimeSec = 0.0,
    memory = fail.still.android.data.Memory(0, 0), disk = fail.still.android.data.Disk("", 0, 0), emberRssBytes = 0, checkedAt = 0,
    summary = "", line = "", facts = emptyList(), usage = "", emberText = "", identity = "",
    meters = List(3) { fail.still.android.data.Meter(label = "$it", short = "", percent = 0, left = 0, level = "ok", value = "", remaining = "", big = "0", unit = "%", title = "内存剩", total = "共 0 GB") },
    details = List(4) { fail.still.android.data.HostDetail("主机名", "直连") },
)

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
    Spinner(inline = true)
    Text(t("common.reconnecting"), fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1)
}

/** A grey bar where a figure would be, not known now: breathing as every wait's shapes (Waiting.kt). */
@Composable
private fun Bar(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp = 10.dp, radius: androidx.compose.ui.unit.Dp = 5.dp) =
    Box(Modifier.width(width).height(height).breathing(rememberBreath()).clip(Smooth(radius)).background(C.bubble))

@Composable
fun StationScreen(current: WorkspaceEntry, address: String, login: String? = null) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    val shared by rememberTopic<fail.still.android.data.AdbShareView>(app.core, Topics.adbShare)
    Column(Modifier.fillMaxSize()) {
        val manager = isManager(current)
        NavBar("Station", app::pop, s?.name ?: stationName(address), sub = s?.let { st ->
            // As tall either way: the title does not move as the station comes and goes.
            { Box(Modifier.height(16.dp), contentAlignment = Alignment.CenterStart) { if (st.reconnecting == true) Reconnecting() else Text(listOfNotNull(joinedMark(st), (st.host?.identity ?: st.line)?.takeIf { it.isNotEmpty() }).joinToString(" · "), fontSize = 11.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) } }
        }, trailing = if (s != null && manager) ({ NavButton(Icons.More, { openStationMenu(app, current, s) }) }) else null)
        if (s == null) return Waiting(WaitShape.Cards, error = stations.error?.message)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            // Every part keeps its room as what it shows comes and goes (not read yet: grey bars); only being online or
            // offline changes what the page is.
            if (s.online) Card { StationFigures(s) }
            else Card {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 220.dp)
                    Text(t("android-settings.stations.offline", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center)
                    RetryPill(Modifier.padding(top = 6.dp), retrying = s.link.retrying == true)
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
                // The folders it lends its members (docs/drive.md); none offered by a station from before the drive.
                overview?.drive?.let { drive -> GoRow(t("android-misc.drive.title"), fail.still.android.data.driveValue(drive.roots)) { app.push(Screen.Drive(address, null, "")) } }
            }
            StationScreens(address)
            // What macOS lets a Mac station's helper do (StationPermissions.kt); nothing from another or an older one.
            if (s.online) overview?.permissions?.let { StationPermissionsSection(address, s.name, it) }
            // The logins its agents did there (LoginCards.kt): those under way as their cards; nothing when none.
            StationLogins(address, marked = login)
            // The variables what it starts for its agents runs with (docs/agent-env.md); none from a station from before them.
            overview?.agentEnv?.let { StationAgentEnv(address, it, manager) }
            // What its search finds of the machine (docs/search.md): the person's own data only where its managers say.
            if (s.online) overview?.search?.takeIf { it.files == "spotlight" }?.let { StationSearchSection(address, it.personal, manager) }
            if (manager) StationWorkspaces(address)
            // Its updates are its home workspace's managers' (docs/multi-workspace.md).
            if (s.online && overview != null) Versions(address, overview.updates, manager, beta = s.betaOffered == true)
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** Whether the station's search finds the machine's person's own mail, messages and the like (web StationSearch.tsx). */
@Composable
private fun StationSearchSection(address: String, personal: Boolean, manager: Boolean) {
    val app = LocalApp.current
    val busy = app.isDoing("search.setPersonal", "station" to address)
    SectionHeader(t("web-pages.stations.search.section"), start = 24.dp)
    ListCard {
        ListRow(onClick = if (!manager || busy) null else ({
            app.act(t("web-pages.stations.search.what")) {
                app.core.call("search.setPersonal", buildJsonObject { put("station", address); put("personal", !personal) })
            }
        })) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(t("web-pages.stations.search.personal"), color = C.ink, fontSize = 15.sp)
                Text(t("web-pages.stations.search.personalLine"), color = C.muted, fontSize = 13.sp)
            }
            Switch(personal)
        }
    }
}

/**
 * The station's screens a person can see and drive (docs/remote-screens.md: its display, its browser's tabs), a row
 * each opening the viewer (remote/ScreenActivity.kt); a station from before them, or none to show, says why in a quiet
 * row. Nothing while the station has not said which it has.
 */
@Composable
private fun StationScreens(address: String) {
    val app = LocalApp.current
    val topic by rememberTopic<fail.still.android.data.ScreensView>(app.core, Topics.screens(address))
    val view = topic.value ?: return
    val why = view.note ?: if (view.outdated) t("android-misc.screen.outdatedRow") else null
    if (view.screens.isEmpty() && why == null) return
    SectionHeader(t("android-misc.screen.section"), start = 24.dp)
    ListCard {
        view.screens.forEach { screen ->
            ListRow(onClick = { app.openScreen(address, screen.id, screen.title) }) {
                IconIn(if (screen.kind == "browser") Icons.Web else Icons.Monitor, 18.dp, C.muted)
                Column(Modifier.weight(1f)) {
                    Text(screen.title, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    // A grant missing (its line says which): the one thing on the row in colour.
                    Text(screen.line, fontSize = 13.sp, lineHeight = 18.sp, color = if (screen.access != null) C.warnInk else C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
        if (view.screens.isEmpty() && why != null) ListRow {
            Text(why, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, modifier = Modifier.weight(1f))
        }
    }
}

/**
 * The workspaces a station is in, a row each (its name, and what it has of the machine: 主 workspace, or the folders
 * opened to it), on its page in its home workspace for that one's owners and admins; only once it is in more than one
 * (as the narrow web's).
 */
@Composable
private fun StationWorkspaces(address: String) {
    val app = LocalApp.current
    val topic by rememberTopic<MembershipsView>(app.core, Topics.memberships(address))
    val view = topic.value ?: return
    if (!view.manages || view.workspaces.size < 2) return
    SectionHeader("Workspace", start = 24.dp)
    ListCard {
        view.workspaces.forEach { w ->
            ListRow {
                Text(w.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(w.line, fontSize = 14.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 220.dp))
            }
        }
    }
}

/**
 * The variables everything the station starts for its agents runs with (docs/agent-env.md: a proxy, mostly), a row each,
 * a secret's value masked; its managers edit them in a sheet (Profiles.kt's, as a custom profile's).
 */
@Composable
private fun StationAgentEnv(address: String, env: List<EnvVar>, manager: Boolean) {
    val app = LocalApp.current
    if (env.isEmpty() && !manager) return
    SectionHeader(t("android-settings.agentEnv.title"), start = 24.dp)
    ListCard {
        if (env.isEmpty()) ListRow { Text(t("android-settings.agentEnv.empty"), fontSize = 15.sp, color = C.muted, modifier = Modifier.weight(1f)) }
        env.forEach { e ->
            ListRow {
                Column(Modifier.weight(1f)) {
                    Text(e.key, fontSize = 15.sp, color = C.ink, fontFamily = CodeFont)
                    Text(e.value, fontSize = 13.sp, color = C.muted, fontFamily = CodeFont, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        if (manager) {
            ListRow(onClick = { app.sheet = SheetSpec(0.85f, draggable = true) { AgentEnvSheet(address) } }) {
                Text(t("android-settings.env.edit"), fontSize = 15.sp, color = C.link, modifier = Modifier.weight(1f))
                // Saved (the sheet gone): a spinner until the station has them.
                DoingMark(app.isDoing("agentEnv.form.save", "station" to address), app.failedOf("agentEnv.form.save", "station" to address))
            }
        }
    }
}

/**
 * The station's variables as a .env file's lines (web AgentEnvText.tsx), in the core's draft (agentEnvForm): coloured as
 * the core reads them, a line it cannot take in red and what is wrong said under the field; saved whole, the sheet
 * closed at once.
 */
@Composable
private fun ColumnScope.AgentEnvSheet(station: String) {
    val app = LocalApp.current
    val form = remember(station) { java.util.UUID.randomUUID().toString() }
    val topic by rememberTopic<AgentEnvDraft>(app.core, buildJsonObject { put("topic", "agentEnvForm"); put("station", station); put("form", form) })
    suspend fun call(action: String, input: JsonObject = buildJsonObject {}) = app.core.call("agentEnv.form.$action", buildJsonObject { put("station", station); put("form", form); put("input", input) })
    LaunchedEffect(station, form) { app.act(t("web-pages.stations.agentEnvRead")) { call("open") } }
    DisposableEffect(station, form) { onDispose { app.act(t("web-pages.stations.agentEnvClose")) { call("drop") } } }
    val d = topic.value
    // What was typed, until the core has it (the field never waits on it).
    var typed by remember { mutableStateOf<String?>(null) }
    if (typed != null && d?.text == typed) typed = null
    val text = typed ?: d?.text ?: ""
    val read = d?.takeIf { it.text == text }
    val palette = listOf(C.blue, C.ink, C.subtle, C.muted, C.red)
    val colours = remember(read, palette) { read?.let { r -> EnvColours(r, palette) } ?: VisualTransformation.None }
    SheetGrab()
    SheetHead(t("android-settings.agentEnv.title"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(t("android-settings.agentEnv.note"), fontSize = 12.sp, color = C.muted)
        Box(Modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.surface).border(1.dp, C.line, Smooth(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
            if (text.isEmpty()) Text("HTTPS_PROXY=http://127.0.0.1:7890\nNO_PROXY=localhost,.internal", color = C.subtle, fontSize = 13.sp, fontFamily = CodeFont, lineHeight = 20.sp)
            BasicTextField(
                text, { next -> typed = next; app.act(t("web-pages.stations.agentEnvEdit")) { call("edit", buildJsonObject { put("text", next) }) } },
                minLines = 6, cursorBrush = SolidColor(C.accent), visualTransformation = colours,
                textStyle = TextStyle(color = C.ink, fontSize = 13.sp, fontFamily = CodeFont, lineHeight = 20.sp), modifier = Modifier.fillMaxWidth(),
            )
        }
        read?.lines?.forEachIndexed { i, l ->
            l.problem?.let { Text(t("web-pages.stations.agentEnvLine", "line" to i + 1, "problem" to it), fontSize = 12.sp, color = if (l.error) C.red else C.muted) }
        }
        val canSave = d != null && d.dirty && !d.pending && read != null && read.errors == 0u
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(t("common.save"), primary = true, enabled = canSave) {
                app.sheet = null
                app.act(t("web-pages.stations.agentEnvSave"), t("android-settings.saved")) { call("save") }
            }
        }
    }
}

/**
 * The text as the core read it: names, values and comments in their colours, a line it cannot take in red. `palette`:
 * the theme's name, value, comment, other and wrong colours.
 */
private class EnvColours(private val read: AgentEnvDraft, private val palette: List<androidx.compose.ui.graphics.Color>) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val coloured = buildAnnotatedString {
            read.lines.forEachIndexed { i, l ->
                if (i > 0) append("\n")
                l.parts.forEach { p ->
                    val colour = palette[if (l.error) 4 else when (p.kind) { "name" -> 0; "value" -> 1; "comment" -> 2; else -> 3 }]
                    withStyle(SpanStyle(color = colour)) { append(p.text) }
                }
            }
        }
        // The same letters (the core's parts are the line as written): only their colours change.
        return TransformedText(if (coloured.text == text.text) coloured else text, OffsetMapping.Identity)
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

/** A station's card, from a chat's bar: whether it is up and what its agents do, its machine and network, and its page. */
fun openStationPeek(app: AppState, address: String) {
    app.sheet = SheetSpec(0.5f) {
        val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(address.substringBefore('/')))
        val s = stations.value?.firstOrNull { it.station == address }
        SheetGrab()
        SheetHead(s?.name ?: stationName(address), lead = if (s != null && hasStationMark(s.emoji, s.icon)) ({ StationMark(s.emoji, s.icon, 17.dp, C.ink) }) else null)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (s != null) Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(s.summary, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
                // What its agents' processes are is on its page, a tap away.
                if (s.online) StationFigures(s, peek = true)
                else Text(t("android-settings.stations.offline", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
            }
            ListCard {
                // Its files (docs/drive.md), where it has a drive: a way there from where it is named, as the wide screen's card has.
                s?.overview?.drive?.let { drive -> GoRow(t("android-misc.drive.title"), fail.still.android.data.driveValue(drive.roots)) { app.sheet = null; app.push(Screen.Drive(address, null, "")) } }
                GoRow(t("android-chat.station.details")) { app.sheet = null; app.push(Screen.Station(address)) }
            }
        }
    }
}
