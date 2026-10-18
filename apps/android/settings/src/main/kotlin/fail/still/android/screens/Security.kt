// The workspace's security mode (its lock, docs/workspace-lock.md), as the narrow web has it (web/src/mobile/Security.tsx):
// its page from the settings, turning it on, a new device's code shown in a bottom sheet (typed there to approve it),
// and what a device waiting itself shows (asking by hand, the code typed in). All of it is the core's (`lock`,
// `lockDraft`, `lockPrompts` topics, `lock.*`, `lockPrompt.*` calls, client/core-ts/src/views/lock.ts, views/pair.ts).
package fail.still.android.screens

import fail.still.android.ui.BusyIcon
import fail.still.android.ui.Spinner
import fail.still.android.ui.WaitLine
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting
import androidx.compose.foundation.background
import fail.still.android.ui.Smooth
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.border
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.LockDevice
import fail.still.android.data.LockDraftView
import fail.still.android.data.LockPairing
import fail.still.android.data.LockPromptsView
import fail.still.android.data.LockRequest
import fail.still.android.data.LockView
import fail.still.android.data.ROLE_LABEL
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.CodeFont
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import fail.still.android.ui.PickRow

/** A device's name as people know it: its label, or what kind of client it is. */
private fun deviceName(kind: String, label: String, older: Boolean = false): String = when {
    older -> label.ifEmpty { t("web-pages.security.olderClient") }
    label.isNotEmpty() -> label
    kind == "web" -> t("web-pages.security.webDevice")
    else -> t("web-pages.security.appDevice")
}

/** `lock.<name>` on this workspace, let go on by itself and said how it ended. */
private fun AppState.lockCall(workspace: String, name: String, what: String, done: String? = null, vararg params: Pair<String, String>) =
    act(what, done) { core.call("lock.$name", buildJsonObject { put("workspace", workspace); params.forEach { (k, v) -> put(k, v) } }) }

@Composable
internal fun Dot(on: Boolean, warn: Boolean = false) =
    Box(Modifier.size(7.dp).background(if (on) C.green else if (warn) C.warn else C.line, CircleShape))

@Composable
internal fun Para(main: String, sub: String? = null) = Column {
    Text(main, fontSize = 15.sp, lineHeight = 22.sp, color = C.ink)
    if (sub != null) Text(sub, fontSize = 15.sp, lineHeight = 22.sp, color = C.subtle)
}

@Composable
private fun Note(text: String) = Text(text, fontSize = 12.sp, lineHeight = 18.sp, color = C.subtle)

/** A main action as wide as where it is (the screen's foot, a sheet's half). */
@Composable
internal fun WideButton(label: String, primary: Boolean, modifier: Modifier = Modifier, busy: Boolean = false, enabled: Boolean = true, danger: Boolean = false, onClick: () -> Unit) {
    val on = enabled && !busy
    // `danger`: red, and faded red (not grey) until it can be pressed, so it reads as the same button.
    // The secondary one a shade of ink, not the chip colour: on a sheet's frosted paper the chip all but disappears.
    val ground = if (!primary) C.ink.copy(alpha = 0.08f) else if (danger) (if (enabled) C.red else C.red.copy(alpha = 0.4f)) else if (!enabled) C.line else C.ink
    Row(
        modifier.height(46.dp).clip(Smooth(23.dp)).background(ground).clickable(enabled = on, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        val ink = if (primary && danger) Color.White else if (primary) C.bg else C.ink
        // A solid one's spinner in its words' colour.
        BusyIcon(busy, solid = if (primary) ink else null)
        if (busy) Spacer(Modifier.width(8.dp))
        Text(label, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = ink)    }
}

/** The page's main action along the bottom of the screen, as wide as it; the page scrolls above it. */
@Composable
internal fun Foot(note: String? = null, content: @Composable () -> Unit) = Column(
    Modifier.fillMaxWidth().background(C.bg).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 16.dp, vertical = 10.dp),
    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
) {
    if (note != null) Note(note)
    content()
}

@Composable
fun SecurityScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<LockView>(app.core, Topics.lock(current.workspace.id))
    val lock = topic.value
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            TopBack(t("android-settings.title"), app::pop)
            LargeTitle("", t("web-pages.security.title"))
            when {
                lock == null -> Waiting(WaitShape.Cards, text = t("web-pages.settings.reading"), error = topic.error?.message)
                !lock.available -> ListCard { Body { Note(t("web-pages.security.unavailable")) } }
                lock.locked -> On(current, lock)
                else -> Off(lock)
            }
            Spacer(Modifier.height(30.dp))
        }
        if (lock != null && lock.available && !lock.locked && lock.owner && lock.canSign) Foot {
            WideButton(t("web-pages.security.turnOn"), primary = true, modifier = Modifier.fillMaxWidth()) { app.push(Screen.SecurityOpen) }
        }
    }
}

@Composable
private fun Off(lock: LockView) {
    ListCard { Body {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { Dot(false); Text(t("web-pages.security.off"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink) }
        Para(t("web-pages.security.now"), t("web-pages.security.nowRisk"))
        Para(t("web-pages.security.then"))
        Para(t("web-pages.security.newDevices"), t("web-pages.security.newDevicesHow"))
        if (!lock.owner) Note(t("web-pages.security.ownerOnly")) else if (!lock.canSign) Note(t("web-pages.security.webCannotSign"))
    } }
    SectionHeader(t("web-pages.security.signing"), start = 24.dp)
    ListCard { Body { Note(t("web-pages.security.signingWho")) } }
}

@Composable
private fun On(current: WorkspaceEntry, lock: LockView) {
    val app = LocalApp.current
    val ws = current.workspace.id
    ListCard { Body {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { Dot(true); Text(t("web-pages.security.on"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink) }
        Note(t("web-pages.security.onMeta", "signers" to lock.signers.toInt(), "stations" to lock.protected.toInt()))
        if (!lock.signs) Note(if (lock.canSign) t("web-pages.security.notSignerApp") else t("web-pages.security.notSignerWeb"))
    } }
    if (lock.requests.isNotEmpty()) {
        SectionHeader("${t("web-pages.security.waiting")} · ${lock.requests.size}", start = 24.dp)
        ListCard {
            lock.requests.forEach { r ->
                ListRow(onClick = if (lock.signs) ({ confirmSheet(app, ws, r) }) else null) {
                    Column(Modifier.weight(1f)) {
                        Text(t("web-pages.security.newDeviceOf", "name" to r.name.ifEmpty { r.email }), fontSize = 15.sp, color = C.ink)
                        Text("${deviceName(r.kind, r.label)} · ${r.time?.get("created_at")?.ago ?: ""}", fontSize = 13.sp, color = C.muted)
                    }
                    Text(r.code, fontFamily = CodeFont, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = C.ink)
                }
            }
        }
    }
    SectionHeader(t("web-pages.security.people"), start = 24.dp)
    ListCard {
        lock.members.forEach { m ->
            ListRow {
                Text(m.name.ifEmpty { m.email }, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                Text(ROLE_LABEL[m.role] ?: m.role, fontSize = 14.sp, color = C.subtle)
            }
            m.devices.forEach { d -> DeviceRow(ws, d, lock.signs) }
        }
    }
    SectionHeader("Station", start = 24.dp)
    ListCard {
        if (lock.stations.isEmpty()) Body { Note(t("web-pages.security.noStations")) }
        lock.stations.forEach { s ->
            val join = !s.protected && lock.owner && lock.signs
            val joining = app.isDoing("lock.joinStation", "workspace" to ws, "station" to s.id)
            ListRow(onClick = if (join && !joining) ({ joinSheet(app, ws, s.id, s.name) }) else null) {
                Dot(s.protected, warn = !s.protected)
                Column(Modifier.weight(1f)) {
                    Text(s.name, fontSize = 15.sp, color = C.ink)
                    if (!s.protected) Text(t("web-pages.security.unprotectedWhy"), fontSize = 13.sp, color = C.muted)
                }
                when {
                    s.protected -> Text(t("web-pages.security.protected"), fontSize = 13.sp, color = C.subtle)
                    joining -> Spinner()
                    join -> Text(t("web-pages.security.join"), fontSize = 14.sp, color = C.accent)
                    else -> Text(t("web-pages.security.unprotected"), fontSize = 13.sp, color = C.warn)
                }
            }
        }
    }
    SectionHeader(t("web-pages.security.webTitle"), start = 24.dp)
    ListCard { Body { Note(t("web-pages.security.webRisk")) } }
    if (lock.owner && lock.signs) {
        val turningOff = app.isDoing("lock.disable", "workspace" to ws)
        Spacer(Modifier.height(18.dp))
        ListCard {
            ListRow(onClick = if (turningOff) null else ({ turnOffSheet(app, ws, current.workspace.name) })) {
                Text(t("web-pages.security.turnOff"), fontSize = 15.sp, color = C.red, modifier = Modifier.weight(1f))
                if (turningOff) Spinner(inline = true)
            }
        }
    }
}

@Composable
private fun DeviceRow(ws: String, d: LockDevice, canRenew: Boolean) {
    val app = LocalApp.current
    val renewing = app.isDoing("lock.renew", "workspace" to ws, "device" to d.id)
    val meta = listOfNotNull(
        if (d.kind == "web") t("web-pages.security.web") else t("web-pages.security.app"),
        if (d.signs) t("web-pages.security.signs") else null,
        if (d.mine) t("web-pages.security.thisDevice") else null,
        d.daysLeft?.let { t("web-pages.security.daysLeft", "n" to it.toInt()) },
        if (d.recent) t("web-pages.security.recent") else null,
    ).joinToString(" · ")
    val renew = d.daysLeft != null && canRenew
    ListRow(onClick = if (renew && !renewing) ({ app.lockCall(ws, "renew", t("web-pages.security.renew"), t("web-pages.security.renewed"), "device" to d.id) }) else null) {
        Column(Modifier.weight(1f).padding(start = 14.dp)) {
            Text(deviceName(d.kind, d.label, d.older), fontSize = 15.sp, color = C.ink)
            Text(meta, fontSize = 13.sp, color = if (d.renewSoon) C.warn else C.muted)
        }
        if (renewing) Spinner() else if (renew) Text(t("web-pages.security.renew"), fontSize = 14.sp, color = C.accent)
    }
}

/**
 * 关闭安全模式？, as the desktop asks it (web/src/cloud/Security.tsx TurnOff): what turning it off gives up, a line each,
 * and the workspace's name typed before it can go. The core then has the system ask the person (fingerprint, the
 * screen lock) before it signs; their no says nothing.
 */
private fun turnOffSheet(app: AppState, ws: String, name: String) {
    // As tall as what it shows (grab, head, the words, the field, the buttons); the sheet rises over the keyboard itself.
    app.sheet = SheetSpec(0.7f, fit = 470.dp) {
        var typed by remember { mutableStateOf("") }
        val named = typed.trim() == name.trim()
        SheetGrab()
        SheetHead(t("web-pages.security.turnOffTitle"))
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("web-pages.security.turnOffBody"), fontSize = 14.sp, color = C.muted)
            listOf(
                Icons.Server to t("web-pages.security.nowRisk"),
                Icons.Devices to t("web-pages.security.turnOffApproval"),
                Icons.Key to t("web-pages.security.turnOffVault"),
            ).forEach { (icon, said) ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    IconIn(icon, 18.dp, C.muted, Modifier.padding(top = 2.dp))
                    Text(said, fontSize = 15.sp, lineHeight = 22.sp, color = C.ink)
                }
            }
            Text(t("web-pages.security.turnOffType", "name" to name), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 6.dp))
            NameField(typed) { typed = it }
        }
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            WideButton(t("common.cancel"), primary = false, modifier = Modifier.weight(1f)) { app.sheet = null }
            WideButton(t("web-pages.security.turnOff"), primary = true, danger = true, enabled = named, modifier = Modifier.weight(1f)) {
                app.sheet = null
                app.vaultAct(t("web-pages.security.turnOff")) { app.core.call("lock.disable", buildJsonObject { put("workspace", ws) }) }
            }
        }
    }
}

/** A line to type in on a sheet (docs/ui-panels.md 浮起面板里的输入框): no ground of its own, a stronger line round it. */
@Composable
private fun NameField(value: String, onChange: (String) -> Unit) {
    var focused by remember { mutableStateOf(false) }
    BasicTextField(
        value, onChange, singleLine = true, cursorBrush = SolidColor(C.accent),
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
        textStyle = TextStyle(color = C.ink, fontSize = 15.sp),
        modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }
            .border(1.dp, C.ink.copy(alpha = if (focused) 0.32f else 0.18f), Smooth(12.dp)).padding(horizontal = 12.dp, vertical = 11.dp),
    )
}

/** A station of the workspace not in the lock, taken in once its owner says it is theirs. */
private fun joinSheet(app: AppState, ws: String, station: String, name: String) {
    app.sheet = SheetSpec(0.4f) {
        SheetGrab()
        SheetHead(t("web-pages.security.joinTitle", "name" to name))
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("web-pages.security.joinBody"), fontSize = 14.sp, color = C.muted)
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                WideButton(t("common.cancel"), primary = false, modifier = Modifier.weight(1f)) { app.sheet = null }
                WideButton(t("web-pages.security.join"), primary = true, modifier = Modifier.weight(1f)) { app.sheet = null; app.lockCall(ws, "joinStation", t("web-pages.security.join"), t("web-pages.security.joined", "name" to name), "station" to station) }
            }
        }
    }
}

/** A waiting device: confirmed once its code is the one on its screen. */
private fun confirmSheet(app: AppState, ws: String, r: LockRequest, onClose: (() -> Unit)? = null) {
    app.sheet = SheetSpec(0.55f, onClose = onClose) {
        val who = r.name.ifEmpty { r.email }
        // Answered on another device: gone here too.
        val lock by rememberTopic<LockView>(app.core, Topics.lock(ws))
        val gone = lock.value?.requests?.none { it.device == r.device } == true
        LaunchedEffect(gone) { if (gone) app.sheet = null }
        SheetGrab()
        SheetHead(t("web-pages.security.confirmTitle", "name" to who))
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("web-pages.security.confirmBody", "device" to deviceName(r.kind, r.label), "name" to who), fontSize = 14.sp, color = C.muted)
            Text(if (r.code.length == 6) "${r.code.take(3)} ${r.code.drop(3)}" else r.code, fontFamily = CodeFont, fontWeight = FontWeight.SemiBold, fontSize = 34.sp, letterSpacing = 5.sp, color = C.ink, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Note(if (r.kind == "web") t("web-pages.security.confirmWeb") else t("web-pages.security.confirmApp"))
            // One above the other, as wide as the sheet: the words fit in any language.
            Column(Modifier.fillMaxWidth().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                WideButton(t("web-pages.security.confirm"), primary = true, modifier = Modifier.fillMaxWidth()) { app.sheet = null; app.lockCall(ws, "confirm", t("web-pages.security.confirmDevice"), t("web-pages.security.confirmed"), "device" to r.device, "code" to r.code) }
                WideButton(t("web-pages.security.deny"), primary = false, modifier = Modifier.fillMaxWidth()) { app.sheet = null; app.lockCall(ws, "deny", t("web-pages.security.denyDevice"), null, "device" to r.device) }
            }
        }
    }
}

/**
 * The code a new device asks for, met face to face, and where it asks to be let in (the core's `lockPrompts`): nothing
 * here approves it, only the code typed on the new device. Turned away, or closed by hand, it is denied
 * (`lockPrompt.deny`) and the code is worth nothing; gone by itself once that device is done or turned away elsewhere.
 */
private fun pairSheet(app: AppState, r: LockPairing, deny: () -> Unit) {
    app.sheet = SheetSpec(0.55f, onClose = deny) {
        // Done or turned away on another device: gone here too; asked in one more workspace meanwhile, named too.
        val prompts by rememberTopic<LockPromptsView>(app.core, Topics.lockPrompts)
        val now = prompts.value?.pairing?.firstOrNull { it.device == r.device }
        val gone = prompts.value != null && now == null
        LaunchedEffect(gone) { if (gone) app.sheet = null }
        val shown = now ?: r
        SheetGrab()
        SheetHead(t("web-pages.security.pairTitle", "name" to r.name.ifEmpty { r.email }))
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("web-pages.security.pairBody", "device" to deviceName(r.kind, r.label)), fontSize = 14.sp, color = C.muted)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(t("web-pages.security.promptFor"), fontSize = 13.sp, color = C.muted)
                shown.workspaces.forEach { Text(it.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink) }
            }
            Text(if (shown.code.length == 6) "${shown.code.take(3)} ${shown.code.drop(3)}" else shown.code, fontFamily = CodeFont, fontWeight = FontWeight.SemiBold, fontSize = 34.sp, letterSpacing = 5.sp, color = C.ink, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Note(t("web-pages.security.pairNote"))
            WideButton(t("web-pages.security.pairDeny"), primary = false, modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 16.dp)) { app.sheet = null; deny() }
        }
    }
}

/**
 * A new device showing this one's code, in any workspace of the person's, put up over whichever page is open (the
 * core's `lockPrompts`), and again after a page change took the sheet away, until it is done or turned away.
 */
@Composable
fun LockPrompts() {
    val app = LocalApp.current
    val topic by rememberTopic<LockPromptsView>(app.core, Topics.lockPrompts)
    // Turned away here: not put up again while the core has yet to drop it.
    val denied = remember { mutableStateListOf<String>() }
    val r = topic.value?.pairing?.firstOrNull { it.device !in denied }
    val free = app.sheet == null
    LaunchedEffect(r?.device, free) {
        if (r == null || !free) return@LaunchedEffect
        pairSheet(app, r) {
            denied += r.device
            app.act(t("web-pages.security.denyDevice")) { app.core.call("lockPrompt.deny", buildJsonObject { put("device", r.device) }) }
        }
    }
}

/** 开启安全模式. */
@Composable
fun SecurityOpenScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace.id
    val topic by rememberTopic<LockDraftView>(app.core, Topics.lockDraft(ws))
    val draft = topic.value
    val opening = app.isDoing("lock.open", "workspace" to ws)
    val toggle = { id: String -> app.act(t("web-pages.security.turnOn")) { app.core.call("lock.toggle", buildJsonObject { put("workspace", ws); put("id", id) }) } }
    Column(Modifier.fillMaxSize()) {
      Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
        TopBack(t("web-pages.security.title"), app::pop)
        LargeTitle("", t("web-pages.security.openTitle"))
        if (draft == null || draft.loading) { Waiting(WaitShape.Cards, text = t("web-pages.settings.reading"), error = topic.error?.message); return@Column }
        PageNote(t("web-pages.security.openLead"))
        SectionHeader(t("web-pages.security.members"), start = 24.dp)
        ListCard {
            draft.members.forEach { m ->
                ListRow {
                    Column(Modifier.weight(1f)) { Text(m.name.ifEmpty { m.email }, fontSize = 15.sp, color = C.ink); Text(m.email, fontSize = 13.sp, color = C.muted) }
                    Text(ROLE_LABEL[m.role] ?: m.role, fontSize = 14.sp, color = C.subtle)
                }
            }
        }
        SectionHeader(t("web-pages.security.devices"), start = 24.dp)
        ListCard {
            draft.devices.forEach { d ->
                PickRow("${d.person} · ${if (d.current) t("web-pages.security.thisDevice") else deviceName(d.kind, d.label, d.older)}",
                    sub = if (d.older) t("web-pages.security.olderHow") else if (d.kind == "web") t("web-pages.security.web") else t("web-pages.security.app"),
                    checked = d.on, enabled = !d.fixed) { toggle(d.id) }
            }
        }
        SectionHeader("Station", start = 24.dp)
        ListCard {
            draft.stations.forEach { s ->
                PickRow(s.name, sub = when (s.state) { "ok" -> s.version; "asking" -> t("web-pages.security.asking"); "old" -> t("web-pages.security.tooOld"); else -> t("web-pages.security.offline") },
                    checked = s.on, enabled = !s.fixed) { toggle(s.id) }
            }
        }
        PageNote(t("web-pages.security.unprotectedNote"))
        Spacer(Modifier.height(24.dp))
      }
      if (draft != null && !draft.loading) Foot(if (draft.canSign) t("web-pages.security.webExpiry") else t("web-pages.security.webCannotSign")) {
          WideButton(t("web-pages.security.signAndTurnOn"), primary = true, modifier = Modifier.fillMaxWidth(), busy = opening, enabled = draft.ready && draft.owner && draft.canSign) {
              app.act(t("web-pages.security.turnOn"), t("web-pages.security.turnedOn")) {
                  app.core.call("lock.open", buildJsonObject { put("workspace", ws) })
                  app.pop()
              }
          }
      }
    }
}

/**
 * What a device waiting to be confirmed shows instead of the workspace's pages: asking by hand, its person's trusted
 * devices reached, the code one of them shows typed here (`me.pair`; views/pair.ts).
 */
@Composable
fun SecurityWaitingScreen(current: WorkspaceEntry, lock: LockView) {
    val app = LocalApp.current
    val ws = current.workspace.id
    val asking = app.isDoing("lock.pair", "workspace" to ws)
    val checking = app.isDoing("lock.pairCode", "workspace" to ws)
    var code by remember { mutableStateOf("") }
    val pair = lock.me?.pair
    val typing = pair != null && pair.state in setOf("code", "wrong", "checking")
    Column(
        Modifier.fillMaxSize().padding(horizontal = 28.dp).windowInsetsPadding(WindowInsets.navigationBars).imePadding(),
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        IconIn(Icons.ShieldCheck, 44.dp, C.ink)
        Text(t("web-pages.security.waitingTitle"), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, textAlign = TextAlign.Center)
        Text(t("web-pages.security.waitingLead", "name" to current.workspace.name), fontSize = 15.sp, lineHeight = 22.sp, color = C.subtle, textAlign = TextAlign.Center)
        val failed = lock.me?.failed
        when {
            typing -> {
                Note(t("web-pages.security.pairEnter"))
                val busy = checking || pair?.state == "checking"
                // Typed wrong: the boxes empty again for the next try, the page says how many are left.
                CodeField(code, wrong = pair?.state == "wrong" && code.isEmpty(), enabled = !busy, onChange = { code = it }) { typed ->
                    app.scope.launch { runCatching { app.core.call("lock.pairCode", buildJsonObject { put("workspace", ws); put("code", typed) }) }.onFailure { code = "" } }
                }
                if (busy) WaitLine(t("web-pages.security.pairChecking"))
                else if (pair?.state == "wrong") Text(t("web-pages.security.pairWrong", "n" to (pair.left ?: 0u).toInt()), fontSize = 12.sp, lineHeight = 18.sp, color = C.red, textAlign = TextAlign.Center)
            }
            pair?.state == "finding" || asking -> WaitLine(t("web-pages.security.pairFinding"))
            else -> {
                when {
                    pair?.state == "none" -> Note(t("web-pages.security.pairNone"))
                    pair?.state == "failed" -> Text(pair.error ?: "", fontSize = 12.sp, lineHeight = 18.sp, color = C.red, textAlign = TextAlign.Center)
                    failed != null -> Text(t("web-pages.security.requestFailed", "error" to failed), fontSize = 12.sp, lineHeight = 18.sp, color = C.red, textAlign = TextAlign.Center)
                    else -> Note(t("web-pages.security.notAsked"))
                }
                WideButton(t("web-pages.security.request"), primary = true) { app.lockCall(ws, "pair", t("web-pages.security.request")) }
            }
        }
    }
}

/**
 * Six digits typed into six boxes (three and three), the keypad up for them: the one to type next marked, a code pasted
 * whole taken, the last one typed handing it on (`onDone`) at once. One field under the boxes takes the typing.
 */
@Composable
private fun CodeField(value: String, wrong: Boolean, enabled: Boolean, onChange: (String) -> Unit, onDone: (String) -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val focus = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    BasicTextField(
        value,
        { typed ->
            val digits = typed.filter { it in '0'..'9' }.take(6)
            onChange(digits)
            if (digits.length == 6) onDone(digits)
        },
        enabled = enabled, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.NumberPassword, autoCorrectEnabled = false),
        textStyle = TextStyle(color = Color.Transparent),
        cursorBrush = SolidColor(Color.Transparent),
        modifier = Modifier.focusRequester(focus).onFocusChanged { focused = it.isFocused },
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.Center) {
                Box(Modifier.size(1.dp)) { inner() }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    for (i in 0 until 6) {
                        if (i == 3) Spacer(Modifier.width(8.dp))
                        val next = focused && enabled && i == minOf(value.length, 5)
                        val edge = when {
                            wrong -> C.red
                            next -> C.ink
                            else -> C.ink.copy(alpha = 0.18f)
                        }
                        Box(Modifier.size(width = 42.dp, height = 52.dp).border(1.dp, edge, Smooth(12.dp)), contentAlignment = Alignment.Center) {
                            Text(value.getOrNull(i)?.toString() ?: "", fontFamily = CodeFont, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, color = if (enabled) C.ink else C.muted)
                        }
                    }
                }
            }
        },
    )
}

/** A device waiting to be confirmed into the workspace's lock sees that instead of the workspace (its settings stay). */
@Composable
fun LockGate(current: WorkspaceEntry, content: @Composable () -> Unit) {
    val app = LocalApp.current
    val topic by rememberTopic<LockView>(app.core, Topics.lock(current.workspace.id))
    val lock = topic.value
    if (lock?.me?.waiting == true) SecurityWaitingScreen(current, lock) else content()
}
