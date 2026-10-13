// Workspaces, as still.fail cloud's pages have them (web/src/cloud/CloudApp.tsx,
// workspace.tsx): straight into one; for an account with none, its invitations
// or a new workspace of its own (with an invite code when still.fail cloud asks for
// one); the panel dropped from the name on Home, with the invitations waiting,
// every account's workspaces and a new one.
package fail.still.android.screens

import fail.still.android.data.t
import fail.still.android.BuildConfig
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import fail.still.android.ui.Ease
import fail.still.android.ui.MenuSpring
import fail.still.android.ui.initial
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
import fail.still.android.ui.CodeFont
import fail.still.android.ui.keyboard
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
import fail.still.android.data.Auth
import fail.still.android.data.Cloud
import fail.still.android.data.PendingInvitation
import fail.still.android.data.ROLE_LABEL
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceMark
import fail.still.android.data.WorkspaceMarksView
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
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import kotlinx.coroutines.launch

/** A write behind a button: whether it runs, and how the last try ended. */
private class Write(app: AppState) : Action(app) {
    /** What the running (or last) try was given. */
    var arg by mutableStateOf<String?>(null)
    var done by mutableStateOf(false)
}

/** Runs `write` for a button: busy while it runs, its error kept until the next try. */
private fun AppState.run(w: Write, arg: String? = null, write: suspend () -> Unit) {
    w.arg = arg; w.done = false
    w.run { write(); w.done = true }
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
    val create = remember { Write(app) }
    val accept = remember { Write(app) }
    val pending = workspaces.flatMap { a -> a.invitations.map { a.account to it } }
    val make = { code: String -> app.run(create, code) { app.pickWorkspace(Cloud(app.core, first.sub).createWorkspace(t("android-misc.workspace.defaultName", "name" to first.name.ifEmpty { first.email.substringBefore('@') }), code)) } }
    // Once asked for a code, the form stays while a code is tried, rather than flicking to "creating…".
    var asked by remember { mutableStateOf(false) }
    if (needsInviteCode(create.error)) asked = true
    val asking = asked && !create.done
    Column(
        Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.keyboard)).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Illustration(R.drawable.illus_sign_in, R.drawable.illus_sign_in_dark, 260.dp)
        when {
            pending.isNotEmpty() -> {
                Title(t("android-misc.invite.received"))
                pending.forEach { (account, invite) ->
                    Row(
                        Modifier.fillMaxWidth().clip(Smooth(16.dp)).background(C.surface).padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(invite.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                            Text(t("android-misc.invite.invitedAs", "inviter" to invite.inviter.ifEmpty { t("android-misc.invite.someone") }, "email" to account.email, "role" to (ROLE_LABEL[invite.role] ?: invite.role)), fontSize = 13.sp, color = C.muted)
                        }
                        Button(t("android-misc.invite.join"), primary = true, busy = accept.busy && accept.arg == invite.id) { app.run(accept, invite.id) { app.join(account, invite) } }
                    }
                }
                accept.error?.let { Error(it.message) }
                if (asking) InviteCodeForm(create, make)
                else Button(t("android-misc.invite.declineCreate"), primary = false, busy = create.busy) { make("") }
            }
            asking -> {
                Title(t("android-misc.invite.onlyInvited", "app" to BuildConfig.APP_NAME))
                Lead(t("android-misc.invite.codeLead", "app" to BuildConfig.APP_NAME, "email" to first.email))
                InviteCodeForm(create, make)
                Button(t("android-misc.account.switch"), primary = false, busy = app.isDoing("auth.begin")) { scope.launch { signIn(app, context) } }
            }
            else -> {
                Title(t("android-misc.workspace.none"))
                Lead(t("android-misc.workspace.none.lead", "app" to BuildConfig.APP_NAME, "email" to first.email))
                Button(t("android-misc.workspace.createOne"), primary = true, busy = create.busy) { make("") }
                create.error?.let { Error(errorText(it)) }
                Button(t("android-misc.invite.byLink"), primary = false) { openInviteLink(app) }
                Button(t("android-misc.account.switch"), primary = false, busy = app.isDoing("auth.begin")) { scope.launch { signIn(app, context) } }
            }
        }
    }
}

/** An account the beta app cannot be used with (the core's `blocked`): it signs out, or another signs in. */
@Composable
fun Blocked(entry: AccountWorkspaces) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val out = remember { Write(app) }
    Column(
        Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.systemBars).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Illustration(R.drawable.illus_sign_in, R.drawable.illus_sign_in_dark, 260.dp)
        Title(entry.blocked ?: "")
        Lead(entry.account.email)
        Button(t("android-misc.account.signOut"), primary = true, busy = out.busy) { app.run(out, entry.account.sub) { Auth.signOut(app.core, entry.account.sub) } }
        out.error?.let { Error(it.message) }
        Button(t("android-misc.account.switch"), primary = false, busy = app.isDoing("auth.begin")) { scope.launch { signIn(app, context) } }
    }
}

@Composable
private fun Title(text: String) = Text(text, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, textAlign = TextAlign.Center)

@Composable
private fun Lead(text: String) = Text(text, fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)

@Composable
private fun Error(text: String) = Text(text, fontSize = 13.sp, color = C.red)

@Composable
internal fun Button(label: String, primary: Boolean, busy: Boolean = false, enabled: Boolean = true, danger: Boolean = false, small: Boolean = false, onClick: () -> Unit) {
    val on = enabled && !busy
    // `small`: in a row of a panel (an invitation's 加入 and 忽略), 30dp tall.
    Row(
        Modifier.height(if (small) 30.dp else 38.dp).clip(RoundedCornerShape(if (small) 15.dp else 19.dp)).background(if (primary) (if (!enabled) C.line else if (danger) C.red else C.ink) else C.chip)
            .clickable(enabled = on, onClick = onClick).padding(horizontal = if (small) 12.dp else 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (small) 6.dp else 8.dp),
    ) {
        if (busy) CircularProgressIndicator(Modifier.size(if (small) 12.dp else 14.dp), color = if (primary) C.bg else C.muted, strokeWidth = 1.5.dp)
        Text(label, fontSize = if (small) 13.sp else 14.sp, fontWeight = FontWeight.SemiBold, color = if (primary && danger && enabled) Color.White else if (primary) C.bg else C.ink)
    }
}

/** A line to type in, on a soft frame; `lines` above one: a few lines, of any length (a pasted list). */
@Composable
internal fun Field(value: String, onChange: (String) -> Unit, placeholder: String, mono: Boolean = false, modifier: Modifier = Modifier, lines: Int = 1) {
    Box(
        modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.surface).border(1.dp, C.line, Smooth(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        if (value.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, fontFamily = if (mono) CodeFont else null)
        BasicTextField(
            value, { onChange(if (lines > 1) it else it.take(if (mono) 32 else 80)) }, singleLine = lines == 1, minLines = lines, cursorBrush = SolidColor(C.accent),
            textStyle = TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = if (mono) CodeFont else null), modifier = Modifier.fillMaxWidth(),
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
            Button(t("android-misc.workspace.create"), primary = true, busy = create.busy, enabled = code.isNotBlank()) { make(code.trim()) }
        }
        // Nothing was wrong with a code nobody had typed yet.
        val error = create.error
        if (error != null && !create.arg.isNullOrEmpty()) Error(errorText(error))
    }
}

// ── the switcher ───────────────────────────────────────────────────────

/**
 * The workspace panel, dropped from the name on Home (web/src/mobile/Workspaces.tsx): the invitations waiting, then
 * every account's workspaces (under its email with more than one account signed in), the one in view checked and the
 * others with what they hold; a new one and another account at its foot. A tap on one switches to it (Home slides its
 * lists over). It is the long-press menu's kind (Sheet.kt MenuHost): its ground and shadow, the scrim, the scale from
 * the corner it hangs from. `left`, `top` (px, in what holds it): the name's left edge and the bar's bottom; it hangs
 * 8dp left of the one and 4dp under the other. The workspace's settings are in 设置 (SettingsHome.kt).
 */
@Composable
internal fun WorkspacePanel(open: Boolean, current: String, left: Float, top: Float, close: () -> Unit) {
    val app = LocalApp.current
    val visible = remember { MutableTransitionState(false) }
    visible.targetState = open
    val scrim by animateFloatAsState(if (open) 1f else 0f, tween(200), label = "panel-scrim")
    // Drawn from the tap that opens it until it and its scrim have gone.
    if (!open && visible.isIdle && !visible.currentState && scrim == 0f) return
    BackHandler(enabled = open) { close() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val width = minOf(320.dp, maxWidth - 32.dp)
        val x = (with(density) { left.toDp() } - 8.dp).coerceAtMost(maxWidth - width - 12.dp).coerceAtLeast(12.dp)
        val y = with(density) { top.toDp() } + 4.dp
        val foot = with(density) { WindowInsets.navigationBars.getBottom(this).toDp() }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f * scrim)).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() })
        val corner = TransformOrigin(0f, 0f)
        AnimatedVisibility(
            visible,
            Modifier.offset(x, y),
            enter = fadeIn(tween(160, easing = Ease.Out)) + scaleIn(MenuSpring, 0.9f, corner),
            exit = fadeOut(tween(120, easing = Ease.CssOut)) + scaleOut(MenuSpring, 0.9f, corner),
        ) {
            Column(
                Modifier.width(width).heightIn(max = (maxHeight - y - foot - 24.dp).coerceAtLeast(120.dp))
                    .shadow(18.dp, Smooth(20.dp)).clip(Smooth(20.dp)).background(C.surface).padding(6.dp),
            ) { PanelContent(app, current, close) }
        }
    }
}

@Composable
private fun ColumnScope.PanelContent(app: AppState, current: String, close: () -> Unit) {
    val context = LocalContext.current
    val all by rememberTopic<List<AccountWorkspaces>>(app.core, Topics.workspaces)
    val byAccount = all.value.orEmpty()
    val respond = remember { Write(app) }
    val pending = byAccount.flatMap { a -> a.invitations.map { a.account to it } }
    // What each of the others has waiting, as the core counts it.
    val marks by rememberTopic<WorkspaceMarksView>(app.core, Topics.workspaceMarks(current))
    // One reached through two accounts is listed once, under the first (as `entries`).
    val listed = HashSet<String>()
    Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) {
        pending.forEach { (account, invite) ->
            Row(
                Modifier.padding(bottom = 4.dp).fillMaxWidth().clip(Smooth(14.dp)).background(C.accentBg).padding(horizontal = 10.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(t("android-misc.invite.invitedYou", "inviter" to invite.inviter.ifEmpty { t("android-misc.invite.someone") }, "name" to invite.name), fontSize = 14.sp, color = C.ink)
                    Text(account.email, fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Button(t("android-misc.invite.join"), primary = true, small = true, busy = respond.busy && respond.arg == "+${invite.id}") {
                    app.run(respond, "+${invite.id}") { app.join(account, invite); close(); app.toast = t("android-misc.invite.joined", "name" to invite.name) }
                }
                Button(t("android-misc.invite.ignore"), primary = false, small = true, busy = respond.busy && respond.arg == "-${invite.id}") {
                    app.run(respond, "-${invite.id}") { Cloud(app.core, account.sub).declineInvitation(invite.id); app.toast = t("android-misc.invite.ignored") }
                }
            }
        }
        respond.error?.let { Box(Modifier.padding(horizontal = 10.dp, vertical = 4.dp)) { Error(it.message) } }
        byAccount.forEach { a ->
            val workspaces = a.workspaces.filter { listed.add(it.id) }
            if (workspaces.isEmpty()) return@forEach
            // Whose they are, only when more than one account is signed in.
            if (byAccount.size > 1) Text(
                a.account.email, fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 4.dp),
            )
            workspaces.forEach { w ->
                PanelRow(w.name, w.id == current, marks.value?.workspaces?.get(w.id)) {
                    close()
                    if (w.id != current) { app.pickWorkspace(w.id); app.home() }
                }
            }
        }
    }
    // Apart from the workspaces by a little room, not a line (as the web's panel).
    Row(Modifier.padding(top = 6.dp).fillMaxWidth()) {
        FootButton(Icons.Plus, t("android-misc.workspace.new"), Modifier.weight(1f)) { close(); openNewWorkspace(app) }
        // Signing in goes on past the panel (the browser comes up over it): in the app's scope, not the panel's.
        FootButton(Icons.LogIn, t("android-misc.workspace.addAccount"), Modifier.weight(1f), busy = app.isDoing("auth.begin")) { close(); app.scope.launch { signIn(app, context) } }
    }
}

/**
 * A workspace in the panel: its first letter on a tile, its name, and what it holds (the core's counts); the one in view
 * on the chip's ground with its tile inverted and a check.
 */
@Composable
private fun PanelRow(name: String, current: Boolean, mark: WorkspaceMark?, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(Smooth(14.dp)).background(if (current) C.chip else Color.Transparent).clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(32.dp).clip(Smooth(10.dp)).background(if (current) C.ink else C.chip), contentAlignment = Alignment.Center) {
            Text(initial(name), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (current) C.bg else C.ink, modifier = Modifier.semantics { hideFromAccessibility() })
        }
        Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        if (current) IconIn(Icons.Check, 16.dp, C.ink)
        else if (mark != null) MarkCounts(mark)
    }
}

/** One of the two at the panel's foot: an icon and its words, no ground of its own. */
@Composable
private fun FootButton(icon: ImageVector, label: String, modifier: Modifier, busy: Boolean = false, onClick: () -> Unit) {
    Row(
        modifier.height(40.dp).clip(Smooth(14.dp)).clickable(enabled = !busy, onClick = onClick).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        if (busy) CircularProgressIndicator(Modifier.size(14.dp), color = C.muted, strokeWidth = 1.5.dp) else IconIn(icon, 16.dp, C.ink)
        Text(label, fontSize = 14.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

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
    val create = remember { Write(app) }
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
    SheetHead(t("android-misc.workspace.new"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(t("android-misc.workspace.new.text"), fontSize = 14.sp, color = C.muted)
        Label0(t("android-misc.workspace.name"))
        Field(name, { name = it }, t("android-misc.workspace.name.placeholder"))
        if (list.size > 1) {
            Label0(t("android-misc.workspace.account"))
            list.forEach { a -> PickRow(a.email, checked = a.sub == sub) { owner = a.sub } }
        }
        if (asked) {
            Label0(t("android-misc.invite.code"))
            Field(code, { code = it }, "XXXX-XXXX-XXXX", mono = true)
            val error = create.error
            if (error != null && needsInviteCode(error) && code.isNotBlank()) Error(errorText(error))
            else Text(t("android-misc.invite.codeNeeded", "app" to BuildConfig.APP_NAME), fontSize = 12.sp, color = C.muted)
        }
        create.error?.takeIf { !needsInviteCode(it) }?.let { Error(it.message) }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(t("android-misc.workspace.createButton"), primary = true, busy = create.busy, enabled = name.isNotBlank()) { go() }
        }
    }
}

@Composable
private fun Label0(text: String) = Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)

/** Whether invitations wait for any signed-in account: the name on Home says so with a dot. */
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
    val accept = remember { Write(app) }
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
        SheetHead(t("android-misc.signIn.title", "app" to BuildConfig.APP_NAME))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("android-misc.signIn.invited", "app" to BuildConfig.APP_NAME), fontSize = 14.sp, color = C.muted)
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(t("android-misc.signIn.google"), primary = true, busy = app.isDoing("auth.begin")) { scope.launch { signIn(app, context) } }
            }
        }
        return
    }
    val p = preview
    SheetHead(if (token == null) t("android-misc.invite.byLink") else if (p != null) t("android-misc.invite.joinNamed", "name" to p.name) else if (failed != null) t("android-misc.invite.unusable") else t("android-misc.invite.loading"))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val link = token
        when {
            link == null -> {
                Text(t("android-misc.invite.pasteLink", "app" to BuildConfig.APP_NAME), fontSize = 14.sp, color = C.muted)
                Field(text, { text = it }, "https://app.still.fail/invite#…", lines = 2)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    Button(t("common.cancel"), primary = false) { app.sheet = null }
                    Button(t("android-misc.invite.view"), primary = true, enabled = invitationToken(text) != null) { token = invitationToken(text) }
                }
            }
            failed != null -> {
                Text(failed ?: "", fontSize = 14.sp, color = C.muted)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    if (given == null) Button(t("android-misc.invite.otherLink"), primary = false) { token = null }
                    Button(t("common.close"), primary = true) { app.sheet = null }
                }
            }
            p == null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { Spinner(13.dp); Text(t("android-misc.reading"), fontSize = 14.sp, color = C.muted) }
            else -> {
                Text(t(if (p.email != null) "android-misc.invite.invitedYouAsOnly" else "android-misc.invite.invitedYouAs", "inviter" to p.inviter.ifEmpty { t("android-misc.invite.someone") }, "role" to (ROLE_LABEL[p.role] ?: p.role), "email" to p.email), fontSize = 14.sp, color = C.muted)
                if (list.size > 1) {
                    Label0(t("android-misc.invite.whichAccount"))
                    Column { list.forEach { a -> PickRow(a.email, checked = a.sub == sub) { chosen = a.sub } } }
                }
                accept.error?.let { Error(it.message) }
                Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    Button(t("common.cancel"), primary = false) { app.sheet = null }
                    Button(t("android-misc.invite.joinAs", "email" to (list.firstOrNull { it.sub == sub }?.email ?: "")), primary = true, busy = accept.busy, enabled = sub != null) {
                        app.run(accept) {
                            val id = Cloud(app.core, sub!!).acceptInvitationToken(link)
                            app.pickWorkspace(id); app.home(); app.toast = t("android-misc.invite.joined", "name" to p.name)
                        }
                    }
                }
            }
        }
    }
}
