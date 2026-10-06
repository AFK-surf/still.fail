// What the shared parts ask of the app they are drawn in (App.kt's AppState is it), so ui/ needs nothing of the app's.
package fail.still.android.ui

import androidx.compose.runtime.staticCompositionLocalOf
import fail.still.core.StillFailCore

interface UiHost {
    /** The core, for what a part fetches itself (a picture by its URL). */
    val core: StillFailCore

    /** Opens a link as the app does (still.fail's own in the app, the rest by the system); `orElse` when it cannot. */
    fun follow(url: String, orElse: () -> Unit)

    /** Says something at the bottom of the screen for a moment. */
    fun note(text: String)
}

val LocalUi = staticCompositionLocalOf<UiHost> { error("no app") }
