// The app's motion, as the web's (web/src/motion.ts and the curves in its styles): one set of curves and springs, so
// a motion here moves as the same one there. CSS cubic-bezier(a, b, c, d) is CubicBezierEasing(a, b, c, d) exactly.
package fail.still.android.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import androidx.compose.runtime.Stable
import kotlin.math.PI
import kotlin.math.pow

object Ease {
    /** --ease-out (.2, .7, .2, 1): morph, a list's rows coming in, folding. */
    val Out = CubicBezierEasing(0.2f, 0.7f, 0.2f, 1f)
    /** --m-ease (.2, .8, .2, 1): sheets, pages rising, a new chat's first words arriving. */
    val Arrive = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)
    /** --m-standard (.4, 0, .2, 1): pages pushed, the jump-to-latest button, the two lists' switch. */
    val Standard = FastOutSlowInEasing
    /** CSS's keyword ease-out. */
    val CssOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)
    /** (0, 0, .2, 1): a segmented control's thumb. */
    val Decel = CubicBezierEasing(0f, 0f, 0.2f, 1f)
    /** (.3, 0, .5, 1): what leaves by fading (a new chat's choosers). */
    val LeaveFade = CubicBezierEasing(0.3f, 0f, 0.5f, 1f)
    /** CSS's keyword ease (.25, .1, .25, 1): a web transition given no curve (a sheet's scrim, a toast). */
    val Css = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f)
}

/**
 * Motion's spring by visual duration (seconds) and bounce, as Compose's: Motion makes it stiffness (2π / 1.2v)² and
 * damping 2·clamp(1 − bounce, .05, 1)·√stiffness at mass 1, so the damping ratio is clamp(1 − bounce, .05, 1).
 */
fun <T> motionSpring(visualDuration: Float, bounce: Float = 0f, visibilityThreshold: T? = null): SpringSpec<T> =
    spring(
        dampingRatio = (1f - bounce).coerceIn(0.05f, 1f),
        stiffness = (2 * PI / (1.2 * visualDuration)).pow(2).toFloat(),
        visibilityThreshold = visibilityThreshold,
    )

/** motion.ts MOVE: what follows another thing's place (a list's rows, small windows). */
val MoveSpring: SpringSpec<Float> = motionSpring(0.28f, visibilityThreshold = 0.5f)
/** A sheet let go (web mobile/app.tsx), from the finger's speed. */
val SheetSpring: SpringSpec<Float> = motionSpring(0.32f, visibilityThreshold = 0.5f)

/**
 * motion.ts `follower`: a value that springs to where it is told, and when told again mid-way goes on from where it is
 * and how fast it moves; the same place again changes nothing. `jump` puts it there at once.
 */
@Stable
class Follower(start: Float, private val spec: AnimationSpec<Float> = MoveSpring) {
    val anim = Animatable(start)
    private var goal = start
    val value: Float get() = anim.value

    suspend fun to(next: Float, velocity: Float = anim.velocity) {
        if (next == goal && (anim.isRunning || anim.value == next)) return
        goal = next
        anim.animateTo(next, spec, velocity)
    }

    suspend fun jump(next: Float) {
        goal = next
        anim.snapTo(next)
    }
}
