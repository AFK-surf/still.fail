// A station's screen, full screen (docs/remote-screens.md): the frame fitted whole (letterboxed), zoomed in place with
// two fingers; while driving it, a tap clicks, a long press right-clicks, a drag drags, two fingers moving together
// scroll, and the keyboard types into it. Upright, the bar is above the frame (close, the title and who is on it,
// 只看/控制, the keyboard); sideways, a rail beside it. How the view is (connecting, reconnecting, ended…) is the
// core's, said over the frame, which stays as it was last shown.
package fail.still.android.remote

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.toSize
import androidx.compose.ui.viewinterop.AndroidView
import fail.still.android.data.ScreenCursor
import fail.still.android.data.t
import fail.still.android.screens.Button
import fail.still.android.screens.Spinner
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Seg
import fail.still.android.ui.floatingStill
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/** The stage's tag (the tests find the frame by it). */
internal const val STAGE = "screen-stage"

/** The most a screen is zoomed in, over its fitted size. */
private const val MAX_ZOOM = 5f

/**
 * The frame's own zoom, on this phone only (never sent): `scale` over the fitted size, the frame moved by `x`, `y` (px)
 * from where it sits fitted. Kept within the stage: smaller than it, centred; larger, no gap at its edges.
 */
internal class ViewZoom {
    var scale by mutableFloatStateOf(1f); private set
    var x by mutableFloatStateOf(0f); private set
    var y by mutableFloatStateOf(0f); private set
    val zoomed get() = scale > 1.01f

    /** Where the frame is drawn on the stage, fitted at `fit`. */
    fun shown(fit: Rect): Rect = Rect(fit.left + x, fit.top + y, fit.left + x + fit.width * scale, fit.top + y + fit.height * scale)

    /** By `factor` around `focus`, and moved by `pan` (on the stage, px). */
    fun by(factor: Float, focus: Offset, pan: Offset, fit: Rect, box: Size) {
        if (fit.width <= 0f) return
        val before = shown(fit)
        val next = (scale * factor).coerceIn(1f, MAX_ZOOM)
        val u = Offset((focus.x - before.left) / before.width, (focus.y - before.top) / before.height)
        val w = fit.width * next
        val h = fit.height * next
        fun place(want: Float, size: Float, room: Float) = if (size <= room) (room - size) / 2 else want.coerceIn(room - size, 0f)
        val left = place(focus.x - u.x * w + pan.x, w, box.width)
        val top = place(focus.y - u.y * h + pan.y, h, box.height)
        scale = next
        x = left - fit.left
        y = top - fit.top
    }

    fun pan(d: Offset, fit: Rect, box: Size) = by(1f, Offset(fit.center.x, fit.center.y), d, fit, box)

    fun reset() { scale = 1f; x = 0f; y = 0f }
}

/** The viewer: `title` until the core says one (the link's own, or the row's it was opened from); `onExit` closes it. */
@Composable
fun ScreenViewer(session: ScreenSession, title: String?, onExit: () -> Unit) {
    val zoom = remember { ViewZoom() }
    val context = LocalContext.current
    var catcher by remember { mutableStateOf<KeyCatcher?>(null) }
    val density = LocalDensity.current
    val ime = WindowInsets.ime
    val typing = ime.getBottom(density) > 0
    fun keyboard() {
        val view = catcher ?: return
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (typing) { imm.hideSoftInputFromWindow(view.windowToken, 0); view.clearFocus() }
        else { view.requestFocus(); imm.showSoftInput(view, 0) }
    }
    // No longer driving it (只看, the view ended): the keyboard goes.
    LaunchedEffect(session.driving) {
        val view = catcher ?: return@LaunchedEffect
        if (!session.driving && view.hasFocus()) {
            (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(view.windowToken, 0)
            view.clearFocus()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.safeDrawing)) {
        // Unseen, where the keyboard's input goes.
        AndroidView({ KeyCatcher(it) { input -> session.input(input) }.also { catcher = it } }, Modifier.size(1.dp).alpha(0f))
        val sideways = maxWidth > maxHeight
        if (sideways) Row(Modifier.fillMaxSize()) {
            Rail(session, typing, ::keyboard, onExit)
            Box(Modifier.weight(1f).fillMaxHeight()) {
                Stage(session, zoom, Modifier.fillMaxSize(), onExit)
                // Sideways the frame takes the height: who drives it floats over its top, while it does.
                if (session.canTakeOver) TakeOver(session, Modifier.align(Alignment.TopCenter).padding(top = 12.dp))
            }
        } else Column(Modifier.fillMaxSize()) {
            Bar(session, title, typing, ::keyboard, onExit)
            if (session.canTakeOver) TakeOver(session, Modifier.align(Alignment.CenterHorizontally).padding(horizontal = 12.dp, vertical = 4.dp))
            Stage(session, zoom, Modifier.weight(1f).fillMaxWidth(), onExit)
        }
    }
}

/** The view is open (on its way, live, or back on its way), not over. */
private fun open(session: ScreenSession) = session.phase in setOf("connecting", "live", "reconnecting")

/** 只看 / 控制, while it may be driven and the view is open. */
private fun choosable(session: ScreenSession) = session.state?.may == true && open(session)

/**
 * Why it is not driven though 控制 was chosen, live (the station lacks a grant: macOS's Accessibility), in the station's
 * words; null when it is driven, or only looked at.
 */
private fun undriven(session: ScreenSession): String? {
    val state = session.state ?: return null
    if (session.phase != "live" || !session.controlling || state.control || !state.may || state.takeOver == true) return null
    return state.access?.message?.takeIf { it.isNotEmpty() }
}

/** Upright: close, the title over the core's line (只看 or 控制, who else is on it), 只看/控制, the keyboard. */
@Composable
private fun Bar(session: ScreenSession, title: String?, typing: Boolean, keyboard: () -> Unit, onExit: () -> Unit) {
    val state = session.state
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(start = 6.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        RoundButton(Icons.Close, t("android-misc.screen.close"), onClick = onExit)
        Column(Modifier.weight(1f)) {
            Text(state?.title?.takeIf { it.isNotEmpty() } ?: title ?: t("android-misc.screen.title"), fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            // While another drives it, who does is said below (with 接管), not twice.
            state?.line?.takeIf { it.isNotEmpty() && open(session) && !session.canTakeOver }?.let { Text(it, fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        if (choosable(session)) Seg(
            listOf(t("android-misc.screen.look"), t("android-misc.screen.drive")), if (session.controlling) 1 else 0,
            { session.control(it == 1) }, height = 32.dp, radius = 16.dp,
        )
        if (session.driving) RoundButton(Icons.Keyboard, t("android-misc.screen.keyboard"), pressed = typing, onClick = keyboard)
    }
}

/** Sideways: the same down the side, the line said when the people on it are tapped. */
@Composable
private fun Rail(session: ScreenSession, typing: Boolean, keyboard: () -> Unit, onExit: () -> Unit) {
    val state = session.state
    var saying by remember { mutableStateOf(false) }
    LaunchedEffect(saying) { if (saying) { kotlinx.coroutines.delay(3000); saying = false } }
    Box {
        Column(
            Modifier.fillMaxHeight().width(60.dp).padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            RoundButton(Icons.Close, t("android-misc.screen.close"), onClick = onExit)
            Spacer(Modifier.weight(1f))
            if (state != null && state.line.isNotEmpty() && open(session)) Box(contentAlignment = Alignment.TopEnd) {
                RoundButton(Icons.Users, state.line, pressed = saying) { saying = !saying }
                if (state.others.isNotEmpty()) Text(
                    "${state.others.size}", fontSize = 10.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, color = C.bg, textAlign = TextAlign.Center,
                    modifier = Modifier.offset(x = 4.dp, y = (-2).dp).widthIn(min = 14.dp).height(14.dp).clip(CircleShape).background(C.ink),
                )
            }
            if (choosable(session)) RoundButton(
                if (session.controlling) Icons.Cursor else Icons.Eye,
                if (session.controlling) t("android-misc.screen.drive") else t("android-misc.screen.look"),
                pressed = session.controlling,
            ) { session.control(!session.controlling) }
            if (session.driving) RoundButton(Icons.Keyboard, t("android-misc.screen.keyboard"), pressed = typing, onClick = keyboard)
        }
        if (saying && state != null) Text(
            state.line, fontSize = 13.sp, lineHeight = 18.sp, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomStart).offset(x = 64.dp, y = (-8).dp).widthIn(max = 280.dp)
                .floatingStill(RoundedCornerShape(18.dp)).padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}

/**
 * Someone else drives it (an agent at work) and this view only looks: who, and 接管 in one tap (`screen.control` true:
 * their input waits while this person drives; the line then says so).
 */
@Composable
private fun TakeOver(session: ScreenSession, modifier: Modifier) {
    val who = session.state?.controllers.orEmpty()
    // A capsule round a 32 high button 6 in from its edge: its corner 6 + 16.
    Row(
        modifier.widthIn(max = 480.dp).floatingStill(RoundedCornerShape(22.dp)).padding(start = 14.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(C.warn))
        Text(
            if (who.isEmpty()) t("android-misc.screen.someoneDrives") else t("android-misc.screen.drives", "who" to who.joinToString("、")),
            fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Box(
            Modifier.height(32.dp).clip(RoundedCornerShape(16.dp)).background(C.accent).clickable { session.control(true) }.padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) { Text(t("android-misc.screen.takeOver"), fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1) }
    }
}

/** A round button with an icon, its name for those who cannot see it; `pressed`: on (the keyboard up, 控制). */
@Composable
private fun RoundButton(icon: ImageVector, label: String, pressed: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(if (pressed) C.ink.copy(alpha = 0.1f) else Color.Transparent)
            .clickable(onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { IconIn(icon, 20.dp, C.ink) }
}

/** The frame, fitted and zoomed, its pointer; the gestures; how the view is, over it. */
@Composable
private fun Stage(session: ScreenSession, zoom: ViewZoom, modifier: Modifier, onExit: () -> Unit) {
    val picture = session.picture
    val size = session.size ?: picture?.let { IntSize(it.bitmap.width, it.bitmap.height) }
    var box by remember { mutableStateOf(Size.Zero) }
    val fit = if (size == null) Rect.Zero else fitIn(box, Size(size.width.toFloat(), size.height.toFloat()))
    // Turned, or another size of frame: fitted again.
    LaunchedEffect(box, size) { zoom.reset() }
    val phase = session.phase
    val density = LocalDensity.current
    val fitNow by rememberUpdatedState(fit)
    val boxNow by rememberUpdatedState(box)
    val sizeNow by rememberUpdatedState(size)
    Box(
        modifier.clipToBounds().testTag(STAGE).onSizeChanged { box = it.toSize() }
            .pointerInput(session, zoom) { gestures(session, zoom, { fitNow }, { boxNow }, { sizeNow }) },
    ) {
        if (size != null && fit.width > 0f) {
            val still = phase != "live" && session.shownAny
            Box(
                Modifier.offset { IntOffset(fit.left.roundToInt(), fit.top.roundToInt()) }
                    .size(with(density) { fit.width.toDp() }, with(density) { fit.height.toDp() })
                    .graphicsLayer {
                        transformOrigin = TransformOrigin(0f, 0f)
                        scaleX = zoom.scale; scaleY = zoom.scale
                        translationX = zoom.x; translationY = zoom.y
                        alpha = if (still) 0.4f else 1f
                    },
            ) {
                if (session.codec == "h264") Texture(session)
                else Canvas(Modifier.fillMaxSize()) {
                    val p = session.picture ?: return@Canvas
                    drawImage(p.bitmap.asImageBitmap(), dstSize = IntSize(this.size.width.roundToInt(), this.size.height.roundToInt()), filterQuality = FilterQuality.Medium)
                    session.drew(p)
                }
                session.state?.cursor?.let { Pointer(it) }
            }
        }
        Over(session, phase, Modifier.align(Alignment.Center), onExit)
        undriven(session)?.let { why ->
            Row(
                Modifier.align(Alignment.BottomCenter).padding(16.dp).widthIn(max = 420.dp).floatingStill(RoundedCornerShape(18.dp))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                IconIn(Icons.Info, 16.dp, C.muted)
                Text(why, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** H.264 decoded straight onto a texture of the frame's size (MediaCodec, Decoders.kt). */
@Composable
private fun Texture(session: ScreenSession) {
    AndroidView({ ctx ->
        TextureView(ctx).apply {
            isOpaque = false
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                private var surface: Surface? = null
                override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                    surface = Surface(st).also(session::surface)
                }
                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                    session.surface(null)
                    surface?.release()
                    surface = null
                    return true
                }
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
            }
        }
    }, Modifier.fillMaxSize())
}

/** Where the station's pointer is: an arrow, white with a dark edge, its tip there. */
@Composable
private fun Pointer(cursor: ScreenCursor) {
    Canvas(Modifier.fillMaxSize()) {
        val k = 1.dp.toPx()
        val arrow = Path().apply {
            moveTo(0f, 0f); lineTo(0f, 16 * k); lineTo(4 * k, 12.5f * k); lineTo(7 * k, 18.5f * k)
            lineTo(9.5f * k, 17.5f * k); lineTo(6.5f * k, 11.5f * k); lineTo(11.5f * k, 11.5f * k); close()
        }
        translate(cursor.x.toFloat() * size.width, cursor.y.toFloat() * size.height) {
            drawPath(arrow, Color.White)
            drawPath(arrow, Color(0xFF1B1C1F), style = Stroke(1.2f * k))
        }
    }
}

/** How the view is, when it is not simply live: on its way, back on its way, or over (why, and what can be done). */
@Composable
private fun Over(session: ScreenSession, phase: String, modifier: Modifier, onExit: () -> Unit) {
    val message = session.message
    when (phase) {
        "live" -> if (!session.shownAny) Waiting(t("android-misc.screen.starting"), modifier)
        "connecting" -> Waiting(message ?: t("android-misc.screen.connecting"), modifier)
        "reconnecting" -> Waiting(message ?: t("android-misc.screen.reconnecting"), modifier)
        else -> Column(
            modifier.padding(24.dp).widthIn(max = 360.dp).floatingStill(RoundedCornerShape(24.dp)).padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconIn(if (session.state?.kind == "browser") Icons.Web else Icons.Monitor, 28.dp, C.muted)
            Text(t("android-misc.screen.$phase"), fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = C.ink, textAlign = TextAlign.Center)
            if (message != null) Text(message, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, textAlign = TextAlign.Center)
            // What to turn on where (macOS's grants), when the station says and its message did not already.
            session.state?.access?.message?.takeIf { it.isNotEmpty() && it != message }?.let {
                Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, textAlign = TextAlign.Center)
            }
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (phase in setOf("ended", "denied", "failed")) Button(t("android-misc.screen.retry"), primary = true) { session.open() }
                Button(t("android-misc.screen.exit"), primary = false, onClick = onExit)
            }
        }
    }
}

/** On its way: a spinner and why, in a capsule over the frame (kept as it was) or the empty stage. */
@Composable
private fun Waiting(text: String, modifier: Modifier) {
    Row(
        modifier.padding(24.dp).floatingStill(RoundedCornerShape(20.dp)).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Spinner(14.dp)
        Text(text, fontSize = 14.sp, lineHeight = 20.sp, color = C.ink, maxLines = 3, overflow = TextOverflow.Ellipsis)
    }
}

private fun centroid(fingers: List<PointerInputChange>): Offset =
    fingers.fold(Offset.Zero) { s, c -> s + c.position } / fingers.size.toFloat()

private fun spread(fingers: List<PointerInputChange>, around: Offset): Float =
    fingers.sumOf { (it.position - around).getDistance().toDouble() }.toFloat() / fingers.size

/**
 * The stage's gestures. Driving it: a tap is a click (down and up, the primary button), a press held a right click,
 * a drag a drag (down, moves, up), two fingers moving together a wheel. Either way two fingers spreading zoom the
 * frame here (it is not sent), and moving together pan it when zoomed and not driving; one finger pans it too then.
 */
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.gestures(
    session: ScreenSession, zoom: ViewZoom, fit: () -> Rect, box: () -> Size, frame: () -> IntSize?,
) {
    val slop = viewConfiguration.touchSlop
    val hold = viewConfiguration.longPressTimeoutMillis
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val drives = session.driving
        val start = down.position
        fun at(p: Offset, clamp: Boolean) = frameAt(p, zoom.shown(fit()), clamp)
        // 0: not yet told, 1: a drag sent, 2: panning here, 3: two fingers, 4: nothing more (a right click sent, or ignored).
        var mode = 0
        var last = start
        var lastTime = down.uptimeMillis
        // Two fingers: 0 not yet told, 1 zooming, 2 scrolling; where they were and how far apart.
        var two = 0
        var from = Offset.Zero
        var c0 = Offset.Zero
        var s0 = 0f
        var s1 = 0f
        while (true) {
            val event = if (mode == 0) withTimeoutOrNull(max(1L, hold - (lastTime - down.uptimeMillis))) { awaitPointerEvent() } else awaitPointerEvent()
            if (event == null) {
                // Held still: a right click where it is.
                if (drives) at(start, false)?.let { session.input(pointer("down", it, SECONDARY)); session.input(pointer("up", it, SECONDARY)) }
                mode = 4
                continue
            }
            event.changes.firstOrNull()?.let { lastTime = it.uptimeMillis }
            val pressed = event.changes.filter { it.pressed }
            if (pressed.isEmpty()) {
                when (mode) {
                    0 -> if (drives) at(start, false)?.let { session.input(pointer("down", it, PRIMARY)); session.input(pointer("up", it, PRIMARY)) }
                    1 -> at(last, true)?.let { session.input(pointer("up", it, PRIMARY)) }
                }
                break
            }
            if (pressed.size >= 2 && mode != 3) {
                // A second finger: what the first was doing ends where it is.
                if (mode == 1) at(last, true)?.let { session.input(pointer("up", it, PRIMARY)) }
                mode = 3
                two = 0
                c0 = centroid(pressed); s0 = spread(pressed, c0)
                from = c0; s1 = s0
                event.changes.forEach { it.consume() }
                continue
            }
            val finger = pressed.firstOrNull { it.id == down.id } ?: pressed.first()
            when (mode) {
                0 -> if ((finger.position - start).getDistance() > slop) {
                    mode = when {
                        drives -> at(start, false)?.let { session.input(pointer("down", it, PRIMARY)); 1 } ?: 4
                        zoom.zoomed -> 2
                        else -> 4
                    }
                    if (mode == 1) at(finger.position, true)?.let { session.input(pointer("move", it, PRIMARY)) }
                    last = finger.position
                }
                1 -> {
                    at(finger.position, true)?.let { session.input(pointer("move", it, PRIMARY)) }
                    last = finger.position
                }
                2 -> zoom.pan(finger.position - finger.previousPosition, fit(), box())
                3 -> if (pressed.size >= 2) {
                    val c = centroid(pressed)
                    val s = spread(pressed, c)
                    if (two == 0) {
                        val spreading = abs(s - s0)
                        val moving = (c - c0).getDistance()
                        if (spreading > slop || moving > slop) two = if (spreading > moving) 1 else 2
                    } else if (two == 1) {
                        zoom.by(if (s1 > 0f) s / s1 else 1f, c, c - from, fit(), box())
                    } else {
                        val d = c - from
                        val shown = zoom.shown(fit())
                        val f = frame()
                        if (drives && f != null && shown.width > 0f) {
                            // The fingers' way in the frame's own pixels; the page under them moves with them.
                            val k = f.width / shown.width
                            at(c, true)?.let { session.input(wheel(it, -d.x * k, -d.y * k)) }
                        } else if (zoom.zoomed) zoom.pan(d, fit(), box())
                    }
                    from = c; s1 = s
                }
            }
            event.changes.forEach { if (it.positionChanged()) it.consume() }
        }
    }
}
