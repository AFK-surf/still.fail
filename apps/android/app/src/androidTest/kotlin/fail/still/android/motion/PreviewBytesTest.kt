// A web service's page in the preview, its bytes never base64 on the way to the station: a request's body goes beside
// its `station.preview` call, the answer's body comes beside each `{chunk: true}`; the page's own fetch() gets it over
// its port as bytes where the WebView can (PreviewWeb.kt fetchBytes), whole and in order.
package fail.still.android.motion

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import fail.still.android.Screen
import fail.still.android.data.Job
import fail.still.android.data.Topics
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

class PreviewBytesTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun webViews(v: View, out: MutableList<WebView> = ArrayList()): List<WebView> {
        if (v is WebView) out += v
        if (v is ViewGroup) for (i in 0 until v.childCount) webViews(v.getChildAt(i), out)
        return out
    }

    /** What the page's script below says as its title, once it has it. */
    private fun title(): String? {
        val got = CompletableFuture<String?>()
        rule.runOnUiThread { got.complete(webViews(rule.activity.window.decorView).firstOrNull()?.title) }
        return got.get(5, TimeUnit.SECONDS)
    }

    @Test fun aFetchsBodyAndAnswerGoAsBytes() {
        val h = Harness(rule)
        // Every byte value, so none is changed on the way; the answer three of the WebView's reads long.
        val sent = ByteArray(256) { it.toByte() }
        val answer = ByteArray(700_000) { (it * 7 % 251).toByte() }
        val page = """<!doctype html><html><head><title>…</title></head><body><script>
            const sent = new Uint8Array(256).map((_, i) => i);
            fetch("/echo", { method: "POST", body: sent }).then((r) => r.arrayBuffer()).then((b) => {
              const got = new Uint8Array(b);
              let sum = 0;
              for (let i = 0; i < got.length; i++) sum = (sum * 31 + got[i]) >>> 0;
              document.title = "bytes=" + StillFailPreviewNative.fetchBytes() + " n=" + got.length + " sum=" + sum;
            }, (e) => { document.title = "failed " + e; });
            </script></body></html>""".toByteArray()
        var sum = 0L
        for (b in answer) sum = (sum * 31 + (b.toInt() and 0xff)) and 0xffffffffL
        /** The bytes beside each path's call (empty: none). */
        val asked = java.util.concurrent.ConcurrentHashMap<String, ByteArray>()
        h.fake.talks["station.preview"] = { params, bytes, say ->
            val path = params["path"]!!.jsonPrimitive.content
            asked[path] = bytes ?: ByteArray(0)
            val (type, body) = when (path) {
                "/" -> "text/html" to page
                "/echo" -> "application/octet-stream" to answer
                else -> "text/plain" to ByteArray(0)
            }
            say(buildJsonObject {
                put("head", buildJsonObject {
                    put("status", if (body.isEmpty()) 404 else 200)
                    putJsonArray("headers") { add(JsonArray(listOf(JsonPrimitive("content-type"), JsonPrimitive(type)))) }
                })
            }, null)
            // In the pieces the core gives them (64 KB).
            var at = 0
            while (at < body.size) {
                val n = minOf(65_536, body.size - at)
                say(buildJsonObject { put("chunk", true) }, body.copyOfRange(at, at + n))
                at += n
            }
            JsonNull
        }
        h.fake.put(Topics.job(Fixtures.STATION, "web"), Job(id = "web", name = "web", state = "running", port = 5173, startedAt = Fixtures.NOW, service = true, open = true))
        h.launch(listOf(Screen.Home, Screen.Preview(Fixtures.STATION, "web")))
        rule.waitUntil(20_000) { title()?.startsWith("bytes=") == true || title()?.startsWith("failed") == true }
        assertEquals("bytes=true n=${answer.size} sum=$sum", title())
        assertArrayEquals(sent, asked["/echo"])
        assertEquals(0, asked["/"]!!.size)
        val echo = h.fake.calls.filter { it.first == "station.preview" && it.second["path"]?.jsonPrimitive?.contentOrNull == "/echo" }
        assertEquals(1, echo.size)
        // No request's body goes in its params any more.
        assertNull(echo.single().second["body"])
    }
}
