// The chat's composer (web/src/mobile/ChatHost.tsx, and ../Chat.tsx's useComposerText and ComposerExtras): what is being
// written (each chat's own draft, kept on the device: web/src/draft.ts), the quotes and files going with it, `@` and a
// few letters naming another chat of the station (web/src/ChatRef.tsx), and the bar. An archived chat's composer says
// so and restores it (web/src/ArchiveNotice.tsx).
package fail.still.android.screens

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
import androidx.compose.animation.animateContentSize
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
import fail.still.android.data.ChatsView
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
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
// ── the draft ──────────────────────────────────────────────────────────

/** A file on its way to the station: uploading, uploaded, or failed. */
class Pending(val id: Long, val name: String, val size: Long, val preview: ImageBitmap?) {
    var done by mutableStateOf<Attachment?>(null)
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
    /** Keeps it on the device as it is now (a chat's draft). */
    fun save() { keptAs?.let { Drafts.save(it, this) } }

    fun quote(author: String, text: String, ts: String?, role: String) {
        val q = DraftQuote(System.nanoTime(), author, text, ts, role)
        quotes += q
        focusQuote = q.id
    }

    /** Empties it, for what is sent: the text (its references made links), the files up, the quotes. */
    fun take(): Taken {
        val taken = Taken(ChatRefs.expand(text.trim()), files.toList(), quotes.toList(), text)
        text = ""; files.clear(); quotes.clear(); error = null; refClosed = null
        save()
        return taken
    }

    /** Puts back what `take` took (sending it failed). */
    fun restore(t: Taken) { text = t.written; files.addAll(t.files); quotes.addAll(t.quotes); save() }
}

/** What a draft held when it was sent: `text` as it goes, `written` as it was typed. */
class Taken(val text: String, val files: List<Pending>, val quotes: List<DraftQuote>, val written: String)

@Serializable
private class KeptQuote(val author: String, val text: String, val comment: String = "", val ts: String? = null, val role: String = "person", val file: String? = null)

@Serializable
private class KeptDraft(val text: String = "", val quotes: List<KeptQuote> = emptyList(), val files: List<Attachment> = emptyList())

/**
 * Each chat's draft, by its station's address and the chat ("<address>:<chat>", as the web keys it): the same one while
 * the app runs (files still going up go on), and on the device what it holds (the text, the quotes with what is said
 * about them, the files already up; the station keeps those in no chat until a message takes them) for after a restart.
 */
object Drafts {
    private val open = HashMap<String, Draft>()
    private var prefs: SharedPreferences? = null

    private fun prefs(context: Context) = prefs ?: context.applicationContext.getSharedPreferences("drafts", Context.MODE_PRIVATE).also { prefs = it }

    fun of(context: Context, key: String): Draft = open.getOrPut(key) {
        val kept = prefs(context).getString(key, null)?.let { runCatching { StillFailJson.decodeFromString(KeptDraft.serializer(), it) }.getOrNull() }
        Draft().apply {
            keptAs = key
            if (kept != null) {
                text = kept.text
                kept.quotes.forEach { q -> quotes += DraftQuote(System.nanoTime(), q.author, q.text, q.ts, q.role, q.file).also { it.comment = q.comment } }
                kept.files.forEach { a -> files += Pending(System.nanoTime(), a.name, a.size, null).also { it.done = a } }
            }
        }
    }

    internal fun save(key: String, d: Draft) {
        val p = prefs ?: return
        val kept = KeptDraft(d.text, d.quotes.map { KeptQuote(it.author, it.text, it.comment, it.ts, it.role, it.file) }, d.files.mapNotNull { it.done })
        if (kept.text.isBlank() && kept.quotes.isEmpty() && kept.files.isEmpty()) p.edit().remove(key).apply()
        else p.edit().putString(key, StillFailJson.encodeToString(KeptDraft.serializer(), kept)).apply()
    }
}

/** A chat's draft (Drafts), kept on the device as it changes and when the page goes. */
@Composable
fun rememberDraft(station: String, of: ChatOf): Draft {
    val context = LocalContext.current
    val key = "$station:" + when (of) { is ChatOf.Session -> of.key; is ChatOf.Thread -> "thread:${of.id}" }
    val draft = remember(key) { Drafts.of(context, key) }
    LaunchedEffect(draft) {
        snapshotFlow { Triple(draft.text, draft.quotes.map { it.id to it.comment }, draft.files.map { it.id to it.done }) }
            .drop(1).collectLatest { delay(400); draft.save() }
    }
    DisposableEffect(draft) { onDispose { draft.save() } }
    return draft
}

// ── references to other chats (web/src/chatRefs.ts, ChatRef.tsx) ───────────

/**
 * References to other chats in what is written: in the composer a short mark, `@[its title]`, drawn in the accent; sent,
 * a link, `[its title](<cloud>/w/<workspace>/s/<station>/chats/<key>)`, which the agent reads the chat by and a message
 * draws as a chip. The link of each title is kept on the device until the mark is sent (a draft outlives the app).
 */
object ChatRefs {
    val MARK = Regex("@\\[([^\\]\\n]{1,120})\\]")
    private const val KEPT = 200
    private const val TITLE = 24
    private var prefs: SharedPreferences? = null
    private val map = MapSerializer(String.serializer(), String.serializer())

    private fun links(): Map<String, String> =
        prefs?.getString("links", null)?.let { runCatching { StillFailJson.decodeFromString(map, it) }.getOrNull() } ?: emptyMap()

    /** A chat's title as a reference shows it: its start, on one line. */
    fun title(title: String): String {
        val words = title.replace(Regex("[\\[\\]\\n]"), " ").replace(Regex("\\s+"), " ").trim()
        val points = words.codePoints().toArray()
        return (if (points.size > TITLE) String(points, 0, TITLE).trimEnd() + "…" else words).ifEmpty { "对话" }
    }

    /** The mark for a chat, its link kept. */
    fun mark(context: Context, title: String, link: String): String {
        val p = prefs ?: context.applicationContext.getSharedPreferences("chatRefs", Context.MODE_PRIVATE).also { prefs = it }
        val all = LinkedHashMap(links())
        all.remove(title)
        all[title] = link
        val kept = all.entries.toList().takeLast(KEPT).associate { it.key to it.value }
        p.edit().putString("links", StillFailJson.encodeToString(map, kept)).apply()
        return "@[$title]"
    }

    /** What is written, its marks made links (one whose link is gone stays as written). */
    fun expand(text: String): String {
        if (!MARK.containsMatchIn(text)) return text
        val all = links()
        return MARK.replace(text) { m -> all[m.groupValues[1]]?.let { "[${m.groupValues[1]}]($it)" } ?: m.value }
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

/** The address's workspace (the scope of its chats' list), "local" for the local station. */
private fun scopeOf(address: String) = if (address == "local") "local" else address.substringBefore('/')

/** A station's pages under the cloud (web/src/station.tsx → stationBase). */
private fun stationBase(address: String): String = if (address == "local") "" else "/w/${address.substringBefore('/')}/s/${address.substringAfter('/')}"

/**
 * `@` and a few letters in the text: the chats of this station it finds (another station's agents cannot read them),
 * the latest first, but not `here` (the chat written in); the one picked goes in as a mark. Over the composer, in its glass.
 */
@Composable
fun ChatRefMenu(draft: Draft, station: String, here: String?, haze: HazeState, modifier: Modifier = Modifier) {
    val app = LocalApp.current
    val context = LocalContext.current
    val field = draft.input
    val found = if (field.selection.collapsed && draft.focused && !draft.locked) ChatRefs.at(field.text, field.selection.start) else null
    val ref = found?.takeIf { it.first != draft.refClosed }
    if (found == null && draft.refClosed != null) draft.refClosed = null
    if (ref == null) return
    val (start, query) = ref
    val chats by rememberTopic<ChatsView>(app.core, Topics.chats(scopeOf(station), false))
    val words = query.lowercase()
    val items = (chats.value?.days ?: emptyList()).flatMap { it.items }
        .filter { it.station == station && it.id != here && it.session != here }
        .filter { words.isEmpty() || it.title.lowercase().contains(words) || it.agents.any { a -> a.agentText.lowercase().contains(words) } }
        .take(8)
    val pick = { item: fail.still.android.data.ChatItem ->
        val link = "${app.cloudOrigin.trimEnd('/')}${stationBase(item.station)}/chats/${Uri.encode(item.id)}"
        val mark = ChatRefs.mark(context, ChatRefs.title(item.title), link)
        val caret = field.selection.start
        val next = field.text.substring(0, start) + mark + " " + field.text.substring(caret)
        draft.input = TextFieldValue(next, TextRange(start + mark.length + 1))
    }
    Column(
        modifier.fillMaxWidth().padding(bottom = 8.dp).floating(haze, RoundedCornerShape(ComposerCorner)).heightIn(max = 320.dp)
            .verticalScroll(rememberScrollState()).padding(12.dp),
    ) {
        Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("引用对话", fontSize = 13.sp, color = C.muted)
            if (query.isNotEmpty()) Text(query, fontSize = 13.sp, color = C.ink)
        }
        when {
            chats.value == null -> Text("正在读取…", fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 6.dp, bottom = 4.dp))
            items.isEmpty() -> Text(if (query.isNotEmpty()) "没有标题里带这些字的对话" else "这台 station 上没有别的对话", fontSize = 15.sp, color = C.muted,
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

private const val MAX_FILE = 50L * 1024 * 1024

/**
 * A file picked on the phone, read whole; images also get their size and a preview. `size` is the file's own: one over
 * MAX_FILE is not read at all (`bytes` empty), so a long video does not have to fit in memory only to be refused.
 */
class Picked(val name: String, val bytes: ByteArray, val width: Int?, val height: Int?, val preview: ImageBitmap?, val size: Long = bytes.size.toLong())

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
    // The provider may not say how big (or say wrong): read no further than one byte past MAX_FILE either way.
    val bytes = try {
        resolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            while (out.size() <= MAX_FILE) {
                val n = input.read(buf, 0, minOf(buf.size.toLong(), MAX_FILE + 1 - out.size()).toInt())
                if (n < 0) break
                out.write(buf, 0, n)
            }
            out.toByteArray()
        }
    } catch (_: java.io.IOException) { null } ?: return@withContext null
    if (bytes.size > MAX_FILE) return@withContext Picked(name, ByteArray(0), null, null, null, bytes.size.toLong())
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }.also { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, it) }
    val image = bounds.outWidth > 0
    val preview = if (image) BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = maxOf(1, bounds.outWidth / 160) })?.asImageBitmap() else null
    Picked(name, bytes, bounds.outWidth.takeIf { image }, bounds.outHeight.takeIf { image }, preview)
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
    if (picked.size > MAX_FILE) { p.error = "超过 50 MB"; return }
    scope.launch {
        try {
            p.done = api(station).upload(picked.name, picked.bytes, picked.width?.toLong(), picked.height?.toLong())
            draft.save()
        } catch (e: CoreException) {
            p.error = e.message
        }
    }
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
        SheetHead("添加到消息")
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            listOf(Triple("拍照", Icons.Camera, launchers.first), Triple("照片", Icons.Photo, launchers.second), Triple("文件", Icons.File, launchers.third)).forEach { (label, icon, go) ->
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
 * line for a comment (the one just added takes the focus; its Enter goes back to the text), then the files.
 */
@Composable
fun DraftExtras(draft: Draft) {
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
                        if (q.comment.isEmpty()) Text("对这段说点什么（可以不写）", color = chatSubtle(), fontSize = 15.sp, lineHeight = 22.sp)
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
            if (f.preview != null) Box(Modifier.size(56.dp).clip(InComposer).background(C.chip)) {
                Image(f.preview, f.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                if (f.done == null) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = if (f.error != null) 0.5f else 0.25f)), contentAlignment = Alignment.Center) {
                    if (f.error != null) Text("失败", color = Color.White, fontSize = 11.sp) else CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 1.5.dp)
                }
                Box(Modifier.align(Alignment.TopEnd).padding(3.dp).size(20.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).clickable(onClick = remove), contentAlignment = Alignment.Center) {
                    IconIn(Icons.Close, 12.dp, Color.White)
                }
            } else FileCard(f.done?.name ?: f.name, f.done?.size ?: f.size, f.error ?: if (f.done == null) "正在上传…" else null, busy = f.done == null && f.error == null, onRemove = remove, shape = InComposer)
        }
    }
}

/**
 * The bar, inside a floating capsule that is its frame (web mobile/Chat.tsx → useComposerBar): ＋, a field that grows
 * with the text up to six lines right after it (its references drawn as marks, a backspace taking one whole), and a round
 * send button (a spinner while a new chat is made). Locked (offline, archived), neither ＋ nor send does anything.
 */
@Composable
fun ComposerBar(draft: Draft, placeholder: String, onPlus: () -> Unit, onType: () -> Unit, onSend: () -> Unit) {
    // One style for what is typed and the placeholder: the field is as tall empty as with a line in it.
    val style = TextStyle(color = C.ink, fontSize = 16.sp, lineHeight = 21.sp)
    val locked = draft.locked
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(
            Modifier.size(36.dp).clip(CircleShape).clickable(enabled = !locked, onClick = onPlus),
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Plus, 18.dp, if (locked) C.ink.copy(alpha = 0.35f) else C.ink) }
        Box(
            Modifier.weight(1f).heightIn(min = 36.dp).padding(end = 14.dp, top = 7.dp, bottom = 7.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (draft.text.isEmpty()) Text(placeholder, style = style.copy(color = C.subtle), maxLines = 1, overflow = TextOverflow.Ellipsis)
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
                textStyle = style, visualTransformation = marks,
                cursorBrush = SolidColor(C.accent), maxLines = 6,
                modifier = Modifier.fillMaxWidth().focusRequester(focus).onFocusChanged { draft.focused = it.isFocused },
            )
        }
        val ready = draft.ready
        // Not ready: the ink faint over the capsule's own ground (web: 18% text over --raised).
        val idle = C.ink.copy(alpha = 0.18f).compositeOver(C.surface)
        Box(
            Modifier.size(36.dp).clip(CircleShape).background(if (ready) C.ink else idle).clickable(enabled = ready, onClick = onSend),
            contentAlignment = Alignment.Center,
        ) {
            if (draft.starting) CircularProgressIndicator(Modifier.size(16.dp), color = C.surface, strokeWidth = 2.dp)
            else IconIn(Icons.ArrowUp, 18.dp, if (ready) C.bg else C.surface)
        }
    }
}

/** An archived chat's composer keeps its draft and says so, with its restore (retried after an error): web ArchiveNotice.tsx. */
@Composable
private fun ArchiveNotice(offline: Boolean, restore: suspend () -> Unit) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.padding(horizontal = 8.dp, vertical = 2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("已归档，还原后才能发送消息。 ", fontSize = 13.sp, color = C.muted)
            Text(
                if (busy) "正在还原…" else "还原对话", fontSize = 13.sp, color = if (offline) C.muted else C.ink, textDecoration = TextDecoration.Underline,
                modifier = Modifier.clickable(enabled = !busy && !offline) {
                    busy = true; error = null
                    scope.launch { try { restore() } catch (e: CoreException) { error = e.message } finally { busy = false } }
                },
            )
        }
        error?.let { Text(it, fontSize = 13.sp, color = C.red) }
    }
}

/**
 * Where people write to the chat. The composer empties at once: the message lives in the chat's outbox until the station
 * has it (a failure shows there too). Before the agent has a chat, the first message makes one, bound to the agent, and
 * the page moves to it. `onHeight`: the capsule's height with its margins (what the list keeps clear of), not the menu
 * of chats over it.
 */
@Composable
internal fun Composer(station: String, of: ChatOf, view: ChatView, agents: List<AgentHere>, draft: Draft, haze: HazeState, modifier: Modifier = Modifier, onHeight: (Int) -> Unit = {}) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    val keeper = agents.firstOrNull()?.key
    // Uploads go on in the app's scope: a draft kept for the chat takes its files when they are up, the page gone or not.
    val launchers = AttachLaunchers { picked -> app.upload(draft, station, picked, app.scope) }
    val thread = view.thread
    val archived = view.archived == true
    draft.locked = view.offline || archived
    Column(modifier.fillMaxWidth()) {
        ChatRefMenu(draft, station, keeper, haze, Modifier.padding(horizontal = 10.dp))
        // A capsule floating over the list, which runs on around it.
        Box(Modifier.fillMaxWidth().onSizeChanged { onHeight(it.height) }.padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp)) {
            Column(
                Modifier.fillMaxWidth().floating(haze, RoundedCornerShape(ComposerCorner))
                    // A tap on the capsule's own room is a tap on the field.
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { draft.focus++ }
                    .animateContentSize(tween(220)).padding(ComposerInset),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (archived) ArchiveNotice(view.offline) { api.setArchived(thread?.id, (of as? ChatOf.Session)?.key ?: keeper ?: "", false) }
                if (view.offline) Text("这台 station 离线了：这里是之前读到的内容，暂时不能发消息。", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
                DraftExtras(draft)
                ComposerBar(draft, if (archived) "还原对话后才能发送" else "发消息", onPlus = { openAttach(app, launchers) },
                    // Typing starts the session's runtime, so a cold start overlaps the writing.
                    onType = {
                        if (!draft.locked && keeper != null && System.currentTimeMillis() - draft.warmed > 60_000) {
                            draft.warmed = System.currentTimeMillis()
                            scope.launch { try { api.warm(keeper) } catch (_: CoreException) {} }
                        }
                    },
                    onSend = {
                        if (draft.locked) return@ComposerBar
                        val taken = draft.take()
                        scope.launch {
                            // A chat made here (`new:…`) is sent to by its key until its station has made it.
                            val pending = (of as? ChatOf.Session)?.key?.takeIf { thread == null && it.startsWith("new:") }
                            if (pending != null) {
                                app.scope.launch { try { api.sendIn(pending, taken.text, taken.files.mapNotNull { it.done }, taken.quotes.map { it.sent() }) } catch (_: CoreException) {} }
                                return@launch
                            }
                            val to = thread?.id ?: try {
                                draft.starting = true
                                api.chatFor((of as ChatOf.Session).key)
                            } catch (e: CoreException) {
                                // No chat to send into: the draft comes back.
                                draft.restore(taken)
                                draft.error = e.message
                                return@launch
                            } finally {
                                draft.starting = false
                            }
                            // Sent from the app's scope: the page may move to the new chat before the station answers.
                            app.scope.launch { try { api.send(to, taken.text, taken.files.mapNotNull { it.done }, taken.quotes.map { it.sent() }) } catch (_: CoreException) {} }
                        }
                    })
                draft.error?.let { Text(it, fontSize = 12.sp, color = C.red, modifier = Modifier.padding(horizontal = 6.dp)) }
            }
        }
    }
}
