package fail.still.android.remote

import java.io.ByteArrayInputStream
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenClipsTest {
    private val signature = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)

    /** A "PNG" of `size` bytes: the signature, then filler. */
    private fun png(size: Int) = ByteArray(size).also { signature.copyInto(it) }

    @Test
    fun aPngIsKnownByItsSignature() {
        assertTrue(isPng(png(8)))
        assertTrue(isPng(png(100)))
        assertFalse(isPng(png(8).copyOf(7)))
        assertFalse(isPng(byteArrayOf(-1, -40, -1, -32, 0, 16, 74, 70, 73, 70)))
        assertFalse(isPng(ByteArray(0)))
    }

    /** A copied picture is taken only from a screen that says it carries pictures, a PNG within the bound. */
    @Test
    fun aCopiedPictureNeedsTheScreenToCarryPictures() {
        assertTrue(takesCopied(listOf("text", "png"), png(1000)))
        assertTrue(takesCopied(listOf("png"), png(CLIP_PNG_MAX)))
        // A station (or helper) from before pictures: none.
        assertFalse(takesCopied(listOf("text"), png(1000)))
        assertFalse(takesCopied(emptyList(), png(1000)))
        // Past the bound, not a PNG, nothing.
        assertFalse(takesCopied(listOf("text", "png"), png(CLIP_PNG_MAX + 1)))
        assertFalse(takesCopied(listOf("text", "png"), ByteArray(1000)))
        assertFalse(takesCopied(listOf("text", "png"), ByteArray(0)))
    }

    /** A paste sends the picture where the screen carries pictures, else the text; the rest is refused or empty. */
    @Test
    fun aPasteSendsWhatTheScreenCarries() {
        val both = listOf("text", "png")
        val text = listOf("text")
        assertEquals(PasteKind.IMAGE, pasteKind(both, image = true, text = false))
        assertEquals(PasteKind.IMAGE, pasteKind(both, image = true, text = true))
        assertEquals(PasteKind.TEXT, pasteKind(both, image = false, text = true))
        assertEquals(PasteKind.EMPTY, pasteKind(both, image = false, text = false))
        // A text-only screen (a browser tab, a station from before pictures): a picture is never sent.
        assertEquals(PasteKind.NO_IMAGES, pasteKind(text, image = true, text = false))
        assertEquals(PasteKind.TEXT, pasteKind(text, image = true, text = true))
        assertEquals(PasteKind.TEXT, pasteKind(text, image = false, text = true))
        // Not driving (no types): nothing goes.
        assertEquals(PasteKind.NO_IMAGES, pasteKind(emptyList(), image = true, text = false))
        assertEquals(PasteKind.NO_TEXT, pasteKind(emptyList(), image = false, text = true))
        assertEquals(PasteKind.NO_TEXT, pasteKind(listOf("png"), image = false, text = true))
    }

    @Test
    fun anImageIsAnImageType() {
        assertTrue(isImageType("image/png"))
        assertTrue(isImageType("image/jpeg"))
        assertTrue(isImageType("Image/HEIC"))
        assertFalse(isImageType("text/plain"))
        assertFalse(isImageType("application/octet-stream"))
        assertFalse(isImageType(null))
    }

    @Test
    fun aStreamIsReadWithinItsBound() {
        assertArrayEquals(ByteArray(0), readAtMost(ByteArrayInputStream(ByteArray(0)), 10))
        assertEquals(200_000, readAtMost(ByteArrayInputStream(ByteArray(200_000)), 200_000)!!.size)
        assertNull(readAtMost(ByteArrayInputStream(ByteArray(200_001)), 200_000))
    }

    /** A PNG goes as it is (within 8 MB); another kind as the converter makes it, held to the same bound. */
    @Test
    fun aPictureIsReadiedAsAPngWithinTheBound() {
        var converted = 0
        val convert = { _: ByteArray -> converted++; Readied.Png(png(2000)) as Readied }
        val same = png(5000)
        assertSame(same, (asPng(same, convert) as Readied.Png).bytes)
        assertEquals(Readied.TooLarge, asPng(png(CLIP_PNG_MAX + 1), convert))
        assertEquals(0, converted)

        val jpeg = byteArrayOf(-1, -40, -1, -32, 0, 16)
        assertEquals(2000, (asPng(jpeg, convert) as Readied.Png).bytes.size)
        assertEquals(1, converted)
        // Converted past the bound (a photo as PNG), unreadable, or nothing at all: not sent.
        assertEquals(Readied.TooLarge, asPng(jpeg) { Readied.Png(png(CLIP_PNG_MAX + 1)) })
        assertEquals(Readied.TooLarge, asPng(jpeg) { Readied.TooLarge })
        assertEquals(Readied.Unreadable, asPng(jpeg) { Readied.Unreadable })
        assertEquals(Readied.Unreadable, asPng(ByteArray(0), convert))
    }

    /** Copies kept in the cache: each a new file, the newest few kept, however quickly they come. */
    @Test
    fun theNewestCopiesAreKept() {
        val dir = ScreenClips.dir(Files.createTempDirectory("clips").toFile())
        try {
            val made = (1..5).map { ScreenClips.keep(dir, png(10 + it), now = 1_000) }
            assertEquals(5, made.map { it.name }.toSet().size)
            val left = dir.listFiles()!!.sortedBy { it.name }
            assertEquals(made.takeLast(ScreenClips.KEEP), left)
            assertEquals(15, left.last().length())
            assertTrue(made.last().name.endsWith(".png"))
            // Later (a new process, the clock on): still the newest last.
            val later = ScreenClips.keep(dir, png(9), now = 2_000_000_000_000)
            assertEquals(later, dir.listFiles()!!.maxBy { it.name })
            assertEquals(ScreenClips.KEEP, dir.listFiles()!!.size)
        } finally {
            dir.parentFile!!.deleteRecursively()
        }
    }
}
