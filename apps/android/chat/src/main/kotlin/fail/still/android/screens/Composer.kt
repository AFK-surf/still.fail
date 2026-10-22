// The chat's composer (web/src/mobile/ChatHost.tsx, and ../Chat.tsx's useComposerText and ComposerExtras): what is being
// written (each chat's own draft, kept on the device: web/src/draft.ts), the quotes and files going with it, `@` and a
// few letters naming another chat of the station (web/src/ChatRef.tsx), and the bar. An archived chat's composer says
// so and restores it (web/src/ArchiveNotice.tsx).
package fail.still.android.screens

import fail.still.android.ui.Spinner
import fail.still.android.ui.BusyIcon
import fail.still.android.ui.WaitLine
import fail.still.android.data.t
import fail.still.android.shared.BuildConfig
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import fail.still.android.ui.InComposer
import fail.still.android.ui.Raised
import fail.still.android.ui.InComposerFiles
import fail.still.android.ui.concentric
import fail.still.android.ui.smoothMiddle
import fail.still.android.ui.ComposerFilesIn
import fail.still.android.ui.ComposerInset
import fail.still.android.ui.ComposerCorner
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.runtime.Stable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import fail.still.android.ui.Ease
import kotlin.math.roundToInt
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.content.consume
import androidx.compose.foundation.content.contentReceiver
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.OutputTransformation
import androidx.compose.foundation.text.input.TextFieldBuffer
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.delete
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.data.Attachment
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.ChatSearchView
import fail.still.android.data.Quote
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.floating
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import fail.still.core.PickedFiles
import fail.still.android.data.ComposerFile
import fail.still.android.data.ComposerView
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import fail.still.android.data.errorText
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.MainScope
import fail.still.android.data.OutsideRef
import fail.still.android.data.StationApi
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import fail.still.android.data.ComposerLink
import fail.still.android.data.DraftView
import fail.still.android.data.decode
import fail.still.core.StillFailCore
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import fail.still.android.ui.Button
import fail.still.android.ui.fileSize
import fail.still.android.ui.chatInk
import fail.still.android.ui.chatMuted
import fail.still.android.ui.chatSubtle
import fail.still.android.ui.quoteGround
import fail.still.android.ui.TextFont
// ── the draft ──────────────────────────────────────────────────────────

/**
 * A file on its way to the station: uploading, uploaded, or failed. `local`: a picture's bytes as picked (one read
 * whole), what the viewer shows it from before it is sent (no session keeps it yet), with its size. `pasted`: the text
 * it was made of, pasted (PastedText.kt).
 */
class Pending(val id: Long, val name: String, val size: Long, val preview: ImageBitmap?, val local: ByteArray? = null, val width: Int? = null, val height: Int? = null, val pasted: PastedText? = null, val ref: RefFile? = null, val link: ComposerLink? = null) {
    var done by mutableStateOf<Attachment?>(null)
    /** How much of it the station has, as it goes up in parts. */
    var sent by mutableStateOf<Long?>(null)
    var error by mutableStateOf<String?>(null)
    /** Failed going up: sends it up again, from what was picked (null: it cannot be, as one too big). */
    var retry by mutableStateOf<(() -> Unit)?>(null)
    /** Its id in the core, which sends it up (`composer.add`): a message sent before it is up names it (`uploads`). */
    internal var coreId: String? = null
    /** A file of a station's named by its path (StationFiles.kt), or a link shared in (share/): it goes as words, nothing goes up. */
    val named get() = ref?.mode == "path" || link != null
}

/** A passage quoted in the message being written, with what is said about it. */
class DraftQuote(val id: Long, val author: String, val text: String, val ts: String?, val role: String, val file: String? = null) {
    var comment by mutableStateOf("")
    fun sent() = Quote(author, text, comment.trim(), ts, role, file)
}

/**
 * What is being written: text (with where the cursor is), quotes, files. A chat's draft is its own (Drafts): leaving the
 * chat, or the app, keeps it for when the chat is opened again; a new chat's lives while its page does.
 */
class Draft {
    /** The text box's own (it takes what is pasted, files and pictures too: ComposerBar). */
    val state = TextFieldState()
    /** Its text and where the cursor is; set, both are replaced. */
    var input: TextFieldValue
        get() = TextFieldValue(state.text.toString(), state.selection)
        set(value) { state.edit { replace(0, length, value.text); selection = value.selection } }
    /** The text; set, the cursor goes to its end. */
    var text: String
        get() = state.text.toString()
        set(value) { state.setTextAndPlaceCursorAtEnd(value) }
    val quotes = mutableStateListOf<DraftQuote>()
    val files = mutableStateListOf<Pending>()
    /** A new chat is being made for the first message. */
    var starting by mutableStateOf(false)
    /** What it refers to is being looked at before it goes (sendSharing): a second tap of send does nothing meanwhile. */
    internal var checking = false
    var error by mutableStateOf<String?>(null)
    /** The quote whose comment line takes the focus. */
    var focusQuote by mutableStateOf<Long?>(null)
    /** Bumped to put the cursor in the text. */
    var focus by mutableIntStateOf(0)
    var warmed = 0L
    val uploading get() = files.any { it.done == null && it.error == null && !it.named }
    /** Nothing can be sent (its station is offline, or the chat archived). */
    var locked by mutableStateOf(false)
    /** A file that did not go up: it is sent again or taken out first, never left out of the message unsaid. */
    val failed get() = files.any { it.error != null && !it.named }
    /** A file going up outside the core (a station's file switched to one, StationFiles.kt): sending waits for it here. */
    private val goingHere get() = files.any { it.done == null && it.error == null && !it.named && it.coreId == null }
    /** Sent while a file is still going up, the message waits for it in the outbox (`uploads`), as the web's does. */
    val ready get() = (text.isNotBlank() || files.any { it.done != null || it.coreId != null || it.named } || quotes.isNotEmpty()) && !goingHere && !failed && !starting && !locked
    /**
     * Where its files go up in the core: a composer of their own there (`composer.add`), by a key no chat has, so nothing
     * of it is kept; this draft keeps what is written.
     */
    internal val uploadKey = "phone-${System.nanoTime()}"
    /** The core its files go up through, once one has. */
    internal var core: StillFailCore? = null

    /** A file taken out: one going up stops (the core lets go of it). */
    fun takeOut(f: Pending) {
        files.remove(f)
        val id = f.coreId ?: return
        val core = core ?: return
        if (f.done == null) Drafts.tell(core, "composer.remove", buildJsonObject { put("key", uploadKey); put("id", id) })
    }
    /** The text box has the focus (the menu of chats shows only then). */
    var focused by mutableStateOf(false)
    /** Where an `@` was put away (its menu closed by picking a chat): not offered again. */
    var refClosed by mutableStateOf<Int?>(null)

    /** The key it is kept on the device by (Drafts); null: not kept. */
    internal var keptAs: String? = null
    /** What the core kept of it has been read: only then is it kept as it is (not written over before). */
    internal var loaded = false
    /** Keeps it on the device as it is now (a chat's draft). */
    fun save() { keptAs?.takeIf { loaded }?.let { Drafts.save(it, this) } }

    internal fun fill(kept: DraftView) {
        text = kept.text
        kept.quotes.forEach { q -> quotes += DraftQuote(System.nanoTime(), q.author, q.text, q.ts, q.role ?: "person", q.file).also { it.comment = q.comment } }
        kept.files.forEach { a -> files += Pending(System.nanoTime(), a.name, a.size, null, width = a.width?.toInt(), height = a.height?.toInt()).also { it.done = a } }
        kept.links.orEmpty().forEach { files += linkPending(it) }
    }

    /**
     * What the core holds of it now, in place of what was kept (something shared into it while it was open: the core
     * put it there, share/ShareActivity.kt); files still going up stay.
     */
    internal fun replace(kept: DraftView) {
        val going = files.filter { it.done == null && it.error == null && !it.named }
        quotes.clear(); files.clear()
        fill(kept)
        files.addAll(going)
    }
    internal val empty get() = text.isEmpty() && quotes.isEmpty() && files.isEmpty()

    fun quote(author: String, text: String, ts: String?, role: String) {
        val q = DraftQuote(System.nanoTime(), author, text, ts, role)
        quotes += q
        focusQuote = q.id
    }

    /** Empties it, for what is sent: the text (its references' marks, which the core makes links) with where each file
     *  named by its path is (StationFiles.kt), the files up, the quotes. */
    fun take(): Taken {
        val named = files.filter { it.named }
        // After the text: each link (its title on a line, then it), then where each file named by its path is (as the core's composer.take).
        val links = named.mapNotNull { it.link }.map { l -> listOfNotNull(l.title?.takeIf { it.isNotEmpty() }, l.url).joinToString("\n") }
        val words = (listOf(text.trim()) + links + named.mapNotNull { f -> f.ref?.let { pathWords(it) } }).filter { it.isNotEmpty() }.joinToString("\n")
        val taken = Taken(words, files.filter { !it.named }, quotes.toList(), text, named)
        text = ""; files.clear(); quotes.clear(); error = null; refClosed = null
        save()
        return taken
    }

    /** Puts back what `take` took (sending it failed). */
    fun restore(t: Taken) { text = t.written; files.addAll(t.named + t.files); quotes.addAll(t.quotes); save() }
}

/** What a draft held when it was sent: `text` as it goes (trimmed), `written` as it was typed. */
class Taken(val text: String, val files: List<Pending>, val quotes: List<DraftQuote>, val written: String, val named: List<Pending> = emptyList()) {
    /** The files up, as the message takes them. */
    val attachments get() = files.mapNotNull { it.done }
    /** Those still going up: the message waits for them in the outbox (the core sends it once they are). */
    val uploads get() = files.filter { it.done == null && it.error == null && it.coreId != null }
        .map { ComposerFile(it.coreId!!, it.name, it.size, width = it.width?.toLong(), height = it.height?.toLong()) }
}

@Serializable
private class KeptQuote(val author: String, val text: String, val comment: String = "", val ts: String? = null, val role: String = "person", val file: String? = null)

/** How the app kept a draft before the core did (in its "drafts" preferences): moved into the core when next opened. */
@Serializable
private class KeptDraft(val text: String = "", val quotes: List<KeptQuote> = emptyList(), val files: List<Attachment> = emptyList())

/**
 * Each chat's draft, by its station's address and the chat ("<address>:<chat>", or "new:<address>" for a new chat
 * there, as the web keys it): the same one while the app runs (files still going up go on); what it holds (the text,
 * the quotes with what is said about them, the files already up; the station keeps those in no chat until a message
 * takes them) the core keeps on the device (its `draft` topic, `draft.put`), as it does for the web.
 */
object Drafts {
    private val open = HashMap<String, Draft>()
    private var core: StillFailCore? = null
    private var prefs: SharedPreferences? = null
    private val scope = MainScope()

    private fun prefs(context: Context) = prefs ?: context.applicationContext.getSharedPreferences("drafts", Context.MODE_PRIVATE).also { prefs = it }

    fun of(context: Context, core: StillFailCore, key: String): Draft = open.getOrPut(key) {
        this.core = core
        ChatRefs.migrate(context, core)
        Draft().apply {
            keptAs = key
            // Kept by the app before the core kept drafts: into the core, once.
            val p = prefs(context)
            val old = p.getString(key, null)?.let { runCatching { StillFailJson.decodeFromString(KeptDraft.serializer(), it) }.getOrNull() }
            if (old != null) {
                fill(DraftView(old.text, old.quotes.map { Quote(it.author, it.text, it.comment, it.ts, it.role, it.file) }, old.files))
                p.edit().remove(key).apply()
                loaded = true
                save()
                return@apply
            }
            scope.launch {
                // A core that keeps none (or refuses the key): nothing kept.
                val kept = try { core.call("draft.get", buildJsonObject { put("key", key) }) } catch (_: CoreException) { null }
                    ?.takeIf { it !is JsonNull }?.let { runCatching { decode(DraftView.serializer(), it) }.getOrNull() }
                // Written here meanwhile: that is what is kept now.
                if (kept != null && empty) fill(kept)
                loaded = true
                if (!empty) save()
            }
        }
    }

    /** Something was put in `key`'s draft by the core (shared into it, share/): an open one takes what the core has now. */
    fun refresh(key: String) {
        val d = open[key] ?: return
        val core = core ?: return
        scope.launch {
            val kept = try { core.call("draft.get", buildJsonObject { put("key", key) }) } catch (_: CoreException) { null }
                ?.takeIf { it !is JsonNull }?.let { runCatching { decode(DraftView.serializer(), it) }.getOrNull() } ?: return@launch
            d.replace(kept)
        }
    }

    /** A composer call nobody waits on (a file taken out): its failure changes nothing here. */
    internal fun tell(core: StillFailCore, name: String, params: kotlinx.serialization.json.JsonObject) {
        scope.launch { try { core.call(name, params) } catch (_: CoreException) {} }
    }

    internal fun save(key: String, d: Draft) {
        val core = core ?: return
        val view = DraftView(d.text, d.quotes.map { it.sent().copy(comment = it.comment) }, d.files.mapNotNull { it.done }, d.files.mapNotNull { it.link })
        val params = buildJsonObject {
            put("key", key)
            StillFailJson.encodeToJsonElement(DraftView.serializer(), view).jsonObject.forEach { (k, v) -> put(k, v) }
        }
        // A core that refuses it keeps nothing: the draft lives while the app does.
        scope.launch { try { core.call("draft.put", params) } catch (_: CoreException) {} }
    }
}

/** A chat's draft (Drafts), kept on the device as it changes (the core writes it down a moment after) and when the page goes. */
@Composable
fun rememberDraft(station: String, of: ChatOf): Draft =
    rememberDraft("$station:" + when (of) { is ChatOf.Session -> of.key; is ChatOf.Thread -> "thread:${of.id}" })

/** The draft kept by `key` (Drafts): a chat's, or a new chat's on a station ("new:<address>", as the web keys it). */
@Composable
fun rememberDraft(key: String): Draft {
    val context = LocalContext.current
    val core = LocalApp.current.core
    val draft = remember(key) { Drafts.of(context, core, key) }
    LaunchedEffect(draft) {
        snapshotFlow { Triple(draft.text, draft.quotes.map { it.id to it.comment }, draft.files.map { it.id to it.done }) }
            .drop(1).collect { draft.save() }
    }
    DisposableEffect(draft) { onDispose { draft.save() } }
    return draft
}

// ── references to other chats (web/src/chatRefs.ts, ChatRef.tsx) ───────────

/**
 * References to other chats in what is written: in the composer a short mark, `@[its title]`, drawn in the accent; sent,
 * a link, `[its title](<cloud>/w/<workspace>/s/<station>/chats/<key>)`, which the agent reads the chat by and a message
 * draws as a chip. The core makes the mark of a chat picked and keeps its link until the mark is sent (`chat.ref`,
 * client/core-ts/src/refs.ts).
 */
object ChatRefs {
    val MARK = Regex("@\\[([^\\]\\n]{1,120})\\]")
    private var migrated = false

    /** Links the app kept before the core did (its "chatRefs" preferences): into the core, once. */
    fun migrate(context: Context, core: StillFailCore) {
        if (migrated) return
        migrated = true
        val prefs = context.applicationContext.getSharedPreferences("chatRefs", Context.MODE_PRIVATE)
        val stored = prefs.getString("links", null) ?: return
        val links = runCatching { StillFailJson.decodeFromString(MapSerializer(String.serializer(), String.serializer()), stored) }.getOrNull().orEmpty()
        MainScope().launch {
            try {
                core.call("chat.refs", buildJsonObject { put("links", JsonArray(links.map { (t, l) -> JsonArray(listOf(JsonPrimitive(t), JsonPrimitive(l))) })) })
                prefs.edit().remove("links").apply()
            } catch (_: CoreException) {}
        }
    }

    /** The `@words` the caret is at the end of, and where the `@` is; null when it is not in one. */
    fun at(text: String, caret: Int): Pair<Int, String>? {
        val m = Regex("(?:^|\\s)@([^\\s@\\[\\]()]{0,40})$").find(text.substring(0, caret.coerceIn(0, text.length))) ?: return null
        val query = m.groupValues[1]
        return (caret - query.length - 1) to query
    }

    /** The mark just before `caret` (a backspace there takes it whole), or null. */
    fun before(text: String, caret: Int): Int? = Regex("@\\[[^\\]\\n]{1,120}\\]$").find(text.substring(0, caret))?.range?.first
}

/** The composer's text with each mark drawn in the accent, its `[` before the `@` and both brackets unseen (the same letters in the same places). */
private class RefMarks(private val accent: Color) : OutputTransformation {
    override fun TextFieldBuffer.transformOutput() {
        val marks = ChatRefs.MARK.findAll(asCharSequence()).toList()
        marks.forEach { m -> replace(m.range.first, m.range.first + 2, "[@") }
        marks.forEach { m ->
            addStyle(SpanStyle(color = Color.Transparent), m.range.first, m.range.first + 1)
            addStyle(SpanStyle(color = accent), m.range.first + 1, m.range.last)
            addStyle(SpanStyle(color = Color.Transparent), m.range.last, m.range.last + 1)
        }
    }
}

/**
 * Puts each chat's link pasted in `pasted` (`linkedRefs`) as its mark, the core keeping its link as for one picked with
 * `@` (a link to its agent's execution history kept as that link); one the core cannot make a mark of stays as it is.
 * Written on meanwhile: each link where it is now, if it still is.
 */
private suspend fun markPasted(app: AppState, draft: Draft, pasted: String, refs: List<Pair<MatchResult, LinkedChat>>) {
    val made = refs.map { (m, chat) ->
        try {
            val mark = app.core.call("chat.ref", buildJsonObject { put("station", chat.station); put("id", chat.id); put("title", m.groupValues[1]); put("base", app.cloudOrigin) })
                .jsonObject["mark"]?.jsonPrimitive?.content ?: m.value
            if (chat.history.isNotEmpty() && mark != m.value) {
                val at = chat.station.indexOf('/')
                val page = "${app.cloudOrigin.trimEnd('/')}/w/${chat.station.substring(0, at)}/s/${chat.station.substring(at + 1)}/chats/${encodeComponent(chat.id)}${chat.history}"
                app.core.call("chat.refs", buildJsonObject { put("links", JsonArray(listOf(JsonArray(listOf(JsonPrimitive(mark.substring(2, mark.length - 1)), JsonPrimitive(page)))))) })
            }
            mark
        } catch (_: CoreException) { m.value }
    }
    val now = draft.input
    var text = now.text
    var caret = now.selection.start
    // Last first, so the places of those before stay as they are.
    refs.indices.reversed().forEach { i ->
        val m = refs[i].first
        val at = if (now.text == pasted) m.range.first else text.indexOf(m.value).takeIf { it >= 0 } ?: return@forEach
        text = text.substring(0, at) + made[i] + text.substring(at + m.value.length)
        if (caret >= at + m.value.length) caret += made[i].length - m.value.length
    }
    if (text != now.text) draft.input = TextFieldValue(text, TextRange(caret.coerceIn(0, text.length)))
}

/** The address's workspace (the scope of its chats' list). */
private fun scopeOf(address: String) = address.substringBefore('/')

/**
 * `@` and a few letters in the text: the chats of this station it finds (another station's agents cannot read them,
 * the core's `chatSearch`), titles first, but not `here` (the chat written in); then those of the viewer's other
 * workspaces (`elsewhere`), each with its workspace's name after its title, as a tag (sent, one is shared with this
 * workspace first: sendSharing). The one picked goes in as the mark the core makes of it. Over the composer, in its glass.
 */
@Composable
fun ChatRefMenu(draft: Draft, station: String, here: String?, haze: HazeState, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val field = draft.input
    val found = if (field.selection.collapsed && draft.focused && !draft.locked) ChatRefs.at(field.text, field.selection.start) else null
    val ref = found?.takeIf { it.first != draft.refClosed }
    if (found == null && draft.refClosed != null) draft.refClosed = null
    if (ref == null) return
    val (start, query) = ref
    val search by rememberTopic<ChatSearchView>(app.core, Topics.chatSearch(scopeOf(station), query, station, here, 8, elsewhere = true))
    val items = search.value?.items ?: emptyList()
    val pick = { item: fail.still.android.data.ChatItem ->
        val caret = field.selection.start
        draft.refClosed = start
        scope.launch {
            // Its mark, from the core, which keeps its link until it is sent; in its place if the `@words` are still there.
            val mark = try {
                app.core.call("chat.ref", buildJsonObject { put("station", item.station); put("id", item.id); put("title", item.title); put("base", app.cloudOrigin); put("into", scopeOf(station)) })
                    .jsonObject["mark"]?.jsonPrimitive?.content
            } catch (e: CoreException) { app.toast = t("android-chat.ref.failed", "error" to errorText(e)); null } ?: return@launch
            val now = draft.input.text
            if (now.getOrNull(start) != '@' || caret > now.length) return@launch
            draft.input = TextFieldValue(now.substring(0, start) + mark + " " + now.substring(caret), TextRange(start + mark.length + 1))
        }
    }
    Column(
        modifier.fillMaxWidth().padding(bottom = 8.dp).floating(haze, Smooth(ComposerCorner)).heightIn(max = 320.dp)
            .verticalScroll(rememberScrollState()).padding(12.dp),
    ) {
        Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(t("android-chat.ref.title"), fontSize = 13.sp, color = C.muted)
            if (query.isNotEmpty()) Text(query, fontSize = 13.sp, color = C.ink)
        }
        when {
            search.value == null && search.error != null -> Text(t("android-chat.ref.update", "app" to BuildConfig.APP_NAME), fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 4.dp))
            search.value == null -> WaitLine(t("common.reading"), modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 4.dp))
            items.isEmpty() -> Text(if (query.isNotEmpty()) t("android-chat.ref.none.match") else t("android-chat.ref.none"), fontSize = 15.sp, color = C.muted,
                modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 4.dp))
            else -> items.forEach { item ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(Smooth(concentric(ComposerCorner, 12.dp))).clickable { pick(item) }.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { item.agents.firstOrNull()?.let { MakerIcon(it.maker, it.runtime, 14.dp) } }
                    // Another workspace's: its name right after the title (cut short first), as a tag.
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(item.title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        item.outside?.let { StationTag(it, null, null) }
                    }
                    item.time?.get("lastActiveAt")?.let { Text(it.ago, fontSize = 13.sp, color = C.muted, maxLines = 1) }
                }
            }
        }
    }
}

// ── sharing what is referred to (docs/chat-share.md) ─────────────────────

/**
 * Sends what `draft` holds by `send`, written on `station`, once this workspace's agents can read what it refers to:
 * the chats of the viewer's other workspaces its marks name that are not shared with this one yet (the core's
 * `chat.outsideRefs`). With none, it goes at once; else a sheet says which first (as the phone's web does).
 */
fun AppState.sendSharing(draft: Draft, station: String, send: () -> Unit) {
    val text = draft.text.trim()
    // No mark, nothing referred to: no need to ask.
    if (!ChatRefs.MARK.containsMatchIn(text)) { send(); return }
    if (draft.checking) return
    draft.checking = true
    scope.launch {
        // A core that cannot say (one before sharing) leaves it as before: sent as it is.
        val outside = try { api(station).outsideRefs(text) } catch (_: CoreException) { emptyList() }
        draft.checking = false
        if (outside.isEmpty()) send() else askToShare(this@sendSharing, draft, station, outside, send)
    }
}

/**
 * Which chats of other workspaces this workspace's agents will read once it is sent, each saying whose; those the
 * viewer may not share (neither its starter nor an owner or admin there) say so. 分享并发送 shares those they may with
 * this workspace (`chat.xshareAdd`, its station told first; the button turning meanwhile, as the phone's web does), then
 * closes the sheet and sends; a share failing is said in the sheet, and nothing is sent (the draft stays). With none they
 * may share, 仍然发送 sends it as it is. 取消 leaves the draft as it was.
 */
private fun askToShare(app: AppState, draft: Draft, station: String, chats: List<OutsideRef>, send: () -> Unit) {
    val may = chats.filter { it.may }
    val rows = chats.sumOf { if (it.may) 34 else 54 }
    app.sheet = SheetSpec(0.5f, fit = (22 + 48 + 30 + rows + 16 + 38 + 24).dp) {
        SheetGrab()
        SheetHead(t("web-main.outside.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            Text(t("web-main.outside.lead"), fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, modifier = Modifier.padding(bottom = 8.dp))
            // Each as a reference shows (its title after `@`, in the accent), whose after it as the `@` menu says it.
            chats.forEach { c ->
                Column(Modifier.fillMaxWidth().padding(vertical = 5.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            buildAnnotatedString { withStyle(SpanStyle(color = C.link.copy(alpha = C.link.alpha * 0.7f))) { append("@") }; append(c.title) },
                            fontSize = 15.sp, lineHeight = 22.sp, color = C.link, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                        )
                        StationTag(t("web-main.outside.from", "name" to c.workspaceName), null, null)
                    }
                    if (!c.may) Text(t("web-main.outside.cannot"), fontSize = 13.sp, lineHeight = 18.sp, color = C.red, modifier = Modifier.padding(top = 2.dp))
                }
            }
            var busy by remember { mutableStateOf(false) }
            var error by remember { mutableStateOf<String?>(null) }
            error?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.red, modifier = Modifier.padding(top = 8.dp)) }
            Row(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(t(if (may.isEmpty()) "web-main.outside.anyway" else "web-main.outside.share"), primary = true, busy = busy) {
                    if (busy) return@Button
                    if (may.isEmpty()) { app.sheet = null; send(); return@Button }
                    busy = true
                    error = null
                    app.scope.launch {
                        // All at once; each told on its own (one failing does not stop the rest).
                        val failed = may.map { c ->
                            async { try { app.api(c.station).shareInto(c.id, scopeOf(station), station); null } catch (e: CoreException) { e } }
                        }.awaitAll().firstOrNull { it != null }
                        busy = false
                        if (failed != null) error = t("web-main.outside.failed", "error" to errorText(failed))
                        else { app.sheet = null; send() }
                    }
                }
            }
        }
    }
}

// ── files ──────────────────────────────────────────────────────────────

private const val MAX_FILE = 1024L * 1024 * 1024
/** A picked file up to this is read into memory (an image's preview and marks read it); a bigger one is read as it goes up. */
private const val IN_MEMORY = 16L * 1024 * 1024

/**
 * A file picked on the phone; images also get their size and a preview. Up to [IN_MEMORY] it is read whole (`bytes`);
 * a bigger one is read from `open` as it goes up, a part at a time. `size` is the file's own: one over MAX_FILE is
 * neither (`bytes` empty, no `open`), and is refused.
 */
class Picked(val name: String, val bytes: ByteArray, val width: Int?, val height: Int?, val preview: ImageBitmap?, val size: Long = bytes.size.toLong(), val open: (() -> java.io.InputStream)? = null) {
    /** Where its bytes are read from as it goes up. */
    fun source(): () -> java.io.InputStream = open ?: { java.io.ByteArrayInputStream(bytes) }
}

suspend fun readPicked(context: Context, uri: Uri): Picked? = withContext(Dispatchers.IO) {
    val resolver = context.contentResolver
    var name = "file"
    var known: Long? = null
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
        if (c.moveToFirst()) {
            if (!c.isNull(0)) name = c.getString(0)
            if (!c.isNull(1)) known = c.getLong(1)
        }
    }
    known?.let { if (it > MAX_FILE) return@withContext Picked(name, ByteArray(0), null, null, null, it) }
    val open = { resolver.openInputStream(uri) ?: throw java.io.IOException("unreadable") }
    // The provider may not say how big (or say wrong): read no further than one byte past IN_MEMORY into memory.
    val bytes = if (known != null && known!! > IN_MEMORY) null else try {
        open().use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            while (out.size() <= IN_MEMORY) {
                val n = input.read(buf, 0, minOf(buf.size.toLong(), IN_MEMORY + 1 - out.size()).toInt())
                if (n < 0) break
                out.write(buf, 0, n)
            }
            out.toByteArray()
        }
    } catch (_: java.io.IOException) { return@withContext null }
    if (bytes != null && bytes.size <= IN_MEMORY) {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }.also { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, it) }
        val image = bounds.outWidth > 0
        val preview = if (image) BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = maxOf(1, bounds.outWidth / 160) })?.asImageBitmap() else null
        return@withContext Picked(name, bytes, bounds.outWidth.takeIf { image }, bounds.outHeight.takeIf { image }, preview)
    }
    // Big: its size as read when the provider did not say (counted, not kept), its picture from a pass of its own.
    val size = try {
        known ?: open().use { input -> var n = 0L; val buf = ByteArray(1 shl 16); while (true) { val r = input.read(buf); if (r < 0) break; n += r; if (n > MAX_FILE) break }; n }
    } catch (_: java.io.IOException) { return@withContext null }
    if (size > MAX_FILE) return@withContext Picked(name, ByteArray(0), null, null, null, size)
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    try { open().use { BitmapFactory.decodeStream(it, null, bounds) } } catch (_: java.io.IOException) {}
    val image = bounds.outWidth > 0
    val preview = if (!image) null else try {
        open().use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = maxOf(1, bounds.outWidth / 160) }) }?.asImageBitmap()
    } catch (_: java.io.IOException) { null } catch (_: OutOfMemoryError) { null }
    Picked(name, ByteArray(0), bounds.outWidth.takeIf { image }, bounds.outHeight.takeIf { image }, preview, size, open)
}

fun photoPicked(bitmap: Bitmap): Picked {
    val bytes = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
    return Picked("photo-${System.currentTimeMillis()}.jpg", bytes, bitmap.width, bitmap.height, bitmap.asImageBitmap())
}

/** Files go to the station as soon as they are added, and wait there in no chat: the message that sends them takes them
 * into its chat (a new chat is made only then). A chat's draft is kept once the file is up. */
fun AppState.upload(draft: Draft, station: String, picked: Picked, scope: CoroutineScope, pasted: PastedText? = null) {
    val p = Pending(System.nanoTime(), picked.name, picked.size, picked.preview, picked.bytes.takeIf { picked.preview != null && it.isNotEmpty() }, picked.width, picked.height, pasted)
    draft.files += p
    if (picked.size > MAX_FILE || (picked.bytes.isEmpty() && picked.open == null && picked.size > 0)) { p.error = t("android-chat.file.tooBig"); return }
    // The core sends it up, reading it from here a part at a time (PickedFiles); a message sent before it is up waits for it.
    val id = "p${p.id}"
    p.coreId = id
    draft.core = core
    val file = PickedFiles.hold(picked.size, picked.source())
    val type = java.net.URLConnection.guessContentTypeFromName(picked.name) ?: ""
    scope.launch {
        try {
            core.call("composer.add", buildJsonObject {
                put("key", draft.uploadKey); put("station", station)
                putJsonArray("files") {
                    addJsonObject {
                        put("id", id); put("name", picked.name); put("size", picked.size)
                        putJsonObject("blob") { put("hostFile", file); put("size", picked.size); put("type", type) }
                    }
                }
            })
        } catch (e: CoreException) {
            PickedFiles.release(file)
            p.error = e.message
            return@launch
        }
        follow(draft, station, picked, p)
    }
}

/**
 * What the core says of `p` as it goes up (its composer's topic), until it is up, has failed, or has left the draft
 * (taken out, or sent: the outbox follows it then). Failed, it can go again from what was kept (`composer.retry`).
 */
private suspend fun AppState.follow(draft: Draft, station: String, picked: Picked, p: Pending) {
    val id = p.coreId ?: return
    var seen = false
    core.topic(buildJsonObject { put("topic", "composer"); put("key", draft.uploadKey) }).first { state ->
        if (p !in draft.files) return@first true
        val view = state.value?.let { runCatching { decode(ComposerView.serializer(), it) }.getOrNull() } ?: return@first false
        val f = view.files.firstOrNull { it.id == id } ?: return@first seen
        seen = true
        f.sent?.let { p.sent = it }
        val done = f.done
        val error = f.error
        when {
            done != null -> {
                p.done = if (done.width == null && picked.width != null && picked.height != null) done.copy(width = picked.width.toLong(), height = picked.height.toLong()) else done
                picked.preview?.let { FileData.keepSent(station, done.path, it) }
                draft.save()
                true
            }
            error != null -> {
                p.error = error
                p.retry = {
                    p.error = null; p.sent = null; p.retry = null
                    scope.launch {
                        try { core.call("composer.retry", buildJsonObject { put("key", draft.uploadKey); put("id", id) }) }
                        catch (e: CoreException) { p.error = e.message; return@launch }
                        follow(draft, station, picked, p)
                    }
                }
                true
            }
            else -> false
        }
    }
}

/** What a file going up says: how far it has gone, once that is known. */
internal fun uploadingText(f: Pending): String = uploadingText(f.sent, f.size)

/** The same, of `sent` bytes of `size` (a message's file going up before it is sent). */
internal fun uploadingText(sent: Long?, size: Long): String =
    if (sent == null || size <= 0) t("common.uploading")
    else t("android-chat.file.uploading.part", "percent" to (sent * 100 / size).toInt(), "size" to fileSize(size))

// ── the composer ───────────────────────────────────────────────────────

/**
 * What waits to go with the message, as the web's composer shows it (ComposerExtras): the quotes, each a card with a
 * line for a comment (the one just added takes the focus; its Enter goes back to the text), then the files (each kept
 * for `host`'s flight to take it from where it is, ChatHost.kt).
 */
@Composable
fun DraftExtras(draft: Draft, host: Host? = null, station: String? = host?.spec?.station, session: String? = host?.spec?.here) {
    val app = LocalApp.current
    if (draft.quotes.isNotEmpty()) Column(Modifier.fillMaxWidth().heightIn(max = 176.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        draft.quotes.forEach { q ->
            // In the composer's capsule: corners concentric with it.
            Box(Modifier.fillMaxWidth().clip(InComposer).background(quoteGround())) {
                Column(Modifier.fillMaxWidth()) {
                    Text(
                        quoteLine(q.author, q.text), inlineContent = quoteMark(), fontSize = 13.sp, lineHeight = 19.5.sp, color = chatMuted(), maxLines = 2, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(start = 16.dp, end = 34.dp, top = 9.dp),
                    )
                    val focus = remember { FocusRequester() }
                    LaunchedEffect(draft.focusQuote) { if (draft.focusQuote == q.id) { focus.requestFocus(); draft.focusQuote = null } }
                    Box(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 3.dp, bottom = 10.dp)) {
                        if (q.comment.isEmpty()) Text(t("android-chat.quote.comment"), color = chatSubtle(), fontSize = 15.sp, lineHeight = 22.sp)
                        BasicTextField(
                            q.comment, { q.comment = it }, singleLine = true, textStyle = TextStyle(fontFamily = TextFont, color = C.ink, fontSize = 15.sp, lineHeight = 22.sp), cursorBrush = SolidColor(C.accent),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next), keyboardActions = KeyboardActions(onNext = { draft.focus++ }),
                            modifier = Modifier.fillMaxWidth().focusRequester(focus),
                        )
                    }
                }
                // In the quote's corner as far from both edges, round in its corner (its half and that: the quote's).
                Box(Modifier.align(Alignment.TopEnd).padding(top = 6.dp, end = 6.dp).size(28.dp).clip(CircleShape).clickable { draft.quotes.remove(q) }, contentAlignment = Alignment.Center) {
                    IconIn(Icons.Close, 12.dp, chatSubtle())
                }
            }
        }
    }
    // As far from the capsule's edge as from its top (ComposerFilesIn), past its own room (ComposerInset).
    val beyond = ComposerFilesIn - ComposerInset
    // A picture's remove button sits over its corner (PictureRemoveOut beyond it): the gap after it room for that too.
    if (draft.files.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()).padding(start = beyond, end = beyond + PictureRemoveOut, top = beyond), horizontalArrangement = Arrangement.spacedBy(6.dp + PictureRemoveOut)) {
        draft.files.forEach { f ->
            val remove = { draft.takeOut(f) }
            val picture = draftPictureOf(f, station, session)
            if (picture != null) Box {
                Box(Modifier.draftPicture(f, station).sendTile(host, f.id).size(56.dp).clip(InComposerFiles).background(C.chip)) {
                    Image(picture, f.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    if (f.done == null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (f.error != null) 0.5f else 0.25f)), contentAlignment = Alignment.Center) {
                        val again = f.retry
                        // Failed: tapped, it goes up again.
                        if (f.error != null && again != null) Column(
                            Modifier.fillMaxSize().clickable(onClick = again).semantics { contentDescription = t("web-main.composer.retryUpload") },
                            verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            IconIn(Icons.Retry, 16.dp, Color.White)
                            Text(t("android-chat.file.failed"), color = Color.White, fontSize = 11.sp)
                        }
                        else if (f.error != null) Text(t("android-chat.file.failed"), color = Color.White, fontSize = 11.sp) else Spinner(color = Color.White)
                    }
                }
                // Only where it is drawn: Compose would take a touch target this small out to 48dp, most of the tile,
                // and a tap meant to open the picture removed it.
                CompositionLocalProvider(LocalViewConfiguration provides LocalViewConfiguration.current.exact()) {
                    // Over the picture's corner, its centre on the curve: solid, as part of it is on the composer's ground.
                    Box(
                        Modifier.align(Alignment.TopEnd).offset(x = PictureRemoveOut, y = -PictureRemoveOut).size(20.dp).clip(CircleShape).background(C.ink).clickable(onClick = remove),
                        contentAlignment = Alignment.Center,
                    ) { IconIn(Icons.Close, 12.dp, Raised) }
                }
            } else if (f.pasted != null) Box(Modifier.sendTile(host, f.id)) {
                val pasted = f.pasted
                PastedCard(f, pasted, onRemove = remove,
                    onRetry = if (f.error != null && station != null) ({ draft.takeOut(f); pasteAsFile(app, draft, station, pasted.text) }) else null,
                    onRestore = if (pasted.restorable && !draft.starting) ({ draft.takeOut(f); draft.text = if (draft.text.isEmpty()) pasted.text else "${draft.text}\n${pasted.text}"; draft.focus++ }) else null)
            } else if (f.link != null) Box(Modifier.sendTile(host, f.id)) {
                LinkCard(f.link, onRemove = remove)
            } else if (f.ref != null && station != null) Box(Modifier.sendTile(host, f.id)) {
                RefCard(f, onRemove = remove, shape = InComposerFiles) { openRefSheet(app, draft, f, station) }
            } else Box(Modifier.sendTile(host, f.id)) {
                FileCard(f.done?.name ?: f.name, f.done?.size ?: f.size, f.error ?: if (f.done == null) uploadingText(f) else null, busy = f.done == null && f.error == null, onRemove = remove, onRetry = f.retry.takeIf { f.error != null }, shape = InComposerFiles)
            }
        }
    }
}

/** How far a composer picture's remove button (20 across) reaches beyond its edges: its centre on the corner's curve. */
private val PictureRemoveOut = 10.dp - smoothMiddle(concentric(ComposerCorner, ComposerFilesIn))

/** Where ＋'s ink starts in its button (36 across, the 18 icon centred; its line from 4.5 of 24, less half its 1.75 stroke): the opened field's text starts there, the caret over ＋'s left edge. */
private val PlusInk = 9.dp + 18.dp * ((4.5f - 1.75f / 2) / 24)

/** A link shared in (share/), as a file of the draft: nothing goes up, it is sent as words after the text. */
internal fun linkPending(link: ComposerLink) = Pending(System.nanoTime(), link.title ?: link.url, 0, null, link = link)

/** A link in the composer, as a file's card: the web's mark, its title, its site; tapped, it opens. */
@Composable
private fun LinkCard(link: ComposerLink, onRemove: () -> Unit) {
    val open = LocalUriHandler.current
    Row(
        Modifier.width(236.dp).clip(InComposerFiles).background(chatInk().neutral).clickable { runCatching { open.openUri(link.url) } }.padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IconIn(Icons.Web, 16.dp, C.muted)
        Column(Modifier.weight(1f)) {
            Text(link.title ?: link.url, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(link.site ?: link.url, fontSize = 11.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.size(22.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.06f)).clickable(onClick = onRemove), contentAlignment = Alignment.Center) {
            IconIn(Icons.Close, 12.dp, C.muted)
        }
    }
}

/**
 * Text pasted as a file, as the web's composer shows it: its first line, then how it goes (going up, failed, or a text
 * file of so many characters); 展开到输入框 puts it back in the text (not one too long for it), 重试上传 after it failed.
 */
@Composable
private fun PastedCard(f: Pending, pasted: PastedText, onRemove: () -> Unit, onRetry: (() -> Unit)?, onRestore: (() -> Unit)?) {
    val busy = f.done == null && f.error == null
    Row(
        Modifier.width(260.dp).clip(InComposerFiles).background(chatInk().neutral).padding(start = 10.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (busy) Spinner() else IconIn(Icons.Read, 16.dp, C.muted)
        Column(Modifier.weight(1f)) {
            Text(pasted.preview.ifEmpty { t("web-main.composer.pastedText") }, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                f.error ?: if (busy) t("web-main.composer.pasteUploading") else t("web-main.composer.pasteAttachment", "count" to pasted.characters),
                fontSize = 11.sp, lineHeight = 16.sp, color = if (f.error != null) C.red else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            val action = if (onRetry != null) t("web-main.composer.retryPaste") to onRetry else onRestore?.let { t("web-main.composer.expandPaste") to it }
            if (action != null) Text(action.first, fontSize = 13.sp, lineHeight = 18.sp, color = C.link, modifier = Modifier.padding(top = 2.dp).clickable(onClick = action.second))
        }
        Box(
            Modifier.size(22.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.06f)).clickable(onClick = onRemove)
                .semantics { contentDescription = t("web-main.composer.removePaste") },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Close, 12.dp, C.muted) }
    }
}

/** A long paste: the file it goes as, up to `station` as any file added (`upload`). */
private fun pasteAsFile(app: AppState, draft: Draft, station: String, text: String) {
    val pasted = PastedText(text)
    app.upload(draft, station, pastedPicked(pasted), app.scope, pasted)
}

/** The same, but a touch target is only as big as what is drawn. */
private fun ViewConfiguration.exact(): ViewConfiguration = object : ViewConfiguration by this {
    override val minimumTouchTargetSize: DpSize get() = DpSize.Zero
}

/**
 * What a draft's picture shows: the one picked, or (a draft kept and opened again, which keeps no picture, only the
 * file it went up as) the one it was sent with this run, else the station's, fetched for its chat's session (`key`).
 * Null for a file that is no picture: it shows as a card.
 */
@Composable
private fun draftPictureOf(f: Pending, station: String?, key: String?): ImageBitmap? {
    if (f.preview != null) return f.preview
    val a = f.done
    if (a == null || station == null || !isImage(a.name)) return null
    val app = LocalApp.current
    val longest = with(LocalDensity.current) { 56.dp.roundToPx() * 2 }
    val id = FileData.id(station, key ?: "", a, thumb = true)
    var picture by remember(f.id) { mutableStateOf(FileData.sentPicture(station, a.path) ?: FileData.keptPicture(id, longest)) }
    LaunchedEffect(f.id, key) {
        if (picture != null || key == null) return@LaunchedEffect
        try { picture = FileData.picture(id, FileData.fetch(app, station, key, a, thumb = true).await(), longest) } catch (_: CoreException) {}
    }
    return picture
}

/**
 * A picture waiting in the composer: tapped, shown whole in the viewer (growing out of its tile), from the bytes picked
 * (web Chat.tsx PendingFile: `draft:<id>`, no session's). Nothing to mark it into: it is already in the draft.
 */
@Composable
private fun Modifier.draftPicture(f: Pending, station: String?): Modifier {
    val bytes = f.local
    if (station == null || bytes == null) return this
    var open by remember(f.id) { mutableStateOf(false) }
    val file = remember(f.id) { Attachment(f.name, "draft:${f.id}", f.size, f.width?.toLong(), f.height?.toLong()) }
    val id = FileViewers.id(station, "", file.path)
    ForgetThumb(id)
    if (open) FilePreview(station, "", file, canDraft = false) { open = false }
    return viewerThumb(id, with(LocalDensity.current) { concentric(ComposerCorner, ComposerFilesIn).toPx() }) { f.preview }
        .clickable {
            FileData.keep(FileData.id(station, "", file, thumb = false), bytes)
            open = true
        }
}

/**
 * The bar, inside a floating capsule that is its frame (web mobile/Chat.tsx → useComposerBar): ＋, a field that grows
 * with the text up to six lines right after it (its references drawn as marks, a backspace taking one whole), and a round
 * send button (a spinner while a new chat is made). Locked (offline, archived), neither ＋ nor send does anything.
 * `hint`: how much the placeholder shows (words just sent pass over it first: ChatHost.kt); `morph`: the capsule's, whose
 * parts ＋, the field and send are (they move with it); `onField`: where the field is, as it is laid out, and
 * `onFieldText` how its words are (where each line breaks: words sent fly line by line from there, ChatHost.kt).
 */
internal val Draft.composerExpanded: Boolean
    get() = focused || text.isNotEmpty() || files.isNotEmpty() || quotes.isNotEmpty()

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ComposerBar(
    draft: Draft, placeholder: String, onPlus: () -> Unit, onType: () -> Unit, onSend: () -> Unit,
    hint: () -> Float = { 1f }, morph: Morph? = null, onField: (LayoutCoordinates) -> Unit = {},
    onFieldText: (TextLayoutResult) -> Unit = {}, station: String? = null,
) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    // One style for what is typed and the placeholder: the field is as tall empty as with a line in it.
    val style = SendTextFaced.copy(color = C.ink)
    val locked = draft.locked || draft.starting
    val expanded = draft.composerExpanded
    // Keep the field in one composition slot while the buttons move below it, preserving focus and the IME.
    Layout(content = {
        Box(
            Modifier.part(morph, "plus").size(36.dp).clip(CircleShape).clickable(enabled = !locked, onClick = onPlus)
                .semantics { contentDescription = t("android-chat.attach.title") },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Plus, 18.dp, if (locked) C.ink.copy(alpha = 0.35f) else C.ink) }
        Box(
            Modifier.part(morph, "field").heightIn(min = 36.dp).padding(start = if (expanded) PlusInk else 0.dp, end = 14.dp, top = 7.dp, bottom = 7.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (draft.text.isEmpty()) Text(placeholder, style = style.copy(color = C.subtle), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.graphicsLayer { alpha = hint() })
            val focus = remember { FocusRequester() }
            LaunchedEffect(draft.focus) { if (draft.focus > 0) focus.requestFocus() }
            val accent = C.accent
            val marks = remember(accent) { RefMarks(accent) }
            val context = LocalContext.current
            // What the text takes as it is written (the user's edits; what the app puts there goes as it is).
            val input = InputTransformation {
                val was = originalText.toString()
                val now = asCharSequence().toString()
                if (now == was) return@InputTransformation
                // A backspace just after a reference takes it whole.
                val caret = originalSelection.start
                val mark = if (originalSelection.collapsed && now.length == was.length - 1 && caret > 0 &&
                    selection.collapsed && selection.start == caret - 1 && now == was.removeRange(caret - 1, caret)) ChatRefs.before(was, caret) else null
                if (mark != null) { delete(mark, caret - 1); selection = TextRange(mark); onType(); return@InputTransformation }
                val put = insertedRange(was, now)
                // A long paste goes as a file (PastedText.kt), the text left as it was.
                if (put != null && put.last - put.first + 1 >= PASTE_THRESHOLD && station != null && !locked) {
                    val text = now.substring(put.first, put.last + 1)
                    revertAllChanges()
                    scope.launch { pasteAsFile(app, draft, station, text) }
                    return@InputTransformation
                }
                onType()
                // A chat's link pasted (`[its title](its link)`, as copied) goes in as a reference, as on the web.
                if (station != null && put != null && put.last > put.first) {
                    val refs = linkedRefs(now, station).filter { (m) -> m.range.first <= put.last && m.range.last >= put.first }
                    if (refs.isNotEmpty()) scope.launch { markPasted(app, draft, now, refs) }
                }
            }
            BasicTextField(
                draft.state, inputTransformation = input, outputTransformation = marks,
                textStyle = style, readOnly = draft.starting, cursorBrush = SolidColor(C.accent),
                lineLimits = TextFieldLineLimits.MultiLine(maxHeightInLines = 6), onTextLayout = { result -> result()?.let(onFieldText) },
                modifier = Modifier.fillMaxWidth().focusRequester(focus).onFocusChanged { draft.focused = it.isFocused }.onGloballyPositioned(onField)
                    // Pictures and files pasted, or sent by the keyboard (its clipboard, stickers): with the message, as one
                    // added by ＋ is; their text, and any other, goes into the text.
                    .contentReceiver { content ->
                        if (station == null || locked) return@contentReceiver content
                        val uris = mutableListOf<Uri>()
                        val rest = content.consume { item -> item.uri?.also { uris += it } != null }
                        // `content` held until they are read: what lets them be read (the keyboard's grant) goes with it.
                        if (uris.isNotEmpty()) scope.launch {
                            uris.forEach { u -> readPicked(context, u)?.let { app.upload(draft, station, it, app.scope) } ?: run { app.toast = t("android-chat.file.uploadFailed") } }
                            java.lang.ref.Reference.reachabilityFence(content)
                        }
                        rest
                    },
            )
        }
        val ready = draft.ready
        // Not ready: the ink faint over the capsule's own ground (web: 18% text over --raised).
        val idle = C.ink.copy(alpha = 0.18f).compositeOver(C.surface)
        Box(
            Modifier.part(morph, "send").size(36.dp).clip(CircleShape).background(if (ready) C.ink else idle).clickable(enabled = ready, onClick = onSend)
                .semantics { contentDescription = t("android-chat.composer.send") },
            contentAlignment = Alignment.Center,
        ) {
            val ink = if (ready) C.bg else C.surface
            BusyIcon(draft.starting, solid = ink) { IconIn(Icons.ArrowUp, 18.dp, ink) }
        }
    }, modifier = Modifier.fillMaxWidth()) { items, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val plus = items[0].measure(loose)
        val send = items[2].measure(loose)
        val gap = 2.dp.roundToPx()
        val width = constraints.maxWidth
        val fieldWidth = if (expanded) width else (width - plus.width - send.width - gap * 2).coerceAtLeast(0)
        val field = items[1].measure(loose.copy(minWidth = fieldWidth, maxWidth = fieldWidth))
        val buttonsHeight = maxOf(plus.height, send.height)
        val height = if (expanded) field.height + 4.dp.roundToPx() + buttonsHeight else maxOf(field.height, buttonsHeight)
        layout(width, height) {
            field.placeRelative(if (expanded) 0 else plus.width + gap, if (expanded) 0 else height - field.height)
            plus.placeRelative(0, height - plus.height)
            send.placeRelative(width - send.width, height - send.height)
        }
    }
}

// ── the capsule's change of shape (web morph.ts → useMorph) ─────────────

/**
 * The composer's capsule growing or shrinking (a line more, a file or a quote, sent and emptied) in one motion, as the
 * web's: its height, and with it its corners (a capsule's ends are half its height), and its parts (＋, the field,
 * send) going from where they showed to where the new layout puts them, all on one timeline (260 ms, Ease.Out). The
 * capsule stands on its bottom edge: what it holds is laid out anew at once from its top, in the box as tall as it is
 * at that moment (the rest cut by its shape), and each part is carried from where it was to its place.
 */
@Stable
class Morph {
    /** A part: where it is in the content as laid out, where it goes from, and where it was last drawn (from the capsule's bottom edge). */
    private class Part { var inContent = Offset.Zero; var from: Offset? = null; var drawn: Offset? = null; var coords: LayoutCoordinates? = null }
    private val parts = HashMap<String, Part>()
    private val progress = Animatable(1f)
    /** Bumped for each change of height: what starts the motion. */
    internal var run by mutableIntStateOf(0)
    private var from = -1
    private var to = -1
    /** Set between a change being seen (in layout) and its motion starting (a frame later): it shows as it began. */
    private var starting = false

    // Both read whatever holds (what reads them, a layout or a part's layer, is to run again as either changes).
    private fun e(): Float { val t = progress.value; return if (starting || run < 0) 0f else Ease.Out.transform(t) }
    /** The height drawn now. */
    fun height(): Int = if (from < 0) to else (from + (to - from) * e()).roundToInt()

    /** Where a part shows now, from the capsule's bottom edge. */
    private fun shown(p: Part): Offset {
        val at = p.inContent - Offset(0f, to.toFloat())
        val was = p.from ?: return at
        return was + (at - was) * e()
    }

    /** The content laid out anew, `h` tall: from where it shows now to there. */
    internal fun retarget(h: Int) {
        if (to < 0) { to = h; from = -1; return }
        val now = height()
        // From where each part was last seen (a layout may have moved it since, before this change of height was seen).
        parts.values.forEach { it.from = it.drawn ?: shown(it) }
        from = now; to = h; starting = true
        run++
    }

    internal suspend fun play() {
        progress.snapTo(0f)
        starting = false
        progress.animateTo(1f, tween(260, easing = LinearEasing))
        parts.values.forEach { it.from = null }
        from = -1
    }

    internal fun placed(key: String, coords: LayoutCoordinates) {
        val p = parts.getOrPut(key) { Part() }
        p.coords = coords
        content?.takeIf { it.isAttached && coords.isAttached }?.let {
            val at = it.localPositionOf(coords, Offset.Zero)
            // Moved: its layer is set again (it may have been set as it was placed, before this was known).
            if (at != p.inContent) { p.inContent = at; moved++ }
        }
    }
    private var moved by mutableIntStateOf(0)
    /** How far a part is off its place in the layout now. */
    internal fun offset(key: String): Offset {
        val p = parts[key] ?: return Offset.Zero
        // Where the layout puts it now, read as it is placed (its layer is set then, before any callback after the
        // layout would say where it went).
        moved
        val c = content; val own = p.coords
        if (c != null && own != null && c.isAttached && own.isAttached) p.inContent = c.localPositionOf(own, Offset.Zero)
        val at = shown(p)
        p.drawn = at
        return at - (p.inContent - Offset(0f, height().toFloat()))
    }
    internal var content: LayoutCoordinates? = null
    /** The height it is going to. */
    internal val target get() = to
}

/** The capsule's content, its height the morph's (it measures itself as it would be, and shows as tall as the motion has got). */
fun Modifier.morph(m: Morph): Modifier = this.layout { measurable, c ->
    val p = measurable.measure(c.copy(minHeight = 0, maxHeight = Constraints.Infinity))
    if (p.height != m.target) m.retarget(p.height)
    val h = m.height()
    layout(p.width, h) { p.place(0, 0) }
}.onPlaced { m.content = it }

/** One of the capsule's parts: carried with it while it changes shape. */
fun Modifier.part(m: Morph?, key: String): Modifier = if (m == null) this else this
    .onPlaced { coords -> m.placed(key, coords) }
    .graphicsLayer { val d = m.offset(key); translationX = d.x; translationY = d.y }

/** A morph for a capsule, played whenever its height changes (at once with motion reduced: ui/Motion.kt). */
@Composable
fun rememberMorph(): Morph {
    val m = remember { Morph() }
    LaunchedEffect(m.run) { if (m.run > 0) m.play() }
    return m
}

/** An archived chat's composer keeps its draft and says so, with its restore (retried after an error): web ArchiveNotice.tsx. */
@Composable
private fun ArchiveNotice(offline: Boolean, restore: suspend () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val operation = remember(app) { Action(app) }
        val busy = operation.busy
    val error = operation.error?.message
    Column(Modifier.padding(horizontal = 8.dp, vertical = 2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t("android-chat.composer.archived"), fontSize = 13.sp, color = C.muted)
            Text(
                if (busy) t("android-chat.composer.restoring") else t("android-chat.composer.restore"), fontSize = 13.sp, color = if (offline) C.muted else C.ink, textDecoration = TextDecoration.Underline,
                modifier = Modifier.clickable(enabled = !busy && !offline) {

                    operation.run { restore() }
                },
            )
        }
        error?.let { Text(it, fontSize = 13.sp, color = C.red) }
    }
}

/**
 * What the chat's composer (the host's: ChatHost.kt) writes to. The composer empties at once: the message lives in the
 * chat's outbox until the station has it (a failure shows there too), its words flying from the composer to its place in
 * the list (Host.sending). Before the agent has a chat, what is sent waits in the outbox while the core has the station
 * make one, bound to the agent; the page becomes it.
 */
@Composable
internal fun chatComposer(host: Host, station: String, of: ChatOf, view: ChatView, agents: List<AgentHere>, draft: Draft): ComposerSpec {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    val keeper = agents.firstOrNull()?.key
    // Uploads go on in the app's scope: a draft kept for the chat takes its files when they are up, the page gone or not.
    val launchers = AttachLaunchers { picked -> app.upload(draft, station, picked, app.scope) }
    val thread = view.thread
    val archived = view.archived == true
    draft.locked = view.offline || archived
    val send = app.chatSend(host, api, of, view, keeper, draft)
    return ComposerSpec(
        station = station, here = keeper, draft = draft, placeholder = if (archived) t("android-chat.composer.archived.placeholder") else t("android-chat.chat.placeholder"),
        notices = {
            if (archived) ArchiveNotice(view.offline) { api.setArchived(thread?.id, (of as? ChatOf.Session)?.key ?: keeper ?: "", false) }
            if (view.offline) Text(t("android-chat.composer.offline"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
        },
        onPlus = { openAttach(app, launchers) { openStationFiles(app, draft, station) } },
        // Typing starts the session's runtime, so a cold start overlaps the writing.
        onType = {
            if (!draft.locked && keeper != null && System.currentTimeMillis() - draft.warmed > 60_000) {
                draft.warmed = System.currentTimeMillis()
                scope.launch { try { api.warm(keeper) } catch (_: CoreException) {} }
            }
        },
        onSend = { if (!draft.locked) app.sendSharing(draft, station, send) },
    )
}

/** Sends what the chat's composer holds (once what it refers to can be read here: sendSharing). */
private fun AppState.chatSend(host: Host, api: StationApi, of: ChatOf, view: ChatView, keeper: String?, draft: Draft): () -> Unit = {
    val app = this
    if (!draft.locked) {
        // Its words stay where they were typed until its row is in the list, then go there. Not from a window short
        // of the chat's end: its row is past the window until the station has the message (at no time known); it
        // comes in as rows do.
        if (view.newer != true) host.sending(draft.text.trim(), carried = false, files = draft.files.toList())
        val taken = draft.take()
        // Refused by the core before it reached the outbox (`invalid_params`: no such chat, a bad address): the words
        // come back if nothing was written since, and why is said. A station's failure is in the outbox (未发送, 重试).
        val refused = { e: CoreException ->
            host.notSent()
            if (e.code == "invalid_params") {
                if (draft.empty) { draft.restore(taken); draft.error = errorText(e) }
                else app.toast = t("android-chat.composer.send.failed", "error" to errorText(e))
            }
            Unit
        }
        // Sent to by the page's key until its thread is known: a chat made here (`new:…`), or the agent's, whose
        // chat the core has its station make behind what is sent (it waits in the outbox meanwhile).
        val to = view.thread?.id
        val key = (of as? ChatOf.Session)?.key ?: keeper
        // Sent from the app's scope: the page may move on before the station answers.
        app.scope.launch {
            try {
                if (to != null) api.send(to, taken.text, taken.attachments, taken.quotes.map { it.sent() }, taken.uploads)
                else if (key != null) api.sendIn(key, taken.text, taken.attachments, taken.quotes.map { it.sent() }, taken.uploads)
                else host.notSent()
            } catch (e: CoreException) { refused(e) }
        }
    }
}
