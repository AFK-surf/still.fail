// A list that keeps to its newest end (web/src/scroll.ts), with the reader not
// touching it: a new message arriving while the list is at its end is followed
// down until its top reaches the top, so a long one is read from its start;
// anything else growing below keeps the end in view. Any scroll it did not make
// itself (the reader's finger and its fling, a code box within it handing on
// at its edge, a jump) sets the new position, as the web's `moved`: once the
// list is at rest, at the end it follows again, elsewhere it stays put.
// Something the reader opens in the list (stay) is not new: it is not followed.
// The list growing shorter (the keyboard) keeps its bottom in place.
// A list whose end is not where it ends (short: a chat's window short of its
// newest) is never followed: what comes in below is a page read, not said.
// Following glides (scroll.ts glide): each frame covers the same share of what
// is left, 1 - e^(-dt/100ms), so a long way is quick and a goal that moves on
// (a reply still growing) is followed without a restart; the reader's finger
// takes the list from it at once. The list's first moments, and anything the
// list does not grow by (the keyboard), are taken at once.
package fail.still.android.ui

import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.min

class Follow(val list: LazyListState, private val margin: Int) {
    /** Until the list is first put in place (its end, a remembered place, the unread line) nothing is followed. */
    var placed by mutableStateOf(false)
    /** Half a second after it was placed: from then on what comes in is glided after. */
    internal var grown = false
    var on by mutableStateOf(false)
    /** Its end is not where it ends (a chat's window short of the newest): not followed, whatever is in view. */
    var short by mutableStateOf(false)
    /** The list at its end, and that the end: once at rest there, it follows. */
    fun atEnd() = !short && !list.canScrollForward
    /** The message being followed, by key: kept in view from its top. */
    var anchor by mutableStateOf<Any?>(null)
    /** Where an item is, by key (-1: not in the list). */
    var indexOf: (Any) -> Int = { -1 }
    /** Someone else moved the list since it was last at rest. */
    internal var touched = false
    /** How many of its own scrolls are going (snapshot state: read with the list's scrolling). */
    internal var own by mutableStateOf(0)

    private suspend fun <T> mine(block: suspend () -> T): T {
        own++
        try { return block() } finally { own-- }
    }

    /** The reader opened something in the list to read it: what it grows by is not new, so not followed. */
    fun stay() {
        if (!placed) return
        on = false
        anchor = null
    }

    suspend fun toEnd(): Unit = mine {
        val info = list.layoutInfo
        val count = info.totalItemsCount
        if (count == 0) return@mine
        // Jumping to an item throws away what is on screen and composes it again; with the last one already in
        // view (most of the time: following), scrolling the rest of the way keeps what is there.
        if ((info.visibleItemsInfo.lastOrNull()?.index ?: -1) < count - 1) list.scrollToItem(count - 1)
        // Past the last item's top to its end, however tall it has grown.
        list.scrollBy(1_000_000f)
    }

    /** Back to the newest, following again: it glides there (web: the pane's `to-bottom`). */
    suspend fun jump() {
        anchor = null
        on = true
        glide()
    }

    internal suspend fun hold(): Unit = mine {
        // What a newly opened list first shows (images loading, the rest of it coming in) is taken at once.
        if (grown) return@mine glide()
        val at = anchor?.let(indexOf)?.takeIf { it >= 0 }
        // The list stops at its end by itself, so this is the anchor's top or the end, whichever comes first.
        if (at != null) list.scrollToItem(at, -margin) else if (list.canScrollForward) toEnd()
    }

    /**
     * How far down the goal is (the anchor's top, else the end; whichever comes first), in pixels, as the list is laid
     * out now; null when the anchor is above what is laid out (taken at once instead). What is not laid out yet is
     * reckoned by the rows that are, and read again each frame as it comes in.
     */
    private fun left(): Float? {
        val info = list.layoutInfo
        val shown = info.visibleItemsInfo
        val last = shown.lastOrNull() ?: return 0f
        val count = info.totalItemsCount
        val spacing = info.mainAxisItemSpacing
        val bottom = last.offset + last.size
        val average = shown.sumOf { it.size } / shown.size + spacing
        val end = (bottom - (info.viewportEndOffset - info.afterContentPadding)).toFloat() + (count - 1 - last.index) * average
        val at = anchor?.let(indexOf)?.takeIf { it >= 0 } ?: return end
        val top = shown.firstOrNull { it.index == at }?.offset
            ?: if (at < shown.first().index) return null else bottom + spacing + (at - last.index - 1) * average
        return min((top - margin).toFloat(), end)
    }

    /** Glides to the goal (see left), each frame 1 - e^(-dt/100ms) of what is left, slowed as the system slows animations. */
    private suspend fun glide(): Unit = mine {
        val scale = (currentCoroutineContext()[MotionDurationScale]?.scaleFactor ?: 1f).coerceAtLeast(0.001f)
        // Far below what is laid out (the newest many rows away), it goes most of the way at once: the list would lay
        // out every row it passes in one frame.
        val info = list.layoutInfo
        val lastShown = info.visibleItemsInfo.lastOrNull()?.index ?: return@mine
        if (anchor == null && info.totalItemsCount - 1 - lastShown > 12) list.scrollToItem(info.totalItemsCount - 1 - 6)
        var above = false
        list.scroll {
            var last = -1L
            while (true) {
                val left = left()
                if (left == null) { above = true; return@scroll }
                // Nearly there, or the goal back up (the content grew shorter): put there at once, as the web does.
                if (left < 1f) { if (abs(left) > 0.01f) scrollBy(left); return@scroll }
                val now = withFrameNanos { it }
                val dt = if (last < 0) 16f else min(64f, (now - last) / 1_000_000f)
                last = now
                // The list lays out whole pixels (a fraction waits for the next): the tail goes at least one a frame,
                // so it lands exactly instead of waiting on fractions that may never add up.
                val step = (left * (1f - exp(-dt / (100f * scale)))).let { if (it < 1f) minOf(left, 1f) else it }
                val used = scrollBy(step)
                // The list's end reached before the goal.
                if (abs(used) < 0.5f && abs(step) >= 0.5f) return@scroll
            }
        }
        if (above) anchor?.let(indexOf)?.takeIf { it >= 0 }?.let { list.scrollToItem(it, -margin) }
    }
}

@Composable
fun rememberFollow(list: LazyListState): Follow {
    val margin = with(LocalDensity.current) { 12.dp.roundToPx() }
    val follow = remember(list) { Follow(list, margin) }
    LaunchedEffect(follow) {
        launch {
            snapshotFlow { follow.placed }.first { it }
            delay(500)
            follow.grown = true
        }
        // A scroll it did not make itself, once the list is at rest: at the end it follows again, elsewhere it stops.
        launch {
            snapshotFlow { list.isScrollInProgress to (follow.own > 0) }.collect { (scrolling, own) ->
                if (scrolling && !own && follow.placed) { follow.touched = true; follow.anchor = null }
                if (!scrolling && follow.touched) { follow.touched = false; follow.on = follow.atEnd() }
            }
        }
        // Short of its end, nothing is followed; back at it (the last page in), at rest at the end it follows again.
        launch {
            snapshotFlow { follow.short }.collect { short ->
                if (short) { follow.on = false; follow.anchor = null }
                else if (follow.placed && !follow.on && !list.isScrollInProgress) follow.on = !list.canScrollForward
            }
        }
        // The list itself grew shorter or taller (the keyboard coming up, or going): what was at its bottom stays at
        // its bottom, as the web keeps the distance from the bottom through a resize.
        launch {
            var last = -1
            snapshotFlow { list.layoutInfo.viewportSize.height }.collect { h ->
                if (last > 0 && h > 0 && h != last && follow.placed) { follow.own++; try { list.scrollBy((last - h).toFloat()) } finally { follow.own-- } }
                if (h > 0) last = h
            }
        }
        // The content changed while following: hold the anchor, or the end.
        snapshotFlow {
            val info = list.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()
            listOf(info.totalItemsCount, last?.index, last?.size, follow.placed && follow.on, follow.anchor)
        }.collect {
            if (!follow.placed || !follow.on || follow.short || list.isScrollInProgress) return@collect
            // A glide the reader's finger took over ends here; one another scroll (the keyboard's) cut short goes on.
            while (follow.on && !follow.short && !follow.touched) {
                try { follow.hold(); break } catch (e: CancellationException) { currentCoroutineContext().ensureActive(); withFrameNanos { } }
            }
        }
    }
    return follow
}

/** Whether the reader is away from the end, by more than a corner of the screen. */
@Composable
fun awayFromEnd(list: LazyListState): Boolean {
    val corner = with(LocalDensity.current) { 120.dp.toPx() }
    val away by remember(list) {
        derivedStateOf {
            val info = list.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull() ?: return@derivedStateOf false
            last.index < info.totalItemsCount - 1 || last.offset + last.size - info.viewportEndOffset > corner
        }
    }
    return away
}

/** Whether the list's end is in view, all of its last item: the reader has seen the newest. */
@Composable
fun endInView(list: LazyListState): Boolean {
    val seen by remember(list) {
        derivedStateOf {
            val info = list.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()
            last != null && last.index == info.totalItemsCount - 1 && last.offset + last.size <= info.viewportEndOffset + 2
        }
    }
    return seen
}
