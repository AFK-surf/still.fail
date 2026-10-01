package fail.still.android.ui

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.MutableWindowInsets
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalLayoutApi::class)
class KeyboardInsetsTest {
    @get:Rule val rule = createComposeRule()
    private val raw = MutableWindowInsets()
    private val source = MutableWindowInsets()
    private val target = MutableWindowInsets()
    private val split = mutableStateOf(true)
    private lateinit var shown: WindowInsets
    private fun height() = shown.getBottom(Density(1f))
    private fun launch() {
        rule.setContent { shown = rememberKeyboardInsets(raw, source, target, split.value) }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
    }
    private fun endpoint(height: Int) {
        rule.runOnUiThread {
            val insets = WindowInsets(0, 0, 0, height)
            raw.insets = insets; source.insets = insets; target.insets = insets
        }
        rule.mainClock.advanceTimeByFrame()
    }

    @Test fun splitScreenEndpointsAnimateBothWaysAndReverse() {
        launch()
        endpoint(800)
        rule.mainClock.advanceTimeBy(96)
        val opening = height()
        assertTrue("opening has intermediate positions: $opening", opening in 1..799)
        endpoint(0)
        assertTrue("reversing must not jump to hidden", height() > 0)
        rule.mainClock.advanceTimeBy(400)
        assertEquals(0, height())
        endpoint(800)
        rule.mainClock.advanceTimeBy(350)
        assertEquals(800, height())
        endpoint(0)
        rule.mainClock.advanceTimeBy(96)
        assertTrue("closing has intermediate positions", height() in 1..799)
        rule.mainClock.advanceTimeBy(400)
        assertEquals(0, height())
    }

    @Test fun nativeFramesAndFullScreenPassThrough() {
        launch()
        rule.runOnUiThread { target.insets = WindowInsets(0, 0, 0, 800) }
        for (h in listOf(0, 100, 400, 799)) {
            rule.runOnUiThread { raw.insets = WindowInsets(0, 0, 0, h) }
            assertEquals("native frame must not be eased again", h, height())
            rule.mainClock.advanceTimeByFrame()
        }
        endpoint(800)
        rule.mainClock.advanceTimeByFrame()
        assertEquals(800, height())
        rule.runOnUiThread { split.value = false }
        rule.mainClock.advanceTimeByFrame()
        endpoint(0)
        assertEquals(0, height())
        endpoint(800)
        assertEquals(800, height())
    }
}
