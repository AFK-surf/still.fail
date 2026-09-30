// The stations at a glance, for the corner of the home bar, drawn as the web's (web/src/StationGlyph.tsx):
// a circle cut into one equal arc per station with the bottom slot left open, the still.fail robot in the middle.
// Online arcs are ink and the rest a faint track; past six stations the arcs join into one bar filled to the share
// online. A station failing drops out of the ring into the open slot as a red dot (two at most). The robot blinks one
// eye while one station works and both while more do; with the phone itself offline it sleeps and the whole fades.
package fail.still.android.ui

import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.layout.size
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import fail.still.android.data.ChatsView
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

data class GlyphCounts(val online: Int, val dim: Int, val failing: Int, val working: Int, val asleep: Boolean)

/** An arc on the ring, angles in degrees clockwise from 12 o'clock; `lit` is ink, otherwise the track. */
data class GlyphArc(val from: Float, val to: Float, val lit: Boolean)

// All in the web's 24-unit box.
private const val CX = 12f
private const val CY = 12f
private const val R = 9.7f
private const val W = 1.8f
private const val GAP = 1.7f
private const val MAX_ARCS = 6
private const val TRACK = 0.18f
private const val MAX_DOTS = 2
private val GAP_DEG = ((GAP + W) / R) * 180f / PI.toFloat()

/** Where every part goes: the same as the web's glyphLayout. */
fun glyphLayout(c: GlyphCounts): Pair<List<GlyphArc>, List<Float>> {
    val ring = c.online + c.dim
    val arcs = mutableListOf<GlyphArc>()
    if (ring > MAX_ARCS) {
        val slot = 360f / (MAX_ARCS + 1)
        val from = 180f + slot / 2 + GAP_DEG / 2
        val to = 540f - slot / 2 - GAP_DEG / 2
        arcs += GlyphArc(from, to, false)
        if (c.online > 0) arcs += GlyphArc(from, from + (to - from) * c.online / ring, true)
    } else if (ring > 0) {
        val slot = 360f / (ring + 1)
        for (i in 0 until ring) {
            val mid = 180f + slot * (i + 1)
            arcs += GlyphArc(mid - slot / 2 + GAP_DEG / 2, mid + slot / 2 - GAP_DEG / 2, i < c.online)
        }
    }
    val k = min(c.failing, MAX_DOTS)
    val step = (3.1f / R) * 180f / PI.toFloat()
    return arcs to List(k) { i -> 180f + (i - (k - 1) / 2f) * step }
}

/** What the glyph draws: the core's counts for the list (its `glyph`), asleep while the core reaches nothing at all. */
fun glyphCounts(view: ChatsView?, asleep: Boolean): GlyphCounts {
    val g = view?.glyph
    return GlyphCounts(g?.online?.toInt() ?: 0, g?.dim?.toInt() ?: 0, g?.failing?.toInt() ?: 0, g?.working?.toInt() ?: 0, asleep)
}

@Composable
fun StationGlyph(counts: GlyphCounts, size: Dp = 24.dp) {
    val (arcs, dots) = glyphLayout(counts)
    val ink = C.ink
    val red = C.red
    val blinking = if (counts.asleep) 0 else counts.working
    val still = reducedMotion()
    // A blink: open most of the time, shut for a moment (the web's 2.6s, shut at 93%).
    val eye = if (blinking > 0 && !still) rememberInfiniteTransition(label = "blink").animateFloat(
        1f, 1f, infiniteRepeatable(keyframes { durationMillis = 2600; 1f at 2288; 0.1f at 2418; 1f at 2600 }), label = "eye",
    ).value else 1f
    Canvas(Modifier.size(size).graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen; alpha = if (counts.asleep) 0.4f else 1f }) {
        val u = this.size.width / 24f
        val stroke = Stroke(W * u, cap = StrokeCap.Round)
        val box = Size(2 * R * u, 2 * R * u)
        val topLeft = Offset((CX - R) * u, (CY - R) * u)
        for (a in arcs) drawArc(ink.copy(alpha = if (a.lit) 1f else TRACK), a.from - 90f, a.to - a.from, false, topLeft, box, style = stroke)
        for (d in dots) {
            val r = d * PI.toFloat() / 180f
            drawCircle(red, 1.25f * u, Offset((CX + R * sin(r)) * u, (CY - R * cos(r)) * u))
        }
        drawRoundRect(ink, Offset(7.1f * u, 7.9f * u), Size(9.8f * u, 8.2f * u), CornerRadius(3f * u))
        if (counts.asleep) {
            for (x in listOf(9.2f to 10.8f, 13.2f to 14.8f))
                drawLine(ink, Offset(x.first * u, 12.1f * u), Offset(x.second * u, 12.1f * u), 1.2f * u, StrokeCap.Round, blendMode = BlendMode.Clear)
        } else listOf(10.3f, 13.7f).forEachIndexed { i, x ->
            val ry = 1.25f * (if (blinking >= (if (i == 1) 1 else 2)) eye else 1f)
            drawOval(ink, Offset((x - 1.1f) * u, (12f - ry) * u), Size(2.2f * u, 2 * ry * u), blendMode = BlendMode.Clear)
        }
    }
}
