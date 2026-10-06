// Files in a chat, as web/src/Chat.tsx shows them: images and video stills side by side at their own proportions
// (known before they load, a ThumbHash likeness standing in), the rest as cards; any of them opens in a full-screen
// preview (FilePreview.kt).
package fail.still.android.screens

import fail.still.android.data.t
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.provider.MediaStore
import android.util.LruCache
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.data.Attachment
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ThumbHash
import fail.still.core.CoreException
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ── what a file is (web/src/FilePreview.tsx kindOf) ─────────────────────

enum class PreviewKind { Image, Video, Audio, Pdf, Markdown, Csv, Html, Code, Text;
    val label: String get() = t("android-chat.kind." + name.lowercase())
}

/** What a file shows as, by its name; `kind` null: look at its bytes to know. */
class Kind(val kind: PreviewKind?, val type: String, val language: String? = null)

private val MEDIA = mapOf(
    "png" to (PreviewKind.Image to "image/png"), "jpg" to (PreviewKind.Image to "image/jpeg"), "jpeg" to (PreviewKind.Image to "image/jpeg"),
    "gif" to (PreviewKind.Image to "image/gif"), "webp" to (PreviewKind.Image to "image/webp"), "svg" to (PreviewKind.Image to "image/svg+xml"),
    "avif" to (PreviewKind.Image to "image/avif"), "bmp" to (PreviewKind.Image to "image/bmp"), "ico" to (PreviewKind.Image to "image/x-icon"),
    "mp4" to (PreviewKind.Video to "video/mp4"), "m4v" to (PreviewKind.Video to "video/mp4"), "webm" to (PreviewKind.Video to "video/webm"),
    "mov" to (PreviewKind.Video to "video/quicktime"), "ogv" to (PreviewKind.Video to "video/ogg"),
    "mp3" to (PreviewKind.Audio to "audio/mpeg"), "m4a" to (PreviewKind.Audio to "audio/mp4"), "aac" to (PreviewKind.Audio to "audio/aac"),
    "wav" to (PreviewKind.Audio to "audio/wav"), "ogg" to (PreviewKind.Audio to "audio/ogg"), "oga" to (PreviewKind.Audio to "audio/ogg"),
    "opus" to (PreviewKind.Audio to "audio/ogg"), "flac" to (PreviewKind.Audio to "audio/flac"),
    "pdf" to (PreviewKind.Pdf to "application/pdf"),
    "md" to (PreviewKind.Markdown to "text/markdown"), "markdown" to (PreviewKind.Markdown to "text/markdown"),
    "csv" to (PreviewKind.Csv to "text/csv"), "tsv" to (PreviewKind.Csv to "text/tab-separated-values"),
    "html" to (PreviewKind.Html to "text/html"), "htm" to (PreviewKind.Html to "text/html"),
)
/** Extensions known by another name; the rest are tried as they are. */
private val LANGUAGE = mapOf(
    "mjs" to "js", "cjs" to "js", "mts" to "ts", "cts" to "ts", "h" to "c", "hh" to "cpp", "hpp" to "cpp", "cc" to "cpp", "cxx" to "cpp",
    "kts" to "kotlin", "yml" to "yaml", "zsh" to "bash", "sh" to "bash", "patch" to "diff", "htm" to "html", "conf" to "ini", "cfg" to "ini",
    "env" to "dotenv", "gradle" to "groovy", "plist" to "xml", "svg" to "xml",
)
private val PLAIN = setOf("txt", "text", "log", "out", "err", "lock")
private val NAMED = mapOf("dockerfile" to "docker", "makefile" to "make", "cmakelists.txt" to "cmake")
private val CODE = setOf(
    "ts", "tsx", "js", "jsx", "json", "jsonc", "json5", "py", "rs", "go", "java", "kt", "swift", "c", "cpp", "cs", "rb", "php", "bash", "fish", "ps1",
    "yaml", "toml", "xml", "sql", "css", "scss", "less", "html", "vue", "svelte", "lua", "dart", "diff", "ini", "dotenv", "groovy", "scala", "r", "pl", "ex", "exs",
    "erl", "hs", "ml", "clj", "zig", "nim", "proto", "graphql", "tex", "vim", "nix", "tf", "hcl", "docker", "make", "cmake", "asm", "wasm", "sol", "prisma", "astro",
)

fun kindOf(name: String): Kind {
    val lower = name.lowercase()
    NAMED[lower]?.let { return Kind(PreviewKind.Code, "text/plain", it) }
    val dot = lower.lastIndexOf('.')
    val ext = if (dot > 0) lower.substring(dot + 1) else ""
    MEDIA[ext]?.let { (kind, type) -> return Kind(kind, type, if (kind == PreviewKind.Html) "html" else null) }
    if (ext in PLAIN) return Kind(PreviewKind.Text, "text/plain")
    val language = LANGUAGE[ext] ?: ext
    if (language in CODE) return Kind(PreviewKind.Code, "text/plain", language)
    return Kind(null, "application/octet-stream")
}

fun isImage(name: String) = kindOf(name).kind == PreviewKind.Image

// ── fetching ───────────────────────────────────────────────────────────

/**
 * Files sent never change: each is fetched once (a chat's image as its thumbnail, a whole file when opened), the
 * most recent kept. How far each whole file on its way has come is kept for whoever shows it.
 */
/** Over this a file is fetched onto the disk a part at a time (FileData.toDisk), not into memory; web's BIG_FILE. */
const val BIG_FILE = 16L * 1024 * 1024
/** The most a station from before parts sends (whole). */
private const val WHOLE_FILE_MAX = 50L * 1024 * 1024

internal object FileData {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    // Bounded by what a phone's heap can spare: bytes up to 32 MB (a larger file is fetched again when opened again),
    // decoded pictures up to an eighth of the heap.
    private val kept = object : LruCache<String, ByteArray>(32 * 1024 * 1024) { override fun sizeOf(key: String, value: ByteArray) = value.size }
    private val coming = HashMap<String, Deferred<ByteArray>>()
    private val pictures = object : LruCache<String, ImageBitmap>((Runtime.getRuntime().maxMemory() / 8).coerceIn(8L * 1024 * 1024, Int.MAX_VALUE.toLong()).toInt()) { override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4 }
    /** Bytes so far and the whole size (null when the station does not say), of whole files on their way. */
    val progress = mutableStateMapOf<String, Pair<Long, Long?>>()

    fun id(station: String, key: String, file: Attachment, thumb: Boolean) = "$station/$key/${file.path}${if (thumb) "#thumb" else ""}"

    fun kept(id: String): ByteArray? = kept.get(id)

    /** The file (`thumb`: as a chat shows an image), fetched once however many ask. Call on the main thread. */
    fun fetch(app: AppState, station: String, key: String, file: Attachment, thumb: Boolean): Deferred<ByteArray> {
        val id = id(station, key, file, thumb)
        kept.get(id)?.let { return CompletableDeferred(it) }
        coming[id]?.let { return it }
        val on: ((Long, Long?) -> Unit)? = if (thumb) null else { loaded, total -> scope.launch { if (id in coming) progress[id] = loaded to total } }
        val got = scope.async {
            try {
                app.api(station).file(key, file.path.substringAfterLast('/'), thumb, on).second.also { kept.put(id, it) }
            } finally {
                coming.remove(id)
                progress.remove(id)
            }
        }
        coming[id] = got
        return got
    }

    /** A picture decoded from `bytes`, its longer side at most `longest` pixels; kept by `id`. */
    suspend fun picture(id: String, bytes: ByteArray, longest: Int): ImageBitmap? {
        val tag = "$id@$longest"
        pictures.get(tag)?.let { return it }
        return withContext(Dispatchers.Default) { decode(bytes, longest) }?.also { pictures.put(tag, it) }
    }

    fun keptPicture(id: String, longest: Int): ImageBitmap? = pictures.get("$id@$longest")

    /** Pictures sent from here as they were picked (by station and file name), until the station's own are read. */
    private val sent = LruCache<String, ImageBitmap>(32)
    fun keepSent(station: String, path: String, picture: ImageBitmap) { sent.put("$station\n${path.substringAfterLast('/')}", picture) }
    fun sentPicture(station: String, path: String): ImageBitmap? = sent.get("$station\n${path.substringAfterLast('/')}")
    fun keepPicture(id: String, longest: Int, picture: ImageBitmap) { pictures.put("$id@$longest", picture) }

    private val comingToDisk = HashMap<String, Deferred<File>>()

    /**
     * A big file (over [BIG_FILE]) onto the phone's disk a part at a time, never all in memory: what the viewers of a
     * big one read. Fetched once however many ask, and gone on from where it stopped when asked again; its progress as
     * a whole file's. A station from before parts sends it whole, as long as that takes it ([WHOLE_FILE_MAX]). Call on
     * the main thread.
     */
    fun toDisk(app: AppState, context: Context, station: String, key: String, file: Attachment): Deferred<File> {
        val id = id(station, key, file, thumb = false)
        comingToDisk[id]?.let { return it }
        val got = scope.async {
            try {
                val done = withContext(Dispatchers.IO) { KeptFiles.place(context, id, file.name, file.size) }
                if (done.exists() && done.length() == file.size) return@async done.also { it.setLastModified(System.currentTimeMillis()) }
                val part = File(done.parentFile, done.name + ".part")
                val name = file.path.substringAfterLast('/')
                try {
                    app.api(station).fileToDisk(key, name, part) { loaded, total -> scope.launch { if (id in comingToDisk) progress[id] = loaded to total } }
                } catch (e: CoreException) {
                    if (e.code != "unsupported" || file.size > WHOLE_FILE_MAX) throw e
                    return@async onDisk(context, id, file.name, app.api(station).file(key, name, false, null).second)
                }
                withContext(Dispatchers.IO) { part.renameTo(done) }
                done
            } finally {
                comingToDisk.remove(id)
                progress.remove(id)
            }
        }
        comingToDisk[id] = got
        return got
    }

    /** The file on the phone's disk, for what reads a file rather than bytes (the players, PdfRenderer); kept until the
     * person deletes it (settings → files kept, KeptFiles.kt). */
    suspend fun onDisk(context: Context, id: String, name: String, bytes: ByteArray): File = withContext(Dispatchers.IO) {
        val file = KeptFiles.place(context, id, name, bytes.size.toLong())
        if (!file.exists() || file.length() != bytes.size.toLong()) {
            val part = File(file.parentFile, file.name + ".part")
            part.writeBytes(bytes)
            part.renameTo(file)
        } else file.setLastModified(System.currentTimeMillis())
        file
    }
}

/**
 * A picture from bytes, its longer side at most `longest` pixels: decoded at the power-of-two sample that brings it
 * within (never the whole of a huge photo in memory), then scaled the rest of the way if the decoder rounded up.
 */
fun decode(bytes: ByteArray, longest: Int): ImageBitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    val max = maxOf(bounds.outWidth, bounds.outHeight)
    var sample = 1
    if (longest > 0) while (max / sample > longest) sample *= 2
    val got = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
    val side = maxOf(got.width, got.height)
    if (longest <= 0 || side <= longest) return got.asImageBitmap()
    val scaled = Bitmap.createScaledBitmap(got, maxOf(1, got.width * longest / side), maxOf(1, got.height * longest / side), true)
    if (scaled !== got) got.recycle()
    return scaled.asImageBitmap()
}

// ── in the chat ────────────────────────────────────────────────────────

/** A file and the session that keeps it. */
class Shown(val key: String, val file: Attachment)

/** The chat's images in the order it shows them: an image opened steps to the one before or after. */
internal fun Here.images(): List<Shown> =
    (view.messages.flatMap { it.attachments } + view.outbox.flatMap { it.attachments }).mapNotNull { f -> owner(f)?.takeIf { isImage(f.name) }?.let { Shown(it, f) } }

/** A message's files, side by side and wrapping (6dp apart); `owner` says which session of the chat keeps each. */
@Composable
internal fun Files(ctx: Here, list: List<Attachment>, mine: Boolean = false) {
    if (list.isEmpty()) return
    var open by remember { mutableStateOf<Attachment?>(null) }
    Wrap(6.dp, end = mine) {
        // Each flown into from its tile in the composer, when it was just sent from there (ChatHost.kt).
        list.forEach { f -> Box(Modifier.landingFile(f.path)) { FileItem(ctx.station, ctx.owner(f), f) { open = f } } }
    }
    val shown = open
    val key = shown?.let { ctx.owner(it) }
    if (shown != null && key != null) FilePreview(ctx.station, key, shown, gallery = { ctx.images() }) { open = null }
}

/** Its children in rows as wide as it may be, `gap` apart, each row from the start (or the end). */
@Composable
private fun Wrap(gap: Dp, end: Boolean, content: @Composable () -> Unit) {
    Layout(content) { measurables, constraints ->
        val space = gap.roundToPx()
        val items = measurables.map { it.measure(constraints.copy(minWidth = 0, minHeight = 0)) }
        val rows = ArrayList<MutableList<Placeable>>()
        var used = 0
        for (p in items) {
            if (rows.isEmpty() || used + space + p.width > constraints.maxWidth) { rows += mutableListOf(p); used = p.width }
            else { rows.last() += p; used += space + p.width }
        }
        val widths = rows.map { r -> r.sumOf { it.width } + space * (r.size - 1) }
        val width = (widths.maxOrNull() ?: 0).coerceIn(constraints.minWidth, constraints.maxWidth)
        val height = rows.sumOf { r -> r.maxOf { it.height } } + space * (rows.size - 1).coerceAtLeast(0)
        layout(width, height.coerceAtLeast(constraints.minHeight)) {
            var y = 0
            rows.forEachIndexed { i, r ->
                var x = if (end) width - widths[i] else 0
                r.forEach { p -> p.place(x, y); x += p.width + space }
                y += r.maxOf { it.height } + space
            }
        }
    }
}

/**
 * An image of the chat on its own (placed in an agent's text, Prose.kt): in the box `modifier` gives it (else its own
 * proportions); a tap opens it in the preview, stepping through `gallery`.
 */
@Composable
internal fun StationImage(station: String, key: String, file: Attachment, modifier: Modifier? = null, gallery: () -> List<Shown> = { emptyList() }) {
    var open by remember { mutableStateOf(false) }
    ChatImage(station, key, file, modifier) { open = true }
    if (open) FilePreview(station, key, file, gallery) { open = false }
}

/** One file of the chat on its own, as a message shows it, opening in the preview (what has no message around it). */
@Composable
internal fun StationFile(station: String, key: String, file: Attachment) {
    var open by remember { mutableStateOf(false) }
    FileItem(station, key, file) { open = true }
    if (open) FilePreview(station, key, file) { open = false }
}

/** Images and video stills show in a box of their own proportions; other files are a card. Either opens in a preview. */
@Composable
private fun FileItem(station: String, key: String?, file: Attachment, onOpen: () -> Unit) {
    val kind = kindOf(file.name).kind
    when {
        key != null && kind == PreviewKind.Image -> ChatImage(station, key, file, onOpen = onOpen)
        key != null && kind == PreviewKind.Video -> ChatVideo(station, key, file, onOpen)
        else -> FileCard(file.name, file.size, onClick = if (key != null) onOpen else null)
    }
}

/**
 * The box an image takes in the chat, known before it loads: its own proportions (sent with it, or read from its
 * ThumbHash) as mediaSize puts them, or a fixed box for images sent before sizes were recorded. A narrower chat shrinks it.
 */
fun imageBox(file: Attachment, least: Float = 16f): MediaSize {
    val ratio = ThumbHash.ratio(file.thumbhash)
    val (w, h) = when {
        file.width != null && file.height != null && file.width > 0 && file.height > 0 -> file.width.toFloat() to file.height.toFloat()
        ratio != null -> Math.round(160 * ratio).toFloat() to 160f
        else -> return MediaSize(240f, 160f)
    }
    return mediaSize(w, h, least)
}

private val ImageShape = RoundedCornerShape(10.dp)
private val EaseOut = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)

/** Images already brushed in on this run (station, session and path): shown again, they just show. */
private val revealed = HashSet<String>()

/** An image's box; until it loads, its likeness (or the blots drifting); one that takes a while is brushed in from the top. */
@Composable
private fun ChatImage(station: String, key: String, file: Attachment, size: Modifier? = null, onOpen: () -> Unit) {
    val app = LocalApp.current
    val id = FileData.id(station, key, file, thumb = true)
    val longest = with(LocalDensity.current) { 360.dp.roundToPx() }
    // One sent from here shows the picture it had in the composer until the station's comes (it flies in from there).
    val sent = remember(id) { FileData.sentPicture(station, file.path) }
    var image by remember(id) { mutableStateOf(FileData.keptPicture(id, longest) ?: sent) }
    var failed by remember(id) { mutableStateOf(false) }
    val instant = remember(id) { image != null || id in revealed }
    val born = remember(id) { System.currentTimeMillis() }
    var reveal by remember(id) { mutableStateOf(false) }
    LaunchedEffect(id) {
        if (FileData.keptPicture(id, longest) != null) return@LaunchedEffect
        try {
            val bytes = FileData.fetch(app, station, key, file, thumb = true).await()
            val got = FileData.picture(id, bytes, longest)
            if (got == null) failed = sent == null
            else {
                reveal = !instant && System.currentTimeMillis() - born >= 150
                image = got
                revealed += id
            }
        } catch (_: CoreException) {
            failed = sent == null
        }
    }
    // What the viewer grows out of and shrinks back into (FilePreview.kt).
    val thumb = FileViewers.id(station, key, file.path)
    ForgetThumb(thumb)
    val radius = with(LocalDensity.current) { 10.dp.toPx() }
    val box = imageBox(file)
    // Letterboxed only in its own box (one given it is filled).
    val fit = box.fit.takeIf { size == null }
    MediaBox(box, Modifier.clickable(enabled = image != null || failed, onClick = onOpen), background = if (fit != null && !failed) Color.Transparent else C.chip, size = size, thumb = Modifier.viewerThumb(thumb, radius, letterbox = fit != null) { image }) {
        if (!instant) Waiting(file.thumbhash, loaded = image != null, still = failed, fit = fit)
        if (failed) Unavailable(20.dp, null)
        image?.let { Revealed(it, file.name, reveal, if (fit != null) ContentScale.Fit else ContentScale.Crop) }
    }
}

@Composable
private fun MediaBox(box: MediaSize, modifier: Modifier, background: Color = C.chip, size: Modifier? = null, thumb: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box((size ?: Modifier.widthIn(max = box.width.dp).fillMaxWidth().aspectRatio(box.width / box.height)).then(thumb).clip(ImageShape).background(background).then(modifier), content = content)
}

/** The picture, brushed in from the top when `reveal` (blurred to sharp, from a little larger), else just shown. */
@Composable
private fun Revealed(image: ImageBitmap, name: String, reveal: Boolean, scale: ContentScale) {
    val t = remember { Animatable(if (reveal) 0f else 1f) }
    LaunchedEffect(Unit) { if (t.value < 1f) t.animateTo(1f, tween(1100, easing = EaseOut)) }
    val density = LocalDensity.current
    Image(
        image, name, contentScale = scale,
        modifier = Modifier.fillMaxSize()
            .graphicsLayer {
                val k = t.value
                if (k < 1f) {
                    scaleX = 1.04f - 0.04f * k; scaleY = scaleX
                    val blur = with(density) { (14 * (1 - k)).dp.toPx() }
                    if (blur > 0.5f && android.os.Build.VERSION.SDK_INT >= 31) renderEffect = BlurEffect(blur, blur, TileMode.Clamp)
                    compositingStrategy = CompositingStrategy.Offscreen
                }
            }
            .drawWithContent {
                drawContent()
                val k = t.value
                if (k < 1f) {
                    // The web's mask: opaque down to an edge that sweeps from above the box to below it.
                    val h = size.height
                    val solid = -0.5f * h + 1.5f * h * k
                    val clear = 1.5f * h * k
                    drawRect(Brush.verticalGradient(0f to Color.Black, 1f to Color.Transparent, startY = solid, endY = clear), blendMode = BlendMode.DstIn)
                }
            },
    )
}

/**
 * What an image's box shows until it loads: its ThumbHash drawn, sent with it; else a few warm blots drifting. Fades
 * once it has. Letterboxed, it takes only the image's share of the box (`fit`), centred.
 */
@Composable
private fun BoxScope.Waiting(hash: String?, loaded: Boolean, still: Boolean, fit: Pair<Float, Float>?) {
    val fade = remember { Animatable(1f) }
    LaunchedEffect(loaded) { if (loaded) fade.animateTo(0f, tween(300, delayMillis = 800, easing = EaseOut)) }
    if (fade.value == 0f) return
    val likeness = remember(hash) { ThumbHash.image(hash) }
    val area = if (fit == null) Modifier.matchParentSize() else Modifier.align(Alignment.Center).fillMaxWidth(fit.first).fillMaxHeight(fit.second)
    Box(area.alpha(fade.value).background(C.chip).clipToBounds()) {
        if (likeness != null) Image(likeness, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Blots(still)
    }
}

@Composable
private fun BoxScope.Blots(still: Boolean) {
    val dark = C.dark
    val blots = remember(dark) {
        listOf(
            Blot(if (dark) Color(0xFF7C3A22) else Color(0xFFF6A27E), -0.15f, -0.2f, 0.35f, 0.25f, 1.15f, 6000),
            Blot(if (dark) Color(0xFF6A4A22) else Color(0xFFF1C58C), 0.5f, 0.1f, -0.3f, 0.2f, 0.9f, 7000),
            Blot(if (dark) Color(0xFF6B3534) else Color(0xFFE7A9A1), 0.15f, 0.65f, 0.2f, -0.3f, 1.1f, 8000),
        )
    }
    val drift = rememberInfiniteTransition("blots")
    val phases = blots.map { b ->
        if (still) remember { mutableStateOf(0f) }
        else drift.animateFloat(0f, 1f, infiniteRepeatable(tween(b.ms, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)), RepeatMode.Reverse), "blot")
    }
    Box(Modifier.matchParentSize().drawWithContent {
        val side = size.width * 0.7f
        blots.forEachIndexed { i, b ->
            val p = phases[i].value
            val s = side * (1 + (b.scale - 1) * p)
            val cx = size.width * b.x + side / 2 + side * b.dx * p
            val cy = size.height * b.y + side / 2 + side * b.dy * p
            // Blurred edges: a radial fall-off rather than a blur filter.
            drawCircle(Brush.radialGradient(0f to b.color.copy(alpha = 0.75f), 0.55f to b.color.copy(alpha = 0.45f), 1f to Color.Transparent, center = Offset(cx, cy), radius = s * 0.8f), s * 0.8f, Offset(cx, cy))
        }
    })
}

private class Blot(val color: Color, val x: Float, val y: Float, val dx: Float, val dy: Float, val scale: Float, val ms: Int)

/** Not to be had (fetching it failed): the box stays as it waited, and says so. */
@Composable
private fun BoxScope.Unavailable(icon: Dp, size: Long?) {
    Column(
        Modifier.matchParentSize().background(C.chip.copy(alpha = 0.7f)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        IconIn(Icons.Read, icon, C.muted)
        Text(t("android-chat.file.noPreview"), fontSize = 12.sp, color = C.muted)
        if (size != null) Text(fileSize(size), fontSize = 11.sp, color = C.muted)
    }
}

/** A video's first frame on black, a play mark over it and its name along the bottom; tapped, it plays in the preview. */
@Composable
private fun ChatVideo(station: String, key: String, file: Attachment, onOpen: () -> Unit) {
    val app = LocalApp.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val id = FileData.id(station, key, file, thumb = false)
    var still by remember(id) { mutableStateOf(FileData.keptPicture("$id#still", 0)) }
    var failed by remember(id) { mutableStateOf(false) }
    LaunchedEffect(id) {
        if (still != null) return@LaunchedEffect
        try {
            // The station's poster where it makes one; else the video itself while it is small, its first frame drawn
            // here; a big one shows without (fetched whole only to be drawn from, it would not fit in memory).
            val poster = try { app.api(station).poster(key, file.path.substringAfterLast('/')) } catch (_: CoreException) { null }
            val drawn = poster?.let { withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(it, 0, it.size) } }
            if (drawn != null) { still = drawn.asImageBitmap().also { FileData.keepPicture("$id#still", 0, it) }; return@LaunchedEffect }
            if (file.size <= 0 || file.size > BIG_FILE) return@LaunchedEffect
            val bytes = FileData.fetch(app, station, key, file, thumb = false).await()
            val path = FileData.onDisk(context, id, file.name, bytes)
            val frame = withContext(Dispatchers.IO) {
                val r = MediaMetadataRetriever()
                try { r.setDataSource(path.path); r.getFrameAtTime(0) } catch (_: Exception) { null } finally { r.release() }
            }
            if (frame == null) failed = true else still = frame.asImageBitmap().also { FileData.keepPicture("$id#still", 0, it) }
        } catch (_: CoreException) {
            failed = true
        }
    }
    val thumb = FileViewers.id(station, key, file.path)
    ForgetThumb(thumb)
    val radius = with(LocalDensity.current) { 10.dp.toPx() }
    // Thick enough for the play mark and the name along the bottom.
    val box = imageBox(file, least = 96f)
    MediaBox(box, Modifier.clickable(onClick = onOpen), background = if (failed) C.chip else Color.Black, thumb = Modifier.viewerThumb(thumb, radius, letterbox = box.fit != null) { FileViewers.frames[thumb]?.picture ?: still }) {
        if (failed) {
            Column(Modifier.matchParentSize().padding(bottom = 30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
                IconIn(Icons.Read, 24.dp, C.muted)
                Text(t("android-chat.file.noPreview"), fontSize = 13.sp, color = C.muted)
                Text(fileSize(file.size), fontSize = 11.sp, color = C.muted)
            }
        } else {
            // The frame the viewer was left at, once it has been closed back into here; else the first.
            (FileViewers.frames[thumb]?.picture ?: still)?.let { Image(it, file.name, Modifier.fillMaxSize(), contentScale = if (box.fit != null) ContentScale.Fit else ContentScale.Crop) }
            // The web's "▶" at 20px: a solid triangle.
            Box(Modifier.align(Alignment.Center).size(40.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.65f)), contentAlignment = Alignment.Center) {
                androidx.compose.foundation.Canvas(Modifier.padding(start = 2.dp).size(12.dp, 14.dp)) {
                    drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(0f, 0f); lineTo(size.width, size.height / 2); lineTo(0f, size.height); close() }, Color.White)
                }
            }
        }
        Text(
            file.name, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (failed) C.ink else Color.White,
            // Centred, as in the web's button.
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().let { if (failed) it.padding(horizontal = 12.dp, vertical = 8.dp) else it.background(Color.Black.copy(alpha = 0.65f)).padding(horizontal = 8.dp, vertical = 6.dp) },
        )
    }
}

/** Puts a file in the phone's Downloads. */
suspend fun download(context: Context, name: String, bytes: ByteArray, type: String? = null): Boolean = withContext(Dispatchers.IO) {
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, name)
        (type ?: kindOf(name).type).takeIf { it != "application/octet-stream" }?.let { put(MediaStore.Downloads.MIME_TYPE, it) }
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return@withContext false
    context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null
}

/** A file on the phone's disk saved to Downloads (a big one, not read into memory). */
suspend fun download(context: Context, name: String, from: File): Boolean = withContext(Dispatchers.IO) {
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, name)
        kindOf(name).type.takeIf { it != "application/octet-stream" }?.let { put(MediaStore.Downloads.MIME_TYPE, it) }
    }
    val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return@withContext false
    context.contentResolver.openOutputStream(uri)?.use { out -> from.inputStream().use { it.copyTo(out, 1 shl 16) } } != null
}

/**
 * A file as a card: its kind's mark, its name, and its size (or what it is doing: uploading, failed); `onRemove`
 * takes it out of a draft, `onClick` opens it.
 */
@Composable
internal fun FileCard(
    name: String, size: Long, note: String? = null, busy: Boolean = false, onRemove: (() -> Unit)? = null,
    shape: Shape = RoundedCornerShape(8.dp), onClick: (() -> Unit)? = null,
) {
    Row(
        // The wide screen's neutral ground (web toast.css.ts → fileCard: --neutral-bg), a cool grey, not the page's warm chip.
        Modifier.width(236.dp).clip(shape).background(chatInk().neutral).let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (busy) Spinner(14.dp) else IconIn(Icons.Read, 16.dp, C.muted)
        Column(Modifier.weight(1f)) {
            Text(name, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(note ?: fileSize(size), fontSize = 11.sp, lineHeight = 16.sp, color = if (note != null && !busy) C.red else C.muted)
        }
        if (onRemove != null) Box(Modifier.size(22.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.06f)).clickable(onClick = onRemove), contentAlignment = Alignment.Center) {
            IconIn(Icons.Close, 12.dp, C.muted)
        }
    }
}

fun fileSize(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${Math.round(bytes / 1024.0)} KB"
    bytes < 1024L * 1024 * 1024 -> String.format(java.util.Locale.ROOT, "%.1f MB", bytes / 1024.0 / 1024.0)
    else -> String.format(java.util.Locale.ROOT, "%.2f GB", bytes / 1024.0 / 1024.0 / 1024.0)
}
