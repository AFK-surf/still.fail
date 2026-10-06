// Regression: videos placed with Markdown image syntax open on a real tap.
package fail.still.android.motion

import android.content.Context
import android.graphics.Paint
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Updates
import fail.still.android.data.Attachment
import fail.still.android.data.ChatOf
import fail.still.android.screens.ViewerHost
import fail.still.android.ui.C
import fail.still.android.ui.StillFailTheme
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import fail.still.android.ui.LocalUi

class VideoAttachmentTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private fun clip(file: java.io.File) {
        val w = 320; val hgt = 240
        val format = android.media.MediaFormat.createVideoFormat("video/avc", w, hgt).apply {
            setInteger(android.media.MediaFormat.KEY_COLOR_FORMAT, android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(android.media.MediaFormat.KEY_BIT_RATE, 1_000_000)
            setInteger(android.media.MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(android.media.MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val enc = android.media.MediaCodec.createEncoderByType("video/avc")
        enc.configure(format, null, null, android.media.MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = enc.createInputSurface()
        enc.start()
        val mux = android.media.MediaMuxer(file.path, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        val info = android.media.MediaCodec.BufferInfo()
        fun drain(end: Boolean) {
            if (end) enc.signalEndOfInputStream()
            while (true) {
                val i = enc.dequeueOutputBuffer(info, 10_000)
                when {
                    i == android.media.MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { track = mux.addTrack(enc.outputFormat); mux.start() }
                    i >= 0 -> {
                        val b = enc.getOutputBuffer(i)!!
                        if (info.flags and android.media.MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && track >= 0) mux.writeSampleData(track, b, info)
                        enc.releaseOutputBuffer(i, false)
                        if (info.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                    i == android.media.MediaCodec.INFO_TRY_AGAIN_LATER && !end -> return
                }
            }
        }
        val text = Paint().apply { color = 0xFFFFFFFF.toInt(); textSize = 120f; isAntiAlias = true }
        for (n in 0 until 30) {
            val c = surface.lockHardwareCanvas()
            val t = n / 29f
            c.drawColor(android.graphics.Color.rgb((230 * (1 - t) + 40 * t).toInt(), 70, (60 * (1 - t) + 220 * t).toInt()))
            c.drawText("$n", 110f, 160f, text)
            surface.unlockCanvasAndPost(c)
            drain(false)
            Thread.sleep(33)
        }
        drain(true)
        enc.stop(); enc.release(); mux.stop(); mux.release(); surface.release()
    }

    /** Videos placed with Markdown image syntax must open, both in paragraphs and in table cells. */
    @Test
    fun videoFromMarkdown() {
        val h = Harness(rule)
        val context = rule.activity
        val out = java.io.File(context.cacheDir, "markdown-video.mp4")
        clip(out)
        val bytes = out.readBytes()
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        h.fake.answer = { name, _ -> if (name == "station.file") buildJsonObject { put("type", "video/mp4"); put("bytes", b64) } else JsonNull }
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val file = Attachment("markdown-video.mp4", "ws/c-1/markdown-video.mp4", bytes.size.toLong(), 320, 240)
        val rowFile = file.copy(name = "row-video.mp4", path = "ws/c-1/row-video.mp4")
        val tableFile = file.copy(name = "table-video.mp4", path = "ws/c-1/table-video.mp4")
        val ctx = fail.still.android.screens.Here(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD), Fixtures.chat(emptyList()), emptyList(), "ember:c-1")
        rule.setContent {
            StillFailTheme(false) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.fillMaxSize().background(C.bg)) {
                        Column(Modifier.padding(start = 16.dp, top = 160.dp).width(320.dp)) {
                            fail.still.android.screens.AgentWords(ctx,
                                "录了一段：\n\n![](markdown-video.mp4) ![](row-video.mp4)\n\n| 视频 |\n| --- |\n| ![](table-video.mp4) |", listOf(file, rowFile, tableFile))
                        }
                        ViewerHost()
                    }
                }
            }
        }
        h.settle()
        for ((index, f) in listOf(file, rowFile, tableFile).withIndex()) {
            val recording = h.record("markdown-video-$index")
            recording.frame { rule.onNodeWithText(f.name).performTouchInput { click() } }
            recording.frames(30)
            recording.end()
            rule.runOnIdle { assertTrue("${f.name} opens the viewer", fail.still.android.screens.FileViewers.open) }
            assertTrue("the opened video is fetched", h.fake.calls.any { it.first == "station.file" })
            rule.onNode(hasContentDescription("关闭")).performSemanticsAction(SemanticsActions.OnClick)
            h.settle()
            rule.runOnIdle { assertFalse(fail.still.android.screens.FileViewers.open) }
        }
    }

}
