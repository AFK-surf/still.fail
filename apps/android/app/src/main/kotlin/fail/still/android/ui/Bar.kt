// The phone's bottom bar (下方栏), as the prototype agreed with the user has it (session c-1c78bb4403's
// proto/vbar/vbar.jsx `Bar`, frosted only): a floating capsule of the places of one bar; a frosted ball over the place
// shown, which travels on a spring stretched by its speed and goes where a finger takes it; 令 (a new chat) standing in
// a notch cut out of the bar's top on the chats' pages; with more than one bar, the glass grows upward into a panel of
// the other bars (a swipe up on the bar), one row each, and a bar chosen there slides down into the bar's place.
// Everything is glass of one source (Haze): the pages under it, the bar's glass for the ball and 令, 令 for the ball.
package fail.still.android.ui

import android.graphics.BlurMaskFilter
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

// ── geometry (dp) ───────────────────────────────────────────────────────

/** The bar's height. */
internal const val BAR_TRACK = 56f
/** The ball at rest: this far from the bar's top, foot and ends alike. */
private const val INSET = 6f
private const val BALL_REST = BAR_TRACK - INSET * 2
/** The ball: always a circle this big at rest, so 6 past the bar on every side. */
internal const val BALL = BAR_TRACK + 12f
/** A place's middle at the bar's ends: the ball at rest as far from the ends as from the top and foot. */
private const val C0 = INSET + BALL_REST / 2
private const val DROP = 56f
private const val NOTCH_GAP = 6f
/** 令's middle above the bar's top. */
private const val LIFT = 4f
private const val FILLET = 8f
/** A row of the panel: as tall as the bar, rows stacked with no gap. */
private const val ROW = 56f
/** Room above the panel's rows for its overshoot as it opens. */
private const val OVER = 20f
private const val RAD = BAR_TRACK / 2
/** One place over: the distance that keeps the ball's spring at tension 300. */
private const val SLOT_PX = 90f
private const val LEAN = 0.25f
private const val MAX_STRETCH = 36f
/** A finger moved this far is a slide, not a tap. */
private const val SLOP = 8f

/** The places' middles on a bar `w` wide holding `n` (four values; past `n` repeated) with the notch `k` open. */
internal fun barCentres(w: Float, k: Float, n: Int): FloatArray {
    val closed = (w - 2 * C0) / 3
    val open = (w / 2 - (DROP / 2 + NOTCH_GAP) - 6f - BALL_REST / 2) - C0
    val sp = closed + (open - closed) * k
    return when {
        n >= 4 -> floatArrayOf(C0, C0 + sp, w - C0 - sp, w - C0)
        n == 3 -> floatArrayOf(C0, C0 + ((w / 2 - C0) - (w / 2 - C0 - sp) * k), w - C0, w - C0)
        n == 2 -> floatArrayOf(C0, w - C0, w - C0, w - C0)
        else -> floatArrayOf(C0, C0, C0, C0)
    }
}

/** A spring as react-spring's tension and friction (mass 1). */
private fun springOf(tension: Float, friction: Float, threshold: Float = 0.01f): SpringSpec<Float> =
    spring(dampingRatio = friction / (2 * sqrt(tension)), stiffness = tension, visibilityThreshold = threshold)

private val OPEN = springOf(260f, 17f, 0.001f)
private val CLOSE = springOf(320f, 26f, 0.001f)
private val SWITCH = springOf(200f, 28f, 0.001f)

/** The bar's layout for what it holds, `w` wide (dp). */
private class Geo(val w: Float, val sets: List<List<String>>, val cur: Int, val active: String?, val chatsPage: Boolean) {
    val items: List<String> = sets.getOrNull(cur).orEmpty()
    /** The other bars, in the panel, top to bottom. */
    val others: List<Int> = sets.indices.filter { it != cur }
    val multi = sets.size > 1
    private val rows = max(1, others.size)
    val panel = BAR_TRACK + rows * ROW + OVER
    /** The bar's top in the panel's frame. */
    val rowTop = panel - BAR_TRACK
    /** How far the glass's top moves from the bar to the open panel. */
    val reach = rowTop - OVER
    val barMid = rowTop + BAR_TRACK / 2
    val topY = OVER + ROW / 2
    val slot = (w - 2 * C0) / 3
    fun rowMid(n: Int) = OVER + n * ROW + ROW / 2
    fun centres(k: Float, n: Int) = barCentres(w, k, n)
    /** Where the bar's places will be, notch open on a chats' page with the panel closed. */
    fun final(mode: Boolean) = centres(if (chatsPage && !mode) 1f else 0f, items.size)
    fun nearest(cs: FloatArray, n: Int, x: Float): Int {
        var best = 0
        for (j in 0 until n) if (abs(cs[j] - x) < abs(cs[best] - x)) best = j
        return best
    }
    /** The row of the panel at `y` (an index into `others`), as the rows lie with the panel open. */
    fun rowAt(y: Float) = floor((y - OVER) / ROW).toInt().coerceIn(0, max(0, others.size - 1))
}

/** The place a let-go would choose while a finger has the ball: its middle, and which bar and place it is. */
private class Cand(val x: Float, val y: Float, val set: Int, val key: String)

/** A bar chosen in the panel, sliding down into the bar's place: which, its row, how open the panel was, the place tapped. */
private class Swap(val i: Int, val n: Int, val from: Float, val key: String?) {
    var done by mutableStateOf(false)
}

/** The rounded bar (or panel) `w`×`h` with the notch cut into its top edge: a circle of radius `r` about (cx, cy). */
private fun outline(w: Float, h: Float, cx: Float, cy: Float, r: Float, d: Float): Path {
    val p = Path()
    val rad = min(RAD * d, h / 2)
    p.moveTo(0f, rad)
    p.arcTo(Rect(0f, 0f, 2 * rad, 2 * rad), 180f, 90f, false)
    notch(p, cx, cy, r, FILLET * d)
    p.lineTo(w - rad, 0f)
    p.arcTo(Rect(w - 2 * rad, 0f, w, 2 * rad), 270f, 90f, false)
    p.lineTo(w, h - rad)
    p.arcTo(Rect(w - 2 * rad, h - 2 * rad, w, h), 0f, 90f, false)
    p.lineTo(rad, h)
    p.arcTo(Rect(0f, h - 2 * rad, 2 * rad, h), 90f, 90f, false)
    p.close()
    return p
}

/**
 * The cut a notch makes in a top edge at y 0: a circle of radius `r` about (cx, c0), met by the edge through two fillets
 * of radius `f` (each touching the edge and the circle). Adds it to `p` from the edge's left meeting to its right, or
 * nothing when there is none (closed); answers whether it did.
 */
private fun notch(p: Path, cx: Float, c0: Float, r: Float, f: Float): Boolean {
    if (r <= 0.5f) return false
    val dy = f - c0
    val reach = (r + f) * (r + f) - dy * dy
    if (c0 + r <= 0.5f || reach <= 0f) return false
    val xf = sqrt(reach)
    val l = cx - xf
    val rr = cx + xf
    val deg = (180.0 / Math.PI).toFloat()
    p.lineTo(l, 0f)
    // The left fillet, from its top round to where it meets the circle (clockwise).
    val a1 = atan2(c0 - f, cx - l) * deg
    p.arcTo(Rect(l - f, 0f, l + f, 2 * f), -90f, a1 + 90f, false)
    // The circle, under, from the left meeting to the right (anticlockwise).
    val aL = atan2(f - c0, l - cx) * deg
    val aR = atan2(f - c0, rr - cx) * deg
    p.arcTo(Rect(cx - r, c0 - r, cx + r, c0 + r), aL, aR - aL, false)
    // The right fillet, from where it meets the circle up to its top (clockwise).
    val a2 = atan2(c0 - f, cx - rr) * deg
    var sweep = -90f - a2
    while (sweep <= 0f) sweep += 360f
    while (sweep > 360f) sweep -= 360f
    p.arcTo(Rect(rr - f, 0f, rr + f, 2 * f), a2, sweep, false)
    return true
}

/** The bar's outline (px) as a shape, a new one whenever it changes, so the glass's clip follows it frame by frame. */
private data class Glass(val w: Float, val h: Float, val cx: Float, val cy: Float, val r: Float, val d: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density) = Outline.Generic(outline(w, h, cx, cy, r, d))
}

/** A rounded rectangle from `top` down (px), for what slides inside the glass as a bar is chosen. */
private data class Window(val top: Float, val radius: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density) =
        Outline.Rounded(RoundRect(0f, top, size.width, max(top, size.height), CornerRadius(radius)))
}

/**
 * Glass's lit rim, as inset shadows on the web: a hairline all round inside its edge (`edge`), light along its top and
 * left (`lit`) and less along its foot and right (`back`).
 */
private fun DrawScope.rim(path: Path, edge: Float, lit: Float, back: Float) {
    val px = 0.5.dp.toPx()
    clipPath(path) { drawPath(path, Color.White.copy(alpha = edge), style = Stroke(width = 2 * px)) }
    val down = Path().apply { addPath(path, Offset(px, px)) }
    drawPath(Path().apply { op(path, down, PathOperation.Difference) }, Color.White.copy(alpha = lit))
    val up = Path().apply { addPath(path, Offset(-px, -px)) }
    drawPath(Path().apply { op(path, up, PathOperation.Difference) }, Color.White.copy(alpha = back))
}

/** A CSS blur's deviation (dp) as BlurMaskFilter's radius (px). */
private fun Density.maskRadius(sigma: Float) = ((sigma.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0.1f)

/** What the bar keeps between frames, and what its gestures do (vbar.jsx's refs and handlers). */
@Stable
private class BarModel(private val scope: CoroutineScope) {
    /** The panel of the other bars open (or opening). */
    var mode by mutableStateOf(false)
    /** How open the panel is: 0 the bar, 1 the panel. */
    val o = Animatable(0f, 0.001f)
    /** The finger's place while it has the ball (dp in the panel's frame); its height only once the panel is involved. */
    var drag by mutableStateOf<Float?>(null)
    var dragY by mutableStateOf<Float?>(null)
    var swap by mutableStateOf<Swap?>(null)

    // The latest of what the bar is told (set as it is drawn).
    var geo: Geo? = null
    var k: () -> Float = { 0f }
    var onTab: (String) -> Unit = {}
    var onSwitch: (Int, String?) -> Unit = { _, _ -> }
    var glass: LayoutCoordinates? = null
    var frame: LayoutCoordinates? = null

    private var dragging = false
    private var opening = false
    private var x0 = 0f
    private var y0 = 0f
    /** What the panel's move under way is to do at its end (a bar chosen: the bar switched); done at once if cut short. */
    private var done: (() -> Unit)? = null
    private var job: Job? = null

    fun springTo(target: Float, v0: Float = o.velocity, then: (() -> Unit)? = null, spec: SpringSpec<Float>? = null) {
        val before = done
        done = then
        before?.invoke()
        job?.cancel()
        job = scope.launch {
            o.animateTo(target, spec ?: if (target > 0f) OPEN else CLOSE, v0)
            val d = done
            done = null
            d?.invoke()
        }
    }

    fun openPanel(open: Boolean) {
        mode = open
        springTo(if (open) 1f else 0f)
    }

    /** A bar being chosen, finished now (a new touch comes before it has landed): it never stays half done. */
    fun finishSwitch() {
        if (swap == null) return
        val d = done ?: return
        done = null
        job?.cancel()
        scope.launch { o.snapTo(0f) }
        d()
    }

    /** Where a touch on the glass is in the panel's frame (dp). */
    fun at(local: Offset, density: Density): Offset {
        val g = glass
        val f = frame
        val p = if (g != null && f != null && g.isAttached && f.isAttached) f.localPositionOf(g, local) else local
        return Offset(p.x / density.density, p.y / density.density)
    }

    fun down(p: Offset) {
        finishSwitch()
        dragging = false
        x0 = p.x
        y0 = p.y
    }

    /** One stroke: a finger set on the bar (or the open panel) and moved any way takes the ball. */
    fun move(p: Offset): Boolean {
        val g = geo ?: return false
        if (!dragging && hypot(p.x - x0, p.y - y0) > SLOP) dragging = true
        if (!dragging) return false
        drag = p.x
        // Leaving the bar upward opens the panel of the other bars, and the ball goes on into their rows.
        if (g.multi && !mode && !opening && p.y < g.rowTop - 8f) {
            opening = true
            mode = true
            springTo(1f)
        }
        dragY = if (g.multi && (mode || opening)) p.y.coerceIn(g.topY, g.rowTop + BAR_TRACK / 2) else null
        return true
    }

    fun up(p: Offset) {
        val g = geo ?: return lost()
        if (!dragging) return tap(p)
        dragging = false
        val open = mode || opening
        opening = false
        drag = null
        dragY = null
        if (open && p.y < g.rowTop - 4f && g.others.isNotEmpty()) {
            // Let go over rows not yet where they go: the panel goes on opening and stays; nothing is chosen.
            if (o.value < 0.85f) { mode = true; return }
            val i = g.others[g.rowAt(p.y)]
            val set = g.sets[i]
            pick(i, set[g.nearest(g.centres(0f, set.size), set.size, p.x)])
            return
        }
        if (g.items.isEmpty()) return
        val j = min(g.items.size - 1, g.nearest(g.final(mode), 4, p.x))
        if (open) openPanel(false)
        if (g.items[j] != g.active) onTab(g.items[j])
    }

    /** The gesture gone without its end being heard: as if let go, nothing chosen. */
    fun lost() {
        opening = false
        dragY = null
        if (dragging) { dragging = false; drag = null }
    }

    /** A tap (moved less than SLOP): a place on the bar; with the panel open, a row (that bar) or a place in it. */
    private fun tap(p: Offset) {
        val g = geo ?: return
        if (mode && p.y < g.rowTop) {
            if (o.value <= 0.6f || g.others.isEmpty()) return
            val n = floor((p.y - OVER - rowsShift(g)) / ROW).toInt()
            if (n !in g.others.indices) return
            val i = g.others[n]
            val set = g.sets[i]
            val cs = g.centres(0f, set.size)
            val j = g.nearest(cs, set.size, p.x)
            pick(i, if (abs(cs[j] - p.x) <= g.slot / 2) set[j] else null)
            return
        }
        if (g.items.isEmpty()) return
        val now = g.centres(k(), g.items.size)
        val j = g.nearest(now, g.items.size, p.x)
        if (abs(now[j] - p.x) > g.slot / 2) return
        if (mode) openPanel(false)
        onTab(g.items[j])
    }

    /** How far the rows are from where they rest as the panel opens: a little low, then up with its overshoot. */
    fun rowsShift(g: Geo): Float {
        val v = o.value
        return (1 - min(1f, v)) * 14f - max(0f, v - 1) * g.reach
    }

    /**
     * Another bar chosen (and a place in it, when one was tapped): the panel closes like a window over a stack of bars,
     * the chosen one sliding down into the bar's place; landed, it is the bar (and the place opens).
     */
    fun pick(i: Int, key: String?) {
        if (swap != null) return
        val g = geo ?: return
        val n = g.others.indexOf(i)
        if (n < 0) return
        val s = Swap(i, n, max(0.2f, o.value), key)
        swap = s
        mode = false
        springTo(0f, o.velocity, then = { s.done = true; onSwitch(i, key) }, spec = SWITCH)
    }
}

/**
 * The bottom bar over the pages that `haze` is the source of. `sets`: the bars (`cur` the one in view); `active`: the
 * place shown (null: none); `chatsPage`: it is one of the chats' (令 in the notch); `shown`: on a place's top page, with
 * nothing over it. `dots`: a place's status dot and its colour; `icon`: a place's icon in a colour.
 */
@Composable
fun BottomBar(
    sets: List<List<String>>, cur: Int, active: String?, chatsPage: Boolean, shown: Boolean, haze: HazeState,
    dots: Map<String, Color>, labelOf: (String) -> String, lingLabel: String, chatFamily: Set<String>,
    icon: @Composable (String, Color) -> Unit,
    onTab: (String) -> Unit, onLing: () -> Unit, onSwitch: (Int, String?) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val m = remember { BarModel(scope) }
    val density = LocalDensity.current
    val dark = C.dark
    val vis by animateFloatAsState(if (shown) 1f else 0f, tween(if (shown) 380 else 300, easing = Ease.Arrive), label = "bar-shown")
    // Hidden, nothing of it is open or held.
    LaunchedEffect(shown) {
        if (!shown) {
            if (m.mode) m.openPanel(false)
            m.lost()
        }
    }
    BackHandler(enabled = shown && m.mode) { m.openPanel(false) }
    // The panel open: a press anywhere else closes it (and does nothing else).
    if (shown && m.mode) Box(Modifier.fillMaxSize().pointerInput(Unit) { awaitEachGesture { awaitFirstDown(); m.openPanel(false) } })
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = maxWidth.value - 32f
        // A bar being chosen with a place in it: the notch already as that place will have it (no 令 coming up only to go).
        val landsOn = m.swap?.key?.let { it in chatFamily }
        val g = Geo(w, sets, cur, active, landsOn ?: chatsPage)
        val chats = g.chatsPage && !m.mode
        // The notch's openness: 令 grows out of the bar with it.
        val kState = animateFloatAsState(if (chats) 1f else 0f, springOf(300f, 30f, 0.001f), label = "notch")
        SideEffect {
            m.geo = g
            m.k = { kState.value }
            m.onTab = onTab
            m.onSwitch = onSwitch
        }
        val final = g.final(m.mode)
        val drag = m.drag
        val dragY = m.dragY
        // While held, the ball keeps to the place a let-go would choose, leaning a quarter of the way toward the finger.
        val cand = drag?.let { x ->
            if (dragY != null && dragY < g.rowTop - 4f && g.others.isNotEmpty()) {
                val n = g.rowAt(dragY)
                val i = g.others[n]
                val set = g.sets[i]
                val cs = g.centres(0f, set.size)
                val j = g.nearest(cs, set.size, x)
                Cand(cs[j], g.rowMid(n), i, set[j])
            } else if (g.items.isNotEmpty()) {
                val j = min(g.items.size - 1, g.nearest(final, 4, x))
                Cand(final[j], g.barMid, cur, g.items[j])
            } else null
        }
        val under = cand?.let { if (it.set == cur) it.key else "" }
        val ai = g.items.indexOf(active)
        val goalX = if (cand != null) cand.x + (drag - cand.x) * LEAN else final[max(0, ai)]
        val goalY = if (cand != null) cand.y + ((dragY ?: g.barMid) - cand.y) * LEAN else g.barMid
        val bx = remember { Animatable(goalX, 0.01f) }
        val by = remember { Animatable(goalY, 0.01f) }
        val sliding = drag != null
        // Sent to a place, its spring is as stiff as the way is short (one place over: tension 300).
        var trip by remember { mutableFloatStateOf(SLOT_PX) }
        LaunchedEffect(active, sliding) { if (!sliding) trip = max(8f, abs(goalX - bx.value)) }
        val tension = if (sliding) 300f else (300f * SLOT_PX / trip).coerceIn(90f, 700f)
        var width by remember { mutableFloatStateOf(w) }
        LaunchedEffect(goalX, tension) {
            // A new width (turned): there at once, not sent across.
            if (width != w) { width = w; bx.snapTo(goalX); return@LaunchedEffect }
            bx.animateTo(goalX, springOf(tension, 2 * 0.635f * sqrt(tension)))
        }
        LaunchedEffect(goalY) { by.animateTo(goalY, springOf(300f, 2 * 0.635f * sqrt(300f))) }
        val held by animateFloatAsState(if (sliding) 1f else 0f, springOf(420f, 16f, 0.001f), label = "held")
        val swap = m.swap
        val ballShown = ai >= 0 || sliding || swap?.key != null
        val ballAlpha by animateFloatAsState(if (ballShown) 1f else 0f, tween(200, easing = Ease.Css), label = "ball-alpha")
        val ballScale by animateFloatAsState(if (ballShown) 1f else 0.6f, tween(250, easing = Ease.Css), label = "ball-scale")
        // Landed: the bar is the chosen one, and the ball is put (not sent) where it is.
        if (swap != null && swap.done) LaunchedEffect(swap) {
            if (ai >= 0) bx.snapTo(final[ai])
            by.snapTo(g.barMid)
            if (m.swap === swap) m.swap = null
        }

        // What moves with the panel, read where it is drawn (not as the bar is composed).
        fun narrow() = 1f - min(0.05f, abs(m.o.velocity) * 0.008f)
        fun sx(x: Float) = w / 2 + (x - w / 2) * narrow()
        fun clipTop() = max(0f, OVER + g.reach * (1 - m.o.value))
        fun notchR() = (DROP / 2 + NOTCH_GAP) * kState.value
        fun notchY() = -LIFT + (1 - kState.value) * 10f
        fun swapAt(s: Swap): Pair<FloatArray, Float>? {
            val into = g.sets.getOrNull(s.i) ?: return null
            val t = (1 - m.o.value / s.from).coerceIn(0f, 1f)
            val lands = if (s.key != null) s.key in chatFamily else chatsPage
            val from = g.centres(0f, into.size)
            val to = g.centres(if (lands) 1f else 0f, into.size)
            val xs = FloatArray(into.size) { from[it] + (to[it] - from[it]) * t }
            return xs to (g.rowMid(s.n) + (g.barMid - g.rowMid(s.n)) * t)
        }

        val idle = if (dark) Color(0xFFD1D5DB) else Color(0xFF6B7280)
        val lit = if (dark) Color.White else Color(0xFF111827)
        val landing = if (dark) Color(0xFFE5E7EB) else Color(0xFF374151)
        val bg = C.bg
        val raised = Raised
        val accent = C.accent
        val shadowPaint = remember { android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG) }
        val navBottom = with(density) { WindowInsets.navigationBars.getBottom(density).toDp() }

        if (vis <= 0f && !shown) return@BoxWithConstraints
        Box(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 22.dp + navBottom).size(w.dp, g.panel.dp)
                .onPlaced { m.frame = it }
                .graphicsLayer {
                    translationY = (1 - vis) * 120.dp.toPx()
                    alpha = vis
                    compositingStrategy = CompositingStrategy.ModulateAlpha
                },
        ) {
            // The shadow of the glass, cast below it and to its sides only: none under it, none above its middle (so none
            // in the notch or over the edge 令 stands on).
            Box(Modifier.matchParentSize().drawBehind {
                val top = clipTop().dp.toPx()
                val gw = w * narrow()
                val left = (w - gw) / 2 * density.density
                val rect = android.graphics.RectF(left, top, left + gw.dp.toPx(), size.height)
                val r = RAD.dp.toPx()
                val out = android.graphics.Path().apply { addRoundRect(rect, r, r, android.graphics.Path.Direction.CW) }
                shadowPaint.color = Color.Black.copy(alpha = if (dark) 0.45f else 0.16f).toArgb()
                shadowPaint.maskFilter = BlurMaskFilter(density.maskRadius(6f), BlurMaskFilter.Blur.NORMAL)
                drawIntoCanvas { c ->
                    val nc = c.nativeCanvas
                    nc.save()
                    nc.clipRect(-size.width, top + r, size.width * 2, size.height + 80.dp.toPx())
                    nc.clipOutPath(out)
                    nc.translate(0f, 4.dp.toPx())
                    nc.drawRoundRect(rect, r, r, shadowPaint)
                    nc.restore()
                }
            })
            // The glass: exactly as tall as what shows of it, the notch cut out of it by a clip of its outline (nothing
            // blurred there); the source of what the ball and 令 frost too. The gestures are its.
            Box(
                Modifier
                    .layout { measurable, constraints ->
                        val gw = (w * narrow()).dp.roundToPx()
                        val top = clipTop().dp.roundToPx()
                        val h = (g.panel.dp.roundToPx() - top).coerceAtLeast(1)
                        val p = measurable.measure(Constraints.fixed(gw, h))
                        layout(constraints.maxWidth, constraints.maxHeight) { p.place(((w.dp.roundToPx() - gw) / 2), top) }
                    }
                    .onPlaced { m.glass = it }
                    .systemGestureExclusion()
                    .semantics { testTag = "bar-glass" }
                    .hazeSource(haze, zIndex = 1f)
                    .graphicsLayer {
                        val gw = size.width
                        shape = Glass(gw, size.height, gw / 2, notchY().dp.toPx(), notchR().dp.toPx(), density.density)
                        clip = true
                    }
                    .drawBehind { drawRect(raised.copy(alpha = 0.72f).compositeOver(bg)) }
                    .hazeEffect(haze) {
                        backgroundColor = bg
                        tints = listOf(HazeTint(raised.copy(alpha = 0.72f)))
                        blurRadius = GlassBlur
                        noiseFactor = 0f
                    }
                    .drawWithContent {
                        drawContent()
                        val path = outline(size.width, size.height, size.width / 2, notchY().dp.toPx(), notchR().dp.toPx(), density.density)
                        if (dark) rim(path, 0.14f, 0.3f, 0.16f) else rim(path, 0.35f, 0.8f, 0.45f)
                    }
                    .pointerInput(shown) {
                        if (!shown) return@pointerInput
                        awaitEachGesture {
                            val first = awaitFirstDown(requireUnconsumed = false)
                            m.down(m.at(first.position, this@pointerInput))
                            var ended = false
                            try {
                                while (true) {
                                    val change = awaitPointerEvent().changes.firstOrNull { it.id == first.id } ?: break
                                    val p = m.at(change.position, this@pointerInput)
                                    if (!change.pressed) { ended = true; change.consume(); m.up(p); break }
                                    if (m.move(p)) change.consume()
                                }
                            } catch (e: CancellationException) {
                                throw e
                            } finally {
                                if (!ended) m.lost()
                            }
                        }
                    },
            )
            // The notch's edge, lit as the glass's own rim.
            Box(Modifier.matchParentSize().drawBehind {
                val r = notchR()
                if (r <= 0.5f) return@drawBehind
                val gw = w * narrow()
                val p = Path()
                p.moveTo(0f, 0f)
                if (!notch(p, gw.dp.toPx() / 2, notchY().dp.toPx(), r.dp.toPx(), FILLET.dp.toPx())) return@drawBehind
                // Only what is below the edge: the notch's own outline, not the line along the edge to it.
                val edge = Path().apply { addPath(p, Offset(((w - gw) / 2).dp.toPx(), clipTop().dp.toPx())) }
                clipPath(Path().apply { addRect(Rect(0f, clipTop().dp.toPx() + 0.5f, size.width, size.height)) }) {
                    drawPath(edge, Color.White.copy(alpha = if (dark) 0.22f else 0.7f), style = Stroke(1.dp.toPx()))
                }
            })
            // 令: a new chat, accent glass in the notch; it grows out of the bar as the notch opens.
            // Its glass is what the ball frosts too, only while it is there (closed, its content would still be drawn there).
            val lingOn by remember { derivedStateOf { kState.value > 0.9f } }
            val lingOut by remember { derivedStateOf { kState.value > 0.001f } }
            if (lingOut) Box(
                Modifier
                    .offset { IntOffset(((w - DROP) / 2).dp.roundToPx(), (g.rowTop + notchY() - DROP / 2).dp.roundToPx()) }
                    .size(DROP.dp)
                    .graphicsLayer {
                        val k = kState.value
                        scaleX = max(0.001f, k); scaleY = scaleX
                        alpha = min(1f, k * 3)
                        compositingStrategy = CompositingStrategy.ModulateAlpha
                    }
                    .then(if (lingOn) Modifier.hazeSource(haze, zIndex = 2f) else Modifier)
                    .clip(CircleShape)
                    .drawBehind { drawRect(accent.copy(alpha = 0.86f).compositeOver(bg)) }
                    .hazeEffect(haze) {
                        backgroundColor = bg
                        tints = listOf(HazeTint(accent.copy(alpha = 0.86f)))
                        blurRadius = GlassBlur
                        noiseFactor = 0f
                    }
                    .drawWithContent {
                        drawContent()
                        val path = Path().apply { addOval(Rect(Offset.Zero, size)) }
                        rim(path, 0.4f, 0.75f, 0.4f)
                    }
                    .then(if (lingOn && shown) Modifier.clickable(onClick = onLing).semantics { contentDescription = lingLabel } else Modifier),
                contentAlignment = Alignment.Center,
            ) { IconIn(Icons.Ling, 40.dp, Color.White) }
            // The ball: under the places (they stay sharp over it), over 令.
            Box(
                Modifier
                    .layout { measurable, _ ->
                        val box = ball(g, swap, ::swapAt, bx, by, goalX, held, ballScale, ::sx)
                        val p = measurable.measure(Constraints.fixed(box.width.dp.roundToPx().coerceAtLeast(1), box.height.dp.roundToPx().coerceAtLeast(1)))
                        layout(p.width, p.height) { p.place(box.left.dp.roundToPx(), box.top.dp.roundToPx()) }
                    }
                    .graphicsLayer { alpha = ballAlpha; compositingStrategy = CompositingStrategy.ModulateAlpha }
                    .semantics { testTag = "bar-ball" }
                    .drawBehind {
                        val r = size.minDimension / 2
                        val rect = android.graphics.RectF(0f, 0f, size.width, size.height)
                        val out = android.graphics.Path().apply { addRoundRect(rect, r, r, android.graphics.Path.Direction.CW) }
                        shadowPaint.color = (if (dark) Color.Black.copy(alpha = 0.35f) else Color(55, 53, 45).copy(alpha = 0.2f)).toArgb()
                        shadowPaint.maskFilter = BlurMaskFilter(density.maskRadius(4f), BlurMaskFilter.Blur.NORMAL)
                        drawIntoCanvas { c ->
                            val nc = c.nativeCanvas
                            nc.save()
                            nc.clipOutPath(out)
                            nc.translate(0f, 1.dp.toPx())
                            nc.drawRoundRect(rect, r, r, shadowPaint)
                            nc.restore()
                        }
                    }
                    .clip(CircleShape)
                    .hazeEffect(haze) {
                        backgroundColor = bg
                        tints = listOf(HazeTint(Color.White.copy(alpha = if (dark) 0.12f else 0.42f)))
                        blurRadius = cssBlur(14f)
                        noiseFactor = 0f
                    }
                    .drawWithContent {
                        drawContent()
                        val r = size.minDimension / 2
                        val path = Path().apply { addRoundRect(RoundRect(Rect(Offset.Zero, size), CornerRadius(r))) }
                        if (dark) rim(path, 0.22f, 0.45f, 0.25f) else rim(path, 0.5f, 0.95f, 0.55f)
                    },
            )
            // The other bars, above this one, as the panel opens (each a row, every place as far from its row's edges as
            // the bar's are from the bar's).
            val panelOut by remember { derivedStateOf { m.mode || m.o.value > 0.001f } }
            if (panelOut && swap == null) Box(Modifier.matchParentSize().graphicsLayer {
                alpha = ((m.o.value - 0.35f) / 0.65f).coerceIn(0f, 1f)
                translationY = m.rowsShift(g).dp.toPx()
                compositingStrategy = CompositingStrategy.ModulateAlpha
            }) {
                g.others.forEachIndexed { n, i ->
                    val set = g.sets[i]
                    val cs = g.centres(0f, set.size)
                    set.forEachIndexed { j, key ->
                        val on = if (cand != null) cand.set == i && cand.key == key else active == key
                        Place(key, labelOf(key), on, idle, lit, dots[key], icon,
                            Modifier.offset { IntOffset((sx(cs[j]) - g.slot / 2).dp.roundToPx(), (OVER + n * ROW + 4f).dp.roundToPx()) }
                                .size(g.slot.dp, 48.dp),
                            role = Role.Button, onA11y = { m.pick(i, key) })
                    }
                }
            }
            // The bar's places, over the ball.
            if (swap == null) g.items.forEachIndexed { j, key ->
                Place(key, labelOf(key), (under ?: active) == key, idle, lit, dots[key], icon,
                    Modifier.offset { IntOffset((sx(g.centres(kState.value, g.items.size)[j]) - g.slot / 2).dp.roundToPx(), (g.rowTop + 4f).dp.roundToPx()) }
                        .size(g.slot.dp, 48.dp),
                    role = Role.Tab, onA11y = { onTab(key) })
            }
            // A bar being chosen: the stack of bars slides down inside the closing glass, the chosen one into the bar's
            // place, what is not chosen cut off by the glass's edge. Nothing fades.
            if (swap != null) Box(Modifier.matchParentSize().graphicsLayer { shape = Window(clipTop().dp.toPx(), RAD.dp.toPx()); clip = true }) {
                fun shift() = swapAt(swap)?.let { (_, y) -> y - g.rowMid(swap.n) } ?: 0f
                g.others.forEachIndexed { n, i ->
                    if (i == swap.i) return@forEachIndexed
                    val set = g.sets[i]
                    val cs = g.centres(0f, set.size)
                    set.forEachIndexed { j, key -> Flying(key, idle, icon) { IntOffset(sx(cs[j]).dp.roundToPx(), (g.rowMid(n) + shift()).dp.roundToPx()) } }
                }
                g.sets.getOrNull(swap.i)?.forEachIndexed { j, key ->
                    Flying(key, landing, icon) {
                        val (xs, y) = swapAt(swap) ?: return@Flying IntOffset.Zero
                        IntOffset(sx(xs[j]).dp.roundToPx(), y.dp.roundToPx())
                    }
                }
                g.items.forEachIndexed { j, key ->
                    Flying(key, idle, icon) { IntOffset(sx(g.centres(kState.value, g.items.size)[j]).dp.roundToPx(), (g.barMid + shift()).dp.roundToPx()) }
                }
            }
        }
    }
}

/** Where the ball is drawn (dp in the panel's frame): its box, stretched by its speed toward where it goes, or riding a bar being chosen. */
private class BallBox(val left: Float, val top: Float, val width: Float, val height: Float)

private fun ball(
    g: Geo, swap: Swap?, swapAt: (Swap) -> Pair<FloatArray, Float>?, bx: Animatable<Float, AnimationVector1D>, by: Animatable<Float, AnimationVector1D>,
    goalX: Float, held: Float, shown: Float, sx: (Float) -> Float,
): BallBox {
    val scale = (1 + 0.06f * held) * shown
    // A bar being chosen with a place tapped in it: the ball rides on that place down into the bar.
    if (swap?.key != null) {
        val into = g.sets.getOrNull(swap.i)
        val j = into?.indexOf(swap.key) ?: -1
        val at = swapAt(swap)
        if (at != null && j >= 0) {
            val d = BALL * scale
            return BallBox(sx(at.first[j]) - d / 2, at.second - d / 2, d, d)
        }
    }
    val x = bx.value
    val v = if (abs(goalX - x) < 0.5f) 0f else bx.velocity / 60f
    val stretch = min(MAX_STRETCH, abs(v) * 1.6f)
    val w = BALL + stretch
    val h = BALL - min(6f, stretch * 0.2f)
    // Its leading edge reaches ahead, toward where it goes.
    val left = x - BALL / 2 - (if (v < 0) stretch else 0f)
    val cx = sx(left + w / 2)
    val cy = by.value
    val sw = w * scale
    val sh = h * scale
    return BallBox(cx - sw / 2, cy - sh / 2, sw, sh)
}

/** A place on the bar or in the panel: its icon in the middle of its slot (lit when it is the one), its dot at the icon's top right. */
@Composable
private fun Place(
    key: String, label: String, on: Boolean, idle: Color, lit: Color, dot: Color?, icon: @Composable (String, Color) -> Unit,
    modifier: Modifier, role: Role, onA11y: () -> Unit,
) {
    val tint by animateColorAsState(if (on) lit else idle, tween(300, easing = Ease.Css), label = "place")
    Box(
        // Its taps are the glass's (the gestures read where they land): here only what a screen reader says and does.
        modifier.semantics {
            contentDescription = label
            this.role = role
            selected = on
            testTag = "bar-place-$key"
            onClick { onA11y(); true }
        },
        contentAlignment = Alignment.Center,
    ) {
        icon(key, tint)
        if (dot != null) Box(Modifier.align(Alignment.Center).offset(13.5.dp, (-12.5).dp).size(7.dp).clip(CircleShape).drawBehind { drawRect(dot) })
    }
}

/** A place's icon as a bar is chosen, its middle where `at` says (px). */
@Composable
private fun Flying(key: String, tint: Color, icon: @Composable (String, Color) -> Unit, at: Density.() -> IntOffset) {
    Box(Modifier.offset { at().let { IntOffset(it.x - 14.dp.roundToPx(), it.y - 14.dp.roundToPx()) } }.size(28.dp), contentAlignment = Alignment.Center) { icon(key, tint) }
}
