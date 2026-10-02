// Decisions (web mobile, the same interaction set): an agent's post that ends its turn asking people to decide carries
// options. In the chat they are a column of buttons right under the post, full width, one per line, the one the agent
// recommends last and filled in ink; a tap answers with it (the viewer's message, quoting the post). Answered (or
// replaced), the buttons go and a quiet line says how it went.
// The decisions page 「奏」 (from the home page's 奏 N) shows the workspace's decisions waiting for the viewer one at a
// time: the chat's title small at the top (to its chat), the messages before the post and the post itself as the chat
// draws them, and at the foot its options, the hint and `1 / N`. The whole decision is swiped: left 待定 (set aside on
// this device: last of the page, still waiting), right 不再提醒 (dismissed for the viewer). Let go past about a third
// of the width, or flung, it flies off and the next comes in; short of that it springs back.
// Options and text cards both have a multiline reply field on the page, below any options
// offered (the reply is the viewer's message quoting the post, `decision.reply`); a swipe never starts in the field. A card
// of a type this app does not know is answered in its chat. In a chat only an options card has anything under it.
package fail.still.android.screens

import androidx.compose.animation.AnimatedVisibility
import fail.still.android.ui.AgentStateMark
import fail.still.android.data.ChatState
import fail.still.android.R
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.Image
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.ui.unit.IntSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.material3.ripple
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import fail.still.android.ui.keyboard
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.util.lerp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.DecisionItem
import fail.still.android.data.DecisionOption
import fail.still.android.data.DecisionsView
import fail.still.android.data.Link
import fail.still.android.data.Me
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.errorText
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Ease
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MoveSpring
import fail.still.android.ui.reducedMotion
import fail.still.core.CoreException
import kotlin.math.abs
import kotlinx.coroutines.launch

// ── the options ────────────────────────────────────────────────────────

/**
 * A decision's options, one per line, full width: the label (medium) and its detail under it, small and quiet; the
 * recommended one (last, as the core orders them) filled in ink with the page's colour for its words, the others in the
 * chip colour. `busy`: the label of the one being sent (a spinner on it, none pressed meanwhile).
 */
@Composable
internal fun DecisionOptions(options: List<DecisionOption>, modifier: Modifier = Modifier, enabled: Boolean = true, busy: String? = null, failed: String? = null, onPick: (DecisionOption) -> Unit) {
    val still = reducedMotion()
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { o ->
            val strong = o.recommended == true
            val ink = if (strong) C.bg else C.ink
            val free = enabled && busy == null
            val touch = remember(o.label) { MutableInteractionSource() }
            val pressed by touch.collectIsPressedAsState()
            val scale by animateFloatAsState(
                if (pressed && !still) 0.97f else 1f,
                tween(if (still) 0 else if (pressed) 80 else 180, easing = Ease.Out), label = "decision press",
            )
            Row(
                Modifier.fillMaxWidth().graphicsLayer { scaleX = scale; scaleY = scale }
                    .clip(RoundedCornerShape(12.dp)).background(if (strong) C.ink else C.chip)
                    .alpha(if (enabled) 1f else 0.5f)
                    .clickable(enabled = free, interactionSource = touch, indication = ripple(color = ink)) { onPick(o) }
                    .padding(horizontal = 14.dp, vertical = 10.dp)
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(o.label, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, color = ink)
                    o.detail?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = if (strong) C.bg.copy(alpha = 0.7f) else C.muted) }
                }
                if (busy == o.label || failed != null) DoingMark(busy == o.label, failed, 14.dp)
            }
        }
    }
}

/**
 * Under a post in a chat (Chat.kt SaidRow): its options while it waits, a tap answering with one; once answered (or
 * dismissed by the viewer, or replaced), no buttons, and how it went in a quiet line when the core says. Nothing under
 * other messages, nor from a station before decisions.
 */
@Composable
internal fun DecisionUnder(ctx: Here, m: ChatMessage) {
    val card = m.card
    if (card == null && m.options == null) return
    // Buttons only for an options card (a core before cards: `options` alone); a text card is answered on the 奏 page.
    val options = if (card != null) card.options.takeIf { card.type == "options" } else m.options
    val decision = m.decision
    val resolved = decision?.resolved == true || decision?.dismissed == true
    if (options.isNullOrEmpty()) {
        val label = if (resolved) decision?.text else card?.assigneeText
        label?.let { Text(it, fontSize = 13.sp, lineHeight = 19.sp, color = chatSubtle(), modifier = Modifier.padding(top = 2.dp)) }
        return
    }
    val app = LocalApp.current
    val station = ctx.station
    val still = reducedMotion()
    val busy = options.firstOrNull { app.isDoing("decision.answer", "station" to station, "thread" to m.thread, "seq" to m.seq, "option" to it.label) }?.label
    Column {
        // Match chat-list archive: the whole group shrinks/fades, then a delayed spring closes its space.
        AnimatedVisibility(
            visible = !resolved, enter = EnterTransition.None,
            exit = fadeOut(tween(if (still) 0 else LEAVE_MS, easing = CssEaseOut)) +
                scaleOut(tween(if (still) 0 else LEAVE_MS, easing = CssEaseOut), targetScale = 0.9f) +
                shrinkVertically(
                    if (still) tween(0) else closeGap(IntSize.VisibilityThreshold),
                    shrinkTowards = Alignment.Top, clip = false,
                ),
        ) {
            Column {
                card?.assigneeText?.let { Text(it, fontSize = 13.sp, lineHeight = 19.sp, color = chatSubtle(), modifier = Modifier.padding(top = 2.dp)) }
            DecisionOptions(
                options, Modifier.padding(top = 6.dp),
                enabled = !ctx.view.offline && ctx.view.archived != true, busy = busy,
            ) { o -> if (!resolved) app.act("回答") { app.api(station).answerDecision(m.thread, m.seq, o.label) } }
            }
        }
        AnimatedVisibility(
            visible = resolved && decision?.text != null,
            enter = fadeIn(tween(if (still) 0 else LEAVE_MS, delayMillis = if (still) 0 else LEAVE_MS, easing = CssEaseOut)) +
                expandVertically(if (still) tween(0) else closeGap(IntSize.VisibilityThreshold), expandFrom = Alignment.Top),
        ) {
            Text(decision?.text.orEmpty(), fontSize = 13.sp, lineHeight = 19.sp, color = chatSubtle(), modifier = Modifier.padding(top = 2.dp))
        }
    }
}

// ── the page ───────────────────────────────────────────────────────────

/** A decision's own key: its station, chat and post. */
private val DecisionItem.key get() = "$station\t$thread\t$seq"

/** Let go past this share of its width, the decision goes. */
private const val THRESHOLD = 0.35f

/**
 * What this device did to the page's decisions before the core says so (kept with the page): one answered or dismissed
 * is not shown, one set aside goes last; each until the core's list has it so.
 */
@Stable
private class DecisionsLocal {
    val gone = mutableStateListOf<String>()
    val later = mutableStateListOf<String>()
    /** The decision in front came in as the one before went: it comes in, not there at once. */
    var arriving by mutableStateOf(false)
    // Keep a reply visible if the core removes it before its exit finishes.
    var replying by mutableStateOf<DecisionItem?>(null)

    fun undo(key: String) { gone.remove(key); later.remove(key) }

    fun caughtUp(items: List<DecisionItem>) {
        val keys = items.mapTo(HashSet()) { it.key }
        gone.removeAll { it !in keys }
        later.removeAll { it !in keys }
    }

    fun shown(items: List<DecisionItem>): List<DecisionItem> {
        val held = replying
        val source = if (held != null) listOf(held) + items.filter { it.key != held.key } else items
        val left = source.filter { it.key !in gone }
        val (moved, rest) = left.partition { it.key in later }
        return rest + later.mapNotNull { k -> moved.find { it.key == k } }
    }
}

@Composable
fun DecisionsScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<DecisionsView>(app.core, Topics.decisions(current.workspace.id))
    val local = remember { DecisionsLocal() }
    val view = topic.value
    val items = view?.items.orEmpty()
    SideEffect { local.caughtUp(items) }
    val shown = local.shown(items)
    // With none left the page stays, for the next to come.
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars))) {
        TopBack("会话", app::pop)
        if (shown.isEmpty()) {
            if (view != null && !view.loading) {
                Idle(view, Modifier.weight(1f))
                return@Column
            }
            val note = if (view == null) topic.error?.message ?: "正在读取…" else "正在读取…"
            Box(Modifier.weight(1f).fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                Text(note, fontSize = 15.sp, color = if (view == null && topic.error != null) C.red else C.muted, textAlign = TextAlign.Center)
            }
            return@Column
        }
        Deck(shown, local, Modifier.weight(1f))
    }
}

/**
 * None left (web DecisionsIdle.tsx): the page stays for the next to come and says how the day went (how many answered,
 * how long they waited on average, how many agents are at work), where the next may come from (the viewer's chats with
 * an agent at work or waiting) and what was answered today. Each opens its chat.
 */
@Composable
private fun Idle(view: DecisionsView, modifier: Modifier) {
    val app = LocalApp.current
    val today = view.today
    val working = view.working.orEmpty()
    val answered = view.answered.orEmpty()
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 24.dp)) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Image(painterResource(if (C.dark) R.drawable.buddy_idle_dark else R.drawable.buddy_idle), null, Modifier.size(72.dp))
            Text("奏折都批完了", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.padding(top = 8.dp))
            Text("有新的会直接出现在这里", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp))
            if (today != null) {
                Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(28.dp)) {
                    Figure(today.count.toString(), "今天批了")
                    today.waited?.let { Figure(it, "平均等你") }
                    Figure(today.working.toString(), "正在办")
                }
            }
        }
        if (working.isNotEmpty()) {
            IdleTitle("正在办 · 下一封可能从这里来")
            working.forEach { w ->
                IdleRow(w.title, w.line, w.time?.get("lastActiveAt")?.ago.orEmpty(), busy = true) { app.push(Screen.Chat(w.station, ChatOf.Session(w.session))) }
            }
        }
        if (answered.isNotEmpty()) {
            IdleTitle("今天批过的")
            answered.forEach { a ->
                IdleRow(a.text, "${a.title} · ${a.answer}", a.clock, busy = false) { app.push(Screen.Chat(a.station, ChatOf.Session(a.session))) }
            }
        }
    }
}

@Composable
private fun Figure(figure: String, words: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(figure, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Text(words, fontSize = 12.sp, color = C.subtle)
    }
}

@Composable
private fun IdleTitle(text: String) {
    Text(text, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = C.subtle, modifier = Modifier.padding(start = 10.dp, top = 28.dp, bottom = 4.dp))
}

/** A chat at work (the turning yellow ring) or a card answered (a quiet dot): its words over where it is, when at its end. */
@Composable
private fun IdleRow(main: String, meta: String, at: String, busy: Boolean, onOpen: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable(onClick = onOpen).padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.padding(top = 4.dp).size(12.dp), contentAlignment = Alignment.Center) {
            if (busy) AgentStateMark(ChatState.Running, C.bg)
            else Box(Modifier.size(6.dp).clip(RoundedCornerShape(3.dp)).background(C.subtle))
        }
        Column(Modifier.weight(1f)) {
            Text(main, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(meta, fontSize = 13.sp, color = C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(at, fontSize = 12.sp, color = C.subtle)
    }
}

/**
 * The decision in front, swiped where it rests: the drag is read on the page's frame (which does not move) before
 * anything in it (PointerEventPass.Initial), so it works over messages and buttons that take touches; across first, it
 * is the swipe and they let go (a tap on an option still answers); up or down first, it is theirs (the messages scroll).
 */
@Composable
private fun Deck(shown: List<DecisionItem>, local: DecisionsLocal, modifier: Modifier) {
    val app = LocalApp.current
    val item = shown.first()
    val n = shown.size
    val still = reducedMotion()
    val scope = rememberCoroutineScope()
    // The front one's way across (px), its coming in (0 → 1) and its departure as it is answered: its own, new with
    // another in front, so what went is not snapped back a frame before the next takes its place.
    val drag = remember(item.key) { Animatable(0f) }
    val lift = remember(item.key) { Animatable(0f) }
    val arrive = remember(item.key) { Animatable(if (local.arriving && !still) 0f else 1f) }
    LaunchedEffect(item.key) {
        local.arriving = false
        if (arrive.value < 1f) arrive.animateTo(1f, tween(260, easing = Ease.Out))
    }
    var width by remember { mutableIntStateOf(1) }
    var height by remember { mutableIntStateOf(1) }
    var busy by remember { mutableStateOf(false) }
    // The deck's frame and a text card's field in it: a touch that begins in the field is the field's (no swipe).
    var frame by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var field by remember(item.key) { mutableStateOf<LayoutCoordinates?>(null) }
    fun inField(p: Offset): Boolean {
        val f = field?.takeIf { it.isAttached } ?: return false
        val box = frame?.takeIf { it.isAttached } ?: return false
        return box.localBoundingBoxOf(f).contains(p)
    }

    /** Says it to the core; refused, the decision is back and why is said. */
    fun call(what: String, run: suspend () -> Unit) {
        app.scope.launch {
            try { run() } catch (e: CoreException) { local.undo(item.key); app.toast = "没能$what：${errorText(e)}" }
        }
    }

    /** The front one goes (`dir` its side, 0 up after answering), `then` is done, and the next comes in. */
    fun go(dir: Int, then: () -> Unit) {
        if (busy) return
        busy = true
        scope.launch {
            if (!still) {
                if (dir == 0) lift.animateTo(height.toFloat(), tween(360, easing = androidx.compose.animation.core.CubicBezierEasing(0.55f, 0f, 0.85f, 0.35f)))
                else drag.animateTo(dir * width * 1.25f, tween(260, easing = Ease.Standard))
            }
            // The next card is already laid out underneath the departing one.
            local.arriving = n == 1
            val alone = n == 1
            then()
            busy = false
            // The only one, set aside: still the one in front; it comes in again.
            if (alone && item.key !in local.gone) {
                drag.snapTo(0f)
                if (!still) { arrive.snapTo(0f); arrive.animateTo(1f, tween(260, easing = Ease.Out)) }
                local.arriving = false
            }
        }
    }
    val defer = { if (local.replying == null) go(-1) { local.later.remove(item.key); local.later.add(item.key); call("待定") { app.api(item.station).deferDecision(item.thread, item.seq) } } }
    val dismiss = { if (local.replying == null) go(1) { local.gone.add(item.key); call("不再提醒") { app.api(item.station).dismissDecision(item.thread, item.seq) } } }
    val answer = { o: DecisionOption -> if (local.replying == null) go(0) { local.gone.add(item.key); call("回答") { app.api(item.station).answerDecision(item.thread, item.seq, o.label) } } }
    // A text card's reply: it stays (a spinner on its send) until the core has it, then goes as an answer does; refused,
    // what was written stays and why is said.
    val replyDraft = rememberDraft("decision:${item.station}:${item.thread}:${item.seq}")
    val reply = {
        val text = replyDraft.text.trim()
        val files = replyDraft.files.mapNotNull { it.done }
        val quotes = replyDraft.quotes.map { it.sent() }
        if (replyDraft.ready && !busy && local.replying == null) {
            local.replying = item
            replyDraft.starting = true
            app.scope.launch {
                try {
                    app.api(item.station).replyDecision(item.thread, item.seq, text, files, quotes)
                    replyDraft.take()
                    go(0) { local.gone.add(item.key); local.replying = null }
                } catch (e: CoreException) { local.replying = null; app.toast = "没能回复：${errorText(e)}" }
                finally { replyDraft.starting = false }
            }
        }
        Unit
    }

    Column(modifier.fillMaxWidth()) {
        Box(
            Modifier.weight(1f).fillMaxWidth().clipToBounds().onSizeChanged { width = it.width.coerceAtLeast(1); height = it.height.coerceAtLeast(1) }
                .onGloballyPositioned { frame = it }
                .pointerInput(item.key, still) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        if (busy || local.replying != null || inField(down.position)) return@awaitEachGesture
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
                                        at > width * THRESHOLD || fling && at > 0 -> dismiss()
                                        at < -width * THRESHOLD || fling && at < 0 -> defer()
                                        else -> scope.launch { if (still) drag.snapTo(0f) else drag.animateTo(0f, MoveSpring, v) }
                                    }
                                }
                                break
                            }
                            val dx = change.position.x - change.previousPosition.x
                            if (!swiping) {
                                across += dx
                                upDown += change.position.y - change.previousPosition.y
                                // Up or down first: the messages' (they scroll), not a swipe.
                                if (abs(upDown) > viewConfiguration.touchSlop && abs(upDown) > abs(across)) break
                                if (abs(across) <= viewConfiguration.touchSlop) continue
                                swiping = true
                                tracker.resetTracking()
                            }
                            change.consume()
                            if (busy) continue
                            tracker.addPosition(change.uptimeMillis, change.position)
                            pos += dx
                            val to = pos
                            scope.launch { drag.snapTo(to) }
                        }
                    }
                }
                .semantics {
                    customActions = listOf(
                        CustomAccessibilityAction("待定") { defer(); true },
                        CustomAccessibilityAction("不再提醒") { dismiss(); true },
                    )
                },
        ) {
            // Under it, what letting it go that way does: left 待定 (at the right edge it uncovers), right 不再提醒.
            val x = drag.value
            if (x != 0f && !busy) Box(
                Modifier.matchParentSize().padding(horizontal = 24.dp).graphicsLayer { alpha = (abs(drag.value) / (width * 0.12f)).coerceIn(0f, 1f) },
                contentAlignment = if (x > 0) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Text(if (x > 0) "不再提醒" else "待定", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.muted)
            }
            if (busy && n > 1) {
                Column(Modifier.fillMaxSize().background(C.bg)) {
                    Face(shown[1], onPick = {}, onReply = {}, onField = {})
                }
            }
            Column(
                Modifier.fillMaxSize().graphicsLayer {
                    val a = arrive.value
                    val progress = (lift.value / height).coerceIn(0f, 1f)
                    val gathered = (progress / 0.4f).coerceIn(0f, 1f)
                    val s = lerp(0.94f, 1f, a) * lerp(1f, 0.88f, gathered)
                    scaleX = s; scaleY = s
                    translationX = drag.value
                    translationY = -lift.value
                    transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 0f)
                    rotationZ = drag.value / width * 4f
                    alpha = a
                }.background(C.bg),
            ) { Face(item, onPick = answer, onReply = reply, onField = { field = it }) }
        }
        // The hint and where this one is among them, still.
        Row(
            Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("← 待定　不再提醒 →", fontSize = 12.sp, color = C.subtle, maxLines = 1, modifier = Modifier.weight(1f))
            Text("1 / $n", fontSize = 12.sp, color = C.subtle, maxLines = 1)
        }
    }
}

/**
 * A decision as the page shows it: its chat's title (to the chat), the messages before it and the post as the chat
 * draws them (scrolled to the post), its options at its foot.
 */
@Composable
private fun androidx.compose.foundation.layout.ColumnScope.Face(
    item: DecisionItem, onPick: (DecisionOption) -> Unit, onReply: () -> Unit, onField: (LayoutCoordinates) -> Unit,
) {
    val app = LocalApp.current
    val messages = item.before + item.message
    // The chat as far as these messages go: enough for them to be drawn as in it (files kept by the post's agent).
    val view = remember(item) {
        ChatView(
            me = Me(), title = item.title, people = emptyList(), agents = emptyList(), messages = messages, more = false,
            outbox = emptyList(), link = Link("online"), offline = false,
        )
    }
    val of = ChatOf.Session(item.session)
    val ctx = remember(item) { Here(item.station, of, view, emptyList(), orOwner = item.message.by.agent ?: item.session) }
    Row(
        Modifier.fillMaxWidth().clickable { app.push(Screen.Chat(item.station, of)) }.padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) { contentDescription = "打开对话「${item.title}」" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(item.title, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
    item.card?.assigneeText?.let { Text(it, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
    val scroll = rememberScrollState()
    val density = LocalDensity.current
    var postAt by remember(item.key) { mutableStateOf<Float?>(null) }
    // Long, it opens at the post (what is to be decided), with a little of what came before above it.
    LaunchedEffect(item.key, postAt) {
        val y = postAt ?: return@LaunchedEffect
        scroll.scrollTo((y - with(density) { 48.dp.toPx() }).toInt().coerceAtLeast(0))
    }
    Column(
        Modifier.weight(1f).fillMaxWidth().verticalScroll(scroll).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        messages.forEach { m ->
            Box(if (m === item.message) Modifier.onGloballyPositioned { if (postAt == null) postAt = it.positionInParent().y } else Modifier) {
                SaidAlone(ctx, m)
            }
        }
    }
    Spacer(Modifier.height(4.dp))
    val card = item.card
    when (card?.type ?: "options") {
        "options" -> {
            DecisionOptions(card?.options ?: item.options, Modifier.padding(horizontal = 14.dp), onPick = onPick)
            Spacer(Modifier.height(8.dp))
            DecisionComposer(item, null, onField, onReply)
        }
        "text" -> DecisionComposer(item, card?.placeholder, onField, onReply)
        // A card this app does not know: answered in its chat, at the post.
        else -> Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("这张卡片要在 chat 里回", fontSize = 13.sp, color = C.muted)
            Box(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.ink)
                    .clickable { app.push(Screen.Chat(item.station, of, at = item.seq)) }.padding(vertical = 12.dp),
                contentAlignment = Alignment.Center,
            ) { Text("去 chat 里回", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.bg) }
        }
    }
}

/** Uses the chat's entire composer: attachments, references, draft extras, capsule and resizing. */
@Composable
private fun DecisionComposer(item: DecisionItem, placeholder: String?, onField: (LayoutCoordinates) -> Unit, onReply: () -> Unit) {
    val app = LocalApp.current
    val draft = rememberDraft("decision:${item.station}:${item.thread}:${item.seq}")
    val host = remember(item.key) { Host() }
    val launchers = AttachLaunchers { picked -> app.upload(draft, item.station, picked, app.scope) }
    host.spec = ComposerSpec(
        station = item.station, here = item.session, draft = draft, placeholder = placeholder ?: "发消息",
        onPlus = { openAttach(app, launchers) }, onSend = onReply,
    )
    host.density = LocalDensity.current
    HostComposer(host, Modifier.onGloballyPositioned(onField).layout { measurable, constraints ->
        val composer = measurable.measure(constraints)
        val height = constraints.constrainHeight(maxOf(composer.height, host.roomForList()))
        layout(composer.width, height) { composer.place(0, height - composer.height) }
    }, overContent = false)
}
