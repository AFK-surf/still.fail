// Profiles (as the narrow web's web/src/mobile/Profiles.tsx, from the desktop's pages/Accounts.tsx): every station's in
// one list, a profile's page
// (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its key or
// variables; renaming, checking and deleting under "…"), and a new one.
package fail.still.android.screens

import fail.still.android.BuildConfig
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.border
import androidx.compose.runtime.DisposableEffect
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.JsonObject
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ACCESS_LABEL
import fail.still.android.data.KEYED
import fail.still.android.data.LoginJob
import fail.still.android.data.MachineLogin
import fail.still.android.data.Overview
import fail.still.android.data.ProfileFlowView
import fail.still.android.data.Profile
import fail.still.android.data.ProfilesView
import fail.still.android.data.ShareStation
import fail.still.android.data.Quota
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.data.errorText
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.ProviderMark
import fail.still.android.ui.QuotaDials
import fail.still.android.ui.QuotaRings
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.android.ui.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

private val SIGNING_IN = setOf("starting", "needs_code", "needs_approval", "verifying")

/** A check's tone as a colour (the core's: accent | green | blue | red | neutral). */
@Composable
internal fun toneColor(tone: String): Color = when (tone) { "green" -> C.green; "red" -> C.red; "blue" -> C.blue; "accent" -> C.accent; else -> C.muted }

/** A state as the pages say it: a small dot in its colour, then its words. */
@Composable
internal fun StateDot(color: Color, size: androidx.compose.ui.unit.Dp = 7.dp) = Box(Modifier.size(size).clip(CircleShape).background(color))

/** Why an allowance could not be read (an account its provider refuses, a sign-in gone stale), in the provider's words. */
internal fun quotaTrouble(quota: Quota?): String? = quota?.takeIf { it.state == "blocked" || it.state == "unavailable" }?.detail?.ifBlank { null }

/** The runtime a machine login is of, by name. */
private val MACHINE_RUNTIME = mapOf("claude" to "Claude Code", "codex" to "Codex")

/**
 * Every station's profiles on one page, from settings (SettingsHome.kt), as the narrow web's ProfilesScreen: each station
 * under its name, what can be added there (a profile, the machine's own logins) with it; one offline says so.
 */
@Composable
fun ProfilesScreen(current: WorkspaceEntry, only: String? = null) {
    val app = LocalApp.current
    val topic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    // From a station's page: that station's only, back to it.
    val stations = topic.value?.let { all -> if (only == null) all else all.filter { it.station == only } }
    val one = if (only != null) stations?.firstOrNull() else null
    val online = stations.orEmpty().filter { it.online }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(one?.name ?: t("android-settings.title"), app::pop, trailing = if (online.isNotEmpty()) ({
            NavButton(Icons.Plus, {
                if (online.size == 1) app.push(Screen.NewProfile(online[0].station))
                else openPickStation(app, t("android-settings.profile.add"), online) { app.push(Screen.NewProfile(it.station)) }
            }, 20.dp)
        }) else null)
        LargeTitle(one?.let { t("android-settings.connects.on", "name" to it.name) } ?: "", "Profile")
        PageNote(t("android-settings.profiles.note"))
        // The workspace's: one list, each shared profile once (the core's `profiles`); a station's own: as before.
        if (one == null) WorkspaceList(current.workspace.id)
        if (stations == null) Text(topic.error?.message ?: t("android-settings.stations.reading"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(20.dp))
        else if (one == null) online.forEach { s -> s.overview?.let { MachineLoginOffers(s.station, it) } }
        else stations.forEach { s ->
            if (one == null) SectionHeader(if (s.online) s.name else t("android-settings.connects.offline", "name" to s.name), start = 24.dp)
            val overview = s.overview
            ListCard {
                if (overview == null) ListRow { Text(if (s.online) t("android-settings.reading") else t("android-settings.profiles.stationOffline"), fontSize = 15.sp, color = C.muted) }
                else if (overview.profiles.isEmpty()) ListRow { Text(t("android-settings.profiles.empty"), fontSize = 15.sp, color = C.muted) }
                else overview.profiles.forEach { ProfileRow(s.station, it) }
            }
            // The machine's own logins not used yet, each offered as a profile.
            if (s.online && overview != null) MachineLoginOffers(s.station, overview)
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** The workspace's profiles in one list: a shared one once, where it is under it; one whose subscription's station is
 * away dimmed, said why (as the narrow web's WorkspaceList). */
@Composable
private fun WorkspaceList(scope: String) {
    val app = LocalApp.current
    val topic by rememberTopic<ProfilesView>(app.core, Topics.profiles(scope))
    val view = topic.value ?: return Text(topic.error?.message ?: t("android-settings.reading"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(20.dp))
    ListCard {
        if (view.items.isEmpty()) ListRow { Text(t("android-settings.profiles.empty"), fontSize = 15.sp, color = C.muted) }
        view.items.forEach { e ->
            val p = e.profile
            ListRow(onClick = { app.push(if (e.members.orEmpty().size > 1) Screen.ProfileAccount(e.key) else Screen.Profile(e.station, p.id)) }) {
                Column(Modifier.weight(1f).then(if (e.usable) Modifier else Modifier.alpha(0.55f))) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        PresenceDot(if (e.usable) toneDot(p.checkTone) else "error")
                        Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Text(
                        if (!e.usable) t("web-pages.settings.profiles.hostAway", "station" to e.hostName)
                        else e.where.ifEmpty { listOfNotNull(p.checkText, p.usesText?.ifEmpty { null } ?: ACCESS_LABEL[p.access.kind] ?: p.access.kind).joinToString(" · ") },
                        fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
                if (e.usable) QuotaRings(p.quota)
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
        if (view.loading) ListRow { Text(t("android-settings.reading"), fontSize = 15.sp, color = C.muted) }
    }
}

/** An account on several stations (as the narrow web's ProfileAccountScreen): what they have in common, then each
 * station's part, each leading to its page there. */
@Composable
fun ProfileAccountScreen(current: WorkspaceEntry, key: String) {
    val app = LocalApp.current
    val topic by rememberTopic<ProfilesView>(app.core, Topics.profiles(current.workspace.id))
    val e = topic.value?.items?.firstOrNull { it.key == key }
    if (e == null) return Column(Modifier.fillMaxSize()) {
        NavBar("Profile", app::pop, "Profile")
        Loading(if (topic.value != null) t("android-settings.profile.none") else t("android-settings.reading"))
    }
    val p = e.profile
    Column(Modifier.fillMaxSize()) {
        NavBar("Profile", app::pop, p.name, sub = { Text(listOfNotNull(p.email, if (p.machine == true) t("android-settings.profile.machine") else p.providerName ?: ACCESS_LABEL[p.access.kind] ?: p.access.kind).joinToString(" · "), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            SectionHeader(t("web-pages.profiles.account.common"), start = 24.dp)
            PageNote(t("web-pages.profiles.account.commonLead"))
            ListCard {
                ListRow {
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            PresenceDot(toneDot(p.checkTone))
                            Text(p.checkText, fontSize = 15.sp, color = C.ink)
                        }
                        Text(p.check?.detail ?: t("android-settings.profile.notChecked"), fontSize = 13.sp, color = C.muted)
                    }
                }
            }
            QuotaSection(e.station, p)
            SectionHeader(t("web-pages.profiles.account.each"), start = 24.dp)
            ListCard {
                e.members.orEmpty().forEach { m ->
                    ListRow(onClick = { app.push(Screen.Profile(m.station, m.profileId)) }) {
                        Column(Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                PresenceDot(if (!m.online) "offline" else if (!m.usable) "error" else toneDot(m.checkTone))
                                Text(m.stationName, fontSize = 15.sp, color = C.ink)
                            }
                            Text(if (m.online) m.about else t("android-settings.profiles.stationOffline"), fontSize = 13.sp, color = C.muted)
                        }
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/**
 * Sharing a profile with the workspace's other stations (as the desktop's ShareSection): a switch; once on, where a
 * subscription is signed in (moved from here) and which stations may use it. A copy of another station's says whose.
 */
@Composable
private fun ShareSection(current: WorkspaceEntry, s: StationView, p: Profile) {
    val app = LocalApp.current
    val api = app.api(s.station)
    val topic by rememberTopic<ProfilesView>(app.core, Topics.profiles(current.workspace.id))
    val share = p.share
    val entry = share?.let { sh -> topic.value?.items?.firstOrNull { it.key == sh.id } }
    val stations = entry?.stations.orEmpty()
    val subscription = p.access.kind == "subscription"
    SectionHeader(t("web-pages.profiles.share.title"), start = 24.dp)
    if (share?.role == "user") {
        val host = entry?.hostName ?: share.host.take(8)
        ListCard {
            ListRow(onClick = if (entry?.editable == true) ({ app.push(Screen.Profile(entry.station, entry.profile.id)) }) else null) {
                Column(Modifier.weight(1f)) {
                    Text(t("web-main.memory.share.from", "station" to host), fontSize = 15.sp, color = C.ink)
                    Text(t("web-pages.profiles.share.changeThere"), fontSize = 13.sp, color = C.muted)
                    if (subscription && share.reachable == false) Text(t("web-pages.profiles.share.hostAway", "station" to host), fontSize = 13.sp, color = C.red)
                }
                if (entry?.editable == true) IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
        return
    }
    val shared = share != null
    val allowed = share?.allow
    val sharing = app.isDoing("profile.share", "station" to s.station, "id" to p.id)
    val moving = app.isDoing("profile.move", "station" to s.station, "id" to p.id)
    val names = if (allowed == null) t("web-pages.profiles.share.everyStation") else stations.filter { it.id in allowed || it.id == s.id }.joinToString("、") { it.name }
    val targets = stations.filter { it.id != s.id }
    ListCard {
        ListRow(onClick = if (sharing) null else ({
            app.act(t("web-pages.profiles.share.switch"), if (shared) t("web-pages.profiles.share.unshared") else t("web-pages.profiles.share.shared")) { api.shareProfile(p.id, !shared, null) }
        })) {
            Column(Modifier.weight(1f)) {
                Text(t("web-pages.profiles.share.switch"), fontSize = 15.sp, color = C.ink)
                Text(if (!shared) t("web-pages.profiles.share.onlyHere", "station" to s.name) else if (subscription) t("web-pages.profiles.share.lent") else t("web-pages.profiles.share.copied"), fontSize = 13.sp, color = C.muted)
            }
            DoingMark(sharing, app.failedOf("profile.share", "station" to s.station, "id" to p.id), 14.dp)
            Switch(shared)
        }
        if (shared && subscription && p.machine != true) {
            ListRow(onClick = if (moving || targets.isEmpty()) null else ({ openMove(app, s, p, targets) })) {
                Text(t("web-pages.profiles.share.signedIn"), fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                DoingMark(moving, app.failedOf("profile.move", "station" to s.station, "id" to p.id), 14.dp)
                Text(s.name, fontSize = 13.sp, color = C.muted)
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
        if (shared) {
            ListRow(onClick = { openPickShare(app, s, p, stations, allowed) }) {
                Column(Modifier.weight(1f)) {
                    Text(t("web-pages.profiles.share.stations"), fontSize = 15.sp, color = C.ink)
                    val users = share?.users.orEmpty()
                    if (users.isNotEmpty()) Text(t("web-pages.profiles.share.users", "stations" to users.joinToString("、") { u -> stations.firstOrNull { it.id == u }?.name ?: u.take(8) }), fontSize = 13.sp, color = C.muted)
                }
                Text(names, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
    }
}

private fun openMove(app: AppState, s: StationView, p: Profile, targets: List<ShareStation>) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead(t("web-pages.profiles.share.moveTitle"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Text(t("web-pages.profiles.share.moveLead", "station" to s.name), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
            targets.forEach { x ->
                PickRow(x.name, sub = if (x.online) null else t("android-settings.profiles.stationOffline"), enabled = x.online) {
                    app.sheet = null
                    app.act(t("web-pages.profiles.share.move"), t("web-pages.profiles.share.moved", "station" to x.name)) { app.api(s.station).moveProfile(p.id, x.id) }
                }
            }
        }
    }
}

/** Which stations may use a shared profile, ticked in a sheet; all ticked is every station (those to come too). */
private fun openPickShare(app: AppState, s: StationView, p: Profile, stations: List<ShareStation>, allowed: List<String>?) {
    app.sheet = SheetSpec(0.6f) {
        var ticked by remember { mutableStateOf(allowed?.toSet() ?: stations.map { it.id }.toSet()) }
        val all = stations.all { it.id == s.id || it.id in ticked }
        SheetGrab()
        SheetHead(t("web-pages.profiles.share.stations"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Text(if (all) t("web-pages.profiles.share.futureIn") else t("web-pages.profiles.share.futureOut"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
            stations.forEach { x ->
                PickRow(x.name, checked = x.id == s.id || x.id in ticked, enabled = x.id != s.id) { ticked = if (x.id in ticked) ticked - x.id else ticked + x.id }
            }
            PickRow(t("web-pages.profiles.share.done"), color = C.accent) {
                app.sheet = null
                val allow = if (all) null else (ticked + s.id).toList()
                app.act(t("web-pages.profiles.share.stations")) { app.api(s.station).shareProfile(p.id, true, allow) }
            }
        }
    }
}

/** Where something is added: one of the stations online, picked in a sheet. */
fun openPickStation(app: AppState, title: String, stations: List<StationView>, go: (StationView) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Text(t("android-settings.pickStation"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
            stations.forEach { s -> PickRow(s.name) { app.sheet = null; go(s) } }
        }
    }
}

/**
 * A profile in the list of profiles: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
@Composable
internal fun ProfileRow(station: String, p: Profile) {
    val app = LocalApp.current
    val trouble = quotaTrouble(p.quota)
    ListRow(onClick = { app.push(Screen.Profile(station, p.id)) }) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PresenceDot(toneDot(p.checkTone))
                Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(listOfNotNull(p.checkText, if (p.machine == true) t("android-settings.profile.machine") else p.usesText?.ifEmpty { null } ?: ACCESS_LABEL[p.access.kind] ?: p.access.kind, p.modelsText).joinToString(" · "),
                fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (p.trouble != null) {
                Text("${p.trouble.title} · ${p.trouble.detail}", fontSize = 13.sp, color = C.muted)
                Text(t("android-settings.profile.seeFix"), fontSize = 13.sp, color = C.accent)
            } else trouble?.let { Text(it, fontSize = 13.sp, color = C.muted) }
        }
        val calls = setOf("profile.check", "profile.quota")
        DoingMark(app.isDoing(calls, "station" to station, "id" to p.id), app.failedOf(calls, "station" to station, "id" to p.id))
        QuotaRings(p.quota)
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

@Composable
fun ProfileScreen(current: WorkspaceEntry, address: String, id: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    val p = s?.overview?.profiles?.firstOrNull { it.id == id }
    if (s == null || p == null) return Column(Modifier.fillMaxSize()) {
        NavBar(s?.name ?: "Station", app::pop, "Profile")
        Loading(stations.error?.message ?: if (s?.overview != null) t("android-settings.profile.none") else t("android-settings.reading"))
    }
    val api = app.api(address)
    val setModels = { models: List<String> ->
        app.act(t("android-settings.profile.saveModels")) { api.setModels(p.id, models) }
    }
    // The switch flipped and not answered yet: shown flipped, with a spinner.
    var flipping by remember { mutableStateOf<Boolean?>(null) }
    val users = p.usedBy.mapNotNull { u -> s.overview?.connects?.firstOrNull { it.id == u } }
    val kind = p.access.kind
    // A copy of another station's: shown, used, changed only there.
    val copy = p.share?.role == "user"
    Column(Modifier.fillMaxSize()) {
        NavBar(s.name, app::pop, p.name, sub = { Text(if (p.machine == true) t("android-settings.profile.machine") else p.providerName ?: ACCESS_LABEL[kind] ?: kind, fontSize = 11.sp, color = C.muted) },
            trailing = if (copy) null else ({ NavButton(Icons.More, { openProfileMenu(app, address, p) }) }))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            Card {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ProviderMark(p.runtime, kind, 26.dp, p.providerMark)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            TonePill(p.checkText, p.checkTone)
                            // Its check or allowance refresh (asked from its menu, gone) failed a moment ago: a red mark, a tap says why.
                            if (app.isDoing("profile.check", "station" to address, "id" to p.id)) { Spinner(12.dp); Text(t("android-settings.version.checking"), fontSize = 12.sp, color = C.muted) }
                            else DoingMark(false, app.failedOf(setOf("profile.check", "profile.quota"), "station" to address, "id" to p.id), 12.dp)
                        }
                        Text(
                            (p.check?.detail?.replace(Regex("^可用[，,]\\s*"), "") ?: t("android-settings.profile.notChecked")) + (p.check?.time?.get("checkedAt")?.let { t("android-settings.profile.checkedAt", "ago" to it.ago) } ?: ""),
                            fontSize = 13.sp, color = C.muted,
                        )
                    }
                }
            }
            if (p.trouble != null) ProfileRecovery(s, p)
            if (!copy && kind == "subscription" && p.machine != true) SignIn(address, p, needed = p.check?.state == "login" || p.login?.state in SIGNING_IN)
            if (p.trouble?.action != "quota") QuotaSection(address, p)
            if (s.overview?.sharing == true) ShareSection(current, s, p)
            if (!copy && p.fast != null) {
                val busy = app.isDoing("profile.put", "station" to address, "id" to p.id)
                SectionHeader(t("android-settings.profile.run"), start = 24.dp)
                ListCard {
                    ListRow(onClick = if (busy) null else ({ app.act(t("android-settings.profile.saveFast"), if (p.fast) t("android-settings.profile.fastOff") else t("android-settings.profile.fastOn")) { api.putProfile(p.id, buildJsonObject { put("fast", !p.fast) }) } })) {
                        Column(Modifier.weight(1f)) {
                            Text(t("android-settings.profile.fast"), fontSize = 15.sp, color = C.ink)
                            Text(t("android-settings.profile.fastNote"), fontSize = 13.sp, color = C.muted)
                        }
                        DoingMark(busy, app.failedOf("profile.put", "station" to address, "id" to p.id), 14.dp)
                        Switch(p.fast)
                    }
                }
            }
            if (!copy) ModelsSection(address, p, p.models, p.modelsSaving != null) { models -> setModels(models) }
            // A station older than the setting says nothing of it.
            val background = flipping ?: p.backgroundOnMessage
            if (!copy && "claude" in p.runtimes && background != null) {
                SectionHeader(t("android-settings.profile.run"), start = 24.dp)
                ListCard {
                    ListRow(onClick = if (flipping != null) null else ({
                        flipping = !background
                        app.scope.launch {
                            try { api.putProfile(p.id, buildJsonObject { put("backgroundOnMessage", !background) }); app.toast = if (background) t("android-settings.profile.turnedOff") else t("android-settings.profile.turnedOn") }
                            catch (e: CoreException) { app.toast = t("android-settings.run.saveFailed", "error" to errorText(e)) }
                            finally { flipping = null }
                        }
                    })) {
                        Column(Modifier.weight(1f)) {
                            Text(t("android-settings.profile.background"), fontSize = 15.sp, color = C.ink)
                            Text(if (background) t("android-settings.profile.backgroundOn") else t("android-settings.profile.backgroundOff"), fontSize = 13.sp, color = C.muted)
                        }
                        if (flipping != null) Spinner(14.dp)
                        Switch(background)
                    }
                }
            }
            SectionHeader(t("android-settings.profile.users"), start = 24.dp)
            ListCard {
                if (users.isEmpty()) ListRow { Text(t("android-settings.profile.noUsers"), fontSize = 15.sp, color = C.muted) }
                users.forEach { c ->
                    ListRow(onClick = { app.push(Screen.Connect(address, c.id)) }) {
                        SlackMark(15.dp)
                        Text(c.name, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(c.modelName ?: p.model?.let { p.names[it] ?: it } ?: t("android-settings.profile.defaultModel"), fontSize = 13.sp, color = C.muted)
                    }
                }
            }
            if (copy) Unit
            else if (p.machine == true) {
                // On the machine's own login: whose it is is changed on that machine, not here.
                val runtime = MACHINE_RUNTIME[p.runtime] ?: p.runtime
                SectionHeader(t("android-settings.run.account"), start = 24.dp)
                Card {
                    Text(t("android-settings.profile.machineLogin", "station" to s.name, "runtime" to runtime), fontSize = 15.sp, color = C.ink)
                    Text(t("android-settings.profile.machineNote", "runtime" to runtime), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp))
                }
            } else if (kind in KEYED) {
                val name = if (kind == "opencode-go") "OpenCode Go key" else p.providerName?.let { "$it key" } ?: "API key"
                SectionHeader(t("android-settings.run.account"), start = 24.dp)
                ListCard {
                    ListRow(onClick = {
                        ask(app, if (kind == "opencode-go") t("android-settings.profile.newGoKey") else t("android-settings.profile.newApiKey"), "", t("android-settings.profile.pasteKey"), t("common.save"), secret = true, hint = t("android-settings.profile.keyHint"), what = t("android-settings.profile.keyWhat")) { key ->
                            api.putProfile(p.id, buildJsonObject { putJsonObject("access") { put("kind", kind); put("key", key) } }); app.toast = t("android-settings.profile.savedChecking")
                        }
                    }) {
                        Column(Modifier.weight(1f)) {
                            Text(name, fontSize = 15.sp, color = C.ink)
                            Text(p.access.key.ifEmpty { t("android-settings.profile.notSaved") }, fontSize = 13.sp, color = C.muted, fontFamily = FontFamily.Monospace)
                        }
                        // A key saved (the sheet that asked gone): a spinner until the station has it.
                        DoingMark(app.isDoing("profile.put", "station" to address, "id" to p.id), app.failedOf("profile.put", "station" to address, "id" to p.id))
                        Text(t("android-settings.profile.change"), fontSize = 14.sp, color = C.accent)
                    }
                    // Where a provider is at an address of the person's own, that can be changed too.
                    p.access.endpoint?.let { endpoint ->
                        ListRow(onClick = {
                            ask(app, t("common.provider.endpoint"), endpoint, "https://", t("common.save")) { value ->
                                api.putProfile(p.id, buildJsonObject { putJsonObject("access") { put("kind", kind); put("endpoint", value.trim()) } }); app.toast = t("android-settings.profile.savedChecking")
                            }
                        }) {
                            Column(Modifier.weight(1f)) {
                                Text(t("common.provider.endpoint"), fontSize = 15.sp, color = C.ink)
                                Text(endpoint, fontSize = 13.sp, color = C.muted, fontFamily = FontFamily.Monospace)
                            }
                            Text(t("android-settings.profile.change"), fontSize = 14.sp, color = C.accent)
                        }
                    }
                }
            }
            if (kind == "env" && !copy) {
                SectionHeader(t("android-settings.env.title"), start = 24.dp)
                ListCard {
                    p.env.forEach { e ->
                        ListRow {
                            Column(Modifier.weight(1f)) {
                                Text(e.key, fontSize = 15.sp, color = C.ink, fontFamily = FontFamily.Monospace)
                                Text(e.value, fontSize = 13.sp, color = C.muted, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                    ListRow(onClick = { app.sheet = SheetSpec(0.8f, draggable = true) { EnvSheet(address, p) } }) {
                        Text(t("android-settings.env.edit"), fontSize = 15.sp, color = C.accent, modifier = Modifier.weight(1f))
                        // Saved (the sheet gone): a spinner until the station has them.
                        DoingMark(app.isDoing("profile.put", "station" to address, "id" to p.id), app.failedOf("profile.put", "station" to address, "id" to p.id))
                    }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** The same core-provided diagnosis and next step as the mobile web. */
@Composable
private fun ProfileRecovery(station: StationView, p: Profile) {
    val app = LocalApp.current
    val issue = p.trouble ?: return
    val address = station.station
    val api = app.api(address)
    val checking = app.isDoing("profile.check", "station" to address, "id" to p.id)
    val refreshing = app.isDoing("profile.quota", "station" to address, "id" to p.id)
    SectionHeader(issue.title, start = 24.dp)
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(issue.detail, fontSize = 13.sp, color = C.ink)
            Text(issue.next, fontSize = 13.sp, color = C.muted)
            if (!station.online) Text(t("android-settings.profile.offline", "name" to station.name), fontSize = 13.sp, color = C.muted)
            if (issue.action == "command") CommandBox(p.loginCommand)
            if (issue.action != "login") Button(issue.label, primary = false, enabled = station.online, busy = checking || refreshing) {
                when (issue.action) {
                    "key" -> ask(app, t("android-settings.profile.newKey"), "", t("android-settings.profile.pasteKey"), t("common.save"), secret = true, hint = t("android-settings.profile.keyHintShort"), what = t("android-settings.profile.keyWhat")) { key ->
                        api.putProfile(p.id, buildJsonObject { putJsonObject("access") { put("kind", p.access.kind); put("key", key) } })
                    }
                    "env" -> app.sheet = SheetSpec(0.8f, draggable = true) { EnvSheet(address, p) }
                    "quota" -> app.act(t("android-settings.quota.checkWhat"), t("android-settings.quota.updated")) { api.refreshQuota(p.id) }
                    else -> app.act(t("android-settings.profile.checkWhat"), t("android-settings.profile.checked")) { api.checkProfile(p.id) }
                }
            }
            if (issue.action in setOf("key", "env")) Button(t("android-settings.profile.recheck"), primary = false, enabled = station.online, busy = checking) {
                app.act(t("android-settings.profile.checkWhat"), t("android-settings.profile.checked")) { api.checkProfile(p.id) }
            }
            DoingMark(false, app.failedOf(setOf("profile.check", "profile.quota"), "station" to address, "id" to p.id))
        }
    }
}

/** Renaming, checking, deleting it (not while a connect uses it). */
private fun openProfileMenu(app: AppState, station: String, p: Profile) {
    val api = app.api(station)
    app.sheet = SheetSpec(0.5f) {
        // Goes on past the sheet; the profile's page shows it under way (a spinner by its state or its allowance).
        val run = { what: String, done: String, call: suspend () -> Unit -> app.sheet = null; app.act(what, done) { call() } }
        val checking = app.isDoing("profile.check", "station" to station, "id" to p.id)
        SheetGrab()
        SheetHead(p.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            if (p.machine != true) PickRow(t("android-settings.station.rename")) { ask(app, t("android-settings.profile.nameTitle"), p.name, t("android-settings.station.name"), t("common.save"), what = t("android-settings.profile.renameWhat")) { name -> api.putProfile(p.id, buildJsonObject { put("name", name) }); app.toast = t("android-settings.renamed") } }
            PickRow(t("android-settings.profile.recheck"), busy = checking, failed = app.failedOf("profile.check", "station" to station, "id" to p.id)) { run(t("android-settings.profile.checkShort"), t("android-settings.profile.checked")) { api.checkProfile(p.id) } }
            // One on the machine's login is stopped rather than deleted: the login stays the machine's, to be used again.
            val machine = p.machine == true
            PickRow((if (machine) t("android-settings.connect.disable") else t("android-settings.profile.delete")).let { if (p.usedBy.isNotEmpty()) t("android-settings.profile.inUse", "action" to it) else it }, color = C.red, enabled = p.usedBy.isEmpty()) {
                if (machine) confirm(app, t("android-settings.profile.disableTitle", "name" to p.name), t("android-settings.profile.disableText", "app" to BuildConfig.APP_NAME, "runtime" to (MACHINE_RUNTIME[p.runtime] ?: p.runtime)), t("android-settings.connect.disable"), danger = true,
                    what = t("android-settings.profile.disableWhat"), then = app::pop) {
                    api.deleteProfile(p.id); app.toast = t("android-settings.profile.disabled")
                }
                else confirm(app, t("android-settings.connect.deleteTitle", "name" to p.name), t("android-settings.profile.deleteText", "app" to BuildConfig.APP_NAME), t("android-settings.profile.delete"), danger = true,
                    what = t("android-settings.profile.deleteWhat"), then = app::pop) {
                    api.deleteProfile(p.id); app.toast = t("android-settings.profile.deleted")
                }
            }
        }
    }
}

/** Its allowance, window by window: what is left and when it refills; why it cannot be read, when the provider says. */
@Composable
private fun QuotaSection(station: String, p: Profile) {
    val app = LocalApp.current
    val refreshing = app.isDoing("profile.quota", "station" to station, "id" to p.id)
    val failed = app.failedOf("profile.quota", "station" to station, "id" to p.id)
    val windows = p.quota?.takeIf { it.state == "ok" }?.windows.orEmpty()
    val trouble = quotaTrouble(p.quota)
    val checked = if (refreshing) t("android-settings.refreshing") else p.quota?.time?.get("checkedAt")?.let { t("android-settings.quota.checkedAt", "ago" to it.ago) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 14.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(t("android-settings.quota.title"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Spacer(Modifier.weight(1f))
        Row(Modifier.clickable(enabled = !refreshing) {
            app.act(t("android-settings.quota.checkWhat"), t("android-settings.quota.updated")) { app.api(station).refreshQuota(p.id) }
        }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DoingMark(refreshing, failed, 12.dp)
            Text(if (refreshing) t("android-settings.quota.checking") else t("android-settings.quota.check"), fontSize = 14.sp, color = if (refreshing) C.muted else C.accent)
        }
    }
    if (checked != null && !refreshing) Text(checked, fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, bottom = 8.dp))
    if (trouble != null) {
        val blocked = p.quota?.state == "blocked"
        ListCard {
            ListRow {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        PresenceDot(if (blocked) "error" else "offline")
                        Text(if (blocked) t("android-settings.quota.blocked") else t("android-settings.quota.unavailable"), fontSize = 15.sp, color = C.ink)
                    }
                    Text(trouble, fontSize = 13.sp, color = C.muted)
                }
            }
        }
        return
    }
    if (windows.isEmpty() && p.quota?.creditsText == null && p.quota?.resetCount == null) {
        Text(p.quota?.detail?.ifBlank { null } ?: t("android-settings.quota.none"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp))
        return
    }
    val resetting = app.isDoing("profile.resetQuota", "station" to station, "id" to p.id)
    ListCard {
        if (windows.isNotEmpty()) QuotaDials(p.quota, Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 14.dp))
        p.quota?.creditsText?.let { text -> ListRow {
            Text(t("android-settings.quota.credits"), fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
            Text(text, fontSize = 13.sp, color = C.muted)
        } }
        p.quota?.resetCount?.let { count -> ListRow(onClick = if (count <= 0 || resetting) null else ({
            confirm(app, t("android-settings.quota.resetTitle"), t("android-settings.quota.resetText", "name" to p.name, "text" to p.quota.resetText), t("android-settings.quota.resetUse"), what = t("android-settings.quota.resetWhat")) {
                app.api(station).resetQuota(p.id); app.toast = t("android-settings.quota.resetDone")
            }
        })) {
            Column(Modifier.weight(1f)) {
                Text(t("android-settings.quota.resets"), fontSize = 15.sp, color = C.ink)
                Text(p.quota.resetText ?: "", fontSize = 13.sp, color = C.muted)
            }
            DoingMark(resetting, app.failedOf("profile.resetQuota", "station" to station, "id" to p.id), 14.dp)
            Text(t("android-settings.quota.reset"), fontSize = 14.sp, color = if (count > 0) C.accent else C.muted)
        } }
    }
}

/** A check's state in its words on a soft pill of its tone (the core's: accent | green | blue | red | amber | neutral). */
@Composable
internal fun TonePill(text: String, tone: String, size: androidx.compose.ui.unit.TextUnit = 12.sp) {
    val color = when (tone) { "green" -> C.green; "red" -> C.red; "blue" -> C.blue; "accent" -> C.accentInk; "amber" -> C.warn; else -> C.muted }
    val bg = if (tone == "neutral") C.chip else color.copy(alpha = if (tone == "amber") 0.14f else 0.12f)
    Text(text, fontSize = size, color = color, maxLines = 1, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 6.dp, vertical = 1.dp))
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
@Composable
internal fun ModelsSection(station: String, p: Profile, models: List<String>, saving: Boolean, onSave: (List<String>) -> Unit) {
    val app = LocalApp.current
    val checking = app.isDoing("profile.check", "station" to station, "id" to p.id)
    val checkFailed = app.failedOf("profile.check", "station" to station, "id" to p.id)
    var filter by remember { mutableStateOf("") }
    val all = (p.available ?: (p.check?.models.orEmpty() + p.models).distinct()).sorted()
    val shown = all.filter { m -> listOf(m, p.names[m] ?: m).any { it.contains(filter.trim(), ignoreCase = true) } }
    val save = { models: List<String> -> onSave(models.distinct().sorted()) }
    val filtered = filter.isNotBlank()
    // A provider that answers the automatic decisions alone: the models its probe found, as they are.
    if (p.decisionOnly == true) {
        SectionHeader(t("web-mobile.profiles.decisionModels"), start = 24.dp)
        p.decisionModels.orEmpty().forEach { m -> Text(m, fontSize = 15.sp, color = C.ink, modifier = Modifier.padding(horizontal = 24.dp, vertical = 6.dp)) }
        p.decisionText?.let { Text(it, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 6.dp)) }
        return
    }
    SectionHeader(t(if (saving) "android-settings.models.headerSaving" else "android-settings.models.header", "on" to models.size, "n" to all.size), start = 24.dp)
    Text(
        if (all.isEmpty()) t("android-settings.models.empty") else t("android-settings.models.note"),
        fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 6.dp),
    )
    Row(Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.clickable(enabled = !checking) { app.act(t("android-settings.models.refreshWhat"), t("android-settings.models.refreshed")) { app.api(station).checkProfile(p.id) } },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DoingMark(checking, checkFailed, 12.dp)
            Text(if (checking) t("android-settings.refreshing") else t("android-settings.models.refresh"), fontSize = 14.sp, color = if (checking) C.muted else C.accent)
        }
        Spacer(Modifier.weight(1f))
        if (all.isNotEmpty()) {
            Text(if (filtered) t("android-settings.models.allFiltered") else t("android-settings.all"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable(enabled = !saving) { save(models + shown) })
            Text(if (filtered) t("android-settings.models.noneFiltered") else t("android-settings.none"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable(enabled = !saving) { save(models - shown.toSet()) })
        }
    }
    // A provider that does not list its models: one is named by hand.
    if (p.canAddModel == true) {
        var typed by remember { mutableStateOf("") }
        val adding = app.isDoing("profile.addModel", "station" to station, "id" to p.id)
        Row(Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Field(typed, { typed = it }, t("web-mobile.profiles.addModelPlaceholder"), mono = true, modifier = Modifier.weight(1f))
            if (adding) Spinner(14.dp)
            else Text(t("web-mobile.profiles.addModel"), fontSize = 14.sp, color = if (typed.isBlank()) C.muted else C.accent, modifier = Modifier.clickable(enabled = typed.isNotBlank()) {
                val model = typed.trim(); typed = ""
                app.act(t("android-settings.models.refreshWhat")) { app.api(station).addModel(p.id, model) }
            })
        }
    }
    if (all.size > 10) Field(filter, { filter = it }, t("android-settings.models.filter"), modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp))
    // Plain rows on the page, no card behind them; by series, newest first (the core's).
    p.series.forEach { series ->
        val list = series.models.filter { it in shown }
        if (list.isNotEmpty()) Text(series.name, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(top = 14.dp, bottom = 2.dp))
        list.forEach { m ->
            val on = m in models
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !saving) { save(if (on) models - m else models + m) }.padding(horizontal = 24.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(20.dp).clip(RoundedCornerShape(6.dp)).background(if (on) C.accent else C.chip), contentAlignment = Alignment.Center) {
                    if (on) IconIn(Icons.Check, 13.dp, C.bg)
                }
                Text(p.names[m] ?: m, fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                // Ticked here, not the station's yet.
                if (m in p.modelsSaving.orEmpty()) Spinner(12.dp)
            }
        }
    }
}

/** A subscription's sign-in: run on the station's machine, the browser steps relayed here. */
@Composable
private fun SignIn(station: String, p: Profile, needed: Boolean) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    val job = p.login
    val active = job != null && job.state in SIGNING_IN
    val provider = if (p.runtime == "claude") "Claude" else "ChatGPT"
    val busy = app.isDoing("profile.login", "station" to station, "id" to p.id)
    var manual by remember { mutableStateOf(false) }
    var previous by remember { mutableStateOf(job?.state) }
    LaunchedEffect(job?.state) {
        if (job?.state == "done" && previous != null && previous != "done") app.toast = t("android-settings.login.done")
        previous = job?.state
    }
    SectionHeader(if (active) t("android-settings.login.active", "provider" to provider) else if (needed) t("android-settings.login.needed", "provider" to provider) else t("android-settings.login.subscription", "provider" to provider), start = 24.dp)
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (active) {
                LoginSteps(job, provider) { code -> api.loginCode(p.id, code) }
                Button(t("android-settings.login.cancel"), primary = false, busy = app.isDoing("profile.cancelLogin", "station" to station, "id" to p.id)) { app.act(t("android-settings.login.cancelWhat")) { api.cancelLogin(p.id) } }
            } else {
                Text(
                    when (job?.state) { "failed" -> t("android-settings.login.failed", "error" to job.error); "done" -> t("android-settings.login.signedIn"); else -> t("android-settings.login.note", "app" to BuildConfig.APP_NAME) },
                    fontSize = 13.sp, color = C.muted,
                )
                Button(if (job?.state == "done" || !needed) t("android-settings.login.again") else t("android-settings.login.signIn"), primary = needed, busy = busy) {
                    scope.launch { try { api.startLogin(p.id) } catch (e: CoreException) { app.toast = t("android-settings.signIn.beginFailed", "error" to errorText(e)) } }
                }
                Text(t("android-settings.login.manual"), fontSize = 13.sp, color = C.muted, modifier = Modifier.clickable { manual = !manual }.padding(vertical = 4.dp))
                if (manual) CommandBox(p.loginCommand)
            }
        }
    }
}

/**
 * What the person does in the browser for a sign-in under way: open the page and paste the code back (Claude), or copy
 * the code and open the page (Codex).
 */
@Composable
private fun LoginSteps(job: LoginJob?, provider: String, send: suspend (String) -> Unit) {
    val context = LocalContext.current
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    val operation = remember(app) { Action(app) }
        val busy = operation.busy
    val error = operation.error?.message
    var copied by remember { mutableStateOf(false) }
    val open = { url: String -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    val waiting = @Composable { text: String ->
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { Spinner(12.dp); Text(text, fontSize = 13.sp, color = C.muted) }
    }
    when {
        job == null || job.state == "starting" -> waiting(t("android-settings.login.making", "provider" to provider))
        job.state == "verifying" -> waiting(t("android-settings.login.finishing"))
        job.state == "done" -> waiting(t("android-settings.login.adding"))
        job.state == "needs_approval" && job.url != null && job.userCode != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(job.userCode, fontSize = 22.sp, letterSpacing = 2.sp, fontFamily = FontFamily.Monospace, color = C.ink,
                modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(C.chip).padding(horizontal = 14.dp, vertical = 8.dp))
            Button(if (copied) t("android-settings.login.reopen") else t("android-settings.login.copyOpen"), primary = true) {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", job.userCode))
                copied = true; open(job.url)
            }
            Text(t("android-settings.login.codexNote", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.muted)
        }
        job.state == "needs_code" && job.url != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row {
                Text("1. ", fontSize = 13.sp, color = C.ink)
                Text(t("android-settings.login.openPage"), fontSize = 13.sp, color = C.accent, modifier = Modifier.clickable { open(job.url) })
                Text(t("android-settings.login.openPageRest", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.ink)
            }
            Text(t("android-settings.login.step2"), fontSize = 13.sp, color = C.ink)
            Field(code, { code = it }, t("android-settings.login.pasteCode"), mono = true)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Button(t("android-settings.login.finish"), primary = true, busy = busy, enabled = code.isNotBlank()) {

                operation.run { send(code.trim()); code = "" }
            }
        }
    }
}

/** A variable being edited: its row, name and value; a secret one saved before shows masked and is kept when left blank. */
private class EnvRow(val row: Int, key: String, value: String, val masked: String?, val original: String?) {
    var key by mutableStateOf(key)
    var value by mutableStateOf(value)
}

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
@Composable
private fun ColumnScope.EnvSheet(station: String, p: Profile) {
    val app = LocalApp.current
    var next by remember { mutableIntStateOf(1) }
    var rows by remember { mutableStateOf(p.env.mapIndexed { i, e -> EnvRow(-i - 1, e.key, if (e.secret) "" else e.value, if (e.secret) e.value else null, e.key) }) }
    val busy = app.isDoing("profile.put", "station" to station, "id" to p.id)
    val patch = {
        buildJsonObject {
            val kept = rows.map { it.key.trim() }.toSet()
            val out = LinkedHashMap<String, String?>()
            p.env.forEach { if (it.key !in kept) out[it.key] = null }
            rows.forEach { r ->
                val key = r.key.trim()
                if (key.isEmpty()) return@forEach
                if (r.original != null && r.original != key) out[r.original] = null
                if (r.masked != null && r.value.isEmpty() && r.original == key) return@forEach
                out[key] = r.value
            }
            out.forEach { (k, v) -> put(k, v?.let { JsonPrimitive(it) } ?: JsonNull) }
        }
    }
    SheetGrab()
    SheetHead(t("android-settings.env.title"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(t("android-settings.env.note"), fontSize = 12.sp, color = C.muted)
        rows.forEach { r ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Field(r.key, { r.key = it }, "NAME", mono = true, modifier = Modifier.weight(1f))
                    Text(t("common.delete"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { rows = rows.filter { it.row != r.row } })
                }
                val placeholder = if (r.masked != null) t("android-settings.tokens.kept", "token" to r.masked) else t("android-settings.env.value")
                if (r.masked != null || Regex("KEY|TOKEN|SECRET|PASSWORD|AUTH", RegexOption.IGNORE_CASE).containsMatchIn(r.key)) SecretField(r.value, { r.value = it }, placeholder)
                else Field(r.value, { r.value = it }, placeholder, mono = true)
            }
        }
        Text(t("android-settings.env.add"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { rows = rows + EnvRow(next++, "", "", null, null) })
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(t("common.save"), primary = true, enabled = !busy) {
                val env = patch()
                app.sheet = null
                app.act(t("android-settings.env.saveWhat"), t("android-settings.saved")) { app.api(station).putProfile(p.id, buildJsonObject { put("env", env) }) }
            }
        }
    }
}

/**
 * A new profile on a station, as the core's add flow has it (the `profileFlow` topic, as the web's profileFlow.ts): the
 * providers by group, then how to connect the one picked (a plan signed in, or a key checked first: the profile is made
 * only if it works).
 */
@Composable
fun NewProfileScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(address)
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    val form = remember(address) { java.util.UUID.randomUUID().toString() }
    val topic by rememberTopic<ProfileFlowView>(app.core, buildJsonObject { put("topic", "profileFlow"); put("station", address); put("form", form) })
    fun edit(input: JsonObject) {
        app.act(t("web-pages.addProfile.editAction")) { app.core.call("profile.flow.edit", buildJsonObject { put("station", address); put("form", form); put("input", input) }) }
    }
    fun edit(key: String, value: String) = edit(buildJsonObject { put(key, value) })
    LaunchedEffect(address, form) { app.act(t("web-pages.addProfile.openAction")) { app.core.call("profile.flow.open", buildJsonObject { put("station", address); put("form", form) }) } }
    DisposableEffect(address, form) { onDispose { app.scope.launch { try { app.core.call("profile.flow.drop", buildJsonObject { put("station", address); put("form", form) }) } catch (_: CoreException) {} } } }
    val d = topic.value
    val submitting = app.isDoing("profile.flow.submit", "station" to address, "form" to form)
    var login by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val pending = login?.let { l -> s?.overview?.logins?.firstOrNull { it.id == l } }
    val go = { id: String, message: String -> app.toast = message; app.replace(Screen.Profile(address, id)) }
    // The sign-in made its profile: on to it.
    LaunchedEffect(pending?.created) { pending?.created?.let { go(it, t("android-settings.profile.addedLogin")) } }
    val runtime = if (d?.tile?.runtime == "codex") "codex" else "claude"
    // A plan's sign-in starts when it is chosen; leaving before it made its profile leaves nothing behind.
    val planning = d?.step == "connect" && d.method == "plan"
    LaunchedEffect(planning) {
        if (planning) { error = null; try { login = api.newLogin(runtime) } catch (e: CoreException) { error = e.message } }
    }
    val dropLogin = {
        val l = login
        if (l != null && pending?.created == null) app.scope.launch { try { api.dropLogin(l) } catch (_: CoreException) {} }
        login = null
    }
    val leave = { if (d != null && d.step != "pick") { dropLogin(); edit("provider", "") } else app.pop() }
    androidx.activity.compose.BackHandler { leave() }
    val job = pending?.job
    Column(Modifier.fillMaxSize()) {
        NavBar(if (d != null && d.step != "pick") t("web-mobile.profiles.pick") else t("common.cancel"), leave, d?.title ?: t("android-settings.profile.add"), sub = { Text(s?.name ?: "", fontSize = 11.sp, color = C.muted) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (d == null) { Text(topic.error?.message ?: t("android-settings.reading"), fontSize = 14.sp, color = C.muted); return@Column }
            when {
                d.step == "pick" -> {
                    Text(d.hint, fontSize = 13.sp, color = C.muted)
                    // The machine's own logins not used yet: a profile on one needs no sign-in.
                    s?.overview?.let { o -> MachineLoginOffers(address, o, inset = 0.dp) { rt -> edit(buildJsonObject { put("provider", if (rt == "claude") "anthropic" else "openai"); put("method", "plan") }) } }
                    d.groups.forEach { g ->
                        Text(g.title, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 6.dp, top = 6.dp))
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                            g.providers.forEach { p ->
                                ListRow(onClick = { edit("provider", p.id) }) {
                                    ProviderMark(p.runtime ?: "claude", (p.kind?.ifEmpty { null } ?: "api-provider"), 18.dp, p.mark)
                                    Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                                }
                            }
                        }
                    }
                }
                d.step == "method" -> Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                    d.choices.forEach { c ->
                        PickRow(c.title, c.hint, leading = { ProviderMark(runtime, if (c.id == "plan") "subscription" else d.tile?.kind ?: "api-provider", 18.dp, d.tile?.mark) }) { edit("method", c.id) }
                    }
                }
                d.method == "plan" -> {
                    val l = login
                    if (error != null || job?.state == "failed" || job?.state == "cancelled") {
                        Text(error ?: job?.error ?: t("android-settings.login.unfinished"), fontSize = 13.sp, color = C.red)
                        Button(t("android-settings.login.restart"), primary = false) { dropLogin(); error = null; scope.launch { try { login = api.newLogin(runtime) } catch (e: CoreException) { error = e.message } } }
                    } else LoginSteps(job, if (runtime == "claude") "Claude" else "ChatGPT") { code -> api.newLoginCode(l ?: return@LoginSteps, code) }
                    if (d.usesLine.isNotEmpty()) Text(d.usesLine, fontSize = 13.sp, color = C.muted)
                }
                else -> ConnectForm(d, ::edit, submitting) {
                    scope.launch {
                        try {
                            val response = app.core.call("profile.flow.submit", buildJsonObject { put("station", address); put("form", form) })
                            go(response.jsonObject["id"]!!.jsonPrimitive.content, t("android-settings.profile.verifiedAdded"))
                        } catch (_: CoreException) {}
                    }
                }
            }
        }
    }
}

/** The form of a key: what is typed is kept here as it is typed (the core has it as it is named, and judges it). */
@Composable
private fun ColumnScope.ConnectForm(d: ProfileFlowView, edit: (String, String) -> Unit, busy: Boolean, submit: () -> Unit) {
    var endpoint by remember(d.tile?.id) { mutableStateOf(d.endpoint) }
    var key by remember(d.tile?.id) { mutableStateOf(d.key) }
    if (d.showEndpoint) {
        Text(t("common.provider.endpoint"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
            if (endpoint.isEmpty()) Text(d.tile?.endpointExample ?: "https://", color = C.subtle, fontSize = 15.sp, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
            androidx.compose.foundation.text.BasicTextField(endpoint, { endpoint = it.trim(); edit("endpoint", endpoint) }, singleLine = true, cursorBrush = androidx.compose.ui.graphics.SolidColor(C.accent),
                textStyle = androidx.compose.ui.text.TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = FontFamily.Monospace), modifier = Modifier.fillMaxWidth())
        }
        d.endpointHint?.let { Text(it, fontSize = 12.sp, color = C.muted) }
    }
    if ((d.regions?.size ?: 0) > 1) {
        Text(t("web-mobile.profiles.region"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
            d.regions.orEmpty().forEach { r -> PickRow(r.label, checked = r.id == d.region) { edit("region", r.id) } }
        }
    }
    if (d.protocols.size > 1) {
        Text(t("web-mobile.profiles.protocol"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
            d.protocols.forEach { p -> PickRow(p.label, checked = p.id == d.protocol) { edit("protocol", p.id) } }
        }
    }
    if (d.showKey) {
        Text(d.keyLabel, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        SecretField(key, { key = it; edit("key", it) }, t("android-settings.profile.keyPlaceholder"))
        val note = d.error ?: d.keyHint
        note?.let { Text(it, fontSize = 12.sp, color = if (d.error != null) C.red else C.muted) }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Button(d.submitLabel, primary = true, busy = busy || d.pending, enabled = d.canSubmit) { submit() }
    }
    if (d.usesLine.isNotEmpty()) Text(d.usesLine, fontSize = 13.sp, color = C.muted)
}

/**
 * The accounts this station machine's own Claude Code and Codex are signed in with and no profile uses yet (the station
 * reads them), each with its plan beside its runtime, its state and allowance: one kept in a file is used as it is (a
 * profile on the machine's login, no sign-in); one only in the keychain is signed in again for still.fail; a refused one is
 * only said so. `inset`: the list's side margin (none inside a padded page). On the new-profile page (`onLogin`) the
 * profile made takes its place, and signing in again picks that runtime's subscription there.
 */
@Composable
fun MachineLoginOffers(station: String, overview: Overview, inset: androidx.compose.ui.unit.Dp = 12.dp, onLogin: ((String) -> Unit)? = null) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val offers = overview.machineLogins.orEmpty().filter { it.offered == true }
    if (offers.isEmpty()) return
    Text(t("android-settings.machine.title"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = inset + 12.dp, end = inset + 12.dp, top = 8.dp, bottom = 4.dp))
    Column(Modifier.padding(horizontal = inset).padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
        offers.forEach { l -> MachineLoginRow(l, app.isDoing("profile.useMachineLogin", "station" to station, "runtime" to l.runtime)) {
            if (l.usable == true) {
                scope.launch {
                    try {
                        val id = app.api(station).useMachineLogin(l.runtime)
                        app.toast = t("android-settings.machine.added")
                        if (onLogin != null) app.replace(Screen.Profile(station, id)) else app.push(Screen.Profile(station, id))
                    } catch (e: CoreException) { app.toast = e.message }
                }
            } else if (onLogin != null) onLogin(l.runtime) else app.push(Screen.NewProfile(station))
        } }
    }
}

/** A machine login as a profile could be made with it: its runtime and plan, a dot and its state, who, its allowance; and what to do. */
@Composable
private fun MachineLoginRow(l: MachineLogin, busy: Boolean, onUse: () -> Unit) {
    val blocked = l.quota?.state == "blocked"
    val plan = l.plan?.replaceFirstChar { it.uppercase() }
    ListRow {
        ProviderMark(l.runtime, "subscription", 18.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(MACHINE_RUNTIME[l.runtime] ?: l.runtime, fontSize = 15.sp, color = C.ink, maxLines = 1)
                plan?.let { Text(it, fontSize = 13.sp, color = C.muted, maxLines = 1) }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                StateDot(if (blocked) C.red else C.green, 6.dp)
                Text(if (blocked) t("android-settings.quota.blocked") else t("android-settings.machine.signedIn"), fontSize = 12.sp, color = if (blocked) C.red else C.muted)
                Text("· ${l.email ?: t("android-settings.machine.someone")}", fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            quotaTrouble(l.quota)?.let { Text(it, fontSize = 12.sp, color = if (blocked) C.red else C.muted) }
        }
        QuotaRings(l.quota)
        // A refused account is said so, with nothing to do with it here.
        if (!blocked) {
            if (busy) Spinner(14.dp)
            else Text(if (l.usable == true) t("android-settings.machine.use") else t("android-settings.login.signIn"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable(onClick = onUse))
        }
    }
}
