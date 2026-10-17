// The workspace's vault (docs/vault.md), as the narrow web has it (one interaction set: bottom sheets): its row in the
// settings, its page (turning it on and the recovery words shown that once, each vault's items, the devices holding its
// key, recovering with the words), an item opened and edited in bottom sheets, and an agent's request approved where it
// is asked (its card in the chat, the 奏 page, the page's 等你批准). All of it is the core's (`vaults`, `vaultItems`
// topics, `vault.*` calls, client/core-ts/src/views/vault.ts): the system's prompt (fingerprint or screen lock) comes up
// from its calls through the host, never from here. What an item holds is shown only in its sheet, never kept.
package fail.still.android.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionOption
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.VaultItemRow
import fail.still.android.data.VaultItemsView
import fail.still.android.data.VaultRequest
import fail.still.android.data.VaultRow
import fail.still.android.data.VaultsView
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.errorText
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
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

// ── calls ──────────────────────────────────────────────────────────────

/** `vault.<name>` on the workspace `ws`, with what it takes. */
internal suspend fun AppState.vaultCall(ws: String, name: String, params: JsonObjectBuilder.() -> Unit = {}): JsonElement =
    core.call("vault.$name", buildJsonObject { put("workspace", ws); params() })

/**
 * What a vault call's failure says: nothing when the person turned the system's prompt down (`user_cancelled`), that
 * another device wrote first and the vault was read again (`vault_conflict`), else why.
 */
internal fun vaultSaid(e: CoreException): String? = when (e.code) {
    "user_cancelled" -> null
    "vault_conflict" -> t("android-settings.vault.conflict")
    else -> errorText(e)
}

/** As [AppState.act], for a vault call: `没能<what>：<why>`; a write made elsewhere first said as such; the prompt turned down, nothing. */
internal fun AppState.vaultAct(what: String, done: String? = null, run: suspend () -> Unit) {
    scope.launch {
        try {
            run()
            done?.let { toast = it }
        } catch (e: CoreException) {
            val why = vaultSaid(e) ?: return@launch
            toast = if (e.code == "vault_conflict") why else t(if (e.code == "unconfirmed") "android-misc.act.unconfirmed" else "android-misc.act.failed", "what" to what, "error" to why)
        }
    }
}

/** An item's plaintext as `vault.open` gives it (docs/vault.md 条目): held by its sheet only, while it is up. */
@Serializable
private data class Plain(val kind: String, val name: String, val fields: Map<String, String> = emptyMap(), val domains: List<String> = emptyList(), val notes: String = "")

/** The kinds of item, in the editor's order, and the fields each holds (the secret ones masked where shown). */
private val KINDS = listOf("token", "ssh_key", "login")
private val FIELDS = mapOf("token" to listOf("value"), "ssh_key" to listOf("private_key", "public_key"), "login" to listOf("username", "password", "totp"))
private val OPEN_FIELDS = setOf("public_key", "username")

private fun kindName(kind: String?) = if (kind in KINDS) t("android-settings.vault.kind.$kind") else ""
private fun kindIcon(kind: String?): ImageVector = when (kind) { "ssh_key" -> Icons.Server; "login" -> Icons.LogIn; else -> Icons.Key }
private fun modeName(mode: String) = if (mode in setOf("proxy", "env", "ssh")) t("android-settings.vault.mode.$mode") else mode
private fun fieldName(field: String) = when (field) {
    "value" -> t("android-settings.vault.value")
    "private_key" -> t("android-settings.vault.privateKey")
    "public_key" -> t("android-settings.vault.publicKey")
    "username" -> t("android-settings.vault.username")
    "password" -> t("android-settings.vault.password")
    "totp" -> t("android-settings.vault.totp")
    else -> field
}

/** What agents may do with an item, in a line: `agent 可申请 · 代理 · api.github.com`, or that it is only its owner's. */
private fun agentLine(listed: Boolean, modes: List<String>, hosts: List<String>, env: String? = null): String =
    if (!listed) t("android-settings.vault.selfOnly")
    else (listOf(t("android-settings.vault.agentCan")) + modes.map(::modeName) + listOfNotNull(hosts.joinToString(", ").ifEmpty { null }, env?.ifEmpty { null }?.let { t("android-settings.vault.envLine", "name" to it) }))
        .joinToString(" · ")

/** How a request would be given: by the proxy (to which hosts), the station's ssh-agent, or the command's environment. */
private fun howLine(mode: String, hosts: List<String>) = listOfNotNull(modeName(mode), hosts.joinToString(", ").ifEmpty { null }.takeIf { mode == "proxy" }).joinToString(" · ")

/**
 * The recovery words `vault.setup` gave, by workspace, until the person says they have written them down: in memory
 * only (a page left and come back to shows them again), never kept, and the core gives them only the once.
 */
private val recoveryWords = mutableStateMapOf<String, List<String>>()

// ── the settings' row ──────────────────────────────────────────────────

/** Settings' 密钥 (SettingsHome.kt, beside 安全): off, how many items, or how many requests wait (in red). */
@Composable
fun VaultSettingsRow(ws: String) {
    val app = LocalApp.current
    val topic by rememberTopic<VaultsView>(app.core, Topics.vaults(ws))
    val v = topic.value ?: return
    val waiting = v.requests.size
    val value = when {
        !v.locked || !v.setUp -> t("android-settings.vault.off")
        waiting > 0 -> t("android-settings.vault.waiting", "n" to waiting)
        else -> t("android-settings.vault.items", "n" to v.vaults.sumOf { it.items.toInt() })
    }
    GoRow(t("android-settings.vault.title"), value, bad = waiting > 0) { app.push(Screen.Vault) }
}

// ── the page ───────────────────────────────────────────────────────────

@Composable
fun VaultScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace.id
    val topic by rememberTopic<VaultsView>(app.core, Topics.vaults(ws))
    val view = topic.value
    val words = recoveryWords[ws]
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            TopBack(t("android-settings.title"), app::pop)
            LargeTitle("", t("android-settings.vault.title"))
            when {
                words != null -> Words(words)
                view == null -> PageNote(topic.error?.message ?: t("web-pages.settings.reading"))
                // A web page's (no keys kept there): what is known of the names, nothing to open.
                !view.available -> {
                    view.vaults.forEach { VaultSection(ws, it, readOnly = true) }
                    PageNote(t("android-settings.vault.readOnly"))
                }
                !view.locked -> ToSecurity(t("android-settings.vault.needsLock"), t("android-settings.vault.needsLockWhy"))
                !view.canSign -> ToSecurity(t("android-settings.vault.notSigner"), t("android-settings.vault.notSignerWhy"))
                !view.setUp -> Off()
                else -> On(ws, view)
            }
            Spacer(Modifier.height(30.dp))
        }
        if (words != null) Foot(t("android-settings.vault.wordsOnce")) {
            WideButton(t("android-settings.vault.wordsDone"), primary = true, modifier = Modifier.fillMaxWidth()) {
                recoveryWords.remove(ws)
                if (view != null && view.vaults.isEmpty()) createFirst(app, ws)
            }
        } else if (view != null && view.available && view.locked && view.canSign && !view.setUp) Foot {
            WideButton(t("android-settings.vault.turnOn"), primary = true, modifier = Modifier.fillMaxWidth(), busy = app.isDoing("vault.setup", "workspace" to ws)) { setUp(app, ws, view) }
        }
    }
}

/**
 * This device set up (its box key made, its certificate published): the first time the person's recovery words come
 * back, to be written down before going on; then (or at once, when one of their devices made the words before) their
 * personal vault, when they have none yet.
 */
private fun setUp(app: AppState, ws: String, view: VaultsView) = app.vaultAct(t("android-settings.vault.turnOn")) {
    val said = app.vaultCall(ws, "setup") as? JsonObject
    val words = (said?.get("words") as? JsonPrimitive)?.contentOrNull
    if (words != null) recoveryWords[ws] = words.trim().split(Regex("\\s+"))
    else if (view.vaults.isEmpty()) app.vaultCall(ws, "create") { put("name", t("android-settings.vault.personal")) }
}

private fun createFirst(app: AppState, ws: String) = app.vaultAct(t("android-settings.vault.create")) {
    app.vaultCall(ws, "create") { put("name", t("android-settings.vault.personal")) }
}

/** What has to come first (the workspace's security mode, this device confirmed in it), and the way to it. */
@Composable
private fun ToSecurity(title: String, why: String) {
    val app = LocalApp.current
    ListCard {
        Body { Para(title, why) }
        GoRow(t("web-pages.security.title")) { app.push(Screen.Security) }
    }
}

@Composable
private fun Off() = ListCard {
    Body {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Dot(false)
            Text(t("android-settings.vault.offTitle"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        }
        Para(t("android-settings.vault.offWhat"))
        Para(t("android-settings.vault.offAgents"), t("android-settings.vault.offUnlock"))
    }
}

/** The 24 recovery words, numbered, three to a row, for the person to copy out (the page's foot goes on). */
@Composable
private fun Words(words: List<String>) = ListCard {
    Body {
        Text(t("android-settings.vault.wordsTitle"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Text(t("android-settings.vault.wordsWhy"), fontSize = 13.sp, lineHeight = 19.sp, color = C.muted)
        Column(Modifier.fillMaxWidth().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            words.chunked(3).forEachIndexed { row, three ->
                Row(Modifier.fillMaxWidth()) {
                    three.forEachIndexed { i, word ->
                        Row(Modifier.weight(1f)) {
                            Text("${row * 3 + i + 1}", Modifier.width(22.dp).alignByBaseline(), fontSize = 12.sp, fontFamily = CodeFont, color = C.subtle, textAlign = TextAlign.End)
                            Spacer(Modifier.width(8.dp))
                            Text(word, Modifier.alignByBaseline(), fontSize = 15.sp, fontFamily = CodeFont, color = C.ink)
                        }
                    }
                }
            }
        }
    }
}

/** Set up: the requests waiting on the viewer, each vault's items, the devices that hold the keys. */
@Composable
private fun On(ws: String, view: VaultsView) {
    val app = LocalApp.current
    if (view.requests.isNotEmpty()) {
        SectionHeader("${t("android-settings.vault.waitingTitle")} · ${view.requests.size}", start = 24.dp)
        view.requests.forEach { r -> RequestCard(ws, view, r) }
    }
    if (view.vaults.isEmpty()) ListCard {
        Body {
            Para(t("android-settings.vault.none"))
            WideButton(t("android-settings.vault.create"), primary = true, modifier = Modifier.fillMaxWidth(), busy = app.isDoing("vault.create", "workspace" to ws)) { createFirst(app, ws) }
        }
    }
    view.vaults.forEach { VaultSection(ws, it, readOnly = false) }
    if (view.vaults.isNotEmpty()) Devices(ws, view)
    view.refused.forEach { r ->
        val name = r.name.ifEmpty { r.station }
        PageNote(if (r.code == "vault_needs_lock") t("android-settings.vault.refusedLock", "name" to name) else t("android-settings.vault.refusedOld", "name" to name))
    }
}

/** A request waiting on the viewer: what it is for (item, reason, command, how it is given), its chat, the three answers. */
@Composable
private fun RequestCard(ws: String, view: VaultsView, r: VaultRequest) {
    val app = LocalApp.current
    // The request's keeper is the station its vault is on (docs/vault.md: the agent asks there); its chat is the session's.
    val station = view.vaults.firstOrNull { it.id == r.vault }?.station?.ifEmpty { null }
    ListCard {
        Body {
            Text(t("android-settings.vault.request.title", "name" to (r.itemName ?: t("android-settings.vault.request.someItem"))), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(r.reason, fontSize = 14.sp, lineHeight = 20.sp, color = C.ink)
            r.command?.let { Text(it, fontSize = 13.sp, lineHeight = 19.sp, fontFamily = CodeFont, color = C.ink) }
            Text(howLine(r.mode, r.hosts), fontSize = 13.sp, color = C.muted)
            if (station != null) Row(
                Modifier.clickable { app.push(Screen.Chat("$ws/$station", ChatOf.Session(r.session))) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(t("android-settings.vault.request.openChat"), fontSize = 14.sp, color = C.accent)
                IconIn(Icons.ChevronRight, 13.dp, C.accent)
            }
        }
    }
    VaultOptions(ws, r.id, Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp))
}

/**
 * The three answers to an agent's request, in the decisions' options (Decisions.kt DecisionOptions): once (the one
 * recommended), this chat for an hour, refused. Approving asks the person through the system's prompt (the core's
 * call); the one under way turns where it was tapped.
 */
@Composable
private fun VaultOptions(ws: String, request: String, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val app = LocalApp.current
    val once = DecisionOption(t("android-settings.vault.approve.once"), t("android-settings.vault.approve.onceDetail"), recommended = true)
    val hour = DecisionOption(t("android-settings.vault.approve.hour"), t("android-settings.vault.approve.hourDetail"))
    val deny = DecisionOption(t("android-settings.vault.approve.deny"), t("android-settings.vault.approve.denyDetail"))
    val on = arrayOf("workspace" to ws, "request" to request)
    val busy = when {
        app.isDoing("vault.approve", *on, "scope" to "once") -> once.label
        app.isDoing("vault.approve", *on, "scope" to "hour") -> hour.label
        app.isDoing("vault.deny", *on) -> deny.label
        else -> null
    }
    DecisionOptions(listOf(once, hour, deny), modifier, enabled = enabled, busy = busy) { o ->
        if (o == deny) app.vaultAct(t("android-settings.vault.approve.denyWhat")) { app.vaultCall(ws, "deny") { put("request", request) } }
        else {
            val scope = if (o == once) "once" else "hour"
            app.vaultAct(t("android-settings.vault.approve.what")) { app.vaultCall(ws, "approve") { put("request", request); put("scope", scope) } }
        }
    }
}

/**
 * An agent's request where its card is (a post's options card with `vault`: Decisions.kt, in a chat and on the 奏 page):
 * the three answers in place of the card's own, when it waits on the viewer here; shown but not to be tapped where they
 * cannot be (another's to decide, `mine` false: the card says whose; a web page's, said to be the app's); once decided
 * (no longer among the requests), nothing to tap, until its station takes the card back.
 */
@Composable
internal fun VaultApproval(workspace: String, request: String, mine: Boolean, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val topic by rememberTopic<VaultsView>(app.core, Topics.vaults(workspace))
    val view = topic.value
    val running = app.isDoing(setOf("vault.approve", "vault.deny"), "workspace" to workspace, "request" to request)
    Column(modifier) {
        when {
            view == null || !mine -> VaultOptions(workspace, request, enabled = false)
            !view.available -> {
                VaultOptions(workspace, request, enabled = false)
                Text(t("android-settings.vault.approve.inApp"), fontSize = 13.sp, lineHeight = 19.sp, color = chatSubtle(), modifier = Modifier.padding(top = 6.dp))
            }
            running || view.requests.any { it.id == request } -> VaultOptions(workspace, request)
            else -> Text(t("android-settings.vault.approve.decided"), fontSize = 13.sp, lineHeight = 19.sp, color = chatSubtle())
        }
    }
}

/**
 * A vault: its name (and whether it is unlocked here: 锁上 then), `+` to add an item; its items, each opened by a tap (the
 * system's prompt when it is locked); this device without its key, how to get it (the recovery words, when it has them).
 * `readOnly`: names only (a web page).
 */
@Composable
private fun VaultSection(ws: String, v: VaultRow, readOnly: Boolean) {
    val app = LocalApp.current
    val topic by rememberTopic<VaultItemsView>(app.core, Topics.vaultItems(ws, v.id))
    val items = topic.value?.items.orEmpty()
    val open = topic.value?.open ?: v.open
    val usable = !readOnly && v.keyed
    Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 14.dp, top = 14.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(v.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            if (usable && !open && items.isNotEmpty()) Text(t("android-settings.vault.lockedNote"), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (usable && open) TextAction(t("android-settings.vault.lock")) { app.scope.launch { runCatching { app.vaultCall(ws, "lock") } } }
        if (usable) RoundIcon(Icons.Plus, t("android-settings.vault.add"), C.accent) { editorSheet(app, ws, v.id, null) }
    }
    if (!readOnly && !v.keyed) ListCard {
        Body { Para(t("android-settings.vault.noKey"), t("android-settings.vault.noKeyHow")) }
        if (v.recoverable) GoRow(t("android-settings.vault.recover")) { recoverSheet(app, ws) }
    }
    ListCard {
        if (items.isEmpty()) Body { Text(if (topic.value == null) t("web-pages.settings.reading") else t("android-settings.vault.empty"), fontSize = 14.sp, color = C.muted) }
        items.forEach { ItemRow(ws, v.id, it, usable) }
    }
}

/** An item: its kind's mark, its name (unknown while it is locked and not listed), what agents may do with it. */
@Composable
private fun ItemRow(ws: String, vault: String, item: VaultItemRow, usable: Boolean) {
    val app = LocalApp.current
    // `vault.open` is a read (no doing): its row turns until it answers (the prompt included).
    var opening by remember(item.id) { mutableStateOf(false) }
    ListRow(onClick = if (!usable || opening) null else ({ opening = true; openItem(app, ws, vault, item) { opening = false } })) {
        KindTile(item.kind)
        Column(Modifier.weight(1f)) {
            Text(item.name ?: t("android-settings.vault.lockedItem"), fontSize = 15.sp, color = if (item.name == null) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (item.listed) Box(Modifier.size(6.dp).clip(CircleShape).background(C.green))
                Text(agentLine(item.listed, item.modes, item.hosts), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (opening) Spinner(14.dp) else if (usable) IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

@Composable
private fun KindTile(kind: String?) = Box(Modifier.size(32.dp).clip(Smooth(10.dp)).background(C.bg), contentAlignment = Alignment.Center) {
    IconIn(kindIcon(kind), 16.dp, if (kind == null) C.subtle else C.ink)
}

/** A round icon button, named for screen readers. */
@Composable
private fun RoundIcon(icon: ImageVector, said: String, tint: Color = C.muted, size: androidx.compose.ui.unit.Dp = 34.dp, onClick: () -> Unit) = Box(
    Modifier.size(size).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = said },
    contentAlignment = Alignment.Center,
) { IconIn(icon, 18.dp, tint) }

/** A secondary action in words alone (no ground, no frame). */
@Composable
private fun TextAction(label: String, color: Color = C.accent, onClick: () -> Unit) =
    Text(label, fontSize = 14.sp, color = color, modifier = Modifier.clip(Smooth(8.dp)).clickable(onClick = onClick).padding(horizontal = 6.dp, vertical = 6.dp))

/** The devices that hold each vault's key; its owner gives it to the ones set up since (`vault.addDevice`). */
@Composable
private fun Devices(ws: String, view: VaultsView) {
    val app = LocalApp.current
    SectionHeader(t("android-settings.vault.devices"), start = 24.dp)
    ListCard {
        view.vaults.forEach { v ->
            val giving = app.isDoing("vault.addDevice", "workspace" to ws, "vault" to v.id)
            val give = v.mine && v.keyed && v.missing > 0u
            val hold = t("android-settings.vault.devicesHold", "n" to v.devices.toInt())
            ListRow(onClick = if (give && !giving) ({ app.vaultAct(t("android-settings.vault.giveKey"), t("android-settings.vault.gaveKey")) { app.vaultCall(ws, "addDevice") { put("vault", v.id) } } }) else null) {
                Column(Modifier.weight(1f)) {
                    Text(if (view.vaults.size > 1) "${v.name} · $hold" else hold, fontSize = 15.sp, color = C.ink)
                    if (v.missing > 0u) Text(t("android-settings.vault.missing", "n" to v.missing.toInt()), fontSize = 13.sp, color = C.warn)
                }
                when {
                    giving -> Spinner(14.dp)
                    give -> Text(t("android-settings.vault.giveKey"), fontSize = 14.sp, color = C.accent)
                }
            }
        }
    }
}

// ── an item ────────────────────────────────────────────────────────────

/** An item opened (`vault.open`: the system's prompt when its vault is locked here), then shown in its sheet. */
private fun openItem(app: AppState, ws: String, vault: String, item: VaultItemRow, done: () -> Unit) {
    app.scope.launch {
        try {
            val said = app.vaultCall(ws, "open") { put("item", item.id) } as JsonObject
            val plain = StillFailJson.decodeFromJsonElement(Plain.serializer(), said["plain"]!!)
            itemSheet(app, ws, vault, item, plain)
        } catch (e: CoreException) {
            vaultSaid(e)?.let { app.toast = t("android-misc.act.failed", "what" to t("android-settings.vault.openWhat"), "error" to it) }
        } finally {
            done()
        }
    }
}

/** An item as it is: its fields (the secret ones masked until shown, each copied), what agents may do with it, 编辑. */
private fun itemSheet(app: AppState, ws: String, vault: String, item: VaultItemRow, plain: Plain) {
    app.sheet = SheetSpec(0.5f, draggable = true) {
        SheetGrab()
        SheetHead(plain.name, lead = { KindTile(plain.kind) }, trailing = { TextAction(t("common.edit")) { editorSheet(app, ws, vault, Editing(item, plain)) } })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            ListCard {
                val fields = FIELDS[plain.kind] ?: plain.fields.keys.toList()
                fields.forEach { f -> plain.fields[f]?.takeIf { it.isNotEmpty() }?.let { FieldRow(fieldName(f), it, secret = f !in OPEN_FIELDS) } }
            }
            ListCard {
                ListRow {
                    if (item.listed) Box(Modifier.size(6.dp).clip(CircleShape).background(C.green))
                    Text(agentLine(item.listed, item.modes, item.hosts, item.env), fontSize = 14.sp, color = C.muted, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

/** A field of an opened item: its name over its value (dots until shown, when secret), shown and copied from beside it. */
@Composable
private fun FieldRow(label: String, value: String, secret: Boolean) {
    val app = LocalApp.current
    val context = LocalContext.current
    var shown by remember { mutableStateOf(!secret) }
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 10.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, fontSize = 12.sp, color = C.muted)
            // Masked, as long whatever its length (which would say something of it).
            Text(if (shown) value else "••••••••••••", fontSize = 14.sp, lineHeight = 20.sp, fontFamily = CodeFont, color = C.ink, maxLines = if (shown) Int.MAX_VALUE else 1, overflow = TextOverflow.Ellipsis)
        }
        if (secret) RoundIcon(Icons.Eye, if (shown) t("android-settings.vault.hide") else t("android-settings.vault.reveal"), if (shown) C.accent else C.muted) { shown = !shown }
        RoundIcon(Icons.Copy, t("common.copy")) { copy(context, app, value, secret) }
    }
}

/**
 * Copied to the clipboard: a secret marked sensitive (the system's preview of it masked, Android 13 on) and cleared 30
 * seconds later, unless something else was copied meanwhile (when the clipboard cannot be read then, the app not in
 * front, it is cleared all the same: a secret left there is worse).
 */
private fun copy(context: Context, app: AppState, text: String, secret: Boolean) {
    val board = context.getSystemService(ClipboardManager::class.java) ?: return
    val clip = ClipData.newPlainText("still.fail", text)
    // ClipDescription.EXTRA_IS_SENSITIVE (Android 13), by its value: older systems pass it over.
    if (secret) clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
    board.setPrimaryClip(clip)
    app.toast = if (secret) t("android-settings.vault.copied") else t("common.copied")
    if (!secret) return
    app.scope.launch {
        delay(30_000)
        val now = runCatching { board.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString() }.getOrNull()
        if (now == null || now == text) runCatching { board.clearPrimaryClip() }
    }
}

// ── the editor ─────────────────────────────────────────────────────────

/** An item being changed: as its vault's list has it (its listing), and what it holds as opened. */
private class Editing(val item: VaultItemRow, val plain: Plain)

private fun editorSheet(app: AppState, ws: String, vault: String, editing: Editing?) {
    app.sheet = SheetSpec(0.92f) { Editor(app, ws, vault, editing) }
}

/**
 * An item written (`vault.putItem`): its kind, name and fields, and whether agents may ask for it (then how it is given,
 * where to, under which variable). The sheet stays while it is saved (the system's prompt may come up for a locked
 * vault): turned down, nothing is lost; refused, why stands under it. 删除这一条 for one that is there.
 */
@Composable
private fun ColumnScope.Editor(app: AppState, ws: String, vault: String, editing: Editing?) {
    val was = editing?.plain
    var kind by remember { mutableIntStateOf(KINDS.indexOf(was?.kind).coerceAtLeast(0)) }
    var name by remember { mutableStateOf(was?.name.orEmpty()) }
    val fields = remember { mutableStateMapOf<String, String>().apply { was?.fields?.let { putAll(it) } } }
    var agent by remember { mutableStateOf(editing?.item?.listed ?: false) }
    var mode by remember { mutableStateOf(editing?.item?.modes?.firstOrNull { it == "proxy" || it == "env" } ?: "proxy") }
    var hosts by remember { mutableStateOf(editing?.item?.hosts?.joinToString(", ").orEmpty()) }
    var env by remember { mutableStateOf(editing?.item?.env.orEmpty()) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val k = KINDS[kind]
    val hostList = hosts.split(',', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }
    val modes = if (k == "ssh_key") listOf("ssh") else listOf(mode)
    val filled = when (k) {
        "token" -> !fields["value"].isNullOrBlank()
        "ssh_key" -> !fields["private_key"].isNullOrBlank()
        else -> !fields["username"].isNullOrBlank() || !fields["password"].isNullOrBlank()
    }
    val noHosts = agent && mode == "proxy" && k != "ssh_key" && hostList.isEmpty()
    val ready = name.isNotBlank() && filled && !noHosts

    fun save() {
        if (saving || !ready) return
        saving = true
        error = null
        val plain = buildJsonObject {
            put("kind", k)
            put("name", name.trim())
            // A private key as pasted (its last line break is part of it); the rest without the spaces around them.
            putJsonObject("fields") { FIELDS.getValue(k).forEach { f -> fields[f]?.let { if (f == "private_key") it else it.trim() }?.takeIf { it.isNotBlank() }?.let { put(f, it) } } }
            putJsonArray("domains") { was?.domains?.forEach { add(it) } }
            put("notes", was?.notes.orEmpty())
        }
        val listing = if (!agent) null else buildJsonObject {
            put("name", name.trim())
            put("kind", k)
            putJsonArray("modes") { modes.forEach { add(it) } }
            putJsonArray("hosts") { if (modes == listOf("proxy")) hostList.forEach { add(it) } }
            env.trim().takeIf { it.isNotEmpty() && k != "ssh_key" }?.let { put("env", it) }
        }
        app.scope.launch {
            try {
                app.vaultCall(ws, "putItem") {
                    put("vault", vault)
                    editing?.let { put("id", it.item.id) }
                    put("plain", plain)
                    listing?.let { put("listing", it) }
                }
                app.sheet = null
            } catch (e: CoreException) {
                val why = vaultSaid(e)
                // Written elsewhere first: the vault was read again; what is here was written over that, so it goes.
                if (e.code == "vault_conflict") { app.sheet = null; app.toast = why } else error = why
            } finally {
                saving = false
            }
        }
    }

    SheetGrab()
    SheetHead(
        if (was == null) t("android-settings.vault.newTitle") else t("android-settings.vault.editTitle", "name" to was.name),
        trailing = { Button(t("common.save"), primary = true, busy = saving, enabled = ready) { save() } },
    )
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Seg(KINDS.map(::kindName), kind, { kind = it }, Modifier.fillMaxWidth(), height = 34.dp, fill = true)
        Labeled(t("android-settings.vault.name")) { VaultField(name, { name = it }, t("android-settings.vault.namePlaceholder")) }
        val optional = { f: String -> t("android-settings.vault.optional", "name" to fieldName(f)) }
        when (k) {
            "token" -> Labeled(fieldName("value")) { VaultField(fields["value"].orEmpty(), { fields["value"] = it }, "ghp_…", mono = true, secret = true) }
            "ssh_key" -> {
                Labeled(fieldName("private_key")) { VaultField(fields["private_key"].orEmpty(), { fields["private_key"] = it }, "-----BEGIN OPENSSH PRIVATE KEY-----", mono = true, lines = 4) }
                Labeled(optional("public_key")) { VaultField(fields["public_key"].orEmpty(), { fields["public_key"] = it }, "ssh-ed25519 AAAA…", mono = true, lines = 2) }
            }
            else -> {
                Labeled(fieldName("username")) { VaultField(fields["username"].orEmpty(), { fields["username"] = it }, "name@example.com") }
                Labeled(fieldName("password")) { VaultField(fields["password"].orEmpty(), { fields["password"] = it }, "", mono = true, secret = true) }
                Labeled(optional("totp")) { VaultField(fields["totp"].orEmpty(), { fields["totp"] = it }, "JBSWY3DPEHPK3PXP", mono = true, secret = true) }
            }
        }
        Column(Modifier.fillMaxWidth().clip(Smooth(16.dp)).background(C.surface).padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().clickable { agent = !agent }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(t("android-settings.vault.agent"), fontSize = 15.sp, color = C.ink)
                    Text(t("android-settings.vault.agentNote"), fontSize = 13.sp, color = C.muted)
                }
                Switch(agent)
            }
            if (agent) {
                if (k == "ssh_key") Labeled(t("android-settings.vault.how")) {
                    Text(modeName("ssh"), fontSize = 15.sp, color = C.ink)
                    Text(t("android-settings.vault.sshNote"), fontSize = 12.sp, lineHeight = 18.sp, color = C.muted)
                } else {
                    Labeled(t("android-settings.vault.how")) {
                        Seg(listOf(modeName("proxy"), modeName("env")), if (mode == "env") 1 else 0, { mode = if (it == 1) "env" else "proxy" }, Modifier.fillMaxWidth(), height = 34.dp, fill = true)
                        Text(t("android-settings.vault.howNote"), fontSize = 12.sp, lineHeight = 18.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp))
                    }
                    if (mode == "proxy") Labeled(t("android-settings.vault.hosts")) {
                        VaultField(hosts, { hosts = it }, "api.github.com, uploads.github.com")
                        if (noHosts && hosts.isNotEmpty()) Text(t("android-settings.vault.hostsNeeded"), fontSize = 12.sp, color = C.red)
                    }
                    Labeled(t("android-settings.vault.env")) { VaultField(env, { env = it.trim() }, t("android-settings.vault.envPlaceholder"), mono = true) }
                }
            }
        }
        error?.let { Text(it, fontSize = 13.sp, color = C.red) }
        if (editing != null) TextAction(t("android-settings.vault.delete"), C.red) {
            confirm(app, t("android-settings.vault.deleteTitle", "name" to editing.plain.name), t("android-settings.vault.deleteText"), t("common.delete"), danger = true, what = t("android-settings.vault.deleteWhat")) {
                app.vaultCall(ws, "deleteItem") { put("vault", vault); put("item", editing.item.id) }
            }
        }
    }
}

/** A field's name over it. */
@Composable
private fun Labeled(label: String, content: @Composable ColumnScope.() -> Unit) = Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
    Text(label, fontSize = 13.sp, color = C.muted)
    content()
}

/**
 * A line (or `lines`) to type a secret's parts in, as the settings' fields are (Workspaces.kt Field) but of any length;
 * `secret`: dots until the eye beside it is tapped, and no suggestions kept by the keyboard.
 */
@Composable
private fun VaultField(value: String, onChange: (String) -> Unit, placeholder: String, mono: Boolean = false, secret: Boolean = false, lines: Int = 1) {
    var shown by remember { mutableStateOf(false) }
    val style = TextStyle(color = C.ink, fontSize = if (mono) 14.sp else 15.sp, lineHeight = 20.sp, fontFamily = if (mono) CodeFont else null)
    Row(
        Modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.surface).border(1.dp, C.line, Smooth(12.dp)).padding(start = 12.dp, end = if (secret) 8.dp else 12.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = style.copy(color = C.subtle), maxLines = lines, overflow = TextOverflow.Ellipsis)
            BasicTextField(
                value, onChange, singleLine = lines == 1, minLines = lines, maxLines = if (lines == 1) 1 else 10, cursorBrush = SolidColor(C.accent),
                visualTransformation = if (secret && !shown) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, keyboardType = if (secret) KeyboardType.Password else if (mono) KeyboardType.Ascii else KeyboardType.Text),
                textStyle = style, modifier = Modifier.fillMaxWidth(),
            )
        }
        if (secret) Box(
            Modifier.size(20.dp).clip(CircleShape).clickable { shown = !shown }.semantics { contentDescription = if (shown) t("android-settings.vault.hide") else t("android-settings.vault.reveal") },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Eye, 18.dp, if (shown) C.accent else C.subtle) }
    }
}

// ── recovering ─────────────────────────────────────────────────────────

/** This device keyed into the person's vaults again by their 24 recovery words (`vault.recover`). */
private fun recoverSheet(app: AppState, ws: String) {
    app.sheet = SheetSpec(0.62f) {
        var text by remember { mutableStateOf("") }
        var error by remember { mutableStateOf<String?>(null) }
        var busy by remember { mutableStateOf(false) }
        val n = text.trim().split(Regex("\\s+")).count { it.isNotEmpty() }
        SheetGrab()
        SheetHead(t("android-settings.vault.recover"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("android-settings.vault.recoverLead"), fontSize = 14.sp, color = C.muted)
            VaultField(text, { text = it; error = null }, "orbit canvas lemon …", mono = true, lines = 5)
            Text(t("android-settings.vault.recoverCount", "n" to n), fontSize = 12.sp, color = if (n == 24) C.green else C.subtle)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(t("android-settings.vault.recoverAction"), primary = true, busy = busy, enabled = n == 24) {
                    busy = true
                    app.scope.launch {
                        try {
                            val said = app.vaultCall(ws, "recover") { put("words", text.trim()) } as? JsonObject
                            val got = (said?.get("recovered") as? JsonPrimitive)?.intOrNull ?: 0
                            app.sheet = null
                            app.toast = if (got > 0) t("android-settings.vault.recovered", "n" to got) else t("android-settings.vault.recoveredNone")
                        } catch (e: CoreException) {
                            error = vaultSaid(e)
                        } finally {
                            busy = false
                        }
                    }
                }
            }
        }
    }
}
