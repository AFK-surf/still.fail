// A capsule's glass when Haze has nothing to frost under it (its source not where it was last seen, as the keyboard
// comes up): its own ground, not clear over the page with its shadow showing through as a wide ring.
package fail.still.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import kotlin.math.abs
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
}
