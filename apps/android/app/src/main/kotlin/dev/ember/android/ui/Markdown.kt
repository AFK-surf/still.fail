// Agents write Markdown. The phone shows the part of it that reads well on a
// small screen: paragraphs, emphasis, inline code, code blocks, headings and
// list items as lines; long outputs are for the computer.
package dev.ember.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private sealed interface Block {
    data class Para(val text: String, val heading: Boolean = false) : Block
    data class Code(val text: String) : Block
}

private fun blocks(text: String): List<Block> {
    val out = mutableListOf<Block>()
    val para = StringBuilder()
    fun flush() { if (para.isNotBlank()) out += Block.Para(para.toString().trimEnd()); para.clear() }
    val lines = text.lines()
    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        when {
            line.trimStart().startsWith("```") -> {
                flush()
                val code = StringBuilder()
                i++
                while (i < lines.size && !lines[i].trimStart().startsWith("```")) { code.appendLine(lines[i]); i++ }
                out += Block.Code(code.toString().trimEnd())
            }
            line.isBlank() -> flush()
            Regex("^#{1,6}\\s").containsMatchIn(line) -> { flush(); out += Block.Para(line.replace(Regex("^#{1,6}\\s+"), ""), heading = true) }
            else -> {
                if (para.isNotEmpty()) para.append('\n')
                para.append(line.replace(Regex("^(\\s*)[-*]\\s+"), "$1• "))
            }
        }
        i++
    }
    flush()
    return out
}

private val INLINE = Regex("`([^`]+)`|\\*\\*([^*]+)\\*\\*|(?<![*\\w])\\*([^*\\n]+)\\*|\\[([^\\]]+)]\\(([^)]+)\\)")

@Composable
private fun inline(text: String): AnnotatedString {
    val code = SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 13.sp, background = C.chip)
    return buildAnnotatedString {
        var at = 0
        for (m in INLINE.findAll(text)) {
            append(text.substring(at, m.range.first))
            val (c, b, e, label) = m.destructured
            when {
                c.isNotEmpty() -> withStyle(code) { append(" $c ") }
                b.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(b) }
                e.isNotEmpty() -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(e) }
                else -> withStyle(SpanStyle(color = C.accentInk)) { append(label) }
            }
            at = m.range.last + 1
        }
        append(text.substring(at))
    }
}

@Composable
fun Markdown(text: String, modifier: Modifier = Modifier, size: Int = 15) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (b in blocks(text)) when (b) {
            is Block.Para -> Text(
                inline(b.text), color = C.ink, fontSize = if (b.heading) (size + 1).sp else size.sp, lineHeight = (size * 1.55).sp,
                fontWeight = if (b.heading) FontWeight.SemiBold else null,
            )
            is Block.Code -> Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.surface2).border(1.dp, C.line, RoundedCornerShape(12.dp))
                    .horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp, vertical = 10.dp),
            ) { Text(b.text, style = Mono, color = C.ink, softWrap = false) }
        }
    }
}
