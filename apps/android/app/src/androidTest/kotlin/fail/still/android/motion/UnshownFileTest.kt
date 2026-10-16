// A file the viewer cannot show is told of (name, size, kind) without being fetched; tapping Download fetches it.
package fail.still.android.motion

import android.content.Context
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Updates
import fail.still.android.data.Attachment
import fail.still.android.screens.FilePreview
import fail.still.android.screens.ViewerHost
import fail.still.android.ui.C
import fail.still.android.ui.LocalUi
import fail.still.android.ui.StillFailTheme
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class UnshownFileTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun open(name: String, bytes: ByteArray, dark: Boolean = false): Harness {
        val h = Harness(rule)
        val context = rule.activity
        h.fake.answer = { call, params ->
            when (call) {
                "station.file" -> buildJsonObject { put("type", "application/octet-stream"); put("bytes", Base64.encodeToString(bytes, Base64.NO_WRAP)) }
                "station.file.part" -> {
                    val length = params["length"]!!.jsonPrimitive.int
                    buildJsonObject { put("type", "application/octet-stream"); put("total", bytes.size); put("bytes", Base64.encodeToString(bytes.copyOf(minOf(length, bytes.size)), Base64.NO_WRAP)) }
                }
                else -> JsonNull
            }
        }
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", if (dark) "dark" else "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val file = Attachment(name, "ws/c-1/$name", bytes.size.toLong(), null, null)
        rule.setContent {
            StillFailTheme(dark) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.fillMaxSize().background(C.bg)) {
                        FilePreview(Fixtures.STATION, "ember:c-1", file) {}
                        ViewerHost()
                    }
                }
            }
        }
        h.settle()
        return h
    }

    /** Bytes no viewer here reads: a NUL among them. */
    private fun binary(size: Int) = ByteArray(size) { (it % 251).toByte() }

    @Test
    fun anApkIsToldOfAndFetchedOnlyWhenAsked() {
        val h = open("still.fail-beta-0.1.3021.apk", binary(3 * 1024 * 1024 + 4321))
        h.record("unshown-apk-light").apply { frame(); end() }
        assertFalse("not fetched whole on opening", h.fake.calls.any { it.first == "station.file" })
        val sniff = h.fake.calls.filter { it.first == "station.file.part" }
        assertEquals("only its first bytes read", listOf(8192), sniff.map { it.second["length"]!!.jsonPrimitive.int })
        rule.onNodeWithText("安装").assertExists()
        rule.onNodeWithText("这种文件没法在这里预览").assertExists()
        rule.onNodeWithText("下载").performClick()
        h.settle()
        assertTrue("fetched once asked", h.fake.calls.any { it.first == "station.file" })
    }

    @Test
    fun anUnknownBinaryInTheDark() {
        val h = open("weights.safetensors", binary(20 * 1024 * 1024), dark = true)
        h.record("unshown-binary-dark").apply { frame(); end() }
        assertFalse(h.fake.calls.any { it.first == "station.file" || it.first == "station.file.part" && it.second["length"]!!.jsonPrimitive.int != 8192 })
    }

    @Test
    fun textOfNoKnownKindIsShown() {
        val h = open("NOTES", "第一行\nsecond line\n".repeat(20).toByteArray())
        h.record("unshown-text").apply { frame(); end() }
        assertTrue("text is fetched to be shown", h.fake.calls.any { it.first == "station.file" })
        rule.onNodeWithText("下载").assertDoesNotExist()
    }
}
