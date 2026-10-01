// How a chat's rows move, apart from the list itself (web/src/Chat.tsx → useEmissions, Quotes → jump; their keyframes in
// styles/keyframes.css.ts): an agent's message coming out of its activity's avatar, and a quoted message flashing when a
// quote leads to it. The state is the page's, outside the rows (a row scrolled away and back is composed anew).
package fail.still.android.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import fail.still.android.data.ChatMessage
import fail.still.android.ui.Ease
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

internal val LocalChatMotion = staticCompositionLocalOf<ChatMotion?> { null }

/**
 * A message an agent posts while its activity shows comes out of the activity's avatar, one at a time (web
 * useEmissions): the activity folds to its avatar (Fold), the avatar hops to where the message goes (Float: up, slowing,
 * then falling ever faster, stretched, stopping dead there), the message comes out of it as it lands, the avatar
 * flattened by the fall and springing back (Spit), and the avatar goes on down to where the activity now is, which
 * unfolds again (Return). Until its turn a message waits out of the list. With animations off messages just
 * appear, and so do those no one watches come out: arriving while the page is not in front or the reader has scrolled
 * up, and all still waiting when that happens.
 */
@Stable
internal class ChatMotion(private val reduced: Boolean) {
    enum class Pose(val ms: Int) { Fold(170), Float(440), Spit(380), Return(320) }
    /** Where the flying avatar's 18dp face is, in the pane, and how it is scaled about its middle (`sx`, `sy`). */
    class Flying(val at: Offset, val sx: Float, val sy: Float)
    /** `from`: on from the same agent's message before it (where its avatar is), dropping on without going home; `fold`:
     *  how much of its folding is left (it folds from when its message begins waiting). */
    class Turn(val seq: Long, val agent: String, val pose: Pose, val from: Offset? = null, val fold: Int = Pose.Fold.ms)

    private val decided = HashMap<Long, Boolean>()
    private val done = HashSet<Long>()
    /** Waiting messages: seq, agent, and since when (ms; the agent's activity folds from then). */
    private val queue = ArrayDeque<Triple<Long, String, Long>>()
    /** Whose avatar the flying copy shows as, while it shows (Chat.kt Flyer): that activity's own is hidden. */
    var copied by mutableStateOf<String?>(null)
    /** The rings round the agents' avatars turning, one for the chat (Chat.kt WorkRing). */
    var ring: androidx.compose.runtime.State<Float>? = null
    /** Where the flying avatar last let a message out (in the pane): where it drops on from to the same agent's next. */
    private var landed: Offset? = null
    /** Bumped when what waits changes without the current turn changing (all let out at once). */
    private var version by mutableIntStateOf(0)
    var current by mutableStateOf<Turn?>(null)
        private set
    /** The current pose's time, 0 to 1, linear: each part eases it as its own keyframes do. */
    val clock = Animatable(0f)

    /** Where things are, as last laid out: the list's box (what the flying avatar moves in), each activity's avatar and
     *  row, each message's avatar. Read anew each frame while it flies. */
    var pane: LayoutCoordinates? = null
    val activityAvatars = HashMap<String, LayoutCoordinates>()
    val activityRows = HashMap<String, LayoutCoordinates>()
    val landings = HashMap<Long, LayoutCoordinates>()

    /** Messages seen for the first time: an agent's, said while the chat shows (the core's `said`), while its activity
     *  shows, waits its turn to come out of it. */
    fun take(messages: List<ChatMessage>, showing: Set<String>) {
        for (m in messages) {
            if (m.seq in decided) continue
            val agent = if (m.authorKind == "agent" && !m.mine && !m.system) m.by.agent else null
            val emits = !reduced && watched && m.said == true && agent != null && agent in showing
            decided[m.seq] = emits
            if (emits) queue.addLast(Triple(m.seq, agent!!, android.os.SystemClock.uptimeMillis()))
        }
    }

    /** Whether messages coming in are watched (the page in front, the reader at the end), as last composed. */
    var watched = false

    /** The first waiting starts, once composed (not from composing itself). */
    fun start() {
        if (current == null && queue.isNotEmpty()) nextAfter(null)
    }

    /** Whether a message comes (or came) out of an avatar: it never eases in as others do. */
    fun emits(seq: Long) = decided[seq] == true

    /** Waiting its turn (or its avatar still on its way to it): not in the list yet. */
    fun held(seq: Long): Boolean {
        version
        if (decided[seq] != true || seq in done) return false
        val c = current
        return !(c?.seq == seq && (c.pose == Pose.Spit || c.pose == Pose.Return))
    }

    fun emitting(seq: Long) = current?.let { it.seq == seq && it.pose == Pose.Spit } == true

    /** Agents whose activity must stay while their messages come out. */
    fun keeps(): Set<String> {
        version
        return buildSet { queue.forEach { add(it.second) }; current?.let { add(it.agent) } }
    }

    /** An agent's activity: folded to its avatar from when its first message begins waiting until its last is out (others'
     *  coming out between do not unfold and fold it again), and whether the avatar is away flying. */
    fun folded(agent: String): Boolean {
        version
        return current?.agent == agent || queue.any { it.second == agent }
    }
    fun away(agent: String) = current?.let { it.agent == agent && it.pose != Pose.Fold } == true

    private fun nextAfter(agent: String?) {
        val next = queue.removeFirstOrNull()
        // The same agent's next message goes straight on: its activity is folded already; another's once folded.
        current = next?.let {
            val left = Pose.Fold.ms - (android.os.SystemClock.uptimeMillis() - it.third).toInt()
            Turn(it.first, it.second, if (it.second == agent || left <= 0) Pose.Float else Pose.Fold, fold = left.coerceAtLeast(0))
        }
    }

    private fun finish(turn: Turn) {
        done += turn.seq
        nextAfter(turn.agent)
    }

    /** Everything waiting or coming out shows at once, where it is. */
    fun release() {
        if (current == null && queue.isEmpty()) return
        queue.forEach { done += it.first }
        current?.let { done += it.seq }
        queue.clear()
        current = null
        version++
    }

    /** Plays the current pose, then moves on to the next (run again as `current` changes). */
    suspend fun play(turn: Turn) {
        val ready = when (turn.pose) {
            Pose.Fold -> true
            Pose.Float -> activityAvatars[turn.agent]?.isAttached == true && activityRows[turn.agent]?.isAttached == true
            Pose.Spit, Pose.Return -> activityAvatars[turn.agent]?.isAttached == true
        }
        if (!ready) return finish(turn)
        clock.snapTo(0f)
        val ms = when {
            turn.pose == Pose.Fold -> turn.fold
            turn.pose == Pose.Float && turn.from != null -> DROP_MS
            else -> turn.pose.ms
        }
        clock.animateTo(1f, tween(ms, easing = LinearEasing))
        // The next pose starts at its own beginning in the frame it takes over: drawn with this one's end (1) for a frame,
        // the avatar would be where the next ends (at home, or at the next message) and blink back.
        clock.snapTo(0f)
        when (turn.pose) {
            Pose.Fold -> current = Turn(turn.seq, turn.agent, Pose.Float)
            Pose.Float -> current = Turn(turn.seq, turn.agent, Pose.Spit)
            Pose.Spit -> {
                val next = queue.firstOrNull()
                val at = landed
                // The same agent's next message is waiting: the avatar drops on to it from here, not going home to hop again.
                if (next != null && next.second == turn.agent && at != null) {
                    queue.removeFirst()
                    done += turn.seq
                    current = Turn(next.first, next.second, Pose.Float, from = at)
                } else current = Turn(turn.seq, turn.agent, Pose.Return)
            }
            Pose.Return -> finish(turn)
        }
    }

    /**
     * Where the flying avatar's 18dp face is, in the pane, or null when none flies: each frame between where it set out
     * and where it is going, both read anew (the message growing moves the one, the activity pushed down the other).
     * Out (web useEmissions → float): thrown up from the avatar, it slows to the top (34dp over the higher end), hangs
     * a moment, then drops ever faster onto the landing, stretched more as it falls; across, it eases in and out.
     * Letting the message out (spit): flattened by the landing (116% wide, 80% high), it springs back (stiffness 520,
     * damping 14, as the web's), with a small swell. Home (return): eased cubic-out.
     */
    fun flight(density: Density): Flying? {
        val c = current ?: return null
        if (c.pose == Pose.Fold) return null
        val pane = pane?.takeIf { it.isAttached } ?: return null
        fun at(l: LayoutCoordinates?) = l?.takeIf { it.isAttached }?.let { pane.localPositionOf(it, Offset.Zero) }
        val avatar = at(activityAvatars[c.agent]) ?: return null
        // Before the message is in the list: where its avatar will be, the activity's place (the message comes in
        // there, and the activity moves down), 3dp down its row as a message's avatar sits.
        val landing = at(landings[c.seq]) ?: at(activityRows[c.agent])?.let { it + Offset(0f, with(density) { 3.dp.toPx() }) } ?: return null
        val t = clock.value
        return when (c.pose) {
            Pose.Float -> {
                // On from the message before it: only the drop.
                val start = c.from ?: avatar
                val rise = if (c.from != null) 0f else RISE
                val top = if (c.from != null) start.y else min(start.y, landing.y) - with(density) { HOP.toPx() }
                val up = if (rise > 0f) t / rise else 1f
                val down = (t - rise) / (1f - rise)
                val y = if (t < rise) start.y + (top - start.y) * (1f - (1f - up).pow(2.5f)) else top + (landing.y - top) * down.pow(2.5f)
                val across = if (t < 0.5f) 4f * t * t * t else 1f - (-2f * t + 2f).pow(3) / 2f
                val stretch = if (t < rise) 0.07f * sin(PI.toFloat() * up) else 0.14f * down * down
                Flying(Offset(start.x + (landing.x - start.x) * across, y), 1f - stretch * 0.6f, 1f + stretch)
            }
            Pose.Spit -> {
                landed = landing
                val k = settle(t * Pose.Spit.ms / 1000f)
                val swell = 1f + 0.12f * when {
                    t < 0.4f -> smooth(t / 0.4f)
                    t < 0.75f -> 1f - smooth((t - 0.4f) / 0.35f)
                    else -> 0f
                }
                Flying(landing, swell * (1f + 0.16f * k), swell * (1f - 0.2f * k))
            }
            else -> {
                val e = 1f - (1f - t) * (1f - t) * (1f - t)
                Flying(lerp(landing, avatar, e), 1f, 1f)
            }
        }
    }

    // ── a quoted message flashing ──

    /** The list's following, which a jump to a quoted message leaves (the reader's move), and the page's scope a jump
     *  runs in (the row it starts from may be scrolled away before its flash ends). */
    var follow: fail.still.android.ui.Follow? = null
    var scope: kotlinx.coroutines.CoroutineScope? = null
    private var flashes = 0

    /**
     * The message a quote last led to, by ts. As the web in Chrome, the quoted passage is marked in its words (`mark`:
     * the accent at 28% for 1600ms, then 12% until 2600ms, then gone; ::highlight(quote-flash) and flashRange); a
     * message whose words do not hold it (the mark never `found`) flashes whole instead (`flash`: web msgFlash, the
     * accent's ground held to 60% of 1400ms, then --ease-out to none).
     */
    var flashed by mutableStateOf<String?>(null)
        private set
    var mark by mutableStateOf<fail.still.android.ui.TextMark?>(null)
        private set
    val flash = Animatable(0f)
    private val marking = Animatable(0f)

    /** Starts marking `passage` in the message `ts` (drawn once its row composes); `flash` then plays it out. */
    fun lead(ts: String, passage: String, accent: Color) {
        flashes++
        flashed = ts
        mark = fail.still.android.ui.TextMark(passage, accent).also { it.level = 0.28f }
    }

    suspend fun flash() {
        val mine = flashes
        val m = mark
        try {
            kotlinx.coroutines.coroutineScope {
                launch {
                    flash.snapTo(1f)
                    // CSS keyframes ease each stretch on its own: 0-60% holds (its curve changes nothing), then --ease-out.
                    flash.animateTo(0f, keyframes { durationMillis = 1400; 1f at 0; 1f at 840 using Ease.Out; 0f at 1400 })
                }
                launch {
                    // Two steps, no easing (a highlight does not transition): 28% until 1600ms, 12% until 2600ms.
                    marking.snapTo(0.28f)
                    marking.animateTo(0f, keyframes { durationMillis = 2600; 0.28f at 0; 0.28f at 1599; 0.12f at 1600; 0.12f at 2599; 0f at 2600 }) {
                        m?.level = if (value >= 0.2f) 0.28f else if (value >= 0.1f) 0.12f else 0f
                    }
                }
            }
        } finally {
            if (flashes == mine) { flashed = null; mark = null }
        }
    }
}

/** The accent's ground (web --accent-bg in a chat: oklch(96.5% .025 45), dark oklch(30% .05 40)). */
@Composable
internal fun accentBg() = if (fail.still.android.ui.C.dark) Color(0xFF43251A) else Color(0xFFFFEFE6)

/** A quoted message flashing, its whole box on the accent's ground, rounded 12dp as the web's. */
internal fun Modifier.flashed(motion: ChatMotion?, ts: String?, color: Color): Modifier =
    if (motion == null || ts == null) this else drawBehind {
        if (motion.flashed != ts || motion.mark?.found == true) return@drawBehind
        drawRoundRect(color.copy(alpha = color.alpha * motion.flash.value), cornerRadius = CornerRadius(12.dp.toPx()))
    }

private fun lerp(a: Offset, b: Offset, t: Float) = Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

/** The hop: how high over the higher of its two ends, and the share of its time spent going up. */
private val HOP = 34.dp
private const val RISE = 0.42f
/** The same agent's next message, waiting as one comes out: the avatar drops on to it, no hop (how long). */
private const val DROP_MS = 280

/** What is left, at `s` seconds, of a spring let go from 1 (stiffness 520, damping 14, mass 1: under-damped). */
private fun settle(s: Float): Float {
    val w0 = sqrt(520f)
    val z = 14f / (2f * w0)
    val wd = w0 * sqrt(1f - z * z)
    return exp(-z * w0 * s) * (cos(wd * s) + z * w0 / wd * sin(wd * s))
}

private fun smooth(t: Float) = t * t * (3f - 2f * t)

/** Its top `share`, what shows of a message unrolling from its avatar (the web's clip-path inset from the bottom). */
private class TopShare(private val share: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density) =
        Outline.Rectangle(Rect(0f, 0f, size.width, size.height * share))
}

/**
 * A message coming out of its avatar (web emitOut, 380ms): scale .35 → 1 from 12dp 12dp, unrolling from the top, both
 * --ease-out over the whole; its opacity 0 → 1 by 35% (that stretch eased on its own), as CSS keyframes ease each stretch.
 */
internal fun Modifier.emitOut(motion: ChatMotion?, seq: Long): Modifier = if (motion == null) this else graphicsLayer {
    if (!motion.emitting(seq)) {
        scaleX = 1f; scaleY = 1f; alpha = 1f; clip = false; shape = RectangleShape
        return@graphicsLayer
    }
    val t = motion.clock.value
    val e = Ease.Out.transform(t)
    val corner = 12.dp.toPx()
    transformOrigin = TransformOrigin(if (size.width > 0) corner / size.width else 0f, if (size.height > 0) corner / size.height else 0f)
    scaleX = 0.35f + 0.65f * e; scaleY = scaleX
    alpha = if (t < 0.35f) Ease.Out.transform(t / 0.35f) else 1f
    clip = true
    shape = TopShare(e)
}
