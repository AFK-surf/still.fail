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

/** The core's done lead in either language (client/core-ts present.ts: 做完了, 做完了：<why>; Done, Done: <why>). */
val doneLead = Regex("^(?:做完了(?:：|$)|Done(?:: |$))")

/** The core's waiting lead in either language (present.ts: 等待中, 在等：<what>; Waiting, Waiting: <what>). */
val waitLead = Regex("^(?:在等：|等待中$|Waiting(?:: |$))")

/** Same compact completed/waiting label as web StatusText (a check, an open arc and dots); the explanation and accessible name stay intact. */
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
    val done = doneLead.find(text)
    val lead = done ?: waitLead.find(text)
    val label = buildAnnotatedString {
        if (lead != null) {
            appendInlineContent("lead", t(if (done != null) "android-misc.status.done" else "android-misc.status.waiting"))
            val reason = text.substring(lead.value.length)
            if (reason.isNotEmpty()) { append(" "); append(reason) }
        } else append(text)
    }
    Text(label, modifier, color = color, fontSize = fontSize, lineHeight = lineHeight,
        maxLines = maxLines, overflow = overflow, style = style,
        inlineContent = if (lead != null) mapOf("lead" to InlineTextContent(
            Placeholder(14.sp, 14.sp, PlaceholderVerticalAlign.TextCenter),
        ) { IconIn(if (done != null) Icons.Check else Icons.Wait, size = 14.dp, tint = color) }) else emptyMap(),
    )
}
