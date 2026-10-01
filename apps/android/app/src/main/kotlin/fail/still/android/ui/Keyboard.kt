package fail.still.android.ui

import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imeAnimationSource
import androidx.compose.foundation.layout.imeAnimationTarget
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.app.MultiWindowModeChangedInfo
import androidx.core.util.Consumer
import kotlinx.coroutines.flow.collectLatest
import kotlin.math.roundToInt

private val LocalKeyboard = staticCompositionLocalOf<WindowInsets?> { null }

/** All keyboard-aware surfaces share one position, including sheets and the wide layout's corners. */
val WindowInsets.Companion.keyboard: WindowInsets
    @Composable get() = LocalKeyboard.current ?: ime

/**
 * In split screen, Android's WM Shell can animate the keyboard itself and dispatch only the final
 * IME insets to the app. Compose's imePadding then jumps. Supply the missing motion there, using
 * DisplayImeController's show/hide durations and curve. When Android dispatches animation frames,
 * keep following those instead; full-screen insets pass through untouched.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun KeyboardInsets(content: @Composable () -> Unit) {
    val activity = LocalActivity.current as? ComponentActivity
    var multiWindow by remember(activity) { mutableStateOf(activity?.isInMultiWindowMode == true) }
    DisposableEffect(activity) {
        val listener = Consumer<MultiWindowModeChangedInfo> { multiWindow = it.isInMultiWindowMode }
        activity?.addOnMultiWindowModeChangedListener(listener)
        onDispose { activity?.removeOnMultiWindowModeChangedListener(listener) }
    }
    val insets = rememberKeyboardInsets(WindowInsets.ime, WindowInsets.imeAnimationSource, WindowInsets.imeAnimationTarget, multiWindow)
    CompositionLocalProvider(LocalKeyboard provides insets, content = content)
}

@Composable
internal fun rememberKeyboardInsets(raw: WindowInsets, source: WindowInsets, target: WindowInsets, multiWindow: Boolean): WindowInsets {
    val density = LocalDensity.current
    val bottom = remember(raw, multiWindow, density) { Animatable(raw.getBottom(density).toFloat()) }
    var followingNative by remember(raw, multiWindow) { mutableStateOf(false) }
    LaunchedEffect(raw, source, target, density, multiWindow, bottom) {
        if (!multiWindow) return@LaunchedEffect
        var native = false
        snapshotFlow { Triple(raw.getBottom(density), source.getBottom(density), target.getBottom(density)) }
            .collectLatest { (height, from, to) ->
                val wasNative = native
                native = from != to
                if (native || wasNative) {
                    bottom.snapTo(height.toFloat())
                    followingNative = native
                }
                else bottom.animateTo(height.toFloat(), tween(
                    durationMillis = if (height > bottom.value) 275 else 340,
                    easing = FastOutSlowInEasing,
                ))
            }
    }
    val followed = remember(raw, source, target, bottom) { object : WindowInsets {
        override fun getLeft(density: Density, layoutDirection: LayoutDirection) = raw.getLeft(density, layoutDirection)
        override fun getTop(density: Density) = raw.getTop(density)
        override fun getRight(density: Density, layoutDirection: LayoutDirection) = raw.getRight(density, layoutDirection)
        override fun getBottom(density: Density): Int =
            if (followingNative || source.getBottom(density) != target.getBottom(density)) raw.getBottom(density)
            else bottom.value.roundToInt()
    } }
    return if (multiWindow) followed else raw
}
