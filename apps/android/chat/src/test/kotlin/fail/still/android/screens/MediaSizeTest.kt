package fail.still.android.screens

import org.junit.Assert.*
import org.junit.Test

class MediaSizeTest {
    @Test fun aFlatImageKeepsItsOwnProportions() {
        assertEquals(MediaSize(360f, 240f), mediaSize(1200f, 800f))
        assertEquals(MediaSize(360f, 31f), mediaSize(701f, 60f))
    }

    @Test fun aTinyImageIsDrawnTo40OnItsLongerSide() {
        assertEquals(MediaSize(40f, 40f), mediaSize(10f, 10f))
        assertEquals(MediaSize(40f, 27f), mediaSize(30f, 20f))
    }

    @Test fun aThinStripIsLetterboxedNotCropped() {
        val wide = mediaSize(2000f, 40f)
        assertEquals(360f to 16f, wide.width to wide.height)
        assertEquals(1f, wide.fit!!.first, 1e-4f)
        assertEquals(0.45f, wide.fit!!.second, 1e-4f)
        val video = mediaSize(640f, 40f, least = 96f)
        assertEquals(360f to 96f, video.width to video.height)
        assertEquals(22.5f / 96f, video.fit!!.second, 1e-4f)
    }
}
