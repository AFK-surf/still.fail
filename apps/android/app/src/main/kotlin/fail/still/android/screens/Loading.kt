// What a page shows until what it lists has come (web mobile/Loading.tsx draws the same): grey placeholders where the
// rows or messages will be, pulsing, and over them a pill saying what it waits on (a spinner before it), or in red what
// is wrong (the placeholders then faded and still). The pill is drawn as a chat's system messages are.
package fail.still.android.screens

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.ui.C
import fail.still.android.ui.reducedMotion

/** What is waited on (a spinner before it), or with `error` what is wrong (in red): centred, a grey capsule. */
@Composable
fun LoadingPill(text: String, error: Boolean = false, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp, start = 20.dp, end = 20.dp), contentAlignment = Alignment.Center) {
        Row(
            Modifier.background(C.chip, RoundedCornerShape(16.dp)).padding(horizontal = 12.dp, vertical = 6.dp)
                .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!error) Spinner(12.dp)
            Text(text, fontSize = 13.sp, color = if (error) C.red else C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        }
    }
}

/** How much the placeholders show: breathing while waited on, faded and still with `still` (something is wrong). */
@Composable
private fun placeholderAlpha(still: Boolean): () -> Float {
    if (still) return { 0.6f }
    if (reducedMotion()) return { 1f }
    val pulse = rememberInfiniteTransition(label = "placeholder").animateFloat(1f, 0.5f, infiniteRepeatable(tween(700), RepeatMode.Reverse), label = "alpha")
    return { pulse.value }
}

@Composable
private fun Bar(width: Dp, height: Dp, shape: androidx.compose.ui.graphics.Shape = RoundedCornerShape(7.dp)) =
    Box(Modifier.width(width).height(height).background(C.bubble, shape))

/** The chat list's rows to come (Home.kt ChatRowBody's size: 66 high, its title and line, who is in it at the end). */
@Composable
fun PlaceholderRows(count: Int, still: Boolean = false) {
    val alpha = placeholderAlpha(still)
    Column(Modifier.graphicsLayer { this.alpha = alpha() }.clearAndSetSemantics {}) {
        repeat(count) { i ->
            Row(Modifier.fillMaxWidth().height(66.dp).padding(start = 22.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Bar(TITLES[i % TITLES.size].dp, 13.dp)
                    Bar(LINES[i % LINES.size].dp, 10.dp)
                }
                Box(Modifier.size(22.dp).background(C.bubble, CircleShape))
            }
        }
    }
}

/** A chat's messages to come: theirs with a picture on the left, the viewer's on the right. */
@Composable
fun PlaceholderMessages(still: Boolean = false) {
    val alpha = placeholderAlpha(still)
    Column(Modifier.fillMaxWidth().padding(top = 8.dp).graphicsLayer { this.alpha = alpha() }.clearAndSetSemantics {}, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        for ((mine, w, h) in MESSAGES) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
            if (!mine) { Box(Modifier.size(28.dp).background(C.bubble, CircleShape)); Spacer(Modifier.width(10.dp)) }
            Bar(w.dp, h.dp, RoundedCornerShape(18.dp))
        }
    }
}

private val TITLES = listOf(150, 110, 170, 130, 96, 160, 120)
private val LINES = listOf(230, 190, 250, 170, 210, 200, 180)
private val MESSAGES = listOf(Triple(false, 220, 40), Triple(false, 160, 58), Triple(true, 180, 40), Triple(false, 240, 76), Triple(true, 120, 40), Triple(false, 200, 40))
