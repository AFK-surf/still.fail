// An inline visualization left alone in a chat must stay still: its page drawn once, its height settled, not drawn
// again and again. On the system's clock (a WebView keeps its own): the page is pictured every few frames for a few
// seconds and each picture compared with the one before; the WebViews' heights are logged as they go.
package fail.still.android.motion

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import fail.still.android.ui.glass
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Updates
import fail.still.android.data.Attachment
import fail.still.android.data.ChatOf
import fail.still.android.ui.C
import fail.still.android.ui.StillFailTheme
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import fail.still.android.ui.LocalUi

class VizFlickerTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun webViews(v: View, out: MutableList<WebView> = ArrayList()): List<WebView> {
        if (v is WebView) out += v
        if (v is ViewGroup) for (i in 0 until v.childCount) webViews(v.getChildAt(i), out)
        return out
    }

    /** The chat's words with `html` placed in them, watched for `ms`: answers how many pictures differed from the one before. */
    private fun watch(name: String, text: String, html: String?, dark: Boolean = false, ms: Long = 6000, glass: Boolean = false, churn: Boolean = false, loading: Boolean = false): Int {
        val h = Harness(rule)
        val context = rule.activity
        val b64 = html?.let { Base64.encodeToString(it.toByteArray(), Base64.NO_WRAP) }
        h.fake.answer = { call, _ ->
            when (call) {
                "station.file" -> buildJsonObject { put("type", "text/html"); put("bytes", b64) }
                // As far away as a station is.
                "widget.state" -> { Thread.sleep(300); JsonObject(emptyMap()) }
                else -> JsonNull
            }
        }
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", if (dark) "dark" else "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val file = Attachment("$name.html", "ws/c-1/$name.html", (html?.length ?: 0).toLong())
        val ctx = fail.still.android.screens.Here(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD), Fixtures.chat(emptyList()), emptyList(), "ember:c-1")
        // What goes on in a chat meanwhile: the glass bar over the list drawn again (an agent's ring turning in it), the
        // message composed again (the chat's data coming in).
        val tick = mutableIntStateOf(0)
        val haze = HazeState()
        rule.setContent {
            StillFailTheme(dark) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.fillMaxSize().background(C.bg)) {
                        LazyColumn(Modifier.fillMaxSize().then(if (glass) Modifier.hazeSource(haze) else Modifier).background(C.bg).padding(start = 16.dp, end = 16.dp), contentPadding = PaddingValues(top = 120.dp, bottom = 120.dp)) {
                            item { Text("上面的一条消息", color = C.ink) }
                            item {
                                val n = if (churn) tick.intValue else 0
                                val here = remember(n) { fail.still.android.screens.Here(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD), Fixtures.chat(emptyList()), emptyList(), "ember:c-1") }
                                fail.still.android.screens.AgentWords(here, text, if (html != null) listOf(file) else emptyList())
                            }
                            item { Text("下面的一条消息", color = C.ink) }
                        }
                        if (glass) Box(Modifier.fillMaxWidth().height(100.dp).glass(haze)) {
                            Box(Modifier.padding(top = 60.dp, start = (16 + tick.intValue % 20 * 8).dp).size(16.dp).background(C.ink))
                        }
                    }
                }
            }
        }
        val dir = File(context.getExternalFilesDir(null), "motion/viz-$name").apply { deleteRecursively(); mkdirs() }
        rule.mainClock.autoAdvance = true
        // Let it load and settle first: what counts is what it does once still.
        if (!loading) repeat(100) { Thread.sleep(30); rule.waitForIdle() }
        var prev: Bitmap? = null
        var changed = 0
        val log = StringBuilder("ms,heights,unlike\n")
        val start = System.currentTimeMillis()
        var n = 0
        while (System.currentTimeMillis() - start < ms) {
            if (glass || churn) rule.runOnUiThread { tick.intValue++ }
            val shot = rule.onRoot().captureToImage().asAndroidBitmap()
            val heights = arrayOf<String>("")
            rule.runOnUiThread { heights[0] = webViews(context.window.decorView).joinToString("/") { "${it.height}:${it.contentHeight}" } }
            // Only the page's own room: the bar over it moves on purpose.
            val unlike = prev?.let { unlike(it, shot, (100 * context.resources.displayMetrics.density).toInt()) } ?: 0f
            if (unlike > 0.001f) changed++
            log.append("${System.currentTimeMillis() - start},${heights[0]},${"%.4f".format(unlike)}\n")
            if (n < 80) FileOutputStream(File(dir, "f%03d.jpg".format(n))).use { shot.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            prev = shot; n++
            Thread.sleep(if (loading) 10 else 50)
        }
        File(dir, "watch.csv").writeText(log.toString())
        Log.i("motion", "viz-$name: $n pictures, $changed unlike the one before\n$log")
        return changed
    }

    private fun unlike(a: Bitmap, b: Bitmap, top: Int): Float {
        if (a.width != b.width || a.height != b.height) return 1f
        val w = a.width; val hgt = a.height - top
        val pa = IntArray(w * hgt); val pb = IntArray(w * hgt)
        a.getPixels(pa, 0, w, 0, top, w, hgt); b.getPixels(pb, 0, w, 0, top, w, hgt)
        var d = 0
        for (i in pa.indices) {
            val x = pa[i]; val y = pb[i]
            if (abs(Color.red(x) - Color.red(y)) + abs(Color.green(x) - Color.green(y)) + abs(Color.blue(x) - Color.blue(y)) > 24) d++
        }
        return d.toFloat() / pa.size
    }

    private val still = """<div style="padding:12px;border:1px solid var(--border);border-radius:12px"><h3>静止的卡片</h3><p>没有动画，没有脚本。</p><table class="table"><tr><th>a</th><th>b</th></tr><tr><td>1</td><td>2</td></tr></table></div>"""

    /** Taller than most of the screen, as a mock-up of a page is (the glass drew such a page blank, a part at a time). */
    private val tall = """<div style="padding:16px;border-radius:28px;background:var(--card)">""" +
        (1..12).joinToString("") { """<div style="display:flex;gap:12px;padding:10px 0;border-bottom:1px solid var(--border)"><div style="width:40px;height:40px;border-radius:50%;background:var(--muted)"></div><div><b>第 $it 行</b><p style="margin:0;color:var(--muted-foreground)">一行说明文字</p></div></div>""" } +
        "</div>"

    @Test fun plain() { assertTrue(watch("plain", "看一下：\n\n[卡片](plain.html)\n\n后面的话", still) == 0) }
    @Test fun plainDark() { assertTrue(watch("plain-dark", "看一下：\n\n[卡片](plain-dark.html)\n\n后面的话", still, dark = true) == 0) }
    @Test fun viewportTall() { assertTrue(watch("vh", "[卡片](vh.html)", """<div style="min-height:100vh;background:var(--muted)">按窗口高度的</div>""") == 0) }
    @Test fun churn() { assertTrue(watch("churn", "[卡片](churn.html)", tall, churn = true) == 0) }
    @Test fun glass() { assertTrue(watch("glass", "[卡片](glass.html)", tall, glass = true, churn = true) == 0) }

    /**
     * Loading, the page comes in at once: its room (and the icons under it), then the page drawn whole; no blank page,
     * no page drawn at another height first.
     */
    @Test fun loads() { assertTrue(watch("loads", "[卡片](loads.html)", tall, loading = true, ms = 3000) <= 2) }
}
