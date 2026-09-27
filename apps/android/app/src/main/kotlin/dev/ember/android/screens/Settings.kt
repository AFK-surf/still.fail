// What the desktop's settings do that the app does too (docs/mobile-parity.md), as the narrow web has it
// (web/src/mobile/WorkspacePage.tsx, sheets.tsx, Stations.tsx): the workspace itself (its name, its people, leaving or
// deleting it), where the account is signed in, and adding, renaming and removing stations. Asking is a sheet: whether
// to go on with what cannot be undone, a name, a command to copy.
package dev.ember.android.screens

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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.Screen
import dev.ember.android.data.Cloud
import dev.ember.android.data.Enrollment
import dev.ember.android.data.LoginSession
import dev.ember.android.data.Member
import dev.ember.android.data.ROLE_HINT
import dev.ember.android.data.ROLE_LABEL
import dev.ember.android.data.StationView
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.WorkspaceView
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.LargeTitle
import dev.ember.android.ui.ListCard
import dev.ember.android.ui.ListRow
import dev.ember.android.ui.Loading
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.core.CoreException
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
                    scope.launch { try { run(); app.sheet = null } catch (e: CoreException) { error = e.message } finally { busy = false } }
                }
            }
        }
    }
}

/** Asks for a line (a name); `run` gets it trimmed. */
fun ask(app: AppState, title: String, value: String, placeholder: String, action: String, run: suspend (String) -> Unit) {
    app.sheet = SheetSpec(0.42f) {
        val scope = rememberCoroutineScope()
        var text by remember { mutableStateOf(value) }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Field(text, { text = it }, placeholder)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, enabled = text.isNotBlank() && text.trim() != value) {
                    busy = true; error = null
                    scope.launch { try { run(text.trim()); app.sheet = null } catch (e: CoreException) { error = e.message } finally { busy = false } }
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
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("ember", text))
                app.toast = "已复制"
            },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Copy, 16.dp) }
    }
}

// ── the workspace ──────────────────────────────────────────────────────

@Composable
fun WorkspaceScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    val view = topic.value
    val me = current.account
    val cloud = Cloud(app.core, me.sub)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("会话", app::pop)
        if (view == null) return Loading(topic.error?.message ?: "正在读取 workspace…")
        LargeTitle("你是${ROLE_LABEL[view.role] ?: view.role} · ${me.email}", view.name)
        if (view.manager) ListCard {
            ListRow(onClick = { ask(app, "Workspace 名字", view.name, "例如：产品团队", "保存") { cloud.renameWorkspace(view.id, it); app.toast = "已改名" } }) {
                Text("改名", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
            }
        }
        SectionHeader("成员 · ${view.members.size} 人", start = 24.dp)
        ListCard {
            view.members.forEach { m -> MemberRow(view, m, me.sub, cloud) }
            if (view.manager) ListRow(onClick = { app.sheet = SheetSpec(0.62f) { InviteSheet(view, cloud) } }) { Text("＋ 邀请成员", fontSize = 15.sp, color = C.accent) }
        }
        if (view.manager && view.invitations.isNotEmpty()) {
            SectionHeader("未接受的邀请", "${view.invitations.size} 个", start = 24.dp)
            ListCard {
                view.invitations.forEach { i ->
                    ListRow {
                        Column(Modifier.weight(1f)) {
                            Text(i.email ?: "任何拿到链接的人", fontSize = 15.sp, color = C.ink)
                            Text("${ROLE_LABEL[i.role] ?: i.role} · ${i.time?.get("expires_at")?.until ?: ""}过期", fontSize = 13.sp, color = C.muted)
                        }
                        val scope = rememberCoroutineScope()
                        Text("撤回", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable {
                            scope.launch { try { cloud.revokeInvitation(view.id, i.id); app.toast = "已撤回邀请" } catch (e: CoreException) { app.toast = e.message } }
                        })
                    }
                }
            }
        }
        SectionHeader("离开", start = 24.dp)
        ListCard {
            ListRow(onClick = {
                confirm(app, "退出「${view.name}」？", "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。", "退出", danger = true) {
                    cloud.removeMember(view.id, me.sub); app.toast = "已退出 workspace"; app.home()
                }
            }) { Text("退出这个 workspace", fontSize = 15.sp, color = C.red) }
            if (view.role == "owner") ListRow(onClick = {
                confirm(app, "删除「${view.name}」？", "所有成员都会失去访问权限，${view.stations.size} 台 station 会断开和 ember cloud 的连接（station 本机上的数据不受影响）。", "删除 workspace", danger = true) {
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

@Composable
private fun ColumnScope.InviteSheet(view: WorkspaceView, cloud: Cloud) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var email by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("member") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var done by remember { mutableStateOf(false) }
    val roles = if (view.role == "owner") listOf("member", "admin", "owner") else listOf("member", "admin")
    val valid = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(email.trim())
    SheetGrab()
    SheetHead("邀请成员")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (done) {
            Text("已邀请 ${email.trim()}。对方用这个邮箱登录 ember 就能看到邀请并加入。", fontSize = 14.sp, color = C.ink)
            Row(Modifier.fillMaxWidth().padding(bottom = 24.dp), horizontalArrangement = Arrangement.End) { Button("完成", primary = true) { app.sheet = null } }
            return@Column
        }
        Text("对方用这个邮箱登录 ember，就会看到加入「${view.name}」的邀请。邀请 7 天内有效。", fontSize = 14.sp, color = C.muted)
        Text("邮箱", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Field(email, { email = it }, "name@example.com")
        Text("角色", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        roles.forEach { r -> PickRow(ROLE_LABEL[r] ?: r, ROLE_HINT[r], checked = role == r) { role = r } }
        error?.let { Text(it, fontSize = 13.sp, color = C.red) }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("取消", primary = false) { app.sheet = null }
            Button("邀请", primary = true, busy = busy, enabled = valid) {
                busy = true; error = null
                scope.launch { try { cloud.invite(view.id, role, email.trim()); done = true } catch (e: CoreException) { error = e.message } finally { busy = false } }
            }
        }
    }
}

// ── where the account is signed in ─────────────────────────────────────

/** The account's devices: where it is signed in to ember; one not recognised can be signed out from here. */
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

/** Adding a station: a name, then the command to run on that machine (which installs ember and joins it); the sheet waits for it to join. */
fun openAddStation(app: AppState, current: WorkspaceEntry, known: List<String>) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val scope = rememberCoroutineScope()
        val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
        var name by remember { mutableStateOf("") }
        var made by remember { mutableStateOf<Enrollment?>(null) }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        val joined = made?.let { stations.value?.firstOrNull { it.id !in known } }
        SheetGrab()
        SheetHead("添加 station")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val enrollment = made
            when {
                enrollment == null -> {
                    Text("station 是一台运行 ember 的机器。给它起个名字，然后在那台机器的终端里执行生成的一行命令，它会装好 ember 并加入。", fontSize = 14.sp, color = C.muted)
                    Text("名字", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Field(name, { name = it }, "比如机器名：studio、mac-mini")
                    error?.let { Text(it, fontSize = 13.sp, color = C.red) }
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                        Button("取消", primary = false) { app.sheet = null }
                        Button("生成命令", primary = true, busy = busy, enabled = name.isNotBlank()) {
                            busy = true; error = null
                            scope.launch { try { made = Cloud(app.core, current.account.sub).enroll(current.workspace.id, name.trim()) } catch (e: CoreException) { error = e.message } finally { busy = false } }
                        }
                    }
                }
                joined != null -> {
                    Text("「${joined.name}」已加入，现在可以打开它了。", fontSize = 14.sp, color = C.ink)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button("完成", primary = true) { app.sheet = null } }
                }
                else -> {
                    Text("在要当 station 的机器（macOS，Apple 芯片）上打开「终端」，执行：", fontSize = 14.sp, color = C.ink)
                    CommandBox(enrollment.install)
                    Text("它会装好 ember、加入这个 workspace，并在后台一直运行（开机自动启动）。之后在电脑上的「设置 → Profile」里登录 Claude Code 或 Codex 的账号。", fontSize = 12.sp, color = C.muted)
                    Text("这台机器上已经有 ember 了", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Text("在 ember 的目录里执行下面这行，然后重启 ember：", fontSize = 12.sp, color = C.muted)
                    CommandBox("bin/${enrollment.command}")
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Spinner(10.dp); Text("等待 station 加入… 命令 1 小时内有效，只能用一次。", fontSize = 12.sp, color = C.muted)
                    }
                }
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
                confirm(app, "移除「${s.name}」？", "它会断开与 ember cloud 的连接，成员不能再从这里访问它。那台机器上的 ember 和数据不受影响，之后可以重新添加。", "移除 station", danger = true) {
                    cloud.removeStation(current.workspace.id, s.id); app.toast = "已移除 station"; app.pop()
                }
            }
        }
    }
}

/** The workspace's own page, from the switcher. */
fun openWorkspacePage(app: AppState) {
    app.push(Screen.Workspace)
}
