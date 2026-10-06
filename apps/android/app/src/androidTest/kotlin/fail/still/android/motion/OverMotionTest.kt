// What moves over the pages, frame by frame (Harness.kt): a page swiped back (predictive back), a sheet let go at the
// finger's speed, the viewer growing out of a thumbnail and shrinking back into it.
package fail.still.android.motion

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.util.Base64
import androidx.activity.BackEventCompat
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.test.click
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.Updates
import fail.still.android.data.Attachment
import fail.still.android.data.ChatOf
import fail.still.android.data.Topics
import fail.still.android.screens.StationImage
import fail.still.android.screens.StationFile
import fail.still.android.screens.ViewerHost
import fail.still.android.ui.C
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.ReaderSpec
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.StillFailTheme
import java.io.ByteArrayOutputStream
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import androidx.core.view.WindowCompat
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import fail.still.android.ui.LocalUi

class OverMotionTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val chat = Screen.Chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD))

    private fun Harness.chatOpen() {
        fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk))
        launch(listOf(Screen.Home, chat))
    }

    private fun back(x: Float, edge: Int = BackEventCompat.EDGE_LEFT) = BackEventCompat(touchX = x, touchY = 1200f, progress = (x / 1080f).coerceIn(0f, 1f), swipeEdge = edge)

    /**
     * Swiped part of the way and back, then called off by the system: the page follows the finger and returns. Then
     * swiped again, and let go: it goes on from where the finger left it, the list showing under it.
     */
    @Test
    fun swipedBack() {
        val h = Harness(rule)
        h.chatOpen()
        val d = rule.activity.onBackPressedDispatcher
        val r = h.record("back-cancelled")
        r.frame { rule.runOnUiThread { d.dispatchOnBackStarted(back(20f)) } }
        for (i in 1..14) r.frame { rule.runOnUiThread { d.dispatchOnBackProgressed(back(20f + 30f * i)) } }
        r.frame { rule.runOnUiThread { d.dispatchOnBackCancelled() } }
        r.frames(18)
        r.end()
        val go = h.record("back-swiped")
        go.frame { rule.runOnUiThread { d.dispatchOnBackStarted(back(20f)) } }
        for (i in 1..20) go.frame { rule.runOnUiThread { d.dispatchOnBackProgressed(back(20f + 27f * i)) } }
        go.frame { rule.runOnUiThread { d.onBackPressed() } }
        go.frames(24)
        go.end()
    }

    /**
     * A chat come back to (tapped back from a page over it), then swiped away: it stays over the list it uncovers (the
     * list was drawn over it, a page's layer being fixed by the way it came in).
     */
    @Test
    fun swipedBackAfterBack() {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk))
        h.launch(listOf(Screen.Home, chat, Screen.Appearance))
        val tapped = h.record("tapped-back")
        tapped.frame { rule.runOnUiThread { h.app.pop() } }
        tapped.frames(24)
        tapped.end()
        val d = rule.activity.onBackPressedDispatcher
        val go = h.record("back-after-back")
        go.frame { rule.runOnUiThread { d.dispatchOnBackStarted(back(20f)) } }
        for (i in 1..20) go.frame { rule.runOnUiThread { d.dispatchOnBackProgressed(back(20f + 27f * i)) } }
        go.frame { rule.runOnUiThread { d.onBackPressed() } }
        go.frames(24)
        go.end()
    }

    /** A page pushed over a chat and tapped back: side by side both ways, the status bar's paper moving with its page. */
    @Test
    fun tappedForthAndBack() {
        val h = Harness(rule)
        h.chatOpen()
        val forth = h.record("tapped-forth")
        forth.frame { rule.runOnUiThread { h.app.push(Screen.Appearance) } }
        forth.frames(24)
        forth.end()
        val back = h.record("tapped-back-to-chat")
        back.frame { rule.runOnUiThread { h.app.pop() } }
        back.frames(24)
        back.end()
    }

    /**
     * A new chat rises from the bottom; become its chat, it sinks back down when tapped back, and when swiped back it
     * goes down with the finger (both went out sideways, unlike how it came).
     */
    @Test
    fun newChatInAndOut() {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk))
        h.launch(listOf(Screen.Home))
        val rise = h.record("new-chat-in")
        rise.frame { rule.runOnUiThread { h.app.push(Screen.NewChat) } }
        rise.frames(28)
        rise.end()
        rule.runOnUiThread { h.app.made(chat) }
        h.settle()
        val sink = h.record("made-chat-out")
        sink.frame { rule.runOnUiThread { h.app.pop() } }
        sink.frames(28)
        sink.end()
        rule.runOnUiThread { h.app.push(Screen.NewChat) }
        h.settle()
        rule.runOnUiThread { h.app.made(chat) }
        h.settle()
        val d = rule.activity.onBackPressedDispatcher
        val go = h.record("made-chat-swiped")
        go.frame { rule.runOnUiThread { d.dispatchOnBackStarted(back(20f)) } }
        for (i in 1..20) go.frame { rule.runOnUiThread { d.dispatchOnBackProgressed(back(20f + 27f * i)) } }
        go.frame { rule.runOnUiThread { d.onBackPressed() } }
        go.frames(24)
        go.end()
    }

    /**
     * Back with a history entry open in full (the reader, over everything) closes it, not the page under it: the
     * pages' handler is added after the reader's (once the workspaces are read), so it must step aside.
     */
    @Test
    fun backClosesReaderFirst() {
        val h = Harness(rule)
        h.fake.put(Topics.chat(Fixtures.STATION, ChatOf.Thread(Fixtures.THREAD)), Fixtures.chat(Fixtures.talk))
        h.launch(listOf(Screen.Home, chat, Screen.Appearance))
        rule.runOnUiThread { h.app.reader = ReaderSpec({ Text("记录") }) { Text("全文") } }
        h.settle()
        val d = rule.activity.onBackPressedDispatcher
        rule.runOnUiThread { d.onBackPressed() }
        h.settle()
        assertTrue("reader closed", h.app.reader == null)
        assertTrue("page kept: ${h.app.stack}", h.app.stack == listOf(Screen.Home, chat, Screen.Appearance))
        rule.runOnUiThread { d.onBackPressed() }
        h.settle()
        assertTrue("page popped: ${h.app.stack}", h.app.stack == listOf(Screen.Home, chat))
    }

    private fun Harness.sheet(draggable: Boolean, height: Float) {
        launch(listOf(Screen.Home))
        rule.runOnUiThread {
            app.sheet = SheetSpec(height, draggable = draggable) {
                SheetGrab()
                SheetHead(if (draggable) "工作区" else "这个成员")
                repeat(10) { Text("第 ${it + 1} 行", fontSize = 16.sp, color = C.ink, modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp)) }
            }
        }
        settle()
    }

    /** A draggable sheet flung up from its top: on to full height at the finger's speed. */
    @Test
    fun sheetFlungUp() {
        val h = Harness(rule)
        h.sheet(draggable = true, height = 0.55f)
        val top = 2400 * 0.45f
        val r = h.record("sheet-flung")
        // A move a frame, as a finger's come (touch events batched into one would end on the lift, whose move a drag
        // does not take).
        r.frame { rule.onRoot().performTouchInput { down(Offset(540f, top + 90f)) } }
        repeat(16) { r.frame { rule.onRoot().performTouchInput { moveBy(Offset(0f, -60f), delayMillis = 16) } } }
        r.frame { rule.onRoot().performTouchInput { up() } }
        r.frames(56)
        r.end()
    }

    /** A sheet that is not draggable, pulled down past 80dp from its head: it closes; less, it goes back. */
    @Test
    fun sheetPulledDown() {
        val h = Harness(rule)
        h.sheet(draggable = false, height = 0.42f)
        val top = 2400 * 0.58f
        val back = h.record("sheet-pulled-back")
        back.frame { rule.onRoot().performTouchInput { down(Offset(540f, top + 90f)) } }
        repeat(6) { back.frame { rule.onRoot().performTouchInput { moveBy(Offset(0f, 25f), delayMillis = 16) } } }
        back.frame { rule.onRoot().performTouchInput { up() } }
        back.frames(56)
        back.end()
        val gone = h.record("sheet-pulled-closed")
        gone.frame { rule.onRoot().performTouchInput { down(Offset(540f, top + 90f)) } }
        repeat(6) { gone.frame { rule.onRoot().performTouchInput { moveBy(Offset(0f, 70f), delayMillis = 16) } } }
        gone.frame { rule.onRoot().performTouchInput { up() } }
        gone.frames(24)
        gone.end()
    }

    private fun picture(): ByteArray {
        val b = Bitmap.createBitmap(800, 600, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawPaint(Paint().apply { shader = LinearGradient(0f, 0f, 800f, 600f, 0xFFE8704A.toInt(), 0xFF3A6FD8.toInt(), Shader.TileMode.CLAMP) })
        val p = Paint().apply { color = 0xFFFFFFFF.toInt(); isAntiAlias = true }
        c.drawCircle(400f, 300f, 140f, p)
        p.color = 0xFF111113.toInt(); p.textSize = 90f
        c.drawText("wwl", 330f, 330f, p)
        for (i in 0..7) c.drawRect(i * 100f, 560f, i * 100f + 50f, 600f, p)
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    /** An image in a chat, tapped: the viewer grows out of it; closed, it shrinks back into it. */
    @Test
    fun viewerFromThumbnail() {
        val h = Harness(rule)
        val bytes = picture()
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        h.fake.answer = { name, _ -> if (name == "station.file") buildJsonObject { put("type", "image/png"); put("bytes", b64) } else JsonNull }
        h.fake.put(Topics.accounts, listOf(Fixtures.account))
        val context = rule.activity
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val file = Attachment(name = "wwl.png", path = "ws/c-1/wwl.png", size = bytes.size.toLong(), width = 800, height = 600)
        rule.setContent {
            StillFailTheme(false) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.fillMaxSize().background(C.bg)) {
                        // Where a chat shows an agent's image: under its words, at the list's side.
                        Column(Modifier.padding(start = 16.dp, top = 360.dp).width(260.dp)) {
                            Text("按这个风格生成了一个 wwl 的头像：", fontSize = 16.sp, color = C.ink, modifier = Modifier.padding(bottom = 10.dp))
                            StationImage(Fixtures.STATION, "ember:c-1", file)
                        }
                        ViewerHost()
                    }
                }
            }
        }
        h.settle()
        val open = h.record("viewer-open")
        open.frame { rule.onRoot().performTouchInput { click(Offset(16f * 2.625f + 300f, 360f * 2.625f + 200f)) } }
        open.frames(26)
        open.end()
        // Over the dark viewer the system bars' icons are light; the app's own again once it has closed.
        val bars = { var light = false; rule.runOnUiThread { light = WindowCompat.getInsetsController(context.window, context.window.decorView).isAppearanceLightStatusBars }; light }
        assertFalse("status bar icons light over the viewer", bars())
        h.settle(3000)
        val close = h.record("viewer-close")
        close.frame { rule.onNode(hasContentDescription("关闭")).performSemanticsAction(SemanticsActions.OnClick) }
        close.frames(22)
        close.end()
        assertTrue("status bar icons dark again over the light page", bars())
    }

    /** A picture of its own colours, `label` on it. */
    private fun slidePicture(label: String, from: Int, to: Int): ByteArray {
        val b = Bitmap.createBitmap(800, 600, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawPaint(Paint().apply { shader = LinearGradient(0f, 0f, 800f, 600f, from, to, Shader.TileMode.CLAMP) })
        c.drawText(label, 300f, 360f, Paint().apply { color = 0xFFFFFFFF.toInt(); textSize = 180f; isAntiAlias = true })
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    /**
     * A chat's three images, the first opened: a finger moving sideways carries it, and let go it slides out as the
     * next slides in; a short drag let go goes back; past the last it gives only a little.
     */
    @Test
    fun viewerSwipes() {
        val h = Harness(rule)
        val pictures = mapOf(
            "a.png" to slidePicture("1", 0xFFE8704A.toInt(), 0xFF3A6FD8.toInt()),
            "b.png" to slidePicture("2", 0xFF2E9E6B.toInt(), 0xFFE0C341.toInt()),
            "c.png" to slidePicture("3", 0xFF8A4FD8.toInt(), 0xFFD84F8A.toInt()),
        )
        h.fake.answer = { name, args ->
            val path = args.toString()
            val bytes = pictures.entries.firstOrNull { path.contains(it.key) }?.value
            if (name == "station.file" && bytes != null) buildJsonObject { put("type", "image/png"); put("bytes", Base64.encodeToString(bytes, Base64.NO_WRAP)) } else JsonNull
        }
        val context = rule.activity
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val files = pictures.map { (name, bytes) -> Attachment(name = name, path = "ws/c-1/$name", size = bytes.size.toLong(), width = 800, height = 600) }
        val gallery = files.map { fail.still.android.screens.Shown("ember:c-1", it) }
        rule.setContent {
            StillFailTheme(false) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.fillMaxSize().background(C.bg)) {
                        Column(Modifier.padding(start = 16.dp, top = 360.dp).width(260.dp)) {
                            StationImage(Fixtures.STATION, "ember:c-1", files[0], gallery = { gallery })
                        }
                        ViewerHost()
                    }
                }
            }
        }
        h.settle()
        rule.onRoot().performTouchInput { click(Offset(16f * 2.625f + 300f, 360f * 2.625f + 200f)) }
        h.settle(3000)
        val w = rule.onRoot().fetchSemanticsNode().size.width.toFloat()
        val y = rule.onRoot().fetchSemanticsNode().size.height / 2f
        // To the next: dragged a third of the way, let go while moving.
        val next = h.record("viewer-swipe-next")
        next.frame { rule.onRoot().performTouchInput { down(Offset(w * 0.8f, y)) } }
        repeat(12) { next.frame { rule.onRoot().performTouchInput { moveBy(Offset(-w / 36f, 0f)) } } }
        next.frame { rule.onRoot().performTouchInput { up() } }
        next.frames(36)
        next.end()
        h.settle(1500)
        // A short slow drag let go: back in place.
        val back = h.record("viewer-swipe-back")
        back.frame { rule.onRoot().performTouchInput { down(Offset(w * 0.5f, y)) } }
        repeat(10) { back.frame { rule.onRoot().performTouchInput { moveBy(Offset(w / 100f, 0f), delayMillis = 60) } } }
        back.frames(3)
        back.frame { rule.onRoot().performTouchInput { up() } }
        back.frames(30)
        back.end()
        h.settle(1500)
        // Back to the first by a fling, then past it: it gives a little and comes back.
        rule.onRoot().performTouchInput { swipe(Offset(w * 0.2f, y), Offset(w * 0.8f, y), 200) }
        h.settle(1500)
        val edge = h.record("viewer-swipe-edge")
        edge.frame { rule.onRoot().performTouchInput { down(Offset(w * 0.2f, y)) } }
        repeat(12) { edge.frame { rule.onRoot().performTouchInput { moveBy(Offset(w / 30f, 0f)) } } }
        edge.frame { rule.onRoot().performTouchInput { up() } }
        edge.frames(30)
        edge.end()
    }

    /** A short clip (red to blue, a frame's number on each), encoded here: 30 frames at about 30 fps. */
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

    /**
     * A video in a chat, tapped: the viewer grows out of its still; left at its last frame and closed, it shrinks back
     * into the thumbnail, which shows that frame from then on (as web's).
     */
    @Test
    fun videoFromThumbnail() {
        val h = Harness(rule)
        val context = rule.activity
        val out = java.io.File(context.cacheDir, "clip.mp4")
        clip(out)
        val bytes = out.readBytes()
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        h.fake.answer = { name, _ -> if (name == "station.file") buildJsonObject { put("type", "video/mp4"); put("bytes", b64) } else JsonNull }
        val prefs = context.getSharedPreferences("motion-test", Context.MODE_PRIVATE)
        prefs.edit().clear().putString("theme", "light").commit()
        rule.runOnUiThread { context.enableEdgeToEdge() }
        val app = AppState(h.fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", h.fake.core))
        val file = Attachment(name = "clip.mp4", path = "ws/c-1/clip.mp4", size = bytes.size.toLong(), width = 320, height = 240)
        rule.setContent {
            StillFailTheme(false) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.fillMaxSize().background(C.bg)) {
                        Column(Modifier.padding(start = 16.dp, top = 360.dp).width(260.dp)) {
                            Text("录了一段：", fontSize = 16.sp, color = C.ink, modifier = Modifier.padding(bottom = 10.dp))
                            StationFile(Fixtures.STATION, "ember:c-1", file)
                        }
                        ViewerHost()
                    }
                }
            }
        }
        h.settle()
        Thread.sleep(1500)
        h.settle()
        val open = h.record("video-open")
        open.frame { rule.onRoot().performTouchInput { click(Offset(16f * 2.625f + 300f, 360f * 2.625f + 200f)) } }
        open.frames(30)
        open.end()
        // Played through (in real time): left at its last frame.
        Thread.sleep(2500)
        h.settle(3000)
        val close = h.record("video-close")
        close.frame { rule.onNode(hasContentDescription("关闭")).performSemanticsAction(SemanticsActions.OnClick) }
        close.frames(24)
        close.end()
        assertTrue("the thumbnail keeps the frame the video was left at", fail.still.android.screens.FileViewers.frames.isNotEmpty())
        // Opened again: out of that frame, and on from there (no jump back to the first).
        h.settle(1000)
        val again = h.record("video-reopen")
        again.frame { rule.onRoot().performTouchInput { click(Offset(16f * 2.625f + 300f, 360f * 2.625f + 200f)) } }
        again.frames(30)
        again.end()
    }
}
