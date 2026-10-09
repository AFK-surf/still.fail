// A new chat's foot: its scene runs on under the choices and the composer (their glass frosts it, as a chat's list
// under its composer), and a picture waiting in the composer opens in the viewer.
package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.Screen
import fail.still.android.data.FrequentCombo
import fail.still.android.data.NewChatView
import fail.still.android.data.Topics
import fail.still.android.screens.Drafts
import fail.still.android.screens.FileViewers
import fail.still.android.screens.Pending
import java.io.File
import java.io.FileOutputStream
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class NewChatGlassTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    private val combos = listOf(
        FrequentCombo("opus", "claude", "medium", "Opus 5.5 · medium", false),
        FrequentCombo("gpt", "codex", "medium", "GPT-6 Astra · medium", false),
        FrequentCombo("opus", "claude", "max", "Opus 5.5 · max", false),
        FrequentCombo("opus", "claude", "high", "Opus 5.5 · high", true),
    )

    private fun Harness.newChat(dark: Boolean) {
        fake.put(Topics.newChat(Fixtures.WS), NewChatView(
            kept = Fixtures.STATION, stations = listOf(Fixtures.station), any = true, station = Fixtures.station,
            model = Fixtures.station.models.first(), runtime = "claude", effort = "high", efforts = listOf("high"),
            accounts = emptyList(), pickAccount = false, waiting = false, frequent = combos,
        ))
        launch(listOf(Screen.Home, Screen.NewChat), dark = dark)
    }

    private fun save(name: String) {
        val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "shots").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { rule.onRoot().captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    /** With the keyboard up the scene is taller than its room: it goes on under the choices, not cut off above them. */
    @Test
    fun sceneRunsUnderTheFoot() = sceneRunsUnderTheFoot(false)

    @Test
    fun sceneRunsUnderTheFootDark() = sceneRunsUnderTheFoot(true)

    private fun sceneRunsUnderTheFoot(dark: Boolean) {
        val h = Harness(rule)
        h.newChat(dark)
        rule.onAllNodes(hasSetTextAction())[0].performClick().performTextReplacement("")
        h.keyboard()
        save(if (dark) "new-chat-foot-dark" else "new-chat-foot")
        val chooser = rule.onNode(hasText(Fixtures.station.name)).fetchSemanticsNode().boundsInRoot
        val last = rule.onNode(hasText(combos.last().label)).fetchSemanticsNode()
        // Laid out where it is, under the choosers: its own box, not clipped at the top of the foot.
        val at = last.positionInRoot.y + last.size.height
        assertTrue("the scene stops above the choosers: last combo ends at $at, choosers start at ${chooser.top}", at > chooser.top)
    }

    /** A picture in the composer, tapped: the viewer shows it, from the bytes picked. */
    @Test
    fun pictureInTheComposerOpens() {
        val h = Harness(rule)
        h.newChat(false)
        val big = Bitmap.createBitmap(1200, 800, Bitmap.Config.ARGB_8888).apply { eraseColor(0xFF2E7DD7.toInt()) }
        val png = java.io.ByteArrayOutputStream().also { big.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        val preview = Bitmap.createScaledBitmap(big, 240, 160, true).asImageBitmap()
        rule.runOnUiThread {
            val draft = Drafts.of(rule.activity, h.fake.core, "new:${Fixtures.STATION}")
            draft.files.add(Pending(901L, "safari.png", png.size.toLong(), preview, png, 1200, 800).apply {
                done = fail.still.android.data.Attachment("safari.png", "uploads/safari.png", png.size.toLong(), 1200, 800)
            })
        }
        h.settle()
        save("composer-picture")
        rule.onNode(hasContentDescription("safari.png")).performClick()
        h.settle()
        assertTrue("the viewer did not open", FileViewers.open)
        save("composer-picture-open")
    }
}
