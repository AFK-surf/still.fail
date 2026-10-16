package fail.still.android.remote

import fail.still.core.CoreException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ScreenDropsTest {
    @Test
    fun aPathIsTheFolderAndTheName() {
        assertEquals("/Users/me/Downloads/a.txt", dropPath("/Users/me/Downloads", "a.txt"))
        assertEquals("/Users/me/Downloads/a.txt", dropPath("/Users/me/Downloads/", "a.txt"))
        assertEquals("/a.txt", dropPath("/", "a.txt"))
        assertEquals("C:\\Users\\me\\Downloads\\a.txt", dropPath("C:\\Users\\me\\Downloads", "a.txt"))
    }

    @Test
    fun aLengthIsCountedToTheEnd() {
        assertEquals(0L, lengthOf(java.io.ByteArrayInputStream(ByteArray(0))))
        assertEquals(200_001L, lengthOf(java.io.ByteArrayInputStream(ByteArray(200_001))))
    }

    /** The station as it answers a name taken: 409 `exists` on the first part (or only the code, from the fake core). */
    private fun taken() = CoreException("exists", "there is already a file by that name", 409)

    @Test
    fun aTakenNameGoesUpUnderTheNextFreeOne() = runBlocking {
        val there = mutableSetOf("report.pdf", "report (1).pdf")
        val tried = mutableListOf<String>()
        val got = putFree("report.pdf") { name -> tried += name; if (name in there) throw taken() }
        assertEquals("report (2).pdf", got)
        assertEquals(listOf("report.pdf", "report (1).pdf", "report (2).pdf"), tried)
        // Free at once: as it is.
        assertEquals("notes", putFree("notes") {})
        // Taken said by its code alone; a name without an extension.
        assertEquals("Makefile (1)", putFree("Makefile") { if (it == "Makefile") throw CoreException("exists", "taken", null) })
    }

    @Test
    fun otherFailuresAreThrownAsTheyCame() {
        val e = assertThrows(CoreException::class.java) {
            runBlocking { putFree("a.txt") { throw CoreException("offline", "station 不在线", null) } }
        }
        assertEquals("offline", e.code)
        // A name never free (the station refusing each): not tried for ever.
        val tries = mutableListOf<String>()
        assertThrows(CoreException::class.java) { runBlocking { putFree("a.txt") { tries += it; throw taken() } } }
        assertEquals(51, tries.size)
    }
}
