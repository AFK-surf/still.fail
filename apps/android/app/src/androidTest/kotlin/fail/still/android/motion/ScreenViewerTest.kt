// A station's screen in the viewer (remote/ScreenViewer.kt) on a fake core: `screen.view` held open, its states and
// JPEG frames said as the core would (bytes beside the JSON). Each state is pictured (settled.png under motion/screen-*);
// a live frame is drawn and acknowledged, a tap is a click at the right place in the frame, a press held a right click,
// a drag a drag; 只看 sends nothing. Driving it, the clipboard goes both ways and files picked go onto its machine.
package fail.still.android.motion

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.pm.ActivityInfo
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.IntSize
import fail.still.android.data.ScreenAccess
import fail.still.android.data.ScreenDrop
import fail.still.android.data.ScreenViewState
import fail.still.android.data.StillFailJson
import fail.still.android.remote.ScreenSession
import fail.still.android.remote.ScreenViewer
import fail.still.android.remote.STAGE
import fail.still.android.remote.fitIn
import fail.still.core.CoreException
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import fail.still.android.ui.StillFailTheme
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private const val VIEW = "screen.view"
private const val W = 1280
private const val H = 720

class ScreenViewerTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    /** The viewer on the fake core, a session at a time (a state each), in the light or dark theme. */
    private inner class Viewer(dark: Boolean = false, private val h264: Boolean = false) {
        val h = Harness(rule)
        var session by mutableStateOf<ScreenSession?>(null)
        var exited = false
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

        init {
            h.fake.streams += VIEW
            rule.runOnUiThread { rule.activity.enableEdgeToEdge() }
            rule.setContent {
                StillFailTheme(dark) {
                    session?.let { s -> key(s) { ScreenViewer(s, "Chrome", onExit = { exited = true }) } }
                }
            }
        }

        /** A new view opened (the last one closed). */
        fun open(): ScreenSession {
            session?.close()
            val s = ScreenSession(h.fake.core, "ws-1/st-1", "browser:tab-1", scope, IntSize(1920, 1080), h264 = h264)
            rule.runOnUiThread { session = s; s.open() }
            rule.waitUntil(5_000) { h.fake.opened(VIEW) }
            h.settle()
            return s
        }

        fun say(value: JsonElement, bytes: ByteArray? = null) { h.fake.say(VIEW, value, bytes); h.deliver() }

        fun state(
            phase: String, control: Boolean = true, may: Boolean = true, others: List<String> = listOf("李雷"), message: String? = null,
            access: ScreenAccess? = null, controllers: List<String>? = null, takeOver: Boolean? = null, line: String? = null,
            clipboard: List<String>? = null, drop: ScreenDrop? = null,
        ) =
            say(buildJsonObject {
                put("state", StillFailJson.encodeToJsonElement(ScreenViewState(
                    phase = phase, message = message, title = "still.fail — Chrome", kind = "browser", control = control, may = may, others = others,
                    line = line ?: ((if (control) "控制" else "只看") + (if (others.isEmpty()) "" else " · ${others.joinToString("、")}也在看")),
                    codec = "jpeg", width = W.toUInt(), height = H.toUInt(), access = access, controllers = controllers, takeOver = takeOver,
                    clipboard = clipboard, drop = drop,
                )))
            })

        fun config() = say(buildJsonObject { put("config", buildJsonObject { put("codec", "jpeg"); put("width", W); put("height", H) }) })

        fun frame(ts: Long, shade: Int = 0) = say(buildJsonObject { put("frame", buildJsonObject { put("key", true); put("ts", ts) }) }, picture(shade))

        /** What it told the core, of one call. */
        fun told(name: String): List<JsonObject> = h.fake.calls.filter { it.first == name }.map { it.second }

        fun acked(ts: Long) = told("screen.ack").any { it["ts"]!!.jsonPrimitive.long == ts }

        /** The latest timestamp acknowledged (acknowledgements only go up). */
        fun lastAck(): Long = told("screen.ack").maxOfOrNull { it["ts"]!!.jsonPrimitive.long } ?: Long.MIN_VALUE

        fun inputs(): List<JsonObject> = told("screen.input").map { it["input"]!!.jsonObject }

        fun shot(name: String) { h.record(name).run { frame(); end() } }

        /** A point of the frame (0..1 each way), in the stage's own px. */
        fun at(x: Float, y: Float): Offset {
            val node = rule.onNodeWithTag(STAGE).fetchSemanticsNode()
            val fit = fitIn(Size(node.size.width.toFloat(), node.size.height.toFloat()), Size(W.toFloat(), H.toFloat()))
            return Offset(fit.left + x * fit.width, fit.top + y * fit.height)
        }
    }

    /** A frame as a browser tab looks: a page with a bar and lines, as a JPEG. */
    private fun picture(shade: Int): ByteArray {
        val b = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = LinearGradient(0f, 0f, W.toFloat(), H.toFloat(), Color.rgb(70 + shade, 110, 190), Color.rgb(160, 90 + shade, 170), Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, W.toFloat(), H.toFloat(), p)
        p.shader = null
        p.color = Color.WHITE
        c.drawRoundRect(RectF(90f, 70f, W - 90f, H - 60f), 18f, 18f, p)
        p.color = Color.rgb(236, 236, 240)
        c.drawRect(90f, 70f, W - 90f, 130f, p)
        p.color = Color.rgb(230, 112, 74)
        c.drawCircle(130f, 100f, 12f, p)
        p.color = Color.rgb(40, 40, 46)
        p.textSize = 44f
        c.drawText("Sign in to continue", 160f, 220f, p)
        p.color = Color.rgb(200, 200, 206)
        for (i in 0 until 5) c.drawRoundRect(RectF(160f, 270f + i * 60f, W - 300f - i * 70f, 300f + i * 60f), 10f, 10f, p)
        p.color = Color.rgb(21, 89, 196)
        c.drawRoundRect(RectF(160f, 580f, 420f, 630f), 25f, 25f, p)
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
    }

    private fun close(a: Float, b: Double) = assertTrue("$a vs $b", abs(a - b) < 0.01)

    @Test fun liveJpegFramesAreDrawnAckedAndDriven() {
        val v = Viewer()
        val s = v.open()
        // What it asked for: the view by its name, JPEG only (no H.264 here), at most the phone's screen, driving it.
        val asked = v.told(VIEW).single()
        assertEquals("ws-1/st-1", asked["station"]!!.jsonPrimitive.contentOrNull)
        assertEquals("browser:tab-1", asked["screen"]!!.jsonPrimitive.contentOrNull)
        assertEquals(s.view, asked["view"]!!.jsonPrimitive.contentOrNull)
        assertEquals(listOf("jpeg"), asked["codecs"]!!.jsonArray.map { it.jsonPrimitive.contentOrNull })
        assertEquals(1920, asked["maxWidth"]!!.jsonPrimitive.int)
        // Not said: the core decides (only looking while someone else drives it).
        assertEquals(null, asked["control"])
        v.shot("screen-connecting")
        rule.onNodeWithText("正在连接…").assertIsDisplayed()

        v.state("live")
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.frame(1033, shade = 30)
        rule.waitUntil(5_000) { v.acked(1033) }
        assertEquals(s.view, v.told("screen.ack").last()["view"]!!.jsonPrimitive.contentOrNull)
        v.shot("screen-live")
        rule.onNodeWithText("控制 · 李雷也在看").assertIsDisplayed()

        // A tap: down and up with the primary button, where it was in the frame.
        rule.onNodeWithTag(STAGE).performTouchInput { click(v.at(0.25f, 0.75f)) }
        rule.waitUntil(5_000) { v.inputs().size >= 2 }
        val (down, up) = v.inputs().take(2)
        assertEquals(listOf("pointer", "down", 1), listOf(down["t"]!!.jsonPrimitive.contentOrNull, down["kind"]!!.jsonPrimitive.contentOrNull, down["buttons"]!!.jsonPrimitive.int))
        assertEquals("up", up["kind"]!!.jsonPrimitive.contentOrNull)
        close(0.25f, down["x"]!!.jsonPrimitive.double); close(0.75f, down["y"]!!.jsonPrimitive.double)
        close(0.25f, up["x"]!!.jsonPrimitive.double); close(0.75f, up["y"]!!.jsonPrimitive.double)

        // Held: a right click.
        rule.onNodeWithTag(STAGE).performTouchInput { longClick(v.at(0.5f, 0.5f)) }
        rule.waitUntil(5_000) { v.inputs().size >= 4 }
        val (rDown, rUp) = v.inputs().drop(2).take(2)
        assertEquals(listOf("down", 2), listOf(rDown["kind"]!!.jsonPrimitive.contentOrNull, rDown["buttons"]!!.jsonPrimitive.int))
        assertEquals("up", rUp["kind"]!!.jsonPrimitive.contentOrNull)
        close(0.5f, rDown["x"]!!.jsonPrimitive.double)

        // A drag: down where it began, moves, up where it ended.
        rule.onNodeWithTag(STAGE).performTouchInput { swipe(v.at(0.2f, 0.5f), v.at(0.6f, 0.5f), 400) }
        rule.waitUntil(5_000) { v.inputs().drop(4).any { it["kind"]!!.jsonPrimitive.contentOrNull == "up" } }
        val drag = v.inputs().drop(4)
        assertEquals("down", drag.first()["kind"]!!.jsonPrimitive.contentOrNull)
        close(0.2f, drag.first()["x"]!!.jsonPrimitive.double)
        assertTrue(drag.count { it["kind"]!!.jsonPrimitive.contentOrNull == "move" } >= 2)
        assertEquals("up", drag.last()["kind"]!!.jsonPrimitive.contentOrNull)
        close(0.6f, drag.last()["x"]!!.jsonPrimitive.double)

        // Turned sideways: the same view goes on (no new screen.view), the controls down the side.
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        rule.waitUntil(10_000) { rule.onNodeWithTag(STAGE).fetchSemanticsNode().size.let { it.width > it.height } }
        v.h.settle()
        v.frame(1066)
        rule.waitUntil(5_000) { v.acked(1066) }
        v.shot("screen-live-landscape")
        assertEquals(1, v.told(VIEW).size)
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }

    /**
     * H.264 through MediaCodec onto the texture: the androidTest's sample (High profile, B-frames: a decoder that holds
     * frames back, harder than a station's low-latency stream), as a station sends it: the avcC with the config, each
     * access unit in AVCC, never more than two ahead of the last acknowledged. All of it goes through (nothing waits
     * for an acknowledgement that never comes), and the picture is drawn.
     */
    @Test fun liveH264IsDecodedOntoTheSurface() {
        val (avcC, units, size) = sample()
        val v = Viewer(h264 = true)
        val asked = v.open().let { v.told(VIEW).single() }
        assertEquals(listOf("h264", "jpeg"), asked["codecs"]!!.jsonArray.map { it.jsonPrimitive.contentOrNull })
        v.state("live", others = emptyList())
        v.say(buildJsonObject { put("config", buildJsonObject { put("codec", "h264"); put("width", size.width); put("height", size.height) }) }, avcC)
        val sent = ArrayList<Long>()
        for ((ts, key, data) in units) {
            rule.waitUntil(5_000) { sent.count { it > v.lastAck() } < 2 }
            v.h.fake.say(VIEW, buildJsonObject { put("frame", buildJsonObject { put("key", key); put("ts", ts) }) }, data)
            sent += ts
        }
        rule.waitUntil(5_000) { sent.count { it > v.lastAck() } < 2 }
        v.h.settle()
        v.shot("screen-live-h264")
        // Drawn: the frame's middle is not the page's ground.
        val image = rule.onNodeWithTag(STAGE).captureToImage().asAndroidBitmap()
        val ground = image.getPixel(2, 2)
        val middle = (0 until 20).map { image.getPixel(image.width / 2 - 40 + it * 4, image.height / 2) }
        assertTrue("the decoded frame is drawn", middle.any { abs(Color.red(it) - Color.red(ground)) + abs(Color.green(it) - Color.green(ground)) + abs(Color.blue(it) - Color.blue(ground)) > 30 })
    }

    /** The sample's avcC, its access units in AVCC (timestamp, key, bytes) and its size, as MediaExtractor reads them. */
    private fun sample(): Triple<ByteArray, List<Triple<Long, Boolean, ByteArray>>, IntSize> {
        val ctx = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().context
        val x = android.media.MediaExtractor()
        ctx.assets.openFd("drive-sample.mp4").use { x.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
        val track = (0 until x.trackCount).first { x.getTrackFormat(it).getString(android.media.MediaFormat.KEY_MIME) == "video/avc" }
        val format = x.getTrackFormat(track)
        x.selectTrack(track)
        fun unit(name: String): ByteArray = format.getByteBuffer(name)!!.let { b -> ByteArray(b.remaining()).also { b.get(it) } }.let { nals(it).single() }
        val sps = unit("csd-0")
        val pps = unit("csd-1")
        val avcC = byteArrayOf(1, sps[1], sps[2], sps[3], 0xff.toByte(), 0xe1.toByte(), (sps.size shr 8).toByte(), sps.size.toByte()) + sps +
            byteArrayOf(1, (pps.size shr 8).toByte(), pps.size.toByte()) + pps
        val units = ArrayList<Triple<Long, Boolean, ByteArray>>()
        val buffer = java.nio.ByteBuffer.allocate(1 shl 20)
        while (true) {
            val n = x.readSampleData(buffer, 0)
            if (n < 0) break
            val bytes = ByteArray(n).also { buffer.position(0); buffer.get(it, 0, n) }
            // Annex B (as the extractor gives it) to AVCC (as the station sends it).
            val out = java.io.ByteArrayOutputStream()
            for (nal in nals(bytes)) { out.write(byteArrayOf((nal.size shr 24).toByte(), (nal.size shr 16).toByte(), (nal.size shr 8).toByte(), nal.size.toByte())); out.write(nal) }
            units += Triple(x.sampleTime, x.sampleFlags and android.media.MediaExtractor.SAMPLE_FLAG_SYNC != 0, out.toByteArray())
            x.advance()
        }
        x.release()
        return Triple(avcC, units, IntSize(format.getInteger(android.media.MediaFormat.KEY_WIDTH), format.getInteger(android.media.MediaFormat.KEY_HEIGHT)))
    }

    /** The NALs of an Annex B stream (split at its 3- and 4-byte start codes). */
    private fun nals(b: ByteArray): List<ByteArray> {
        val starts = ArrayList<Pair<Int, Int>>()
        var i = 0
        while (i + 3 <= b.size) {
            if (b[i].toInt() == 0 && b[i + 1].toInt() == 0 && b[i + 2].toInt() == 1) { starts += i to i + 3; i += 3 }
            else if (i + 4 <= b.size && b[i].toInt() == 0 && b[i + 1].toInt() == 0 && b[i + 2].toInt() == 0 && b[i + 3].toInt() == 1) { starts += i to i + 4; i += 4 }
            else i++
        }
        return starts.mapIndexed { k, (_, from) -> b.copyOfRange(from, if (k + 1 < starts.size) starts[k + 1].first else b.size) }
    }

    /**
     * An agent drives it as it opens: the core opened it only looking (no `control` asked), who drives it is said with
     * 接管; 接管 asks for control (`screen.control` true), and the line then says the agent waits. Upright and sideways.
     */
    @Test fun anAgentDrivingIsTakenOver() {
        val v = Viewer()
        val s = v.open()
        assertEquals(null, v.told(VIEW).single()["control"])
        val agent = "Agent「修登录」"
        v.state("live", control = false, others = listOf(agent, "Bob"), controllers = listOf(agent), takeOver = true, line = "只看 · $agent 正在控制 · Bob 也在查看")
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.shot("screen-agent-driving")
        rule.onNodeWithText("$agent 正在控制").assertIsDisplayed()
        // Only looking: a tap is not sent.
        rule.onNodeWithTag(STAGE).performTouchInput { click(v.at(0.5f, 0.5f)) }
        v.h.settle()
        assertEquals(emptyList<JsonObject>(), v.inputs())

        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        rule.waitUntil(10_000) { rule.onNodeWithTag(STAGE).fetchSemanticsNode().size.let { it.width > it.height } }
        v.frame(1033)
        rule.waitUntil(5_000) { v.acked(1033) }
        v.shot("screen-agent-driving-landscape")
        rule.onNodeWithText("接管").performTouchInput { click() }
        v.h.settle()
        val asked = v.told("screen.control").single()
        assertEquals(s.view, asked["view"]!!.jsonPrimitive.contentOrNull)
        assertEquals(true, asked["control"]!!.jsonPrimitive.contentOrNull?.toBoolean())
        // The core opens it again driving; the agent waits.
        v.state("live", control = true, others = listOf(agent, "Bob"), controllers = emptyList(), takeOver = false, line = "控制 · $agent 已暂停 · Bob 也在查看")
        v.frame(1066)
        rule.waitUntil(5_000) { v.acked(1066) }
        v.shot("screen-agent-paused-landscape")
        assertEquals(0, rule.onAllNodesWithTextCount("接管"))
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
        rule.waitUntil(10_000) { rule.onNodeWithTag(STAGE).fetchSemanticsNode().size.let { it.width < it.height } }
        v.frame(1100)
        rule.waitUntil(5_000) { v.acked(1100) }
        v.shot("screen-agent-paused")
        rule.onNodeWithText("控制 · $agent 已暂停 · Bob 也在查看").assertIsDisplayed()
        // Driving now: a tap is a click.
        rule.onNodeWithTag(STAGE).performTouchInput { click(v.at(0.5f, 0.5f)) }
        rule.waitUntil(5_000) { v.inputs().size >= 2 }
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }

    /** 接管 in the dark: the main solid button, as the web's primary (light on the dark theme). */
    @Test fun anAgentDrivingInTheDark() {
        val v = Viewer(dark = true)
        v.open()
        val agent = "Agent「修登录」"
        v.state("live", control = false, others = listOf(agent), controllers = listOf(agent), takeOver = true, line = "只看 · $agent 正在控制")
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.shot("screen-agent-driving-dark")
    }

    @Test fun liveInTheDark() {
        val v = Viewer(dark = true)
        v.open()
        v.state("live", others = emptyList())
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.shot("screen-live-dark")
    }

    @Test fun readOnlySendsNothing() {
        val v = Viewer()
        v.open()
        v.state("live", control = false, may = false)
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.shot("screen-read-only")
        // No 只看/控制 to choose, no keyboard; a tap is not sent.
        assertEquals(0, rule.onAllNodesWithTextCount("控制"))
        rule.onNodeWithTag(STAGE).performTouchInput { click(v.at(0.5f, 0.5f)) }
        v.h.settle()
        assertEquals(emptyList<JsonObject>(), v.inputs())
    }

    @Test fun liveButNotDrivable() {
        val v = Viewer()
        v.open()
        // 控制 chosen, but the station cannot take input (Accessibility not granted): seen, nothing sent, why said quietly.
        v.state("live", control = false, others = emptyList(), access = ScreenAccess(capture = true, control = false, message = "在 辅助功能 里打开 stillfail-station", app = "stillfail-station"))
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.shot("screen-not-drivable")
        rule.onNodeWithText("在 辅助功能 里打开 stillfail-station").assertIsDisplayed()
        rule.onNodeWithTag(STAGE).performTouchInput { click(v.at(0.5f, 0.5f)) }
        v.h.settle()
        assertEquals(emptyList<JsonObject>(), v.inputs())
    }

    @Test fun reconnectingKeepsTheFrame() {
        val v = Viewer()
        v.open()
        v.state("live")
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.state("reconnecting", message = "和 station 的连接断了，正在重新连接…")
        v.shot("screen-reconnecting")
        rule.onNodeWithText("和 station 的连接断了，正在重新连接…").assertIsDisplayed()
    }

    @Test fun overStates() {
        val v = Viewer()
        // Ended by the station: the frame kept under it, 再试一次 and 退出.
        v.open()
        v.state("live")
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        v.state("ended", message = "agent 关掉了这个标签页")
        v.h.fake.finish(VIEW)
        v.h.deliver()
        v.shot("screen-ended")
        rule.onNodeWithText("已结束").assertIsDisplayed()
        rule.onNodeWithText("重试").assertIsDisplayed()

        for ((phase, why) in listOf(
            "outdated" to "这台 station 的版本还不能共享屏幕，更新后再试",
            "gone" to "这个标签页已经关了",
            "denied" to "station 现在录不了屏",
        )) {
            v.open()
            // Denied for a grant the station lacks: what to turn on where, as the station says.
            val access = if (phase == "denied") ScreenAccess(capture = false, control = false, message = "在 系统设置 › 隐私与安全性 › 屏幕录制 里打开 stillfail-station", app = "stillfail-station") else null
            v.state(phase, others = emptyList(), message = why, access = access)
            v.h.fake.finish(VIEW)
            v.h.deliver()
            v.shot("screen-$phase")
            rule.onNodeWithText(why).assertIsDisplayed()
            access?.message?.let { rule.onNodeWithText(it).assertIsDisplayed() }
        }

        // The call itself failed (the station unreachable): said with the core's words.
        v.open()
        v.h.fake.fail(VIEW, "offline", "station 不在线")
        v.h.deliver()
        v.h.settle()
        v.shot("screen-failed")
        rule.onNodeWithText("station 不在线").assertIsDisplayed()

        // 退出 leaves.
        rule.onNodeWithText("退出").performTouchInput { click() }
        v.h.settle()
        assertTrue(v.exited)
    }

    private fun MotionRule.onAllNodesWithTextCount(text: String) =
        onAllNodes(androidx.compose.ui.test.hasText(text)).fetchSemanticsNodes().size

    private fun MotionRule.countLabelled(label: String) =
        onAllNodes(androidx.compose.ui.test.hasContentDescription(label)).fetchSemanticsNodes().size

    private val clipboard: ClipboardManager get() = rule.activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    /** The phone's clipboard's text now (read on the main thread, as the app in front). */
    private fun phoneClip(): String? {
        var text: String? = null
        rule.runOnUiThread { text = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString() }
        return text
    }

    private val DROP = ScreenDrop(folder = "/Users/alice/Downloads", reveal = true)

    /** Live and driven, a station that carries the clipboard both ways and takes files (or, `old`, one from before them). */
    private fun driven(v: Viewer, old: Boolean = false): ScreenSession {
        val s = v.open()
        if (old) v.state("live", others = emptyList()) else v.state("live", others = emptyList(), clipboard = listOf("text", "png"), drop = DROP)
        v.config()
        v.frame(1000)
        rule.waitUntil(5_000) { v.acked(1000) }
        return s
    }

    /** Driving it: 发送文件 and 粘贴 beside the keyboard; 粘贴 sends the phone's clipboard (`screen.clipboard`, pasted). */
    @Test fun pastesThePhonesClipboard() {
        val v = Viewer()
        val s = driven(v)
        v.shot("screen-clipboard-driving")
        rule.onNodeWithContentDescription("发送文件").assertIsDisplayed()
        rule.onNodeWithContentDescription("粘贴手机剪贴板").assertIsDisplayed()
        rule.onNodeWithContentDescription("键盘").assertIsDisplayed()

        rule.runOnUiThread { clipboard.setPrimaryClip(ClipData.newPlainText("test", "hello from the phone")) }
        rule.onNodeWithContentDescription("粘贴手机剪贴板").performTouchInput { click() }
        rule.waitUntil(5_000) { v.told("screen.clipboard").isNotEmpty() }
        val asked = v.told("screen.clipboard").single()
        assertEquals(s.view, asked["view"]!!.jsonPrimitive.contentOrNull)
        assertEquals("hello from the phone", asked["text"]!!.jsonPrimitive.contentOrNull)
        assertEquals(true, asked["paste"]!!.jsonPrimitive.boolean)

        // Refused (the core says why): said.
        v.h.fake.answer = { name, _ -> if (name == "screen.clipboard") throw CoreException("unsupported", "这个屏幕不支持剪贴板", null) else JsonNull }
        rule.onNodeWithContentDescription("粘贴手机剪贴板").performTouchInput { click() }
        rule.waitUntil(5_000) { rule.onAllNodesWithTextCount("无法粘贴：这个屏幕不支持剪贴板") == 1 }
        v.h.settle(3000)

        // Nothing on the phone's clipboard: said, nothing sent.
        rule.runOnUiThread { clipboard.clearPrimaryClip() }
        rule.onNodeWithContentDescription("粘贴手机剪贴板").performTouchInput { click() }
        v.h.deliver()
        rule.onNodeWithText("剪贴板是空的").assertIsDisplayed()
        v.shot("screen-clipboard-empty")
        assertEquals(2, v.told("screen.clipboard").size)
    }

    /** A copy made on the screen lands on the phone's clipboard; a picture is only said (the phone takes text). */
    @Test fun aCopyOnTheScreenLandsOnThePhone() {
        val v = Viewer()
        driven(v)
        rule.runOnUiThread { clipboard.setPrimaryClip(ClipData.newPlainText("test", "before")) }
        v.say(buildJsonObject { put("clipboard", buildJsonObject { put("type", "text"); put("text", "copied on the Mac 复制的") }) })
        rule.waitUntil(5_000) { phoneClip() == "copied on the Mac 复制的" }

        v.say(buildJsonObject { put("clipboard", buildJsonObject { put("type", "png"); put("size", 8) }) }, byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10))
        rule.waitUntil(5_000) { rule.onAllNodesWithTextCount("远端复制了图片，手机上暂不支持") == 1 }
        v.shot("screen-clipboard-image")
        assertEquals("copied on the Mac 复制的", phoneClip())
    }

    /** A station from before the clipboard and files, or only looking: neither offered (the keyboard types, as before). */
    @Test fun anOldStationOffersNeither() {
        val v = Viewer()
        driven(v, old = true)
        v.shot("screen-clipboard-old-station")
        rule.onNodeWithContentDescription("键盘").assertIsDisplayed()
        assertEquals(0, rule.countLabelled("发送文件"))
        assertEquals(0, rule.countLabelled("粘贴手机剪贴板"))

        // Only looking, the core says neither (they go only to a view that drives it).
        v.state("live", control = false, others = emptyList())
        v.h.settle()
        assertEquals(0, rule.countLabelled("发送文件"))
        assertEquals(0, rule.countLabelled("粘贴手机剪贴板"))
        assertEquals(0, rule.countLabelled("键盘"))
    }

    @Test fun filesGoOntoTheMachine() = filesGoOntoTheMachine(dark = false)

    @Test fun filesGoOntoTheMachineInTheDark() = filesGoOntoTheMachine(dark = true)

    /**
     * Files picked go up one after another into the state's `drop` folder (the drive's upload, `root` the folder), the
     * first under a free name as its own is taken there; how far each has got shows over the frame, then where it is,
     * its path pasted (`screen.clipboard`) or shown in Finder (`screen.input` reveal); let go of, gone.
     */
    private fun filesGoOntoTheMachine(dark: Boolean) {
        val v = Viewer(dark = dark)
        val s = driven(v)
        val dir = File(rule.activity.cacheDir, "picked").apply { deleteRecursively(); mkdirs() }
        val report = File(dir, "季度报告.pdf").apply { writeBytes(ByteArray(1_200_000) { (it % 251).toByte() }) }
        val notes = File(dir, "notes.txt").apply { writeText("still.fail\n".repeat(400)) }
        val held = CountDownLatch(1)
        var parts = 0
        v.h.fake.answer = { name, p ->
            if (name != "drive.upload.part") JsonNull
            else {
                val path = p["path"]!!.jsonPrimitive.contentOrNull!!
                val offset = p["offset"]!!.jsonPrimitive.long
                val total = p["total"]!!.jsonPrimitive.long
                val got = android.util.Base64.decode(p["bytes"]!!.jsonPrimitive.contentOrNull!!, android.util.Base64.NO_WRAP).size
                assertEquals("/Users/alice/Downloads", p["root"]!!.jsonPrimitive.contentOrNull)
                // A file of its name there already.
                if (path == "季度报告.pdf") throw CoreException("exists", "there is already a file by that name", 409)
                // Its second part waits while it is pictured going.
                if (path == "季度报告 (1).pdf" && offset > 0 && parts++ == 0) held.await(20, TimeUnit.SECONDS)
                val have = offset + got
                buildJsonObject {
                    put("have", have)
                    if (have >= total) put("entry", buildJsonObject { put("name", path.substringAfterLast('/')); put("dir", false) })
                }
            }
        }
        rule.runOnUiThread { s.drops.send(rule.activity.contentResolver, listOf(Uri.fromFile(report), Uri.fromFile(notes)), DROP) }
        try { rule.waitUntil(10_000) { s.drops.list.size == 2 && s.drops.list[0].state == "going" && s.drops.list[0].sent > 0 } }
        catch (e: Throwable) { throw AssertionError("drops: " + s.drops.list.map { "${it.name} ${it.state} ${it.sent}/${it.size} ${it.error}" } + " parts: " + v.told("drive.upload.part").map { "${it["path"]} ${it["offset"]}" }, e) }
        v.h.deliver()
        rule.onNodeWithText("季度报告 (1).pdf").assertIsDisplayed()
        rule.onNodeWithText("等待发送").assertIsDisplayed()
        v.shot(if (dark) "screen-files-going-dark" else "screen-files-going")

        held.countDown()
        rule.waitUntil(10_000) { s.drops.list.all { it.state == "done" } }
        v.h.deliver()
        rule.onNodeWithText("/Users/alice/Downloads/季度报告 (1).pdf").assertIsDisplayed()
        rule.onNodeWithText("/Users/alice/Downloads/notes.txt").assertIsDisplayed()
        v.shot(if (dark) "screen-files-done-dark" else "screen-files-done")
        if (dark) return

        rule.onAllNodes(androidx.compose.ui.test.hasText("粘贴路径"))[0].performTouchInput { click() }
        rule.waitUntil(5_000) { v.told("screen.clipboard").isNotEmpty() }
        assertEquals("/Users/alice/Downloads/季度报告 (1).pdf", v.told("screen.clipboard").single()["text"]!!.jsonPrimitive.contentOrNull)
        rule.onAllNodes(androidx.compose.ui.test.hasText("在访达中显示"))[1].performTouchInput { click() }
        rule.waitUntil(5_000) { v.told("screen.input").isNotEmpty() }
        val reveal = v.told("screen.input").single()
        assertEquals(s.view, reveal["view"]!!.jsonPrimitive.contentOrNull)
        assertEquals("reveal", reveal["input"]!!.jsonObject["t"]!!.jsonPrimitive.contentOrNull)
        assertEquals("/Users/alice/Downloads/notes.txt", reveal["input"]!!.jsonObject["path"]!!.jsonPrimitive.contentOrNull)

        // Let go of, one and then the other: the panel goes.
        rule.onAllNodes(androidx.compose.ui.test.hasContentDescription("关闭") and androidx.compose.ui.test.hasClickAction()).fetchSemanticsNodes().size.let { assertEquals(3, it) }
        repeat(2) { rule.onAllNodes(androidx.compose.ui.test.hasContentDescription("关闭"))[1].performTouchInput { click() }; v.h.deliver() }
        assertEquals(0, s.drops.list.size)
        assertEquals(0, rule.onAllNodesWithTextCount("粘贴路径"))
    }
}
