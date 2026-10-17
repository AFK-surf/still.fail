// ＋'s sheet (screens/Attach.kt) in a chat on the fake core: without the gallery's permission the strip is the camera and
// 显示最近照片; allowed, the gallery's latest photos follow the camera, newest first, and a tap on one closes the sheet
// and puts it in the composer. The photos are put in the gallery here (screenshots drawn) and taken out after. Pictured
// light and dark, and in English (the longest words: Station files), as settled.png under motion/attach-*.
package fail.still.android.motion

import android.Manifest
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.I18n
import fail.still.android.data.Topics
import fail.still.android.screens.PhotoAccess
import fail.still.android.screens.RECENT_TAG
import fail.still.android.screens.photoAccess
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class AttachTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val st = Fixtures.STATION
    private val topic = Topics.chat(st, ChatOf.Thread(Fixtures.THREAD))
    private val put = mutableListOf<Uri>()

    @Test fun dark() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        screenshots(context)
        val h = open(true)
        // Without the gallery first (granting it after does not end the process; taking it back would).
        if (photoAccess(context) == PhotoAccess.None) {
            plus(h)
            rule.onNodeWithText("显示最近照片").assertExists()
            picture(h, "attach-dark-ask")
            close(h)
        }
        grant()
        plus(h)
        picture(h, "attach-dark-recent")
        close(h)
        I18n.lang = "en"
        plus(h)
        picture(h, "attach-dark-en")
        I18n.lang = "zh"
    }

    @Test fun light() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        screenshots(context)
        grant()
        val h = open(false)
        plus(h)
        picture(h, "attach-light-recent")
        // The newest, tapped: the sheet closed, the photo in the composer.
        rule.onAllNodesWithTag(RECENT_TAG).onFirst().performSemanticsAction(SemanticsActions.OnClick)
        Thread.sleep(800); h.settle()
        rule.runOnIdle { assertEquals(null, h.app.sheet) }
        picture(h, "attach-light-picked")
    }

    private fun open(dark: Boolean): Harness {
        val h = Harness(rule)
        h.fake.put(topic, Fixtures.chat(Fixtures.talk))
        h.launch(listOf(Screen.Home, Screen.Chat(st, ChatOf.Thread(Fixtures.THREAD))), dark = dark)
        return h
    }

    private fun grant() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(
            context.packageName, if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE,
        )
        assertEquals(PhotoAccess.All, photoAccess(context))
    }

    @After fun out() {
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        put.forEach { resolver.delete(it, null, null) }
    }

    private fun plus(h: Harness) {
        rule.onNode(hasContentDescription("添加到消息").or(hasContentDescription("Attach"))).performSemanticsAction(SemanticsActions.OnClick)
        h.settle(); Thread.sleep(800); h.settle()
    }

    private fun close(h: Harness) { rule.runOnUiThread { h.app.sheet = null }; h.settle() }

    private fun picture(h: Harness, name: String) { val shot = h.record(name); shot.frame(); shot.end() }

    /** Six phone screenshots, light and dark by turns, put in the gallery a second apart (the last drawn the newest). */
    private fun screenshots(context: android.content.Context) {
        val now = System.currentTimeMillis() / 1000
        repeat(6) { i ->
            val dark = i % 2 == 1
            val bitmap = Bitmap.createBitmap(540, 1170, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(if (dark) 0xFF202125.toInt() else 0xFFF3F1EC.toInt())
            val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = if (dark) 0xFF3A3B40.toInt() else 0xFFCFCAC0.toInt() }
            val block = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = listOf(0xFFEF7A55, 0xFF5B8DEF, 0xFF4CAF7A)[i % 3].toInt(); alpha = if (dark) 150 else 110 }
            for (y in listOf(70, 110, 640, 690, 740, 790)) canvas.drawRoundRect(RectF(40f, y.toFloat(), 500f - (y * 7 + i * 53) % 160, y + 22f), 11f, 11f, line)
            canvas.drawRoundRect(RectF(40f, 170f, 500f, 580f), 28f, 28f, block)
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "Screenshot_attach_$i.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Screenshots")
                put(MediaStore.Images.Media.DATE_ADDED, now - 60 + i)
            }
            val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
            context.contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            put += uri
        }
    }
}
