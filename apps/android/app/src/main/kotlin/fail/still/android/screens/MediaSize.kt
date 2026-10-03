package fail.still.android.screens

/**
 * The box an image or video still takes in the chat, as web/src/imageBox.ts sizes it: its own proportions within
 * 360×300, a tiny one drawn to 40 on its longer side. A strip thinner than `least` there gets a box that thick all the
 * same and is letterboxed in it: fitted whole inside rather than filling (and cropped to) it, `fit` the share of the
 * box (of its width, of its height) it takes.
 */
data class MediaSize(val width: Float, val height: Float, val fit: Pair<Float, Float>? = null)

fun mediaSize(w: Float, h: Float, least: Float = 16f): MediaSize {
    val scale = minOf(maxOf(1f, 40f / maxOf(w, h)), 360f / w, 300f / h)
    val width = w * scale
    val height = h * scale
    if (width >= least && height >= least) return MediaSize(Math.round(width).toFloat(), Math.round(height).toFloat())
    val boxW = Math.round(maxOf(least, width)).toFloat()
    val boxH = Math.round(maxOf(least, height)).toFloat()
    val k = minOf(boxW / w, boxH / h)
    return MediaSize(boxW, boxH, w * k / boxW to h * k / boxH)
}
