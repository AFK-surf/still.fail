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
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
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

/**
 * A tap or a drag on what this is on lets go of what is being typed into, and the keyboard goes (what was typed stays).
 * It only watches: the tap or drag still goes to what is under the finger (a link, a button, the list's scroll). Going on
 * the finger lifted or moved past the slop, not as it comes down, so what is tapped does not move under it first. A long
 * press lets it be.
 */
@Composable
fun Modifier.letsGoOfKeyboard(): Modifier {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    return pointerInput(keyboard, focus) {
        val slop = viewConfiguration.touchSlop
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            var moved = Offset.Zero
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                val change = event.changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
                moved += change.positionChange()
                if (moved.getDistance() > slop) break
                // A long press is not a tap: it picks a passage there (MessagePick.kt), whose quote may want the keyboard.
                if (!change.pressed) {
                    if (change.uptimeMillis - down.uptimeMillis >= viewConfiguration.longPressTimeoutMillis) return@awaitEachGesture
                    break
                }
            }
            focus.clearFocus(); keyboard?.hide()
        }
    }
}
