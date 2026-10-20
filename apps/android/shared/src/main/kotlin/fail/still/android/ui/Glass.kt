// Frosted glass over a page's list (Haze; Android 12 and later blur, earlier
// ones get the tinted glass alone). The top bar is the page's paper, frosted,
// with a hairline under it as the capsules have round them. What sits at the
// bottom floats instead: capsules raised over the list, which runs on around
// them.
package fail.still.android.ui

import androidx.compose.foundation.background
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
import dev.chrisbanes.haze.HazeInputScale
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

/**
 * What the app's glass blurs from: the page at a third of its pixels each way, so the blur (redone whenever anything
 * under it moves, a step of an at-work mark too) is about a ninth of the work at full size. Under the glass's 70% tint
 * the softer source does not show (2026-10-19, battery).
 */
val GlassScale: HazeInputScale = HazeInputScale.Fixed(1f / 3f)

/** A bar at the top of the page, over the list that `state` is the source of: frosted, a hairline along its bottom. */
@Composable
fun Modifier.glass(state: HazeState): Modifier {
    val bg = C.bg
    val line = C.line
    return hazeEffect(state) {
        backgroundColor = bg
        tints = listOf(HazeTint(bg.copy(alpha = 0.7f)))
        blurRadius = cssBlur(24f)
        inputScale = GlassScale
        noiseFactor = 0f
    }.drawWithContent {
        drawContent()
        val y = size.height - 0.25.dp.toPx()
        drawLine(line, Offset(0f, y), Offset(size.width, y), strokeWidth = 0.5.dp.toPx())
    }
}

/** The same glass as a band along the page's foot (a new chat's choices and composer stand on it), with no line. */
@Composable
fun Modifier.glassFoot(state: HazeState): Modifier {
    val bg = C.bg
    // The paper under the frost, for when Haze draws none (see floating).
    return background(bg).hazeEffect(state) {
        backgroundColor = bg
        tints = listOf(HazeTint(bg.copy(alpha = 0.7f)))
        blurRadius = cssBlur(24f)
        inputScale = GlassScale
        noiseFactor = 0f
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
val InComposer = Smooth(concentric(ComposerCorner, ComposerInset))
/** The files in it: as far from its edge as from its top (its room and 2 more, as the web phone's: ChatHost.css.ts), and
 *  rounded as its corner less that. */
val ComposerFilesIn = 10.dp
val InComposerFiles = Smooth(concentric(ComposerCorner, ComposerFilesIn))

/**
 * A capsule floating over the list that `state` is the source of: raised and frosted as the web phone's (pages.css.ts
 * mFloating: `--raised` at 72% over a 20px blur, no line round it, only a breath of shadow); `tint` for glass of
 * another colour (the new-chat disc's accent).
 */
@Composable
fun Modifier.floating(state: HazeState, shape: Shape, tint: Color = Raised): Modifier {
    val bg = C.bg
    // Its glass over the plain page under the frost: Haze draws nothing at all when what it frosts is not where it
    // last saw it (its source moved or resized under it, as the keyboard comes up), and the capsule would be clear,
    // showing its own shadow through it as a wide grey ring.
    val ground = tint.copy(alpha = 0.72f).compositeOver(bg)
    return shadow(1.dp, shape, ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f))
        .clip(shape).background(ground)
        .hazeEffect(state) {
            backgroundColor = bg
            tints = listOf(HazeTint(tint.copy(alpha = 0.72f)))
            blurRadius = GlassBlur
            inputScale = GlassScale
            noiseFactor = 0f
        }
        .keepsTouches()
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
        .keepsTouches()
}

/**
 * What is under a capsule is not reached through it: a touch anywhere on it, its gaps too, lands on it (the first thing
 * hit takes a touch, not the page under it). Only that: it consumes nothing, as what is in it (a list's scroll, a row's
 * tap) gives the drag or tap up when something round it has consumed it (2026-10-17: the `@` menu did not scroll).
 */
private fun Modifier.keepsTouches() = pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent() } }
