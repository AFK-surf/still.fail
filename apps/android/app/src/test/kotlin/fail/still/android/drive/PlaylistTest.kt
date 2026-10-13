package fail.still.android.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaylistTest {
    private val video = { name: String -> name.endsWith(".mkv") || name.endsWith(".mp4") }

    @Test
    fun episodesSortByNumberNotByString() {
        assertEquals(listOf("E1.mkv", "E2.mkv", "E10.mkv"), playlistOf(listOf("E10.mkv", "E2.mkv", "E1.mkv"), video))
    }

    @Test
    fun nonMediaIsDropped() {
        assertEquals(listOf("E1.mkv"), playlistOf(listOf("E1.mkv", "E1.srt", "notes.txt"), video))
    }

    @Test
    fun nextFollowsTheCurrentFileAndStopsAtTheEnd() {
        val list = listOf("E1.mkv", "E2.mkv", "E3.mkv")
        assertEquals("E3.mkv", nextIn("E2.mkv", list))
        assertNull(nextIn("E3.mkv", list))
        // Missing from the listing: its name still says where it belongs.
        assertEquals("E3.mkv", nextIn("E2b.mkv", list))
    }

    @Test
    fun clockAndSpeed() {
        assertEquals("1:05", clock(65_000))
        assertEquals("1:58:04", clock(7_084_000))
        assertEquals("1.5×", speedLabel(1.5f))
        assertEquals("1×", speedLabel(1f))
    }
}
