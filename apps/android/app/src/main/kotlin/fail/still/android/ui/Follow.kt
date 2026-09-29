// A list that keeps to its newest end (web/src/scroll.ts), with the reader not
// touching it: a new message arriving while the list is at its end is followed
// down until its top reaches the top, so a long one is read from its start;
// anything else growing below keeps the end in view. Scrolling by the reader
// sets the new position: at the end it follows again, elsewhere it stays put.
// The list growing shorter (the keyboard) keeps its bottom in place.
package fail.still.android.ui

import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

class Follow(val list: LazyListState, private val margin: Int) {
    /** Until the list is first put in place (its end, a remembered place, the unread line) nothing is followed. */
    var placed by mutableStateOf(false)
    var on by mutableStateOf(false)
    /** The message being followed, by key: kept in view from its top. */
    var anchor by mutableStateOf<Any?>(null)
    /** Where an item is, by key (-1: not in the list). */
    var indexOf: (Any) -> Int = { -1 }
    /** The reader's finger moved the list since the last scroll ended. */
    internal var touched = false

    suspend fun toEnd() {
        val info = list.layoutInfo
        val count = info.totalItemsCount
        if (count == 0) return
        // Jumping to an item throws away what is on screen and composes it again; with the last one already in
        // view (most of the time: following), scrolling the rest of the way keeps what is there.
        if ((info.visibleItemsInfo.lastOrNull()?.index ?: -1) < count - 1) list.scrollToItem(count - 1)
        // Past the last item's top to its end, however tall it has grown.
        list.scrollBy(1_000_000f)
    }

    /** Back to the newest, following again. */
    suspend fun jump() {
        anchor = null
        on = true
        toEnd()
    }

    internal suspend fun hold() {
        val at = anchor?.let(indexOf)?.takeIf { it >= 0 }
        // The list stops at its end by itself, so this is the anchor's top or the end, whichever comes first.
        if (at != null) list.scrollToItem(at, -margin) else if (list.canScrollForward) toEnd()
    }
}

@Composable
fun rememberFollow(list: LazyListState): Follow {
    val margin = with(LocalDensity.current) { 12.dp.roundToPx() }
    val follow = remember(list) { Follow(list, margin) }
    LaunchedEffect(follow) {
        launch {
            list.interactionSource.interactions.collect { if (it is DragInteraction.Start) { follow.touched = true; follow.anchor = null } }
        }
        // A scroll the reader made, ending at the end, follows again; ending elsewhere, it stops.
        launch {
            snapshotFlow { list.isScrollInProgress }.collect { scrolling ->
                if (!scrolling && follow.touched) { follow.touched = false; follow.on = !list.canScrollForward }
            }
        }
        // The list itself grew shorter or taller (the keyboard coming up, or going): what was at its bottom stays at
        // its bottom, as the web keeps the distance from the bottom through a resize.
        launch {
            var last = -1
            snapshotFlow { list.layoutInfo.viewportSize.height }.collect { h ->
                if (last > 0 && h > 0 && h != last && follow.placed) list.scrollBy((last - h).toFloat())
                if (h > 0) last = h
            }
        }
        // The content changed while following: hold the anchor, or the end.
        snapshotFlow {
            val info = list.layoutInfo
            val last = info.visibleItemsInfo.lastOrNull()
            listOf(info.totalItemsCount, last?.index, last?.size, follow.placed && follow.on, follow.anchor)
        }.collect { if (follow.placed && follow.on && !list.isScrollInProgress) follow.hold() }
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
