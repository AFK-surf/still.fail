// The pages' small parts used across them (the chats', the drive's, the screens', the share sheet's): buttons, fields,
// rows to pick from, the mark of what was set going. Moved here from screens/ so that what is not a chat's page does not
// depend on the pages (2026-10-17).
package fail.still.android.ui

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Where what someone set going shows how it is (AppState.isDoing / failedOf): a spinner while it is under way, a small
 * red mark the few seconds after it failed (a tap says why), nothing otherwise. The menu or sheet that asked may be gone.
 */
@Composable
fun DoingMark(running: Boolean, failed: String?, inline: Boolean = false) {
    if (running) Spinner(inline)
    // The app only for what failed: a spinner shows where there is none (the share sheet over another app).
    else if (failed != null) {
        val ui = LocalUi.current
        IconIn(Icons.Info, if (inline) 12.dp else 14.dp, C.red, Modifier.semantics { contentDescription = failed }.clickable { ui.note(failed) })
    }
}

/**
 * A row of a picking sheet: what, a line under it, and a check on the chosen one; `busy`: what it set going is under way
 * (a spinner, not tapped again); `done`: what it stands for is done (a station joined: not tapped again, the line under it
 * and a check in green); `failed`: it failed a moment ago (DoingMark); `mark`: drawn before what (a station's icon);
 * `subLines`: at most that many lines of the line under it (a chat's last message: one).
 */
@Composable
fun PickRow(label: String, sub: String? = null, checked: Boolean = false, enabled: Boolean = true, busy: Boolean = false, done: Boolean = false, failed: String? = null, color: Color = C.ink, leading: (@Composable () -> Unit)? = null, mark: (@Composable () -> Unit)? = null, subLines: Int = Int.MAX_VALUE, onClick: () -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp)) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled && !busy && !done, onClick = onClick).padding(horizontal = 8.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            leading?.invoke()
            Column(Modifier.weight(1f)) {
                if (mark == null) Text(label, fontSize = 15.sp, color = if (enabled) color else C.subtle)
                else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    mark()
                    Text(label, fontSize = 15.sp, color = if (enabled) color else C.subtle)
                }
                if (sub != null) Text(sub, fontSize = 12.sp, color = if (done) C.green else C.muted, maxLines = subLines, overflow = TextOverflow.Ellipsis)
            }
            if (busy || failed != null) DoingMark(busy, failed)
            else if (done) IconIn(Icons.Check, 14.dp, C.green)
            else if (checked) IconIn(Icons.Check, 14.dp, C.accent)
        }
    }
}

@Composable
fun Button(label: String, primary: Boolean, busy: Boolean = false, enabled: Boolean = true, danger: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val on = enabled && !busy
    val ink = if (primary && danger && enabled) Color.White else if (primary) C.bg else C.ink
    // Its words in the middle: the same as wrapped round them, centred where `modifier` makes it wider (full width).
    Row(
        modifier.height(38.dp).clip(Smooth(19.dp)).background(if (primary) (if (!enabled) C.line else if (danger) C.red else C.ink) else C.chip)
            .clickable(enabled = on, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
    ) {
        // A solid one's spinner in its words' colour.
        BusyIcon(busy, solid = if (primary) ink else null)
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = ink)
    }
}

/** A line to type in, on a soft frame; `lines` above one: a few lines, of any length (a pasted list). */
@Composable
fun Field(value: String, onChange: (String) -> Unit, placeholder: String, mono: Boolean = false, modifier: Modifier = Modifier, lines: Int = 1, max: Int = if (mono) 32 else 80) {
    Box(
        modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.surface).border(1.dp, C.line, Smooth(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        if (value.isEmpty()) Text(placeholder, color = C.subtle, fontSize = 15.sp, fontFamily = if (mono) CodeFont else null)
        BasicTextField(
            value, { onChange(if (lines > 1) it else it.take(max)) }, singleLine = lines == 1, minLines = lines, cursorBrush = SolidColor(C.accent),
            textStyle = TextStyle(color = C.ink, fontSize = 15.sp, fontFamily = if (mono) CodeFont else null), modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
fun GroupLabel(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))

fun fileSize(bytes: Long): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${Math.round(bytes / 1024.0)} KB"
    bytes < 1024L * 1024 * 1024 -> String.format(java.util.Locale.ROOT, "%.1f MB", bytes / 1024.0 / 1024.0)
    else -> String.format(java.util.Locale.ROOT, "%.2f GB", bytes / 1024.0 / 1024.0 / 1024.0)
}

/** The line icon an entry of the drive is drawn with, by its kind (the core's `kind`). */
fun kindIcon(kind: String): ImageVector = when (kind) {
    "folder" -> Icons.Folder
    "video" -> Icons.FileVideo
    "audio" -> Icons.FileAudio
    "image" -> Icons.Photo
    "markdown", "text", "subtitle" -> Icons.FileText
    "code", "csv", "html" -> Icons.FileCode
    "pdf" -> Icons.FilePdf
    else -> Icons.File
}

/**
 * The activity a context belongs to. The viewers sit in a Dialog, whose context wraps the activity's (a theme wrapper):
 * `context as? Activity` is null there, and the landscape button did nothing.
 */
tailrec fun android.content.Context.activity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.activity()
    else -> null
}
