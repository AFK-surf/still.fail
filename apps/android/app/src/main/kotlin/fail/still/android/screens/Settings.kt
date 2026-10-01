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
import androidx.compose.ui.text.font.FontFamily
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
import fail.still.core.CoreException
import kotlinx.coroutines.launch

// ── asking ─────────────────────────────────────────────────────────────

/** Asks before something that cannot be undone; the sheet stays, with what went wrong, until it is done. */
fun confirm(app: AppState, title: String, text: String, action: String, danger: Boolean = false, run: suspend () -> Unit) {
    app.sheet = SheetSpec(0.36f) {
        val scope = rememberCoroutineScope()
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(text, fontSize = 14.sp, color = C.muted)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, danger = danger) {
                    busy = true; error = null
                    scope.launch { try { run(); app.sheet = null } catch (e: CoreException) { error = errorText(e) } finally { busy = false } }
                }
            }
        }
    }
}

/** Asks for a line (a name); `run` gets it trimmed. */
fun ask(app: AppState, title: String, value: String, placeholder: String, action: String, secret: Boolean = false, hint: String? = null, run: suspend (String) -> Unit) {
    app.sheet = SheetSpec(0.42f) {
        val scope = rememberCoroutineScope()
        var text by remember { mutableStateOf(value) }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (secret) SecretField(text, { text = it }, placeholder) else Field(text, { text = it }, placeholder)
            hint?.let { Text(it, fontSize = 12.sp, color = C.muted) }
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, enabled = text.isNotBlank() && text.trim() != value) {
                    busy = true; error = null
                    scope.launch { try { run(text.trim()); app.sheet = null } catch (e: CoreException) { error = errorText(e) } finally { busy = false } }
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
        Text(text, fontSize = 12.sp, lineHeight = 18.sp, fontFamily = FontFamily.Monospace, color = C.ink, modifier = Modifier.weight(1f))
        Box(
            Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).background(C.chip).clickable {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", text))
                app.toast = "已复制"
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
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("设置", app::pop, trailing = if (view?.manager == true) ({
            NavButton(Icons.UserPlus, { app.sheet = SheetSpec(0.8f, draggable = true) { AddSheet(current, view, cloud) } }, 20.dp)
        }) else null)
        if (view == null) return Loading(topic.error?.message ?: "正在读取 workspace…")
        val waiting = if (view.manager) view.added.size + view.invitations.size else 0
        // Its name is the title, renamed by a tap on it (by its owner and admins).
        Box(if (view.manager) Modifier.clickable { ask(app, "Workspace 名字", view.name, "例如：产品团队", "保存") { cloud.renameWorkspace(view.id, it); app.toast = "已改名" } } else Modifier) {
            LargeTitle("", view.name)
        }
        Text("你是${ROLE_LABEL[view.role] ?: view.role} · ${view.members.size} 人 · ${view.stations.size} 台 station" + if (view.manager) " · 点名字改名" else "",
            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 4.dp))
        // Its people in one list: those in it, then those added who have not signed in yet, then the invitations out;
        // which is which on each row's second line.
        SectionHeader("成员", "${view.members.size} 人" + if (waiting > 0) " · $waiting 人待加入" else "", start = 24.dp)
        ListCard {
            view.members.forEach { m -> MemberRow(view, m, me.sub, cloud) }
            if (view.manager) view.added.forEach { a ->
                ListRow {
                    Avatar(a.email, a.email, 28.dp)
                    Column(Modifier.weight(1f)) {
                        Text(a.email, fontSize = 15.sp, color = C.ink, maxLines = 1)
                        Text("${ROLE_LABEL[a.role] ?: a.role} · 还没登录过，第一次登录时自动加入", fontSize = 13.sp, color = C.muted)
                    }
                    Text("移除", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable {
                        scope.launch { try { cloud.removeAdded(view.id, a.email); app.toast = "已移除" } catch (e: CoreException) { app.toast = e.message } }
                    })
                }
            }
            if (view.manager) view.invitations.forEach { i ->
                ListRow {
                    Avatar(i.email ?: i.id, i.email ?: "?", 28.dp)
                    Column(Modifier.weight(1f)) {
                        Text(i.email ?: "任何拿到链接的人", fontSize = 15.sp, color = C.ink)
                        Text("${ROLE_LABEL[i.role] ?: i.role} · 邀请 · ${i.time?.get("expires_at")?.until ?: ""}过期", fontSize = 13.sp, color = C.muted)
                    }
                    Text("撤回", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable {
                        scope.launch { try { cloud.revokeInvitation(view.id, i.id); app.toast = "已撤回邀请" } catch (e: CoreException) { app.toast = e.message } }
                    })
                }
            }
        }
        Spacer(Modifier.height(18.dp))
        ListCard {
            ListRow(onClick = {
                confirm(app, "退出「${view.name}」？", "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。", "退出", danger = true) {
                    cloud.removeMember(view.id, me.sub); app.toast = "已退出 workspace"; app.home()
                }
            }) { Text("退出这个 workspace", fontSize = 15.sp, color = C.red) }
            if (view.role == "owner") ListRow(onClick = {
                confirm(app, "删除「${view.name}」？", "所有成员都会失去访问权限，${view.stations.size} 台 station 会断开和 ${BuildConfig.APP_NAME} cloud 的连接（station 本机上的数据不受影响）。", "删除 workspace", danger = true) {
                    cloud.deleteWorkspace(view.id); app.toast = "已删除 workspace"; app.home()
                }
            }) { Text("删除 workspace", fontSize = 15.sp, color = C.red) }
        }
        Spacer(Modifier.height(30.dp))
    }
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
                if (m.sub == me) You("你")
            }
            Text(m.email, fontSize = 13.sp, color = C.muted, maxLines = 1)
        }
        Text(ROLE_LABEL[m.role] ?: m.role, fontSize = 13.sp, color = C.muted)
    }
}

@Composable
private fun You(text: String) =
    Text(text, fontSize = 12.sp, color = C.accentInk, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(C.accentBg).padding(horizontal = 6.dp))

@Composable
private fun ColumnScope.MemberSheet(view: WorkspaceView, m: Member, cloud: Cloud) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    SheetGrab()
    SheetHead(m.name.ifEmpty { m.email })
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        if (view.role == "owner") listOf("owner", "admin", "member").forEach { r ->
            PickRow(ROLE_LABEL[r] ?: r, ROLE_HINT[r], checked = m.role == r) {
                scope.launch { try { cloud.setRole(view.id, m.sub, r); app.toast = "已更改角色"; app.sheet = null } catch (e: CoreException) { app.toast = e.message } }
            }
        }
        PickRow("移出 workspace", color = C.red) {
            confirm(app, "把 ${m.email} 移出「${view.name}」？", "对方不能再访问这个 workspace 里的 station，之后可以重新邀请。", "移出", danger = true) {
                cloud.removeMember(view.id, m.sub); app.toast = "已移除成员"
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
    var busy by remember { mutableStateOf(false) }
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
    SheetHead("添加成员")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val result = done
        if (result != null) {
            Text(result, fontSize = 14.sp, color = C.ink)
            Row(Modifier.fillMaxWidth().padding(bottom = 24.dp), horizontalArrangement = Arrangement.End) { Button("完成", primary = true) { app.sheet = null } }
            return@Column
        }
        Text("直接加进「${view.name}」，不用对方接受：登录过 ${BuildConfig.APP_NAME} 的人马上加入，其他人第一次用这个邮箱登录时自动加入。", fontSize = 14.sp, color = C.muted)
        Text("邮箱", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Field(text, { text = it }, "name@example.com，可以粘贴多个", lines = 3)
        val list = people
        if (online.isNotEmpty()) {
            if (list == null) Row { Button("从 Slack 里选人", primary = false, busy = reading) { fromSlack() } }
            else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Slack 里 ${list.size} 人，选中 ${picked.count { it !in inside }} 人", fontSize = 13.sp, color = C.muted, modifier = Modifier.weight(1f))
                    Text("全选", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { picked = list.map { it.email }.filter { it !in inside }.toSet() })
                    Text("全不选", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { picked = emptySet() })
                }
                Column {
                    list.forEach { p ->
                        val there = p.email in inside
                        PickRow(p.name.ifEmpty { p.email }, listOfNotNull(p.email, if (there) "已在" else if (p.guest) "访客" else null).joinToString(" · "),
                            checked = there || p.email in picked, enabled = !there, leading = { Avatar(p.email, p.name.ifEmpty { p.email }, 28.dp, picture = p.image) }) {
                            picked = if (p.email in picked) picked - p.email else picked + p.email
                        }
                    }
                }
                if (problems.isNotEmpty()) Text(problems.joinToString("；"), fontSize = 13.sp, color = C.red)
            }
        }
        Text("角色", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Column {
            roles.forEach { r -> PickRow(ROLE_LABEL[r] ?: r, ROLE_HINT[r], checked = role == r) { role = r } }
        }
        error?.let { Text(it, fontSize = 13.sp, color = C.red) }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("取消", primary = false) { app.sheet = null }
            Button(if (emails.size > 1) "添加 ${emails.size} 人" else "添加", primary = true, busy = busy, enabled = emails.isNotEmpty()) {
                busy = true; error = null
                scope.launch {
                    try {
                        val r = cloud.addMembers(view.id, role, emails)
                        done = listOf(
                            if (r.joined.isNotEmpty()) "${r.joined.size} 人已经加入" else "",
                            if (r.added.isNotEmpty()) "${r.added.size} 人第一次登录 ${BuildConfig.APP_NAME} 时自动加入" else "",
                            if (r.already.isNotEmpty()) "${r.already.size} 人本来就在" else "",
                        ).filter { it.isNotEmpty() }.joinToString("，") + "。"
                    } catch (e: CoreException) { error = errorText(e) } finally { busy = false }
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
    val scope = rememberCoroutineScope()
    val topic by rememberTopic<List<LoginSession>>(app.core, Topics.loginSessions(current.account.sub))
    val list = topic.value ?: return Text(topic.error?.let { "读不到登录记录：${it.message}" } ?: "正在读取…", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
    val cloud = Cloud(app.core, current.account.sub)
    ListCard {
        list.forEach { s ->
            ListRow {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(s.name.ifEmpty { "未命名设备" }, fontSize = 15.sp, color = C.ink, maxLines = 1)
                        if (s.current) You("这里")
                    }
                    Text("${s.time?.get("created_at")?.ago ?: ""}登录 · ${s.time?.get("expires_at")?.until ?: ""}过期", fontSize = 13.sp, color = C.muted)
                }
                if (!s.current) Text("退出", fontSize = 15.sp, color = C.red, modifier = Modifier.clickable {
                    scope.launch { try { cloud.revokeLoginSession(s.id); app.toast = "已让那台设备退出" } catch (e: CoreException) { app.toast = e.message } }
                })
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
        SheetHead("添加 station")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("station 是一台运行 ${BuildConfig.APP_NAME} 的机器。给它起个名字，然后在那台机器的终端里执行生成的一行命令，它会装好 ${BuildConfig.APP_NAME} 并加入。", fontSize = 14.sp, color = C.muted)
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
private fun AddStationSteps(current: WorkspaceEntry, known: List<String>, label: String = "名字", placeholder: String = "比如机器名：studio、mac-mini", onCancel: (() -> Unit)? = null, onJoined: () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    var name by remember { mutableStateOf("") }
    var made by remember { mutableStateOf<Enrollment?>(null) }
    var busy by remember { mutableStateOf(false) }
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
                    if (onCancel != null) Button("取消", primary = false) { onCancel() }
                    Button("生成命令", primary = true, busy = busy, enabled = name.isNotBlank()) {
                        busy = true; error = null
                        scope.launch { try { made = Cloud(app.core, current.account.sub).enroll(current.workspace.id, name.trim()) } catch (e: CoreException) { error = errorText(e) } finally { busy = false } }
                    }
                }
            }
            joined != null -> {
                Text("「${joined.name}」已加入，现在可以打开它了。", fontSize = 14.sp, color = C.ink)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button("完成", primary = true) { onJoined() } }
            }
            else -> {
                Text("在那台机器的终端里执行：", fontSize = 14.sp, color = C.ink)
                CommandBox(enrollment.install)
                Text("macOS（Apple 芯片）和 Linux 都行；装过 ${BuildConfig.APP_NAME} 的机器也用这条命令。它会装好 ${BuildConfig.APP_NAME}、加入这个 workspace，并在后台一直运行。加入以后，在它的 Station 页添加 Profile。", fontSize = 13.sp, color = C.muted)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Spinner(10.dp)
                    Text("等待这台机器加入… 执行命令后会自动继续 · 命令 1 小时内有效", fontSize = 13.sp, color = C.muted)
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
        Text("添加第一台 station", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink, textAlign = TextAlign.Center)
        Text("agent 在你的机器上干活。先把一台 Mac 或 Linux 机器加进来。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
        Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when {
                view == null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Spinner(13.dp); Text(topic.error?.message ?: "正在读取 workspace…", fontSize = 14.sp, color = C.muted)
                }
                !view.manager -> Text("这个 workspace 还没有 station，等管理员添加。", fontSize = 13.sp, lineHeight = 19.5.sp, color = C.ink,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(horizontal = 12.dp, vertical = 10.dp))
                else -> AddStationSteps(current, emptyList(), label = "给这台机器起个名字", placeholder = "比如 studio、mac-mini") {}
            }
        }
    }
}

/** A station's own actions: its name, and removing it from the workspace. */
fun openStationMenu(app: AppState, current: WorkspaceEntry, s: StationView) {
    val cloud = Cloud(app.core, current.account.sub)
    app.sheet = SheetSpec(0.34f) {
        SheetGrab()
        SheetHead(s.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("改名") { ask(app, "station 的名字", s.name, "比如机器名：studio", "保存") { cloud.renameStation(current.workspace.id, s.id, it); app.toast = "已改名" } }
            PickRow("从 workspace 移除", color = C.red) {
                confirm(app, "移除「${s.name}」？", "它会断开与 ${BuildConfig.APP_NAME} cloud 的连接，成员不能再从这里访问它。那台机器上的 ${BuildConfig.APP_NAME} 和数据不受影响，之后可以重新添加。", "移除 station", danger = true) {
                    cloud.removeStation(current.workspace.id, s.id); app.toast = "已移除 station"; app.pop()
                }
            }
        }
    }
}
