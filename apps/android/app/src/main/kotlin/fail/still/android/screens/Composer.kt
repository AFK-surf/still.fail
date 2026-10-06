// The chat's composer (web/src/mobile/ChatHost.tsx, and ../Chat.tsx's useComposerText and ComposerExtras): what is being
// written (each chat's own draft, kept on the device: web/src/draft.ts), the quotes and files going with it, `@` and a
// few letters naming another chat of the station (web/src/ChatRef.tsx), and the bar. An archived chat's composer says
// so and restores it (web/src/ArchiveNotice.tsx).
package fail.still.android.screens

import fail.still.android.ui.t
import fail.still.android.BuildConfig
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import fail.still.android.ui.InComposer
import fail.still.android.ui.ComposerInset
import fail.still.android.ui.ComposerCorner
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.runtime.Stable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
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
import fail.still.core.CoreException
import fail.still.android.data.errorText
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.MainScope
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import fail.still.android.data.DraftView
import fail.still.android.data.decode
import fail.still.core.StillFailCore
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
// ── the draft ──────────────────────────────────────────────────────────

/** A file on its way to the station: uploading, uploaded, or failed. */
class Pending(val id: Long, val name: String, val size: Long, val preview: ImageBitmap?) {
    var done by mutableStateOf<Attachment?>(null)
    /** How much of it the station has, as it goes up in parts. */
    var sent by mutableStateOf<Long?>(null)
    var error by mutableStateOf<String?>(null)
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
    var input by mutableStateOf(TextFieldValue(""))
    /** The text; set, the cursor goes to its end. */
    var text: String
        get() = input.text
        set(value) { input = TextFieldValue(value, TextRange(value.length)) }
    val quotes = mutableStateListOf<DraftQuote>()
    val files = mutableStateListOf<Pending>()
    /** A new chat is being made for the first message. */
    var starting by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    /** The quote whose comment line takes the focus. */
    var focusQuote by mutableStateOf<Long?>(null)
    /** Bumped to put the cursor in the text. */
    var focus by mutableIntStateOf(0)
    var warmed = 0L
    val uploading get() = files.any { it.done == null && it.error == null }
    /** Nothing can be sent (its station is offline, or the chat archived). */
    var locked by mutableStateOf(false)
    val ready get() = (text.isNotBlank() || files.any { it.done != null } || quotes.isNotEmpty()) && !uploading && !starting && !locked
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
        kept.files.forEach { a -> files += Pending(System.nanoTime(), a.name, a.size, null).also { it.done = a } }
    }
    internal val empty get() = text.isEmpty() && quotes.isEmpty() && files.isEmpty()

    fun quote(author: String, text: String, ts: String?, role: String) {
        val q = DraftQuote(System.nanoTime(), author, text, ts, role)
        quotes += q
        focusQuote = q.id
    }

    /** Empties it, for what is sent: the text (its references' marks, which the core makes links), the files up, the quotes. */
    fun take(): Taken {
        val taken = Taken(text.trim(), files.toList(), quotes.toList(), text)
        text = ""; files.clear(); quotes.clear(); error = null; refClosed = null
        save()
        return taken
    }

    /** Puts back what `take` took (sending it failed). */
    fun restore(t: Taken) { text = t.written; files.addAll(t.files); quotes.addAll(t.quotes); save() }
}

/** What a draft held when it was sent: `text` as it goes (trimmed), `written` as it was typed. */
class Taken(val text: String, val files: List<Pending>, val quotes: List<DraftQuote>, val written: String)

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

    internal fun save(key: String, d: Draft) {
        val core = core ?: return
        val view = DraftView(d.text, d.quotes.map { it.sent().copy(comment = it.comment) }, d.files.mapNotNull { it.done })
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
private class RefMarks(private val accent: Color) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val s = text.text
        if (!ChatRefs.MARK.containsMatchIn(s)) return TransformedText(text, OffsetMapping.Identity)
        val out = buildAnnotatedString {
            var at = 0
            ChatRefs.MARK.findAll(s).forEach { m ->
                append(s.substring(at, m.range.first))
                pushStyle(SpanStyle(color = Color.Transparent)); append("["); pop()
                pushStyle(SpanStyle(color = accent)); append("@"); append(m.groupValues[1]); pop()
                pushStyle(SpanStyle(color = Color.Transparent)); append("]"); pop()
                at = m.range.last + 1
            }
            append(s.substring(at))
        }
        return TransformedText(out, OffsetMapping.Identity)
    }
}

/** The address's workspace (the scope of its chats' list). */
private fun scopeOf(address: String) = address.substringBefore('/')

/**
 * `@` and a few letters in the text: the chats of this station it finds (another station's agents cannot read them,
 * the core's `chatSearch`), titles first, but not `here` (the chat written in); the one picked goes in as the mark the
 * core makes of it. Over the composer, in its glass.
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
    val search by rememberTopic<ChatSearchView>(app.core, Topics.chatSearch(scopeOf(station), query, station, here, 8))
    val items = search.value?.items ?: emptyList()
    val pick = { item: fail.still.android.data.ChatItem ->
        val caret = field.selection.start
        draft.refClosed = start
        scope.launch {
            // Its mark, from the core, which keeps its link until it is sent; in its place if the `@words` are still there.
            val mark = try {
                app.core.call("chat.ref", buildJsonObject { put("station", item.station); put("id", item.id); put("title", item.title); put("base", app.cloudOrigin) })
                    .jsonObject["mark"]?.jsonPrimitive?.content
            } catch (e: CoreException) { app.toast = t("android-chat.ref.failed", "error" to errorText(e)); null } ?: return@launch
            val now = draft.input.text
            if (now.getOrNull(start) != '@' || caret > now.length) return@launch
            draft.input = TextFieldValue(now.substring(0, start) + mark + " " + now.substring(caret), TextRange(start + mark.length + 1))
        }
    }
    Column(
        modifier.fillMaxWidth().padding(bottom = 8.dp).floating(haze, RoundedCornerShape(ComposerCorner)).heightIn(max = 320.dp)
            .verticalScroll(rememberScrollState()).padding(12.dp),
    ) {
        Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(t("android-chat.ref.title"), fontSize = 13.sp, color = C.muted)
            if (query.isNotEmpty()) Text(query, fontSize = 13.sp, color = C.ink)
        }
        when {
            search.value == null -> Text(if (search.error != null) t("android-chat.ref.update", "app" to BuildConfig.APP_NAME) else t("android-chat.reading"), fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 4.dp))
            items.isEmpty() -> Text(if (query.isNotEmpty()) t("android-chat.ref.none.match") else t("android-chat.ref.none"), fontSize = 15.sp, color = C.muted,
                modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 4.dp))
            else -> items.forEach { item ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(20.dp)).clickable { pick(item) }.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { item.agents.firstOrNull()?.let { MakerIcon(it.maker, it.runtime, 14.dp) } }
                    Text(item.title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    item.time?.get("lastActiveAt")?.let { Text(it.ago, fontSize = 13.sp, color = C.muted, maxLines = 1) }
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
fun AppState.upload(draft: Draft, station: String, picked: Picked, scope: CoroutineScope) {
    val p = Pending(System.nanoTime(), picked.name, picked.size, picked.preview)
    draft.files += p
    if (picked.size > MAX_FILE || (picked.bytes.isEmpty() && picked.open == null && picked.size > 0)) { p.error = t("android-chat.file.tooBig"); return }
    scope.launch {
        try {
            p.done = api(station).upload(picked.name, picked.size, picked.source(), picked.width?.toLong(), picked.height?.toLong()) { p.sent = it }
            p.done?.let { a -> picked.preview?.let { FileData.keepSent(station, a.path, it) } }
            draft.save()
        } catch (e: CoreException) {
            p.error = e.message
        } catch (_: java.io.IOException) {
            p.error = t("android-chat.file.uploadFailed")
        }
    }
}

/** What a file going up says: how far it has gone, when it is more than a part. */
private fun uploadingText(f: Pending): String {
    val sent = f.sent
    return if (sent == null || f.size <= 4L * 1024 * 1024) t("android-chat.file.uploading")
    else t("android-chat.file.uploading.part", "percent" to (sent * 100 / f.size).toInt(), "size" to fileSize(f.size))
}

@Composable
fun AttachLaunchers(onPicked: (Picked) -> Unit): Triple<() -> Unit, () -> Unit, () -> Unit> {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap -> bitmap?.let { onPicked(photoPicked(it)) } }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        scope.launch { uris.forEach { u -> readPicked(context, u)?.let(onPicked) } }
    }
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        scope.launch { uris.forEach { u -> readPicked(context, u)?.let(onPicked) } }
    }
    return Triple(
        { camera.launch(null) },
        { photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
        { files.launch(arrayOf("*/*")) },
    )
}

/** ＋: take a photo, pick photos, pick files. */
fun openAttach(app: AppState, launchers: Triple<() -> Unit, () -> Unit, () -> Unit>) {
    app.sheet = SheetSpec(0.32f) {
        SheetGrab()
        SheetHead(t("android-chat.attach.title"))
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(Triple(t("android-chat.attach.camera"), Icons.Camera, launchers.first), Triple(t("android-chat.attach.photos"), Icons.Photo, launchers.second), Triple(t("android-chat.attach.files"), Icons.File, launchers.third)).forEach { (label, icon, go) ->
                Column(
                    Modifier.weight(1f).clip(RoundedCornerShape(18.dp)).background(C.chip).clickable { app.sheet = null; go() }.padding(top = 16.dp, bottom = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    IconIn(icon, 24.dp)
                    Text(label, fontSize = 13.sp, color = C.ink)
                }
            }
        }
    }
}

// ── the composer ───────────────────────────────────────────────────────

/**
 * What waits to go with the message, as the web's composer shows it (ComposerExtras): the quotes, each a card with a
 * line for a comment (the one just added takes the focus; its Enter goes back to the text), then the files (each kept
 * for `host`'s flight to take it from where it is, ChatHost.kt).
 */
@Composable
fun DraftExtras(draft: Draft, host: Host? = null) {
    if (draft.quotes.isNotEmpty()) Column(Modifier.fillMaxWidth().heightIn(max = 176.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        draft.quotes.forEach { q ->
            // In the composer's capsule: corners concentric with it.
            // One coming from a message's page (Annotate.kt) shows once it has landed here; till then it is on its way.
            Box(
                Modifier.fillMaxWidth().onGloballyPositioned { AnnotateFlight.quotes[q.id] = it.boundsInRoot() }
                    .graphicsLayer { alpha = if (q.id in AnnotateFlight.landing) 0f else 1f }.clip(InComposer).background(quoteGround()),
            ) {
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
                            q.comment, { q.comment = it }, singleLine = true, textStyle = TextStyle(color = C.ink, fontSize = 15.sp, lineHeight = 22.sp), cursorBrush = SolidColor(C.accent),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next), keyboardActions = KeyboardActions(onNext = { draft.focus++ }),
                            modifier = Modifier.fillMaxWidth().focusRequester(focus),
                        )
                    }
                }
                Box(Modifier.align(Alignment.TopEnd).padding(top = 5.dp, end = 7.dp).size(28.dp).clip(CircleShape).clickable { draft.quotes.remove(q) }, contentAlignment = Alignment.Center) {
                    IconIn(Icons.Close, 12.dp, chatSubtle())
                }
            }
        }
    }
    if (draft.files.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        draft.files.forEach { f ->
            val remove = { draft.files.remove(f); Unit }
            if (f.preview != null) Box(Modifier.sendTile(host, f.id).size(56.dp).clip(InComposer).background(C.chip)) {
                Image(f.preview, f.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                if (f.done == null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (f.error != null) 0.5f else 0.25f)), contentAlignment = Alignment.Center) {
                    if (f.error != null) Text(t("android-chat.file.failed"), color = Color.White, fontSize = 11.sp) else CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 1.5.dp)
                }
                Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(20.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).clickable(onClick = remove), contentAlignment = Alignment.Center) {
                    IconIn(Icons.Close, 12.dp, Color.White)
                }
            } else Box(Modifier.sendTile(host, f.id)) {
                FileCard(f.done?.name ?: f.name, f.done?.size ?: f.size, f.error ?: if (f.done == null) uploadingText(f) else null, busy = f.done == null && f.error == null, onRemove = remove, shape = InComposer)
            }
        }
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

@Composable
fun ComposerBar(
    draft: Draft, placeholder: String, onPlus: () -> Unit, onType: () -> Unit, onSend: () -> Unit,
    hint: () -> Float = { 1f }, morph: Morph? = null, onField: (LayoutCoordinates) -> Unit = {},
    onFieldText: (TextLayoutResult) -> Unit = {},
) {
    // One style for what is typed and the placeholder: the field is as tall empty as with a line in it.
    val style = SendTextStyle.copy(color = C.ink)
    val locked = draft.locked || draft.starting
    val expanded = draft.composerExpanded
    // Keep the field in one composition slot while the buttons move below it, preserving focus and the IME.
    Layout(content = {
        Box(
            Modifier.part(morph, "plus").size(36.dp).clip(CircleShape).clickable(enabled = !locked, onClick = onPlus),
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Plus, 18.dp, if (locked) C.ink.copy(alpha = 0.35f) else C.ink) }
        Box(
            Modifier.part(morph, "field").heightIn(min = 36.dp).padding(start = if (expanded) 14.dp else 0.dp, end = 14.dp, top = 7.dp, bottom = 7.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (draft.text.isEmpty()) Text(placeholder, style = style.copy(color = C.subtle), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.graphicsLayer { alpha = hint() })
            val focus = remember { FocusRequester() }
            LaunchedEffect(draft.focus) { if (draft.focus > 0) focus.requestFocus() }
            val accent = C.accent
            val marks = remember(accent) { RefMarks(accent) }
            BasicTextField(
                draft.input,
                { next ->
                    val was = draft.input
                    // A backspace just after a reference takes it whole.
                    val caret = was.selection.start
                    val mark = if (was.selection.collapsed && next.text.length == was.text.length - 1 && caret > 0 &&
                        next.selection.collapsed && next.selection.start == caret - 1 && next.text == was.text.removeRange(caret - 1, caret)) ChatRefs.before(was.text, caret) else null
                    draft.input = if (mark != null) TextFieldValue(was.text.removeRange(mark, caret), TextRange(mark)) else next
                    if (next.text != was.text) onType()
                },
                textStyle = style, visualTransformation = marks, readOnly = draft.starting,
                cursorBrush = SolidColor(C.accent), maxLines = 6, onTextLayout = onFieldText,
                modifier = Modifier.fillMaxWidth().focusRequester(focus).onFocusChanged { draft.focused = it.isFocused }.onGloballyPositioned(onField),
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
            if (draft.starting) CircularProgressIndicator(Modifier.size(16.dp), color = C.surface, strokeWidth = 2.dp)
            else IconIn(Icons.ArrowUp, 18.dp, if (ready) C.bg else C.surface)
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
    internal var still = false

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
        if (to < 0 || still) { to = h; from = -1; return }
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

/** A morph for a capsule, played whenever its height changes (at once with the system's animations off). */
@Composable
fun rememberMorph(): Morph {
    val m = remember { Morph() }
    m.still = fail.still.android.ui.reducedMotion()
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
    return ComposerSpec(
        station = station, here = keeper, draft = draft, placeholder = if (archived) t("android-chat.composer.archived.placeholder") else t("android-chat.chat.placeholder"),
        notices = {
            if (archived) ArchiveNotice(view.offline) { api.setArchived(thread?.id, (of as? ChatOf.Session)?.key ?: keeper ?: "", false) }
            if (view.offline) Text(t("android-chat.composer.offline"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
        },
        onPlus = { openAttach(app, launchers) },
        // Typing starts the session's runtime, so a cold start overlaps the writing.
        onType = {
            if (!draft.locked && keeper != null && System.currentTimeMillis() - draft.warmed > 60_000) {
                draft.warmed = System.currentTimeMillis()
                scope.launch { try { api.warm(keeper) } catch (_: CoreException) {} }
            }
        },
        onSend = {
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
                val to = thread?.id
                val key = (of as? ChatOf.Session)?.key ?: keeper
                // Sent from the app's scope: the page may move on before the station answers.
                app.scope.launch {
                    try {
                        if (to != null) api.send(to, taken.text, taken.files.mapNotNull { it.done }, taken.quotes.map { it.sent() })
                        else if (key != null) api.sendIn(key, taken.text, taken.files.mapNotNull { it.done }, taken.quotes.map { it.sent() })
                        else host.notSent()
                    } catch (e: CoreException) { refused(e) }
                }
            }
        },
    )
}
