// Workspaces, as ember cloud's pages have them (web/src/cloud/CloudApp.tsx,
// workspace.tsx): straight into one; for an account with none, its invitations
// or a new workspace of its own (with an invite code when ember cloud asks for
// one); the switcher with the invitations waiting, every account's workspaces
// and a new one.
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.R
import dev.ember.android.data.Account
import dev.ember.android.data.AccountWorkspaces
import dev.ember.android.data.Cloud
import dev.ember.android.data.PendingInvitation
import dev.ember.android.data.ROLE_LABEL
import dev.ember.android.data.Topics
import dev.ember.android.data.errorText
import dev.ember.android.data.needsInviteCode
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.Avatar
import dev.ember.android.ui.C
import dev.ember.android.ui.Illustration
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.core.CoreException
import kotlinx.coroutines.launch

/** A write behind a button: whether it runs, and how the last try ended. */
private class Write {
    var busy by mutableStateOf(false)
    var error by mutableStateOf<CoreException?>(null)
    /** What the running (or last) try was given. */
    var arg by mutableStateOf<String?>(null)
    var done by mutableStateOf(false)
}

/** Runs `write` for a button: busy while it runs, its error kept until the next try. */
private fun AppState.run(w: Write, arg: String? = null, write: suspend () -> Unit) {
    w.busy = true; w.error = null; w.arg = arg; w.done = false
    scope.launch {
        try { write(); w.done = true } catch (e: CoreException) { w.error = e } finally { w.busy = false }
    }
}

/** The workspace an invitation's acceptance joined becomes the one in view. */
private suspend fun AppState.join(account: Account, invite: PendingInvitation) {
    pickWorkspace(Cloud(core, account.sub).acceptInvitation(invite.id))
    home()
}

/**
 * Signed in, with no workspace yet: the invitations waiting, or, with none, said so; a workspace of the first account's
 * own is made only when asked for (with the invite code ember cloud wants, once it asks for one).
 */
@Composable
fun Landing(accounts: List<Account>, workspaces: List<AccountWorkspaces>) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val first = accounts.first()
    val create = remember { Write() }
    val accept = remember { Write() }
    val pending = workspaces.flatMap { a -> a.invitations.map { a.account to it } }
    val make = { code: String -> app.run(create, code) { app.pickWorkspace(Cloud(app.core, first.sub).createWorkspace("${first.name.ifEmpty { first.email.substringBefore('@') }} 的 workspace", code)) } }
    // Once asked for a code, the form stays while a code is tried, rather than flicking to "creating…".
    var asked by remember { mutableStateOf(false) }
    if (needsInviteCode(create.error)) asked = true
    val asking = asked && !create.done
    Column(
        Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.ime)).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Illustration(R.drawable.illus_sign_in, R.drawable.illus_sign_in_dark, 260.dp)
        when {
            pending.isNotEmpty() -> {
                Title("你收到了邀请")
                pending.forEach { (account, invite) ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface).padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(invite.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                            Text("${invite.inviter.ifEmpty { "有人" }}邀请 ${account.email} 以${ROLE_LABEL[invite.role] ?: invite.role}身份加入", fontSize = 13.sp, color = C.muted)
                        }
                        Button("加入", primary = true, busy = accept.busy && accept.arg == invite.id) { app.run(accept, invite.id) { app.join(account, invite) } }
                    }
                }
                accept.error?.let { Error(it.message) }
                if (asking) InviteCodeForm(create, make)
                else Button("不加入，建一个自己的 workspace", primary = false, busy = create.busy) { make("") }
            }
            asking -> {
                Title("ember 目前只对受邀的人开放")
                Lead("有邀请码的话填在下面，就能建一个自己的 workspace。也可以请已经在用 ember 的人把 ${first.email} 邀请进他们的 workspace。")
                InviteCodeForm(create, make)
                Button("换一个账号", primary = false) { scope.launch { signIn(app, context) } }
            }
            else -> {
                Title("你还不在任何 workspace 里")
                Lead("可以请已经在用 ember 的人把 ${first.email} 邀请进他们的 workspace，也可以自己建一个。")
                Button("建一个 workspace", primary = true, busy = create.busy) { make("") }
                create.error?.let { Error(errorText(it)) }
                Button("换一个账号", primary = false) { scope.launch { signIn(app, context) } }
            }
        }
    }
}

@Composable
private fun Title(text: String) = Text(text, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, textAlign = TextAlign.Center)

@Composable
private fun Lead(text: String) = Text(text, fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)

@Composable
private fun Error(text: String) = Text(text, fontSize = 13.sp, color = C.red)

@Composable
internal fun Button(label: String, primary: Boolean, busy: Boolean = false, enabled: Boolean = true, danger: Boolean = false, onClick: () -> Unit) {
    val on = enabled && !busy
    Row(
        Modifier.height(38.dp).clip(RoundedCornerShape(19.dp)).background(if (primary) (if (!enabled) C.line else if (danger) C.red else C.ink) else C.chip)
            .clickable(enabled = on, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (busy) CircularProgressIndicator(Modifier.size(14.dp), color = if (primary) C.bg else C.muted, strokeWidth = 1.5.dp)
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (primary && danger && enabled) Color.White else if (primary) C.bg else C.ink)
    }
}

/** A line to type in, on a soft frame. */
@Composable
internal fun Field(value: String, onChange: (String) -> Unit, placeholder: String, mono: Boolean = false, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        if (value.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, fontFamily = if (mono) FontFamily.Monospace else null)
        BasicTextField(
            value, { onChange(it.take(if (mono) 32 else 80)) }, singleLine = true, cursorBrush = SolidColor(C.accent),
            textStyle = TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = if (mono) FontFamily.Monospace else null), modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Asks for the invite code a new workspace needs; what the last try said stands under it. */
@Composable
private fun InviteCodeForm(create: Write, make: (String) -> Unit) {
    var code by remember { mutableStateOf(create.arg ?: "") }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Field(code, { code = it }, "XXXX-XXXX-XXXX", mono = true, modifier = Modifier.weight(1f))
            Button("建 workspace", primary = true, busy = create.busy, enabled = code.isNotBlank()) { make(code.trim()) }
        }
        // Nothing was wrong with a code nobody had typed yet.
        val error = create.error
        if (error != null && !create.arg.isNullOrEmpty()) Error(errorText(error))
    }
}

// ── the switcher ───────────────────────────────────────────────────────

fun openWorkspaces(app: AppState) {
    app.sheet = SheetSpec(0.7f, draggable = true) { WorkspacesSheet(app) }
}

@Composable
private fun ColumnScope.WorkspacesSheet(app: AppState) {
    val all by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    val byAccount = all.value.orEmpty()
    val respond = remember { Write() }
    val pending = byAccount.flatMap { a -> a.invitations.map { a.account to it } }
    SheetGrab()
    SheetHead("切换 workspace")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        if (pending.isNotEmpty()) {
            Label("邀请")
            pending.forEach { (account, invite) ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Column(Modifier.weight(1f)) {
                        Text("${invite.inviter.ifEmpty { "有人" }}邀请你加入「${invite.name}」", fontSize = 15.sp, color = C.ink)
                        Text(account.email, fontSize = 12.sp, color = C.muted)
                    }
                    Button("加入", primary = true, busy = respond.busy && respond.arg == "+${invite.id}") {
                        app.run(respond, "+${invite.id}") { app.join(account, invite); app.toast = "已加入「${invite.name}」" }
                    }
                    Button("忽略", primary = false, busy = respond.busy && respond.arg == "-${invite.id}") {
                        app.run(respond, "-${invite.id}") { Cloud(app.core, account.sub).declineInvitation(invite.id); app.toast = "已忽略邀请" }
                    }
                }
            }
            respond.error?.let { Box(Modifier.padding(horizontal = 20.dp)) { Error(it.message) } }
        }
        byAccount.forEach { (account, items) ->
            Row(Modifier.padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Avatar(account.email, account.name.ifEmpty { account.email }, 16.dp, picture = account.picture)
                Text(account.email, fontSize = 13.sp, color = C.muted)
            }
            if (items.isEmpty()) Text("没有 workspace", fontSize = 14.sp, color = C.subtle, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            items.forEach { w ->
                PickRow(w.name, "${w.stations} 台 station · ${w.members} 人", checked = w.id == app.workspace) { app.pickWorkspace(w.id); app.sheet = null }
            }
        }
        val current = byAccount.flatMap { it.workspaces }.firstOrNull { it.id == app.workspace }
        if (current != null) PickRow("「${current.name}」的设置", "名字、成员、退出") { openWorkspacePage(app) }
        PickRow("＋ 新建 workspace", color = C.accent) { openNewWorkspace(app) }
    }
}

@Composable
private fun Label(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 2.dp))

// ── a new workspace ────────────────────────────────────────────────────

private fun openNewWorkspace(app: AppState) {
    app.sheet = SheetSpec(0.8f) { NewWorkspaceSheet(app) }
}

@Composable
private fun ColumnScope.NewWorkspaceSheet(app: AppState) {
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val list = accounts.value.orEmpty()
    var name by remember { mutableStateOf("") }
    var owner by remember { mutableStateOf<String?>(null) }
    // Sent every time: ember cloud looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
    var code by remember { mutableStateOf("") }
    val create = remember { Write() }
    var asked by remember { mutableStateOf(false) }
    if (needsInviteCode(create.error)) asked = true
    val sub = owner?.takeIf { o -> list.any { it.sub == o } } ?: list.firstOrNull()?.sub
    val go = {
        if (name.isNotBlank() && sub != null) app.run(create) {
            val id = Cloud(app.core, sub).createWorkspace(name.trim(), code.trim())
            app.pickWorkspace(id)
            app.home()
        }
    }
    SheetGrab()
    SheetHead("新建 workspace")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("workspace 是一组人和他们共用的 station。你会成为它的 owner。", fontSize = 14.sp, color = C.muted)
        Label0("名字")
        Field(name, { name = it }, "例如：产品团队")
        if (list.size > 1) {
            Label0("属于哪个账号")
            list.forEach { a -> PickRow(a.email, checked = a.sub == sub) { owner = a.sub } }
        }
        if (asked) {
            Label0("邀请码")
            Field(code, { code = it }, "XXXX-XXXX-XXXX", mono = true)
            val error = create.error
            if (error != null && needsInviteCode(error) && code.isNotBlank()) Error(errorText(error))
            else Text("ember 目前只对受邀的人开放：这个账号还没被邀请进任何 workspace，新建需要一个邀请码。", fontSize = 12.sp, color = C.muted)
        }
        create.error?.takeIf { !needsInviteCode(it) }?.let { Error(it.message) }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("取消", primary = false) { app.sheet = null }
            Button("新建", primary = true, busy = create.busy, enabled = name.isNotBlank()) { go() }
        }
    }
}

@Composable
private fun Label0(text: String) = Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)

/** Whether invitations wait for any signed-in account: the switcher says so with a dot. */
@Composable
fun invitationsWaiting(app: AppState): Boolean {
    val all by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    return all.value.orEmpty().any { it.invitations.isNotEmpty() }
}
