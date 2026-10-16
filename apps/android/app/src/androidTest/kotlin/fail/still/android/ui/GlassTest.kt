// A capsule's glass when Haze has nothing to frost under it (its source not where it was last seen, as the keyboard
// comes up): its own ground, not clear over the page with its shadow showing through as a wide ring.
package fail.still.android.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class GlassTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun capsuleWithNothingToFrostKeepsItsGround() {
        val page = Color(0xFF606060)
        rule.setContent {
            Box(Modifier.fillMaxSize().background(page), contentAlignment = Alignment.Center) {
                Box(Modifier.testTag("capsule").size(240.dp, 120.dp).floating(HazeState(), RoundedCornerShape(ComposerCorner)))
            }
        }
        val ground = Color.White.copy(alpha = 0.72f).compositeOver(Light.bg)
        val shot = rule.onNodeWithTag("capsule").captureToImage().toPixelMap()
        for ((x, y) in listOf(shot.width / 2 to shot.height / 2, shot.width / 2 to shot.height - 4, 4 to shot.height / 2)) {
            val c = shot[x, y]
            val off = maxOf(abs(c.red - ground.red), abs(c.green - ground.green), abs(c.blue - ground.blue))
            assertTrue("($x, $y) is $c, not the capsule's ground $ground", off < 0.04f)
        }
    }

    /** A drag on a capsule over a list stays on the capsule: the list under it does not move. */
    @Test
    fun aDragOnTheCapsuleLeavesTheListUnderIt() {
        val list = LazyListState()
        rule.setContent {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LazyColumn(Modifier.fillMaxSize(), state = list) { items(100) { BasicText("row $it", Modifier.height(48.dp)) } }
                Box(Modifier.testTag("capsule").size(240.dp, 320.dp).floating(HazeState(), RoundedCornerShape(ComposerCorner)))
            }
        }
        rule.onNodeWithTag("capsule").performTouchInput { swipeUp(durationMillis = 1500) }
        rule.waitForIdle()
        assertEquals(0, list.firstVisibleItemIndex)
        assertEquals(0, list.firstVisibleItemScrollOffset)
    }

    /** What scrolls in a capsule scrolls under a drag on it (the `@` menu over the composer did not, 2026-10-17). */
    @Test
    fun whatScrollsInTheCapsuleScrolls() {
        val scroll = ScrollState(0)
        rule.setContent {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(Modifier.testTag("capsule").size(240.dp, 320.dp).floating(HazeState(), RoundedCornerShape(ComposerCorner)).verticalScroll(scroll)) {
                    repeat(30) { BasicText("row $it", Modifier.height(48.dp)) }
                }
            }
        }
        // Slowly, as a finger: each step within the touch slop, where a scroll gives up a drag consumed round it.
        rule.onNodeWithTag("capsule").performTouchInput { swipeUp(durationMillis = 1500) }
        rule.waitForIdle()
        assertTrue("it did not scroll", scroll.value > 0)
    }
}
