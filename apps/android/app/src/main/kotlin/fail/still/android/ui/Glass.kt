// Frosted glass over a page's list (Haze; Android 12 and later blur, earlier
// ones get the tinted glass alone). The top bar is the page's paper, frosted,
// with a hairline under it as the capsules have round them. What sits at the
// bottom floats instead: capsules raised over the list, which runs on around
// them.
package fail.still.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.compositeOver
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
        blurRadius = cssBlur(24f)
        noiseFactor = 0f
    }.drawWithContent {
        drawContent()
        val y = size.height - 0.25.dp.toPx()
        drawLine(line, Offset(0f, y), Offset(size.width, y), strokeWidth = 0.5.dp.toPx())
    }
}

/** The web phone's `--raised` (mobile/styles/root.css.ts): white over the warm page, the wide screen's grey in the dark. */
val Raised: Color @Composable get() = if (C.dark) Color(0xFF2A2C31) else Color.White

/**
 * The blur radius that is CSS `blur(<px>)`: CSS gives the Gaussian's deviation, while Haze hands its radius to
 * RenderEffect.createBlurEffect, which takes a deviation of 0.57735 × radius + 0.5 from it (Skia's convertRadiusToSigma).
 */
fun cssBlur(px: Float) = ((px - 0.5f) / 0.57735f).dp

val GlassBlur = cssBlur(20f)

/** The composer's capsule: its corner and the room inside it; what sits in it takes the corner that is concentric with it. */
val ComposerCorner = 26.dp
val ComposerInset = 8.dp
val InComposer = RoundedCornerShape(ComposerCorner - ComposerInset)

/**
 * A capsule floating over the list that `state` is the source of: raised and frosted as the web phone's (pages.css.ts
 * mFloating: `--raised` at 72% over a 20px blur, no line round it, only a breath of shadow); `tint` for glass of
 * another colour (the new-chat disc's accent).
 */
@Composable
fun Modifier.floating(state: HazeState, shape: Shape, tint: Color = Raised): Modifier {
    val bg = C.bg
    return shadow(1.dp, shape, ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f))
        .clip(shape)
        .hazeEffect(state) {
            backgroundColor = bg
            tints = listOf(HazeTint(tint.copy(alpha = 0.72f)))
            blurRadius = GlassBlur
            noiseFactor = 0f
        }
        // What is under it is not reached through it: a touch anywhere on the capsule, its gaps too, stays on it.
        .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } }
}

/**
 * The same capsule where nothing runs under it (a new chat's choices and composer sit below its page, not over it):
 * the glass over the plain page, drawn as it comes out. Frosting there would blur what is outside the source and
 * smear its last row of pixels into the capsule.
 */
@Composable
fun Modifier.floatingStill(shape: Shape, tint: Color = Raised): Modifier {
    val ground = tint.copy(alpha = 0.72f).compositeOver(C.bg)
    return shadow(1.dp, shape, ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f))
        .clip(shape).background(ground)
        .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } }
}

