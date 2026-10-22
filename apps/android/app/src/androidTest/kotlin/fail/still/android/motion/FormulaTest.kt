// The real Markdown/Canvas renderer over the same core answer as mbui and the browser, without a WebView.
package fail.still.android.motion

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Updates
import fail.still.android.data.I18n
import fail.still.android.data.PrefsView
import fail.still.android.ui.Markdown
import fail.still.android.ui.LocalUi
import fail.still.android.ui.StillFailTheme
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class FormulaTest {
    @get:Rule val rule: MotionRule = createAndroidComposeRule<ComponentActivity>()

    @Test fun light() = formulas(false)
    @Test fun dark() = formulas(true)

    private fun formulas(dark: Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val fixture = Json.parseToJsonElement(instrumentation.context.assets.open("math.json").bufferedReader().use { it.readText() }).jsonObject
        val source = fixture["text"]!!.jsonPrimitive.content
        val fake = FakeCore()
        val context = rule.activity
        I18n.load(context)
        val prefs = context.getSharedPreferences("formula-test", 0)
        val app = AppState(fake.core, prefs, "http://127.0.0.1:9", Updates(context, "http://127.0.0.1:9", fake.core), PrefsView())
        rule.setContent {
            StillFailTheme(dark) {
                CompositionLocalProvider(LocalApp provides app, LocalUi provides app) {
                    Box(Modifier.requiredSize(390.dp, 540.dp).testTag("formulas").background(if (dark) Color(0xFF171819) else Color.White).padding(24.dp)) {
                        Markdown(source, size = 18, md = fixture["md"])
                    }
                }
            }
        }
        // A supplied tree is drawn as it is. TextLayoutResult records the actual inline placeholders, not a
        // second approximation of the formula's layout. The whole TeX remains its selectable alternative.
        val paragraphs = listOf("Inline E=mc^2", "Fraction ", "\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}", "\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}")
        val layouts = paragraphs.map { words ->
            val result = mutableListOf<TextLayoutResult>()
            rule.onAllNodesWithText(words, substring = true)[0].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(result) }
            result.single()
        }
        assertEquals(1, layouts[0].placeholderRects.size)
        assertEquals(2, layouts[1].placeholderRects.size)
        assertEquals(1, layouts[2].placeholderRects.size)
        assertEquals(1, layouts[3].placeholderRects.size)
        assertEquals(paragraphs[2], layouts[2].layoutInput.text.text)
        assertEquals(paragraphs[3], layouts[3].layoutInput.text.text)
        for (layout in layouts) {
            for (rect in layout.placeholderRects) {
                assertNotNull("Formula must use native drawing, not the source fallback", rect)
                val line = layout.getLineForVerticalPosition(rect!!.center.y)
                assertTrue(rect.top >= layout.getLineTop(line))
                assertTrue(rect.bottom <= layout.getLineBottom(line))
                assertTrue(rect.width > 0f)
            }
        }
        assertTrue(layouts[0].layoutInput.text.text.contains("E=mc^2"))
        assertTrue(rule.onAllNodesWithText("\\unknowncommand{x}", substring = true).fetchSemanticsNodes().isNotEmpty())
        val bitmap = rule.onNodeWithTag("formulas").captureToImage().asAndroidBitmap()
        val dir = File(instrumentation.targetContext.getExternalFilesDir(null), "formula-evidence").apply { mkdirs() }
        File(dir, if (dark) "android-dark.png" else "android-light.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
