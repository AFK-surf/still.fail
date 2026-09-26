// Frosted bars: a page's list runs under its top bar and its bottom one, and
// they show it through, blurred (Haze; Android 12 and later blur, earlier ones
// get the tinted glass alone). The tint is the page's paper, so the bars read
// as the page, not as panels on it.
package dev.ember.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

@Composable
fun glassStyle(): HazeStyle = HazeStyle(backgroundColor = C.bg, tint = HazeTint(C.bg.copy(alpha = 0.72f)), blurRadius = 24.dp, noiseFactor = 0f)

/** A bar over the list that `state` is the source of. */
@Composable
fun Modifier.glass(state: HazeState): Modifier = hazeEffect(state, glassStyle())
