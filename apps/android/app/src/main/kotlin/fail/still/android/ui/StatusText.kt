package fail.still.android.ui

import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The core's done lead in either language (client/core present.rs: 做完了, 做完了：<why>; Done, Done: <why>). */
val doneLead = Regex("^(?:做完了(?:：|$)|Done(?:: |$))")

/** Same compact completed label as web StatusText; the explanation and accessible name stay intact. */
@Composable
fun StatusText(
    text: String,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = TextUnit.Unspecified,
    color: Color = C.muted,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
    style: TextStyle = TextStyle.Default,
    lineHeight: TextUnit = TextUnit.Unspecified,
) {
    val lead = doneLead.find(text)
    val done = lead != null
    val label = buildAnnotatedString {
        if (lead != null) {
            appendInlineContent("done", t("android-misc.status.done"))
            val reason = text.substring(lead.value.length)
            if (reason.isNotEmpty()) { append(" "); append(reason) }
        } else append(text)
    }
    Text(label, modifier, color = color, fontSize = fontSize, lineHeight = lineHeight,
        maxLines = maxLines, overflow = overflow, style = style,
        inlineContent = if (done) mapOf("done" to InlineTextContent(
            Placeholder(14.sp, 14.sp, PlaceholderVerticalAlign.TextCenter),
        ) { IconIn(Icons.Check, size = 14.dp, tint = color) }) else emptyMap(),
    )
}
