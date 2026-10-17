// The phone's bottom bar (下方栏), as the prototype agreed with the user has it (session c-1c78bb4403's
// proto/vbar/vbar.jsx `Bar`, frosted only): a floating capsule of the places of one bar; a frosted ball over the place
// shown, which travels on a spring stretched by its speed and goes where a finger takes it; the page's primary action
// standing in a notch cut out of the bar's top (令, a new chat, on the chats' pages; a "+" on a page that adds
// something); with more than one bar, the glass grows upward into a panel of the other bars, one row each, snapping
// open once a finger on the bar is drawn high enough and closed once it comes back down (leaning toward the finger, as
// the ball does to a place), and a bar chosen there slides down into the bar's place. All of it moves on springs
// stepped a frame at a time by one loop (BarModel), retargeted by the finger as it goes, nothing playing out on its own.
// Everything is glass of one source (Haze): the pages under it, frosted by the bar's glass, the action and the ball;
// the action for the ball too.
package fail.still.android.ui

import android.graphics.BlurMaskFilter
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.LinearEasing
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
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.MotionDurationScale
import kotlinx.coroutines.currentCoroutineContext
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
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
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
import kotlinx.coroutines.flow.first
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

/** The panel snaps open once a finger is this far over the bar's top, and closed once it is back under `CLOSES`. */
private const val OPENS = 24f
private const val CLOSES = 16f

/**
 * A page's primary action, which the notch holds on a place's top page: `key` tells one from another (the icon swaps
 * between two, the notch staying open), `label` is what a screen reader says, `run` what a tap does (the page's latest).
 */
@Stable
class BarAction(val key: String, val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, run: () -> Unit) {
    var run: () -> Unit = run
}

/** The bar's layout for what it holds, `w` wide (dp); `notched`: the page shown has an action in the notch. */
private class Geo(val w: Float, val sets: List<List<String>>, val cur: Int, val active: String?, val notched: Boolean) {
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
    /** Where the bar's places will be, notch open on a page with an action, the panel closed. */
    fun final(mode: Boolean) = centres(if (notched && !mode) 1f else 0f, items.size)
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

/**
 * A bar chosen in the panel, sliding down into the bar's place: which, its row, how open the panel was, the place tapped;
 * `laid`: the bars as they were then, which the stack sliding down is laid out by to its end (the chosen bar is the one
 * in view from the moment it is chosen); the rows' fade and offset then (`alpha`, `drop`) and how lit each place was
 * (`lit`, by slot), which the stack starts from; `still`: chosen from a panel at rest (its first frame is as it was).
 */
private class Swap(
    val i: Int, val n: Int, val from: Float, val key: String?, val laid: Geo,
    val alpha: Float, val drop: Float, val lit: Map<String, Float>, var still: Boolean,
)

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
 * of radius `f` (each touching the edge and the circle). Adds it to `p` from the edge's left meeting to its right (`alone`:
 * starting there, not along the edge to it), or nothing when there is none (closed); answers whether it did.
 */
private fun notch(p: Path, cx: Float, c0: Float, r: Float, f: Float, alone: Boolean = false): Boolean {
    if (r <= 0.5f) return false
    val dy = f - c0
    val reach = (r + f) * (r + f) - dy * dy
    if (c0 + r <= 0.5f || reach <= 0f) return false
    val xf = sqrt(reach)
    val l = cx - xf
    val rr = cx + xf
    val deg = (180.0 / Math.PI).toFloat()
    if (alone) p.moveTo(l, 0f) else p.lineTo(l, 0f)
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
 * A piece of glass's outline and its rim's two lit edges, made once for each shape it takes (`key`): the glass is drawn
 * again with every frame of what it frosts (a list scrolling under it), and cutting the edges (Path.op) every time was
 * much of what a frame took.
 */
private class Rim {
    private var key: Any? = null
    var path = Path(); private set
    val lit = Path()
    val back = Path()

    fun of(key: Any, px: Float, make: () -> Path): Rim {
        if (key == this.key) return this
        this.key = key
        path = make()
        lit.reset(); lit.op(path, Path().apply { addPath(path, Offset(px, px)) }, PathOperation.Difference)
        back.reset(); back.op(path, Path().apply { addPath(path, Offset(-px, -px)) }, PathOperation.Difference)
        return this
    }
}

/**
 * Glass's lit rim, as inset shadows on the web: a hairline all round inside its edge (`edge`), light along its top and
 * left (`lit`) and less along its foot and right (`back`).
 */
private fun DrawScope.rim(r: Rim, edge: Float, lit: Float, back: Float) {
    val px = 0.5.dp.toPx()
    clipPath(r.path) { drawPath(r.path, Color.White.copy(alpha = edge), style = Stroke(width = 2 * px)) }
    drawPath(r.lit, Color.White.copy(alpha = lit))
    drawPath(r.back, Color.White.copy(alpha = back))
}

/** Room round the bar for its shadow, in the layer the shadow is kept in. */
private const val SHADOW_PAD = 32f

/** A CSS blur's deviation (dp) as BlurMaskFilter's radius (px). */
private fun Density.maskRadius(sigma: Float) = ((sigma.dp.toPx() - 0.5f) / 0.57735f).coerceAtLeast(0.1f)

/**
 * One number on a spring (react-spring's tension and friction, mass 1), stepped a frame at a time by the bar's loop
 * (BarModel.run), as the web's Spring: no motion of its own that plays out, only what each frame makes of it. `rest`: how
 * near its target (and how slow, ten times that a second) it is still.
 */
@Stable
private class BarSpring(start: Float, var tension: Float, var friction: Float, private val rest: Float = 0.001f) {
    var value by mutableFloatStateOf(start)
    /** Its speed (a second). */
    var velocity by mutableFloatStateOf(0f)
    var target by mutableFloatStateOf(start)
        private set
    val moving: Boolean get() = velocity != 0f || value != target

    fun to(target: Float, tension: Float = this.tension, friction: Float = this.friction) {
        this.target = target
        this.tension = tension
        this.friction = friction
    }

    /** There at once, still (where a finger puts it). */
    fun jump(at: Float) {
        value = at
        target = at
        velocity = 0f
    }

    /** A frame of `dt` seconds; `instant` (motion reduced: ui/Motion.kt), at its target at once. */
    fun step(dt: Float, instant: Boolean = false) {
        if (instant) return jump(target)
        var x = value
        var v = velocity
        var left = dt
        // In steps of 4 ms at most: steady however stiff.
        while (left > 0f) {
            val h = min(left, 0.004f)
            left -= h
            v += (-tension * (x - target) - friction * v) * h
            x += v * h
        }
        if (abs(x - target) < rest && abs(v) < rest * 10) { x = target; v = 0f }
        value = x
        velocity = v
    }
}

/** One number gliding to where it is sent over a time on a curve (a CSS transition's way), stepped by the bar's loop. */
@Stable
private class Glide(start: Float) {
    var value by mutableFloatStateOf(start)
    var target by mutableFloatStateOf(start)
        private set
    private var from = start
    private var t = 0f
    private var span = 0f
    private var easing: Easing = LinearEasing
    val moving: Boolean get() = value != target

    /** Sent to `target` from where it is now, over `ms` (nothing new when that is where it is going already). */
    fun to(target: Float, ms: Int, easing: Easing) {
        if (target == this.target) return
        from = value
        this.target = target
        t = 0f
        span = ms / 1000f
        this.easing = easing
    }

    fun jump(at: Float) {
        value = at
        target = at
    }

    fun step(dt: Float, instant: Boolean = false) {
        if (instant) return jump(target)
        t += dt
        val p = if (span <= 0f) 1f else min(1f, t / span)
        value = if (p >= 1f) target else from + (target - from) * easing.transform(p)
    }
}

/**
 * What the bar keeps between frames and what its gestures do (vbar.jsx's refs and handlers; the web's mobile/Bar.tsx
 * the same rules): every motion of the bar is a number here (the panel's openness, the notch's, the ball, the bar
 * shown, the notch's icon swapping, the places lit), stepped by one loop a frame at a time while any moves (`run`).
 * The panel snaps, as the ball does to a place: while a finger has it, it is open once the finger is high enough over
 * the bar and closed once it is back down (a little apart, so it does not flicker between), leaning a quarter of the way
 * toward where the finger draws it, on its springs, retargeted at every move from where it is; let go, it stays as the
 * finger left it. What is chosen (a place, a bar) is chosen at the gesture, not once a motion has ended.
 */
@Stable
private class BarModel(shown: Boolean, notched: Boolean, ballShown: Boolean) {
    /** The panel of the other bars open (or opening, or the finger's). */
    var mode by mutableStateOf(false)
    /** How open the panel is: 0 the bar, 1 the panel (past 1 a little as it overshoots or a finger draws it on). */
    val o = BarSpring(0f, 260f, 17f)
    /** The notch as the place has it (open on a page with an action), a spring as the place changes. */
    val k = BarSpring(if (notched) 1f else 0f, 300f, 30f)
    /** The ball held by a finger (it grows a little). */
    val held = BarSpring(0f, 420f, 16f)
    /** The bar shown (on a place's top page) or gone down out of the way. */
    val vis = Glide(if (shown) 1f else 0f)
    val ballAlpha = Glide(if (ballShown) 1f else 0f)
    val ballScale = Glide(if (ballShown) 1f else 0.6f)
    /** The notch's icon, the one it replaces as it swaps (null: none going), and how far the swap is (0 to 1, 300 ms). */
    var icon by mutableStateOf<ImageVector?>(null)
    var iconWas by mutableStateOf<ImageVector?>(null)
    val iconSwap = Glide(1f)
    /** Each place drawn (by its slot, `bar:<place>` or `row:<place>`): how lit it is. */
    val tints = mutableStateMapOf<String, Glide>()
    var ball: BallMotion? = null

    /** The finger's place while it has the ball (dp in the panel's frame); its height only once the panel is the finger's. */
    var drag by mutableStateOf<Float?>(null)
    var dragY by mutableStateOf<Float?>(null)
    var swap by mutableStateOf<Swap?>(null)

    // The latest of what the bar is told (set as it is drawn).
    var geo: Geo? = null
    var onTab: (String) -> Unit = {}
    var onSwitch: (Int, String?) -> Unit = { _, _ -> }
    var glass: LayoutCoordinates? = null
    var frame: LayoutCoordinates? = null

    // The finger: where it went down, whether it has the ball (moved past SLOP) and the panel (`holds`; from `o0`, the
    // panel as open as that when it went down, `fromOpen`: it had it from there, so no slop to take up), which way the
    // panel snaps (`open`). `waits`: it went down as a bar chosen was landing, and is the finger's only once it has.
    private var dragging = false
    private var holds = false
    private var fromOpen = false
    private var open = false
    private var waits = false
    private var x0 = 0f
    private var y0 = 0f
    private var o0 = 0f

    /** The notch's openness as drawn: as its place has it, closed as far as the panel is drawn up (fully by half open). */
    fun kNow(): Float = k.value * (1f - (2f * o.value).coerceIn(0f, 1f))

    val moving: Boolean
        get() = o.moving || k.moving || held.moving || vis.moving || ballAlpha.moving || ballScale.moving || iconSwap.moving ||
            iconWas != null || swap != null || ball?.resting == false || tints.values.any { it.moving }

    /**
     * The loop: a frame at a time while anything moves, asleep otherwise, on the app's clock (ui/Motion.kt: its
     * MotionDurationScale, as the web's `if (instant) spring.jump(spring.target)`): with motion reduced each frame puts
     * everything where it is going.
     */
    suspend fun run() {
        while (true) {
            snapshotFlow { moving }.first { it }
            var last = -1L
            while (moving) {
                val scale = currentCoroutineContext()[MotionDurationScale]?.scaleFactor ?: 1f
                withFrameNanos { now ->
                    val dt = if (last < 0) 1 / 60f else ((now - last) / 1e9f).coerceIn(0f, 0.05f)
                    step(if (scale > 0f) dt / scale else dt, instant = scale <= 0f)
                    last = now
                }
            }
        }
    }

    fun step(dt: Float, instant: Boolean = false) {
        val s = swap
        // The frame a bar is chosen from a panel at rest, the stack is drawn as the rows were: it slides from the next.
        if (s != null && s.still) s.still = false else if (o.moving) o.step(dt, instant)
        for (sp in arrayOf(k, held)) if (sp.moving) sp.step(dt, instant)
        for (g in arrayOf(vis, ballAlpha, ballScale, iconSwap)) if (g.moving) g.step(dt, instant)
        for (g in tints.values) if (g.moving) g.step(dt, instant)
        // Riding a bar chosen: the ball goes on its spring after the place it rides, from wherever it was.
        val b = ball
        if (b != null && s != null) ride(s)?.let { b.goX = it.x; b.goY = it.y; b.tension = 300f }
        if (b != null && !b.resting) b.step(dt, instant)
        if (iconWas != null && !iconSwap.moving) iconWas = null
        // A bar chosen: landed, the stack is where the bar is, drawn as the bar will be; it goes in this same frame.
        if (s != null && !o.moving && o.value <= 0f) swap = null
    }

    /** How far a bar chosen has come down: 0 as the panel was, 1 landed. */
    fun t(s: Swap) = (1 - o.value / s.from).coerceIn(0f, 1f)

    /** The stack's rows' look as they come down: from the rows' fade and offset as the bar was chosen, to none. */
    fun rowAlpha(s: Swap) = s.alpha + (1 - s.alpha) * t(s)
    fun rowDrop(s: Swap) = s.drop * (1 - t(s))

    /** The chosen bar's places' middles and their height (dp in the panel's frame) as it comes down. */
    fun swapAt(s: Swap): Pair<FloatArray, Float>? {
        val sg = s.laid
        val into = sg.sets.getOrNull(s.i) ?: return null
        val t = t(s)
        val from = sg.centres(0f, into.size)
        if (t <= 0f) return from to sg.rowMid(s.n)
        val to = sg.centres(kNow(), into.size)
        // Landed: exactly where the bar's places are drawn.
        if (t >= 1f) return to to sg.barMid
        val xs = FloatArray(into.size) { from[it] + (to[it] - from[it]) * t }
        return xs to (sg.rowMid(s.n) + (sg.barMid - sg.rowMid(s.n)) * t)
    }

    /** Where the place tapped in a bar chosen is as it comes down (null: none tapped). */
    private fun ride(s: Swap): Offset? {
        val key = s.key ?: return null
        val j = s.laid.sets.getOrNull(s.i)?.indexOf(key) ?: return null
        if (j < 0) return null
        val (xs, y) = swapAt(s) ?: return null
        return Offset(xs[j], y + rowDrop(s))
    }

    /** The notch's icon: another one swaps in (the circle staying), as it is when the notch is closed (nothing to see). */
    fun showIcon(next: ImageVector?, out: Boolean) {
        if (next == null || next == icon) return
        if (icon == null || !out) {
            icon = next
            iconWas = null
            iconSwap.jump(1f)
            return
        }
        iconWas = icon
        icon = next
        iconSwap.jump(0f)
        iconSwap.to(1f, 300, LinearEasing)
    }

    fun openPanel(open: Boolean) {
        mode = open
        // From where it is, at the speed it has.
        if (open) o.to(1f, 260f, 17f) else o.to(0f, 320f, 26f)
    }

    /** Where a touch on the glass is in the panel's frame (dp). */
    fun at(local: Offset, density: Density): Offset {
        val g = glass
        val f = frame
        val p = if (g != null && f != null && g.isAttached && f.isAttached) f.localPositionOf(g, local) else local
        return Offset(p.x / density.density, p.y / density.density)
    }

    fun down(p: Offset) {
        // A bar chosen landing: it lands on its own spring, untouched; the finger is the finger's once it has.
        waits = swap != null
        dragging = false
        holds = false
        if (waits) return
        x0 = p.x
        y0 = p.y
        // The panel open, opening or closing: the finger has it from here, not stopping it (it goes on as it was going
        // until the finger moves).
        val o0 = o.value
        holds = geo?.multi == true && (o0 > 0.02f || (o.moving && o.target > 0f))
        fromOpen = holds
        open = o.target > 0.5f
        if (holds) mode = true
        this.o0 = o0
    }

    /** One stroke: a finger set on the bar (or the open panel) and moved any way takes the ball; up, the panel. */
    fun move(p: Offset): Boolean {
        val g = geo ?: return false
        if (waits) {
            if (swap != null) return true
            // Landed, the finger still down: a stroke of its own from here.
            down(p)
        }
        if (!dragging && hypot(p.x - x0, p.y - y0) > SLOP) dragging = true
        if (g.multi && (holds || dragging)) {
            // How open the finger draws it (1 to 1, from where it was).
            val raw = o0 + (y0 - p.y - (if (fromOpen) 0f else SLOP)) / g.reach
            if (!holds && raw > 0f) { holds = true; mode = true }
            if (holds) {
                // Open once the finger is 24 over the bar, closed once it is back under 16; a quarter of the way toward
                // where the finger draws it, as the ball leans toward the finger.
                val over = g.rowTop - p.y
                if (!open && over > OPENS) open = true else if (open && over < CLOSES) open = false
                val snap = if (open) 1f else 0f
                val goal = (snap + LEAN * (raw - snap)).coerceIn(0f, 1.1f)
                if (open) o.to(goal, 260f, 17f) else o.to(goal, 320f, 26f)
            }
        }
        if (!dragging) return holds
        drag = p.x
        // The ball goes on into the rows of the other bars once the finger has the panel open (closed, it keeps to the bar).
        dragY = if (g.multi && holds && open) p.y.coerceIn(g.topY, g.barMid) else null
        return true
    }

    fun up(p: Offset) {
        val g = geo ?: return lost()
        // Lifted as a bar chosen was landing (or before the finger was its own): nothing.
        if (waits) { waits = false; return }
        val had = holds
        holds = false
        if (!dragging) {
            // A tap; the panel's and nothing tapped there: it goes on as it was going.
            if (!tap(p) && had) mode = o.target > 0.5f
            return
        }
        dragging = false
        drag = null
        dragY = null
        if (had) {
            letGo(g, p)
            return
        }
        if (g.items.isEmpty()) return
        val j = min(g.items.size - 1, g.nearest(g.final(mode), 4, p.x))
        if (mode) openPanel(false)
        if (g.items[j] != g.active) onTab(g.items[j])
    }

    /**
     * The panel let go: on a place in the rows or above them, the panel open (0.85), that bar and that place (the top row's,
     * above); elsewhere (on the bar, or the panel not yet open) it ends as the finger left it, open or closed, the lean gone
     * (let go on the bar, closed: the place under the finger too).
     */
    private fun letGo(g: Geo, p: Offset) {
        // Over the rows, or above the panel (gone up too far: the top row's place the ball keeps to there, as on the web;
        // it was let go open with nothing chosen, and the bar could not be switched).
        val inRows = p.y < g.rowTop - 4f && g.others.isNotEmpty()
        if (inRows && o.value >= 0.85f) {
            val i = g.others[g.rowAt(p.y)]
            val set = g.sets[i]
            pick(i, set[g.nearest(g.centres(0f, set.size), set.size, p.x)])
            return
        }
        val j = if (p.y >= g.rowTop - 4f && g.items.isNotEmpty()) min(g.items.size - 1, g.nearest(g.final(mode), 4, p.x)) else -1
        openPanel(open)
        if (!open && j >= 0 && g.items[j] != g.active) onTab(g.items[j])
    }

    /** The gesture gone without its end being heard: as if let go where it was, nothing chosen. */
    fun lost() {
        waits = false
        dragY = null
        if (dragging) { dragging = false; drag = null }
        if (holds) { holds = false; openPanel(open) }
    }

    /** A tap (moved less than SLOP): a place on the bar; with the panel open, a row (that bar) or a place in it. */
    private fun tap(p: Offset): Boolean {
        val g = geo ?: return false
        if (mode && p.y < g.rowTop) {
            if (o.value <= 0.6f || g.others.isEmpty()) return false
            val n = floor((p.y - OVER - rowsShift(g)) / ROW).toInt()
            if (n !in g.others.indices) return false
            val i = g.others[n]
            val set = g.sets[i]
            val cs = g.centres(0f, set.size)
            val j = g.nearest(cs, set.size, p.x)
            pick(i, if (abs(cs[j] - p.x) <= g.slot / 2) set[j] else null)
            return true
        }
        // The bar's places only on the bar (not on a panel going, above it).
        if (g.items.isEmpty() || p.y < g.rowTop - 4f) return false
        val now = g.centres(kNow(), g.items.size)
        val j = g.nearest(now, g.items.size, p.x)
        if (abs(now[j] - p.x) > g.slot / 2) return false
        if (mode) openPanel(false)
        onTab(g.items[j])
        return true
    }

    /** How far the rows are from where they rest as the panel opens: a little low, then up with its overshoot. */
    fun rowsShift(g: Geo): Float {
        val v = o.value
        return (1 - min(1f, v)) * 14f - max(0f, v - 1) * g.reach
    }

    /** How the rows show as the panel opens: they come in over 0.35 to 1. */
    fun rowsAlpha(): Float = ((o.value - 0.35f) / 0.65f).coerceIn(0f, 1f)

    /**
     * Another bar chosen (and a place in it, when one was tapped): it is the bar, and the place opens, now; the panel
     * closes like a window over a stack of bars, the chosen one sliding down into the bar's place, as the panel's
     * openness goes to 0 from where it is. The stack starts as the rows and the bar were drawn (their fade, offset and
     * how lit each place was), and comes to the bar's look as it lands.
     */
    fun pick(i: Int, key: String?) {
        if (swap != null) return
        val g = geo ?: return
        val n = g.others.indexOf(i)
        if (n < 0) return
        val lit = HashMap<String, Float>()
        for ((id, shade) in tints) lit[id] = shade.value
        swap = Swap(i, n, max(0.2f, o.value), key, Geo(g.w, g.sets, g.cur, null, false), rowsAlpha(), rowsShift(g), lit, still = !o.moving)
        mode = false
        o.to(0f, 200f, 28f)
        onSwitch(i, key)
    }
}

/**
 * The bottom bar over the pages that `haze` is the source of. `sets`: the bars (`cur` the one in view); `active`: the
 * place shown (null: none); `action`: its page's primary action, in the notch (null: none, the notch closed); `notches`:
 * whether a place's page has one (a bar chosen with a place in it lands with the notch as that place will have it);
 * `shown`: on a place's top page, with nothing over it. `dots`: a place's status dot and its colour; `icon`: a place's
 * icon in a colour.
 */
@Composable
fun BottomBar(
    sets: List<List<String>>, cur: Int, active: String?, action: BarAction?, shown: Boolean, haze: HazeState,
    dots: Map<String, Color>, labelOf: (String) -> String, notches: (String) -> Boolean,
    icon: @Composable (String, Color) -> Unit,
    onTab: (String) -> Unit, onSwitch: (Int, String?) -> Unit,
) {
    val first = sets.getOrNull(cur).orEmpty()
    val m = remember { BarModel(shown, action != null, active != null && active in first) }
    val density = LocalDensity.current
    val dark = C.dark
    // The one loop that draws every motion of the bar, a frame at a time while any moves.
    LaunchedEffect(m) { m.run() }
    SideEffect { m.vis.to(if (shown) 1f else 0f, if (shown) 380 else 300, Ease.Arrive) }
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
        // 22 in from either side, as from the foot: the ball (6 past the bar) as far from the screen's sides as from its foot.
        val w = maxWidth.value - 44f
        // A bar being chosen with a place in it: the notch already as that place will have it (no action coming up only to go).
        val landsOn = m.swap?.key?.let(notches)
        val g = Geo(w, sets, cur, active, landsOn ?: (action != null))
        SideEffect {
            m.geo = g
            m.onTab = onTab
            m.onSwitch = onSwitch
            // The notch: open on a page with an action (a spring as the place changes); the panel drawn up closes it
            // as far as it is drawn (kNow), not on its own.
            m.k.to(if (g.notched) 1f else 0f)
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
        val ball = remember { BallMotion(goalX, goalY).also { m.ball = it } }
        val sliding = drag != null
        // Sent to a place, its spring is as stiff as the way is short (one place over: tension 300).
        var trip by remember { mutableFloatStateOf(SLOT_PX) }
        LaunchedEffect(active, sliding) { if (!sliding) trip = max(8f, abs(goalX - ball.x)) }
        val tension = if (sliding) 300f else (300f * SLOT_PX / trip).coerceIn(90f, 700f)
        var width by remember { mutableFloatStateOf(w) }
        val swap = m.swap
        val ballShown = ai >= 0 || sliding || swap?.key != null
        // Where the ball and its look go: one spring each way toward where it is sent (a goal moved meanwhile, by a
        // finger every frame, changes where it goes on the way), stepped by the bar's loop with the rest.
        SideEffect {
            // Riding a bar chosen, the bar's loop sends it (after the place it rides).
            if (swap?.key == null) {
                ball.goX = goalX
                ball.goY = goalY
                ball.tension = tension
            }
            // A new width (turned): there at once, not sent across.
            if (width != w) { width = w; ball.snapTo(goalX, ball.y) }
            m.held.to(if (sliding) 1f else 0f)
            m.ballAlpha.to(if (ballShown) 1f else 0f, 200, Ease.Css)
            m.ballScale.to(if (ballShown) 1f else 0.6f, 250, Ease.Css)
        }

        // What moves with the panel, read where it is drawn (not as the bar is composed).
        fun clipTop() = max(0f, OVER + g.reach * (1 - m.o.value))
        fun notchR() = (DROP / 2 + NOTCH_GAP) * m.kNow()
        // The action and its notch shrink about one middle, which comes up to the bar's edge: the notch closes to nothing, no dent left.
        fun notchY() = -LIFT * m.kNow()
        // The stack of bars as a bar is chosen, laid out by the bars as they were when it was (the bar in view is the
        // chosen one from then: laid out by that, the bar left was drawn over the chosen one's places, a flash). The
        // chosen bar lands where the bar's places are drawn as the notch is then (kNow): when the panel is closed, the
        // stack is the bar, place for place.
        val laid = swap?.laid

        val idle = if (dark) Color(0xFFD1D5DB) else Color(0xFF6B7280)
        val lit = if (dark) Color.White else Color(0xFF111827)
        val bg = C.bg
        val raised = Raised
        val accent = C.accent
        val shadowPaint = remember { android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG) }
        val glassRim = remember { Rim() }
        val actionRim = remember { Rim() }
        val ballRim = remember { Rim() }
        val fadePaint = remember { android.graphics.Paint().apply { xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN) } }
        val navBottom = with(density) { WindowInsets.navigationBars.getBottom(density).toDp() }

        val gone by remember { derivedStateOf { m.vis.value <= 0f } }
        if (gone && !shown) return@BoxWithConstraints
        Box(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 22.dp + navBottom).size(w.dp, g.panel.dp)
                .onPlaced { m.frame = it }
                .graphicsLayer {
                    val vis = m.vis.value
                    translationY = (1 - vis) * 120.dp.toPx()
                    alpha = vis
                    compositingStrategy = CompositingStrategy.ModulateAlpha
                },
        ) {
            // The shadow of the glass, cast below it and to its sides only: none under it, none above its top (so none in
            // the notch or over the edge the action stands on), coming in down its rounded ends.
            // Kept in a layer of its own (with room round it for the blur), drawn again only as the panel moves: blurred
            // anew with every frame, it cost each frame of a list scrolling under the bar.
            Box(Modifier.matchParentSize()
                .layout { measurable, constraints ->
                    val pad = SHADOW_PAD.dp.roundToPx()
                    val p = measurable.measure(Constraints.fixed(constraints.maxWidth + 2 * pad, constraints.maxHeight + 2 * pad))
                    layout(constraints.maxWidth, constraints.maxHeight) { p.place(-pad, -pad) }
                }
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawBehind { val pad = SHADOW_PAD.dp.toPx(); val size = Size(size.width - 2 * pad, size.height - 2 * pad); translate(pad, pad) {
                val top = clipTop().dp.toPx()
                val gw = w
                val left = (w - gw) / 2 * density.density
                val rect = android.graphics.RectF(left, top, left + gw.dp.toPx(), size.height)
                val r = RAD.dp.toPx()
                val out = android.graphics.Path().apply { addRoundRect(rect, r, r, android.graphics.Path.Direction.CW) }
                shadowPaint.color = Color.Black.copy(alpha = if (dark) 0.45f else 0.16f).toArgb()
                shadowPaint.maskFilter = BlurMaskFilter(density.maskRadius(6f), BlurMaskFilter.Blur.NORMAL)
                drawIntoCanvas { c ->
                    val nc = c.nativeCanvas
                    val foot = size.height + 80.dp.toPx()
                    val layer = nc.saveLayer(-size.width, top, size.width * 2, foot, null)
                    nc.clipOutPath(out)
                    nc.translate(0f, 4.dp.toPx())
                    nc.drawRoundRect(rect, r, r, shadowPaint)
                    nc.translate(0f, -4.dp.toPx())
                    // Faded in down its rounded ends, from nothing at its top: no step where it begins.
                    fadePaint.shader = android.graphics.LinearGradient(0f, top, 0f, top + r, 0, android.graphics.Color.BLACK, android.graphics.Shader.TileMode.CLAMP)
                    nc.drawRect(-size.width, top, size.width * 2, foot, fadePaint)
                    nc.restoreToCount(layer)
                }
            } })
            // The glass: exactly as tall as what shows of it, the notch cut out of it by a clip of its outline (nothing
            // blurred there). Not a source of what the ball frosts: the ball frosts the pages as the glass does, with the
            // glass's tint under its own (blurring the glass's blur again was a whole blur more in every frame of a list
            // scrolling under the bar, for next to no difference). The gestures are its.
            Box(
                Modifier
                    .layout { measurable, constraints ->
                        val gw = (w).dp.roundToPx()
                        val top = clipTop().dp.roundToPx()
                        val h = (g.panel.dp.roundToPx() - top).coerceAtLeast(1)
                        val p = measurable.measure(Constraints.fixed(gw, h))
                        layout(constraints.maxWidth, constraints.maxHeight) { p.place(((w.dp.roundToPx() - gw) / 2), top) }
                    }
                    .onPlaced { m.glass = it }
                    .systemGestureExclusion()
                    .semantics { testTag = "bar-glass" }
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
                        val cy = notchY().dp.toPx()
                        val r = notchR().dp.toPx()
                        val shape = glassRim.of(Glass(size.width, size.height, size.width / 2, cy, r, density.density), 0.5.dp.toPx()) { outline(size.width, size.height, size.width / 2, cy, r, density.density) }
                        if (dark) rim(shape, 0.14f, 0.3f, 0.16f) else rim(shape, 0.35f, 0.8f, 0.45f)
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
                val gw = w
                // The notch's own outline alone. (It was drawn from the bar's left end along its edge, the half of the
                // stroke below the edge showing: a line over the ball and past the bar's rounded end.)
                val p = Path()
                if (!notch(p, gw.dp.toPx() / 2, notchY().dp.toPx(), r.dp.toPx(), FILLET.dp.toPx(), alone = true)) return@drawBehind
                val edge = Path().apply { addPath(p, Offset(((w - gw) / 2).dp.toPx(), clipTop().dp.toPx())) }
                clipPath(Path().apply { addRect(Rect(0f, clipTop().dp.toPx() + 0.5f, size.width, size.height)) }) {
                    drawPath(edge, Color.White.copy(alpha = if (dark) 0.22f else 0.7f), style = Stroke(1.dp.toPx()))
                }
            })
            // The page's primary action (令, a new chat; a "+"): accent glass in the notch; it grows out of the bar as the
            // notch opens. Its glass is what the ball frosts too, only while it is there (closed, its content would still
            // be drawn there). Closing, it keeps the last action's icon as it shrinks.
            val actionOn by remember { derivedStateOf { m.kNow() > 0.9f } }
            val actionOut by remember { derivedStateOf { m.kNow() > 0.001f } }
            val face = remember { arrayOf(action) }
            if (action != null) face[0] = action
            val shownAction = face[0]
            SideEffect { m.showIcon(shownAction?.icon, actionOut) }
            if (actionOut && shownAction != null) Box(
                Modifier
                    .offset { IntOffset(((w - DROP) / 2).dp.roundToPx(), (g.rowTop + notchY() - DROP / 2).dp.roundToPx()) }
                    .size(DROP.dp)
                    .graphicsLayer {
                        val k = m.kNow()
                        scaleX = max(0.001f, k); scaleY = scaleX
                        alpha = min(1f, k * 3)
                        compositingStrategy = CompositingStrategy.ModulateAlpha
                    }
                    .then(if (actionOn) Modifier.hazeSource(haze, zIndex = 2f) else Modifier)
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
                        rim(actionRim.of(size, 0.5.dp.toPx()) { Path().apply { addOval(Rect(Offset.Zero, size)) } }, 0.4f, 0.75f, 0.4f)
                    }
                    .semantics { testTag = "bar-action" }
                    .then(if (actionOn && shown && action != null) Modifier.clickable { action.run() }.semantics { contentDescription = action.label } else Modifier),
                contentAlignment = Alignment.Center,
            ) {
                // From one action to another with another icon (令 and a "+"): the icon swaps (a short scale and fade, the
                // bar's loop stepping it), the circle stays. Another "+" (文件's to Profile's) is the same icon: nothing moves.
                val was = m.iconWas
                val now = m.icon
                if (was != null) ActionIcon(was) {
                    val p = Ease.Css.transform((m.iconSwap.value * 300f / 120f).coerceIn(0f, 1f))
                    alpha = 1f - p
                    scaleX = 1f - 0.5f * p; scaleY = scaleX
                }
                if (now != null) ActionIcon(now) {
                    val ms = m.iconSwap.value * 300f
                    alpha = Ease.Css.transform(((ms - 60f) / 180f).coerceIn(0f, 1f))
                    scaleX = 0.5f + 0.5f * Ease.Arrive.transform(((ms - 60f) / 240f).coerceIn(0f, 1f)); scaleY = scaleX
                }
            }
            // The ball: under the places (they stay sharp over it), over the action.
            Box(
                Modifier
                    .layout { measurable, _ ->
                        val box = ballBox(ball, goalX, m.held.value, m.ballScale.value)
                        val p = measurable.measure(Constraints.fixed(box.width.dp.roundToPx().coerceAtLeast(1), box.height.dp.roundToPx().coerceAtLeast(1)))
                        layout(p.width, p.height) { p.place(box.left.dp.roundToPx(), box.top.dp.roundToPx()) }
                    }
                    .graphicsLayer { alpha = m.ballAlpha.value; compositingStrategy = CompositingStrategy.ModulateAlpha }
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
                    // The glass's frost and tint under its own (as a blur of the glass looked: the two blurs' as one).
                    .hazeEffect(haze) {
                        backgroundColor = bg
                        tints = listOf(HazeTint(raised.copy(alpha = 0.72f)), HazeTint(Color.White.copy(alpha = if (dark) 0.12f else 0.42f)))
                        blurRadius = cssBlur(24f)
                        noiseFactor = 0f
                    }
                    .drawWithContent {
                        drawContent()
                        val r = size.minDimension / 2
                        val shape = ballRim.of(size, 0.5.dp.toPx()) { Path().apply { addRoundRect(RoundRect(Rect(Offset.Zero, size), CornerRadius(r))) } }
                        if (dark) rim(shape, 0.22f, 0.45f, 0.25f) else rim(shape, 0.5f, 0.95f, 0.55f)
                    },
            )
            // The other bars, above this one, as the panel opens (each a row, every place as far from its row's edges as
            // the bar's are from the bar's).
            val panelOut by remember { derivedStateOf { m.mode || m.o.value > 0.001f } }
            if (panelOut && swap == null) Box(Modifier.matchParentSize().graphicsLayer {
                alpha = m.rowsAlpha()
                translationY = m.rowsShift(g).dp.toPx()
                compositingStrategy = CompositingStrategy.ModulateAlpha
            }) {
                g.others.forEachIndexed { n, i ->
                    val set = g.sets[i]
                    val cs = g.centres(0f, set.size)
                    set.forEachIndexed { j, key ->
                        val on = if (cand != null) cand.set == i && cand.key == key else active == key
                        Place(m, "row:$key", key, labelOf(key), on, idle, lit, dots[key], icon,
                            Modifier.offset { IntOffset((cs[j] - g.slot / 2).dp.roundToPx(), (OVER + n * ROW + 4f).dp.roundToPx()) }
                                .size(g.slot.dp, 48.dp),
                            role = Role.Button, onA11y = { m.pick(i, key) })
                    }
                }
            }
            // The bar's places, over the ball.
            if (swap == null) g.items.forEachIndexed { j, key ->
                Place(m, "bar:$key", key, labelOf(key), (under ?: active) == key, idle, lit, dots[key], icon,
                    Modifier.offset { IntOffset((g.centres(m.kNow(), g.items.size)[j] - g.slot / 2).dp.roundToPx(), (g.rowTop + 4f).dp.roundToPx()) }
                        .size(g.slot.dp, 48.dp),
                    role = Role.Tab, onA11y = { onTab(key) })
            }
            // A bar being chosen: the stack of bars slides down inside the closing glass, the chosen one into the bar's
            // place, what is not chosen cut off by the glass's edge. Nothing fades out. It starts as the rows and the bar
            // were drawn (the rows' fade and offset, each place as lit as it was), and comes to the bar's look as it
            // lands (the place shown lit): landed, it is the bar's places as drawn the next frame, and goes with nothing
            // changing.
            if (swap != null && laid != null) Box(Modifier.matchParentSize().graphicsLayer { shape = Window(clipTop().dp.toPx(), RAD.dp.toPx()); clip = true }) {
                fun shift() = m.swapAt(swap)?.let { (_, y) -> y - laid.rowMid(swap.n) } ?: 0f
                fun was(id: String) = shade(idle, lit, swap.lit[id] ?: 0f)
                val rowAlpha = { m.rowAlpha(swap) }
                val rowDrop = { m.rowDrop(swap) }
                laid.others.forEachIndexed { n, i ->
                    if (i == swap.i) return@forEachIndexed
                    val set = laid.sets[i]
                    val cs = laid.centres(0f, set.size)
                    set.forEachIndexed { j, key -> Flying(key, was("row:$key"), dots[key], icon, g.slot, rowAlpha, rowDrop) { Offset(cs[j], laid.rowMid(n) + shift()) } }
                }
                val t = m.t(swap)
                laid.sets.getOrNull(swap.i)?.forEachIndexed { j, key ->
                    val from = was("row:$key")
                    val end = if (key == active) lit else idle
                    Flying(key, if (t >= 1f) end else if (t <= 0f) from else lerp(from, end, t), dots[key], icon, g.slot, rowAlpha, rowDrop) {
                        val (xs, y) = m.swapAt(swap) ?: return@Flying Offset.Zero
                        Offset(xs[j], y)
                    }
                }
                laid.items.forEachIndexed { j, key ->
                    Flying(key, was("bar:$key"), dots[key], icon, g.slot) { Offset(laid.centres(m.kNow(), laid.items.size)[j], laid.barMid + shift()) }
                }
            }
        }
    }
}

/**
 * Where the ball is (dp in the panel's frame) and how fast it goes, a spring each way toward where it is sent (`goX`,
 * `goY`), stepped a frame at a time (the bar's loop, BarModel.run). Where it is sent may change every frame (a finger moving on the
 * bar): it goes on from where it is at the speed it has, toward the new goal. (An animation started over at each move,
 * as it was, never got past its first frame under a real finger: the ball stayed where it was until the finger stopped.)
 */
@Stable
private class BallMotion(x: Float, y: Float) {
    var x by mutableFloatStateOf(x)
    var y by mutableFloatStateOf(y)
    /** Its speed (dp a second), read with where it is. */
    var vx = 0f
    var vy = 0f
    var goX by mutableFloatStateOf(x)
    var goY by mutableFloatStateOf(y)
    /** Across, as stiff as the way is short; down and up, 300. Damped as the web's (ZETA 0.635). */
    var tension = 300f
    val resting: Boolean get() = abs(goX - x) < 0.01f && abs(goY - y) < 0.01f && abs(vx) < 0.01f && abs(vy) < 0.01f

    fun snapTo(x0: Float, y0: Float) { x = x0; y = y0; vx = 0f; vy = 0f }

    fun step(dt: Float, instant: Boolean = false) {
        if (instant) return snapTo(goX, goY)
        val cx = 2 * 0.635f * sqrt(tension)
        val cy = 2 * 0.635f * sqrt(300f)
        var nx = x
        var ny = y
        var left = dt
        // In steps of 4 ms at most: steady however stiff.
        while (left > 0f) {
            val h = min(left, 0.004f)
            left -= h
            vx += (-tension * (nx - goX) - cx * vx) * h
            nx += vx * h
            vy += (-300f * (ny - goY) - cy * vy) * h
            ny += vy * h
        }
        if (abs(goX - nx) < 0.01f && abs(vx) < 0.01f) { nx = goX; vx = 0f }
        if (abs(goY - ny) < 0.01f && abs(vy) < 0.01f) { ny = goY; vy = 0f }
        x = nx
        y = ny
    }
}

/** Where the ball is drawn (dp in the panel's frame): its box, stretched by its speed toward where it goes, or riding a bar being chosen. */
private class BallBox(val left: Float, val top: Float, val width: Float, val height: Float)

private fun ballBox(ball: BallMotion, goalX: Float, held: Float, shown: Float): BallBox {
    val scale = (1 + 0.06f * held) * shown
    val x = ball.x
    val v = if (abs(goalX - x) < 0.5f) 0f else ball.vx / 60f
    val stretch = min(MAX_STRETCH, abs(v) * 1.6f)
    val w = BALL + stretch
    val h = BALL - min(6f, stretch * 0.2f)
    // Its leading edge reaches ahead, toward where it goes.
    val left = x - BALL / 2 - (if (v < 0) stretch else 0f)
    val cx = left + w / 2
    val cy = ball.y
    val sw = w * scale
    val sh = h * scale
    return BallBox(cx - sw / 2, cy - sh / 2, sw, sh)
}

/**
 * A place on the bar or in the panel: its icon in the middle of its slot (lit when it is the one, going from one to the
 * other over 300 ms, the bar's loop stepping it), its dot at the icon's top right.
 */
@Composable
private fun Place(
    m: BarModel, id: String, key: String, label: String, on: Boolean, idle: Color, lit: Color, dot: Color?, icon: @Composable (String, Color) -> Unit,
    modifier: Modifier, role: Role, onA11y: () -> Unit,
) {
    // As it is when it comes, not lit up as it comes.
    val shade = remember { Glide(if (on) 1f else 0f) }
    DisposableEffect(id, shade) {
        m.tints[id] = shade
        onDispose { if (m.tints[id] === shade) m.tints.remove(id) }
    }
    SideEffect { shade.to(if (on) 1f else 0f, 300, Ease.Css) }
    val tint = shade(idle, lit, shade.value)
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
    ) { PlaceFace(key, tint, dot, icon) }
}

@Composable
private fun PlaceFace(key: String, tint: Color, dot: Color?, icon: @Composable (String, Color) -> Unit) {
    icon(key, tint)
    if (dot != null) Box(Modifier.offset(13.5.dp, (-12.5).dp).size(7.dp).clip(CircleShape).drawBehind { drawRect(dot) })
}

/** A place `v` lit: `lit` at 1, `idle` at 0. */
private fun shade(idle: Color, lit: Color, v: Float) = if (v >= 1f) lit else if (v <= 0f) idle else lerp(idle, lit, v)

/**
 * A place's icon as a bar is chosen, its middle where `at` says (dp), in a slot as the bar's places are (to the pixel);
 * faded and dropped (dp) as the rows were (`alpha`, `drop`) when it comes from them.
 */
@Composable
private fun Flying(
    key: String, tint: Color, dot: Color?, icon: @Composable (String, Color) -> Unit, slot: Float,
    alpha: () -> Float = { 1f }, drop: () -> Float = { 0f }, at: () -> Offset,
) {
    Box(
        Modifier.offset { at().let { IntOffset((it.x - slot / 2).dp.roundToPx(), (it.y - 24f).dp.roundToPx()) } }.size(slot.dp, 48.dp)
            .graphicsLayer {
                this.alpha = alpha()
                translationY = drop().dp.toPx()
                compositingStrategy = CompositingStrategy.ModulateAlpha
            }
            .semantics { testTag = "bar-flying-$key" },
        contentAlignment = Alignment.Center,
    ) { PlaceFace(key, tint, dot, icon) }
}

/** The notch's icon, as `look` has it (its swap). */
@Composable
private fun ActionIcon(icon: ImageVector, look: androidx.compose.ui.graphics.GraphicsLayerScope.() -> Unit) {
    Box(Modifier.graphicsLayer(look).semantics { testTag = "bar-action-icon" }) { IconIn(icon, if (icon == Icons.Ling) 40.dp else 30.dp, Color.White) }
}
