// A drag on an inline visualization moves the chat's list as a drag on its words does, fling included: the same swipe
// over the page and over a message next to it sends the list as far. The page moves with the list under the finger,
// so a fling measured where the finger is on the page came out a fraction of the list's own.
package fail.still.android.motion

import android.content.Context
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.dp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Updates
import fail.still.android.ui.C
import fail.still.android.ui.LocalUi
import fail.still.android.ui.StillFailTheme
import fail.still.android.ui.VizFrame
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class VizFlingTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val page = """<div style="height:2000px;background:var(--e-paper)">一张很高的卡片</div>"""

    /** How far the list is from its top, its rows being as tall as they are made here. */
    private fun at(list: LazyListState, rowPx: Int, pagePx: Int): Int {
        val i = list.firstVisibleItemIndex
        return (if (i == 0) 0 else pagePx + (i - 1) * rowPx) + list.firstVisibleItemScrollOffset
    }

    @Test fun flingOverPageAsOverWords() {
        val h = Harness(rule)
        val context = rule.activity
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", "light").commit()
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val list = LazyListState()
        val density = context.resources.displayMetrics.density
        val rowPx = (100 * density).toInt()
        val pagePx = (400 * density).toInt()
        rule.setContent {
            StillFailTheme(false) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    LazyColumn(Modifier.fillMaxSize().background(C.bg).testTag("list"), state = list) {
                        // As tall as it says, at most MAX_HEIGHT: here held to 400dp so the list's rows are known.
                        item { Box(Modifier.fillMaxWidth().height(400.dp)) { VizFrame(page) } }
                        items(300) { Box(Modifier.fillMaxWidth().height(100.dp)) { Text("第 $it 条消息", color = C.ink) } }
                    }
                }
            }
        }
        rule.mainClock.autoAdvance = true
        // The page loaded and drawn.
        repeat(60) { Thread.sleep(30); rule.waitForIdle() }

        fun fling(fromDp: Float): Int {
            rule.runOnUiThread { runBlocking { list.scrollToItem(0) } }
            rule.waitForIdle()
            val before = at(list, rowPx, pagePx)
            rule.onNodeWithTag("list").performTouchInput {
                swipe(Offset(centerX, fromDp * density), Offset(centerX, (fromDp - 250) * density), durationMillis = 120)
            }
            rule.waitForIdle()
            return at(list, rowPx, pagePx) - before
        }

        // Over the page (its upper part on screen) and over the words below it, the same swipe.
        val overPage = fling(350f)
        val overWords = fling(700f)
        Log.i("motion", "viz fling: over the page $overPage px, over the words $overWords px")
        assertTrue("over the page $overPage px, over the words $overWords px", overWords > rowPx * 5)
        assertTrue("over the page $overPage px, over the words $overWords px", overPage > overWords * 0.85 && overPage < overWords * 1.15)
    }
}
