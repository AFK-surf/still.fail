// Corners, as the web's (web/src/styles/global.css.ts): a rounded rectangle's corner is a superellipse(1.5) one,
// |x|^n + |y|^n = 1 with n = 2^1.5, over a radius a quarter longer than the one it is given. Circles and capsules
// are never touched: a corner needs room for the longer radius, and where the box has none (the radius is half its
// shorter side) it is the plain round one. Between the two it goes over evenly, so a box that grows (a capsule of one
// line taking a second) changes shape with its size, and never at once.
package fail.still.android.ui

import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.toRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** How much longer the smooth corner's radius is, and its exponent (CSS superellipse(1.5) is 2^1.5). */
const val SMOOTH_SCALE = 1.25f
internal const val SMOOTH_EXPONENT = 2.8284271f

/** The cubic pieces a corner is drawn in: at 12, nowhere a hundredth of a pixel off the curve over a radius of 200 pixels. */
private const val CUTS = 12

/**
 * A rounded rectangle with the web's corners; `Smooth(12.dp)`, or a radius for each corner (the others square).
 * A radius of half the shorter side or more is a capsule's or a circle's, and is drawn as RoundedCornerShape draws it.
 */
class Smooth(topStart: CornerSize, topEnd: CornerSize, bottomEnd: CornerSize, bottomStart: CornerSize) : CornerBasedShape(topStart, topEnd, bottomEnd, bottomStart) {
    constructor(radius: Dp) : this(CornerSize(radius), CornerSize(radius), CornerSize(radius), CornerSize(radius))
    constructor(topStart: Dp = 0.dp, topEnd: Dp = 0.dp, bottomEnd: Dp = 0.dp, bottomStart: Dp = 0.dp) : this(CornerSize(topStart), CornerSize(topEnd), CornerSize(bottomEnd), CornerSize(bottomStart))

    override fun copy(topStart: CornerSize, topEnd: CornerSize, bottomEnd: CornerSize, bottomStart: CornerSize) = Smooth(topStart, topEnd, bottomEnd, bottomStart)

    override fun createOutline(size: Size, topStart: Float, topEnd: Float, bottomEnd: Float, bottomStart: Float, layoutDirection: LayoutDirection): Outline {
        val ltr = layoutDirection == LayoutDirection.Ltr
        return smoothOutline(size.toRect(), if (ltr) topStart else topEnd, if (ltr) topEnd else topStart, if (ltr) bottomEnd else bottomStart, if (ltr) bottomStart else bottomEnd)
    }

    // Shapes are made anew at each composition: equal ones keep the outline (and the path) they have.
    override fun equals(other: Any?) = other is Smooth && topStart == other.topStart && topEnd == other.topEnd && bottomEnd == other.bottomEnd && bottomStart == other.bottomStart
    override fun hashCode() = ((topStart.hashCode() * 31 + topEnd.hashCode()) * 31 + bottomEnd.hashCode()) * 31 + bottomStart.hashCode()
    override fun toString() = "Smooth($topStart, $topEnd, $bottomEnd, $bottomStart)"
}

/**
 * The corner, as Smooth takes it, of a smooth box `inset` inside a smooth one of corner `outer`, concentric with it: a
 * curve moved in by `inset` is drawn `inset` smaller, and Smooth draws a corner a quarter larger than it is given, so
 * the inset is taken a quarter smaller here (as the web's squarer corners less their padding, align.ts surface).
 */
fun concentric(outer: Dp, inset: Dp): Dp = outer - inset / SMOOTH_SCALE

/** The other way round: the corner of a smooth box round a smooth one of corner `inner`, `inset` in from its edges. */
fun concentricOut(inner: Dp, inset: Dp): Dp = inner + inset / SMOOTH_SCALE

/**
 * How far in from each of its edges a Smooth corner of `radius` (room enough to be wholly smooth) passes at its middle,
 * where it turns 45°: the superellipse's point with x = y, 2^(-1/n) of the longer radius from its centre.
 */
fun smoothMiddle(radius: Dp): Dp = radius * SMOOTH_SCALE * (1f - 2f.pow(-1f / SMOOTH_EXPONENT))

/**
 * A box on its way between a round-cornered place and a smooth one (a note flying from a capsule into its card):
 * `amount` of the smoothing, 0 the plain round corner and 1 Smooth's own.
 */
fun Smooth(radius: Dp, amount: Float): Shape = object : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density) = smoothOutline(size.toRect(), with(density) { radius.toPx() }, amount = amount)
}

/** A smooth box filled, for what is drawn by hand behind something (a press, a flash) and has to be the shape the rest is. */
fun DrawScope.drawSmooth(color: Color, radius: Float, box: Rect = size.toRect(), alpha: Float = 1f) = drawOutline(smoothOutline(box, radius), color, alpha)

/**
 * How smooth a corner of `radius` is where `room` is half the box's shorter side: wholly (1) with room for the longer
 * radius, not at all (0) with none, a capsule's end.
 */
internal fun smoothness(radius: Float, room: Float): Float =
    if (radius <= 0f) 0f else ((room - radius) / ((SMOOTH_SCALE - 1f) * radius)).coerceIn(0f, 1f)

/**
 * Smooth's outline in pixels, for a box anywhere (what is drawn or clipped by hand): a plain rounded rectangle where
 * no corner is smooth, which the system clips and shadows without a path; else a closed convex path.
 */
fun smoothOutline(box: Rect, topLeft: Float, topRight: Float = topLeft, bottomRight: Float = topLeft, bottomLeft: Float = topLeft, amount: Float = 1f): Outline {
    val room = min(box.width, box.height) / 2f
    val tl = topLeft.coerceIn(0f, room); val tr = topRight.coerceIn(0f, room); val br = bottomRight.coerceIn(0f, room); val bl = bottomLeft.coerceIn(0f, room)
    val a = amount.coerceIn(0f, 1f)
    val stl = smoothness(tl, room) * a; val str = smoothness(tr, room) * a; val sbr = smoothness(br, room) * a; val sbl = smoothness(bl, room) * a
    if (stl == 0f && str == 0f && sbr == 0f && sbl == 0f) {
        return if (tl == 0f && tr == 0f && br == 0f && bl == 0f) Outline.Rectangle(box) else Outline.Rounded(RoundRect(box, CornerRadius(tl), CornerRadius(tr), CornerRadius(br), CornerRadius(bl)))
    }
    val rtl = tl * (1f + (SMOOTH_SCALE - 1f) * stl); val rtr = tr * (1f + (SMOOTH_SCALE - 1f) * str)
    val rbr = br * (1f + (SMOOTH_SCALE - 1f) * sbr); val rbl = bl * (1f + (SMOOTH_SCALE - 1f) * sbl)
    // Clockwise from the top edge; each corner turns from the edge it ends (to its centre: `u`) to the one it begins (`v`).
    val path = Path()
    path.moveTo(box.left + rtl, box.top)
    path.lineTo(box.right - rtr, box.top)
    path.corner(box.right - rtr, box.top + rtr, rtr, 0f, -1f, 1f, 0f, str)
    path.lineTo(box.right, box.bottom - rbr)
    path.corner(box.right - rbr, box.bottom - rbr, rbr, 1f, 0f, 0f, 1f, sbr)
    path.lineTo(box.left + rbl, box.bottom)
    path.corner(box.left + rbl, box.bottom - rbl, rbl, 0f, 1f, -1f, 0f, sbl)
    path.lineTo(box.left, box.top + rtl)
    path.corner(box.left + rtl, box.top + rtl, rtl, -1f, 0f, 0f, -1f, stl)
    path.close()
    return Outline.Generic(path)
}

/** A quarter turn round (cx, cy) from cx + r·u to cx + r·v. */
private fun Path.corner(cx: Float, cy: Float, r: Float, ux: Float, uy: Float, vx: Float, vy: Float, smooth: Float) {
    if (r <= 0f) return
    val k = if (smooth == 1f) Full else smoothCorner(smooth)
    var i = 0
    while (i < k.size) {
        cubicTo(
            cx + r * (k[i] * ux + k[i + 1] * vx), cy + r * (k[i] * uy + k[i + 1] * vy),
            cx + r * (k[i + 2] * ux + k[i + 3] * vx), cy + r * (k[i + 2] * uy + k[i + 3] * vy),
            cx + r * (k[i + 4] * ux + k[i + 5] * vx), cy + r * (k[i + 4] * uy + k[i + 5] * vy),
        )
        i += 6
    }
}

/** The corner nearly every box has, worked out once. */
private val Full by lazy { smoothCorner(1f) }

/**
 * A quarter of the unit superellipse from (1, 0) to (0, 1), its exponent `smooth` of the way from a circle's 2 to
 * SMOOTH_EXPONENT, as cubics: for each, its two control points and its end. Cut by the angle from the centre, where
 * the curve has a tangent everywhere (by its usual parameter it has none at its ends), each cubic takes the curve's
 * own direction at both of its ends: the pieces join without a kink, and the first and last leave along the edges.
 */
internal fun smoothCorner(smooth: Float): FloatArray {
    val n = 2.0 + (SMOOTH_EXPONENT - 2.0) * smooth
    val h = PI / 2 / CUTS
    val out = FloatArray(CUTS * 6)
    // The point at an angle and the curve's direction there: (ρ cos, ρ sin) with ρ = (cosⁿ + sinⁿ)^(-1/n).
    fun at(i: Int): DoubleArray {
        val c = if (i == CUTS) 0.0 else cos(i * h); val s = if (i == 0) 0.0 else sin(i * h)
        val sum = c.pow(n) + s.pow(n)
        val rho = sum.pow(-1 / n)
        val turn = rho * (c.pow(n - 1) * s - s.pow(n - 1) * c) / sum
        return doubleArrayOf(rho * c, rho * s, turn * c - rho * s, turn * s + rho * c)
    }
    var p = at(0)
    for (i in 0 until CUTS) {
        val q = at(i + 1)
        out[i * 6] = (p[0] + p[2] * h / 3).toFloat(); out[i * 6 + 1] = (p[1] + p[3] * h / 3).toFloat()
        out[i * 6 + 2] = (q[0] - q[2] * h / 3).toFloat(); out[i * 6 + 3] = (q[1] - q[3] * h / 3).toFloat()
        out[i * 6 + 4] = q[0].toFloat(); out[i * 6 + 5] = q[1].toFloat()
        p = q
    }
    return out
}
