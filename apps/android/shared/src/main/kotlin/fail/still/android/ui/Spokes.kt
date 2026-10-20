// What is at work, as the web's (web/ui/src/styles/spokes.ts): eight spokes, the brightest a step further round every
// SPOKE_STEP_MS, the others fading behind it. It steps, it does not turn: a frame for each step (10 a second) and none
// between, where a turning ring drew one for every frame of the screen (120 a second on a phone, 2026-10-19).
package fail.still.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin

const val SPOKE_STEP_MS = 100L
private const val SPOKES = 8
/** The spokes' strength from the brightest back. */
private val SPOKE_ALPHA = floatArrayOf(1f, .75f, .55f, .42f, .32f, .25f, .2f, .2f)

private fun spokeNow() = ((System.currentTimeMillis() / SPOKE_STEP_MS) % SPOKES).toInt()

/**
 * Which spoke leads now. One clock for every mark, the wall clock's steps, so the marks on a page step in one frame
 * together; with motion reduced, held at the first. Read it as it is drawn (in a draw block): a step redraws, nothing
 * composes again.
 */
@Composable
fun rememberSpokeStep(): State<Int> {
    val reduced = Motion.reduced
    val step = remember(reduced) { mutableIntStateOf(if (reduced) 0 else spokeNow()) }
    if (!reduced) LaunchedEffect(step) {
        while (true) {
            delay(SPOKE_STEP_MS - System.currentTimeMillis() % SPOKE_STEP_MS)
            step.intValue = spokeNow()
        }
    }
    return step
}

/**
 * The eight spokes in a box `size` across round `center`, as the web's 24-unit drawing: each from 4.8 to 9.6 out, 2.9
 * thick with round ends, the first straight up and the rest clockwise; `step` the one that leads.
 */
fun DrawScope.drawSpokes(step: Int, color: Color, size: Float, center: Offset = this.center) {
    val u = size / 24f
    for (i in 0 until SPOKES) {
        val a = Math.toRadians(i * 360.0 / SPOKES)
        val dx = sin(a).toFloat() * u
        val dy = -cos(a).toFloat() * u
        drawLine(
            color.copy(alpha = color.alpha * SPOKE_ALPHA[(step - i + SPOKES) % SPOKES]),
            Offset(center.x + dx * 4.8f, center.y + dy * 4.8f), Offset(center.x + dx * 9.6f, center.y + dy * 9.6f),
            2.9f * u, StrokeCap.Round,
        )
    }
}

/**
 * The same steps as a ring of eight arcs round an avatar (web spokes.ts `segments`): in a box `size` across, a circle
 * `stroke` thick on its edge, each arc 31° of its 45° with round ends, the first straight up; `step` the one that leads.
 */
fun DrawScope.drawSegments(step: Int, color: Color, size: Float, stroke: Float, center: Offset = this.center) {
    val r = size / 2 - stroke / 2
    val box = androidx.compose.ui.geometry.Size(r * 2, r * 2)
    val at = Offset(center.x - r, center.y - r)
    // The round ends reach half the stroke past each arc: shortened by as much, the gaps stay 14°.
    val cap = Math.toDegrees((stroke / 2 / r).toDouble()).toFloat()
    for (i in 0 until SPOKES) {
        drawArc(
            color.copy(alpha = color.alpha * SPOKE_ALPHA[(step - i + SPOKES) % SPOKES]),
            i * 45f - 90f - 15.5f + cap, 31f - 2 * cap, false, at, box,
            style = androidx.compose.ui.graphics.drawscope.Stroke(stroke, cap = StrokeCap.Round),
        )
    }
}
