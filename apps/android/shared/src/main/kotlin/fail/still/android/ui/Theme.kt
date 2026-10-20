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
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import fail.still.android.shared.R
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

@Immutable
data class StillFailColors(
    val dark: Boolean,
    val bg: Color, val surface: Color, val surface2: Color,
    val ink: Color, val muted: Color, val subtle: Color, val line: Color,
    /** The web's --line-strong: a field's frame, a quote's bar, a spinner's track. */
    val lineStrong: Color,
    val accent: Color, val accentBg: Color, val accentInk: Color,
    val green: Color, val red: Color, val warn: Color,
    /**
     * The accent, amber and green as words (a link, 需要登录, 可用): on paper the accent and amber are too light to read
     * (under 3:1), so words take a darker one of each, 4.5:1 on a chip; the dark theme's own read as they are.
     */
    val link: Color, val warnInk: Color, val greenInk: Color,
    /** Unread: news, not "this needs you". */
    val blue: Color,
    val chip: Color, val bubble: Color,
)

val Light = StillFailColors(
    dark = false,
    bg = Color(0xFFF5F3EF), surface = Color(0xFFFFFFFF), surface2 = Color(0xFFFBFAF7),
    ink = Color(0xFF24272B), muted = Color(0xFF626469), subtle = Color(0xFF7C7E81), line = Color(0xFFE7E3DC), lineStrong = Color(0xFFC1C4C9),
    accent = Color(0xFFE5704A), accentBg = Color(0xFFFBE6DC), accentInk = Color(0xFFB9471F),
    green = Color(0xFF2F8F5B), red = Color(0xFFBF3E2C), warn = Color(0xFFD9962B), blue = Color(0xFF1559C4),
    link = Color(0xFFB9471F), warnInk = Color(0xFF98691E), greenInk = Color(0xFF287A4D),
    chip = Color(0xFFE8E4DC), bubble = Color(0xFFE8E4DC),
)

val Dark = StillFailColors(
    dark = true,
    bg = Color(0xFF1B1C1F), surface = Color(0xFF26272B), surface2 = Color(0xFF2C2D31),
    ink = Color(0xFFECECED), muted = Color(0xFF9A9DA3), subtle = Color(0xFF84888F), line = Color(0xFF34353A), lineStrong = Color(0xFF3D3F44),
    accent = Color(0xFFEF7A55), accentBg = Color(0xFF4A2F25), accentInk = Color(0xFFF6A383),
    green = Color(0xFF5CC08A), red = Color(0xFFEB6B58), warn = Color(0xFFD9962B), blue = Color(0xFF81AEFA),
    link = Color(0xFFEF7A55), warnInk = Color(0xFFD9962B), greenInk = Color(0xFF5CC08A),
    chip = Color(0xFF313237), bubble = Color(0xFF313237),
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

/**
 * The app's own code face (CodeFont, ui/Fonts.kt, when none is chosen): JetBrains Mono, carried in the app (res/font,
 * OFL in assets/licenses). Not the system's `monospace`: a phone maker's font theme (ColorOS, HyperOS…) replaces that
 * too, and code came out in a proportional face. One variable file, set to each weight asked for.
 */
@OptIn(ExperimentalTextApi::class)
val JetBrainsMono = FontFamily(listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold).map {
    Font(R.font.jetbrains_mono, it, variationSettings = FontVariation.Settings(FontVariation.weight(it.weight)))
})

/** The type with the ui face chosen (ui/Fonts.kt): every Text that does not say a face of its own is set in it. */
private fun Typography.inFace(face: FontFamily?): Typography {
    if (face == null) return this
    fun TextStyle.f() = copy(fontFamily = face)
    return Typography(
        displayLarge = displayLarge.f(), displayMedium = displayMedium.f(), displaySmall = displaySmall.f(),
        headlineLarge = headlineLarge.f(), headlineMedium = headlineMedium.f(), headlineSmall = headlineSmall.f(),
        titleLarge = titleLarge.f(), titleMedium = titleMedium.f(), titleSmall = titleSmall.f(),
        bodyLarge = bodyLarge.f(), bodyMedium = bodyMedium.f(), bodySmall = bodySmall.f(),
        labelLarge = labelLarge.f(), labelMedium = labelMedium.f(), labelSmall = labelSmall.f(),
    )
}

@Composable
fun StillFailTheme(dark: Boolean, fonts: AppFonts = AppFonts(), content: @Composable () -> Unit) {
    val colors = if (dark) Dark else Light
    val scheme = if (dark) {
        darkColorScheme(primary = colors.accent, background = colors.bg, surface = colors.surface, onSurface = colors.ink, onBackground = colors.ink, outline = colors.line)
    } else {
        lightColorScheme(primary = colors.accent, background = colors.bg, surface = colors.surface, onSurface = colors.ink, onBackground = colors.ink, outline = colors.line)
    }
    val type = remember(fonts.ui) { WebType.inFace(fonts.ui) }
    CompositionLocalProvider(LocalColors provides colors, LocalFonts provides fonts) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}
