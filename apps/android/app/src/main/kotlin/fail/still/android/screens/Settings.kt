// What the desktop's settings do that the app does too (docs/mobile-parity.md), as the narrow web has it
// (web/src/mobile/WorkspacePage.tsx, sheets.tsx, Stations.tsx): the workspace itself (its name, its people, leaving or
// deleting it), where the account is signed in, and adding, renaming and removing stations. Asking is a sheet: whether
// to go on with what cannot be undone, a name, a command to copy.
package fail.still.android.screens

import fail.still.android.BuildConfig
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.data.Cloud
import fail.still.android.data.Enrollment
import fail.still.android.data.LoginSession
import fail.still.android.data.errorText
import fail.still.android.data.Member
import fail.still.android.data.ROLE_HINT
import fail.still.android.data.ROLE_LABEL
import fail.still.android.data.SlackPerson
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.CodeFont
import fail.still.android.ui.IconIn
import fail.still.android.ui.Illustration
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.NavButton
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.data.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch

// ── asking ─────────────────────────────────────────────────────────────

/**
 * Asks before something that cannot be undone. With `what` (a verb phrase, as [AppState.act] takes) the sheet closes at
 * once, `then` runs (a page left, say) and `run` goes on by itself, the thing it is about marked under way, a failure
 * told by a toast; without it the sheet stays, with what went wrong, until it is done.
 */
fun confirm(app: AppState, title: String, text: String, action: String, danger: Boolean = false, what: String? = null, then: () -> Unit = {}, run: suspend () -> Unit) {
    app.sheet = SheetSpec(0.36f) {
        val scope = rememberCoroutineScope()
        val operation = remember(app) { Action(app) }
        val busy = operation.busy
        val error = operation.error?.message
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(text, fontSize = 14.sp, color = C.muted)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, danger = danger) {
                    if (what != null) { app.sheet = null; then(); app.act(what) { run() } }
                    else operation.run { run(); app.sheet = null }
                }
            }
        }
    }
}

/** Asks for a line (a name); `run` gets it trimmed. With `what`, as [confirm]: closes at once and goes on by itself. */
fun ask(app: AppState, title: String, value: String, placeholder: String, action: String, secret: Boolean = false, hint: String? = null, what: String? = null, empty: Boolean = false, run: suspend (String) -> Unit) {
    app.sheet = SheetSpec(0.42f) {
        val scope = rememberCoroutineScope()
        var text by remember { mutableStateOf(value) }
        val operation = remember(app) { Action(app) }
        val busy = operation.busy
        val error = operation.error?.message
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (secret) SecretField(text, { text = it }, placeholder) else Field(text, { text = it }, placeholder)
            hint?.let { Text(it, fontSize = 12.sp, color = C.muted) }
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, enabled = (empty || text.isNotBlank()) && text.trim() != value) {
                    val line = text.trim()
                    if (what != null) { app.sheet = null; app.act(what) { run(line) } }
                    else operation.run { run(line); app.sheet = null }
                }
            }
        }
    }
}

/** A command to run elsewhere, with a button that copies it. */
@Composable
fun CommandBox(text: String) {
    val app = LocalApp.current
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface2).border(1.dp, C.line, RoundedCornerShape(12.dp)).padding(start = 12.dp, end = 10.dp, top = 10.dp, bottom = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(text, fontSize = 12.sp, lineHeight = 18.sp, fontFamily = CodeFont, color = C.ink, modifier = Modifier.weight(1f))
        Box(
            Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).background(C.chip).clickable {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", text))
                app.toast = t("common.copied")
            },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Copy, 16.dp) }
    }
}

// ── the workspace ──────────────────────────────────────────────────────

/**
 * The workspace itself, from settings (SettingsHome.kt), as the narrow web's WorkspacePage.tsx: its name as the title (a
 * tap renames it), its people in one list (those in it, those added who have not signed in, the invitations out), adding
 * them from the ＋ at the top, and leaving or deleting it at the bottom.
 */
@Composable
fun WorkspaceScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    val view = topic.value
    val me = current.account
    val cloud = Cloud(app.core, me.sub)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop, trailing = if (view?.manager == true) ({
            NavButton(Icons.UserPlus, { app.sheet = SheetSpec(0.8f, draggable = true) { AddSheet(current, view, cloud) } }, 20.dp)
        }) else null)
        if (view == null) return Loading(topic.error?.message ?: t("android-settings.workspace.reading"))
        val waiting = if (view.manager) view.added.size + view.invitations.size else 0
        // Its name is the title, renamed by a tap on it (by its owner and admins).
        Box(if (view.manager) Modifier.clickable { ask(app, t("android-settings.workspace.name"), view.name, t("android-settings.workspace.namePlaceholder"), t("common.save"), what = t("android-settings.workspace.renameWhat")) { cloud.renameWorkspace(view.id, it); app.toast = t("android-settings.renamed") } } else Modifier) {
            LargeTitle("", view.name)
        }
        Text(t(if (view.manager) "android-settings.workspace.aboutRename" else "android-settings.workspace.about", "role" to (ROLE_LABEL[view.role] ?: view.role), "people" to t("android-settings.members.count", "n" to view.members.size), "stations" to t("android-settings.workspace.stations", "n" to view.stations.size)),
            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 4.dp))
        // Its people in one list: those in it, then those added who have not signed in yet, then the invitations out;
        // which is which on each row's second line.
        SectionHeader(t("android-settings.members.title"), if (waiting > 0) t("android-settings.members.waiting", "n" to view.members.size, "waiting" to waiting) else t("android-settings.members.count", "n" to view.members.size), start = 24.dp)
        ListCard {
            view.members.forEach { m -> MemberRow(view, m, me.sub, cloud) }
            if (view.manager) view.added.forEach { a ->
                ListRow {
                    Avatar(a.email, a.email, 28.dp)
                    Column(Modifier.weight(1f)) {
                        Text(a.email, fontSize = 15.sp, color = C.ink, maxLines = 1)
                        Text(t("android-settings.members.added", "role" to (ROLE_LABEL[a.role] ?: a.role)), fontSize = 13.sp, color = C.muted)
                    }
                    val on = arrayOf<Pair<String, Any?>>("workspace" to view.id, "email" to a.email)
                    RowAction(t("android-settings.members.remove"), C.accent, app.isDoing("workspace.removeAdded", *on), app.failedOf("workspace.removeAdded", *on)) {
                        app.act(t("android-settings.members.removeWhat"), t("android-settings.members.removed")) { cloud.removeAdded(view.id, a.email) }
                    }
                }
            }
            if (view.manager) view.invitations.forEach { i ->
                ListRow {
                    Avatar(i.email ?: i.id, i.email ?: "?", 28.dp)
                    Column(Modifier.weight(1f)) {
                        Text(i.email ?: t("android-settings.members.anyone"), fontSize = 15.sp, color = C.ink)
                        Text(t("android-settings.members.invitation", "role" to (ROLE_LABEL[i.role] ?: i.role), "until" to (i.time?.get("expires_at")?.until ?: "")), fontSize = 13.sp, color = C.muted)
                    }
                    val on = arrayOf<Pair<String, Any?>>("workspace" to view.id, "invitation" to i.id)
                    RowAction(t("android-settings.members.revoke"), C.accent, app.isDoing("workspace.revokeInvitation", *on), app.failedOf("workspace.revokeInvitation", *on)) {
                        app.act(t("android-settings.members.revokeWhat"), t("android-settings.members.revoked")) { cloud.revokeInvitation(view.id, i.id) }
                    }
                }
            }
        }
        Relays(view, cloud)
        Spacer(Modifier.height(18.dp))
        ListCard {
            ListRow(onClick = {
                confirm(app, t("android-settings.workspace.leaveTitle", "name" to view.name), t("android-settings.workspace.leaveText"), t("android-settings.workspace.leave"), danger = true,
                    what = t("android-settings.workspace.leaveWhat"), then = app::home) {
                    cloud.removeMember(view.id, me.sub); app.toast = t("android-settings.workspace.left")
                }
            }) { Text(t("android-settings.workspace.leaveRow"), fontSize = 15.sp, color = C.red) }
            if (view.role == "owner") ListRow(onClick = {
                confirm(app, t("android-settings.workspace.deleteTitle", "name" to view.name), t("android-settings.workspace.deleteText", "n" to view.stations.size, "app" to BuildConfig.APP_NAME), t("android-settings.workspace.delete"), danger = true,
                    what = t("android-settings.workspace.deleteWhat"), then = app::home) {
                    cloud.deleteWorkspace(view.id); app.toast = t("android-settings.workspace.deleted")
                }
            }) { Text(t("android-settings.workspace.delete"), fontSize = 15.sp, color = C.red) }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/**
 * The workspace's own relays, used besides still.fail's by its stations and its members' devices: owners and admins add
 * one from the last row (a sheet that says why one is refused) and take one out from its row.
 */
@Composable
private fun Relays(view: WorkspaceView, cloud: Cloud) {
    val app = LocalApp.current
    if (!view.manager && view.relays.isEmpty()) return
    val busy = app.isDoing("workspace.setRelays", "workspace" to view.id)
    SectionHeader(t("android-settings.relays.title"), start = 24.dp)
    ListCard {
        view.relays.forEach { url ->
            ListRow {
                Text(url.removePrefix("https://").removePrefix("http://"), fontSize = 15.sp, color = C.ink, maxLines = 1, modifier = Modifier.weight(1f))
                if (view.manager) RowAction(t("android-settings.members.remove"), C.accent, busy) {
                    app.act(t("android-settings.relays.removeWhat"), t("android-settings.relays.removed")) { cloud.setRelays(view.id, view.relays - url) }
                }
            }
        }
        if (view.manager) ListRow(onClick = if (busy) null else ({
            ask(app, t("android-settings.relays.add"), "", "https://relay.example.com", t("android-settings.relays.addAction"), hint = t("android-settings.relays.hint")) {
                cloud.setRelays(view.id, view.relays + it); app.toast = t("android-settings.relays.added")
            }
        })) { Text(t(if (busy) "android-settings.relays.saving" else "android-settings.relays.add"), fontSize = 15.sp, color = C.accent) }
    }
    Text(t("android-settings.relays.lead", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 6.dp))
}

/** A person of the workspace; the owner changes their role, a manager moves them out (an owner only by an owner). */
@Composable
private fun MemberRow(view: WorkspaceView, m: Member, me: String, cloud: Cloud) {
    val app = LocalApp.current
    val can = m.sub != me && view.manager && (m.role != "owner" || view.role == "owner")
    ListRow(onClick = if (can) ({ app.sheet = SheetSpec(0.5f) { MemberSheet(view, m, cloud) } }) else null) {
        Avatar(m.email, m.name.ifEmpty { m.email }, 28.dp, picture = m.picture)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(m.name.ifEmpty { m.email }, fontSize = 15.sp, color = C.ink, maxLines = 1)
                if (m.sub == me) You(t("android-settings.members.you"))
            }
            Text(m.email, fontSize = 13.sp, color = C.muted, maxLines = 1)
        }
        // Its role being set or it being moved out (the sheet that asked may be gone): a spinner, or a red mark a moment.
        val calls = setOf("workspace.setRole", "workspace.removeMember")
        DoingMark(app.isDoing(calls, "workspace" to view.id, "member" to m.sub), app.failedOf(calls, "workspace" to view.id, "member" to m.sub))
        Text(ROLE_LABEL[m.role] ?: m.role, fontSize = 13.sp, color = C.muted)
    }
}

/** A word at a row's end that does something (移除, 撤回, 退出): a spinner in its place while it is under way; a red mark before it a moment after it failed. */
@Composable
private fun RowAction(label: String, color: androidx.compose.ui.graphics.Color, busy: Boolean, failed: String? = null, onClick: () -> Unit) {
    if (busy) Spinner(14.dp)
    else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        DoingMark(false, failed)
        Text(label, fontSize = 14.sp, color = color, modifier = Modifier.clickable(onClick = onClick))
    }
}

@Composable
private fun You(text: String) =
    Text(text, fontSize = 12.sp, color = C.accentInk, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(C.accentBg).padding(horizontal = 6.dp))

@Composable
private fun ColumnScope.MemberSheet(view: WorkspaceView, m: Member, cloud: Cloud) {
    val app = LocalApp.current
    SheetGrab()
    SheetHead(m.name.ifEmpty { m.email })
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        // A role set closes the sheet at once; the person's row shows it under way (MemberRow), a toast if it failed.
        val setting = app.isDoing("workspace.setRole", "workspace" to view.id, "member" to m.sub)
        if (view.role == "owner") listOf("owner", "admin", "member").forEach { r ->
            PickRow(ROLE_LABEL[r] ?: r, ROLE_HINT[r], checked = m.role == r, enabled = !setting) {
                app.sheet = null
                if (r != m.role) app.act(t("android-settings.members.roleWhat"), t("android-settings.members.roleSet")) { cloud.setRole(view.id, m.sub, r) }
            }
        }
        PickRow(t("android-settings.members.moveOutRow"), color = C.red) {
            confirm(app, t("android-settings.members.moveOutTitle", "email" to m.email, "name" to view.name), t("android-settings.members.moveOutText"), t("android-settings.members.moveOut"), danger = true,
                what = t("android-settings.members.moveOutWhat")) {
                cloud.removeMember(view.id, m.sub); app.toast = t("android-settings.members.movedOut")
            }
        }
    }
}

/** The emails in what was typed or pasted: separated by commas, spaces, semicolons or lines; "Name <a@b.c>" too (web/src/cloud/adding.ts). */
private fun parseEmails(text: String): List<String> =
    Regex("""[^\s<>,;"'()]+@[^\s<>,;"'()]+\.[^\s<>,;"'()]+""").findAll(text).map { it.value.lowercase() }.distinct().toList()

/**
 * Adding people by email, no invitation to accept: members at once when they have signed in to still.fail before, from their
 * first sign-in otherwise. Typed or pasted, or picked from the people of the Slack workspaces the online stations are in
 * (each station reads its own Slack).
 */
@Composable
private fun ColumnScope.AddSheet(current: WorkspaceEntry, view: WorkspaceView, cloud: Cloud) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val online = stations.value.orEmpty().filter { it.online }
    var text by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("member") }
    val busy = app.isDoing("workspace.addMembers", "account" to current.account.sub, "workspace" to view.id)
    var error by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf<String?>(null) }
    var people by remember { mutableStateOf<List<SlackPerson>?>(null) }
    var problems by remember { mutableStateOf<List<String>>(emptyList()) }
    var reading by remember { mutableStateOf(false) }
    var picked by remember { mutableStateOf<Set<String>>(emptySet()) }
    val inside = (view.members.map { it.email.lowercase() } + view.added.map { it.email.lowercase() }).toSet()
    val emails = (parseEmails(text) + picked).distinct().filter { it !in inside }
    val roles = if (view.role == "owner") listOf("member", "admin", "owner") else listOf("member", "admin")
    val fromSlack = {
        reading = true
        scope.launch {
            val seen = LinkedHashMap<String, SlackPerson>()
            val found = mutableListOf<String>()
            for (s in online) {
                try {
                    val (list, errors) = app.api(s.station).slackPeople()
                    list.forEach { p -> if (p.email !in seen) seen[p.email] = p }
                    found += errors
                } catch (e: CoreException) { found += e.message }
            }
            val all = seen.values.sortedWith(compareBy<SlackPerson> { it.guest }.thenBy { it.name })
            people = all; problems = found
            // Once read, the workspace's own Slack people are picked; guests are left to choose.
            picked = all.filter { !it.guest && it.email !in inside }.map { it.email }.toSet()
            reading = false
        }
        Unit
    }
    SheetGrab()
    SheetHead(t("android-settings.add.title"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val result = done
        if (result != null) {
            Text(result, fontSize = 14.sp, color = C.ink)
            Row(Modifier.fillMaxWidth().padding(bottom = 24.dp), horizontalArrangement = Arrangement.End) { Button(t("common.done"), primary = true) { app.sheet = null } }
            return@Column
        }
        Text(t("android-settings.add.note", "name" to view.name, "app" to BuildConfig.APP_NAME), fontSize = 14.sp, color = C.muted)
        Text(t("android-settings.add.emails"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Field(text, { text = it }, t("android-settings.add.emailsPlaceholder"), lines = 3)
        val list = people
        if (online.isNotEmpty()) {
            if (list == null) Row { Button(t("android-settings.add.fromSlack"), primary = false, busy = reading) { fromSlack() } }
            else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(t("android-settings.add.picked", "n" to list.size, "picked" to picked.count { it !in inside }), fontSize = 13.sp, color = C.muted, modifier = Modifier.weight(1f))
                    Text(t("android-settings.all"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { picked = list.map { it.email }.filter { it !in inside }.toSet() })
                    Text(t("android-settings.none"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { picked = emptySet() })
                }
                Column {
                    list.forEach { p ->
                        val there = p.email in inside
                        PickRow(p.name.ifEmpty { p.email }, listOfNotNull(p.email, if (there) t("android-settings.add.in") else if (p.guest) t("android-settings.add.guest") else null).joinToString(" · "),
                            checked = there || p.email in picked, enabled = !there, leading = { Avatar(p.email, p.name.ifEmpty { p.email }, 28.dp, picture = p.image) }) {
                            picked = if (p.email in picked) picked - p.email else picked + p.email
                        }
                    }
                }
                if (problems.isNotEmpty()) Text(problems.joinToString(t("android-settings.add.problemSep")), fontSize = 13.sp, color = C.red)
            }
        }
        Text(t("android-settings.add.role"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Column {
            roles.forEach { r -> PickRow(ROLE_LABEL[r] ?: r, ROLE_HINT[r], checked = role == r) { role = r } }
        }
        error?.let { Text(it, fontSize = 13.sp, color = C.red) }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(if (emails.size > 1) t("android-settings.add.many", "n" to emails.size) else t("android-settings.add.one"), primary = true, busy = busy, enabled = emails.isNotEmpty()) {
                error = null
                scope.launch {
                    try {
                        val r = cloud.addMembers(view.id, role, emails)
                        done = t("android-settings.add.done", "list" to listOf(
                            if (r.joined.isNotEmpty()) t("android-settings.add.joined", "n" to r.joined.size) else "",
                            if (r.added.isNotEmpty()) t("android-settings.add.added", "n" to r.added.size, "app" to BuildConfig.APP_NAME) else "",
                            if (r.already.isNotEmpty()) t("android-settings.add.already", "n" to r.already.size) else "",
                        ).filter { it.isNotEmpty() }.joinToString(t("android-settings.add.sep")))
                    } catch (e: CoreException) { error = errorText(e) }
                }
            }
        }
    }
}

// ── where the account is signed in ─────────────────────────────────────

/** The account's devices: where it is signed in to still.fail; one not recognised can be signed out from here. */
@Composable
fun Devices(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<List<LoginSession>>(app.core, Topics.loginSessions(current.account.sub))
    val list = topic.value ?: return Text(topic.error?.let { t("android-settings.devices.failed", "error" to it.message) } ?: t("android-settings.reading"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
    val cloud = Cloud(app.core, current.account.sub)
    ListCard {
        list.forEach { s ->
            ListRow {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(s.name.ifEmpty { t("android-settings.devices.unnamed") }, fontSize = 15.sp, color = C.ink, maxLines = 1)
                        if (s.current) You(t("android-settings.devices.here"))
                    }
                    Text(t("android-settings.devices.times", "ago" to (s.time?.get("created_at")?.ago ?: ""), "until" to (s.time?.get("expires_at")?.until ?: "")), fontSize = 13.sp, color = C.muted)
                }
                if (!s.current) {
                    if (app.isDoing("loginSession.revoke", "id" to s.id)) Spinner(14.dp)
                    else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        DoingMark(false, app.failedOf("loginSession.revoke", "id" to s.id))
                        Text(t("android-settings.devices.signOut"), fontSize = 15.sp, color = C.red, modifier = Modifier.clickable {
                            app.act(t("android-settings.devices.signOutWhat"), t("android-settings.devices.signedOut")) { cloud.revokeLoginSession(s.id) }
                        })
                    }
                }
            }
        }
    }
}

// ── stations ───────────────────────────────────────────────────────────

/** Whether the viewer may add, rename and remove stations: the workspace's owner and admins. */
@Composable
fun isManager(current: WorkspaceEntry): Boolean {
    val app = LocalApp.current
    val topic by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    return topic.value?.manager == true
}

/** Adding a station: a name, then the command to run on that machine (which installs still.fail and joins it); the sheet waits for it to join. */
fun openAddStation(app: AppState, current: WorkspaceEntry, known: List<String>) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        SheetGrab()
        SheetHead(t("android-settings.station.add"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("android-settings.station.addNote", "app" to BuildConfig.APP_NAME), fontSize = 14.sp, color = C.muted)
            AddStationSteps(current, known, onCancel = { app.sheet = null }) { app.sheet = null }
        }
    }
}

/**
 * A station's name, then the one command that installs still.fail on that machine and joins it (one with still.fail already
 * too), copied from here, and the wait for it; `onJoined` once it has. `onCancel`: a way out beside the first step.
 * `label`: what the name's line is called.
 */
@Composable
private fun AddStationSteps(current: WorkspaceEntry, known: List<String>, label: String = t("android-settings.station.name"), placeholder: String = t("android-settings.station.namePlaceholder"), onCancel: (() -> Unit)? = null, onJoined: () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    var name by remember { mutableStateOf("") }
    var made by remember { mutableStateOf<Enrollment?>(null) }
    val busy = app.isDoing("workspace.enroll", "account" to current.account.sub, "workspace" to current.workspace.id)
    var error by remember { mutableStateOf<String?>(null) }
    val joined = made?.let { stations.value?.firstOrNull { it.id !in known } }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val enrollment = made
        when {
            enrollment == null -> {
                Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Field(name, { name = it }, placeholder)
                error?.let { Text(it, fontSize = 13.sp, color = C.red) }
                Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    if (onCancel != null) Button(t("common.cancel"), primary = false) { onCancel() }
                    Button(t("android-settings.station.make"), primary = true, busy = busy, enabled = name.isNotBlank()) {
                        error = null
                        scope.launch { try { made = Cloud(app.core, current.account.sub).enroll(current.workspace.id, name.trim()) } catch (e: CoreException) { error = errorText(e) } }
                    }
                }
            }
            joined != null -> {
                Text(t("android-settings.station.joined", "name" to joined.name), fontSize = 14.sp, color = C.ink)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button(t("common.done"), primary = true) { onJoined() } }
            }
            else -> {
                Text(t("android-settings.station.run"), fontSize = 14.sp, color = C.ink)
                CommandBox(enrollment.install)
                Text(t("android-settings.station.runNote", "app" to BuildConfig.APP_NAME), fontSize = 13.sp, color = C.muted)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Spinner(10.dp)
                    Text(t("android-settings.station.waiting"), fontSize = 13.sp, color = C.muted)
                }
            }
        }
    }
}

/**
 * A workspace with no station: its first one added in the page (as the desktop's Onboarding, web/src/cloud/workspace.tsx,
 * and the narrow web's FirstStation, web/src/mobile/Stations.tsx): what a station is, its name, then the command to copy
 * and the wait. The workspace's pages take over once it has joined. Only its owner and admins add one; anyone else is
 * told to wait for them.
 */
@Composable
fun FirstStation(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    val view = topic.value
    Column(Modifier.fillMaxWidth().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Illustration(R.drawable.illus_no_station, R.drawable.illus_no_station_dark, 240.dp)
        Text(t("android-settings.station.first"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink, textAlign = TextAlign.Center)
        Text(t("android-settings.station.firstNote"), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
        Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when {
                view == null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Spinner(13.dp); Text(topic.error?.message ?: t("android-settings.workspace.reading"), fontSize = 14.sp, color = C.muted)
                }
                !view.manager -> Text(t("android-settings.station.wait"), fontSize = 13.sp, lineHeight = 19.5.sp, color = C.ink,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(horizontal = 12.dp, vertical = 10.dp))
                else -> AddStationSteps(current, emptyList(), label = t("android-settings.station.firstName"), placeholder = t("android-settings.station.firstPlaceholder")) {}
            }
        }
    }
}

/** A station's own actions: its name, its emoji, and removing it from the workspace. */
fun openStationMenu(app: AppState, current: WorkspaceEntry, s: StationView) {
    val cloud = Cloud(app.core, current.account.sub)
    app.sheet = SheetSpec(0.34f) {
        SheetGrab()
        SheetHead(s.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow(t("android-settings.station.rename")) { ask(app, t("android-settings.station.renameTitle"), s.name, t("android-settings.station.renamePlaceholder"), t("common.save"), what = t("android-settings.station.renameWhat")) { cloud.renameStation(current.workspace.id, s.id, it); app.toast = t("android-settings.renamed") } }
            PickRow(t("android-settings.station.emoji")) { ask(app, t("android-settings.station.emojiTitle", "name" to s.name), s.emoji ?: "", t("android-settings.station.emojiPlaceholder"), t("common.save"), what = t("android-settings.station.emojiWhat"), empty = true) { cloud.setStationEmoji(current.workspace.id, s.id, it); app.toast = t("android-settings.station.emojiSet") } }
            PickRow(t("android-settings.station.removeRow"), color = C.red) {
                confirm(app, t("android-settings.station.removeTitle", "name" to s.name), t("android-settings.station.removeText", "app" to BuildConfig.APP_NAME), t("android-settings.station.remove"), danger = true,
                    what = t("android-settings.station.removeWhat"), then = app::pop) {
                    cloud.removeStation(current.workspace.id, s.id); app.toast = t("android-settings.station.removed")
                }
            }
        }
    }
}
