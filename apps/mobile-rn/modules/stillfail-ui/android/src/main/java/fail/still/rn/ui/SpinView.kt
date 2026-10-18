package fail.still.rn.ui

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.view.View
import android.view.animation.LinearInterpolator
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.views.ExpoView

/**
 * A box that turns for ever while `spinning`, once each `period` ms (a spinner's ring): turned by an animator of its own
 * on the view itself, as Compose's infinite transition draws one, not by Reanimated: each frame of a Reanimated rotation is
 * a prop it keeps for the view and lays again over every commit of React's (a list of turning marks, scrolled, cost its
 * JS thread a second in every ten). Quiet as QuietView: its turning is not told to accessibility.
 */
class SpinView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private var animator: ObjectAnimator? = null
    var spinning = false
        set(value) { if (field != value) { field = value; update() } }
    var period = 1200L
        set(value) { if (field != value) { field = value; animator?.duration = value } }

    init {
        clipChildren = false
        clipToPadding = false
    }

    private fun update() {
        if (spinning && isAttachedToWindow) {
            if (animator == null) {
                animator = ObjectAnimator.ofFloat(this, View.ROTATION, 0f, 360f).apply {
                    duration = period
                    repeatCount = ValueAnimator.INFINITE
                    interpolator = LinearInterpolator()
                    start()
                }
            }
        } else {
            animator?.cancel()
            animator = null
            rotation = 0f
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        update()
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        animator = null
        super.onDetachedFromWindow()
    }

    override fun onViewAdded(child: View) {
        super.onViewAdded(child)
        child.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }

    override fun notifySubtreeAccessibilityStateChanged(child: View, source: View, changeType: Int) {}

    // React Native places what it holds (an ExpoView is a LinearLayout: SmoothView.kt).
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {}
}

class StillfailSpinModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("StillfailSpin")
        View(SpinView::class) {
            Prop("spinning") { view: SpinView, spinning: Boolean -> view.spinning = spinning }
            Prop("period") { view: SpinView, period: Double -> view.period = period.toLong() }
        }
    }
}
