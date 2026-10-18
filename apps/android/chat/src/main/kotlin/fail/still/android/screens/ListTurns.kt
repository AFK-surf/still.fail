// What changes the height of a chat's list plays one at a time (web/src/listQueue.ts, docs/list-motion.md): words sent
// flying in from the composer, a message simply coming in, the agent's line coming, messages coming out of its avatar,
// a decision's options closing, what goes from under a post. Each waits its turn here, in the order they came; a turn
// is over once its own motion is and the list has stopped where it moved it to. What only fades, turns or changes its
// words is not in it. A row waiting its turn is not in the list yet: its room comes when its turn does.
package fail.still.android.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

/** The most a turn holds the next one back, whatever it does (one whose motion never ends). */
private const val MOST_MS = 3000L

@Stable
internal class ListTurns {
    // Fair: turns go in the order they were asked for.
    private val mutex = Mutex()
    /** Rows waiting their turn, by key: kept out of the list till then. */
    val waiting = mutableStateMapOf<String, Unit>()
    /** Words sent from the composer waiting their turn: their row kept out of the list, the words in the composer. */
    var sendWaiting by mutableStateOf(false)
        private set
    /** Whether the list is where it goes (no scroll of its own under way). */
    var still: () -> Boolean = { true }
    var scope: CoroutineScope? = null

    /** `block` (its motion, from its start to its end) in its turn; the next goes once it is over and the list still.
     *  `after`: asked for a couple of frames on, after what else changed with it (what closes under a post as an
     *  agent starts: the agent's line comes after it). */
    fun take(after: Boolean = false, block: suspend () -> Unit): Job? = scope?.launch {
        if (after) repeat(2) { withFrameNanos { } }
        mutex.withLock {
            withTimeoutOrNull(MOST_MS) { block() }
            // Looked at from two frames on (what it moved is laid out in the frame after it, the list sets out then).
            withTimeoutOrNull(MOST_MS) {
                var calm = 0
                while (calm < 2) { withFrameNanos { }; calm = if (still()) calm + 1 else 0 }
            }
        }
    }

    /** The row `key` comes into the list in its turn, its own motion taking `ms` (`after`: see take). */
    fun admit(key: String, ms: Long, after: Boolean = false) {
        if (key in waiting) return
        waiting[key] = Unit
        if (take(after) { waiting.remove(key); delay(ms) } == null) waiting.remove(key)
    }

    /** Words sent: their row comes in its turn, which lasts till they have landed (`landed`). */
    fun send(landed: suspend () -> Unit) {
        sendWaiting = true
        if (take { sendWaiting = false; landed() } == null) sendWaiting = false
    }
}

/**
 * `target` (something under a post shown or not: a decision's options, 忽略) as it shows, changed in its turn among what
 * changes the list's height: the change waits for it, and holds the next for `ms` (its motion) once made.
 */
@Composable
internal fun inTurn(target: Boolean, ms: Long): Boolean {
    val turns = LocalChatMotion.current?.turns ?: return target
    var shown by remember { mutableStateOf(target) }
    val latest by rememberUpdatedState(target)
    LaunchedEffect(target) {
        if (shown == target) return@LaunchedEffect
        turns.take { shown = latest; delay(ms) } ?: run { shown = target }
    }
    return shown
}
