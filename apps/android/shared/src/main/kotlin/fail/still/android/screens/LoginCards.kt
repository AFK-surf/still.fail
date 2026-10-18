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
import androidx.compose.foundation.layout.Arrangement
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
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SMOOTH_SCALE
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Smooth
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
/** Its buttons: pills this high. */
private val PILL = 28.dp
/** The card's corner as Smooth takes it: a pill's half and the padding, drawn (a quarter larger) round the pills. */
private val CARD_CORNER: Dp = (CARD_PAD + PILL / 2) / SMOOTH_SCALE

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
        Text(login.title, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, color = C.ink, modifier = Modifier.padding(start = TEXT_IN, end = TEXT_IN, top = TEXT_IN))
        if (view?.canLogin == true) ActiveCard(app, station, login, view.canRelay)
        else Said(login.statusText, Modifier.padding(bottom = TEXT_IN))
    }
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
 * command or it is starting, how it stands), then one row of buttons: the step's own first (filled), 取消 beside it
 * (plain: a ground only while pressed).
 */
@Composable
private fun ActiveCard(app: AppState, station: String, login: MachineLoginShown, canRelay: Boolean) {
    val context = LocalContext.current
    val step = if (login.waiting) null else login.step
    val opening = app.isDoing("machineLogin.open", "station" to station, "id" to login.id)
    val cancelling = app.isDoing("machineLogin.cancel", "station" to station, "id" to login.id)
    val domain = login.domain?.let { t("web-main.logins.domain", "domain" to it) }
    var main: (@Composable () -> Unit)? = null
    when {
        step == "device" && login.code != null -> {
            Said(t("web-main.logins.device", "domain" to (login.domain ?: "")))
            CardCode(app, login.code)
            // One press (用户定: not two buttons): the code copied first, then its page; the code stays on show for a
            // clipboard that refused it.
            main = { Pill(t("web-main.logins.copyOpen"), filled = true) { copy(context, login.code); (login.codeUrl ?: login.url)?.let { LoginPages.open(context, it) } } }
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
            main = { Pill(if (login.listening) t("web-main.logins.openAgain") else t("web-main.logins.signIn"), filled = true, busy = opening) { relay(app, context, station, login) } }
        }
        step == "open" && login.url != null -> {
            domain?.let { Said(it) }
            main = { Pill(t("web-main.logins.signIn"), filled = true) { LoginPages.open(context, login.url) } }
        }
        else -> Said(login.statusText, busy = true)
    }
    Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        main?.invoke()
        Pill(t("common.cancel"), filled = false, busy = cancelling) {
            app.act(t("web-main.logins.cancelWhat")) { app.api(station).cancelMachineLogin(login.id) }
        }
    }
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

/** One of the card's buttons, a pill: the step's own filled (the accent's tint), 取消 plain. */
@Composable
private fun Pill(label: String, filled: Boolean, busy: Boolean = false, onClick: () -> Unit) {
    val ink = if (filled) C.accentInk else C.ink
    Row(
        Modifier.height(PILL).clip(Smooth(PILL / 2)).background(if (filled) C.accentBg else Color.Transparent)
            .clickable(enabled = !busy, interactionSource = remember { MutableInteractionSource() }, indication = ripple(color = ink), onClick = onClick)
            .alpha(if (busy) 0.6f else 1f).padding(horizontal = TEXT_IN),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (busy) Spinner(inline = true, color = ink)
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = ink, maxLines = 1)
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
            ListRow {
                Column(Modifier.weight(1f).let { if (l.id == marked) it.background(C.accent.copy(alpha = 0.12f)) else it }) {
                    Text(l.command, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(said, fontSize = 13.sp, color = if (l.state == "failed") C.red else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
    Text(t("web-main.logins.lead"), fontSize = 13.sp, lineHeight = 19.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 4.dp))
}
