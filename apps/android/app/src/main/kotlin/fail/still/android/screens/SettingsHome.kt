// Settings, one page from the gear on Home: who is signed in and the workspace in view, each a card; then the
// workspace's in small groups (who may do what; its stations and what they run; its agents), then this device's (how it
// looks, its bar, whether it notifies, what it keeps), then 关于 (this build, what changed, whether it reports, the
// terms). Each row has its icon, and says how things stand at its end, what is wrong in red, so the page is worth a look
// before anything is opened. And how this device shows still.fail (外观), and 关于 itself.
package fail.still.android.screens

import fail.still.android.ui.Spinner
import fail.still.android.ui.CARD_PAD
import fail.still.android.ui.CARD_CORNER
import fail.still.android.ui.concentric
import fail.still.android.ui.initial
import fail.still.android.ui.isStationPicture
import fail.still.android.ui.hasStationMark
import fail.still.android.ui.StationMark
import fail.still.android.ui.Smooth
import fail.still.android.data.VaultsView
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.background
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
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import fail.still.android.BuildConfig
import fail.still.android.Crashes
import fail.still.android.LocalApp
import fail.still.android.Push
import fail.still.android.Screen
import fail.still.android.data.ConnectsView
import fail.still.android.data.I18n
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
import fail.still.android.data.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.fileSize
import fail.still.android.ui.LocalWide

private fun themes() = listOf("system" to t("android-settings.theme.system"), "light" to t("android-settings.theme.light"), "dark" to t("android-settings.theme.dark"))

/** When a done chat is offered to archive: null once done (the default), as the web's (the core's `archiveHint`). */
private fun archiveHints() = listOf("off" to t("web-pages.appearance.archive.off"), null to t("web-pages.appearance.archive.done"), "reviewed" to t("web-pages.appearance.archive.reviewed"))

/** The motions to choose: null follows the system's (ui/Motion.kt; the core's `motion`, client/core-ts/src/prefs.ts). */
private fun motions() = listOf(null to t("web-pages.appearance.motion.system"), "reduce" to t("web-pages.appearance.motion.reduce"), "full" to t("web-pages.appearance.motion.full"))

/** The languages to choose: null follows the phone (the core's `language`, client/core-ts/src/prefs.ts). */
private fun languages() = listOf(null to t("common.language.system"), "zh" to t("common.language.zh"), "en" to t("common.language.en"))

@Composable
fun SettingsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val me = current.account
    val workspace by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    val stationsTopic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val connectsTopic by rememberTopic<ConnectsView>(app.core, Topics.connects(current.workspace.id, false))
    val lock by rememberTopic<fail.still.android.data.LockView>(app.core, Topics.lock(current.workspace.id))
    val view = workspace.value
    val stations = stationsTopic.value
    val connects = connectsTopic.value
    val waiting = view?.let { it.added.size + it.invitations.size } ?: 0
    val online = stations?.count { it.online } ?: 0
    val troubled = stations?.any { !it.online } ?: false
    val failing = connects?.items?.count { it.connect.presence == "error" } ?: 0
    val profiles = stations.orEmpty().flatMap { it.overview?.profiles.orEmpty() }
    val short = profiles.count { it.trouble != null }
    val vaults by rememberTopic<VaultsView>(app.core, Topics.vaults(current.workspace.id))
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
        // The workspace as the account is: its mark, its name, the viewer's role in it and its people.
        val summary = current.workspace
        val role = view?.role ?: summary.role
        val members = view?.let { if (it.manager && waiting > 0) t("android-settings.members.waiting", "n" to it.members.size, "waiting" to waiting) else t("android-settings.members.count", "n" to it.members.size) }
            ?: t("android-settings.members.count", "n" to summary.members)
        Card(onClick = { app.push(Screen.Workspace) }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                WorkspaceTile(view?.name ?: summary.name, view?.emoji ?: summary.emoji, view?.icon ?: summary.icon)
                Column(Modifier.weight(1f)) {
                    Text(view?.name ?: summary.name, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(listOfNotNull(ROLE_LABEL[role] ?: role.ifEmpty { null }, members).joinToString(" · "), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                IconIn(Icons.ChevronRight, 14.dp, C.subtle)
            }
        }
        // Who may do what: security mode and the vault, where the workspace has them.
        val security = lock.value?.takeIf { it.available }
        if (security != null || vaults.value != null) ListCard {
            security?.let { l ->
                GoRow(t("web-pages.security.title"), if (!l.locked) t("web-mobile.settings.securityOff") else if (l.attention > 0u) t("web-mobile.settings.securityWaiting", "n" to l.attention.toInt()) else t("web-mobile.settings.securityOn"), bad = l.attention > 0u, icon = Icons.ShieldCheck) { app.push(Screen.Security) }
            }
            VaultSettingsRow(current.workspace.id)
        }
        // Its stations and what they run: the agents' accounts and the chats' ways in.
        ListCard {
            GoRow("Station", stations?.let { t("android-settings.home.online", "online" to online, "total" to it.size) }, dot = troubled, icon = Icons.Server) { app.push(Screen.Stations) }
            GoRow(t("android-settings.connects.title"), connects?.let { if (failing > 0) t("android-settings.home.failing", "n" to failing) else t("android-settings.count", "n" to it.items.size) }, bad = failing > 0, icon = Icons.Im) { app.push(Screen.Connects()) }
            GoRow("Profile", stations?.let { if (short > 0) t("android-settings.home.short", "n" to short) else t("android-settings.count", "n" to profiles.size) }, bad = short > 0, icon = Icons.Quota) { app.push(Screen.Profiles()) }
        }
        // Its agents: what they decide by themselves, what they remember, what they used.
        ListCard {
            GoRow(t("web-pages.automaticDecisions.title"), icon = Icons.Check) { app.push(Screen.AutomaticDecisions) }
            GoRow(t("android-settings.memory"), icon = Icons.Brain) { app.push(Screen.Memories) }
            GoRow(t("android-settings.home.usage"), icon = Icons.Chart) { app.push(Screen.Usage) }
        }
        SectionHeader(t("android-settings.home.device"), start = 24.dp)
        ListCard {
            GoRow(t("android-settings.appearance.title"), themes().firstOrNull { it.first == app.theme }?.second, icon = Icons.Sliders) { app.push(Screen.Appearance) }
            // The bottom bar's places (BarSettings.kt): a phone's only, a wide screen has none.
            if (!LocalWide.current) GoRow(t("android-misc.bar.title"), barsValue(app), icon = Icons.ViewColumns) { app.push(Screen.BarSettings) }
            Notify()
            KeptFilesRow()
        }
        ListCard { AboutRow() }
        Spacer(Modifier.height(30.dp))
    }
}

/**
 * The workspace's mark on its card, as the account's picture is on its own: CARD_PAD from the card's edges, so in its
 * corners, its corner concentric with the card's; a picture put up fills the square; one of still.fail's icons or an
 * emoji on the chips' ground; else its first letter, muted, as the web's rail has it, near the account's initial beside
 * it (half its picture).
 */
@Composable
private fun WorkspaceTile(name: String, emoji: String?, icon: String?) {
    val picture = isStationPicture(icon)
    Box(Modifier.size(46.dp).clip(Smooth(concentric(CARD_CORNER, CARD_PAD))).background(if (picture) C.surface else C.chip), contentAlignment = Alignment.Center) {
        when {
            picture -> StationMark(emoji, icon, 46.dp, C.ink)
            hasStationMark(emoji, icon) -> StationMark(emoji, icon, 26.dp, C.ink)
            else -> Text(initial(name), fontSize = 22.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = C.muted)
        }
    }
}

/** 关于's row: this build, or the newer one still.fail cloud has (tapped there, it is installed). */
@Composable
private fun AboutRow() {
    val app = LocalApp.current
    LaunchedEffect(Unit) { app.checkUpdates() }
    val newer = app.updates.available
    GoRow(t("web-pages.settings.nav.about"), newer?.let { t("android-settings.version.update", "version" to it.versionName) } ?: BuildConfig.VERSION_NAME, icon = Icons.Info) { app.push(Screen.About) }
}

/** About this app, as the web's 关于: this build and a newer one, what changed, whether it reports, the terms. */
@Composable
fun AboutScreen() {
    val app = LocalApp.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle("", t("web-pages.settings.nav.about"))
        ListCard {
            Version()
            GoRow(t("android-settings.changelog.title")) { app.push(Screen.Changelog) }
        }
        if (BuildConfig.POSTHOG_KEY.isNotEmpty()) ListCard { Reporting() }
        ListCard { Legal() }
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
    GoRow(t("android-settings.files.title"), total?.let { fileSize(it) }, icon = Icons.Disk) { app.push(Screen.KeptFiles) }
}

/** Local notices and pushes alike, on this device (Notices.kt, Push.kt); turned on, the system is asked too. Its switch
 *  says whether: no note under it. */
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
        RowIcon(Icons.Bell)
        Text(t("android-settings.notify.title"), fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
        if (pending) Spinner()
        Switch(app.notify)
    }
}

/**
 * Whether usage statistics and error reports go to still.fail (docs/telemetry.md → 安卓), on this device (Crashes.kt
 * keeps it and sends by it): not shown in a build without PostHog's key, which sends nothing anyway.
 */
@Composable
private fun Reporting() {
    if (BuildConfig.POSTHOG_KEY.isEmpty()) return
    val context = LocalContext.current
    var on by remember { mutableStateOf(Crashes.reporting(context)) }
    ListRow(onClick = { on = !on; Crashes.setReporting(context, on) }) {
        Column(Modifier.weight(1f)) {
            Text(t("android-settings.telemetry.title"), fontSize = 15.sp, color = C.ink)
            Text(t("android-settings.telemetry.note", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.muted)
        }
        Switch(on)
    }
}

/**
 * still.fail's terms and privacy policy, on the web in a Custom Tab, in English when the app speaks it (data/I18n.kt):
 * the arrow out, as the web's 关于 has them.
 */
@Composable
private fun Legal() {
    val context = LocalContext.current
    val open = { page: String ->
        val url = "https://still.fail${if (I18n.lang == "en") "/en" else ""}/$page"
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri())
    }
    for ((page, title) in listOf("terms" to t("android-settings.legal.terms"), "privacy" to t("android-settings.legal.privacy"))) {
        ListRow(onClick = { open(page) }) {
            Text(title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            IconIn(Icons.ArrowUpRight, 14.dp, C.subtle)
        }
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
        Text(updates.progress ?: (if (updates.checking) t("android-settings.version.checking") else null) ?: newer?.let { t("android-settings.version.update", "version" to it.versionName) } ?: t("android-settings.version.check"), fontSize = 15.sp, color = if (newer != null && !busy) C.link else C.muted)
    }
}

/** How this device shows still.fail: its theme, its fonts, its motion, and the language it speaks (the web's 外观 the same). */
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
        Spacer(Modifier.height(12.dp))
        ListCard { FontRow() }
        Motions()
        Language()
        ArchiveHints()
        Spacer(Modifier.height(30.dp))
    }
}

/** Whether motion is reduced on this device, as the web's (prefs `motion`): the system's say, reduced, or in full. */
@Composable
private fun Motions() {
    val app = LocalApp.current
    val motions = motions()
    SectionHeader(t("web-pages.appearance.motion.title"), start = 24.dp)
    Seg(motions.map { it.second }, motions.indexOfFirst { it.first == app.motion }.coerceAtLeast(0), { i ->
        val value = motions[i].first
        if (value != app.motion) app.setMotion(value)
    }, Modifier.padding(horizontal = 12.dp).fillMaxWidth(), height = 34.dp, fill = true)
    // As the web's note under it (mobile/Settings.css.ts mSegNote).
    Text(t("web-pages.appearance.motion.description"), fontSize = 13.sp, lineHeight = 19.5.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp))
}

/** 提示归档, as the web's (prefs `archiveHint`): never, once done, or once the station's archive review recommended it;
 *  what the one chosen does, under it. */
@Composable
private fun ArchiveHints() {
    val app = LocalApp.current
    val hints = archiveHints()
    val at = hints.indexOfFirst { it.first == app.archiveHint }.let { if (it < 0) 1 else it }
    SectionHeader(t("web-pages.appearance.archive.title"), start = 24.dp)
    Seg(hints.map { it.second }, at, { i ->
        val value = hints[i].first
        if (value != app.archiveHint) app.setArchiveHint(value)
    }, Modifier.padding(horizontal = 12.dp).fillMaxWidth(), height = 34.dp, fill = true)
    Text(t("web-pages.appearance.archive.${hints[at].first ?: "done"}Hint"), fontSize = 13.sp, lineHeight = 19.5.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp))
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
