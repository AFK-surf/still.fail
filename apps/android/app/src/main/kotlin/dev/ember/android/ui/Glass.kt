// Frosted bars: a page's list runs under its top bar and its bottom one, and
// they show it through, blurred (Haze; Android 12 and later blur, earlier ones
// get the tinted glass alone). The tint is the page's paper, so the bars read
// as the page, not as panels on it; and a bar has no hard edge: its glass
// fades out over a strip past its content, toward the list.
package dev.ember.android.ui

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

/** Which side of the page a bar sits on: its glass fades toward the other. */
enum class Edge { Top, Bottom }

/** How far past a bar's content its glass runs, fading out. */
val GlassFade = 20.dp

/**
 * A bar over the list that `state` is the source of, with a strip of `GlassFade` added on its open side where the
 * glass fades out. The bar measures that much taller, and lists pad by its whole height: at rest nothing lies under
 * the fade, and what scrolls under the bar goes into the glass gradually.
 */
@Composable
fun Modifier.glass(state: HazeState, edge: Edge): Modifier {
    var height by remember { mutableIntStateOf(0) }
    val fade = with(LocalDensity.current) { GlassFade.toPx() }
    val bg = C.bg
    return onSizeChanged { height = it.height }
        .hazeEffect(state) {
            backgroundColor = bg
            tints = listOf(HazeTint(bg.copy(alpha = 0.55f)))
            blurRadius = 28.dp
            noiseFactor = 0f
            if (height > 0) {
                val solid = ((height - fade) / height).coerceIn(0f, 1f)
                mask = when (edge) {
                    Edge.Top -> Brush.verticalGradient(0f to Color.Black, solid to Color.Black, 1f to Color.Transparent)
                    Edge.Bottom -> Brush.verticalGradient(0f to Color.Transparent, 1f - solid to Color.Black, 1f to Color.Black)
                }
            }
        }
        .padding(fadePadding(edge, GlassFade))
}

private fun fadePadding(edge: Edge, fade: Dp) = when (edge) {
    Edge.Top -> PaddingValues(bottom = fade)
    Edge.Bottom -> PaddingValues(top = fade)
}
