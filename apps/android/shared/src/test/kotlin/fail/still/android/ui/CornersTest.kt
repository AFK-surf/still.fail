package fail.still.android.ui

import kotlin.math.abs
import kotlin.math.pow
import org.junit.Assert.*
import org.junit.Test

class CornersTest {
    /** The cubics of a corner walked: each point, and the direction the curve has there. */
    private fun walk(k: FloatArray, each: (x: Double, y: Double, dx: Double, dy: Double) -> Unit) {
        var x0 = 1.0; var y0 = 0.0
        for (i in k.indices step 6) {
            for (j in 0..20) {
                val t = j / 20.0; val u = 1 - t
                val x = u * u * u * x0 + 3 * u * u * t * k[i] + 3 * u * t * t * k[i + 2] + t * t * t * k[i + 4]
                val y = u * u * u * y0 + 3 * u * u * t * k[i + 1] + 3 * u * t * t * k[i + 3] + t * t * t * k[i + 5]
                val dx = 3 * u * u * (k[i] - x0) + 6 * u * t * (k[i + 2] - k[i]) + 3 * t * t * (k[i + 4] - k[i + 2])
                val dy = 3 * u * u * (k[i + 1] - y0) + 6 * u * t * (k[i + 3] - k[i + 1]) + 3 * t * t * (k[i + 5] - k[i + 3])
                each(x, y, dx, dy)
            }
            x0 = k[i + 4].toDouble(); y0 = k[i + 5].toDouble()
        }
    }

    @Test fun aSmoothCornerIsTheWebsSuperellipse() {
        // Within a hundredth of a pixel of |x|^n + |y|^n = 1 over a radius of 200 pixels (more than any the app has at 4×).
        // Half way to it (a box with half the room) the same, of the exponent half way.
        for (smooth in listOf(1f, 0.5f)) {
            val n = 2 + (SMOOTH_EXPONENT - 2.0) * smooth
            walk(smoothCorner(smooth)) { x, y, _, _ -> assertEquals(0.0, ((abs(x).pow(n) + abs(y).pow(n)).pow(1 / n) - 1) * 200, 0.01) }
        }
        assertEquals(2.0.pow(1.5), SMOOTH_EXPONENT.toDouble(), 1e-6)
    }

    @Test fun withNoSmoothingItIsACirclesArc() {
        walk(smoothCorner(0f)) { x, y, _, _ -> assertEquals(1.0, x * x + y * y, 1e-5) }
    }

    @Test fun itLeavesAlongTheEdgesAndOnlyEverTurnsOneWay() {
        for (smooth in listOf(0f, 0.3f, 1f)) {
            val k = smoothCorner(smooth)
            assertEquals(1f, k[0], 1e-6f)
            assertEquals(1f, k[k.size - 3], 1e-6f)
            assertEquals(0f, k[k.size - 2], 1e-6f); assertEquals(1f, k[k.size - 1], 1e-6f)
            // Convex: the direction keeps turning the same way, from straight up the one edge to straight back along the other.
            var px = 0.0; var py = 1.0
            walk(k) { _, _, dx, dy ->
                assertTrue("turned back at smooth $smooth", px * dy - py * dx >= -1e-6)
                assertTrue("went back at smooth $smooth", dx <= 1e-6 && dy >= -1e-6)
                if (dx != 0.0 || dy != 0.0) { px = dx; py = dy }
            }
        }
    }

    @Test fun aCornerIsAsSmoothAsItHasRoomFor() {
        // A capsule's end and a circle (the radius half the side) are not smoothed; a quarter more room, wholly.
        assertEquals(0f, smoothness(26f, 26f), 0f)
        assertEquals(0f, smoothness(999f, 26f), 0f)
        assertEquals(1f, smoothness(26f, 32.5f), 0f)
        assertEquals(1f, smoothness(12f, 200f), 0f)
        assertEquals(0.5f, smoothness(16f, 18f), 1e-6f)
        assertEquals(0f, smoothness(0f, 20f), 0f)
        // Growing, the radius drawn is never more than the room there is, and never jumps.
        var last = 26f
        for (i in 0..100) {
            val room = 26f + i * 0.1f
            val r = 26f * (1f + (SMOOTH_SCALE - 1f) * smoothness(26f, room))
            assertTrue(r <= room + 1e-4f)
            assertTrue(r - last in 0f..0.11f)
            last = r
        }
    }
}
