// Frosted glass over a page's list (Haze; Android 12 and later blur, earlier
// ones get the tinted glass alone). The top bar is the page's paper, frosted,
// with a hairline under it as the capsules have round them. What sits at the
// bottom floats instead: capsules raised over the list, which runs on around
// them.
package dev.ember.android.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

/** A bar at the top of the page, over the list that `state` is the source of: frosted, a hairline along its bottom. */
@Composable
fun Modifier.glass(state: HazeState): Modifier {
    val bg = C.bg
    val line = C.line
    return hazeEffect(state) {
        backgroundColor = bg
        tints = listOf(HazeTint(bg.copy(alpha = 0.7f)))
        blurRadius = 24.dp
        noiseFactor = 0f
    }.drawWithContent {
        drawContent()
        val y = size.height - 0.25.dp.toPx()
        drawLine(line, Offset(0f, y), Offset(size.width, y), strokeWidth = 0.5.dp.toPx())
    }
}

/** The composer's capsule: its corner and the room inside it; what sits in it takes the corner that is concentric with it. */
val ComposerCorner = 26.dp
val ComposerInset = 8.dp
val InComposer = RoundedCornerShape(ComposerCorner - ComposerInset)

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
        // What is under it is not reached through it: a touch anywhere on the capsule, its gaps too, stays on it.
        .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } }
}
