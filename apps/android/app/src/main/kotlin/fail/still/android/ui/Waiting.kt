// Waiting, drawn one way everywhere (docs/ui-panels.md「等待」; web ui/src/waiting.tsx draws the same). Three kinds:
// - a page or list read for the first time: `Waiting`, placeholders shaped as what will come with a light sweeping over
//   them, no words (the page's frame, its bar, title and composer, drawn as ever around it); what could not be read
//   said over them in red;
// - a row or button at work: `Spinner` in its place (DoingMark where it is a core call), in one of two sizes;
// - what has a size on its way (a file, an update): `Progress`.
// Words (a pill, a line) come only after a moment (LATER_MS), so what is there at once shows none; what failed says so
// at once, in red.
package fail.still.android.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.data.ListNote
import fail.still.android.data.t
import kotlinx.coroutines.delay

/** Words about a wait come only when it takes a while: what is there in a moment (from the device) shows none. */
const val LATER_MS = 400L

/** CSS's `ease-in-out`, as the web's breathing and sweeping go. */
private val EaseInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)

/** Whether words about a wait show yet: after LATER_MS, or at once with `now` (what failed). */
@Composable
private fun later(now: Boolean): Boolean {
    var shown by remember { mutableStateOf(now) }
    LaunchedEffect(now) { if (!now) { delay(LATER_MS); shown = true } else shown = true }
    return shown || now
}

/**
 * The turning ring: `inline` (12) in a line of small text (a row's end, a pill), else a button's icon's size (14).
 * A track of the line colour and an arc of the accent; `color` (a solid button's text colour) is the arc's, its track that
 * at 30%. Where it sits says its colour and place, never its size.
 */
@Composable
fun Spinner(inline: Boolean = false, color: Color? = null, modifier: Modifier = Modifier) {
    val arc = color ?: C.accent
    val track = color?.copy(alpha = color.alpha * 0.3f) ?: C.lineStrong
    val turn = rememberInfiniteTransition(label = "spinner")
        .animateFloat(0f, 360f, infiniteRepeatable(tween(if (reducedMotion()) 2400 else 800, easing = LinearEasing)), label = "turn")
    Canvas(modifier.size(if (inline) 12.dp else 14.dp).semantics { progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate }) {
        val w = 2.dp.toPx()
        val r = (size.minDimension - w) / 2
        drawCircle(track, r, style = Stroke(w))
        // The web's: a border whose top is the arc, a quarter from its top-left to its top-right.
        rotate(turn.value) { drawArc(arc, -135f, 90f, false, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), style = Stroke(w)) }
    }
}

/** A button at work (one behaviour for all): the spinner (14) in its icon's place, or before its label; `solid`: the
 *  button's text colour on a solid button. The button itself is not tapped again while `busy` (`clickable(enabled = !busy)`). */
@Composable
fun BusyIcon(busy: Boolean, solid: Color? = null, icon: (@Composable () -> Unit)? = null) {
    if (busy) Spinner(color = solid) else icon?.invoke()
}

/**
 * What is waited on (a spinner before it), or with `error` what is wrong (in red, at once): a grey capsule. Over a
 * viewer's content (a player buffering, a remote screen connecting) it floats: `ground` clear and a glass in `modifier`.
 */
@Composable
fun WaitPill(text: String, error: Boolean = false, modifier: Modifier = Modifier, ground: Color = C.chip, ink: Color = C.muted) {
    val shown = later(error)
    Row(
        Modifier.graphicsLayer { alpha = if (shown) 1f else 0f }.then(modifier).background(ground, CircleShape).padding(horizontal = 12.dp, vertical = 6.dp)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (!error) Spinner(inline = true)
        Text(text, fontSize = 13.sp, lineHeight = 18.sp, color = if (error) C.red else ink, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

/** A wait said in a line of its own where a row or a section's content will be (a spinner before it), or in red what is wrong. */
@Composable
fun WaitLine(text: String = t("common.reading"), error: Boolean = false, modifier: Modifier = Modifier) {
    val shown = later(error)
    Row(
        modifier.graphicsLayer { alpha = if (shown) 1f else 0f }.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (!error) Spinner(inline = true)
        Text(text, fontSize = 13.sp, lineHeight = 18.sp, color = if (error) C.red else C.muted)
    }
}

/** The shapes of what will come: rows (a list's: a title and a line), messages (a chat's) or cards (a settings page's). */
enum class WaitShape { Rows, Messages, Cards }

/**
 * The light over placeholders (the web's waiting.css.ts shapes): where it is across them, 0 to 1 in 1.6s, left to right,
 * again and again; null under reduced motion (none). `still`: what is waited on failed, faded (0.6) and no light.
 */
class Sweep(val still: Boolean, val at: (() -> Float)?)

@Composable
fun rememberSweep(still: Boolean = false): Sweep {
    if (still || reducedMotion()) return remember(still) { Sweep(still, null) }
    val at = rememberInfiniteTransition(label = "light").animateFloat(0f, 1f, infiniteRepeatable(tween(1600, easing = LinearEasing)), label = "at")
    return remember(at) { Sweep(false, { at.value }) }
}

/**
 * Something to come drawn as a grey placeholder (a list's rows, a station's figures, a page of a document) with the light
 * sweeping over it: a band of white at 35% from left of it to right of it, drawn only over what it draws.
 */
fun Modifier.sweeping(sweep: Sweep): Modifier =
    if (sweep.still) graphicsLayer { alpha = 0.6f }
    else sweep.at?.let { at -> graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
        drawContent()
        val w = size.width
        val peak = -0.5f * w + 2f * w * at()
        val light = Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.35f), Color.Transparent), startX = peak - 0.3f * w, endX = peak + 0.3f * w)
        drawRect(light, blendMode = BlendMode.SrcAtop)
    } } ?: this

@Composable
private fun Bar(width: Dp, height: Dp, shape: Shape = CircleShape) = Box(Modifier.width(width).height(height).background(C.bubble, shape))

/**
 * The shapes of what will come, the light sweeping over them: rows as the chats' list's (66 high, a title and a line, a picture at the end),
 * a chat's messages (theirs with a picture on the left, the viewer's on the right) or a settings page's cards.
 */
@Composable
fun WaitShapes(shape: WaitShape = WaitShape.Rows, count: Int? = null, still: Boolean = false, modifier: Modifier = Modifier) {
    val m = modifier.fillMaxWidth().sweeping(rememberSweep(still)).clearAndSetSemantics {}
    when (shape) {
        WaitShape.Rows -> Column(m) {
            repeat(count ?: 7) { i ->
                Row(Modifier.fillMaxWidth().height(66.dp).padding(start = 22.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Bar(TITLES[i % TITLES.size].dp, 13.dp)
                        Bar(LINES[i % LINES.size].dp, 10.dp)
                    }
                    Box(Modifier.size(22.dp).background(C.bubble, CircleShape))
                }
            }
        }
        WaitShape.Messages -> BoxWithConstraints(m.padding(top = 8.dp)) {
            val most = maxWidth * 0.7f
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                for ((mine, w, h) in MESSAGES.take(count ?: MESSAGES.size)) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
                    if (!mine) { Box(Modifier.size(28.dp).background(C.bubble, CircleShape)); Spacer(Modifier.width(10.dp)) }
                    Box(Modifier.widthIn(max = most).width(w.dp).height(h.dp).background(C.bubble, Smooth(18.dp)))
                }
            }
        }
        WaitShape.Cards -> Column(m.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // A page's card's corner (Parts.kt Card).
            repeat(count ?: 3) { i -> Box(Modifier.fillMaxWidth().height(CARDS[i % CARDS.size].dp).background(C.bubble, Smooth(20.dp))) }
        }
    }
}

/**
 * A page's or list's content while it is read the first time: its shapes with the light sweeping over them, what it
 * waits on (`note`, else `text`, else 正在读取) said only to a screen reader; over them in red what could not be read
 * (`error`, `note.failing`), the shapes then still. The page's frame (its bar, title, composer) is drawn around it as ever.
 */
@Composable
fun Waiting(shape: WaitShape = WaitShape.Rows, count: Int? = null, text: String? = null, error: String? = null, note: ListNote? = null, modifier: Modifier = Modifier) {
    val failing = listOfNotNull(error) + note?.failing.orEmpty().map { it.text }
    val reading = error == null && (note?.reading ?: true)
    val said = note?.text ?: text ?: t("common.reading")
    Column(modifier.fillMaxWidth().semantics { if (reading) contentDescription = said }) {
        if (failing.isNotEmpty()) Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (f in failing) WaitPill(f, error = true)
        }
        WaitShapes(shape, count, still = !reading)
    }
}

/**
 * How much has come of what has a size (0…1), or with `part` null a bar that sweeps while that is not known: a capsule
 * 3 high, its track the accent at 18%, what has come the accent. Under reduced motion an unknown one is a full bar, faint.
 */
@Composable
fun Progress(part: Float?, modifier: Modifier = Modifier, color: Color = C.accent) {
    val known = part?.coerceIn(0f, 1f)
    Box(
        modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(color.copy(alpha = color.alpha * 0.18f))
            .semantics { progressBarRangeInfo = if (known == null) ProgressBarRangeInfo.Indeterminate else ProgressBarRangeInfo(known, 0f..1f) },
    ) {
        if (known != null) {
            val shown by animateFloatAsState(known, tween(200, easing = Ease.Out), label = "progress")
            Box(Modifier.fillMaxWidth(shown).height(3.dp).background(color, CircleShape))
        } else if (reducedMotion()) {
            Box(Modifier.fillMaxWidth().height(3.dp).background(color.copy(alpha = color.alpha * 0.35f), CircleShape))
        } else {
            // The web's: a segment 40% wide, from just before the track's start to just past its end, again and again.
            val sweep = rememberInfiniteTransition(label = "sweep").animateFloat(-1f, 2.5f, infiniteRepeatable(tween(1400, easing = EaseInOut)), label = "at")
            Box(Modifier.fillMaxWidth(0.4f).height(3.dp).graphicsLayer { translationX = sweep.value * size.width }.background(color, CircleShape))
        }
    }
}

private val TITLES = listOf(150, 110, 170, 130, 96, 160, 120)
private val LINES = listOf(230, 190, 250, 170, 210, 200, 180)
private val MESSAGES = listOf(Triple(false, 220, 40), Triple(false, 160, 58), Triple(true, 180, 40), Triple(false, 240, 76), Triple(true, 120, 40), Triple(false, 200, 40))
private val CARDS = listOf(120, 88, 152, 104)
