// The app's lazy lists, with keys that cannot crash it. Compose ends the app on a key used twice in one list
// (IllegalArgumentException "Key … was already used", or after it "layout state is not idle before measure starts"),
// and keys come from data the app does not control (an outgoing message's id, a file's name, a day's label): a chat's
// list crashed on two rows keyed o:out-1 when the core, restarted, named a message out-1 again (2026-10). Here a key
// seen again in a list is told (ListKeys.onDuplicate: the app reports it as a handled error, Crashes.kt) and its item
// keyed apart. LazyColumn and LazyRow are these, not foundation's: scripts/check.sh keeps the app importing them.
package fail.still.android.ui

import androidx.compose.foundation.OverscrollEffect
import androidx.compose.foundation.gestures.FlingBehavior
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberOverscrollEffect
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.lazy.LazyColumn as FoundationColumn
import androidx.compose.foundation.lazy.LazyRow as FoundationRow

/** The keys of one list as its content is built: each the first time, else told apart (a String, as Compose saves). */
class ListKeys(private val list: String) {
    private val seen = HashMap<Any, Int>()

    fun of(key: Any): Any {
        val n = (seen[key] ?: 0) + 1
        seen[key] = n
        if (n == 1) return key
        if (told.add("$list\u0000$key")) onDuplicate?.invoke(list, key.toString())
        return "$key\u0000$n"
    }

    companion object {
        /** Told of a key used twice: which kind of list (column, row) and the key. */
        @Volatile var onDuplicate: ((list: String, key: String) -> Unit)? = null
        /** What was told already: once a process (a list built again each frame would tell it each frame). */
        private val told = java.util.Collections.synchronizedSet(HashSet<String>())
    }
}

/** A list's content, its keys made unique: what the list's `item`s and `items` say goes through [keys] first. */
internal class Keyed(private val inner: LazyListScope, private val keys: ListKeys) : LazyListScope {
    override fun item(key: Any?, contentType: Any?, content: @Composable LazyItemScope.() -> Unit) =
        inner.item(key?.let(keys::of), contentType, content)

    override fun items(count: Int, key: ((index: Int) -> Any)?, contentType: (index: Int) -> Any?, itemContent: @Composable LazyItemScope.(index: Int) -> Unit) {
        // Made now, all of them: a list hands out its keys lazily, in whatever order it lays out.
        val made = key?.let { k -> Array(count) { keys.of(k(it)) } }
        inner.items(count, made?.let { m -> { i: Int -> m[i] } }, contentType, itemContent)
    }

    override fun stickyHeader(key: Any?, contentType: Any?, content: @Composable LazyItemScope.(Int) -> Unit) =
        inner.stickyHeader(key?.let(keys::of), contentType, content)
}

/** foundation's LazyColumn, its keys unique. */
@Composable
fun LazyColumn(
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    contentPadding: PaddingValues = PaddingValues(0.dp),
    reverseLayout: Boolean = false,
    verticalArrangement: Arrangement.Vertical = if (!reverseLayout) Arrangement.Top else Arrangement.Bottom,
    horizontalAlignment: Alignment.Horizontal = Alignment.Start,
    flingBehavior: FlingBehavior = ScrollableDefaults.flingBehavior(),
    userScrollEnabled: Boolean = true,
    overscrollEffect: OverscrollEffect? = rememberOverscrollEffect(),
    content: LazyListScope.() -> Unit,
) = FoundationColumn(modifier, state, contentPadding, reverseLayout, verticalArrangement, horizontalAlignment, flingBehavior, userScrollEnabled, overscrollEffect) {
    Keyed(this, ListKeys("column")).content()
}

/** foundation's LazyRow, its keys unique. */
@Composable
fun LazyRow(
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    contentPadding: PaddingValues = PaddingValues(0.dp),
    reverseLayout: Boolean = false,
    horizontalArrangement: Arrangement.Horizontal = if (!reverseLayout) Arrangement.Start else Arrangement.End,
    verticalAlignment: Alignment.Vertical = Alignment.Top,
    flingBehavior: FlingBehavior = ScrollableDefaults.flingBehavior(),
    userScrollEnabled: Boolean = true,
    overscrollEffect: OverscrollEffect? = rememberOverscrollEffect(),
    content: LazyListScope.() -> Unit,
) = FoundationRow(modifier, state, contentPadding, reverseLayout, horizontalArrangement, verticalAlignment, flingBehavior, userScrollEnabled, overscrollEffect) {
    Keyed(this, ListKeys("row")).content()
}
