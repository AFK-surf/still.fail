// still.fail's corners (apps/android/shared/.../ui/Corners.kt, the same curves): a rounded rectangle's corner is a
// superellipse(1.5) one over a radius a quarter longer than the one it is given; circles and capsules are untouched,
// and between the two it goes over evenly.
package fail.still.rn.ui

import android.graphics.Path
import android.graphics.RectF
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

const val SMOOTH_SCALE = 1.25f
private const val SMOOTH_EXPONENT = 2.8284271f
private const val CUTS = 12

private fun smoothness(radius: Float, room: Float): Float =
    if (radius <= 0f) 0f else ((room - radius) / ((SMOOTH_SCALE - 1f) * radius)).coerceIn(0f, 1f)

/** The outline as a path, into `path` (reset first), for a box of `box`; radii in pixels. */
fun smoothPath(path: Path, box: RectF, topLeft: Float, topRight: Float, bottomRight: Float, bottomLeft: Float, amount: Float = 1f) {
    path.reset()
    val room = min(box.width(), box.height()) / 2f
    val tl = topLeft.coerceIn(0f, room); val tr = topRight.coerceIn(0f, room); val br = bottomRight.coerceIn(0f, room); val bl = bottomLeft.coerceIn(0f, room)
    val a = amount.coerceIn(0f, 1f)
    val stl = smoothness(tl, room) * a; val str = smoothness(tr, room) * a; val sbr = smoothness(br, room) * a; val sbl = smoothness(bl, room) * a
    val rtl = tl * (1f + (SMOOTH_SCALE - 1f) * stl); val rtr = tr * (1f + (SMOOTH_SCALE - 1f) * str)
    val rbr = br * (1f + (SMOOTH_SCALE - 1f) * sbr); val rbl = bl * (1f + (SMOOTH_SCALE - 1f) * sbl)
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
}

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

private val Full by lazy { smoothCorner(1f) }

private fun smoothCorner(smooth: Float): FloatArray {
    val n = 2.0 + (SMOOTH_EXPONENT - 2.0) * smooth
    val h = PI / 2 / CUTS
    val out = FloatArray(CUTS * 6)
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
