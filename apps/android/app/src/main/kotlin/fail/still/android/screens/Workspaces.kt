// Workspaces, as still.fail cloud's pages have them (web/src/cloud/CloudApp.tsx,
// workspace.tsx): straight into one; for an account with none, its invitations
// or a new workspace of its own (with an invite code when still.fail cloud asks for
// one); the switcher with the invitations waiting, every account's workspaces
// and a new one.
package fail.still.android.screens

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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.data.Account
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.Cloud
import fail.still.android.data.PendingInvitation
import fail.still.android.data.ROLE_LABEL
import fail.still.android.data.Topics
import fail.still.android.data.errorText
import fail.still.android.data.needsInviteCode
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Illustration
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.core.CoreException
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
 * own is made only when asked for (with the invite code still.fail cloud wants, once it asks for one).
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
                Title("still.fail 目前只对受邀的人开放")
                Lead("有邀请码的话填在下面，就能建一个自己的 workspace。也可以请已经在用 still.fail 的人把 ${first.email} 邀请进他们的 workspace。")
                InviteCodeForm(create, make)
                Button("换一个账号", primary = false) { scope.launch { signIn(app, context) } }
            }
            else -> {
                Title("你还不在任何 workspace 里")
                Lead("可以请已经在用 still.fail 的人把 ${first.email} 邀请进他们的 workspace，也可以自己建一个。")
                Button("建一个 workspace", primary = true, busy = create.busy) { make("") }
                create.error?.let { Error(errorText(it)) }
                Button("用邀请链接加入", primary = false) { openInviteLink(app) }
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

/** A line to type in, on a soft frame; `lines` above one: a few lines, of any length (a pasted list). */
@Composable
internal fun Field(value: String, onChange: (String) -> Unit, placeholder: String, mono: Boolean = false, modifier: Modifier = Modifier, lines: Int = 1) {
    Box(
        modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        if (value.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, fontFamily = if (mono) FontFamily.Monospace else null)
        BasicTextField(
            value, { onChange(if (lines > 1) it else it.take(if (mono) 32 else 80)) }, singleLine = lines == 1, minLines = lines, cursorBrush = SolidColor(C.accent),
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

/**
 * The workspace sheet, opened from its name on Home (web/src/mobile/Workspaces.tsx): the one in use on top as a card (its
 * settings open from it), the invitations waiting, the others to switch to (with more than one account signed in, whose
 * each is under its name; what it holds at the row's end), a new one, and joining by an invitation's link.
 */
@Composable
private fun ColumnScope.WorkspacesSheet(app: AppState) {
    val all by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    val byAccount = all.value.orEmpty()
    val respond = remember { Write() }
    val pending = byAccount.flatMap { a -> a.invitations.map { a.account to it } }
    val currentOf = byAccount.firstOrNull { a -> a.workspaces.any { it.id == app.workspace } }
    val current = currentOf?.workspaces?.firstOrNull { it.id == app.workspace }
    val others = byAccount.flatMap { a -> a.workspaces.filter { it.id != app.workspace }.map { a.account to it } }
    SheetGrab()
    SheetHead("Workspace")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        // The workspace in use first, as what the sheet is about: its settings open from it, not from a row among the others.
        if (current != null) Row(
            Modifier.padding(start = 12.dp, end = 12.dp, bottom = 8.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.ink.copy(alpha = 0.05f))
                .clickable { openWorkspacePage(app) }.padding(start = 16.dp, end = 14.dp, top = 14.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(current.name, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("你是${ROLE_LABEL[current.role] ?: current.role} · ${current.stations} 台 station · ${current.members} 人", fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (byAccount.size > 1) Text(currentOf.account.email, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("设置", fontSize = 14.sp, color = C.muted)
                IconIn(Icons.ChevronRight, 14.dp, C.muted)
            }
        }
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
        if (others.isNotEmpty()) Label("切换到")
        others.forEach { (account, w) ->
            AsideRow(w.name, if (byAccount.size > 1) account.email else null, "${w.stations} 台 station", "${w.members} 人") { app.pickWorkspace(w.id); app.home() }
        }
        PickRow("＋ 新建 workspace", color = C.accent) { openNewWorkspace(app) }
        PickRow("＋ 用邀请链接加入", color = C.accent) { openInviteLink(app) }
    }
}

/** A row of the sheet with two short notes at its end, each by one of its lines (the name, and whose it is). */
@Composable
private fun AsideRow(label: String, sub: String?, first: String, second: String, onClick: () -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(label, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alignByBaseline())
            Text(first, fontSize = 12.sp, color = C.muted, maxLines = 1, modifier = Modifier.alignByBaseline())
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(sub ?: "", fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alignByBaseline())
            Text(second, fontSize = 12.sp, color = C.muted, maxLines = 1, modifier = Modifier.alignByBaseline())
        }
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
    // Sent every time: still.fail cloud looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
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
            else Text("still.fail 目前只对受邀的人开放：这个账号还没被邀请进任何 workspace，新建需要一个邀请码。", fontSize = 12.sp, color = C.muted)
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

// ── an invitation's link ───────────────────────────────────────────────

/** The token of an invitation's link (`<cloud>/invite#<token>`), or what was pasted when it is a token by itself. */
fun invitationToken(text: String): String? {
    val t = text.trim()
    if (t.isEmpty()) return null
    val hash = t.substringAfter("/invite#", "")
    return (hash.ifEmpty { if (t.contains('/') || t.contains(' ')) "" else t }).trim().ifEmpty { null }
}

/** Joining by an invitation's link: pasted here, then what it leads to is shown before it is accepted (as the web's /invite). */
fun openInviteLink(app: AppState) {
    app.sheet = SheetSpec(0.5f) { InviteLinkSheet(app, null) }
}

/** An invitation's link opened in the app: what it leads to, before it is accepted. */
fun openInvite(app: AppState, token: String) {
    app.sheet = SheetSpec(0.5f) { InviteLinkSheet(app, token) }
}

@Composable
private fun ColumnScope.InviteLinkSheet(app: AppState, given: String?) {
    val accounts by rememberTopic<List<Account>>(app.core, Topics.accounts)
    val list = accounts.value.orEmpty()
    var text by remember { mutableStateOf("") }
    var token by remember { mutableStateOf(given) }
    var chosen by remember { mutableStateOf<String?>(null) }
    val sub = chosen?.takeIf { c -> list.any { it.sub == c } } ?: list.firstOrNull()?.sub
    // Read once per account: what the link leads to depends on who looks.
    var preview by remember { mutableStateOf<fail.still.android.data.InvitationPreview?>(null) }
    var failed by remember { mutableStateOf<String?>(null) }
    val accept = remember { Write() }
    androidx.compose.runtime.LaunchedEffect(token, sub) {
        preview = null; failed = null
        val t = token ?: return@LaunchedEffect
        if (sub == null) return@LaunchedEffect
        try { preview = Cloud(app.core, sub).previewInvitation(t) } catch (e: CoreException) { failed = e.message }
    }
    SheetGrab()
    // Signed out: nothing reads the invitation yet (as the web's /invite: sign in first, then decide).
    if (accounts.value != null && list.isEmpty()) {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        SheetHead("登录 still.fail")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("你收到了一个 still.fail workspace 的邀请。先用 Google 账号登录，再决定是否加入。", fontSize = 14.sp, color = C.muted)
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button("使用 Google 账号登录", primary = true) { scope.launch { signIn(app, context) } }
            }
        }
        return
    }
    val p = preview
    SheetHead(if (token == null) "用邀请链接加入" else if (p != null) "加入「${p.name}」" else if (failed != null) "邀请不能用" else "正在读取邀请…")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val t = token
        when {
            t == null -> {
                Text("把收到的 still.fail 邀请链接粘贴在下面，先看看是哪个 workspace，再决定是否加入。", fontSize = 14.sp, color = C.muted)
                Field(text, { text = it }, "https://app.still.fail/invite#…", lines = 2)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    Button("取消", primary = false) { app.sheet = null }
                    Button("查看邀请", primary = true, enabled = invitationToken(text) != null) { token = invitationToken(text) }
                }
            }
            failed != null -> {
                Text(failed ?: "", fontSize = 14.sp, color = C.muted)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    if (given == null) Button("换一个链接", primary = false) { token = null }
                    Button("关闭", primary = true) { app.sheet = null }
                }
            }
            p == null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { Spinner(13.dp); Text("正在读取…", fontSize = 14.sp, color = C.muted) }
            else -> {
                Text("${p.inviter.ifEmpty { "有人" }}邀请你以${ROLE_LABEL[p.role] ?: p.role}身份加入。" + (p.email?.let { "这个邀请只能由 $it 接受。" } ?: ""), fontSize = 14.sp, color = C.muted)
                if (list.size > 1) {
                    Label0("用哪个账号加入")
                    Column { list.forEach { a -> PickRow(a.email, checked = a.sub == sub) { chosen = a.sub } } }
                }
                accept.error?.let { Error(it.message) }
                Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    Button("取消", primary = false) { app.sheet = null }
                    Button("以 ${list.firstOrNull { it.sub == sub }?.email ?: ""} 加入", primary = true, busy = accept.busy, enabled = sub != null) {
                        app.run(accept) {
                            val id = Cloud(app.core, sub!!).acceptInvitationToken(t)
                            app.pickWorkspace(id); app.home(); app.toast = "已加入「${p.name}」"
                        }
                    }
                }
            }
        }
    }
}
