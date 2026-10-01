// What a chat waits on, over its composer (web mobile, the same interaction set): its pieces of work waiting on
// someone, one card at a time, as the core orders them (`asks`: those on the viewer first, set aside last). The card
// is the composer's glass: a ring and one quiet line (whose, what, since when), what is to be decided, and its answers
// as pills (yes filled in ink); tapped elsewhere, it shows the message that asked, in the list over it. Swiped right it is 随便 (the agent decides: its delegate answer is said), swiped left 待定 (set aside: last
// of those waiting, the ring kept; nothing said); what it reveals under it says which. Let go past about a third of
// its width, or flung, it flies off and the next comes up from the edge of the card behind it; short of that it
// springs back. Anything else is written in the card's own field and said of it. `1 / N ›` steps through them here.
package fail.still.android.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.util.lerp
import dev.chrisbanes.haze.HazeState
import fail.still.android.data.WorkAnswer
import fail.still.android.data.WorkItem
import fail.still.android.ui.C
import fail.still.android.ui.Ease
import fail.still.android.ui.MoveSpring
import fail.still.android.ui.floating
import fail.still.android.ui.reducedMotion
import kotlin.math.abs
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/** The blue of a mark waiting on the viewer (as the list's, Home.kt). */
private val AskBlue = androidx.compose.ui.graphics.Color(0xFF3B82F6)
private val CardShape = RoundedCornerShape(20.dp)
/** The card behind, peeking out under this one: lower by this, and narrower. */
private val PeekDrop = 7.dp
private const val PEEK_SCALE = 0.94f
/** Let go past this share of its width, the card goes. */
private const val THRESHOLD = 0.35f

/**
 * What this device has done to a chat's cards before the core says so (kept with the chat's page): one answered is
 * not shown, one set aside goes last, only until the core's asks have it so (the core leaves out what was answered
 * here, and puts last what was set aside); `at`, which card is shown.
 */
@Stable
internal class AskLocal {
    internal val answered = mutableStateMapOf<String, Long>()
    internal var later by mutableStateOf(listOf<String>())
    internal var at by mutableIntStateOf(0)
    /** What is written in each card's own field, by its key (kept as the cards go round). */
    internal val replies = mutableStateMapOf<String, String>()

    /** The answer did not go: the card is back. */
    fun undo(key: String, words: String? = null) {
        answered.remove(key); later = later - key
        if (words != null) replies[key] = words
    }

    /** Lets go of what the core has caught up with. */
    internal fun caughtUp(asks: List<WorkItem>) {
        val keys = asks.associateBy { it.key }
        answered.keys.filter { it !in keys }.forEach { answered.remove(it) }
        fun waiting(k: String) = keys[k]?.let { it.deferred != true } == true
        if (!later.all(::waiting)) later = later.filter(::waiting)
    }

    internal fun shown(asks: List<WorkItem>): List<WorkItem> {
        val left = asks.filter { answered[it.key] != it.updatedAt }
        // Set aside here, until the core has it so (it puts it last itself).
        val (moved, rest) = left.partition { it.key in later && it.deferred != true }
        return rest + later.mapNotNull { k -> moved.find { it.key == k } }
    }
}

/**
 * The cards, over the composer: none when nothing waits. `onAnswer` says an answer (its `text`) in the chat,
 * `onDefer` sets one aside, `onReply` says the words written in its own field of it (`failed` with what to say when
 * they did not go: they are back in the field); `onShow`, the card tapped (not on a pill or its field): the message that
 * asked it (its `evidence`) is to be shown.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun AskCards(
    asks: List<WorkItem>, local: AskLocal, haze: HazeState, modifier: Modifier = Modifier,
    onAnswer: (WorkItem, WorkAnswer) -> Unit, onDefer: (WorkItem) -> Unit, onReply: (WorkItem, String) -> Unit,
    onShow: (WorkItem) -> Unit = {},
) {
    val shown = local.shown(asks)
    androidx.compose.runtime.SideEffect { local.caughtUp(asks) }
    val n = shown.size
    // The box is there with nothing in it too: its height (none) is what the list keeps clear of.
    Box(modifier.fillMaxWidth()) {
        if (n == 0) return@Box
        val i = local.at.mod(n)
        val item = shown[i]
        val next = if (n > 1) shown[(i + 1) % n] else null
        val still = reducedMotion()
        val scope = rememberCoroutineScope()
        val density = LocalDensity.current
        val drop = with(density) { PeekDrop.toPx() }
        // The front card's way across (px), its coming up from behind (0 behind, 1 in place) and fading (a pill
        // answered); the card behind's coming forward as the front one goes. Each is the card's own (new with another
        // card in front or behind): what went is not snapped back, which the layers would draw a frame before the
        // page shows the next one in its place.
        val drag = remember(item.key) { Animatable(0f) }
        val lift = remember(item.key) { Animatable(1f) }
        val fade = remember(item.key) { Animatable(1f) }
        val promote = remember(item.key, next?.key) { Animatable(0f) }
        var width by remember { mutableIntStateOf(1) }
        var busy by remember { mutableStateOf(false) }
        // While one goes: the cards as they will be, for the one coming forward to say its place among them already.
        var after by remember { mutableStateOf<List<WorkItem>?>(null) }
        val delegate = item.answers.firstOrNull { it.kind == "delegate" && it.text != null }
        val defer = item.answers.firstOrNull { it.kind == "defer" }

        /** The front card goes (`dir` its side, 0: fades where it is), what it does is done, and the next is in its place. */
        fun go(dir: Int, then: List<WorkItem>, act: () -> Unit) {
            if (busy) return
            busy = true
            after = then
            scope.launch {
                val alone = next == null
                if (!still) coroutineScope {
                    if (dir != 0) launch { drag.animateTo(dir * width * 1.25f, tween(220, easing = Ease.Standard)) }
                    else launch { fade.animateTo(0f, tween(160, easing = Ease.Css)) }
                    if (!alone) launch { promote.animateTo(1f, tween(260, easing = Ease.Out)) }
                }
                act()
                // The next one is the one shown now, wherever what went has gone (set aside, it is last).
                if (next != null) local.at = local.shown(asks).indexOfFirst { it.key == next.key }.coerceAtLeast(0)
                busy = false
                after = null
                // The only one (set aside, it is still the one): it comes up again from behind.
                if (alone) {
                    if (!still) lift.snapTo(0f)
                    drag.snapTo(0f); fade.snapTo(1f)
                    if (!still) lift.animateTo(1f, tween(260, easing = Ease.Out))
                }
            }
        }
        fun delegateIt() { delegate?.let { a -> go(1, shown - item) { local.answered[item.key] = item.updatedAt; onAnswer(item, a) } } }
        fun deferIt() { if (defer != null) go(-1, shown - item + item) { local.later = local.later - item.key + item.key; onDefer(item) } }

        // Swiped where it rests, not on the card that follows the finger (in the card's own terms the finger would
        // barely move: the card moves with it). Seen before the card's glass, which keeps every touch to itself: once
        // the finger has gone across far enough (and not up or down first), the swipe is this and the card's pills let
        // go. One begun in the reply field stays the field's.
        var field by remember { mutableStateOf(androidx.compose.ui.geometry.Rect.Zero) }
        var origin by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
        Box(Modifier.fillMaxWidth().padding(horizontal = 10.dp).onSizeChanged { width = it.width }
            .onGloballyPositioned { origin = it.positionInRoot() }
            .pointerInput(item.key, next?.key, delegate != null, defer != null, still) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    if (busy || field.contains(down.position + origin)) return@awaitEachGesture
                    val tracker = VelocityTracker()
                    var pos = drag.value
                    var across = 0f
                    var upDown = 0f
                    var swiping = false
                    while (true) {
                        val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) {
                            if (swiping) {
                                change.consume()
                                val v = tracker.calculateVelocity().x
                                val at = drag.value
                                val fling = abs(v) > 900.dp.toPx() && abs(at) > 16.dp.toPx() && (v > 0) == (at > 0)
                                when {
                                    busy -> {}
                                    (at > width * THRESHOLD || fling && at > 0) && delegate != null -> delegateIt()
                                    (at < -width * THRESHOLD || fling && at < 0) && defer != null -> deferIt()
                                    else -> scope.launch { if (still) drag.snapTo(0f) else drag.animateTo(0f, MoveSpring, v) }
                                }
                            }
                            break
                        }
                        val dx = change.position.x - change.previousPosition.x
                        if (!swiping) {
                            across += dx
                            upDown += change.position.y - change.previousPosition.y
                            if (abs(upDown) > viewConfiguration.touchSlop && abs(upDown) > abs(across)) break
                            if (abs(across) <= viewConfiguration.touchSlop) continue
                            swiping = true
                            tracker.resetTracking()
                        }
                        change.consume()
                        if (busy) continue
                        tracker.addPosition(change.uptimeMillis, change.position)
                        // A side with nothing to do there only gives a little.
                        val stiff = (pos + dx > 0 && delegate == null) || (pos + dx < 0 && defer == null)
                        pos += if (stiff) dx * 0.2f else dx
                        val to = pos
                        scope.launch { drag.snapTo(to) }
                    }
                }
            }) {
            // Under the front card, what letting it go there does; once let go to go, under the card behind too, which
            // comes forward over it as it fades.
            val x = drag.value
            val shownSide = if (x > 0 && delegate != null) 1 else if (x < 0 && defer != null) -1 else 0
            val revealAt = Modifier.matchParentSize().graphicsLayer {
                alpha = (abs(drag.value) / (width * 0.12f)).coerceIn(0f, 1f) * (1f - promote.value)
            }
            val reveal = @Composable { Reveal(shownSide, (if (shownSide > 0) delegate else defer)?.label.orEmpty(), revealAt) }
            if (shownSide != 0 && busy) reveal()
            // Behind: the next one's edge, peeking out under it; it comes forward as the front one goes.
            if (next != null) {
                val then = after
                Face(
                    next, then?.indexOfFirst { it.key == next.key }?.plus(1) ?: ((i + 1) % n + 1), then?.size ?: n, haze,
                    Modifier.matchParentSize().graphicsLayer {
                        val p = promote.value
                        val s = lerp(PEEK_SCALE, 1f, p)
                        scaleX = s; scaleY = s
                        transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)
                        translationY = drop * (1f - p)
                    },
                    fill = true, hint = hintOf(next),
                )
            }
            if (shownSide != 0 && !busy) reveal()
            Face(
                item, i + 1, n, haze,
                Modifier.graphicsLayer {
                    val l = lift.value
                    val s = lerp(PEEK_SCALE, 1f, l)
                    scaleX = s; scaleY = s
                    translationX = drag.value
                    translationY = drop * (1f - l)
                    rotationZ = drag.value / width * 7f
                    alpha = fade.value * (if (next == null) l else 1f)
                },
                // A tap where nothing else takes it (its pills, its field, `1 / N` do): the message that asked. A swipe
                // takes the touch from it (consumed once it is one).
                gesture = Modifier.clickable(interactionSource = null, indication = null, onClickLabel = "看提问的消息") { if (!busy) onShow(item) }.semantics {
                    customActions = listOfNotNull(
                        delegate?.let { CustomAccessibilityAction(it.label) { delegateIt(); true } },
                        defer?.let { CustomAccessibilityAction(it.label) { deferIt(); true } },
                    )
                },
                onCycle = { if (!busy) local.at = (i + 1) % n },
                onPill = { a -> if (a.text != null) go(0, shown - item) { local.answered[item.key] = item.updatedAt; onAnswer(item, a) } },
                reply = local.replies[item.key].orEmpty(),
                onType = { local.replies[item.key] = it },
                onSend = {
                    val words = local.replies[item.key].orEmpty().trim()
                    if (words.isNotEmpty()) go(1, shown - item) { local.replies.remove(item.key); local.answered[item.key] = item.updatedAt; onReply(item, words) }
                },
                hint = hintOf(item),
                onField = { field = it },
            )
        }
    }
}

/** What swiping a card does, as far as it can be swiped. */
private fun hintOf(item: WorkItem) = listOfNotNull(
    item.answers.firstOrNull { it.kind == "defer" }?.let { "← ${it.label}" },
    item.answers.firstOrNull { it.kind == "delegate" && it.text != null }?.let { "${it.label} →" },
).joinToString("\u3000")

/** A card's face: its ring and its quiet line (whose, what, since when), `1 / N`, what is to be decided, its answers; `fill`: as the one behind (its pills not to be pressed). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Face(
    item: WorkItem, number: Int, of: Int, haze: HazeState, modifier: Modifier, fill: Boolean = false, gesture: Modifier = Modifier,
    onCycle: () -> Unit = {}, onPill: (WorkAnswer) -> Unit = {}, hint: String = "",
    reply: String = "", onType: (String) -> Unit = {}, onSend: () -> Unit = {},
    onField: (androidx.compose.ui.geometry.Rect) -> Unit = {},
) {
    Column(modifier.fillMaxWidth().floating(haze, CardShape).then(gesture).padding(start = 14.dp, end = 12.dp, top = 11.dp, bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
            val ring = if (item.mine) AskBlue else C.subtle
            Canvas(Modifier.size(9.dp)) {
                val w = 2.dp.toPx()
                drawCircle(ring, size.minDimension / 2 - w / 2, style = Stroke(w))
            }
            Spacer(Modifier.width(7.dp))
            Text(item.head, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (of > 1) Text(
                "$number / $of ›", fontSize = 13.sp, color = C.muted, maxLines = 1,
                modifier = Modifier.clip(CircleShape).clickable(enabled = !fill, onClick = onCycle).padding(horizontal = 4.dp, vertical = 2.dp),
            )
        }
        Spacer(Modifier.height(6.dp))
        // What is to be decided (the web's: 15px, 500).
        Text(item.question, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, color = C.ink)
        val pills = item.answers.filter { it.kind != "delegate" && it.kind != "defer" }
        if (pills.isNotEmpty() || hint.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                FlowRow(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    pills.forEach { a -> Pill(a, enabled = !fill) { onPill(a) } }
                }
                if (hint.isNotEmpty()) Text(hint, fontSize = 12.sp, color = C.subtle, maxLines = 1, modifier = Modifier.padding(start = 8.dp, bottom = 7.dp))
            }
        }
        Spacer(Modifier.height(8.dp))
        ReplyField(item.title, reply, enabled = !fill, onType = onType, onSend = onSend, onPlaced = onField)
    }
}

/**
 * Anything else, said of it right here: one line in the chip colour, a round ink send button in its end once something
 * is written. A touch in it stays in it (no swipe starts from it).
 */
@Composable
private fun ReplyField(title: String, text: String, enabled: Boolean, onType: (String) -> Unit, onSend: () -> Unit, onPlaced: (androidx.compose.ui.geometry.Rect) -> Unit) {
    val ink = C.ink
    Box(
        Modifier.fillMaxWidth().height(34.dp).onGloballyPositioned { onPlaced(it.boundsInRoot()) }.clip(CircleShape).background(C.chip)
            .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } },
        contentAlignment = Alignment.CenterStart,
    ) {
        androidx.compose.foundation.text.BasicTextField(
            text, onType, enabled = enabled, singleLine = true,
            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, color = ink),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(C.accent),
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Send),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSend = { onSend() }),
            modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 38.dp).semantics { contentDescription = "回复「$title」" },
            decorationBox = { field ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty()) Text("说点别的…", fontSize = 14.sp, color = C.subtle, maxLines = 1)
                    field()
                }
            },
        )
        if (text.isNotBlank()) Box(
            Modifier.align(Alignment.CenterEnd).padding(end = 4.dp).size(26.dp).clip(CircleShape).background(ink)
                .clickable(enabled = enabled, onClick = onSend).semantics { contentDescription = "发送" },
            contentAlignment = Alignment.Center,
        ) { fail.still.android.ui.IconIn(fail.still.android.ui.Icons.ArrowUp, 14.dp, C.bg) }
    }
}

/** An answer's pill: yes filled in ink, the others in the chip colour. */
@Composable
private fun Pill(a: WorkAnswer, enabled: Boolean, onClick: () -> Unit) {
    val yes = a.kind == "yes"
    Box(
        Modifier.height(32.dp).clip(CircleShape).background(if (yes) C.ink else C.chip)
            .clickable(enabled = enabled, onClick = onClick).padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(a.label, fontSize = 14.sp, color = if (yes) C.bg else C.ink, maxLines = 1, fontWeight = if (yes) FontWeight.Medium else FontWeight.Normal)
    }
}

/** Under the card, what letting it go that way does (`label`, the answer's): right, 随便 on ink; left, 待定 on the chip colour. */
@Composable
private fun Reveal(side: Int, label: String, modifier: Modifier) {
    val right = side > 0
    Box(
        modifier.clip(CardShape).background(if (right) C.ink else C.chip).padding(horizontal = 20.dp),
        contentAlignment = if (right) Alignment.CenterStart else Alignment.CenterEnd,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (right) {
                Text("→ $label", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.bg)
                Text("agent 自己判断", fontSize = 13.sp, color = C.bg.copy(alpha = 0.6f), maxLines = 1)
            } else {
                Text("排到最后，圈留着", fontSize = 13.sp, color = C.muted, maxLines = 1)
                Text("$label ←", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            }
        }
    }
}
