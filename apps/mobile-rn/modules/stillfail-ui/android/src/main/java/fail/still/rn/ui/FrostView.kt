package fail.still.rn.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.graphics.Shader
import android.os.Build
import android.view.ViewTreeObserver
import androidx.annotation.RequiresApi
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.views.ExpoView
import java.lang.ref.WeakReference

/**
 * What a frost blurs (Haze's hazeSource, Glass.kt): what this box holds is recorded into a RenderNode of its own, then
 * drawn from it; each FrostView naming this one (`name`) draws that same node again, blurred, on the GPU. Nothing is
 * drawn twice on the main thread and no bitmap is made: expo-blur's Android blur (Dimezis') drew the whole window into a
 * bitmap on the main thread each frame and uploaded it, for each glass on the screen (40% of the frames late scrolling
 * the chats on a phone).
 */
class BackdropView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    var name: String? = null
        set(value) {
            field?.let { if (sources[it]?.get() === this) sources.remove(it) }
            field = value
            if (value != null) sources[value] = WeakReference(this)
        }
    internal val node: RenderNode? = if (Build.VERSION.SDK_INT >= 31) RenderNode("stillfail-backdrop") else null
    /** Whether the node holds what this box drew last (a frost draws nothing from one never recorded). */
    internal var recorded = false

    init {
        clipChildren = false
        setWillNotDraw(false)
    }

    // React Native places what it holds (an ExpoView is a LinearLayout: SmoothView.kt).
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {}

    override fun dispatchDraw(canvas: Canvas) {
        val n = node
        if (n == null || !canvas.isHardwareAccelerated || Build.VERSION.SDK_INT < 31) { super.dispatchDraw(canvas); return }
        record(n, canvas)
    }

    @RequiresApi(31)
    private fun record(n: RenderNode, canvas: Canvas) {
        n.setPosition(0, 0, width, height)
        val inside = n.beginRecording(width, height)
        try { super.dispatchDraw(inside) } finally { n.endRecording() }
        recorded = true
        canvas.drawRenderNode(n)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        recorded = false
    }

    companion object {
        internal val sources = HashMap<String, WeakReference<BackdropView>>()
        fun find(name: String?): BackdropView? = name?.let { sources[it]?.get() }?.takeIf { it.isAttachedToWindow }
    }
}

/**
 * A frost (Haze's hazeEffect): `base` (the page's paper, as Haze's backgroundColor), then what the BackdropView named
 * `source` draws under this box, blurred `blurRadius` (dp, as Haze's: RenderEffect's radius). The tint over it and
 * what the glass holds are React Native's, drawn after. Before Android 12, or with no source drawn, the base alone.
 * The blurred node only refers to the source's: as the source draws anew (a list scrolled), the blur follows on the
 * render thread; this box records again only when where it is over the source changes.
 */
class FrostView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private val density = resources.displayMetrics.density
    var source: String? = null
        set(value) { field = value; invalidate() }
    var blurRadius = 0f
        set(value) { field = value; effectFor = -1f; invalidate() }
    var base = Color.TRANSPARENT
        set(value) { field = value; invalidate() }
    private val blur: RenderNode? = if (Build.VERSION.SDK_INT >= 31) RenderNode("stillfail-frost") else null
    private var effectFor = -1f
    private val mine = IntArray(2)
    private val theirs = IntArray(2)
    private var lastDx = Int.MIN_VALUE
    private var lastDy = Int.MIN_VALUE
    private var lastFound: WeakReference<BackdropView>? = null
    // Moved over its source (a page sliding, the bar rising), it draws again: a pre-draw look, before each frame.
    private val moved = ViewTreeObserver.OnPreDrawListener {
        val src = BackdropView.find(source)
        if (src !== lastFound?.get()) invalidate()
        else if (src != null) {
            offsetTo(src)
            if (theirs[0] != lastDx || theirs[1] != lastDy) invalidate()
        }
        true
    }

    init {
        setWillNotDraw(false)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {}

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnPreDrawListener(moved)
    }

    override fun onDetachedFromWindow() {
        viewTreeObserver.removeOnPreDrawListener(moved)
        super.onDetachedFromWindow()
    }

    /** Where the source is from this box, in theirs (dx, dy into `theirs`). */
    private fun offsetTo(src: BackdropView) {
        src.getLocationInWindow(theirs)
        getLocationInWindow(mine)
        theirs[0] -= mine[0]
        theirs[1] -= mine[1]
    }

    override fun onDraw(canvas: Canvas) {
        if (base != Color.TRANSPARENT) canvas.drawColor(base)
        val n = blur
        val src = BackdropView.find(source)
        lastFound = src?.let { WeakReference(it) }
        if (n == null || src == null || !src.recorded || !canvas.isHardwareAccelerated || Build.VERSION.SDK_INT < 31) return
        // Inside what it would blur, it would draw itself into itself: the base alone (a frost wired to the wrong source).
        var up = parent
        while (up != null) { if (up === src) return; up = up.parent }
        frost(n, src, canvas)
    }

    @RequiresApi(31)
    private fun frost(n: RenderNode, src: BackdropView, canvas: Canvas) {
        val from = src.node ?: return
        offsetTo(src)
        lastDx = theirs[0]; lastDy = theirs[1]
        if (effectFor != blurRadius) {
            val r = blurRadius * density
            n.setRenderEffect(if (r > 0f) RenderEffect.createBlurEffect(r, r, Shader.TileMode.CLAMP) else null)
            effectFor = blurRadius
        }
        n.setPosition(0, 0, width, height)
        val inside = n.beginRecording(width, height)
        try {
            inside.translate(lastDx.toFloat(), lastDy.toFloat())
            inside.drawRenderNode(from)
        } finally { n.endRecording() }
        canvas.drawRenderNode(n)
    }
}

class StillfailBackdropModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("StillfailBackdrop")
        View(BackdropView::class) {
            Prop("name") { view: BackdropView, name: String? -> view.name = name }
        }
    }
}

class StillfailFrostModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("StillfailFrost")
        View(FrostView::class) {
            Prop("source") { view: FrostView, source: String? -> view.source = source }
            Prop("blurRadius") { view: FrostView, radius: Double -> view.blurRadius = radius.toFloat() }
            Prop("base") { view: FrostView, color: Color? -> view.base = color?.toArgb() ?: Color.TRANSPARENT }
        }
    }
}
