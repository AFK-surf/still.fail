package fail.still.android.ui

import android.util.LruCache
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.text
import androidx.compose.ui.semantics.getTextLayoutResult
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private data class CodeKey(val code: String, val language: String?, val dark: Boolean, val style: TextStyle,
    val density: Float, val fontScale: Float, val direction: LayoutDirection, val fonts: FontFamily.Resolver)
private data class CodeLayout(val key: CodeKey, val layout: TextLayoutResult, val colored: Boolean)

// TextLayoutResult owns the shaped paragraph as well as the spans. Bound by source characters (not entry count),
// so a few large replies cannot keep unlimited native paragraphs alive. Each composable also holds its current one.
private val codeLayouts = object : LruCache<CodeKey, TextLayoutResult>(128 * 1024) {
    override fun sizeOf(key: CodeKey, value: TextLayoutResult) = key.code.length.coerceAtLeast(1)
}
private val codeWork = Dispatchers.Default.limitedParallelism(2)

/** Code is only drawn here. Tokenizing AND shaping thousands of colored spans happens off the UI thread. */
@Composable
internal fun CodeInk(code: String, language: String?, dark: Boolean) {
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val fonts = LocalFontFamilyResolver.current
    // Match the Text this replaces, including the theme's inherited paragraph settings.
    val style = LocalTextStyle.current.merge(TextStyle(color = C.ink, fontFamily = FontFamily.Monospace,
        fontWeight = CodeWeight, fontSize = 12.5.sp, lineHeight = 20.sp))
    val key = remember(code, language, dark, style, density.density, density.fontScale, direction, fonts) {
        CodeKey(code, language?.lowercase(), dark, style, density.density, density.fontScale, direction, fonts)
    }
    val cached = remember(key) { codeLayouts.get(key)?.let { CodeLayout(key, it, true) } }
    val prepared by produceState(cached, key) {
        value = cached
        if (cached != null) return@produceState
        val measurer = TextMeasurer(fonts, Density(key.density, key.fontScale), direction, cacheSize = 0)
        // Plain code first, with its final dimensions. Coloring changes only ink, never glyph metrics or scrolling.
        val plain = withContext(codeWork) { measurer.measure(AnnotatedString(code), style, softWrap = false) }
        value = CodeLayout(key, plain, false)
        val colored = withContext(codeWork) { measurer.measure(highlight(code, key.language, dark), style, softWrap = false) }
        codeLayouts.put(key, colored)
        value = CodeLayout(key, colored, true)
    }
    val result = prepared?.takeIf { it.key == key }?.layout
    if (result == null) {
        // No synchronous fallback: even a plain 20 MB string is not safe to shape on Main.
        Text(t("android-misc.markdown.laying"), fontSize = 12.5.sp, color = webSubtle, modifier = Modifier.height(with(density) { 20.sp.toDp() }))
    } else {
        Canvas(Modifier.size(with(density) { result.size.width.toDp() }, with(density) { result.size.height.toDp() })
            .semantics { text = AnnotatedString(code); getTextLayoutResult { it.add(result); true } }) {
            drawText(result)
        }
    }
}
