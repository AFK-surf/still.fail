// The app's motion, as the web's (web/src/motion.ts and the curves in its styles): one set of curves and springs, so
// a motion here moves as the same one there. CSS cubic-bezier(a, b, c, d) is CubicBezierEasing(a, b, c, d) exactly.
// Reduced motion is one clock for all of it (Motion): every animation goes the same way, reduced or not, only at
// once; loops and flashes, which that would stop or hide, go through rememberLoop and flash.
package fail.still.android.ui

import android.content.Context
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.InfiniteRepeatableSpec
import androidx.compose.animation.core.KeyframesSpec
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.platform.WindowRecomposerPolicy
import androidx.compose.ui.platform.createLifecycleAwareWindowRecomposer
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.pow

/**
 * Whether motion is reduced, for the whole app: as this device's setting says (prefs `motion`), else as the system's
 * (animations off: its animator duration scale 0, followed as it changes). It is Compose's own clock in every window of
 * the app (MotionDurationScale, `scale`): reduced, it is 0, and every animation (animateTo, animate*AsState,
 * AnimatedVisibility, a transition) is at its end at once, what follows it done as ever. Nothing else differs: no page
 * asks whether motion is reduced, but for a loop (rememberLoop) and a flash (flash), which the clock at 0 would stop at a
 * pose of no meaning or never show.
 */
object Motion {
    /** This device's setting (prefs `motion`, as AppState has it): `reduce`, `full`, or null to go by the system. */
    var chosen by mutableStateOf<String?>(null)
    /** The system's animation speed (Settings.Global.ANIMATOR_DURATION_SCALE). */
    private var system by mutableFloatStateOf(1f)

    val reduced: Boolean get() = chosen == "reduce" || (chosen == null && system == 0f)

    /** The clock: 0 reduced; else the system's speed (1 when motion is asked for in full with the system's animations off). */
    val scale: MotionDurationScale = object : MotionDurationScale {
        override val scaleFactor: Float get() = if (reduced) 0f else system.takeIf { it > 0f } ?: 1f
    }

    private var installed = false

    /** Follows the system's setting and makes `scale` the clock of every window made from now on (once, as an activity starts). */
    @OptIn(InternalComposeUiApi::class)
    fun install(context: Context) {
        if (installed) return
        installed = true
        val resolver = context.applicationContext.contentResolver
        fun read() { system = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) }
        read()
        resolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false,
            object : ContentObserver(Handler(Looper.getMainLooper())) { override fun onChange(selfChange: Boolean) = read() },
        )
        WindowRecomposerPolicy.setFactory { root -> root.createLifecycleAwareWindowRecomposer(scale) }
    }
}

/**
 * A loop (a spinner, a mark turning or breathing): `spec` from `from` to `to`, again and again. With motion reduced the
 * clock would leave it at its end, wherever that is: it holds `still`, its pose at rest, instead; or with `slowMs` (a
 * spinner: what it says is still under way) it goes on turning, linearly, that slowly.
 */
@Composable
fun rememberLoop(from: Float, to: Float, spec: InfiniteRepeatableSpec<Float>, label: String, still: Float = from, slowMs: Int = 0): State<Float> {
    if (!Motion.reduced) return rememberInfiniteTransition(label).animateFloat(from, to, spec, label)
    if (slowMs <= 0) return rememberUpdatedState(still)
    val at = remember { mutableFloatStateOf(from) }
    LaunchedEffect(from, to, slowMs) {
        val start = withInfiniteAnimationFrameNanos { it }
        while (true) withInfiniteAnimationFrameNanos { now -> at.floatValue = from + (to - from) * ((now - start) / 1_000_000L % slowMs) / slowMs }
    }
    return at
}

/**
 * A highlight that comes and goes, from where it is (its start and its end) to `peak` and back as `spec` says; `block`
 * is told each value. With motion reduced it would be at its end at once, never seen: it shows at `peak` instead, for as
 * long, then goes, without a fade.
 */
suspend fun Animatable<Float, AnimationVector1D>.flash(peak: Float, spec: KeyframesSpec<Float>, block: (Float) -> Unit = {}) {
    val rest = value
    if ((currentCoroutineContext()[MotionDurationScale]?.scaleFactor ?: 1f) > 0f) { animateTo(rest, spec) { block(value) }; return }
    snapTo(peak)
    block(peak)
    delay(spec.config.durationMillis.toLong())
    snapTo(rest)
    block(rest)
}

object Ease {
    /** --ease-out (.2, .7, .2, 1): morph, a list's rows coming in, folding. */
    val Out = CubicBezierEasing(0.2f, 0.7f, 0.2f, 1f)
    /** --m-ease (.2, .8, .2, 1): sheets, pages rising, a new chat's first words arriving. */
    val Arrive = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)
    /** (.6, 0, .2, 1): words sent in an open chat on their way to their row, each way (web madeChat.ts FLIGHT). */
    val Flight = CubicBezierEasing(0.6f, 0f, 0.2f, 1f)
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
