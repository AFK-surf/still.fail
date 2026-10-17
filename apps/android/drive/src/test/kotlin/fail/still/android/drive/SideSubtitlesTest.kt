package fail.still.android.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SideSubtitlesTest {
    @Test
    fun theVideosNameWithoutItsExtensionCounts() {
        assertEquals("E01.srt", pickSubtitle("E01.mp4", listOf("E01.mp4", "E01.srt", "E02.srt")))
    }

    @Test
    fun theFullNameStillWinsOverTheStem() {
        assertEquals("E01.mp4.srt", pickSubtitle("E01.mp4", listOf("E01.srt", "E01.mp4.srt")))
    }

    @Test
    fun anExactNameBeatsALanguageTag() {
        assertEquals("E01.srt", pickSubtitle("E01.mkv", listOf("E01.zh.srt", "E01.srt")))
        assertEquals("E01.zh.srt", pickSubtitle("E01.mkv", listOf("E01.zh.srt", "E02.srt")))
    }

    @Test
    fun anotherEpisodesSubtitleIsNotPicked() {
        assertNull(pickSubtitle("E01.mp4", listOf("E010.srt", "E02.srt")))
    }
}
