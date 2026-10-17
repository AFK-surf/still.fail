// Numbered notes, as a picture's marks have them (ImageMarks.kt; web mobile/Notes.tsx): a pin with the number, the box
// a note is written in under what it is about, and the cards they gather into at the foot.
package fail.still.android.screens

import fail.still.android.data.t
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import fail.still.android.ui.C
import fail.still.android.ui.Ease
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Smooth
import fail.still.android.ui.floating
import fail.still.android.ui.floatingStill

/** A numbered note, as its box and card show it (NoteBox, Card): a passage of a message's, or a mark on an image (ImageMarks.kt). */
interface NoteLike {
    val n: Int
    /** What it is about, in a line under what is said. */
    val text: String
    var comment: String
    /** Its pin's colour (none: the accent). */
    val color: Color? get() = null
}

/** A note's number, as a web page's marks show theirs: a pin, its point at the bottom right. */
@Composable
private fun Pin(n: Int, open: Boolean = false, small: Boolean = false, color: Color? = null, onClick: (() -> Unit)? = null) {
    val size = if (small) 16.dp else 20.dp
    val shape = if (small) Smooth(8.dp, 8.dp, 2.dp, 8.dp) else Smooth(10.dp, 10.dp, 2.dp, 10.dp)
    // In the margin: pops in from its point, and grows a little while its note is open (160ms, as the web's).
    val grown by animateFloatAsState(if (open) 1.12f else 1f, tween(160, easing = Ease.Arrive), label = "pin")
    Box(
        Modifier.heightIn(min = size).widthIn(min = size)
            .then(if (small) Modifier else Modifier.pop(160, TransformOrigin(1f, 1f)).graphicsLayer { scaleX = grown; scaleY = grown; transformOrigin = TransformOrigin(1f, 1f) })
            .then(if (small) Modifier else Modifier.border(2.dp, Color.White, shape))
            .clip(shape).background(color ?: C.accent)
            .then(if (onClick != null) Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick) else Modifier)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) { Text("$n", fontSize = if (small) 10.sp else 11.sp, fontWeight = FontWeight(650), color = Color.White, lineHeight = 16.sp) }
}

/** Saying something about a passage: a frosted composer floating under it, as the chat's is, the passage over what is written. */
@Composable
fun NoteBox(note: NoteLike, modifier: Modifier, onDone: () -> Unit, onRemove: () -> Unit) {
    val focus = remember { FocusRequester() }
    val into = remember { BringIntoViewRequester() }
    LaunchedEffect(Unit) { focus.requestFocus(); into.bringIntoView() }
    Column(
        modifier.fillMaxWidth().bringIntoViewRequester(into).pop().floatingStill(Smooth(26.dp)).padding(start = 8.dp, end = 8.dp, top = 10.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Pin(note.n, small = true, color = note.color)
            Text(note.text, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Box(Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onRemove).semantics { contentDescription = t("android-chat.annotate.remove") }, contentAlignment = Alignment.Center) { IconIn(Icons.Trash, 17.dp, C.muted) }
            Box(Modifier.weight(1f).heightIn(min = 36.dp).padding(horizontal = 8.dp, vertical = 7.dp), contentAlignment = Alignment.CenterStart) {
                if (note.comment.isEmpty()) Text(t("android-chat.annotate.write"), fontSize = 16.sp, lineHeight = 21.sp, color = C.subtle)
                BasicTextField(
                    note.comment, { note.comment = it }, Modifier.fillMaxWidth().focusRequester(focus),
                    textStyle = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, color = C.ink), cursorBrush = SolidColor(C.accent), maxLines = 8,
                )
            }
            Box(Modifier.size(36.dp).clip(CircleShape).background(C.ink).clickable(onClick = onDone).semantics { contentDescription = t("android-chat.annotate.done") }, contentAlignment = Alignment.Center) { IconIn(Icons.Check, 18.dp, C.bg) }
        }
    }
}

/** A note in the tray at the foot: its number and what is said, over the passage. */
@Composable
fun Card(note: NoteLike, open: Boolean, haze: HazeState, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = Smooth(16.dp)
    Column(
        modifier.width(160.dp).pop().floating(haze, shape).then(if (open) Modifier.border(1.5.dp, C.accent, shape) else Modifier)
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 9.dp),
    ) { CardContent(note, padded = false) }
}

/** What a note's card holds: its number and what is said, over the passage. */
@Composable
private fun CardContent(note: NoteLike, padded: Boolean = true) {
    Column(if (padded) Modifier.padding(horizontal = 12.dp, vertical = 9.dp) else Modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Pin(note.n, small = true, color = note.color)
            val said = note.comment.trim()
            Text(said.ifEmpty { t("android-chat.annotate.quoteOnly") }, fontSize = 14.sp, lineHeight = 20.sp, color = if (said.isEmpty()) C.muted else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(note.text, fontSize = 12.sp, lineHeight = 17.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Coming in as the web's pop does (keyframes.css.ts popKeyframes over --m-ease): from nothing and 97% of its size to
 * itself, `ms` long, from `origin` (its middle by default).
 */
@Composable
fun Modifier.pop(ms: Int = 140, origin: TransformOrigin = TransformOrigin.Center): Modifier {
    val p = remember { Animatable(0f) }
    LaunchedEffect(Unit) { p.animateTo(1f, tween(ms, easing = Ease.Arrive)) }
    return graphicsLayer {
        alpha = p.value
        val s = 0.97f + 0.03f * p.value
        scaleX = s; scaleY = s
        transformOrigin = origin
    }
}
