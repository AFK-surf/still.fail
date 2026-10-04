// Settings, one page from the gear on Home, as the narrow web has it (web/src/mobile/Settings.tsx): who is signed in, then
// the workspace's (its people, stations, connects, profiles, memory), then this device's (how it looks, whether it
// notifies, this build). Each row says how things stand at its end, what is wrong in red, so the page is worth a look
// before anything is opened. And how this device shows still.fail (外观).
package fail.still.android.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.BuildConfig
import fail.still.android.LocalApp
import fail.still.android.Push
import fail.still.android.Screen
import fail.still.android.data.ConnectsView
import fail.still.android.data.ROLE_LABEL
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.errorText
import fail.still.android.data.rememberTopic
import fail.still.android.rememberNotificationAsk
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.ui.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private fun themes() = listOf("system" to t("android-settings.theme.system"), "light" to t("android-settings.theme.light"), "dark" to t("android-settings.theme.dark"))

/** The languages to choose: null follows the phone (the core's `language`, client/core-ts/src/prefs.ts). */
private fun languages() = listOf(null to t("common.language.system"), "zh" to t("common.language.zh"), "en" to t("common.language.en"))

/** A row that opens a page: its name, how things stand (`bad` in red; `dot`, a red dot before it), a chevron. */
@Composable
fun GoRow(title: String, value: String? = null, bad: Boolean = false, dot: Boolean = false, lead: (@Composable RowScope.() -> Unit)? = null, onClick: () -> Unit) {
    ListRow(onClick = onClick) {
        lead?.invoke(this)
        Text(title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (value != null) Row(Modifier.widthIn(max = 220.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (dot) PresenceDot("error")
            Text(value, fontSize = 14.sp, color = if (bad) C.red else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/** A page's note under its title, in a line or two. */
@Composable
fun PageNote(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 10.dp))

@Composable
fun SettingsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val me = current.account
    val workspace by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    val stationsTopic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val connectsTopic by rememberTopic<ConnectsView>(app.core, Topics.connects(current.workspace.id, false))
    val view = workspace.value
    val stations = stationsTopic.value
    val connects = connectsTopic.value
    val waiting = view?.let { it.added.size + it.invitations.size } ?: 0
    val online = stations?.count { it.online } ?: 0
    val troubled = stations?.any { !it.online } ?: false
    val failing = connects?.items?.count { it.connect.presence == "error" } ?: 0
    val profiles = stations.orEmpty().flatMap { it.overview?.profiles.orEmpty() }
    val short = profiles.count { it.trouble != null }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.home.back"), app::pop)
        LargeTitle("", t("android-settings.title"))
        Card(onClick = { app.push(Screen.Me) }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Avatar(me.email, me.name.ifEmpty { me.email }, 46.dp, picture = me.picture)
                Column(Modifier.weight(1f)) {
                    Text(me.name.ifEmpty { me.email }, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(me.email, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
        SectionHeader(view?.let { t("android-settings.home.workspace", "name" to it.name, "role" to (ROLE_LABEL[it.role] ?: it.role)) } ?: current.workspace.name, start = 24.dp)
        ListCard {
            GoRow("Workspace", view?.let { if (it.manager && waiting > 0) t("android-settings.members.waiting", "n" to it.members.size, "waiting" to waiting) else t("android-settings.members.count", "n" to it.members.size) }) { app.push(Screen.Workspace) }
            GoRow("Station", stations?.let { t("android-settings.home.online", "online" to online, "total" to it.size) }, dot = troubled) { app.push(Screen.Stations) }
            GoRow(t("android-settings.connects.title"), connects?.let { if (failing > 0) t("android-settings.home.failing", "n" to failing) else t("android-settings.count", "n" to it.items.size) }, bad = failing > 0) { app.push(Screen.Connects()) }
            GoRow("Profile", stations?.let { if (short > 0) t("android-settings.home.short", "n" to short) else t("android-settings.count", "n" to profiles.size) }, bad = short > 0) { app.push(Screen.Profiles()) }
            GoRow(t("web-pages.automaticDecisions.title")) { app.push(Screen.AutomaticDecisions) }
            GoRow(t("android-settings.memory")) { app.push(Screen.Memories) }
            GoRow(t("android-settings.home.usage")) { app.push(Screen.Usage) }
        }
        SectionHeader(t("android-settings.home.device"), start = 24.dp)
        ListCard {
            GoRow(t("android-settings.appearance.title"), themes().firstOrNull { it.first == app.theme }?.second) { app.push(Screen.Appearance) }
            KeptFilesRow()
            Notify()
            Version()
            GoRow(t("android-settings.changelog.title")) { app.push(Screen.Changelog) }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** What this device keeps (its chats' messages and files, and the rest), how much it takes. */
@Composable
private fun KeptFilesRow() {
    val app = LocalApp.current
    val context = LocalContext.current
    var total by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(Unit) { total = KeptFiles.read(app, context).total }
    GoRow(t("android-settings.files.title"), total?.let { fileSize(it) }) { app.push(Screen.KeptFiles) }
}

/** Local notices and pushes alike, on this device (Notices.kt, Push.kt); turned on, the system is asked too. */
@Composable
private fun Notify() {
    val app = LocalApp.current
    val context = LocalContext.current
    val ask = rememberNotificationAsk(app, once = false)
    // Switched and not answered yet: shown as asked, with a spinner, and not switched again meanwhile.
    val pending = app.isDoing("notify.set")
    ListRow(onClick = if (pending) null else ({
        val on = !app.notify
        if (on) ask()
        app.scope.launch { Push.sync(context.applicationContext, app.core, app.useNotify(on)) }
    })) {
        Column(Modifier.weight(1f)) {
            Text(t("android-settings.notify.title"), fontSize = 15.sp, color = C.ink)
            Text(if (app.notify) t("android-settings.notify.on") else t("android-settings.notify.off"), fontSize = 13.sp, color = C.muted)
        }
        if (pending) Spinner(14.dp)
        Switch(app.notify)
    }
}

/**
 * This build, and a newer one when still.fail cloud has it: tapped, it is downloaded and installed; with none known yet,
 * tapping asks still.fail cloud again right away.
 */
@Composable
private fun Version() {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val updates = app.updates
    val newer = updates.available
    LaunchedEffect(Unit) { app.checkUpdates() }
    val busy = updates.progress != null || updates.checking
    ListRow(onClick = if (busy) null else ({ scope.launch { (if (newer == null) updates.checkNow() else updates.install())?.let { app.toast = it } } })) {
        // The beta app goes by its own name (app/build.gradle.kts).
        Text("${BuildConfig.APP_NAME} ${BuildConfig.VERSION_NAME}", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
        Text(updates.progress ?: (if (updates.checking) t("android-settings.version.checking") else null) ?: newer?.let { t("android-settings.version.update", "version" to it.versionName) } ?: t("android-settings.version.check"), fontSize = 15.sp, color = if (newer != null && !busy) C.accent else C.muted)
    }
}

/** How this device shows still.fail: its theme, and the language it speaks. */
@Composable
fun AppearanceScreen() {
    val app = LocalApp.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("android-settings.appearance.title"))
        SectionHeader(t("android-settings.appearance.theme"), start = 24.dp)
        val themes = themes()
        Seg(themes.map { it.second }, themes.indexOfFirst { it.first == app.theme }.coerceAtLeast(0), { app.useTheme(themes[it].first) },
            Modifier.padding(horizontal = 12.dp).fillMaxWidth(), height = 34.dp, fill = true)
        Language()
        Spacer(Modifier.height(30.dp))
    }
}

/**
 * The language things are said in: the phone's (the default), Chinese or English, as the core keeps it (prefs
 * `language`); the core's `lang` then changes the app's words (ui/I18n.kt).
 */
@Composable
private fun Language() {
    val app = LocalApp.current
    val languages = languages()
    SectionHeader(t("common.language"), start = 24.dp)
    Seg(languages.map { it.second }, languages.indexOfFirst { it.first == app.language }.coerceAtLeast(0), { i ->
        val value = languages[i].first
        if (value != app.language) app.setLanguage(value)
    }, Modifier.padding(horizontal = 12.dp).fillMaxWidth(), height = 34.dp, fill = true)
}
