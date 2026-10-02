// A file sent in a chat, opened over the whole screen (web/src/FilePreview.tsx): images to zoom, pan, step through
// and mark; video and audio to play; PDFs drawn page by page (PdfRenderer); Markdown rendered; CSV as a table; HTML
// in a WebView of its own; code and text highlighted. Anything else says it cannot be shown and offers the download.
// One bar floats at the top with its name and tools, frosted, and fades when left alone; a tap brings it back.
package fail.still.android.screens

import fail.still.android.ui.t
import android.annotation.SuppressLint
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import fail.still.android.ui.keyboard
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.runtime.rememberUpdatedState
import fail.still.android.ui.Swipe
import kotlinx.coroutines.CoroutineStart
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Stable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import fail.still.android.ui.Ease
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import fail.still.android.LocalApp
import fail.still.android.data.Attachment
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Markdown
import fail.still.android.ui.Seg
import fail.still.android.ui.ZoomState
import fail.still.android.ui.highlight
import fail.still.android.ui.zoomable
import fail.still.core.CoreException
import java.io.File
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sign
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** The bars fade after this long left alone; after a tap that brought them back, a while longer. */
private const val REST_MS = 2000L
private const val TAP_REST_MS = 4000L
/** Above this a file shows as plain text, unhighlighted; above the next, only its start. */
private const val HIGHLIGHT_LIMIT = 256 * 1024
private const val SHOW_LIMIT = 2 * 1024 * 1024
private const val TABLE_ROWS = 2000

/** Dark whatever the theme, as a viewer of pictures: its text, what is quieter, its canvas. */
private val DarkText = Color(0xFFF4F4F5)
private val DarkMuted = Color.White.copy(alpha = 0.6f)
private val DarkCanvas = Color(0xFF111113)

private sealed interface FileLoad {
    class Loading(val got: Pair<Long, Long?>?) : FileLoad
    class Failed(val message: String) : FileLoad
    class Ready(val bytes: ByteArray) : FileLoad
}

/**
 * `file` (kept by the session `key`) over the whole screen; `gallery`: the chat's images, for an image to step to the
 * one before or after. Back (or ×) closes it.
 */
@Composable
fun FilePreview(station: String, key: String, file: Attachment, gallery: () -> List<Shown> = { emptyList() }, onClose: () -> Unit) {
    // Drawn by ViewerHost, a layer of the app's own window over the pages (not a dialog's window of its own): it can grow
    // out of the thumbnail in the chat and shrink back into it. Here it only says it is open, while it is.
    val open = remember { ViewerOpen(station, Shown(key, file), gallery) }
    open.onClose = onClose
    DisposableEffect(open) {
        FileViewers.shown = open
        onDispose { if (FileViewers.shown === open) { FileViewers.shown = null; FileViewers.hidden = null } }
    }
}

// ── the viewer's layer, and its flight from and to the chat ────────────

/** The viewer grows from the thumbnail this long, and shrinks back into it; both on web mobile's --m-ease (.2, .8, .2, 1). */
private const val OPEN_MS = 320
private const val CLOSE_MS = 280
/** Opened or closed with no thumbnail on the screen: the web's fade (FilePreview.css.ts fp: 140ms ease-out). */
private const val FADE_MS = 140

internal class ViewerOpen(val station: String, val opened: Shown, val gallery: () -> List<Shown>) {
    var onClose: () -> Unit = {}
}

/** Where a thumbnail in the chat is (in the window), what it shows, and whether any of it is on the screen. */
internal class Thumb(val bounds: Rect, val visible: Boolean, val radius: Float, val picture: () -> ImageBitmap?)

/** The viewer open, if one is; the chat's thumbnails by the file each shows; the one hidden while the viewer is its picture. */
object FileViewers {
    internal var shown by mutableStateOf<ViewerOpen?>(null)
    val open: Boolean get() = shown != null
    internal val thumbs = HashMap<String, Thumb>()
    internal var hidden by mutableStateOf<String?>(null)
    /**
     * A video closed back into its thumbnail keeps the frame it was left at (web: its still is set to that time): the
     * thumbnail shows it from then on, and opened again the video goes on from there. By the thumbnail's id.
     */
    internal val frames = mutableStateMapOf<String, KeptFrame>()
    internal fun id(station: String, key: String, path: String) = "$station/$key/$path"
}

/**
 * A thumbnail in the chat the viewer opens from (`id`: FileViewers.id): where it is, kept as it moves; hidden while the
 * viewer shows its picture in its place (one picture on the screen, never two).
 */
internal fun Modifier.viewerThumb(id: String, radius: Float, picture: () -> ImageBitmap?): Modifier =
    onGloballyPositioned { c ->
        val at = c.positionInRoot()
        FileViewers.thumbs[id] = Thumb(Rect(at, Size(c.size.width.toFloat(), c.size.height.toFloat())), c.boundsInRoot().let { it.width > 0 && it.height > 0 }, radius, picture)
    }.graphicsLayer { alpha = if (FileViewers.hidden == id) 0f else 1f }

@Composable
internal fun ForgetThumb(id: String) {
    DisposableEffect(id) { onDispose { FileViewers.thumbs.remove(id) } }
}

/**
 * The picture's flight: `p` 0 is the thumbnail (its box, its corners, the picture cropped to it as the chat shows it),
 * 1 the picture where the stage puts it. One value moves the picture, its crop and corners, the black behind it and
 * the bars together.
 */
@Stable
internal class KeptFrame(val picture: ImageBitmap, val atUs: Long)

internal class ViewerFlight {
    enum class Phase { Waiting, Flying, Rest, Fading }
    var phase by mutableStateOf(Phase.Rest)
    val p = Animatable(1f)
    val fade = Animatable(1f)
    /** The thumbnail's box on the stage. */
    var from: Rect? = null
    var radius = 0f
    /** The picture's box on the stage, as it is now (null until known). */
    var target: () -> Rect? = { null }
    /** A video's frame as it shows now, and where it is (null for a picture, or before the player has one). */
    var frame: suspend () -> KeptFrame? = { null }
    /** How much of the viewer's ground and bars shows. */
    val chrome: Float get() = when (phase) { Phase.Waiting -> 0f; Phase.Flying -> p.value; else -> 1f }
}

/** The stage (what shows the picture) carried from the thumbnail's box to its own place, or back. */
internal fun Modifier.viewerFlying(f: ViewerFlight): Modifier = graphicsLayer {
    when (f.phase) {
        ViewerFlight.Phase.Waiting -> alpha = 0f
        ViewerFlight.Phase.Flying -> {
            val from = f.from
            val to = f.target()
            if (from == null || to == null || to.width <= 0f || to.height <= 0f) return@graphicsLayer
            val t = f.p.value
            // Covering the thumbnail's box at the start, as a cropped picture does.
            val s0 = max(from.width / to.width, from.height / to.height)
            val s = s0 + (1f - s0) * t
            val c = androidx.compose.ui.geometry.lerp(from.center, to.center, t)
            transformOrigin = TransformOrigin(to.center.x / size.width, to.center.y / size.height)
            scaleX = s; scaleY = s
            translationX = c.x - to.center.x; translationY = c.y - to.center.y
            // The crop, in the stage's own (unscaled) terms: the thumbnail's box growing into the picture's.
            val w = (from.width + (to.width - from.width) * t) / s
            val h = (from.height + (to.height - from.height) * t) / s
            val r = f.radius * (1f - t) / s
            val box = Rect(Offset(to.center.x - w / 2, to.center.y - h / 2), Size(w, h))
            shape = object : Shape {
                override fun createOutline(size: Size, layoutDirection: androidx.compose.ui.unit.LayoutDirection, density: androidx.compose.ui.unit.Density) =
                    Outline.Rounded(RoundRect(box, CornerRadius(r)))
            }
            clip = true
        }
        else -> {}
    }
}

/** The viewer open over the pages (App.kt puts it over them, under sheets, menus and toasts). */
@Composable
fun ViewerHost() {
    val open = FileViewers.shown ?: return
    key(open) { ViewerLayer(open) }
}

@Composable
private fun ViewerLayer(open: ViewerOpen) {
    val scope = rememberCoroutineScope()
    val flight = remember { ViewerFlight() }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var current by remember { mutableStateOf(open.opened) }
    var closing by remember { mutableStateOf(false) }
    // It comes up in the keyboard's place: what was being typed into lets go of it first.
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    fun idOf(s: Shown) = FileViewers.id(open.station, s.key, s.file.path)
    fun thumbOf(s: Shown) = FileViewers.thumbs[idOf(s)]?.takeIf { it.visible && known(s) }
    LaunchedEffect(Unit) {
        focus.clearFocus(); keyboard?.hide()
        val thumb = thumbOf(open.opened)
        val known = thumb != null && withTimeoutOrNull(400) {
            flight.phase = ViewerFlight.Phase.Waiting
            snapshotFlow { flight.target() }.first { it != null }
        } != null
        if (thumb != null && known) {
            flight.from = thumb.bounds.translate(-origin)
            flight.radius = thumb.radius
            flight.p.snapTo(0f)
            FileViewers.hidden = idOf(open.opened)
            flight.phase = ViewerFlight.Phase.Flying
            flight.p.animateTo(1f, tween(OPEN_MS, easing = Ease.Arrive))
        } else {
            flight.phase = ViewerFlight.Phase.Fading
            flight.fade.snapTo(0f)
            flight.fade.animateTo(1f, tween(FADE_MS, easing = Ease.Out))
        }
        flight.phase = ViewerFlight.Phase.Rest
        FileViewers.hidden = null
    }
    fun close() {
        if (closing) return
        closing = true
        scope.launch {
            val thumb = thumbOf(current)
            if (thumb != null && flight.target() != null) {
                flight.from = thumb.bounds.translate(-origin)
                flight.radius = thumb.radius
                if (flight.phase != ViewerFlight.Phase.Flying) flight.p.snapTo(1f)
                // The thumbnail it lands in shows the frame it goes back with (hidden until then, so never seen changing).
                flight.frame()?.let { FileViewers.frames[idOf(current)] = it }
                FileViewers.hidden = idOf(current)
                flight.phase = ViewerFlight.Phase.Flying
                flight.p.animateTo(0f, tween(CLOSE_MS, easing = Ease.Arrive))
            } else {
                // As web's: the viewer fades from where it is (140ms), its thumbnail (if it hid one) shown again at once.
                if (flight.phase == ViewerFlight.Phase.Flying) flight.fade.snapTo(flight.p.value)
                FileViewers.hidden = null
                flight.phase = ViewerFlight.Phase.Fading
                flight.fade.animateTo(0f, tween(FADE_MS, easing = Ease.Out))
            }
            // Left drawn as it ended (on the thumbnail, or gone) until the page lets it go.
            open.onClose()
        }
    }
    BackHandler(enabled = !closing) { close() }
    Box(
        Modifier.fillMaxSize().onGloballyPositioned { origin = it.positionInRoot() }
            .graphicsLayer { if (flight.phase == ViewerFlight.Phase.Fading) alpha = flight.fade.value }
            // Its own: no touch reaches the page under it.
            .pointerInput(Unit) { awaitEachGesture { awaitFirstDown(requireUnconsumed = false) } },
    ) {
        Viewer(open.station, open.opened, open.gallery, ::close, flight, closing) { current = it }
    }
}

/** A kind the viewer carries between the thumbnail and its stage: images, and videos' stills. */
private fun known(s: Shown) = kindOf(s.file.name).kind.let { it == PreviewKind.Image || it == PreviewKind.Video }

@Composable
private fun Viewer(station: String, opened: Shown, gallery: () -> List<Shown>, onClose: () -> Unit, flight: ViewerFlight, closing: Boolean, onShown: (Shown) -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current.density
    var shown by remember { mutableStateOf(opened) }
    val file = shown.file
    val key = shown.key
    LaunchedEffect(shown) { onShown(shown) }
    val known = remember(file.path) { kindOf(file.name) }
    val images = remember(file.path) { if (known.kind == PreviewKind.Image) gallery() else emptyList() }
    val at = images.indexOfFirst { it.file.path == file.path }
    val before = if (at > 0) images[at - 1] else null
    val after = if (at >= 0) images.getOrNull(at + 1) else null
    val fullId = FileData.id(station, key, file, thumb = false)
    fun keptLoad() = FileData.kept(fullId)?.let { FileLoad.Ready(it) } ?: FileLoad.Loading(null)
    // By the file it is of: stepped to another, what came of the one before is not taken for it (not even for a frame).
    val got by produceState<Pair<String, FileLoad>>(fullId to keptLoad(), fullId) {
        if (value.first == fullId && value.second is FileLoad.Ready) return@produceState
        value = fullId to keptLoad()
        if (value.second is FileLoad.Ready) return@produceState
        value = fullId to try { FileLoad.Ready(FileData.fetch(app, station, key, file, thumb = false).await()) } catch (e: CoreException) { FileLoad.Failed(e.message) }
    }
    val loaded = got.second.takeIf { got.first == fullId } ?: keptLoad()
    val progress = FileData.progress[fullId]
    val shownLoaded = (loaded as? FileLoad.Loading)?.let { FileLoad.Loading(progress) } ?: loaded
    // The neighbours are fetched ahead, so a step shows the next one at once.
    LaunchedEffect(before?.file?.path, after?.file?.path) {
        listOfNotNull(before, after).forEach { n -> FileData.fetch(app, station, n.key, n.file, thumb = false) }
    }
    val bytes = (loaded as? FileLoad.Ready)?.bytes
    // What a file of no known kind is: text, when its first bytes read as UTF-8 with no NULs.
    val kind = known.kind ?: bytes?.let { if (looksLikeText(it)) PreviewKind.Text else null }
    val dark = kind == PreviewKind.Image || kind == PreviewKind.Video

    // The bars float over the file, and fade when left alone (not while an image comes, nor while marking).
    var awake by remember { mutableStateOf(true) }
    var rest by remember { mutableStateOf<Job?>(null) }
    fun wake(ms: Long = REST_MS) {
        awake = true
        rest?.cancel()
        rest = scope.launch { delay(ms); awake = false }
    }
    fun toggle() { if (awake) { rest?.cancel(); awake = false } else wake(TAP_REST_MS) }
    LaunchedEffect(file.path) { wake() }

    val zoom = remember(file.path) { ZoomState(density) }
    val marks = remember(file.path) { ImageMarks(zoom, density) }

    // The one shown and those beside it move as one strip, GAP apart (web: FilePreview.tsx go): a step slides it out to
    // one side and the next in from the other, a swipe carries it under the finger first. The one going is drawn from
    // its picture where it was.
    val strip = remember { Animatable(0f) }
    var leaving by remember { mutableStateOf<Leaving?>(null) }
    var width by remember { mutableIntStateOf(0) }
    val near by rememberUpdatedState(before to after)
    val gap = with(LocalDensity.current) { SLIDE_GAP.toPx() }
    val chatLongest = with(LocalDensity.current) { 360.dp.roundToPx() }
    fun back(v: Float = 0f) { scope.launch { strip.animateTo(0f, SLIDE, v) } }
    fun go(dir: Int, v: Float = 0f) {
        val to = (if (dir < 0) near.first else near.second) ?: return back(v)
        val w = width + gap
        val from = strip.value
        val was = shown
        leaving = zoom.rect()?.let { r -> leavingPicture(station, was, chatLongest)?.let { Leaving(it, r, dir, w) } }
        shown = to
        // Set before the next frame draws the new one: it comes in from the side, not first in place.
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            strip.snapTo(from + dir * w)
            strip.animateTo(0f, SLIDE, v)
            leaving = null
        }
    }
    val swipe = remember {
        object : Swipe {
            override fun drag(dx: Float) {
                // A swipe while one slides: it takes the strip as it is.
                leaving = null
                // Past the first or the last, it gives only a little.
                val none = if (dx > 0) near.first == null else near.second == null
                scope.launch(start = CoroutineStart.UNDISPATCHED) { strip.snapTo(if (none) dx / 3 else dx) }
            }
            override fun end(dx: Float, vx: Float) {
                val far = abs(dx) > min(80 * density, width / 5f)
                val flung = abs(vx) > 300 * density && sign(vx) == sign(dx) && abs(dx) > 10 * density
                if (dx != 0f && (far || flung)) go(if (dx > 0) -1 else 1, vx) else back(vx)
            }
        }
    }
    var source by remember(file.path) { mutableStateOf(false) }
    BackHandler(enabled = marks.on) { marks.back() }
    val coming = (kind == PreviewKind.Image || kind == PreviewKind.Video && FileData.keptPicture("$fullId#still", 0) != null) && shownLoaded is FileLoad.Loading
    val haze = remember { HazeState() }

    // The system bars' icons light over a dark viewer, as the app's again once it closes (it is in the app's own window).
    val view = androidx.compose.ui.platform.LocalView.current
    val appLight = !C.dark
    val light = !dark && appLight
    DisposableEffect(light, closing) {
        val window = view.context.activity()?.window
        val controller = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        val want = if (closing) appLight else light
        controller?.apply { isAppearanceLightStatusBars = want; isAppearanceLightNavigationBars = want }
        onDispose { controller?.apply { isAppearanceLightStatusBars = appLight; isAppearanceLightNavigationBars = appLight } }
    }
    // A video's still, as the chat shows it: what flies from the thumbnail, and stands in until the player's first frame.
    val still = if (known.kind == PreviewKind.Video) remember(file.path) { FileViewers.thumbs[FileViewers.id(station, key, file.path)]?.picture?.invoke() ?: FileData.keptPicture("$fullId#still", 0) } else null
    val videoZoom = remember(file.path) { ZoomState(density) }
    LaunchedEffect(videoZoom, still) {
        val sent = if (file.width != null && file.height != null && file.width > 0 && file.height > 0) IntSize(file.width.toInt(), file.height.toInt()) else null
        if (videoZoom.natural == null) (still?.let { IntSize(it.width, it.height) } ?: sent)?.let { videoZoom.fitNatural(it) }
    }
    flight.target = when (known.kind) {
        PreviewKind.Image -> ({ zoom.rect() })
        PreviewKind.Video -> ({ videoZoom.rect() })
        else -> ({ null })
    }
    val ground = when { dark -> Color.Black; kind == PreviewKind.Pdf -> lerp(C.bg, C.ink, 0.05f); else -> chatInk().canvas }
    Box(Modifier.fillMaxSize().onSizeChanged { videoZoom.fitBox(it); width = it.width }.drawBehind { drawRect(ground, alpha = flight.chrome) }) {
        Box(Modifier.fillMaxSize().hazeSource(haze)) {
            leaving?.let { l -> Canvas(Modifier.fillMaxSize()) { l.draw(this, strip.value) } }
            // The ones beside it, out of sight until a swipe brings them in (while one goes, it is drawn in their place).
            if (known.kind == PreviewKind.Image && !marks.on && leaving == null) {
                val w = width + gap
                before?.let { key(it.file.path) { Beside(station, it, chatLongest) { strip.value - w } } }
                after?.let { key(it.file.path) { Beside(station, it, chatLongest) { strip.value + w } } }
            }
            when {
                // One of its own for each image: what it remembers of one (its picture) is not the next one's.
                known.kind == PreviewKind.Image -> key(file.path) {
                    ImageStage(station, key, file, bytes, zoom, marks, Modifier.viewerFlying(flight), onTap = ::toggle,
                        swipe = if (marks.on) null else swipe, slide = { strip.value })
                }
                known.kind == PreviewKind.Video && still != null && (bytes == null || shownLoaded !is FileLoad.Ready) -> Poster(still, videoZoom, Modifier.viewerFlying(flight))
                shownLoaded is FileLoad.Loading -> Note { if (progress != null) Progress(progress, file.size, dark = false) else Waiting() }
                shownLoaded is FileLoad.Failed -> Note { Text(t("android-chat.file.loadFailed", "error" to shownLoaded.message), fontSize = 15.sp, color = C.muted, textAlign = TextAlign.Center) }
                bytes == null -> {}
                kind == PreviewKind.Video -> OnDisk(fullId, file.name, bytes, waiting = { if (still != null) Poster(still, videoZoom, Modifier.viewerFlying(flight)) else Note { Waiting() } }) {
                    VideoViewer(it, file.name, awake, { wake(TAP_REST_MS) }, ::toggle, darkGlass(haze, RoundedCornerShape(16.dp)), videoZoom, Modifier.viewerFlying(flight), still, chrome = { flight.chrome },
                        startAtUs = FileViewers.frames[FileViewers.id(station, key, file.path)]?.atUs ?: 0L, frameOut = { flight.frame = it })
                }
                kind == PreviewKind.Audio -> OnDisk(fullId, file.name, bytes) { Note { AudioViewer(it, file.name) } }
                kind == PreviewKind.Pdf -> OnDisk(fullId, file.name, bytes) { PdfViewer(it, ::toggle) }
                kind != null -> TextViewer(bytes, kind, known.language, file.name, source, ::toggle)
                else -> Note {
                    Text(t("android-chat.file.cantPreview"), fontSize = 15.sp, color = C.muted)
                    Row(
                        Modifier.clip(RoundedCornerShape(12.dp)).background(C.chip).clickable { scope.launch { app.toast = if (download(context, file.name, bytes)) t("android-chat.file.saved") else t("android-chat.file.saveFailed") } }
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) { IconIn(Icons.Download, 16.dp, C.ink); Text(t("android-chat.file.download"), fontSize = 15.sp, color = C.ink) }
                }
            }
        }
        // A page's taps are its own (they do not reach here to bring the bar back): over one, the bar stays.
        val show = awake || coming || marks.on || kind == PreviewKind.Html && !source
        // Over the image's sides, in the middle: to the one before and after.
        if (images.size > 1 && at >= 0 && !marks.on) {
            listOf(before to Alignment.CenterStart, after to Alignment.CenterEnd).forEachIndexed { i, (to, side) ->
                if (to != null) Box(
                    Modifier.align(side).padding(horizontal = 8.dp).graphicsLayer { alpha = flight.chrome }.alpha(if (show) 1f else 0f).size(36.dp).shadow(1.dp, CircleShape)
                        .clip(CircleShape).background(DarkCanvas.copy(alpha = 0.8f)).clickable(enabled = show) { go(if (i == 0) -1 else 1) },
                    contentAlignment = Alignment.Center,
                ) { IconIn(if (i == 0) Icons.ChevronLeft else Icons.ChevronRight, 22.dp, DarkText) }
            }
        }
        // The bar at the top: the file's name, its own tools, how far it has come, download and close.
        val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding().coerceAtLeast(8.dp)
        BoxWithConstraints(Modifier.fillMaxWidth().padding(top = top).graphicsLayer { alpha = flight.chrome }, contentAlignment = Alignment.TopCenter) {
            var widest by remember { mutableIntStateOf(0) }
            val shape = RoundedCornerShape(14.dp)
            val tint = if (dark) DarkMuted else C.muted
            Row(
                Modifier.widthIn(min = with(LocalDensity.current) { widest.toDp() }, max = maxWidth - 16.dp).width(IntrinsicSize.Max)
                    .onSizeChanged { if (it.width > widest) widest = it.width }
                    .alpha(if (show) 1f else 0f)
                    .then(if (dark) darkGlass(haze, shape) else pageGlass(haze, shape))
                    .height(44.dp).padding(start = 12.dp, end = 2.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(file.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (dark) DarkText else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(end = 12.dp))
                if (coming && progress != null) Progress(progress, file.size, dark = true, inBar = true)
                when {
                    marks.on -> MarksActions(marks, canDraft = true,
                        onDownload = { if (bytes != null) scope.launch { finish(marks, bytes, zoom, file) { p, _ -> app.toast = if (marks.save(context, p.name)) t("android-chat.file.saved") else t("android-chat.file.saveFailed") } } },
                        onDraft = {
                            // Into the draft of the chat whose agent keeps the image: its page takes it (Preview.kt → TakeDraftOffers).
                            if (bytes != null) scope.launch {
                                finish(marks, bytes, zoom, file) { p, quotes -> DraftOffers.waiting += MarkOffer(station, key, listOf(p), quotes); marks.leave(); onClose() }
                            }
                        })
                    // While the whole of it comes the bar says how far it has; its tools come with it.
                    coming -> {}
                    known.kind == PreviewKind.Image -> {
                        PictureButton(Icons.Minus, t("android-chat.file.zoomOut"), enabled = zoom.scale > zoom.minScale + 1e-4f, tint = tint) { zoom.zoomTo(zoom.scale / 1.25f, scope = scope) }
                        Box(Modifier.height(32.dp).widthIn(min = 52.dp).clip(RoundedCornerShape(12.dp)).clickable { zoom.reset(scope) }, contentAlignment = Alignment.Center) {
                            Text("${(zoom.scale * 100).roundToInt()}%", fontSize = 13.sp, color = tint)
                        }
                        PictureButton(Icons.Plus, t("android-chat.file.zoomIn"), enabled = zoom.scale < fail.still.android.ui.MAX_SCALE - 1e-4f, tint = tint) { zoom.zoomTo(zoom.scale * 1.25f, scope = scope) }
                        if (bytes != null) PictureButton(Icons.Edit, t("android-chat.file.mark"), tint = tint) { marks.start() }
                    }
                    kind == PreviewKind.Markdown || kind == PreviewKind.Csv || kind == PreviewKind.Html ->
                        Seg(listOf(t("android-chat.file.tab.preview"), t("android-chat.file.tab.source")), if (source) 1 else 0, { source = it == 1 }, Modifier.width(120.dp), height = 30.dp, fill = true, radius = 15.dp, inset = 2.dp)
                }
                if (!marks.on && !coming) Box(Modifier.alpha(if (bytes != null) 1f else 0f)) {
                    PictureButton(Icons.Download, t("android-chat.file.download"), enabled = bytes != null, tint = tint) {
                        if (bytes != null) scope.launch { app.toast = if (download(context, file.name, bytes)) t("android-chat.file.saved") else t("android-chat.file.saveFailed") }
                    }
                }
                PictureButton(Icons.Close, t("common.close"), tint = tint, onClick = onClose)
            }
        }
        if (marks.on) Box(Modifier.align(Alignment.BottomCenter).padding(WindowInsets.navigationBars.asPaddingValues()).padding(bottom = 8.dp)) {
            MarksFoot(marks, haze, darkGlass(haze, RoundedCornerShape(14.dp)))
        }
    }
}

/** The marked image made and handed on (`use`), with a quote per numbered mark; what went wrong said in the bar. */
private suspend fun finish(marks: ImageMarks, bytes: ByteArray, zoom: ZoomState, file: Attachment, use: suspend (Picked, List<OfferQuote>) -> Unit) {
    val natural = zoom.natural ?: return
    marks.busy = true
    marks.error = null
    try {
        marks.putDown()
        val all = marks.all()
        val made = marks.render(bytes, natural) ?: throw IllegalStateException(t("android-chat.file.drawFailed"))
        val stamp = java.text.SimpleDateFormat("HHmmss", java.util.Locale.ROOT).format(java.util.Date())
        val name = t("android-chat.file.marked.name", "name" to file.name.substringBeforeLast('.'), "stamp" to stamp)
        use(Picked(name, made.bytes, made.width, made.height, made.preview, made.size), marks.quotes(all, name, file.name, natural))
    } catch (e: Exception) {
        marks.error = e.message ?: t("android-chat.file.drawFailed")
    } finally {
        marks.busy = false
    }
}

/** Frosted glass over a picture. */
@Composable
private fun darkGlass(haze: HazeState, shape: Shape): Modifier = Modifier.clip(shape).hazeEffect(haze) {
    backgroundColor = Color.Black
    tints = listOf(HazeTint(Color(0xFF121214).copy(alpha = 0.62f)))
    blurRadius = 24.dp
    noiseFactor = 0f
}

/** The same over a page of the theme's colours (a document), as the composer's. */
@Composable
private fun pageGlass(haze: HazeState, shape: Shape): Modifier {
    // Over the viewer's canvas (web FilePreview.css.ts: --canvas), white in the light.
    val bg = chatInk().canvas
    val tint = if (C.dark) C.surface2 else C.surface
    return Modifier.shadow(6.dp, shape, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f)).clip(shape).hazeEffect(haze) {
        backgroundColor = bg
        tints = listOf(HazeTint(tint.copy(alpha = 0.72f)))
        blurRadius = 20.dp
        noiseFactor = 0f
    }
}

@Composable
private fun Note(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) { content() }
}

@Composable
private fun Waiting() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { Spinner(16.dp); Text(t("android-chat.file.loading"), fontSize = 15.sp, color = C.muted) }
}

/** How much of a file has come, out of its size (the station's, else the one sent with it). */
@Composable
private fun Progress(got: Pair<Long, Long?>, sent: Long, dark: Boolean, inBar: Boolean = false) {
    val total = got.second ?: sent.takeIf { it > 0 }
    val part = if (total != null && total > 0) min(1f, got.first.toFloat() / total) else null
    val text = if (dark) DarkText else C.ink
    val muted = if (dark) DarkMuted else C.muted
    val words = buildAnnotatedString {
        if (total != null) {
            // The size so far in bold, where the sentence has it.
            val (before, after) = t("android-chat.file.loading.size").split("{size}", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
            if (!inBar) append(before)
            withStyle(SpanStyle(color = text, fontWeight = FontWeight.SemiBold)) { append(fileSize(got.first)) }
            append(" / ${fileSize(total)}")
            if (!inBar) append(after)
        } else append(t("android-chat.file.loading"))
    }
    val trackColor = (if (dark) Color.White else C.ink).copy(alpha = 0.12f)
    val barColor = if (dark) DarkText else C.accent
    val track = @Composable { w: Dp? ->
        Canvas((if (w != null) Modifier.width(w) else Modifier.fillMaxWidth()).height(4.dp)) {
            val r = androidx.compose.ui.geometry.CornerRadius(size.height / 2)
            drawRoundRect(trackColor, cornerRadius = r)
            drawRoundRect(barColor, size = androidx.compose.ui.geometry.Size(size.width * (part ?: 0.4f), size.height), cornerRadius = r)
        }
    }
    if (inBar) Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(words, fontSize = 13.sp, color = muted, maxLines = 1)
        track(48.dp)
    } else Column(
        Modifier.width(220.dp).clip(RoundedCornerShape(14.dp)).background(if (C.dark) C.surface2 else C.surface).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(words, fontSize = 15.sp, color = muted, textAlign = TextAlign.Center)
        track(null)
    }
}

/** Text, when its first bytes decode as UTF-8 with no NULs. */
private fun looksLikeText(bytes: ByteArray): Boolean {
    val n = min(bytes.size, 8192)
    for (i in 0 until n) if (bytes[i] == 0.toByte()) return false
    // The cut may split a character; its last bytes are left out.
    val head = if (bytes.size > 8192) bytes.copyOf(8188) else bytes.copyOf(n)
    return try {
        java.nio.charset.StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(head)); true
    } catch (_: java.nio.charset.CharacterCodingException) {
        false
    }
}

/** Shows `content` once the file is on the phone's disk (the players and PdfRenderer read files). */
@Composable
private fun OnDisk(id: String, name: String, bytes: ByteArray, waiting: @Composable () -> Unit = { Note { Waiting() } }, content: @Composable (File) -> Unit) {
    val context = LocalContext.current
    val file by produceState<File?>(null, id) { value = FileData.onDisk(context, id, name, bytes) }
    file?.let { content(it) } ?: waiting()
}

/** A video's still where the player will show it (`zoom`), until it can. */
@Composable
private fun Poster(still: ImageBitmap, zoom: ZoomState, stage: Modifier) {
    Canvas(Modifier.fillMaxSize().then(stage)) { drawFitted(still, zoom) }
}

internal fun androidx.compose.ui.graphics.drawscope.DrawScope.drawFitted(p: ImageBitmap, zoom: ZoomState) {
    val r = zoom.rect() ?: return
    withTransform({ translate(r.left, r.top); scale(r.width / p.width, r.height / p.height, Offset.Zero) }) {
        drawImage(p, filterQuality = FilterQuality.Medium)
    }
}

// ── images ─────────────────────────────────────────────────────────────

/** Images stepped through slide this far apart, on this spring (web: FilePreview.tsx GAP, SLIDE). */
private val SLIDE_GAP = 24.dp
private val SLIDE = spring<Float>(dampingRatio = 1f, stiffness = 400f)

/** The image going as the next comes: its `picture` where it was (`at`), moving out to the side away from `dir`. */
private class Leaving(val picture: ImageBitmap, val at: Rect, val dir: Int, val width: Float) {
    fun draw(scope: androidx.compose.ui.graphics.drawscope.DrawScope, x: Float) = with(scope) {
        withTransform({ translate(at.left + x - dir * width, at.top); scale(at.width / picture.width, at.height / picture.height, Offset.Zero) }) {
            drawImage(picture, filterQuality = FilterQuality.Medium)
        }
    }
}

/** An image beside the one shown, fitted as the stage will fit it, drawn `x()` px aside. */
@Composable
private fun Beside(station: String, s: Shown, thumbLongest: Int, x: () -> Float) {
    val app = LocalApp.current
    val density = LocalDensity.current.density
    val id = FileData.id(station, s.key, s.file, thumb = false)
    val picture by produceState(leavingPicture(station, s, thumbLongest), id) {
        FileData.keptPicture(id, 4096)?.let { value = it; return@produceState }
        val bytes = try { FileData.fetch(app, station, s.key, s.file, thumb = false).await() } catch (e: CoreException) { return@produceState }
        FileData.picture(id, bytes, 4096)?.let { value = it }
    }
    val p = picture ?: return
    val zoom = remember { ZoomState(density) }
    val sent = s.file.width?.takeIf { it > 0 }?.let { w -> s.file.height?.takeIf { it > 0 }?.let { h -> IntSize(w.toInt(), h.toInt()) } }
    zoom.fitNatural(sent ?: IntSize(p.width, p.height))
    Canvas(Modifier.fillMaxSize().onSizeChanged { zoom.fitBox(it) }.graphicsLayer { translationX = x() }) {
        val r = zoom.rect() ?: return@Canvas
        withTransform({ translate(r.left, r.top); scale(r.width / p.width, r.height / p.height, Offset.Zero) }) {
            drawImage(p, filterQuality = FilterQuality.Medium)
        }
    }
}

/** What the stage drew of `s`: the whole of it if it came, else the chat's thumbnail. */
private fun leavingPicture(station: String, s: Shown, thumbLongest: Int): ImageBitmap? =
    FileData.keptPicture(FileData.id(station, s.key, s.file, thumb = false), 4096) ?: FileData.keptPicture(FileData.id(station, s.key, s.file, thumb = true), thumbLongest)

/**
 * An image fitted to the screen, to pinch, pan and double-tap; fitted, one finger sideways is `swipe`'s (drawn `slide` px aside). Until the
 * whole of it comes (`bytes`), its thumbnail (as the chat showed it) stands in its place. Marked, the marks are drawn
 * over it, moved and zoomed with it.
 */
@Composable
private fun ImageStage(station: String, key: String, file: Attachment, bytes: ByteArray?, zoom: ZoomState, marks: ImageMarks, stage: Modifier, onTap: () -> Unit, swipe: Swipe?, slide: () -> Float) {
    val scope = rememberCoroutineScope()
    val thumbId = FileData.id(station, key, file, thumb = true)
    val chatLongest = with(LocalDensity.current) { 360.dp.roundToPx() }
    val thumb = remember(thumbId) { FileData.keptPicture(thumbId, chatLongest) }
    val fullId = FileData.id(station, key, file, thumb = false)
    var failed by remember(fullId) { mutableStateOf(false) }
    val full by produceState<ImageBitmap?>(FileData.keptPicture(fullId, 4096), fullId, bytes) {
        if (value != null || bytes == null) return@produceState
        value = FileData.picture(fullId, bytes, 4096)
        if (value == null) failed = true
    }
    LaunchedEffect(fullId, bytes, thumb) {
        val sent = if (file.width != null && file.height != null && file.width > 0 && file.height > 0) IntSize(file.width.toInt(), file.height.toInt()) else null
        val read = bytes?.let { withContext(Dispatchers.Default) {
            val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(it, 0, it.size, o)
            if (o.outWidth > 0) IntSize(o.outWidth, o.outHeight) else null
        } }
        // A thumbnail's own size is not the image's: it only stands in the image's place.
        zoom.fitNatural(read ?: sent ?: thumb?.let { IntSize(it.width, it.height) })
    }
    if (failed && file.name.lowercase().endsWith(".svg") && bytes != null) {
        // Not a bitmap: drawn by a page of its own.
        HtmlPage("<!doctype html><meta name=viewport content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;display:grid;place-items:center;min-height:100vh;background:#000\">" +
            "<img style=\"max-width:100%;max-height:100vh\" src=\"data:image/svg+xml;base64,${android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)}\">")
        return
    }
    if (failed) { Note { Text(t("android-chat.file.image.failed"), fontSize = 15.sp, color = DarkMuted) }; return }
    val picture = full ?: thumb
    // Words written under where the keyboard comes up: the image goes up with them, above it.
    val ime = WindowInsets.keyboard.getBottom(LocalDensity.current)
    val gap = with(LocalDensity.current) { 24.dp.toPx() }
    val below = marks.writingBottom()?.let { it + gap - (zoom.box.height - ime) } ?: 0f
    val lift by animateFloatAsState(if (ime > 0 && below > 0) below else 0f, label = "lift")
    Box(Modifier.fillMaxSize().then(stage).graphicsLayer { translationY = -lift }.zoomable(zoom, scope, onTap, swipe, strokes = if (marks.on) marks else null)) {
        // Moved by the strip in drawing only: the gestures measure the finger on the stage, which stays put.
        Canvas(Modifier.fillMaxSize().graphicsLayer { translationX = slide() }) {
            val r = zoom.rect() ?: return@Canvas
            val p = picture ?: return@Canvas
            withTransform({ translate(r.left, r.top); scale(r.width / p.width, r.height / p.height, Offset.Zero) }) {
                drawImage(p, filterQuality = if (zoom.k > 2) FilterQuality.None else FilterQuality.Medium)
            }
            if (marks.on) drawIntoCanvas { c ->
                val n = c.nativeCanvas
                n.save()
                n.translate(r.left, r.top)
                n.scale(zoom.k, zoom.k)
                drawMarks(n, marks.drawn())
                marks.drawPicked(n, zoom.k)
                n.restore()
            }
        }
        if (marks.on) { marks.Pins(); marks.WritingField() }
    }
}

// ── PDFs ───────────────────────────────────────────────────────────────

/** An open PDF: its renderer (one page at a time, under `lock`), its pages' sizes; `closed` once let go. */
private class PdfDoc(val renderer: PdfRenderer, val sizes: List<IntSize>, val lock: Mutex) { var closed = false }

/** Opens `file` (on an IO thread); whatever was opened is closed again if it fails on the way. */
private fun openPdf(file: File): PdfDoc {
    val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    // The renderer owns the descriptor once it is made (its close closes it).
    val r = try { PdfRenderer(fd) } catch (e: Throwable) { fd.close(); throw e }
    return try {
        PdfDoc(r, (0 until r.pageCount).map { i -> r.openPage(i).use { IntSize(it.width, it.height) } }, Mutex())
    } catch (e: Throwable) {
        r.close()
        throw e
    }
}

/** Pages drawn by the system's PdfRenderer, each as it scrolls near, as wide as the screen allows. */
@Composable
private fun PdfViewer(file: File, onTap: () -> Unit) {
    val app = LocalApp.current
    val doc by produceState<Result<PdfDoc>?>(null, file) {
        var made: PdfDoc? = null
        try {
            value = withContext(Dispatchers.IO) { runCatching { openPdf(file).also { made = it } } }
            awaitCancellation()
        } finally {
            // Gone (or gone while it opened): closed off the main thread, once no page is being drawn.
            made?.let { m -> app.scope.launch(Dispatchers.IO) { m.lock.withLock { m.closed = true; m.renderer.close() } } }
        }
    }
    val d = doc
    when {
        d == null -> Note { Spinner(16.dp) }
        d.isFailure -> Note { Text(t("android-chat.file.pdf.failed", "error" to (d.exceptionOrNull()?.message ?: "")), fontSize = 15.sp, color = C.muted) }
        else -> {
            val pdf = d.getOrThrow()
            LazyColumn(
                Modifier.fillMaxSize().clickable(interactionSource = null, indication = null, onClick = onTap),
                contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 60.dp + WindowInsets.statusBars.asPaddingValues().calculateTopPadding(), bottom = 12.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                itemsIndexed(pdf.sizes) { i, size ->
                    var width by remember { mutableIntStateOf(0) }
                    val page by produceState<ImageBitmap?>(null, width) {
                        if (width <= 0) return@produceState
                        value = withContext(Dispatchers.IO) {
                            pdf.lock.withLock {
                                if (pdf.closed) return@withLock null
                                pdf.renderer.openPage(i).use { p ->
                                    val w = min(width, 2400)
                                    val h = (w.toFloat() * size.height / size.width).roundToInt().coerceAtLeast(1)
                                    val bmp = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
                                    bmp.eraseColor(android.graphics.Color.WHITE)
                                    p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                    bmp.asImageBitmap()
                                }
                            }
                        }
                    }
                    Box(Modifier.fillMaxWidth().aspectRatio(size.width.toFloat() / max(1, size.height)).shadow(2.dp).background(Color.White).onSizeChanged { width = it.width }) {
                        page?.let { Image(it, t("android-chat.file.pdf.page", "n" to i + 1), Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds) }
                    }
                }
            }
        }
    }
}

// ── text ───────────────────────────────────────────────────────────────

/** Markdown rendered, CSV a table, HTML a page (each, or its source); code highlighted; text as it is. */
@Composable
private fun TextViewer(bytes: ByteArray, kind: PreviewKind, language: String?, name: String, source: Boolean, onTap: () -> Unit) {
    val cut = bytes.size > SHOW_LIMIT
    val text by produceState<String?>(null, bytes) { value = withContext(Dispatchers.Default) { String(bytes, 0, min(bytes.size, SHOW_LIMIT), Charsets.UTF_8) } }
    val t = text ?: return Note { Waiting() }
    if (kind == PreviewKind.Html && !source) {
        // Its scripts run, in a page of its own that reaches nothing of the app's.
        val html = if (Regex("<!doctype|<html[\\s>]", RegexOption.IGNORE_CASE).containsMatchIn(t.take(2048))) t
        else "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><body style=\"margin:0;padding:16px;font-family:system-ui,sans-serif\">$t"
        Box(Modifier.fillMaxSize().padding(top = 60.dp + WindowInsets.statusBars.asPaddingValues().calculateTopPadding())) { HtmlPage(html) }
        return
    }
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    if (kind == PreviewKind.Csv && !source) { CsvTable(t, name.lowercase().endsWith(".tsv"), cut, top, bottom, onTap); return }
    val tap = Modifier.clickable(interactionSource = null, indication = null, onClick = onTap)
    Column(Modifier.fillMaxSize().then(tap).verticalScroll(rememberScrollState())) {
        if (cut) Cut(fail.still.android.ui.t("android-chat.file.cut", "size" to fileSize(SHOW_LIMIT.toLong())), top)
        when {
            kind == PreviewKind.Markdown && !source -> Markdown(t, Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 64.dp + top, bottom = 64.dp + bottom))
            else -> {
                val lang = if (kind == PreviewKind.Markdown) "markdown" else if (kind == PreviewKind.Csv) null else language
                if (lang != null && t.length <= HIGHLIGHT_LIMIT) {
                    val dark = C.dark
                    val colored = remember(t, lang, dark) { highlight(t, lang, dark) }
                    Box(Modifier.horizontalScroll(rememberScrollState()).padding(start = 32.dp, end = 32.dp, top = 80.dp + top, bottom = 64.dp + bottom)) {
                        Text(colored, style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.5.sp, lineHeight = 20.sp, color = C.ink), softWrap = false)
                    }
                } else Text(t, style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.5.sp, lineHeight = 20.6.sp, color = C.ink),
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 60.dp + top, bottom = 48.dp + bottom))
            }
        }
    }
}

@Composable
private fun Cut(words: String, top: Dp) {
    Text(words, fontSize = 13.sp, color = C.warn, modifier = Modifier.fillMaxWidth().background(C.warn.copy(alpha = 0.14f)).padding(start = 20.dp, end = 20.dp, top = 8.dp + top, bottom = 8.dp))
}

/** A page of its own in a WebView: scripts on, nothing of the phone's files or the app's reachable; links stay out. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun HtmlPage(html: String) {
    AndroidView({ ctx ->
        WebView(ctx).apply {
            setBackgroundColor(android.graphics.Color.WHITE)
            settings.javaScriptEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.domStorageEnabled = false
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = true
            }
            loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
        }
    }, Modifier.fillMaxSize(), onRelease = { it.destroy() })
}

/** Rows of a CSV (or TSV), quotes and all. */
fun parseCsv(text: String, separator: Char, limit: Int = Int.MAX_VALUE): List<List<String>> {
    val rows = ArrayList<List<String>>()
    var row = ArrayList<String>()
    val field = StringBuilder()
    var quoted = false
    var i = 0
    while (i < text.length && rows.size < limit) {
        val c = text[i]
        if (quoted) {
            if (c == '"' && text.getOrNull(i + 1) == '"') { field.append('"'); i++ }
            else if (c == '"') quoted = false
            else field.append(c)
        } else if (c == '"' && field.isEmpty()) quoted = true
        else if (c == separator) { row.add(field.toString()); field.clear() }
        else if (c == '\n' || c == '\r') {
            if (c == '\r' && text.getOrNull(i + 1) == '\n') i++
            row.add(field.toString()); rows.add(row); row = ArrayList(); field.clear()
        } else field.append(c)
        i++
    }
    if ((field.isNotEmpty() || row.isNotEmpty()) && rows.size < limit) { row.add(field.toString()); rows.add(row) }
    return rows
}

/** A table: a row number, then its columns, each as wide as what it holds (up to a limit); the head stays on top. */
@Composable
private fun CsvTable(text: String, tab: Boolean, cut: Boolean, top: Dp, bottom: Dp, onTap: () -> Unit) {
    val rows = remember(text) { parseCsv(text, if (tab) '\t' else ',', TABLE_ROWS + 1) }
    val head = rows.firstOrNull() ?: return
    val body = rows.drop(1).take(TABLE_ROWS)
    val more = rows.size - 1 > TABLE_ROWS
    val measurer = rememberTextMeasurer()
    val d = LocalDensity.current
    // As the cells' Text draws it (the theme's letter spacing included).
    val style = androidx.compose.material3.LocalTextStyle.current.merge(TextStyle(fontSize = 15.sp))
    val widths = remember(text) {
        val sample = listOf(head) + body.take(200)
        head.indices.map { j ->
            val px = sample.maxOf { r -> r.getOrNull(j)?.let { measurer.measure(it.take(80), style.copy(fontWeight = FontWeight.SemiBold), maxLines = 1).size.width } ?: 0 }
            with(d) { (px.toDp() + 32.dp).coerceIn(48.dp, 420.dp) }
        }
    }
    val number = with(d) { (measurer.measure("${body.size}", style).size.width.toDp() + 36.dp) }
    val line = C.line
    Box(Modifier.fillMaxSize().clickable(interactionSource = null, indication = null, onClick = onTap).horizontalScroll(rememberScrollState())) {
        LazyColumn(Modifier.width(number + widths.fold(0.dp) { a, b -> a + b }).fillMaxSize(), contentPadding = PaddingValues(top = 60.dp + top, bottom = 48.dp + bottom)) {
            stickyHeader {
                Row(Modifier.background(chatInk().canvas).drawBehindLine(line)) {
                    Box(Modifier.width(number))
                    head.forEachIndexed { j, h -> Cell(h, widths[j], FontWeight.SemiBold, C.ink) }
                }
            }
            itemsIndexed(body) { i, r ->
                Row {
                    Text("${i + 1}", fontSize = 15.sp, color = C.muted, textAlign = TextAlign.End, modifier = Modifier.width(number).padding(start = 20.dp, end = 16.dp, top = 8.dp, bottom = 8.dp))
                    head.indices.forEach { j -> Cell(r.getOrNull(j) ?: "", widths[j], null, C.ink) }
                }
            }
            if (more || cut) item { Cut(t("android-chat.file.cut.rows", "n" to TABLE_ROWS), 0.dp) }
        }
    }
}

/** A hairline along its bottom. */
private fun Modifier.drawBehindLine(color: Color) = drawBehind { drawLine(color, Offset(0f, size.height), Offset(size.width, size.height), 1f) }

@Composable
private fun Cell(text: String, width: Dp, weight: FontWeight?, color: Color) {
    Text(text, fontSize = 15.sp, fontWeight = weight, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(width).padding(horizontal = 16.dp, vertical = 8.dp))
}
