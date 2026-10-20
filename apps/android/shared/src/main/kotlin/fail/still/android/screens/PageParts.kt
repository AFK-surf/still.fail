// The pages' parts that more than one of their modules shows (:settings, :chat, :drive): a switch, a secret's field,
// a station's tag and chip, asking before something is done, where opened files are kept. Here so that the pages'
// modules stand side by side, none on another (2026-10-18).
package fail.still.android.screens

import fail.still.android.shared.BuildConfig
import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.Connect
import fail.still.android.data.ConnectItem
import fail.still.android.data.ConnectsView
import fail.still.android.data.MODE_LABEL
import fail.still.android.data.MODE_TEXT
import fail.still.android.data.MadeSlackApp
import fail.still.android.data.ModelOption
import fail.still.android.data.Overview
import fail.still.android.data.RUNTIME_LABEL
import fail.still.android.data.SlackTokenForm
import fail.still.android.data.StillFailJson
import fail.still.android.data.SlackTokensView
import fail.still.android.data.StationView
import fail.still.android.data.PickView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.CodeFont
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.BusyIcon
import fail.still.android.ui.WaitLine
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.android.ui.Smooth
import fail.still.android.ui.LIST_PAD
import fail.still.android.ui.CARD_PAD
import fail.still.android.ui.LocalOnCard
import fail.still.android.data.t
import fail.still.core.CoreException
import fail.still.android.data.errorText
import kotlinx.coroutines.launch
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import fail.still.android.ui.DoingMark
import fail.still.android.ui.PickRow
import fail.still.android.ui.Button
import fail.still.android.ui.Field
import fail.still.android.ui.GroupLabel
import fail.still.android.ui.Spinner
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import fail.still.android.data.LockDevice
import fail.still.android.data.LockDraftView
import fail.still.android.data.LockRequest
import fail.still.android.data.LockView
import fail.still.android.data.ROLE_LABEL
import fail.still.android.ui.LargeTitle
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.draw.alpha
import fail.still.android.data.ACCESS_LABEL
import fail.still.android.data.KEYED
import fail.still.android.data.LoginJob
import fail.still.android.data.MachineLogin
import fail.still.android.data.ProfileFlowView
import fail.still.android.data.Profile
import fail.still.android.data.ProfilesView
import fail.still.android.data.ShareStation
import fail.still.android.data.Quota
import fail.still.android.data.MembershipsView
import fail.still.android.ui.Card
import fail.still.android.ui.ProviderMark
import fail.still.android.ui.QuotaDials
import fail.still.android.ui.QuotaRings
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.putJsonArray
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.asPaddingValues
import fail.still.android.ui.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.foundation.Canvas
import androidx.compose.ui.graphics.drawscope.Stroke
import fail.still.android.shared.R
import fail.still.android.data.StationNet
import fail.still.android.data.NetFigure
import fail.still.android.ui.StationMark
import fail.still.android.ui.hasStationMark
import fail.still.android.ui.AgentStateMark
import fail.still.android.ui.ModelMark
import fail.still.android.data.ChatState
import fail.still.android.data.Maker
import fail.still.android.ui.Illustration
import fail.still.android.ui.breathing
import fail.still.android.ui.rememberBreath
import fail.still.android.ui.NavBack
import fail.still.android.ui.MeterChips
import fail.still.android.ui.MeterDials
import fail.still.android.ui.HostDetails
import fail.still.android.ui.stationName
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import fail.still.android.ui.MARK_COLORS
import fail.still.android.ui.glyphColor
import fail.still.android.ui.markColor
import androidx.compose.foundation.layout.aspectRatio
import fail.still.android.data.Cloud
import fail.still.android.data.Enrollment
import fail.still.android.data.JoinableStation
import fail.still.android.data.JoinableView
import fail.still.android.data.LoginSession
import fail.still.android.data.Member
import fail.still.android.data.ROLE_HINT
import fail.still.android.data.SlackPerson
import fail.still.android.ui.StationIcons
import fail.still.android.data.DriveCache
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.long
import java.io.File
import fail.still.android.ui.fileSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.rememberTextMeasurer
import fail.still.android.data.ChangelogItem
import fail.still.android.data.ChangelogLine
import fail.still.android.data.ChangelogView

@Composable
fun Switch(on: Boolean) {
    Box(Modifier.size(44.dp, 26.dp).clip(Smooth(13.dp)).background(if (on) C.green else C.line), contentAlignment = Alignment.CenterStart) {
        Box(Modifier.offset(x = if (on) 21.dp else 3.dp).size(20.dp).clip(CircleShape).background(androidx.compose.ui.graphics.Color.White))
    }
}

/** A token's line: shown as dots, pasted into. */
@Composable
fun SecretField(value: String, onChange: (String) -> Unit, placeholder: String) {
    Box(Modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.surface).border(1.dp, C.line, Smooth(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
        if (value.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, fontFamily = CodeFont, maxLines = 1, overflow = TextOverflow.Ellipsis)
        BasicTextField(value, { onChange(it.trim()) }, singleLine = true, cursorBrush = SolidColor(C.accent), visualTransformation = PasswordVisualTransformation(),
            textStyle = TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = CodeFont), modifier = Modifier.fillMaxWidth())
    }
}

/** Words on a card: on a list card (its padding in already) its words CARD_PAD from the card's edge, as its rows'. */
@Composable
fun Body(content: @Composable () -> Unit) {
    val onCard = LocalOnCard.current
    Column(Modifier.fillMaxWidth().padding(horizontal = if (onCard) CARD_PAD - LIST_PAD else 16.dp, vertical = if (onCard) 12.dp else 14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
}

/** A check's tone as a colour (the core's: accent | green | blue | red | neutral). */
@Composable
fun toneColor(tone: String): Color = when (tone) { "green" -> C.green; "red" -> C.red; "blue" -> C.blue; "accent" -> C.accent; else -> C.muted }

/**
 * The station a chat runs on, in its bar: its icon and name, short; a tap opens
 * its card (the web's is a hover card over the same tag: web/src/cloud/StationCards.tsx StationPeek).
 */
@Composable
fun ChatStationChip(address: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(address.substringBefore('/')))
    val list = stations.value ?: return
    val s = list.firstOrNull { it.station == address } ?: return
    StationTag(s.name, s.emoji, s.icon, Modifier.clickable { Elsewhere.stationPeek(app, address) }, via = stationVia(s))
}

/**
 * A chat's first agent in its bar with the station it runs on, one tile (web ui.tsx AgentMark with children, as the phone
 * web's bar): the maker's square, then the station's icon, or its name where it has none; the agent's state on the
 * maker's corner, how the station is reached on the tile's (StationViaDot). One tap for all of it (halves
 * this small are not told apart under a finger): the agent's card, which leads on to the station's. Until the station
 * is known, the agent's mark alone.
 */
@Composable
fun AgentStationMark(address: String, who: String, maker: Maker?, runtime: String, state: ChatState?, onAgent: () -> Unit) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(address.substringBefore('/')))
    val s = stations.value?.firstOrNull { it.station == address }
    // Not clipped: the state's dot sits over the tile's corner, partly outside it.
    if (s == null) {
        Box(Modifier.clickable(onClick = onAgent)) { ModelMark(maker, runtime, 22.dp, state, listMark = true) }
        return
    }
    val shape = Smooth(6.dp)
    Box(Modifier.semantics(mergeDescendants = true) { contentDescription = "$who · ${s.name}" }) {
        Row(
            Modifier.height(22.dp).clip(shape).background(C.surface).border(1.dp, C.line, shape).clickable(onClick = onAgent),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) { MakerIcon(maker, runtime, 13.2.dp) }
            Box(Modifier.widthIn(max = 96.dp).padding(horizontal = 5.dp), contentAlignment = Alignment.Center) {
                if (hasStationMark(s.emoji, s.icon)) StationMark(s.emoji, s.icon, 13.dp, C.muted)
                else Text(s.name, fontSize = 12.sp, lineHeight = 14.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        // The agent's state on the maker's corner; the station's on the tile's, how it is reached.
        if (state != null) AgentStateMark(state, C.bg, Modifier.align(Alignment.BottomStart).offset(13.dp, 3.dp))
        stationVia(s)?.let { StationViaDot(it, 10.dp, 2.dp, Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp)) }
    }
}

/** A station named in a small outlined tag, its icon before its name (in a chat's bar, how it is reached as a dot before both): in a chat's bar (ChatStationChip) and the composer's chats from elsewhere. */
@Composable
fun StationTag(name: String, emoji: String?, icon: String?, modifier: Modifier = Modifier, via: String? = null) {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier.widthIn(max = 104.dp).clip(shape).border(1.dp, C.line, shape).then(modifier)
            .padding(horizontal = 8.dp, vertical = 2.dp).semantics { contentDescription = name },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (via != null) StationViaDot(via, 7.dp)
        if (hasStationMark(emoji, icon)) StationMark(emoji, icon, 12.dp, C.muted)
        Text(name, fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Asks before something that cannot be undone. With `what` (a verb phrase, as [AppState.act] takes) the sheet closes at
 * once, `then` runs (a page left, say) and `run` goes on by itself, the thing it is about marked under way, a failure
 * told by a toast; without it the sheet stays, with what went wrong, until it is done.
 */
fun confirm(app: AppState, title: String, text: String, action: String, danger: Boolean = false, what: String? = null, then: () -> Unit = {}, run: suspend () -> Unit) {
    app.sheet = SheetSpec(0.36f) {
        val scope = rememberCoroutineScope()
        val operation = remember(app) { Action(app) }
        val busy = operation.busy
        val error = operation.error?.message
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(text, fontSize = 14.sp, color = C.muted)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, danger = danger) {
                    if (what != null) { app.sheet = null; then(); app.act(what) { run() } }
                    else operation.run { run(); app.sheet = null }
                }
            }
        }
    }
}

/** Asks for a line (a name); `run` gets it trimmed. With `what`, as [confirm]: closes at once and goes on by itself. */
fun ask(app: AppState, title: String, value: String, placeholder: String, action: String, secret: Boolean = false, hint: String? = null, what: String? = null, empty: Boolean = false, run: suspend (String) -> Unit) {
    app.sheet = SheetSpec(0.42f) {
        val scope = rememberCoroutineScope()
        var text by remember { mutableStateOf(value) }
        val operation = remember(app) { Action(app) }
        val busy = operation.busy
        val error = operation.error?.message
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (secret) SecretField(text, { text = it }, placeholder) else Field(text, { text = it }, placeholder)
            hint?.let { Text(it, fontSize = 12.sp, color = C.muted) }
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(action, primary = true, busy = busy, enabled = (empty || text.isNotBlank()) && text.trim() != value) {
                    val line = text.trim()
                    if (what != null) { app.sheet = null; app.act(what) { run(line) } }
                    else operation.run { run(line); app.sheet = null }
                }
            }
        }
    }
}

object KeptFiles {
    fun dir(context: Context) = File(context.cacheDir, "files")
    private const val ORIGIN = ".origin"

    /** Where a file (by its id, `<station>/<session>/<path>`, and size) is kept, under its own name; its directory made,
     * where it came from written beside it. */
    fun place(context: Context, id: String, name: String, size: Long): File {
        val safe = name.substringAfterLast('/').replace(Regex("[\\u0000-\\u001f]"), "_").trimStart('.').take(120).ifEmpty { "file" }
        val home = File(dir(context), "${Integer.toHexString(id.hashCode())}-$size").apply { mkdirs() }
        File(home, ORIGIN).takeIf { !it.exists() }?.writeText(id)
        return File(home, safe)
    }

    /** Every file kept, the latest opened first: each in its directory, and loose ones from before names were kept. */
    fun list(context: Context): List<KeptFile> {
        val out = ArrayList<KeptFile>()
        fun add(f: File, origin: String?) {
            val partial = f.name.endsWith(".part")
            val parts = origin?.split('/')
            val (station, session) = if (parts != null && parts.size >= 3) "${parts[0]}/${parts[1]}" to parts[2] else null to null
            out += KeptFile(f, if (partial) f.name.removeSuffix(".part") else f.name, f.length(), f.lastModified(), partial, station, session)
        }
        dir(context).listFiles()?.forEach { f ->
            if (f.isDirectory) {
                val origin = File(f, ORIGIN).takeIf { it.exists() }?.readText()
                f.listFiles()?.filter { it.isFile && it.name != ORIGIN }?.forEach { add(it, origin) }
            } else add(f, null)
        }
        return out.sortedByDescending { it.opened }
    }

    /** Deletes a kept file (its directory with it, once nothing else is in it). */
    fun delete(context: Context, kept: KeptFile) {
        kept.file.delete()
        val home = kept.file.parentFile ?: return
        if (home != dir(context) && home.listFiles()?.all { it.name == ORIGIN } == true) home.deleteRecursively()
    }

    private fun sizeOf(f: File): Long = if (f.isDirectory) f.listFiles()?.sumOf { sizeOf(it) } ?: 0L else f.length()

    private fun webCache(context: Context) = File(context.cacheDir, "WebView")
    private fun updates(context: Context) = File(context.cacheDir, "updates")
    /** Temporary files of the app's own (a marked image made, say): the cache but for what is counted apart. */
    private fun temporary(context: Context) = context.cacheDir.listFiles()?.filter { it.name !in setOf("files", "WebView", "updates", DriveCache.dir(context).name, DriveCache.playedDir(context).name) }.orEmpty()

    /** Everything kept, read now: the core says what it keeps of each chat. */
    suspend fun read(app: AppState, context: Context): Kept {
        val usage = try { app.core.call("cache.usage").jsonObject["chats"]?.jsonArray ?: JsonArray(emptyList()) } catch (_: Exception) { JsonArray(emptyList()) }
        return withContext(Dispatchers.IO) {
            val files = list(context)
            val bySession = files.filter { it.station != null }.groupBy { it.station to it.session }
            val used = HashSet<KeptFile>()
            val chats = usage.map { e ->
                val o = e.jsonObject
                val station = o["station"]!!.jsonPrimitive.content
                val thread = o["thread"]!!.jsonPrimitive.long
                val sessions = o["sessions"]?.jsonArray?.map { it.jsonPrimitive.content }.orEmpty()
                val mine = sessions.flatMap { bySession[station to it].orEmpty() }.filter { used.add(it) }
                KeptChat(station, thread, o["title"]?.jsonPrimitive?.contentOrNull ?: t("android-settings.files.untitled", "n" to thread), o["bytes"]?.jsonPrimitive?.long ?: 0L, mine)
            }
            val loose = files.filter { it !in used }
            val data = (sizeOf(File(context.filesDir, "stillfail-core")) - chats.sumOf { it.messages }).coerceAtLeast(0L)
            Kept(chats.sortedByDescending { it.size }, loose, DriveCache.size(context), sizeOf(webCache(context)), sizeOf(updates(context)), temporary(context).sumOf { sizeOf(it) }, data)
        }
    }

    /** Forgets a chat's messages (read again from its station when it is opened) and deletes its files. */
    suspend fun clearChat(app: AppState, context: Context, chat: KeptChat) {
        app.core.call("cache.clear", buildJsonObject { put("station", chat.station); put("thread", chat.thread) })
        withContext(Dispatchers.IO) { chat.files.forEach { delete(context, it) } }
    }

    suspend fun clearDrive(context: Context) = withContext(Dispatchers.IO) { DriveCache.clear(context) }
    suspend fun clearWeb(context: Context) = withContext(Dispatchers.IO) { webCache(context).deleteRecursively(); Unit }
    suspend fun clearUpdates(context: Context) = withContext(Dispatchers.IO) { updates(context).deleteRecursively(); Unit }
    suspend fun clearTemporary(context: Context) = withContext(Dispatchers.IO) { temporary(context).forEach { it.deleteRecursively() } }

    /** Everything that can go: every chat's, files of no chat, files opened from drives, web pages', update packages, temporary files. */
    suspend fun clearAll(app: AppState, context: Context, kept: Kept) {
        kept.chats.forEach { clearChat(app, context, it) }
        withContext(Dispatchers.IO) { kept.loose.forEach { delete(context, it) } }
        clearDrive(context); clearWeb(context); clearUpdates(context); clearTemporary(context)
    }
}

/** A file kept on the phone: where it is, its name, how big, when last opened; `partial`, a fetch that stopped;
 * `station` and `session`, where it came from (none for one kept before that was written beside it). */
class KeptFile(val file: File, val name: String, val size: Long, val opened: Long, val partial: Boolean, val station: String?, val session: String?)

/** A chat as kept here: its messages (`messages`, as the core counts them) and the files opened in it. */
class KeptChat(val station: String, val thread: Long, val title: String, val messages: Long, val files: List<KeptFile>) {
    val size get() = messages + files.sumOf { it.size }
}

/** What is kept here: by chat, files of no chat known, and what belongs to no chat. */
class Kept(val chats: List<KeptChat>, val loose: List<KeptFile>, val drive: Long, val web: Long, val updates: Long, val temporary: Long, val data: Long) {
    val total get() = chats.sumOf { it.size } + loose.sumOf { it.size } + drive + web + updates + temporary + data
}

/** A connect's presence as a dot: online green, at work orange, failing red, offline hollow. */
@Composable
fun PresenceDot(state: String) {
    val m = Modifier.size(7.dp).clip(CircleShape)
    Box(when (state) {
        "online" -> m.background(C.green)
        "busy" -> m.background(C.accent)
        "error" -> m.background(C.red)
        else -> m.border(1.5.dp, C.subtle, CircleShape)
    })
}

/**
 * How this device reaches a station, as a dot where a chat names it (web StationLink.tsx): straight there (green),
 * through a relay (amber), away (red), else coming back or a way still being chosen (a grey ring); null before it is known.
 */
fun stationVia(s: StationView): String? = when {
    !s.online -> "offline"
    s.reconnecting == true -> "waiting"
    else -> when (s.way?.via) { "direct" -> "direct"; "relay" -> "relay"; "choosing" -> "waiting"; else -> null }
}

/** The dot of [stationVia], `size` across with a ring of the ground round it when [ring] is given (on a tile's corner). */
@Composable
fun StationViaDot(via: String, size: Dp, ring: Dp = 0.dp, modifier: Modifier = Modifier) {
    val c = C
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2
        if (ring > 0.dp) drawCircle(c.bg, r)
        val inner = r - ring.toPx()
        when (via) {
            "direct" -> drawCircle(c.green, inner)
            "relay" -> drawCircle(c.warn, inner)
            "offline" -> drawCircle(c.red, inner)
            else -> { val w = 1.5.dp.toPx(); drawCircle(c.muted, inner - w / 2, style = Stroke(w)) }
        }
    }
}

/** At the top of the list after an update: the build it is now and what it brought; opens the changelog. */
@Composable
fun ChangelogNews() {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val topic by rememberTopic<ChangelogView>(app.core, Topics.changelog)
    // Let go (知道了): gone at once, before the core has it.
    var gone by remember { mutableStateOf<Any?>(null) }
    val news = topic.value?.news ?: return
    if (gone == news) return
    val lines = news.entries.flatMap { it.text }
    // Its close button, round, in its corner 6 from both edges: the card's corner taken from it (6 + its half).
    Box(Modifier.padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 10.dp).fillMaxWidth().clip(Smooth(6.dp + 16.dp)).background(C.surface)) {
        Column(Modifier.fillMaxWidth().clickable { app.push(Screen.Changelog) }.padding(start = 16.dp, end = 44.dp, top = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.padding(bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                IconIn(Icons.Sparks, 16.dp, C.ink)
                Text(news.build?.let { t("android-settings.changelog.updatedTo", "build" to it) } ?: t("android-settings.changelog.updated"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            }
            lines.take(3).forEach { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            if (lines.size > 3) Text(t("android-settings.changelog.more", "n" to lines.size - 3), fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
        }
        Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(32.dp).clip(CircleShape).clickable { gone = news; app.scope.launch { seen(app) } }.semantics { contentDescription = t("android-settings.changelog.dismiss") }, contentAlignment = Alignment.Center) {
            IconIn(Icons.Close, 16.dp, C.muted)
        }
    }
}

/** Says the changelog was seen up to this build: what it brought is not news any more. */
suspend fun seen(app: AppState) {
    try { app.core.call("changelog.seen", buildJsonObject {}) } catch (_: CoreException) {}
}
