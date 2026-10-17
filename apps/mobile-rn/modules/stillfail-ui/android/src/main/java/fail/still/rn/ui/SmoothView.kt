package fail.still.rn.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import android.view.ViewOutlineProvider
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.views.ExpoView

/**
 * A box with still.fail's corners: what it holds (its own background, set by React Native, included) is clipped to
 * them, its shadow follows them, and its line (`stroke`) is drawn along them over what it holds. Radii in dp.
 */
class SmoothView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private val density = resources.displayMetrics.density
    private val path = Path()
    private val box = RectF()
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    var radii = floatArrayOf(0f, 0f, 0f, 0f)
        set(value) { field = value; reshape() }
    var amount = 1f
        set(value) { field = value; reshape() }
    var strokeWidth = 0f
        set(value) { field = value; line.strokeWidth = value * density; invalidate() }
    var strokeColor = 0
        set(value) { field = value; line.color = value; invalidate() }

    init {
        clipToOutline = true
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                if (path.isEmpty) outline.setRect(0, 0, view.width, view.height) else outline.setPath(path)
            }
        }
        setWillNotDraw(false)
    }

    private fun reshape() {
        box.set(0f, 0f, width.toFloat(), height.toFloat())
        smoothPath(path, box, radii[0] * density, radii[1] * density, radii[2] * density, radii[3] * density, amount)
        invalidateOutline()
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        reshape()
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        if (strokeWidth <= 0f || line.color == 0) return
        // Inside the edge, as a CSS border: the outline's path stroked twice as wide, clipped to it.
        val save = canvas.save()
        canvas.clipPath(path)
        line.strokeWidth = strokeWidth * density * 2
        canvas.drawPath(path, line)
        canvas.restoreToCount(save)
    }
}
