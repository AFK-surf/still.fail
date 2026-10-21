// A command's output in a terminal's colours (the core's TermRuns, client/core-ts/src/terminal.ts): the 16 colours from a
// palette for each theme (as the web's TermText.tsx), the rest as said.
package fail.still.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import fail.still.android.data.TermRun

private val TermLight = longArrayOf(
    0xFF000000, 0xFFCD3131, 0xFF00BC00, 0xFF949800, 0xFF0451A5, 0xFFBC05BC, 0xFF0598BC, 0xFF555555,
    0xFF666666, 0xFFCD3131, 0xFF14CE14, 0xFFB5BA00, 0xFF0451A5, 0xFFBC05BC, 0xFF0598BC, 0xFFA5A5A5,
)
private val TermDark = longArrayOf(
    0xFF6E6E6E, 0xFFCD3131, 0xFF0DBC79, 0xFFE5E510, 0xFF2472C8, 0xFFBC3FBC, 0xFF11A8CD, 0xFFE5E5E5,
    0xFF8A8A8A, 0xFFF14C4C, 0xFF23D18B, 0xFFF5F543, 0xFF3B8EEA, 0xFFD670D6, 0xFF29B8DB, 0xFFE5E5E5,
)

private fun termColor(c: String?, dark: Boolean): Color? = when {
    c == null -> null
    c.startsWith("#") && c.length == 7 -> c.substring(1).toLongOrNull(16)?.let { Color(0xFF000000 or it) }
    else -> c.toIntOrNull()?.takeIf { it in 0..15 }?.let { Color((if (dark) TermDark else TermLight)[it]) }
}

/** `runs` in their styles, `ink` the text's own colour (a dim run is it, faded). */
fun termText(runs: List<TermRun>, ink: Color, dark: Boolean): AnnotatedString = buildAnnotatedString {
    for (r in runs) {
        val fg = termColor(r.fg, dark)
        withStyle(SpanStyle(
            color = if (r.dim == true) (fg ?: ink).copy(alpha = 0.6f) else fg ?: Color.Unspecified,
            background = termColor(r.bg, dark) ?: Color.Unspecified,
            fontWeight = if (r.bold == true) FontWeight.SemiBold else null,
            fontStyle = if (r.italic == true) FontStyle.Italic else null,
            textDecoration = if (r.underline == true) TextDecoration.Underline else null,
        )) { append(r.text) }
    }
}
