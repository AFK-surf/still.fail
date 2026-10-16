// A video or a song of a drive, played as it streams through the core (DriveSource; media3's ExoPlayer): nothing is
// fetched whole first, a seek far ahead is one more ranged read; what was played is kept (DriveCache's played) and
// plays again from the phone. Dark, as the chat's viewer of pictures is; its controls
// float over the picture, frosted, and fade when left alone (a tap brings them back): where it is and how much is
// buffered, play, the next in the folder, the speed, the subtitle beside it (E01.srt for E01.mp4), fit or fill, and
// sideways (landscape, the system bars away). A double tap on the left or right third jumps 15 s, in the middle it
// pauses or plays. Where it was left is kept on this device (drivePlace) and played on from next time.
// media3's DataSource and source classes are marked unstable (UnstableApi): their API may change between releases.
@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package fail.still.android.drive

import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.TextureView
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SingleSampleMediaSource
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.text.TextRenderer
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.DriveEntry
import fail.still.android.data.DriveFolder
import fail.still.android.data.Topics
import fail.still.android.data.decode
import fail.still.android.data.t
import fail.still.android.screens.PickRow
import fail.still.android.screens.Spinner
import fail.still.android.screens.activity
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.android.ui.C as Palette
import fail.still.core.CoreException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import androidx.media3.common.C as Media

private const val TAG = "drive-player"

/** Dark whatever the theme, as a viewer of pictures: its text, what is quieter. */
private val Ink = Color(0xFFF4F4F5)
private val Muted = Color.White.copy(alpha = 0.6f)

/** The speeds offered, slowest first. */
private val SPEEDS = listOf(1f, 1.25f, 1.5f, 2f, 0.5f, 0.75f)
/** What a double tap on a side jumps. */
private const val NUDGE_MS = 15_000L
/** The controls fade after this long left alone while it plays. */
private const val REST_MS = 2500L

/** The folder a file is in as last read (held on the device): its entries, for the playlist and the subtitle. */
internal suspend fun folderOf(app: AppState, station: String, root: String, dir: String): List<DriveEntry> {
    val got = withTimeoutOrNull(5000) { app.core.topic(Topics.drive(station, root, dir)).first { it.value != null || it.error != null } }
    return got?.value?.let { runCatching { decode(DriveFolder.serializer(), it).entries }.getOrNull() }.orEmpty()
}

/** What is playing, in the terms a person cares about. */
private enum class Phase { Opening, Buffering, Playing, Paused, Ended, Failed }

/** The video or song `path` of `root` on `station`, played. */
// SingleSampleMediaSource: the one way to side-load a subtitle that may fail without stopping the film.
@Suppress("DEPRECATION")
@Composable
fun PlayerScreen(station: String, root: String, path: String) {
    val app = LocalApp.current
    val context = LocalContext.current
    val dir = parentOf(path)
    val name = nameOf(path)
    val api = remember(station) { app.api(station) }
    val stats = remember(path) { StreamStats() }
    val player = remember(path) { newPlayer(context) }
    val haze = remember { HazeState() }

    var entries by remember { mutableStateOf<List<DriveEntry>>(emptyList()) }
    var subtitle by remember(path) { mutableStateOf<String?>(null) }
    var subtitlesOn by remember { mutableStateOf(true) }
    var speed by remember { mutableFloatStateOf(1f) }
    var fill by remember { mutableStateOf(false) }
    var sideways by remember { mutableStateOf(false) }
    var awake by remember { mutableStateOf(true) }
    var poke by remember { mutableIntStateOf(0) }
    var note by remember { mutableStateOf<String?>(null) }
    var attempt by remember(path) { mutableIntStateOf(0) }

    var state by remember(path) { mutableIntStateOf(Player.STATE_IDLE) }
    var playing by remember(path) { mutableStateOf(false) }
    var started by remember(path) { mutableStateOf(false) }
    var failure by remember(path) { mutableStateOf<String?>(null) }
    var position by remember(path) { mutableLongStateOf(0L) }
    var duration by remember(path) { mutableLongStateOf(0L) }
    var buffered by remember(path) { mutableLongStateOf(0L) }
    var video by remember(path) { mutableStateOf<IntSize?>(null) }
    var cues by remember(path) { mutableStateOf("") }
    var openedAt by remember(path) { mutableLongStateOf(0L) }

    val phase = when {
        failure != null -> Phase.Failed
        !started -> Phase.Opening
        state == Player.STATE_ENDED -> Phase.Ended
        state == Player.STATE_BUFFERING -> Phase.Buffering
        playing -> Phase.Playing
        else -> Phase.Paused
    }
    val playable = { e: DriveEntry -> !e.dir && (e.kind == "video" || e.kind == "audio") }
    val list = remember(entries) { playlistOf(entries.filter(playable).map { it.name }) { true } }
    val next = remember(list, name) { nextIn(name, list) }

    // Everything the player needs to start: the folder (sizes, the subtitle beside it, what comes next) and where it was left.
    LaunchedEffect(path, attempt) {
        failure = null; started = false
        openedAt = android.os.SystemClock.elapsedRealtime()
        val held = folderOf(app, station, root, dir)
        entries = held
        val sizes = held.filter { !it.dir }.associate { join(dir, it.name) to it.size }
        val sub = pickSubtitle(name, held.filter { !it.dir }.map { it.name })
        subtitle = sub
        // Kept by when each changed, as the folder says: one not in it is played without being kept.
        val known = held.filter { !it.dir }.associateBy { join(dir, it.name) }
        val played = withContext(Dispatchers.IO) { DriveCache.played() }
        val upstream = DriveSource.Factory(api, root, sizes, stats)
        val factory = if (path !in known) upstream else CacheDataSource.Factory().setCache(played).setUpstreamDataSourceFactory(upstream)
            .setCacheKeyFactory { spec -> DriveUri.pathOf(spec.uri).let { p -> known[p]?.let { DriveCache.playedKey(station, root, p, it.mtime, it.size) } ?: "$station\n$root\n$p" } }
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        val sources = mutableListOf<MediaSource>(ProgressiveMediaSource.Factory(factory).createMediaSource(MediaItem.fromUri(DriveUri.of(path))))
        if (sub != null) subtitleMime(sub)?.let { mime ->
            val config = MediaItem.SubtitleConfiguration.Builder(DriveUri.of(join(dir, sub))).setMimeType(mime).setLabel(sub).setSelectionFlags(Media.SELECTION_FLAG_DEFAULT).build()
            // A subtitle that does not read is no reason for the film to stop.
            sources += SingleSampleMediaSource.Factory(factory).setTreatLoadErrorsAsEndOfStream(true).createMediaSource(config, Media.TIME_UNSET)
        }
        val place = withTimeoutOrNull(1000) { app.core.topic(Topics.drivePlace(station, root, path)).first { !it.loading } }?.value as? JsonObject
        val at = place?.get("at")?.jsonPrimitive?.doubleOrNull?.toLong() ?: 0L
        val of = place?.get("of")?.jsonPrimitive?.doubleOrNull?.toLong() ?: 0L
        player.setMediaSource(MergingMediaSource(*sources.toTypedArray()))
        // Left near its end: from the start again.
        if (at > 0 && (of <= 0 || at < of - 5_000)) player.seekTo(at)
        player.prepare()
        player.playWhenReady = true
        Log.i(TAG, "open $path size=${sizes[path]} subtitle=${sub ?: "none"} resume=${at}ms")
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(s: Int) {
                state = s
                if (s == Player.STATE_READY && !started) {
                    started = true
                    Log.i(TAG, "ready ${android.os.SystemClock.elapsedRealtime() - openedAt}ms after opening, ${stats.bytesRead}B read in ${stats.readCount} reads")
                }
            }
            override fun onIsPlayingChanged(p: Boolean) { playing = p }
            override fun onVideoSizeChanged(size: VideoSize) {
                if (size.width > 0 && size.height > 0) video = IntSize((size.width * size.pixelWidthHeightRatio).toInt(), size.height)
            }
            override fun onCues(group: CueGroup) { cues = group.cues.mapNotNull { it.text?.toString() }.joinToString("\n") }
            override fun onPlayerError(error: PlaybackException) {
                var deepest: Throwable = error
                while (deepest.cause != null && deepest.cause !== deepest) deepest = deepest.cause!!
                failure = deepest.message?.takeIf { it.isNotBlank() } ?: error.errorCodeName
                Log.w(TAG, "playback failed: ${error.errorCodeName}: ${deepest.message}")
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); player.release() }
    }

    // Where it is, read off the player as it plays (it says nothing of it by itself); and kept, every few seconds.
    LaunchedEffect(player) {
        var tick = 0
        while (true) {
            position = player.currentPosition.coerceAtLeast(0)
            duration = player.duration.takeIf { it != Media.TIME_UNSET }?.coerceAtLeast(0) ?: 0
            buffered = player.bufferedPosition.coerceAtLeast(0)
            if (++tick % 20 == 0) {
                Log.i(TAG, "pos=${position}ms buffered=${buffered}ms read=${stats.bytesRead}B reads=${stats.readCount} window=${stats.windowBytes}B rate=${"%.1f".format(stats.rate / 1048576)}MB/s")
                if (started && duration > 0) keepPlace(app, station, root, path, position, duration)
            }
            delay(250)
        }
    }
    val last by rememberUpdatedState(position to duration)
    DisposableEffect(path) { onDispose { if (last.second > 0) keepPlace(app, station, root, path, last.first, last.second) } }
    LaunchedEffect(speed) { player.setPlaybackSpeed(speed) }
    LaunchedEffect(subtitlesOn) {
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setSelectUndeterminedTextLanguage(true).setTrackTypeDisabled(Media.TRACK_TYPE_TEXT, !subtitlesOn).build()
    }
    LaunchedEffect(note) { if (note != null) { delay(800); note = null } }
    // A song has no picture to clear the way for: its controls stay.
    val audio = entries.firstOrNull { it.name == name }?.kind == "audio" || (started && video == null)
    LaunchedEffect(awake, phase, poke, audio) { if (awake && phase == Phase.Playing && !audio) { delay(REST_MS); awake = false } }

    // Sideways: landscape asked for (a phone with rotation locked turns too) and the system bars away; back, upright.
    val view = LocalView.current
    DisposableEffect(sideways) {
        val activity = context.activity()
        val controller = activity?.window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (sideways) controller?.hide(WindowInsetsCompat.Type.systemBars()) else controller?.show(WindowInsetsCompat.Type.systemBars())
        activity?.requestedOrientation = if (sideways) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        onDispose { if (sideways) { controller?.show(WindowInsetsCompat.Type.systemBars()); activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED } }
    }
    // The bars' icons light over the black page, as the app's again once it goes.
    val appLight = !Palette.dark
    DisposableEffect(Unit) {
        val controller = context.activity()?.window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.apply { isAppearanceLightStatusBars = false; isAppearanceLightNavigationBars = false }
        onDispose { controller?.apply { isAppearanceLightStatusBars = appLight; isAppearanceLightNavigationBars = appLight } }
    }
    BackHandler(enabled = sideways) { sideways = false }

    fun wake() { awake = true; poke++ }
    fun playPause() {
        if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
        if (player.isPlaying) player.pause() else player.play()
    }
    fun seekBy(delta: Long) {
        val end = player.duration.takeIf { it != Media.TIME_UNSET }
        player.seekTo((player.currentPosition + delta).coerceAtLeast(0).let { if (end != null) it.coerceAtMost(end) else it })
    }
    fun open(other: String) { player.pause(); app.replace(Screen.DrivePlay(station, root, join(dir, other))) }

    val shown by animateFloatAsState(if (awake || phase != Phase.Playing || audio) 1f else 0f, tween(200), label = "controls")
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Box(Modifier.fillMaxSize().hazeSource(haze)) {
            Picture(player, video, fill)
            if (audio) Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                IconIn(Icons.FileAudio, 56.dp, Muted)
                Text(name, fontSize = 16.sp, color = Ink, textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
        // A tap shows or hides the controls; a double tap on a side jumps, in the middle pauses or plays.
        Box(
            Modifier.fillMaxSize().pointerInput(Unit) {
                val third = size.width / 3f
                detectTapGestures(
                    onTap = { if (awake && phase == Phase.Playing) awake = false else wake() },
                    onDoubleTap = { at ->
                        when {
                            at.x < third -> { seekBy(-NUDGE_MS); note = t("android-misc.drive.player.back", "n" to NUDGE_MS / 1000) }
                            at.x > third * 2 -> { seekBy(NUDGE_MS); note = t("android-misc.drive.player.ahead", "n" to NUDGE_MS / 1000) }
                            else -> { val was = player.isPlaying; playPause(); note = if (was) t("android-misc.drive.player.paused") else t("android-misc.drive.player.playing") }
                        }
                    },
                )
            },
        )
        if (subtitlesOn && cues.isNotEmpty()) Text(
            cues, fontSize = if (sideways) 20.sp else 16.sp, lineHeight = if (sideways) 26.sp else 22.sp, color = Color.White, textAlign = TextAlign.Center,
            style = TextStyle(shadow = Shadow(Color.Black, Offset(0f, 1f), 6f)),
            modifier = Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 24.dp)
                .padding(bottom = if (shown > 0.5f) 132.dp else 28.dp).background(Color.Black.copy(alpha = 0.35f), Smooth(6.dp)).padding(horizontal = 8.dp, vertical = 2.dp),
        )
        when (phase) {
            Phase.Opening, Phase.Buffering -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Spinner(22.dp)
                Text(if (phase == Phase.Opening) t("android-misc.drive.player.opening") else t("android-misc.drive.player.buffering"), fontSize = 13.sp, color = Muted)
            }
            Phase.Failed -> Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(t("android-misc.drive.player.failed"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ink)
                failure?.let { Text(it, fontSize = 12.sp, color = Muted, textAlign = TextAlign.Center, maxLines = 4, overflow = TextOverflow.Ellipsis) }
                Chip(t("android-misc.drive.player.retry")) { attempt++ }
            }
            Phase.Ended -> if (next != null) Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(t("android-misc.drive.player.ended"), fontSize = 14.sp, color = Muted)
                Chip(t("android-misc.drive.player.nextOne", "name" to next)) { open(next) }
            }
            else -> {}
        }
        note?.let { Text(it, fontSize = 14.sp, color = Ink, modifier = Modifier.align(Alignment.Center).padding(bottom = 120.dp).background(Color.Black.copy(alpha = 0.55f), Smooth(12.dp)).padding(horizontal = 16.dp, vertical = 9.dp)) }

        // The bar at the top: back, the name, which of the folder's it is (as the phone web's).
        val insets = WindowInsets.statusBars.union(WindowInsets.displayCutout)
        val index = list.indexOf(name)
        Row(
            Modifier.align(Alignment.TopCenter).windowInsetsPadding(insets).padding(horizontal = 8.dp, vertical = 6.dp).fillMaxWidth().alpha(shown)
                .glass(haze, Smooth(16.dp)).height(48.dp).padding(start = 4.dp, end = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Key(Icons.ChevronLeft, t("common.back"), enabled = shown > 0f) { if (sideways) sideways = false else app.pop() }
            Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false).padding(horizontal = 4.dp))
            if (list.size > 1 && index >= 0) Text("${index + 1} / ${list.size}", fontSize = 12.sp, color = Muted, maxLines = 1, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.padding(start = 4.dp))
        }
        // The controls at the foot: the time over where it is (and what is buffered beyond it); the one before, 15 s back,
        // play, 15 s on, the one after; the speed, the subtitle, sideways.
        val prev = if (index > 0) list[index - 1] else null
        Column(
            Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars.union(WindowInsets.displayCutout)).padding(horizontal = 8.dp, vertical = 8.dp)
                .widthIn(max = 720.dp).fillMaxWidth().alpha(shown).glass(haze, Smooth(20.dp))
                .pointerInput(Unit) { awaitEachGesture { awaitFirstDown(requireUnconsumed = false); wake() } }
                .padding(start = 6.dp, end = 6.dp, top = 8.dp, bottom = 4.dp),
        ) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(color = Ink, fontWeight = FontWeight.SemiBold)) { append(clock(position)) }
                    append(" / ${if (duration > 0) clock(duration) else "--:--"}")
                },
                fontSize = 12.sp, color = Muted, maxLines = 1, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.padding(start = 10.dp),
            )
            Timeline(position, duration, buffered, enabled = shown > 0f) { player.seekTo(it); wake() }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                if (list.size > 1) Key(Icons.SkipBack, t("android-misc.drive.player.prev"), enabled = shown > 0f && prev != null) { prev?.let { open(it) } }
                Key(Icons.Back15, t("android-misc.drive.player.back15"), enabled = shown > 0f) { seekBy(-NUDGE_MS); wake() }
                Key(if (phase == Phase.Playing || phase == Phase.Buffering) Icons.Pause else Icons.Play, if (playing) t("android-chat.video.pause") else t("android-chat.video.play"), enabled = shown > 0f) { playPause(); wake() }
                Key(Icons.Forward15, t("android-misc.drive.player.forward15"), enabled = shown > 0f) { seekBy(NUDGE_MS); wake() }
                if (list.size > 1) Key(Icons.SkipForward, t("android-misc.drive.player.next"), enabled = shown > 0f && next != null) { next?.let { open(it) } }
                Spacer(Modifier.weight(1f))
                SpeedKey(speed, enabled = shown > 0f) { speed = SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.size]; wake() }
                if (subtitle != null) Key(Icons.Captions, if (subtitlesOn) t("android-misc.drive.player.subtitlesOff") else t("android-misc.drive.player.subtitlesOn"), pressed = subtitlesOn, enabled = shown > 0f) { subtitlesOn = !subtitlesOn; wake() }
                // Turned sideways the picture can fill the screen (cropped) or fit in it.
                if (!audio && sideways) Key(if (fill) Icons.Shrink else Icons.Expand, if (fill) t("android-misc.drive.player.fit") else t("android-misc.drive.player.fill"), pressed = fill, enabled = shown > 0f) { fill = !fill; wake() }
                if (!audio) Key(Icons.Landscape, if (sideways) t("android-misc.drive.player.unfull") else t("android-misc.drive.player.full"), pressed = sideways, enabled = shown > 0f) { sideways = !sideways; wake() }
            }
        }
    }
}

/** Where it was left, kept on this device: its time and its length (ms). */
private fun keepPlace(app: AppState, station: String, root: String, path: String, at: Long, of: Long) {
    app.scope.launch { try { app.api(station).drivePlace(root, path, at.toDouble(), of.toDouble()) } catch (e: CoreException) { Log.w(TAG, "place not kept: ${e.code} ${e.message}") } }
}

/** A player that reads side-loaded subtitles (SubRip and the rest arrive as raw samples, which media3 decodes only so). */
private fun newPlayer(context: Context): ExoPlayer {
    val renderers = object : DefaultRenderersFactory(context) {
        override fun buildTextRenderers(context: Context, output: TextOutput, outputLooper: Looper, extensionRendererMode: Int, out: ArrayList<Renderer>) {
            super.buildTextRenderers(context, output, outputLooper, extensionRendererMode, out)
            @Suppress("DEPRECATION")
            out.filterIsInstance<TextRenderer>().forEach { it.experimentalSetLegacyDecodingEnabled(true) }
        }
    }
    return ExoPlayer.Builder(context, renderers).build().apply { setAudioAttributes(AudioAttributes.DEFAULT, true) }
}

private fun subtitleMime(name: String): String? = when (name.substringAfterLast('.').lowercase()) {
    "srt" -> MimeTypes.APPLICATION_SUBRIP
    "vtt" -> MimeTypes.TEXT_VTT
    "ass", "ssa" -> MimeTypes.TEXT_SSA
    else -> null
}

/** The picture: fitted inside the page, or filling it (cropped), centred. */
@Composable
private fun Picture(player: ExoPlayer, video: IntSize?, fill: Boolean) {
    var view by remember { mutableStateOf<TextureView?>(null) }
    var box by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(view, video, fill, box) {
        val v = view ?: return@LaunchedEffect
        val n = video ?: return@LaunchedEffect
        if (box.width == 0 || box.height == 0) return@LaunchedEffect
        val k = if (fill) maxOf(box.width.toFloat() / n.width, box.height.toFloat() / n.height) else minOf(box.width.toFloat() / n.width, box.height.toFloat() / n.height)
        val w = n.width * k
        val h = n.height * k
        val m = Matrix()
        m.setScale(w / box.width, h / box.height)
        m.postTranslate((box.width - w) / 2, (box.height - h) / 2)
        v.setTransform(m)
    }
    AndroidView({ ctx ->
        TextureView(ctx).apply {
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                var surface: Surface? = null
                override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) { surface = Surface(st).also { player.setVideoSurface(it) } }
                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean { player.clearVideoSurface(); surface?.release(); return true }
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
            }
            view = this
        }
    }, Modifier.fillMaxSize().onSizeChanged { box = it })
}

/** Frosted glass over the picture (as the chat's viewer has). */
private fun Modifier.glass(haze: HazeState, shape: Shape): Modifier = clip(shape).hazeEffect(haze) {
    backgroundColor = Color.Black
    tints = listOf(HazeTint(Color(0xFF121214).copy(alpha = 0.62f)))
    blurRadius = 24.dp
    noiseFactor = 0f
}

/** A round key on the controls; `pressed`, a soft light behind it while what it turns on is on. */
@Composable
private fun Key(icon: ImageVector, label: String, pressed: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(if (pressed) Color.White.copy(alpha = 0.14f) else Color.Transparent)
            .clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { IconIn(icon, 20.dp, Ink) }
}

/** The speed, as a figure; a tap goes to the next (1×, 1.25×, 1.5×, 2×, 0.5×, 0.75×, as the phone web's). */
@Composable
private fun SpeedKey(speed: Float, enabled: Boolean, next: () -> Unit) {
    Box(
        Modifier.height(30.dp).widthIn(min = 44.dp).clip(Smooth(10.dp))
            .background(if (speed != 1f) Color.White.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.06f))
            .clickable(enabled = enabled, onClick = next)
            .padding(horizontal = 8.dp).semantics { contentDescription = t("android-misc.drive.player.speed") },
        contentAlignment = Alignment.Center,
    ) { Text(speedLabel(speed), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Ink) }
}

@Composable
private fun Chip(label: String, onClick: () -> Unit) {
    Text(
        label, fontSize = 14.sp, color = Ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
        modifier = Modifier.widthIn(max = 280.dp).clip(Smooth(12.dp)).background(Color.White.copy(alpha = 0.14f)).clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 9.dp),
    )
}

/**
 * Where it is, to tap or drag to a place: a thin track, what is buffered lighter on it, what has played, a round head.
 * The time follows the finger while it drags; the player is sent there once it is let go (not a read per pixel).
 */
@Composable
private fun Timeline(position: Long, duration: Long, buffered: Long, enabled: Boolean, onSeek: (Long) -> Unit) {
    var scrub by remember { mutableStateOf<Long?>(null) }
    var width by remember { mutableIntStateOf(1) }
    val shown = scrub ?: position
    fun at(x: Float) = ((x / width).coerceIn(0f, 1f) * duration).toLong()
    Canvas(
        Modifier.fillMaxWidth().padding(horizontal = 10.dp).height(26.dp).onSizeChanged { width = it.width.coerceAtLeast(1) }
            .pointerInput(duration, enabled) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    if (duration <= 0) return@awaitEachGesture
                    var x = down.position.x
                    try {
                        scrub = at(x)
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (change.changedToUpIgnoreConsumed()) { onSeek(at(x)); break }
                            if (change.positionChanged()) { x = change.position.x; scrub = at(x); change.consume() }
                        }
                    } finally { scrub = null }
                }
            },
    ) {
        val part = { ms: Long -> if (duration <= 0) 0f else (ms.toFloat() / duration).coerceIn(0f, 1f) }
        val h = (if (scrub != null) 4.dp else 3.dp).toPx()
        val y = size.height / 2 - h / 2
        drawRoundRect(Color.White.copy(alpha = 0.2f), Offset(0f, y), Size(size.width, h), CornerRadius(h / 2))
        drawRoundRect(Color.White.copy(alpha = 0.35f), Offset(0f, y), Size(size.width * part(buffered), h), CornerRadius(h / 2))
        drawRoundRect(Ink, Offset(0f, y), Size(size.width * part(shown), h), CornerRadius(h / 2))
        drawCircle(Ink, (if (scrub != null) 8.dp else 6.dp).toPx(), Offset(size.width * part(shown), size.height / 2))
    }
}

