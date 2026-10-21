// Logging a station in to the command-line tools its agents use (docs/remote-login.md), on the phone: an agent starts
// the login and answers the command's questions; the person only does the step that needs them, in the browser here
// (a Custom Tab). The login card is all of it (no sheet, no second layer), as the web's (web/src/MachineLogins.tsx
// LoginCard): in a chat under the agent's message and on 奏 (Decisions.kt), and on the station page's 登录 while it is
// under way (Stations.kt StationLogins). What it shows is the core's (`machineLogins`, `machineLogin`); what is done goes
// through its calls, under way on its button (app.isDoing), a failure said by a toast.
//
// A device code's page and a page to open go straight to the browser. A loopback login's needs this phone to take the
// browser's callback back to the station: the core listens on the callback's port (`machineLogin.open`, the listener
// Kotlin's, :core Loopback.kt), the app holds itself up meanwhile (AppHooks.relaying: :app LoginRelay.kt), then the page
// opens; the port taken here, the card says so (the core's `relayText`) and nothing opens.
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.ripple
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import fail.still.android.AppHooks
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.data.MachineLoginShown
import fail.still.android.data.MachineLoginsView
import fail.still.android.data.Topics
import fail.still.android.data.errorText
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.CodeFont
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Smooth
import fail.still.android.ui.concentric
import fail.still.android.ui.Spinner
import fail.still.android.ui.chatSubtle
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Where the card's buttons stand from its edges (its corner theirs and this together, concentric). */
private val CARD_PAD = 8.dp
/** Its words in by a button's own padding more, in line with the buttons' words. */
private val TEXT_IN = 10.dp
/** Its × and what its corner is taken from: pills this high. */
private val PILL = 28.dp
/**
 * The card's corner: a pill's half and the padding, as the web's pillInner (align.ts) and a decision's number in its row
 * (SettingParts.kt NUMBER_IN). Smooth draws it a quarter larger and squarer, so it clears the pill's round end; taken a
 * quarter smaller it cut into it, a crescent beside the pill.
 */
private val CARD_CORNER: Dp = CARD_PAD + PILL / 2

/** How long a marked card follows the page moving it, once shown (ns). */
private const val MARKED_FOLLOW_NS = 2_000_000_000L

/** Where a login card's login is: the chat's station, or another of its workspace (the card's `station`, its key). */
fun loginStation(chatStation: String, cardStation: String?): String =
    if (cardStation.isNullOrEmpty()) chatStation else "${chatStation.substringBefore('/')}/$cardStation"

/** Where a login's page opens: a Custom Tab (a test puts what records it in its place). */
object LoginPages {
    @Volatile var open: (Context, String) -> Unit = ::openLoginPage
}

/** A page of a login, in a Custom Tab (the system's browser where there is none that takes one). */
fun openLoginPage(context: Context, url: String) {
    try {
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri())
    } catch (_: Exception) {
        context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, url.toUri()).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** The code on the clipboard: why not, when it could not be. */
private fun copy(context: Context, code: String): Throwable? = runCatching {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", code))
}.exceptionOrNull()

/**
 * A login, as a card (in a chat under the agent's message, on 奏, on the station page while under way): its title, then
 * what the person does now (a code with 复制并打开; 在浏览器里登录), or how it stands (its agent answering the command),
 * and 取消. Ended, it is a line saying how (done, failed and why, cancelled and by whom). Pressing it elsewhere does
 * nothing. A login the core does not know (ended long ago) draws nothing: the message's words say it. `marked`: the one
 * a link pointed to, brought into view.
 */
@Composable
fun LoginCard(station: String, id: String, modifier: Modifier = Modifier, marked: Boolean = false) {
    val app = LocalApp.current
    val topic by rememberTopic<MachineLoginShown?>(app.core, Topics.machineLogin(station, id))
    val all by rememberTopic<MachineLoginsView>(app.core, Topics.machineLogins(station))
    val login = topic.value ?: return
    val into = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()
    // Brought into view whole, and again as what is above it on the page comes in and moves it (the station's figures,
    // its screens), for a moment after it is shown (not after: the person scrolls on their own then).
    val shownAt = remember { System.nanoTime() }
    // With room under it for the system's navigation bar (the page scrolls on under it) and a little more.
    val density = LocalDensity.current
    val below = WindowInsets.navigationBars.getBottom(density) + with(density) { 16.dp.toPx() }
    var size by remember { mutableStateOf(IntSize.Zero) }
    fun bring() = scope.launch { into.bringIntoView(Rect(0f, 0f, size.width.toFloat(), size.height + below)) }
    LaunchedEffect(marked) { if (marked) { withFrameNanos {}; bring() } }
    val follow = if (marked) Modifier.onGloballyPositioned { size = it.size; if (System.nanoTime() - shownAt < MARKED_FOLLOW_NS) bring() } else Modifier
    // Ended: one quiet line, as an answered decision's (已在 studio 上登录 gh), failed in red; no card.
    if (!login.active) {
        Text(
            login.endedText ?: "${login.title} · ${login.statusText}", fontSize = 13.sp, lineHeight = 19.sp,
            color = if (login.state == "failed") C.red else chatSubtle(),
            modifier = modifier.padding(top = 2.dp).bringIntoViewRequester(into).then(follow).testTag("login-ended"),
        )
        return
    }
    val view = all.value
    Column(
        modifier.padding(top = 6.dp).widthIn(min = 280.dp).clip(Smooth(CARD_CORNER))
            .background(if (marked) C.accent.copy(alpha = 0.12f) else C.chip).padding(CARD_PAD)
            .bringIntoViewRequester(into).then(follow).testTag("login-card"),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        if (view?.canLogin == true) {
            // Its title, with 取消 as its × in the card's top corner (on its padding, concentric with its corner).
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Title(login.title, Modifier.weight(1f))
                CancelLogin(app, station, login.id)
            }
            ActiveCard(app, station, login, view.canRelay)
        } else {
            Title(login.title)
            Said(login.statusText, Modifier.padding(bottom = TEXT_IN))
        }
    }
}

@Composable
private fun Title(title: String, modifier: Modifier = Modifier) =
    Text(title, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, color = C.ink, modifier = modifier.padding(start = TEXT_IN, end = TEXT_IN, top = TEXT_IN))

/** 取消, as the card's ×: a pill's size, round, in its top corner. */
@Composable
private fun CancelLogin(app: AppState, station: String, id: String) {
    val cancelling = app.isDoing("machineLogin.cancel", "station" to station, "id" to id)
    val label = t("web-main.logins.cancelWhat")
    Box(
        Modifier.size(PILL).clip(CircleShape)
            .clickable(enabled = !cancelling, interactionSource = remember { MutableInteractionSource() }, indication = ripple(color = C.ink)) {
                app.act(label) { app.api(station).cancelMachineLogin(id) }
            }
            .semantics { contentDescription = label; role = Role.Button }.testTag("login-cancel"),
        contentAlignment = Alignment.Center,
    ) { if (cancelling) Spinner(inline = true) else IconIn(Icons.Close, 14.dp, C.muted) }
}

/** A line of how it stands or what to do, grey (red: what is off), in by the card's words' room. */
@Composable
private fun Said(words: String, modifier: Modifier = Modifier, red: Boolean = false, busy: Boolean = false) {
    Row(modifier.padding(horizontal = TEXT_IN), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (busy) Spinner(inline = true)
        Text(words, fontSize = 13.sp, lineHeight = 19.sp, color = if (red) C.red else C.muted)
    }
}

/**
 * A login under way, for one who may finish it: what the person does now, by its step (or, while its agent answers the
 * command or it is starting, how it stands), then the step's own button (filled). 取消 is the card's ×. One whose page
 * gives a code to paste back is its own (PasteSteps).
 */
@Composable
private fun ActiveCard(app: AppState, station: String, login: MachineLoginShown, canRelay: Boolean) {
    val context = LocalContext.current
    if (login.paste == true && login.url != null) return PasteSteps(app, station, login)
    // Checking what came back (the browser's callback): nothing left for the person but to wait.
    val step = if (login.waiting || login.state == "verifying") null else login.step
    val opening = app.isDoing("machineLogin.open", "station" to station, "id" to login.id)
    val domain = login.domain?.let { t("web-main.logins.domain", "domain" to it) }
    // Its one button solid while it is the thing to do, a plain grey one once pressed here (as a pasted code's steps).
    var pressed by remember(login.id) { mutableStateOf(false) }
    var main: (@Composable () -> Unit)? = null
    when {
        step == "device" && login.code != null -> {
            Said(t("web-main.logins.device", "domain" to (login.domain ?: "")))
            CardCode(app, login.code)
            // One press (用户定: not two buttons): the code copied first, then its page; the code stays on show for a
            // clipboard that refused it.
            main = { StepButton(t("web-main.logins.copyOpen"), solid = !pressed) { pressed = true; copy(context, login.code); (login.codeUrl ?: login.url)?.let { LoginPages.open(context, it) } } }
        }
        step == "loopback" && !canRelay -> {
            Said(t("web-main.logins.needsDesktop"))
            domain?.let { Said(it) }
        }
        step == "loopback" -> {
            when {
                login.listening -> Said(t("web-main.logins.waitingBrowser"), busy = true)
                login.relayText != null -> { Said(login.relayText, red = true); domain?.let { Said(it) } }
                else -> domain?.let { Said(it) }
            }
            main = { StepButton(if (login.listening) t("web-main.logins.openAgain") else t("web-main.logins.signIn"), solid = !login.listening, busy = opening) { relay(app, context, station, login) } }
        }
        step == "open" && login.url != null -> {
            domain?.let { Said(it) }
            main = { StepButton(t("web-main.logins.signIn"), solid = !pressed) { pressed = true; LoginPages.open(context, login.url) } }
        }
        else -> Said(login.statusText, busy = true)
    }
    main?.invoke()
}

/**
 * A loopback login's browser, on this phone: the core listens for the browser's callback first, the app held up while it
 * does (the browser in front, or the app a sign-in sends one to), then the page opens. This phone's port taken: said on
 * the card (`relayText`), nothing opened, no toast.
 */
private fun relay(app: AppState, context: Context, station: String, login: MachineLoginShown) {
    app.scope.launch {
        try {
            val answer = app.core.call("machineLogin.open", buildJsonObject { put("station", station); put("id", login.id); put("here", false) })
            val url = answer.jsonObject["url"]?.jsonPrimitive?.content ?: return@launch
            AppHooks.relaying(login.title)
            LoginPages.open(context, url)
        } catch (e: CoreException) {
            if (e.code != "port_taken") app.toast = t("android-misc.act.failed", "what" to t("web-main.logins.openWhat"), "error" to errorText(e))
        }
    }
}

/** The device code, large enough to read and copy by eye; pressed, it is copied (nothing opened), a toast says so. */
@Composable
private fun CardCode(app: AppState, code: String) {
    val context = LocalContext.current
    val label = "${t("web-main.logins.copyCode")} $code"
    Text(
        code, fontFamily = CodeFont, fontSize = 22.sp, lineHeight = 29.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.08.em, color = C.ink,
        modifier = Modifier
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                val failed = copy(context, code)
                app.toast = if (failed == null) t("web-main.logins.codeCopied") else t("android-misc.act.failed", "what" to t("web-main.logins.copyCodeWhat"), "error" to (failed.message ?: failed.toString()))
            }
            .semantics { contentDescription = label; role = Role.Button }
            .padding(horizontal = TEXT_IN, vertical = 4.dp).testTag("login-code"),
    )
}

/**
 * A login whose page gives a code to paste back (Devin's, gcloud --no-launch-browser's), as the web's PasteSteps: one
 * line saying where to sign in and what to bring back, then its two steps in the order they are done, each a row of its
 * own (用户定: B, the page's button not in the field), the eye led by which is next: 打开登录页 filled until it has been
 * pressed here (or a code is in), then quiet; the field under it, 完成 in its end once a code is in (the keyboard's Done
 * too). Sent, the code stays and 完成 turns while it is checked (正在确认登录), nothing moving, until the login ends.
 */
@Composable
private fun PasteSteps(app: AppState, station: String, login: MachineLoginShown) {
    val context = LocalContext.current
    var opened by remember(login.id) { mutableStateOf(false) }
    val sending = app.isDoing("machineLogin.answer", "station" to station, "id" to login.id)
    val checking = login.state == "verifying"
    // Checked: said here, its spinner where 完成 was pressed.
    Said(if (checking) login.statusText else login.domain?.let { t("web-main.logins.pasteLead", "domain" to it) } ?: login.statusText)
    var typed by remember(login.id) { mutableStateOf(false) }
    StepButton(t("web-main.logins.openPage"), solid = !opened && !typed && !sending && !checking, external = true, modifier = Modifier.testTag("login-paste-open")) {
        opened = true; LoginPages.open(context, login.url!!)
    }
    CodeField(t("web-main.logins.pasteCode"), busy = sending || checking, onTyped = { typed = it }) { text ->
        app.act(t("web-main.logins.answerWhat")) { app.api(station).answerMachineLogin(login.id, text) }
    }
}

/** A step's row: a thumb's height, its corners a card's (CARD_PAD in, at its foot concentric with it). */
val STEP_HEIGHT = 44.dp
val STEP_CORNER = concentric(CARD_CORNER, CARD_PAD)

/**
 * A sign-in's step to press (its page, a code copied and its page): the card's width, solid (as the app's primary
 * buttons, Controls.kt Button) while it is the next thing to do, a plain grey one once it has been (the eye on to what
 * follows). The login cards' and a profile's sign-in's (Profiles.kt LoginSteps) alike.
 */
@Composable
fun StepButton(label: String, solid: Boolean, busy: Boolean = false, external: Boolean = false, corner: Dp = STEP_CORNER, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val ink = if (solid) C.bg else C.ink
    Row(
        modifier.fillMaxWidth().padding(top = 8.dp).height(STEP_HEIGHT).clip(Smooth(corner)).background(if (solid) C.ink else C.ink.copy(alpha = 0.06f))
            .clickable(enabled = !busy, interactionSource = remember { MutableInteractionSource() }, indication = ripple(color = ink), onClick = onClick),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        if (busy) Spinner(inline = true, color = ink)
        Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = ink, maxLines = 1)
        if (external) IconIn(Icons.ArrowUpRight, 16.dp, ink)
    }
}

/**
 * What a sign-in's page gave (a code), pasted back: a field the card's width, 完成 in its end once a code is in (solid:
 * the next thing to do then; the keyboard's Done too). `busy`: sent and being checked, the code kept (read-only) and 完成
 * turning in place, nothing moving. `onTyped`: whether a code is in, for the step above it to step back. `ground`: its own,
 * apart from what it sits on (paper on a grey card, grey on a white one); `corner`: concentric with that card's.
 */
@Composable
fun CodeField(placeholder: String, busy: Boolean, finish: String = t("web-main.logins.finish"), ground: Color = C.surface, corner: Dp = STEP_CORNER,
              onTyped: (Boolean) -> Unit = {}, send: (String) -> Unit) {
    var code by remember { mutableStateOf("") }
    val typed = code.isNotBlank()
    fun go() { if (typed && !busy) send(code.trim()) }
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp).height(STEP_HEIGHT).clip(Smooth(corner)).background(ground).padding(start = 14.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (code.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            BasicTextField(
                code, { if (!busy) { code = it.take(2_000); onTyped(code.isNotBlank()) } }, singleLine = true, readOnly = busy, cursorBrush = SolidColor(C.accent),
                textStyle = TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = CodeFont),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { go() }),
                modifier = Modifier.fillMaxWidth().testTag("login-paste"),
            )
        }
        // In the field's end, concentric with it (6 in); turning while it is checked, as wide as before.
        if (typed || busy) Box(
            Modifier.height(STEP_HEIGHT - 12.dp).clip(Smooth(corner - 6.dp)).background(C.ink)
                .clickable(enabled = !busy, interactionSource = remember { MutableInteractionSource() }, indication = ripple(color = C.bg)) { go() }
                .padding(horizontal = 14.dp).testTag("login-paste-go"),
            contentAlignment = Alignment.Center,
        ) {
            Text(finish, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.bg, maxLines = 1, modifier = Modifier.alpha(if (busy) 0f else 1f))
            if (busy) Spinner(inline = true, color = C.bg)
        }
    }
}

// ── the station page ──

/**
 * A station page's 登录 (docs/remote-login.md), as the narrow web's (web/src/mobile/Stations.tsx Logins): only the logins
 * done there through still.fail. Agents start them (用户定: nobody types a command); one under way is its card, as in its
 * chat; one ended a row saying how it ended, which chat's agent started it and who ended it. Nothing at all when there
 * are none (or the station is from before them). `marked`: the login a link pointed to, brought into view.
 */
@Composable
fun StationLogins(station: String, marked: String? = null) {
    val app = LocalApp.current
    val topic by rememberTopic<MachineLoginsView>(app.core, Topics.machineLogins(station))
    val view = topic.value ?: return
    if (!view.supported || view.logins.isEmpty()) return
    val active = view.logins.filter { it.active }
    val past = view.logins.filter { !it.active }
    SectionHeader(t("web-main.logins.title"), start = 24.dp)
    if (active.isNotEmpty()) Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        active.forEach { l -> LoginCard(station, l.id, Modifier.fillMaxWidth(), marked = l.id == marked) }
    }
    if (past.isNotEmpty()) ListCard {
        past.forEach { l ->
            val said = listOfNotNull(l.chatTitle?.let { t("web-main.logins.startedIn", "chat" to it) }, l.doneByText, l.whenText.takeIf { it.isNotEmpty() }, if (l.doneByText != null) null else l.statusText).joinToString(" · ")
            ListRow(ground = if (l.id == marked) C.accent.copy(alpha = 0.12f) else Color.Transparent) {
                Column(Modifier.weight(1f)) {
                    Text(l.command, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(said, fontSize = 13.sp, color = if (l.state == "failed") C.red else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
    Text(t("web-main.logins.lead"), fontSize = 13.sp, lineHeight = 19.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 4.dp))
}
