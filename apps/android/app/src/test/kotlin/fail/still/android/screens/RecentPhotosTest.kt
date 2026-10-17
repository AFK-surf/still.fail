package fail.still.android.screens

import org.junit.Assert.assertEquals
import org.junit.Test

/** ＋'s recent photos (Attach.kt `latest`): ranked by the latest time of each that can be believed. */
class RecentPhotosTest {
    private val now = 1_792_245_000L

    @Test fun newestFirstByTheirTimes() {
        val photos = listOf(GalleryPhoto(1, now - 3600, now - 3600, null), GalleryPhoto(2, now - 60, now - 60, now - 60), GalleryPhoto(3, now - 600, null, null))
        assertEquals(listOf(2L, 3L, 1L), latest(photos, now, 30))
    }

    @Test fun aTimeInMillisecondsIsTheSecondsItMeans() {
        // Saved a year ago by an app that wrote when in milliseconds: behind a screenshot of a minute ago.
        val photos = listOf(GalleryPhoto(1, (now - 31_536_000) * 1000, now - 31_536_000, null), GalleryPhoto(2, now - 60, now - 60, now - 60))
        assertEquals(listOf(2L, 1L), latest(photos, now, 30))
    }

    @Test fun aTimeAheadOfNowIsLeftOut() {
        val photos = listOf(GalleryPhoto(1, now + 30 * 86_400, now - 86_400 * 400, null), GalleryPhoto(2, now - 60, null, null))
        assertEquals(listOf(2L, 1L), latest(photos, now, 30))
    }

    @Test fun theLatestOfItsTimesRanksIt() {
        // Taken long ago, put in the gallery a moment ago (synced down): as new as when it came.
        val photos = listOf(GalleryPhoto(1, now - 10, now - 10, now - 86_400 * 900), GalleryPhoto(2, now - 60, now - 60, now - 60))
        assertEquals(listOf(1L, 2L), latest(photos, now, 30))
    }

    @Test fun sameTimeByIdAndNoMoreThanAsked() {
        val photos = (1L..40L).map { GalleryPhoto(it, now - 5, null, null) } + GalleryPhoto(99, null, null, null)
        assertEquals((40L downTo 11L).toList(), latest(photos, now, 30))
    }
}
