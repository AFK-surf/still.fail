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
import fail.still.android.LocalApp
import fail.still.android.data.t

private data class CodeKey(val code: String, val language: String?, val dark: Boolean, val style: TextStyle,
    val density: Float, val fontScale: Float, val direction: LayoutDirection, val fonts: FontFamily.Resolver)
private data class CodeLayout(val key: CodeKey, val layout: TextLayoutResult, val colored: Boolean)

// TextLayoutResult owns the shaped paragraph as well as the spans. Bound by source characters (not entry count),
// so a few large replies cannot keep unlimited native paragraphs alive. Each composable also holds its current one.
private val codeLayouts = object : LruCache<CodeKey, TextLayoutResult>(128 * 1024) {
    override fun sizeOf(key: CodeKey, value: TextLayoutResult) = key.code.length.coerceAtLeast(1)
}
private val codeWork = Dispatchers.Default.limitedParallelism(2)
/** Code up to this long (characters) is shaped plain on the UI thread as it is first drawn; longer, never. */
private const val SHAPED_AT_ONCE = 4_000

/** Code is only drawn here, in the colours the core says (`code.ink`); shaping thousands of colored spans happens off the
 *  UI thread. */
@Composable
internal fun CodeInk(code: String, language: String?, dark: Boolean) {
    val core = LocalApp.current.core
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val fonts = LocalFontFamilyResolver.current
    // Match the Text this replaces, including the theme's inherited paragraph settings.
    val style = LocalTextStyle.current.merge(TextStyle(color = C.ink, fontFamily = CodeFont,
        fontWeight = CodeWeight, fontSize = 12.5.sp, lineHeight = 20.sp))
    val key = remember(code, language, dark, style, density.density, density.fontScale, direction, fonts) {
        CodeKey(code, language?.lowercase(), dark, style, density.density, density.fontScale, direction, fonts)
    }
    val cached = remember(key) {
        codeLayouts.get(key)?.let { CodeLayout(key, it, true) }
            // A little code is shaped here at once (well under a millisecond), so its message has its height as it is
            // first drawn, not "laying out" and then taller: coloured when the core has said its colours (the same
            // code drawn before), else plain, its colours coming after, off the UI thread.
            ?: if (code.length <= SHAPED_AT_ONCE) {
                val known = inkKnown(code, key.language)
                val laid = TextMeasurer(fonts, Density(key.density, key.fontScale), direction, cacheSize = 0).measure(paint(code, known?.ink, dark), style, softWrap = false)
                if (known != null) codeLayouts.put(key, laid)
                CodeLayout(key, laid, known != null)
            } else null
    }
    val prepared by produceState(cached, key) {
        value = cached
        if (cached?.colored == true) return@produceState
        val measurer = TextMeasurer(fonts, Density(key.density, key.fontScale), direction, cacheSize = 0)
        // Plain code first, with its final dimensions. Coloring changes only ink, never glyph metrics or scrolling.
        if (cached == null) {
            val plain = withContext(codeWork) { measurer.measure(AnnotatedString(code), style, softWrap = false) }
            value = CodeLayout(key, plain, false)
        }
        val ink = inkOf(core, code, key.language)
        val colored = withContext(codeWork) { measurer.measure(paint(code, ink, dark), style, softWrap = false) }
        codeLayouts.put(key, colored)
        value = CodeLayout(key, colored, true)
    }
    // The key changed (a face chosen, the size): what was produced is the last key's until its producer starts again,
    // a frame or two; this key's own (shaped above) meanwhile, not "laying out" (the block flashed shorter).
    val result = prepared?.takeIf { it.key == key }?.layout ?: cached?.layout
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
