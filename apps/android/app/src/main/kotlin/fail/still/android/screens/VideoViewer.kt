// A video to play and to step through frame by frame (web/src/VideoViewer.tsx), for a close look at an interface's
// motion: its frames' times read from the file (MediaExtractor), so a step is to the very next frame the file has,
// whatever its frame rate. Its controls float over the picture, frosted, and fade when left alone. Audio plays in a
// small player of the same kind.
package fail.still.android.screens

import fail.still.android.ui.t
import android.app.Activity
import android.content.pm.ActivityInfo
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import fail.still.android.LocalApp
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ZoomState
import fail.still.android.ui.zoomable
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val RATES = listOf(0.1f, 0.25f, 0.5f, 1f)
/** Without the file's own frames, a step is this long (ms). */
private const val GUESSED_STEP_US = 1_000_000L / 60

/** When each frame of the file's video starts (µs, in time order), or null when it has none to read. */
private fun frameStarts(path: String): LongArray? {
    val x = MediaExtractor()
    return try {
        x.setDataSource(path)
        val track = (0 until x.trackCount).firstOrNull { x.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true } ?: return null
        x.selectTrack(track)
        val times = ArrayList<Long>()
        while (true) {
            val t = x.sampleTime
            if (t < 0) break
            times += t
            if (!x.advance()) break
        }
        times.sort()
        times.toLongArray().takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
        null
    } finally {
        x.release()
    }
}

/** The frame showing at `time` (the last to start by then). */
private fun LongArray.at(time: Long): Int {
    var lo = 0
    var hi = size - 1
    while (lo < hi) {
        val mid = (lo + hi + 1) / 2
        if (this[mid] <= time + 100) lo = mid else hi = mid - 1
    }
    return lo
}

/** Seconds as m:ss. */
private fun short(ms: Long): String = "${ms / 60000}:${(ms / 1000 % 60).toString().padStart(2, '0')}"

/**
 * The video in `file`: pinch to zoom, controls over it (`awake`: shown; `wake`: a finger on them keeps them a while
 * longer; `onTap`: a tap on the picture shows or hides them).
 */
@Composable
internal fun VideoViewer(
    file: File, name: String, awake: Boolean, wake: () -> Unit, onTap: () -> Unit, glass: Modifier,
    /** Where the picture shows (the viewer's own, known from the still before the player is ready). */
    zoomOf: ZoomState? = null,
    /** On the picture (and the still over it): the viewer's flight from the chat's thumbnail (FilePreview.kt). */
    stage: Modifier = Modifier,
    /** The still the chat shows, over the picture until the player's first frame is drawn. */
    poster: androidx.compose.ui.graphics.ImageBitmap? = null,
    /** How much of the controls shows as the viewer comes and goes. */
    chrome: () -> Float = { 1f },
    /** Where to start (µs): where it was left when closed before (the still over it is that frame). */
    startAtUs: Long = 0L,
    /** Hands over how to read the frame showing now and its time (for the viewer to close into the thumbnail with it). */
    frameOut: ((suspend () -> KeptFrame?) -> Unit)? = null,
) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current.density
    val zoom = zoomOf ?: remember { ZoomState(density) }
    var framed by remember { mutableStateOf(false) }
    val player = remember { MediaPlayer() }
    var ready by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }
    var duration by remember { mutableLongStateOf(0L) }
    // Where it is, in µs: the frame shown when paused, the player's clock while it plays.
    var time by remember { mutableLongStateOf(0L) }
    var frames by remember { mutableStateOf<LongArray?>(null) }
    var read by remember { mutableStateOf(false) }
    var rate by remember { mutableFloatStateOf(1f) }
    var turned by remember { mutableStateOf(false) }
    // The player could not play it (a file it cannot read): said over the picture, the controls idle.
    var failed by remember { mutableStateOf(false) }
    val texture = remember { mutableStateOf<TextureView?>(null) }

    DisposableEffect(file) {
        player.setOnPreparedListener { mp ->
            zoom.fitNatural(IntSize(mp.videoWidth.coerceAtLeast(1), mp.videoHeight.coerceAtLeast(1)))
            duration = mp.duration.toLong() * 1000
            // Opened again where it was left: from there; left at its end, it stays on that frame (play starts over).
            val resume = startAtUs in 1 until duration + 1
            if (resume) { time = startAtUs; mp.seekTo((startAtUs + 999) / 1000, MediaPlayer.SEEK_CLOSEST) }
            ready = true
            if (!resume || startAtUs < duration - 50_000) { mp.start(); playing = true }
        }
        player.setOnVideoSizeChangedListener { _, w, h -> if (w > 0 && h > 0) zoom.fitNatural(IntSize(w, h)) }
        // Played to the end: it rests on its last frame (and says so), as it would be left.
        player.setOnCompletionListener { playing = false; time = frames?.last() ?: duration }
        player.setOnErrorListener { _, _, _ -> ready = false; playing = false; failed = true; true }
        try {
            player.setDataSource(file.path)
            player.prepareAsync()
        } catch (_: Exception) { failed = true }
        onDispose { player.release() }
    }
    LaunchedEffect(file) {
        frames = withContext(Dispatchers.IO) { frameStarts(file.path) }
        read = true
    }
    // Playing, the time follows the player's clock.
    LaunchedEffect(playing) {
        while (playing && isActive) {
            withFrameMillis {}
            // Not once it has stopped (at its end the player's clock reads back near the start; the end is kept).
            try { if (playing) time = player.currentPosition.toLong() * 1000 } catch (_: IllegalStateException) {}
        }
    }
    // The picture where the zoom puts it.
    // The transform is by the view's own size, set again as it is laid out: turned sideways, the stage's size changes
    // before the view is laid out anew, and a transform made for the old size squashed the picture into a strip.
    LaunchedEffect(texture.value) {
        val view = texture.value ?: return@LaunchedEffect
        fun place() {
            val r = zoom.rect() ?: return
            if (view.width == 0 || view.height == 0) return
            val m = Matrix()
            m.setScale(r.width / view.width, r.height / view.height)
            m.postTranslate(r.left, r.top)
            view.setTransform(m)
        }
        val laid = android.view.View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> place() }
        view.addOnLayoutChangeListener(laid)
        try {
            snapshotFlow { zoom.rect() to zoom.box }.collect { place() }
        } finally {
            view.removeOnLayoutChangeListener(laid)
        }
    }
    LaunchedEffect(frameOut) {
        frameOut?.invoke {
            val view = texture.value
            val n = zoom.natural
            // The texture's content (not the transform the zoom puts on it) at the video's own size: the whole frame.
            if (!framed || view == null || n == null) null
            else view.getBitmap(n.width, n.height)?.let { KeptFrame(it.asImageBitmap(), time) }
        }
    }
    DisposableEffect(Unit) {
        onDispose { if (turned) context.activity()?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }

    val starts = frames
    val at = starts?.at(time) ?: -1
    fun play() {
        if (!ready) return
        if (player.isPlaying) { player.pause(); playing = false; return }
        if (starts != null) {
            // From the frame stepped to; from the start again at the end.
            val i = if (at >= starts.size - 1) 0 else at
            player.seekTo((starts[i] + 999) / 1000, MediaPlayer.SEEK_CLOSEST)
        }
        try { player.playbackParams = player.playbackParams.setSpeed(rate) } catch (_: Exception) {}
        player.start()
        playing = true
    }
    /** Paused, to the frame `to` makes of the one shown (without the file's frames, steps of a guessed 60 fps). */
    fun go(to: (Int) -> Int) {
        if (!ready) return
        if (player.isPlaying) { player.pause(); playing = false }
        val target = if (starts != null) starts[to(starts.at(time)).coerceIn(0, starts.size - 1)]
        else (to((time / GUESSED_STEP_US).toInt()).toLong() * GUESSED_STEP_US).coerceIn(0, duration)
        time = target
        player.seekTo((target + 999) / 1000, MediaPlayer.SEEK_CLOSEST)
    }
    fun seek(us: Long) = go { if (starts != null) starts.at(us) else (us / GUESSED_STEP_US).toInt() }

    // Its ground is the viewer's (black, coming in with it).
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().then(stage).zoomable(zoom, scope, onTap = onTap)) {
            AndroidView({ ctx ->
                TextureView(ctx).apply {
                    surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                        override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) { try { player.setSurface(Surface(st)) } catch (_: Exception) {} }
                        override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                        override fun onSurfaceTextureDestroyed(st: SurfaceTexture) = true
                        override fun onSurfaceTextureUpdated(st: SurfaceTexture) { if (!framed) framed = true }
                    }
                    texture.value = this
                }
            }, Modifier.fillMaxSize())
            if (!framed && poster != null) Canvas(Modifier.fillMaxSize()) { drawFitted(poster, zoom) }
        }
        if (failed) Text(t("android-chat.video.failed"), fontSize = 14.sp, color = Color.White.copy(alpha = 0.6f), modifier = Modifier.align(Alignment.Center))
        // The controls: where it is, the steps and play, which frame, the speed, a frame saved, turned sideways.
        Column(
            Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 8.dp, vertical = 8.dp)
                .fillMaxWidth().graphicsLayer { alpha = chrome() }.alpha(if (awake) 1f else 0f).then(glass).pointerInput(Unit) { detectTapGestures(onPress = { wake() }) }
                .padding(start = 4.dp, end = 4.dp, top = 2.dp, bottom = 4.dp),
        ) {
            val end = if (starts != null) starts.last() + (if (starts.size > 1) starts.last() - starts[starts.size - 2] else 0) else duration
            val start = starts?.first() ?: 0L
            val now = if (starts != null && at >= 0) starts[at] else time
            Timeline(start, end, now, dark = true) { seek(it); wake() }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    PictureButton(Icons.ChevronLeft, t("android-chat.video.prev")) { go { it - 1 }; wake() }
                    PictureButton(if (playing) Icons.Pause else Icons.Play, if (playing) t("android-chat.video.pause") else t("android-chat.video.play")) { play(); wake() }
                    PictureButton(Icons.ChevronRight, t("android-chat.video.next")) { go { it + 1 }; wake() }
                }
                Box(Modifier.weight(1f)) {
                    if (starts != null) Text(buildAnnotatedString {
                        // Which frame in bold, where the sentence has it.
                        val (before, after) = t("android-chat.video.frames", "n" to starts.size).split("{at}", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
                        withStyle(SpanStyle(color = Color.White.copy(alpha = 0.6f))) { append(before) }
                        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = Color(0xFFF4F4F5))) { append("${at + 1}") }
                        withStyle(SpanStyle(color = Color.White.copy(alpha = 0.6f))) { append(after) }
                    }, fontFamily = FontFamily.Monospace, fontSize = 12.sp, maxLines = 1)
                    else if (!read) Text(t("android-chat.video.reading"), fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f), maxLines = 1)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Box(
                        Modifier.height(28.dp).widthIn(min = 46.dp).clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = 0.1f)).clickable {
                            rate = RATES[(RATES.indexOf(rate) + RATES.size - 1) % RATES.size]
                            if (ready && player.isPlaying) try { player.playbackParams = player.playbackParams.setSpeed(rate) } catch (_: Exception) {}
                            wake()
                        }.padding(horizontal = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        val r = if (rate == 1f) "1" else rate.toString().trimEnd('0')
                        Text("$r×", fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFF4F4F5))
                    }
                    PictureButton(Icons.Camera, t("android-chat.video.saveFrame"), enabled = !playing && ready) {
                        scope.launch {
                            val png = withContext(Dispatchers.IO) {
                                val r = MediaMetadataRetriever()
                                try {
                                    r.setDataSource(file.path)
                                    r.getFrameAtTime(now, MediaMetadataRetriever.OPTION_CLOSEST)?.let { b -> ByteArrayOutputStream().also { b.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }.toByteArray() }
                                } catch (_: Exception) { null } finally { r.release() }
                            }
                            val saved = png != null && download(context, "${name.substringBeforeLast('.')}-${at + 1}.png", png, "image/png")
                            app.toast = if (saved) t("android-chat.file.saved") else t("android-chat.video.saveFrame.failed")
                        }
                    }
                    PictureButton(Icons.Landscape, if (turned) t("android-chat.video.landscape.exit") else t("android-chat.video.landscape"), pressed = turned) {
                        val activity = context.activity()
                        turned = !turned
                        activity?.requestedOrientation = if (turned) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                        wake()
                    }
                }
            }
        }
    }
}

/** Where in the media it is (µs), to tap or drag to a place: a thin track, what has played, a round head. */
@Composable
private fun Timeline(start: Long, end: Long, now: Long, dark: Boolean, onSeek: (Long) -> Unit) {
    val span = (end - start).coerceAtLeast(1)
    var width by remember { mutableIntStateOf(1) }
    fun at(x: Float) = start + ((x / width).coerceIn(0f, 1f) * span).toLong()
    val track = if (dark) Color.White.copy(alpha = 0.2f) else C.ink.copy(alpha = 0.12f)
    val played = if (dark) Color(0xFFF4F4F5) else C.accent
    Canvas(
        Modifier.fillMaxWidth().padding(horizontal = 6.dp).height(22.dp)
            .pointerInput(start, end) { detectTapGestures { onSeek(at(it.x)) } }
            .pointerInput(start, end) { detectDragGestures(onDragStart = { onSeek(at(it.x)) }) { change, _ -> onSeek(at(change.position.x)) } },
    ) {
        width = size.width.roundToInt().coerceAtLeast(1)
        val part = ((now - start).toFloat() / span).coerceIn(0f, 1f)
        val h = 4.dp.toPx()
        val y = size.height / 2 - h / 2
        drawRoundRect(track, Offset(0f, y), Size(size.width, h), CornerRadius(h / 2))
        drawRoundRect(played, Offset(0f, y), Size(size.width * part, h), CornerRadius(h / 2))
        drawCircle(played, 6.dp.toPx(), Offset(size.width * part, size.height / 2))
    }
}

/** An audio file: its name, and a player (play, where it is, how long) in the page's colours. */
@Composable
fun AudioViewer(file: File, name: String) {
    val player = remember { MediaPlayer() }
    var ready by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }
    var duration by remember { mutableLongStateOf(0L) }
    var time by remember { mutableLongStateOf(0L) }
    var failed by remember { mutableStateOf(false) }
    DisposableEffect(file) {
        player.setOnPreparedListener { mp -> duration = mp.duration.toLong(); ready = true; mp.start(); playing = true }
        player.setOnCompletionListener { playing = false }
        player.setOnErrorListener { _, _, _ -> ready = false; playing = false; failed = true; true }
        try { player.setDataSource(file.path); player.prepareAsync() } catch (_: Exception) { failed = true }
        onDispose { player.release() }
    }
    LaunchedEffect(playing) {
        while (playing && isActive) {
            withFrameMillis {}
            try { time = player.currentPosition.toLong() } catch (_: IllegalStateException) {}
        }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).widthIn(max = 480.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(name, fontSize = 15.sp, color = C.muted, maxLines = 1)
        Row(
            Modifier.fillMaxWidth().heightIn(min = 54.dp).clip(RoundedCornerShape(27.dp)).background(C.chip).padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(Modifier.size(38.dp).clip(CircleShape).background(C.ink).clickable(enabled = ready) {
                if (player.isPlaying) { player.pause(); playing = false } else { player.start(); playing = true }
            }, contentAlignment = Alignment.Center) { IconIn(if (playing) Icons.Pause else Icons.Play, 16.dp, C.bg) }
            Box(Modifier.weight(1f)) { Timeline(0, duration * 1000, time * 1000, dark = false) { if (ready) { player.seekTo((it / 1000).toInt()); time = it / 1000 } } }
            Text(if (failed) t("android-chat.video.playFailed") else "${short(time)} / ${short(duration)}", fontSize = 12.sp, color = C.muted, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(end = 10.dp))
        }
    }
}

/**
 * The activity a context belongs to. The viewers sit in a Dialog, whose context wraps the activity's (a theme wrapper):
 * `context as? Activity` is null there, and the landscape button did nothing.
 */
internal tailrec fun android.content.Context.activity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.activity()
    else -> null
}
