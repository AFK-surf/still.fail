// An image's ThumbHash as the station keeps it with the message (base64, made as it keeps the image,
// the Rust station's thumbs.rs): a blurred likeness of it, shown until the image itself loads (web/src/thumbhash.ts).
// The decoder is thumbhash's own (Evan Wallace, MIT), as the web uses it.
package fail.still.android.ui

import android.graphics.Bitmap
import android.util.Base64
import android.util.LruCache
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

object ThumbHash {
    private class Read(val image: ImageBitmap, val ratio: Float)

    private val drawn = LruCache<String, Any>(200)
    private val none = Any()

    private fun read(hash: String?): Read? {
        if (hash.isNullOrEmpty()) return null
        drawn.get(hash)?.let { return it as? Read }
        val got = try {
            val bytes = Base64.decode(hash, Base64.DEFAULT)
            val (w, h, rgba) = toRgba(bytes)
            val pixels = IntArray(w * h) { i -> (rgba[i * 4 + 3] shl 24) or (rgba[i * 4] shl 16) or (rgba[i * 4 + 1] shl 8) or rgba[i * 4 + 2] }
            Read(Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888).asImageBitmap(), ratio(bytes))
        } catch (_: Exception) {
            null
        }
        drawn.put(hash, got ?: none)
        return got
    }

    /** The likeness, about 32px across (the box it fills blurs it further), or null for none. */
    fun image(hash: String?): ImageBitmap? = read(hash)?.image

    /** The image's width over its height, near enough to size a box by. */
    fun ratio(hash: String?): Float? = read(hash)?.ratio

    private fun ratio(hash: ByteArray): Float {
        val header = hash[3].u
        val hasAlpha = hash[2].u and 0x80 != 0
        val isLandscape = hash[4].u and 0x80 != 0
        val lx = if (isLandscape) (if (hasAlpha) 5 else 7) else header and 7
        val ly = if (isLandscape) header and 7 else if (hasAlpha) 5 else 7
        return lx.toFloat() / ly
    }

    private val Byte.u get() = toInt() and 0xFF

    private fun toRgba(hash: ByteArray): Triple<Int, Int, IntArray> {
        val header24 = hash[0].u or (hash[1].u shl 8) or (hash[2].u shl 16)
        val header16 = hash[3].u or (hash[4].u shl 8)
        val lDc = (header24 and 63) / 63.0
        val pDc = ((header24 shr 6) and 63) / 31.5 - 1
        val qDc = ((header24 shr 12) and 63) / 31.5 - 1
        val lScale = ((header24 shr 18) and 31) / 31.0
        val hasAlpha = (header24 shr 23) != 0
        val pScale = ((header16 shr 3) and 63) / 63.0
        val qScale = ((header16 shr 9) and 63) / 63.0
        val isLandscape = (header16 shr 15) != 0
        val lx = max(3, if (isLandscape) (if (hasAlpha) 5 else 7) else header16 and 7)
        val ly = max(3, if (isLandscape) header16 and 7 else if (hasAlpha) 5 else 7)
        val aDc = if (hasAlpha) (hash[5].u and 15) / 15.0 else 1.0
        val aScale = (hash[5].u shr 4) / 15.0

        // The varying factors (saturation boosted by 1.25x to make up for quantization).
        val acStart = if (hasAlpha) 6 else 5
        var acIndex = 0
        fun channel(nx: Int, ny: Int, scale: Double): DoubleArray {
            val ac = ArrayList<Double>()
            for (cy in 0 until ny) {
                var cx = if (cy > 0) 0 else 1
                while (cx * ny < nx * (ny - cy)) {
                    ac += (((hash[acStart + (acIndex shr 1)].u shr ((acIndex and 1) shl 2)) and 15) / 7.5 - 1) * scale
                    acIndex++
                    cx++
                }
            }
            return ac.toDoubleArray()
        }
        val lAc = channel(lx, ly, lScale)
        val pAc = channel(3, 3, pScale * 1.25)
        val qAc = channel(3, 3, qScale * 1.25)
        val aAc = if (hasAlpha) channel(5, 5, aScale) else null

        val ratio = ratio(hash)
        val w = (if (ratio > 1) 32f else 32 * ratio).roundToInt()
        val h = (if (ratio > 1) 32 / ratio else 32f).roundToInt()
        val rgba = IntArray(w * h * 4)
        val fx = DoubleArray(7)
        val fy = DoubleArray(7)
        var i = 0
        for (y in 0 until h) for (x in 0 until w) {
            var l = lDc; var p = pDc; var q = qDc; var a = aDc
            for (cx in 0 until max(lx, if (hasAlpha) 5 else 3)) fx[cx] = cos(PI / w * (x + 0.5) * cx)
            for (cy in 0 until max(ly, if (hasAlpha) 5 else 3)) fy[cy] = cos(PI / h * (y + 0.5) * cy)
            var j = 0
            for (cy in 0 until ly) {
                var cx = if (cy > 0) 0 else 1
                val fy2 = fy[cy] * 2
                while (cx * ly < lx * (ly - cy)) { l += lAc[j] * fx[cx] * fy2; cx++; j++ }
            }
            j = 0
            for (cy in 0 until 3) {
                var cx = if (cy > 0) 0 else 1
                val fy2 = fy[cy] * 2
                while (cx < 3 - cy) { val f = fx[cx] * fy2; p += pAc[j] * f; q += qAc[j] * f; cx++; j++ }
            }
            if (aAc != null) {
                j = 0
                for (cy in 0 until 5) {
                    var cx = if (cy > 0) 0 else 1
                    val fy2 = fy[cy] * 2
                    while (cx < 5 - cy) { a += aAc[j] * fx[cx] * fy2; cx++; j++ }
                }
            }
            val b = l - 2.0 / 3 * p
            val r = (3 * l - b + q) / 2
            val g = r - q
            rgba[i] = (255 * min(1.0, r)).coerceAtLeast(0.0).toInt()
            rgba[i + 1] = (255 * min(1.0, g)).coerceAtLeast(0.0).toInt()
            rgba[i + 2] = (255 * min(1.0, b)).coerceAtLeast(0.0).toInt()
            rgba[i + 3] = (255 * min(1.0, a)).coerceAtLeast(0.0).toInt()
            i += 4
        }
        return Triple(w, h, rgba)
    }
}
