package fail.still.rn.ui

import android.content.Context
import android.view.View
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.views.ExpoView

/**
 * A box whose insides move without the accessibility services hearing of it: what it holds turning or breathing
 * (a spinner, a pulse) sets a view's rotation, scale or alpha each frame, and Android tells every accessibility client
 * of each as a change in the window (View.notifySubtreeAccessibilityStateChangedIfNeeded), so the window is never idle
 * (UI Automator waits for idle; TalkBack hears a flood). Compose draws such motion in its draw phase, telling nobody.
 * Only for what moves without changing what it says.
 */
class QuietView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    init {
        // A plain box: what it holds may reach past it (a ring's halo), as from a View of React Native's.
        clipChildren = false
        clipToPadding = false
    }

    override fun notifySubtreeAccessibilityStateChanged(child: View, source: View, changeType: Int) {}
}

class StillfailQuietModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("StillfailQuiet")
    View(QuietView::class) {}
  }
}
