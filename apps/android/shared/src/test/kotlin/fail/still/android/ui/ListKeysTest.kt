package fail.still.android.ui

import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import org.junit.Assert.assertEquals
import org.junit.Test

class ListKeysTest {
    /** What a list was given: each item's key. */
    private class Taken : LazyListScope {
        val keys = mutableListOf<Any?>()
        override fun item(key: Any?, contentType: Any?, content: @Composable LazyItemScope.() -> Unit) { keys += key }
        override fun items(count: Int, key: ((index: Int) -> Any)?, contentType: (index: Int) -> Any?, itemContent: @Composable LazyItemScope.(index: Int) -> Unit) {
            repeat(count) { keys += key?.invoke(it) }
        }
        override fun stickyHeader(key: Any?, contentType: Any?, content: @Composable LazyItemScope.(Int) -> Unit) { keys += key }
    }

    @Test fun aKeyGivenTwiceInAListIsToldAndKeptApart() {
        val told = mutableListOf<String>()
        ListKeys.onDuplicate = { list, key -> told += "$list $key" }
        val taken = Taken()
        Keyed(taken, ListKeys("test-twice")).apply {
            item(key = "top") {}
            items(listOf("m:1", "o:out-1", "o:out-1"), key = { it }) {}
            item(key = "o:out-1") {}
        }
        assertEquals(5, taken.keys.toSet().size)
        assertEquals(listOf("top", "m:1", "o:out-1"), taken.keys.take(3))
        assertEquals(listOf("test-twice o:out-1"), told)
        ListKeys.onDuplicate = null
    }

    @Test fun keysOnceEachAreTheirOwn() {
        val taken = Taken()
        Keyed(taken, ListKeys("test-once")).apply { items(listOf(1, 2, 3), key = { it }) {} }
        assertEquals(listOf<Any?>(1, 2, 3), taken.keys)
    }
}
