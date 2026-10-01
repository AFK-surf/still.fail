package fail.still.android.screens

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.unit.sp

/** The field, flying words and own messages share their typography and line breaks. */
internal val SendTextStyle = TextStyle(
    fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Normal,
    fontSize = 16.sp, lineHeight = 21.sp, letterSpacing = 0.sp,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineBreak = LineBreak.Simple, hyphens = Hyphens.None,
)

/** Actual field width in pixels, excluding the buttons and padding; updated on resize too. */
internal val LocalSendTextWidth = compositionLocalOf { 0 }
