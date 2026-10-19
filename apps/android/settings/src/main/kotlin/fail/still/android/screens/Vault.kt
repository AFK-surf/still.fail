// The workspace's library (docs/vault.md 一个库), as the narrow web has it (web/src/mobile/Vault.tsx; one interaction set:
// bottom sheets): its row in the settings, its page (what it waits for first when locked, turning it on and the recovery
// words shown that once; then the requests waiting, whether it is locked, the profiles' accounts, each vault's secrets a
// section a kind, the devices holding its key), a secret's own page (its content shown, how agents may use it, when they
// did), adding and editing in bottom sheets, and an agent's request approved where it is asked (its card in the chat, the
// 奏 page, the page's 待批准). All of it is the core's (`vaults`, `vaultItems`, `vaultUses` topics, `vault.*` calls,
// client/core-ts/src/views/vault.ts): the system's prompt (fingerprint or screen lock) comes up from its calls through the
// host, never from here. What an item holds is shown only on its page, while it is up, never kept.
package fail.still.android.screens

import fail.still.android.ui.pressText
import fail.still.android.ui.Spinner
import fail.still.android.ui.WaitLine
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting
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
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.DecisionOption
import fail.still.android.data.ProfilesView
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.VaultItemRow
import fail.still.android.data.VaultItemsView
import fail.still.android.data.VaultRequest
import fail.still.android.data.VaultRow
import fail.still.android.data.VaultUse
import fail.still.android.data.VaultUsesView
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
import fail.still.android.ui.NavBar
import fail.still.android.ui.ProviderMark
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SHEET_ACTION
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.android.ui.Card
import fail.still.android.ui.concentricOut
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
import fail.still.android.ui.Button
import fail.still.android.ui.chatSubtle

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
private fun kindIcon(kind: String?): ImageVector = when (kind) { "ssh_key" -> Icons.Server; "login" -> Icons.User; else -> Icons.Key }
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

/** How a request would be given: by the proxy (限 which hosts), the station's ssh-agent, or the command's environment. */
private fun howLine(mode: String, hosts: List<String>) =
    listOfNotNull(modeName(mode), hosts.joinToString(", ").ifEmpty { null }?.takeIf { mode == "proxy" }?.let { t("web-pages.vault.onlyTo", "hosts" to it) }).joinToString(" · ")

/** The kinds the library lists after the profiles' accounts, a section each, in this order (the editor's). */
private val ITEM_SECTIONS = KINDS

/**
 * The recovery words `vault.setup` gave, by workspace, until the person says they have written them down: in memory
 * only (a page left and come back to shows them again), never kept, and the core gives them only the once.
 */
private val recoveryWords = mutableStateMapOf<String, List<String>>()

// ── the settings' row ──────────────────────────────────────────────────

/** Settings' 密钥 (SettingsHome.kt, beside 安全), as the web's vaultStatus: how many requests wait (in red), else how many items, else off. */
@Composable
fun VaultSettingsRow(ws: String) {
    val app = LocalApp.current
    val topic by rememberTopic<VaultsView>(app.core, Topics.vaults(ws))
    val v = topic.value ?: return
    val waiting = v.requests.size
    val value = when {
        waiting > 0 -> t("android-settings.vault.waiting", "n" to waiting)
        v.vaults.isNotEmpty() -> t("android-settings.vault.items", "n" to v.vaults.sumOf { it.items.toInt() })
        else -> t("android-settings.vault.off")
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
    // Not locked (no security mode in the workspace): the library kept in the clear on its station, usable at once.
    val plain = view?.plain == true
    val usable = view != null && words == null && (plain || (view.available && view.locked && view.canSign && view.setUp))
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            TopBack(t("android-settings.title"), app::pop, trailing = if (usable) ({ RoundIcon(Icons.Plus, t("android-settings.vault.add"), C.ink) { addSheet(app, ws) } }) else null)
            LargeTitle("", t("android-settings.vault.title"))
            when {
                words != null -> Words(words)
                view == null -> Waiting(WaitShape.Cards, text = t("web-pages.settings.reading"), error = topic.error?.message)
                plain -> Library(ws, view)
                // A web page's (no keys kept there): what is known of the names, nothing to open.
                !view.available -> {
                    view.vaults.forEach { VaultSection(ws, it, readOnly = true) }
                    PageNote(t("android-settings.vault.readOnly"))
                }
                !view.locked -> ToSecurity(t("android-settings.vault.needsLock"), t("android-settings.vault.needsLockWhy"))
                !view.canSign -> ToSecurity(t("android-settings.vault.notSigner"), t("android-settings.vault.notSignerWhy"))
                !view.setUp -> Off()
                else -> Library(ws, view)
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

/**
 * The library (docs/vault.md 一个库), not locked or set up: the requests waiting on the viewer, whether it is locked (and
 * what is still in the clear from before), the profiles' accounts, each vault's secrets a section a kind, the devices
 * that hold the keys (locked).
 */
@Composable
private fun Library(ws: String, view: VaultsView) {
    val app = LocalApp.current
    val plain = view.plain == true
    if (view.requests.isNotEmpty()) {
        SectionHeader("${t("android-settings.vault.waitingTitle")} · ${view.requests.size}", start = 24.dp)
        view.requests.forEach { r -> RequestCard(ws, view, r) }
    }
    LibraryState(plain)
    val left = view.plainLeft?.toInt() ?: 0
    if (!plain && left > 0) PlainLeft(ws, left)
    ProfileAccounts(ws)
    // Words and its button under them, in the corner.
    if (!plain && view.vaults.isEmpty()) Card(foot = true) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Para(t("android-settings.vault.none"))
            Button(t("android-settings.vault.create"), primary = true, modifier = Modifier.fillMaxWidth(), busy = app.isDoing("vault.create", "workspace" to ws)) { createFirst(app, ws) }
        }
    }
    // A vault this device has no key to: what is known of it, and how to get the key.
    view.vaults.forEach { if (plain || it.keyed) LibraryVault(ws, it, plain) else VaultSection(ws, it, readOnly = false) }
    if (!plain && view.vaults.isNotEmpty()) Devices(ws, view)
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
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(t("android-settings.vault.request.title", "name" to (r.itemName ?: t("android-settings.vault.request.someItem"))), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(r.reason, fontSize = 14.sp, lineHeight = 20.sp, color = C.ink)
            r.command?.let { Text(it, fontSize = 13.sp, lineHeight = 19.sp, fontFamily = CodeFont, color = C.ink) }
            Text(howLine(r.mode, r.hosts), fontSize = 13.sp, color = C.muted)
            if (station != null) Row(
                Modifier.pressText { app.push(Screen.Chat("$ws/$station", ChatOf.Session(r.session))) },
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
fun VaultApproval(workspace: String, request: String, mine: Boolean, modifier: Modifier = Modifier) {
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
 * A vault as far as it is known here, names only: a web page's (`readOnly`), or one this device has no key to (then how
 * to get it: the recovery words, when it has them).
 */
@Composable
private fun VaultSection(ws: String, v: VaultRow, readOnly: Boolean) {
    val app = LocalApp.current
    val topic by rememberTopic<VaultItemsView>(app.core, Topics.vaultItems(ws, v.id))
    val items = topic.value?.items.orEmpty()
    SectionHeader(v.name, start = 24.dp)
    if (!readOnly && !v.keyed) ListCard {
        Body { Para(t("android-settings.vault.noKey"), t("android-settings.vault.noKeyHow")) }
        if (v.recoverable) GoRow(t("android-settings.vault.recover")) { recoverSheet(app, ws) }
    }
    ListCard {
        if (items.isEmpty()) Body {
            if (topic.value == null) WaitLine(topic.error?.message ?: t("web-pages.settings.reading"), error = topic.error != null)
            else Text(t("android-settings.vault.empty"), fontSize = 14.sp, color = C.muted)
        }
        items.forEach { ItemRow(it) }
    }
}

/** An item known by name: its kind's mark, its name (unknown while it is locked and not listed), what agents may do with it. */
@Composable
private fun ItemRow(item: VaultItemRow) = ListRow {
    KindTile(item.kind)
    Column(Modifier.weight(1f)) {
        Text(item.name ?: t("android-settings.vault.lockedItem"), fontSize = 15.sp, color = if (item.name == null) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (item.listed) Box(Modifier.size(6.dp).clip(CircleShape).background(C.green))
            Text(agentLine(item.listed, item.modes, item.hosts), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// ── the library's parts (docs/vault.md 一个库) ─────────────────────────

/** A row's mark: an icon in the narrow column the library's rows keep for it. */
@Composable
private fun RowMark(content: @Composable () -> Unit) = Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) { content() }

/** First in the library: whether it is locked (security mode on), and the way to lock it when not; a tap opens 安全. */
@Composable
private fun LibraryState(plain: Boolean) {
    val app = LocalApp.current
    ListCard {
        ListRow(onClick = { app.push(Screen.Security) }) {
            RowMark { IconIn(Icons.ShieldCheck, 18.dp, if (plain) C.warn else C.subtle) }
            Column(Modifier.weight(1f)) {
                Text(t(if (plain) "web-pages.vault.lib.plain" else "web-pages.vault.lib.sealed"), fontSize = 15.sp, color = if (plain) C.warn else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(t(if (plain) "web-pages.vault.lib.plainWhy" else "web-pages.vault.lib.sealedWhy"), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (plain) Text(t("web-pages.vault.lib.turnOn"), fontSize = 15.sp, color = C.accent, maxLines = 1)
            else IconIn(Icons.ChevronRight, 14.dp, C.subtle)
        }
    }
}

/** Security mode on, the viewer's secrets saved before it still in plain text: encrypted into their vault (`vault.migrate`). */
@Composable
private fun PlainLeft(ws: String, n: Int) {
    val app = LocalApp.current
    // Its words, its button under them in the corner.
    Card(foot = true) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column {
                Text(t("android-settings.vault.migrate.title", "n" to n), fontSize = 15.sp, color = C.ink)
                Text(t("android-settings.vault.migrate.body"), fontSize = 13.sp, lineHeight = 19.sp, color = C.muted)
            }
            Button(t("android-settings.vault.migrate.action"), primary = true, busy = app.isDoing("vault.migrate", "workspace" to ws)) {
                app.vaultAct(t("android-settings.vault.migrate.what"), t("android-settings.vault.migrate.done")) { app.vaultCall(ws, "migrate") }
            }
        }
    }
}

/**
 * The profiles' accounts the library keeps (a subscription's sign-in, a model's key), a section a kind as the Profile
 * list groups them; each opens its profile as that list does (an account on several stations, its own page).
 */
@Composable
private fun ProfileAccounts(ws: String) {
    val app = LocalApp.current
    val topic by rememberTopic<ProfilesView>(app.core, Topics.profiles(ws))
    val view = topic.value ?: return
    view.items.groupBy { it.group }.forEach { (_, g) ->
        SectionHeader(g.first().groupTitle, start = 24.dp)
        ListCard {
            g.forEach { e ->
                val p = e.profile
                ListRow(onClick = { app.push(if (e.members.orEmpty().count { it.role != "user" } > 1) Screen.ProfileAccount(e.key) else Screen.Profile(e.station, p.id)) }) {
                    RowMark { ProviderMark(p.runtime, p.access.kind, 18.dp, p.providerMark) }
                    Column(Modifier.weight(1f)) {
                        Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOf("Profile", e.where).filter { it.isNotEmpty() }.joinToString(" · "), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
            }
        }
    }
}

/**
 * A vault's secrets after the profiles' accounts, a section each kind: each one's name, and when an agent last used it
 * (else what agents may do with it); in a library not locked, that it is not encrypted, first. A tap opens its page.
 */
@Composable
private fun LibraryVault(ws: String, v: VaultRow, plain: Boolean) {
    val app = LocalApp.current
    val topic by rememberTopic<VaultItemsView>(app.core, Topics.vaultItems(ws, v.id))
    val items = topic.value?.items ?: return
    val warn = C.warn
    ITEM_SECTIONS.forEach { kind ->
        val rows = items.filter { it.name != null && it.kind == kind }
        if (rows.isEmpty()) return@forEach
        SectionHeader(kindName(kind), start = 24.dp)
        ListCard {
            rows.forEach { row ->
                ListRow(onClick = { app.push(Screen.VaultItem(v.id, row.id)) }) {
                    RowMark { IconIn(kindIcon(row.kind), 18.dp, C.subtle) }
                    Column(Modifier.weight(1f)) {
                        Text(row.name.orEmpty(), fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            buildAnnotatedString {
                                if (plain) withStyle(SpanStyle(color = warn)) { append("${t("web-pages.vault.risk.row")} · ") }
                                append(row.lastUse?.let { t("web-pages.vault.uses.last", "when" to it.at.ago) } ?: agentLine(row.listed, row.modes, row.hosts))
                            },
                            fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
            }
        }
    }
    // Locked here: those whose names it does not know, a tap unlocking it; unlocked, locking it again.
    val hidden = items.filter { it.name == null }
    if (!plain && (hidden.isNotEmpty() || v.open)) ListCard {
        if (hidden.isNotEmpty()) ListRow(onClick = { app.vaultAct(t("android-settings.vault.lockedNote")) { app.vaultCall(ws, "open") { put("item", hidden.first().id) } } }) {
            RowMark { IconIn(Icons.Key, 18.dp, C.subtle) }
            Text(t("android-settings.vault.lockedNote"), fontSize = 15.sp, color = C.muted, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (v.open) ListRow(onClick = { app.scope.launch { runCatching { app.vaultCall(ws, "lock") } } }) {
            RowMark {}
            Text(t("android-settings.vault.lock"), fontSize = 15.sp, color = C.accent, modifier = Modifier.weight(1f))
        }
    }
}

/**
 * 添加 in the library: a subscription or a model's key (a profile, added on the Profile list), or a secret of a kind (its
 * editor, the kind fixed). Not locked: that such a secret is kept in the clear, under the list.
 */
private fun addSheet(app: AppState, ws: String) {
    app.sheet = SheetSpec(0.55f, draggable = true) {
        val topic by rememberTopic<VaultsView>(app.core, Topics.vaults(ws))
        val view = topic.value
        val mine = view?.vaults?.firstOrNull { it.mine }
        val plain = view?.plain == true
        SheetGrab()
        SheetHead(t("web-pages.vault.addKind.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            ListCard {
                AddRow(Icons.Quota, "profile") { app.sheet = null; app.push(Screen.Profiles()) }
                if (mine != null) ITEM_SECTIONS.forEach { k -> AddRow(kindIcon(k), k) { editorSheet(app, ws, mine.id, null, kind = k, plain = plain) } }
            }
            if (plain && mine != null) Text(t("web-pages.vault.risk.editor"), fontSize = 13.sp, lineHeight = 19.sp, color = C.warn, modifier = Modifier.padding(horizontal = 24.dp))
        }
    }
}

@Composable
private fun AddRow(icon: ImageVector, kind: String, onClick: () -> Unit) = ListRow(onClick = onClick) {
    RowMark { IconIn(icon, 18.dp, C.subtle) }
    Column(Modifier.weight(1f)) {
        Text(t("web-pages.vault.addKind.$kind"), fontSize = 15.sp, color = C.ink)
        Text(t("web-pages.vault.addKind.${kind}Detail"), fontSize = 13.sp, color = C.muted)
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
                    giving -> Spinner()
                    give -> Text(t("android-settings.vault.giveKey"), fontSize = 14.sp, color = C.accent)
                }
            }
        }
    }
}

// ── an item ────────────────────────────────────────────────────────────

/** What `vault.open` gives of an item (the system's prompt first when its vault is locked here), or null when it did not. */
private suspend fun openPlain(app: AppState, ws: String, item: String): Plain? = try {
    val said = app.vaultCall(ws, "open") { put("item", item) } as JsonObject
    StillFailJson.decodeFromJsonElement(Plain.serializer(), said["plain"]!!)
} catch (e: CoreException) {
    vaultSaid(e)?.let { app.toast = t("android-misc.act.failed", "what" to t("android-settings.vault.openWhat"), "error" to it) }
    null
}

/**
 * A secret's page (as the narrow web's VaultItemScreen): its kind and where it is kept; in a library not locked, that it
 * is not encrypted and the way to lock it; its content masked until shown (`vault.open`), each field shown and copied;
 * how agents may use it; when they did, each use leading to its chat. 编辑 opens it first, then its editor.
 */
@Composable
fun VaultItemScreen(current: WorkspaceEntry, vault: String, item: String) {
    val app = LocalApp.current
    val ws = current.workspace.id
    val vaults by rememberTopic<VaultsView>(app.core, Topics.vaults(ws))
    val items by rememberTopic<VaultItemsView>(app.core, Topics.vaultItems(ws, vault))
    val uses by rememberTopic<VaultUsesView>(app.core, Topics.vaultUses(ws, vault, item))
    // What it holds, once shown: on this page only, while it is up.
    var opened by remember { mutableStateOf<Plain?>(null) }
    var opening by remember { mutableStateOf(false) }
    val v = vaults.value?.vaults?.firstOrNull { it.id == vault }
    val row = items.value?.items?.firstOrNull { it.id == item }
    val plain = vaults.value?.plain == true
    fun open(then: (Plain) -> Unit = {}) {
        if (opening) return
        opening = true
        app.scope.launch {
            openPlain(app, ws, item)?.let { opened = it; then(it) }
            opening = false
        }
    }
    val back = t("android-settings.vault.title")
    Column(Modifier.fillMaxSize()) {
        if (v == null || row == null) {
            NavBar(back, app::pop, back)
            Waiting(WaitShape.Cards, count = 2, error = vaults.error?.message ?: items.error?.message)
            return@Column
        }
        NavBar(
            back, app::pop, row.name.orEmpty(),
            sub = { Text(listOf(kindName(row.kind), t("web-pages.vault.storedOn", "station" to v.stationName)).filter { it.isNotEmpty() }.joinToString(" · "), fontSize = 11.sp, color = C.muted, maxLines = 1) },
            trailing = { RoundIcon(Icons.Edit, t("common.edit"), C.ink) { opened?.let { editorSheet(app, ws, vault, Editing(row, it), plain = plain) } ?: open { editorSheet(app, ws, vault, Editing(row, it), plain = plain) } } },
        )
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            if (plain) ListCard {
                Body {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Dot(false, warn = true)
                        Text(t("web-pages.vault.risk.title"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    }
                    Text(t("web-pages.vault.risk.body", "station" to v.stationName), fontSize = 14.sp, lineHeight = 21.sp, color = C.subtle)
                    Link(t("web-pages.vault.lib.turnOn")) { app.push(Screen.Security) }
                }
            }
            SectionHeader(t("web-pages.vault.content"), start = 24.dp)
            ListCard {
                val shown = opened
                if (shown == null) ListRow {
                    // Masked, as long whatever its length (which would say something of it).
                    Text("••••••••••••••••••••", fontSize = 14.sp, fontFamily = CodeFont, color = C.ink, maxLines = 1, overflow = TextOverflow.Clip, modifier = Modifier.weight(1f))
                    if (opening) Spinner(inline = true) else Link(t("web-pages.vault.show")) { open() }
                } else {
                    val fields = FIELDS[shown.kind] ?: shown.fields.keys.toList()
                    fields.forEach { f -> shown.fields[f]?.takeIf { it.isNotEmpty() }?.let { FieldRow(fieldName(f), it, secret = f !in OPEN_FIELDS) } }
                }
            }
            SectionHeader(t("web-pages.vault.forAgents"), start = 24.dp)
            ListCard {
                Body {
                    if (!row.listed) Text(t("web-pages.vault.notForAgents"), fontSize = 15.sp, color = C.muted)
                    else {
                        Fact(t("web-pages.vault.how"), row.modes.joinToString("、") { howLine(it, row.hosts) })
                        row.env?.ifEmpty { null }?.let { Fact(t("android-settings.vault.env"), it, mono = true) }
                    }
                }
            }
            SectionHeader(t("web-pages.vault.uses.title"), start = 24.dp)
            ListCard {
                val list = uses.value?.uses
                when {
                    list == null -> ListRow { Text(uses.error?.message ?: t("web-pages.settings.reading"), fontSize = 15.sp, color = C.muted) }
                    list.isEmpty() -> ListRow { Text(t("web-pages.vault.uses.none"), fontSize = 15.sp, color = C.muted) }
                    else -> list.forEach { UseRow(ws, it) }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** A fact of an item: its name in a narrow column, then what it is. */
@Composable
private fun Fact(label: String, value: String, mono: Boolean = false) = Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
    Text(label, fontSize = 14.sp, lineHeight = 21.sp, color = C.muted, modifier = Modifier.widthIn(min = 52.dp))
    Text(value, fontSize = if (mono) 14.sp else 15.sp, lineHeight = 21.sp, fontFamily = if (mono) CodeFont else null, color = C.ink, modifier = Modifier.weight(1f))
}

/** An agent's use of an item: its chat (turned down, said so), the command or how it was given, when; a tap opens the chat. */
@Composable
private fun UseRow(ws: String, u: VaultUse) {
    val app = LocalApp.current
    val warn = C.warn
    ListRow(onClick = u.station?.let { s -> { app.push(Screen.Chat("$ws/$s", ChatOf.Session(u.session))) } }) {
        Column(Modifier.weight(1f)) {
            Text(
                buildAnnotatedString {
                    append(u.chatTitle ?: u.session)
                    if (u.denied == true) withStyle(SpanStyle(color = warn)) { append(" · ${t("web-pages.vault.uses.denied")}") }
                },
                fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            Text(u.command ?: howLine(u.mode, u.hosts), fontSize = 13.sp, fontFamily = CodeFont, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(u.at.ago, fontSize = 13.sp, color = C.muted, maxLines = 1)
    }
}

/** A link in words in a card's body: no ground, flush with the text around it. */
@Composable
private fun Link(label: String, onClick: () -> Unit) = Text(label, fontSize = 15.sp, color = C.accent, modifier = Modifier.pressText(onClick = onClick))

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

/** `kind`: a new one of that kind (chosen in 添加), no kind to switch; `plain`: the library not locked, said at its top. */
private fun editorSheet(app: AppState, ws: String, vault: String, editing: Editing?, kind: String? = null, plain: Boolean = false) {
    app.sheet = SheetSpec(0.92f) { Editor(app, ws, vault, editing, kind, plain) }
}

/**
 * An item written (`vault.putItem`): its kind, name and fields, and whether agents may ask for it (then how it is given,
 * where to, under which variable). The sheet stays while it is saved (the system's prompt may come up for a locked
 * vault): turned down, nothing is lost; refused, why stands under it. 删除这一条 for one that is there.
 */
@Composable
private fun ColumnScope.Editor(app: AppState, ws: String, vault: String, editing: Editing?, fixed: String?, plainLibrary: Boolean) {
    val was = editing?.plain
    var kind by remember { mutableIntStateOf(KINDS.indexOf(was?.kind ?: fixed).coerceAtLeast(0)) }
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
        action = { Button(t("common.save"), primary = true, busy = saving, enabled = ready, height = SHEET_ACTION) { save() } },
    )
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (plainLibrary) Text(t("web-pages.vault.risk.editor"), fontSize = 13.sp, lineHeight = 19.sp, color = C.warn)
        if (was == null && fixed == null) Seg(KINDS.map(::kindName), kind, { kind = it }, Modifier.fillMaxWidth(), height = 34.dp, fill = true)
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
        // Its fields (rounded 12) in its corners 16 from both edges: its corner taken from theirs, concentric.
        Column(Modifier.fillMaxWidth().clip(Smooth(concentricOut(12.dp, 16.dp))).background(C.surface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().clip(Smooth(12.dp)).clickable { agent = !agent }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
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
