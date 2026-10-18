// A call's bytes beside its JSON both ways through the real engine (Hermes, cpp/engine.cpp `receiveBytes`, `emitBytes`)
// and the real StillFailCore, with assets/bytes-echo.js in place of the core (docs/client-core.md "Protocol"): every
// byte value, an empty run, a 4 MB part, and a call with none.
package fail.still.core

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BytesBesideTest {
    @Test
    fun bytesGoAndComeBesideTheJson() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val script = instrumentation.context.assets.open("bytes-echo.js").use { it.readBytes() }
        val dir = File(instrumentation.targetContext.cacheDir, "bytes-core").apply { deleteRecursively(); mkdirs() }
        val core = StillFailCore(hermesEngines(instrumentation.targetContext, dir.path, "http://127.0.0.1:9", scriptOf = { script })).also { it.open() }
        for (sent in listOf(ByteArray(256) { it.toByte() }, ByteArray(0), ByteArray(4 * 1024 * 1024) { (it * 31).toByte() })) {
            val (answer, back) = core.callBytes("echo", buildJsonObject {}, sent)
            assertEquals(sent.size, answer.jsonObject["size"]!!.jsonPrimitive.int)
            assertArrayEquals(ByteArray(sent.size) { (255 - (sent[it].toInt() and 255)).toByte() }, back)
        }
        val (answer, back) = core.callBytes("echo", buildJsonObject {})
        assertEquals(JsonNull, answer.jsonObject["size"])
        assertNull(back)
    }
}
