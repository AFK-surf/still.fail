// Zooming and panning a picture in a stage (an image, a video's frames), as web/src/FilePreview.tsx useZoom: fitted
// to the stage with a margin, pinched around the fingers, panned when larger than the stage, a double tap zooms in
// (or back to fitted). Fitted, a sideways swipe steps to the picture before or after.
package fail.still.android.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

const val MAX_SCALE = 16f

/**
 * Where a picture of `natural` size (its pixels) shows in a stage of `box` (px). `scale` is the web's: dp per picture
 * pixel (1 = "100%"); `x`, `y` move its centre from the stage's, in px.
 */
class ZoomState(private val density: Float) {
    var natural by mutableStateOf<IntSize?>(null)
        private set
    var box by mutableStateOf(IntSize.Zero)
        private set
    var scale by mutableFloatStateOf(1f)
        private set
    var x by mutableFloatStateOf(0f)
        private set
    var y by mutableFloatStateOf(0f)
        private set
    private var fitted = true
    private var animation: Job? = null

    private val margin get() = (if (box.width < 640 * density) 12f else 32f) * density

    /** Fitted: the whole picture within the stage, never enlarged. */
    val fit: Float
        get() {
            val n = natural ?: return 1f
            if (box.width == 0 || box.height == 0 || n.width == 0 || n.height == 0) return 1f
            return min(1f, min((box.width - 2 * margin) / (n.width * density), (box.height - 2 * margin) / (n.height * density)))
        }
    val minScale get() = min(fit, 1f) / 2
    val zoomed get() = scale > fit * 1.01f
    /** Larger than the stage: a drag pans it. */
    val larger get() = natural?.let { it.width * scale * density > box.width + 1 || it.height * scale * density > box.height + 1 } ?: false
    /** Screen px per picture pixel. */
    val k get() = scale * density

    fun fitNatural(size: IntSize?) {
        if (size == natural) return
        natural = size
        if (fitted) { scale = fit; x = 0f; y = 0f } else clampNow()
    }

    fun fitBox(size: IntSize) {
        if (size == box) return
        box = size
        if (fitted) { scale = fit; x = 0f; y = 0f } else clampNow()
    }

    private fun clampNow() {
        val n = natural ?: return
        scale = scale.coerceIn(minScale, MAX_SCALE)
        val spareX = max(0f, (n.width * k - box.width) / 2)
        val spareY = max(0f, (n.height * k - box.height) / 2)
        x = x.coerceIn(-spareX, spareX)
        y = y.coerceIn(-spareY, spareY)
    }

    /** The picture's place on the stage, in px. */
    fun rect(): Rect? {
        val n = natural ?: return null
        val w = n.width * k
        val h = n.height * k
        val left = box.width / 2f + x - w / 2
        val top = box.height / 2f + y - h / 2
        return Rect(left, top, left + w, top + h)
    }

    /** A point on the stage (px) in the picture's own pixels. */
    fun toPicture(p: Offset): Offset {
        val r = rect() ?: return Offset.Zero
        return Offset((p.x - r.left) / k, (p.y - r.top) / k)
    }

    /** By `zoom` around `centroid` (on the stage), and moved by `pan`. */
    fun transform(centroid: Offset, zoom: Float, pan: Offset) {
        animation?.cancel()
        val next = (scale * zoom).coerceIn(minScale, MAX_SCALE)
        val f = next / scale
        val px = centroid.x - box.width / 2f
        val py = centroid.y - box.height / 2f
        fitted = false
        scale = next
        x = px - (px - x) * f + pan.x
        y = py - (py - y) * f + pan.y
        clampNow()
    }

    /** To `target`, the picture's point under `at` (on the stage; null: its centre) staying put. */
    fun zoomTo(target: Float, at: Offset? = null, scope: CoroutineScope? = null) {
        val next = target.coerceIn(minScale, MAX_SCALE)
        val px = (at?.x ?: (box.width / 2f)) - box.width / 2f
        val py = (at?.y ?: (box.height / 2f)) - box.height / 2f
        val f = next / scale
        var tx = px - (px - x) * f
        var ty = py - (py - y) * f
        natural?.let { n ->
            val sx = max(0f, (n.width * next * density - box.width) / 2)
            val sy = max(0f, (n.height * next * density - box.height) / 2)
            tx = tx.coerceIn(-sx, sx); ty = ty.coerceIn(-sy, sy)
        }
        fitted = false
        glide(next, tx, ty, scope)
    }

    fun reset(scope: CoroutineScope? = null) {
        glide(fit, 0f, 0f, scope)
        fitted = true
    }

    private fun glide(toScale: Float, toX: Float, toY: Float, scope: CoroutineScope?) {
        animation?.cancel()
        if (scope == null) { scale = toScale; x = toX; y = toY; return }
        val from = Triple(scale, x, y)
        animation = scope.launch {
            animate(0f, 1f, animationSpec = tween(260, easing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f))) { t, _ ->
                scale = from.first + (toScale - from.first) * t
                x = from.second + (toX - from.second) * t
                y = from.third + (toY - from.third) * t
            }
        }
    }

    /** A double tap: fitted, in to 2.5× the fitted size (at least 100%) around it; zoomed, back to fitted. */
    fun doubleTap(at: Offset, scope: CoroutineScope) {
        if (zoomed) reset(scope) else zoomTo(max(fit * 2.5f, 1f), at, scope)
    }
}

/** A finger drawing on the picture (marks): its own while it is the only one; a second one takes it back to pinch. */
interface Strokes {
    fun down(at: Offset)
    fun move(at: Offset)
    fun up()
    /** A second finger came: what the first was doing is put back. */
    fun cancel()
}

/**
 * The stage's gestures: pinch and pan; a tap (`onTap`) and a double tap; a sideways swipe when fitted (`onSwipe`: -1
 * to the one before, 1 after). With `strokes`, one finger is theirs and double taps are not heard.
 */
fun Modifier.zoomable(state: ZoomState, scope: CoroutineScope, onTap: () -> Unit, onSwipe: ((Int) -> Unit)? = null, strokes: Strokes? = null): Modifier =
    onSizeChanged { state.fitBox(it) }
        .pointerInput(state, strokes == null) {
            if (strokes == null) detectTapGestures(onDoubleTap = { state.doubleTap(it, scope) }, onTap = { onTap() })
        }
        .pointerInput(state, strokes, onSwipe) {
            val slop = viewConfiguration.touchSlop
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val start = down.position
                var multi = false
                var past = false
                var drawing = false
                var pan = Offset.Zero
                var zoom = 1f
                var last: PointerInputChange = down
                if (strokes != null) { strokes.down(start); drawing = true; down.consume() }
                while (true) {
                    val event = awaitPointerEvent()
                    val pressed = event.changes.filter { it.pressed }
                    if (pressed.isEmpty()) { last = event.changes.firstOrNull { it.id == down.id } ?: event.changes.first(); break }
                    if (pressed.size > 1 && !multi) {
                        multi = true
                        if (drawing) { strokes?.cancel(); drawing = false }
                    }
                    if (drawing) {
                        pressed.firstOrNull { it.id == down.id }?.let { strokes?.move(it.position); it.consume() }
                        continue
                    }
                    val z = event.calculateZoom()
                    val p = event.calculatePan()
                    if (!past) {
                        zoom *= z; pan += p
                        past = abs(1 - zoom) * 200 > slop || pan.getDistance() > slop
                    }
                    if (past) {
                        // Fitted and one finger: a swipe, not a pan.
                        val swiping = !multi && onSwipe != null && !state.zoomed && !state.larger
                        if (!swiping) state.transform(event.calculateCentroid(useCurrent = true), z, p)
                        event.changes.forEach { if (it.positionChanged()) it.consume() }
                    }
                }
                if (drawing) strokes?.up()
                else if (!multi && onSwipe != null && !state.zoomed) {
                    val dx = last.position.x - start.x
                    val dy = last.position.y - start.y
                    if (abs(dx) > 60 * density && abs(dx) > 2 * abs(dy)) onSwipe(if (dx > 0) -1 else 1)
                }
            }
        }
