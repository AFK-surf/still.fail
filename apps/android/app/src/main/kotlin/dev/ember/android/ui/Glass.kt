// Frosted glass over a page's list (Haze; Android 12 and later blur, earlier
// ones get the tinted glass alone). The top bar is the page's paper, frosted,
// with no hard edge: its glass fades out over a strip past its content. What
// sits at the bottom floats instead: capsules raised over the list, which runs
// on around them.
package dev.ember.android.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
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
            tints = listOf(HazeTint(bg.copy(alpha = 0.7f)))
            blurRadius = 24.dp
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

/** A capsule floating over the list that `state` is the source of: raised, frosted, with a hairline round it. */
@Composable
fun Modifier.floating(state: HazeState, shape: Shape): Modifier {
    val bg = C.bg
    val tint = if (C.dark) C.surface2 else C.surface
    return shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.25f), spotColor = Color.Black.copy(alpha = 0.25f))
        .clip(shape)
        .hazeEffect(state) {
            backgroundColor = bg
            tints = listOf(HazeTint(tint.copy(alpha = 0.72f)))
            blurRadius = 20.dp
            noiseFactor = 0f
        }
        .border(0.5.dp, C.line, shape)
}
