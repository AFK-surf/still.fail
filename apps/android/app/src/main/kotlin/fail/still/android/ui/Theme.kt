// The mobile concept's look (design/mobile/app.css): warm paper, ink, and one
// still.fail orange that means "this needs you". Material 3 underneath only for
// what it draws itself (text fields, selection, ripples).
package fail.still.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

@Immutable
data class StillFailColors(
    val dark: Boolean,
    val bg: Color, val surface: Color, val surface2: Color,
    val ink: Color, val muted: Color, val subtle: Color, val line: Color,
    val accent: Color, val accentBg: Color, val accentInk: Color,
    val green: Color, val red: Color, val warn: Color,
    /** Unread: news, not "this needs you". */
    val blue: Color,
    val chip: Color, val bubble: Color,
)

val Light = StillFailColors(
    dark = false,
    bg = Color(0xFFF5F3EF), surface = Color(0xFFFFFFFF), surface2 = Color(0xFFFBFAF7),
    ink = Color(0xFF24272B), muted = Color(0xFF7A7D83), subtle = Color(0xFFA6A8AC), line = Color(0xFFE7E3DC),
    accent = Color(0xFFE5704A), accentBg = Color(0xFFFBE6DC), accentInk = Color(0xFFB9471F),
    green = Color(0xFF2F8F5B), red = Color(0xFFC9412E), warn = Color(0xFFD9962B), blue = Color(0xFF1559C4),
    chip = Color(0xFFEFECE6), bubble = Color(0xFFEDEAE4),
)

val Dark = StillFailColors(
    dark = true,
    bg = Color(0xFF1B1C1F), surface = Color(0xFF26272B), surface2 = Color(0xFF2C2D31),
    ink = Color(0xFFECECED), muted = Color(0xFF9A9DA3), subtle = Color(0xFF6E7177), line = Color(0xFF34353A),
    accent = Color(0xFFEF7A55), accentBg = Color(0xFF4A2F25), accentInk = Color(0xFFF6A383),
    green = Color(0xFF5CC08A), red = Color(0xFFEB6B58), warn = Color(0xFFD9962B), blue = Color(0xFF81AEFA),
    chip = Color(0xFF313237), bubble = Color(0xFF33343A),
)

val LocalColors = staticCompositionLocalOf { Light }

/** The palette in use. */
val C: StillFailColors @Composable get() = LocalColors.current

/**
 * Text as the web phone sets it (mobile/styles/root.css.ts: `line-height: 1.4`, no letter spacing): Material's own
 * type (24sp lines for every size, 0.5sp between letters) made rows taller and words wider than the web's.
 */
private val WebType = Typography().let { t ->
    fun TextStyle.web() = copy(lineHeight = 1.4.em, letterSpacing = 0.sp)
    Typography(
        displayLarge = t.displayLarge.web(), displayMedium = t.displayMedium.web(), displaySmall = t.displaySmall.web(),
        headlineLarge = t.headlineLarge.web(), headlineMedium = t.headlineMedium.web(), headlineSmall = t.headlineSmall.web(),
        titleLarge = t.titleLarge.web(), titleMedium = t.titleMedium.web(), titleSmall = t.titleSmall.web(),
        bodyLarge = t.bodyLarge.web(), bodyMedium = t.bodyMedium.web(), bodySmall = t.bodySmall.web(),
        labelLarge = t.labelLarge.web(), labelMedium = t.labelMedium.web(), labelSmall = t.labelSmall.web(),
    )
}

val Mono = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp, lineHeight = 18.sp)

@Composable
fun StillFailTheme(dark: Boolean, content: @Composable () -> Unit) {
    val colors = if (dark) Dark else Light
    val scheme = if (dark) {
        darkColorScheme(primary = colors.accent, background = colors.bg, surface = colors.surface, onSurface = colors.ink, onBackground = colors.ink, outline = colors.line)
    } else {
        lightColorScheme(primary = colors.accent, background = colors.bg, surface = colors.surface, onSurface = colors.ink, onBackground = colors.ink, outline = colors.line)
    }
    CompositionLocalProvider(LocalColors provides colors) {
        MaterialTheme(colorScheme = scheme, typography = WebType, content = content)
    }
}
