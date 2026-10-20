// What the core keeps sealed, on a device (SecureStore.kt): the real engine (cpp/engine.cpp) running
// assets/secure-bridge.js, whose `secure.*` calls go to Kotlin and the Keystore and back, as client/core-ts
// hosts/bridge.ts's do. The person's prompt needs someone to answer it, so that test runs only when asked:
//   adb shell am instrument -w -e class fail.still.core.SecureStoreTest -e person yes fail.still.core.test/androidx.test.runner.AndroidJUnitRunner
// with a screen lock set (`adb shell locksettings set-pin 1234`) and then the PIN typed into the prompt
// (`adb shell input text 1234 && adb shell input keyevent 66`) or an enrolled finger touched (`adb -e emu finger touch 1`);
// `-e person no` expects the prompt to be cancelled (back).
package fail.still.core

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Base64
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/** The screen the prompt goes over. */
class PromptHost : Activity()

class SecureStoreTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context get() = instrumentation.targetContext
    private val sealed get() = File(context.filesDir, "stillfail-sealed")
    private lateinit var core: StillFailCore

    @Before
    fun start() {
        Foreground.watch(context)
        val script = instrumentation.context.assets.open("secure-bridge.js").use { it.readBytes() }
        val dir = File(context.cacheDir, "secure-core").apply { deleteRecursively(); mkdirs() }
        core = StillFailCore(hermesEngines(context, dir.path, "http://127.0.0.1:9", scriptOf = { script })).also { it.open() }
    }

    @After
    fun stop() = runBlocking {
        for (key in listOf("test-device", "test-moved", "test-person")) secure("delete", key)
    }

    private suspend fun secure(op: String, key: String, user: Boolean = false, value: ByteArray? = null, reason: String = ""): JsonObject =
        core.call("secure", buildJsonObject {
            put("op", op); put("key", key); put("user", user); put("reason", reason)
            if (value != null) put("value", Base64.getEncoder().encodeToString(value))
        }).jsonObject

    private fun valueOf(answer: JsonObject): ByteArray? = answer["value"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content?.let { Base64.getDecoder().decode(it) }

    private suspend fun failure(block: suspend () -> Unit): CoreException {
        try {
            block()
        } catch (e: CoreException) {
            return e
        }
        fail("it did not fail")
        throw IllegalStateException()
    }

    @Test
    fun keptWithoutThePerson() = runBlocking {
        val value = ByteArray(300) { (it * 7).toByte() }
        assertEquals(true, secure("get", "test-device")["json"]!!.jsonObject["none"]!!.jsonPrimitive.content.toBoolean())
        secure("set", "test-device", value = value)
        assertArrayEquals(value, valueOf(secure("get", "test-device")))

        // On the disk: sealed, the value not in it as it is.
        val file = File(sealed, "test-device")
        val blob = file.readBytes()
        assertEquals(1, blob[0].toInt())
        assertEquals(0, blob[1].toInt())
        assertFalse(String(blob, Charsets.ISO_8859_1).contains(String(value.copyOfRange(0, 16), Charsets.ISO_8859_1)))

        // Copied to another key, it does not open; nor with its `user` byte changed.
        file.copyTo(File(sealed, "test-moved"), overwrite = true)
        assertTrue(failure { secure("get", "test-moved") }.message.contains("AEADBadTag"))
        File(sealed, "test-moved").writeBytes(blob.copyOf().also { it[1] = 1 })
        assertTrue(failure { secure("get", "test-moved") }.message.contains("kept with user: true"))
        assertTrue(failure { secure("get", "test-device", user = true) }.message.contains("kept with user: false"))

        secure("delete", "test-device")
        assertFalse(file.exists())
        assertEquals(JsonNull, secure("get", "test-device")["value"])
    }

    @Test
    fun thePersonNeedsAScreenLock() = runBlocking {
        assumeFalse((context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceSecure)
        assertEquals("no_device_lock", failure { secure("set", "test-person", user = true, value = byteArrayOf(1)) }.message)
    }

    @Test
    fun thePersonIsAsked() = runBlocking {
        val said = InstrumentationRegistry.getArguments().getString("person")
        assumeTrue(said == "yes" || said == "no")
        assumeTrue((context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceSecure)
        // Without a screen of the app in front, nothing asks.
        val value = ByteArray(32) { it.toByte() }
        secure("set", "test-person", user = true, value = value)
        assertEquals(1, File(sealed, "test-person").readBytes()[1].toInt())
        assertEquals("not_in_front", failure { secure("get", "test-person", user = true, reason = "x") }.message)
        val host = instrumentation.startActivitySync(Intent(context, PromptHost::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        instrumentation.waitForIdleSync()
        try {
            if (said == "yes") assertArrayEquals(value, valueOf(secure("get", "test-person", user = true, reason = "open the test's sealed value")))
            else assertEquals("user_cancelled", failure { secure("get", "test-person", user = true, reason = "cancel this one") }.message)
        } finally {
            host.finish()
        }
    }
}
