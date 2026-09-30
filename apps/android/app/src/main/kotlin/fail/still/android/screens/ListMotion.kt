// How the home list's rows move when the list changes (web/src/listMotion.ts): each row is placed where it was and goes
// to where it is now (the lazy list's placement animation, FLIP), carrying on from wherever it had got to; one gone is
// drawn by a copy that shrinks and fades where it was, under the rows closing over it; one new grows in where it is. A
// row that overtakes others on its way up (a chat with a new message) passes over them on a ground of its own.
package fail.still.android.screens

import android.os.SystemClock
import androidx.compose.animation.core.AnimationVector
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.TwoWayConverter
import androidx.compose.animation.core.VectorizedFiniteAnimationSpec
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.unit.IntOffset
import fail.still.android.data.ChatDay
import fail.still.android.data.ChatItem

/** A row's key in the list, kept as it changes: a chat asked for here goes by its `clientKey` before and after its station makes it. */
internal fun rowKey(item: ChatItem): String = "${item.station}/${item.clientKey ?: item.id}"

internal fun dayKey(day: ChatDay): String = "h/${day.daysAgo}"

/** What leaves takes this long; the rest start closing over it a little after it begins to go. */
internal const val LEAVE_MS = 200
private const val CLOSE_DELAY_MS = 100L

/** Motion's `MOVE` (spring, visualDuration 0.28 s, no bounce): stiffness (2π / (0.28 × 1.2))², critically damped. */
private const val MOVE_STIFFNESS = 350f

/** The web's `cubic-bezier(0.2, 0.7, 0.2, 1)` for a row coming in, and CSS `ease-out`. */
internal val ArriveEasing = CubicBezierEasing(0.2f, 0.7f, 0.2f, 1f)
internal val CssEaseOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)

/** A row or day heading gone from the list, drawn where it was while it goes. */
internal class Ghost(val key: String, val y: Float, val item: ChatItem?, val label: String?, val at: Long)

/**
 * One list's motion: what it showed last (keys in order, and what each was), where each row is placed now, and what
 * the last change set going (rows coming in, rows lifted over others, copies of rows gone).
 */
@Stable
internal class ListMotion {
    private var was: List<String>? = null
    private var shown: Map<String, Any> = emptyMap()
    /** Where each row's top is in the list (its placement, moving or not), as last placed. */
    val placed = HashMap<String, Float>()
    /** Rows new since the last change, and when they came: they grow in when first drawn. */
    private val arrived = HashMap<String, Long>()
    /** Rows that went ahead of others, and when: they pass over them. */
    val lifted = mutableStateMapOf<String, Long>()
    val ghosts = mutableStateListOf<Ghost>()
    private var closeUntil = 0L

    /**
     * The list as drawn now, in order: sets what moves from what was drawn last. `visible` are the keys on screen (only
     * those leave by a copy). Nothing moves the first time, or with no motion wanted.
     */
    fun update(days: List<ChatDay>, visible: Set<String>, still: Boolean) {
        val keys = ArrayList<String>()
        val now = HashMap<String, Any>()
        for (day in days) {
            dayKey(day).let { keys += it; now[it] = day.label }
            for (item in day.items) rowKey(item).let { keys += it; now[it] = item }
        }
        val before = was
        if (before == keys) { shown = now; return }
        was = keys
        val old = shown
        shown = now
        // Nothing to move from (the list's first rows), or no motion wanted: only where they are is kept.
        if (before.isNullOrEmpty() || still) return
        val t = SystemClock.uptimeMillis()
        val oldSet = before.toHashSet()
        val newSet = keys.toHashSet()
        val gone = before.filter { it !in newSet }
        for (key in keys) if (key !in oldSet) arrived[key] = t
        // Which of the rows there before and now went ahead of others: they pass over the rest.
        val kept = keys.filter { it in oldSet }
        val keptBefore = before.filter { it in newSet }
        val rank = keptBefore.withIndex().associate { it.value to it.index }
        kept.forEachIndexed { i, key -> if (!key.startsWith("h/") && (rank[key] ?: i) > i) lifted[key] = t }
        for (key in gone) {
            val y = placed[key] ?: continue
            if (key !in visible) continue
            val what = old[key]
            ghosts += Ghost(key, y, what as? ChatItem, what as? String, t)
        }
        if (gone.isNotEmpty()) closeUntil = t + 50
        placed.keys.retainAll(newSet)
        arrived.keys.retainAll { t - (arrived[it] ?: 0) < 500 }
    }

    /** Whether the row came just now: it is then drawn growing in (once). */
    fun arriving(key: String): Boolean {
        val at = arrived.remove(key) ?: return false
        return SystemClock.uptimeMillis() - at < 400
    }

    /** How long a row waits before it moves: the rows closing over one gone start a little after it begins to go. */
    fun delayFor(key: String): Long =
        if (SystemClock.uptimeMillis() <= closeUntil && liftedAt(key) == null) CLOSE_DELAY_MS else 0L

    /** When the row went ahead of others, if that was just now (its ground lasts 480 ms). */
    fun liftedAt(key: String): Long? = lifted[key]?.takeIf { SystemClock.uptimeMillis() - it < 480 }

    /** A row's placement: the web's MOVE spring, after `delayFor` (asked when the move starts). */
    fun placement(key: String): FiniteAnimationSpec<IntOffset> =
        Delayed(spring(dampingRatio = 1f, stiffness = MOVE_STIFFNESS, visibilityThreshold = IntOffset.VisibilityThreshold)) { delayFor(key) }
}

/** `inner`, begun `delay()` ms late (read as it starts); held at its start meanwhile. */
private class Delayed<T>(private val inner: FiniteAnimationSpec<T>, private val delay: () -> Long) : FiniteAnimationSpec<T> {
    override fun <V : AnimationVector> vectorize(converter: TwoWayConverter<T, V>): VectorizedFiniteAnimationSpec<V> {
        val run = inner.vectorize(converter)
        val wait = delay() * 1_000_000L
        if (wait == 0L) return run
        return object : VectorizedFiniteAnimationSpec<V> {
            override fun getValueFromNanos(playTimeNanos: Long, initialValue: V, targetValue: V, initialVelocity: V): V =
                if (playTimeNanos < wait) initialValue else run.getValueFromNanos(playTimeNanos - wait, initialValue, targetValue, initialVelocity)
            override fun getVelocityFromNanos(playTimeNanos: Long, initialValue: V, targetValue: V, initialVelocity: V): V =
                if (playTimeNanos < wait) initialVelocity else run.getVelocityFromNanos(playTimeNanos - wait, initialValue, targetValue, initialVelocity)
            override fun getDurationNanos(initialValue: V, targetValue: V, initialVelocity: V): Long =
                wait + run.getDurationNanos(initialValue, targetValue, initialVelocity)
        }
    }
}

/**
 * `days` as shown: while `hold` (a finger on the list, or it scrolling), rows keep their places and their days, each
 * with what is new of it, so the row about to be tapped does not move away; ones gone go, new ones come in where they
 * would be. Let go, the list is as it is (web: useHeldOrder, there while the mouse is over the list).
 */
internal class HeldOrder {
    private var shown: List<ChatDay> = emptyList()

    fun of(days: List<ChatDay>, hold: Boolean): List<ChatDay> {
        if (!hold) { shown = days; return days }
        val fresh = HashMap<String, ChatItem>()
        for (day in days) for (item in day.items) fresh[rowKey(item)] = item
        val held = HashSet<String>()
        val out = shown.map { day -> day to day.items.mapNotNull { item -> fresh[rowKey(item)]?.also { held += rowKey(item) } }.toMutableList() }.toMutableList()
        // New rows go into their own day, where they would be in it (a day not shown yet comes in its place).
        for (day in days) day.items.forEachIndexed { i, item ->
            if (rowKey(item) in held) return@forEachIndexed
            var into = out.indexOfFirst { it.first.daysAgo == day.daysAgo }
            if (into < 0) {
                val at = out.indexOfFirst { it.first.daysAgo > day.daysAgo }
                into = if (at < 0) out.size else at
                out.add(into, day to mutableListOf())
            }
            val items = out[into].second
            items.add(minOf(i, items.size), item)
        }
        shown = out.map { (day, items) -> day.copy(items = items) }.filter { it.items.isNotEmpty() }
        return shown
    }
}

/**
 * The mark each chat has and since when, to know one that has just come: both lists pop it, also as its row is drawn
 * anew on the way to its new place (web: ChatMark.tsx `shown`). Fed from the whole list, so a row off screen as its
 * mark changes does not pop when scrolled to later.
 */
internal object MarksSeen {
    private val seen = HashMap<String, Pair<Any?, Long>>()

    fun note(key: String, tone: Any?) {
        val had = seen[key]
        if (had == null) seen[key] = tone to Long.MIN_VALUE
        else if (had.first != tone) seen[key] = tone to SystemClock.uptimeMillis()
    }

    /** Whether the mark came within the last 300 ms. */
    fun fresh(key: String): Boolean {
        val since = seen[key]?.second ?: return false
        return since != Long.MIN_VALUE && SystemClock.uptimeMillis() - since <= 300
    }
}
