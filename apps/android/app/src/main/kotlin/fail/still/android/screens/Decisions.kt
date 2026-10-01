// Decisions (web mobile, the same interaction set): an agent's post that ends its turn asking people to decide carries
// options. In the chat they are a column of buttons right under the post, full width, one per line, the one the agent
// recommends last and filled in ink; a tap answers with it (the viewer's message, quoting the post). Answered (or
// replaced), the buttons go and a quiet line says how it went.
// The decisions page 「奏」 (from the home page's 奏 N) shows the workspace's decisions waiting for the viewer one at a
// time: the chat's title small at the top (to its chat), the messages before the post and the post itself as the chat
// draws them, and at the foot its options, the hint and `1 / N`. The whole decision is swiped: left 待定 (set aside on
// this device: last of the page, still waiting), right 不再提醒 (dismissed for the viewer). Let go past about a third
// of the width, or flung, it flies off and the next comes in; short of that it springs back.
// A card is options (the buttons above) or text: on the page a one-line field and a round send button where the options
// go (the reply is the viewer's message quoting the post, `decision.reply`); a swipe never starts in the field. A card
// of a type this app does not know is answered in its chat. In a chat only an options card has anything under it.
package fail.still.android.screens

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
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
internal fun DecisionOptions(options: List<DecisionOption>, modifier: Modifier = Modifier, enabled: Boolean = true, busy: String? = null, onPick: (DecisionOption) -> Unit) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { o ->
            val strong = o.recommended == true
            val ink = if (strong) C.bg else C.ink
            val free = enabled && busy == null
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (strong) C.ink else C.chip)
                    .alpha(if (enabled) 1f else 0.5f)
                    .clickable(enabled = free) { onPick(o) }
                    .padding(horizontal = 14.dp, vertical = 10.dp)
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(o.label, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium, color = ink)
                    o.detail?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = if (strong) C.bg.copy(alpha = 0.7f) else C.muted) }
                }
                if (busy == o.label) DoingMark(true, null, 14.dp)
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
    if (decision?.resolved == true || decision?.dismissed == true) {
        decision.text?.let { Text(it, fontSize = 13.sp, lineHeight = 19.sp, color = chatSubtle(), modifier = Modifier.padding(top = 2.dp)) }
        return
    }
    if (options.isNullOrEmpty()) return
    val app = LocalApp.current
    val station = ctx.station
    val busy = options.firstOrNull { app.isDoing("decision.answer", "station" to station, "thread" to m.thread, "seq" to m.seq, "option" to it.label) }?.label
    DecisionOptions(
        options, Modifier.padding(top = 6.dp), enabled = !ctx.view.offline && ctx.view.archived != true, busy = busy,
    ) { o -> app.act("回答") { app.api(station).answerDecision(m.thread, m.seq, o.label) } }
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

    fun undo(key: String) { gone.remove(key); later.remove(key) }

    fun caughtUp(items: List<DecisionItem>) {
        val keys = items.mapTo(HashSet()) { it.key }
        gone.removeAll { it !in keys }
        later.removeAll { it !in keys }
    }

    fun shown(items: List<DecisionItem>): List<DecisionItem> {
        val left = items.filter { it.key !in gone }
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
    // Only the core can confirm the queue is empty; an optimistic dismissal may still fail.
    // Covered pages stay composed: never pop the chat opened over this page.
    val empty = view != null && !view.loading && view.count == 0u && topic.error == null
    val active = app.stack.lastOrNull() == Screen.Decisions
    LaunchedEffect(empty, active) {
        if (empty && active) app.pop()
    }
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars))) {
        TopBack("会话", app::pop)
        if (shown.isEmpty()) {
            val note = when {
                view == null -> topic.error?.message ?: "正在读取…"
                view.loading -> "正在读取…"
                else -> "没有等你决定的事"
            }
            Box(Modifier.weight(1f).fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                Text(note, fontSize = 15.sp, color = if (view == null && topic.error != null) C.red else C.muted, textAlign = TextAlign.Center)
            }
            return@Column
        }
        Deck(shown, local, Modifier.weight(1f))
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
    // The front one's way across (px), its coming in (0 → 1) and its fading as it is answered: its own, new with
    // another in front, so what went is not snapped back a frame before the next takes its place.
    val drag = remember(item.key) { Animatable(0f) }
    val arrive = remember(item.key) { Animatable(if (local.arriving && !still) 0f else 1f) }
    val fade = remember(item.key) { Animatable(1f) }
    LaunchedEffect(item.key) {
        local.arriving = false
        if (arrive.value < 1f) arrive.animateTo(1f, tween(260, easing = Ease.Out))
    }
    var width by remember { mutableIntStateOf(1) }
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

    /** The front one goes (`dir` its side; 0 fades where it is), `then` is done, and the next comes in. */
    fun go(dir: Int, then: () -> Unit) {
        if (busy) return
        busy = true
        scope.launch {
            if (!still) {
                if (dir != 0) drag.animateTo(dir * width * 1.25f, tween(220, easing = Ease.Standard))
                else fade.animateTo(0f, tween(160, easing = Ease.Css))
            }
            local.arriving = true
            val alone = n == 1
            then()
            busy = false
            // The only one, set aside: still the one in front; it comes in again.
            if (alone) {
                drag.snapTo(0f); fade.snapTo(1f)
                if (!still) { arrive.snapTo(0f); arrive.animateTo(1f, tween(260, easing = Ease.Out)) }
                local.arriving = false
            }
        }
    }
    val defer = { go(-1) { local.later.remove(item.key); local.later.add(item.key); call("待定") { app.api(item.station).deferDecision(item.thread, item.seq) } } }
    val dismiss = { go(1) { local.gone.add(item.key); call("不再提醒") { app.api(item.station).dismissDecision(item.thread, item.seq) } } }
    val answer = { o: DecisionOption -> go(0) { local.gone.add(item.key); call("回答") { app.api(item.station).answerDecision(item.thread, item.seq, o.label) } } }
    // A text card's reply: it stays (a spinner on its send) until the core has it, then goes as an answer does; refused,
    // what was written stays and why is said.
    val reply = { text: String ->
        app.scope.launch {
            try {
                app.api(item.station).replyDecision(item.thread, item.seq, text)
                go(0) { local.gone.add(item.key) }
            } catch (e: CoreException) { app.toast = "没能回复：${errorText(e)}" }
        }
        Unit
    }

    Column(modifier.fillMaxWidth()) {
        Box(
            Modifier.weight(1f).fillMaxWidth().clipToBounds().onSizeChanged { width = it.width.coerceAtLeast(1) }
                .onGloballyPositioned { frame = it }
                .pointerInput(item.key, still) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        if (busy || inField(down.position)) return@awaitEachGesture
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
            if (x != 0f) Box(
                Modifier.matchParentSize().padding(horizontal = 24.dp).graphicsLayer { alpha = (abs(drag.value) / (width * 0.12f)).coerceIn(0f, 1f) },
                contentAlignment = if (x > 0) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Text(if (x > 0) "不再提醒" else "待定", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.muted)
            }
            Column(
                Modifier.fillMaxSize().graphicsLayer {
                    val a = arrive.value
                    val s = lerp(0.94f, 1f, a)
                    scaleX = s; scaleY = s
                    translationX = drag.value
                    rotationZ = drag.value / width * 4f
                    alpha = a * fade.value
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
    item: DecisionItem, onPick: (DecisionOption) -> Unit, onReply: (String) -> Unit, onField: (LayoutCoordinates) -> Unit,
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
        "options" -> DecisionOptions(card?.options ?: item.options, Modifier.padding(horizontal = 14.dp), onPick = onPick)
        "text" -> TextReply(item, card?.placeholder, onField, onReply)
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

/**
 * A text card's foot: a one-line field (the agent's placeholder, else 写点什么…) and a round send button in ink; the
 * keyboard's send or the button replies. While the reply is under way, a spinner on the button and nothing pressed again;
 * refused, what was written stays.
 */
@Composable
private fun TextReply(item: DecisionItem, placeholder: String?, onField: (LayoutCoordinates) -> Unit, onReply: (String) -> Unit) {
    val app = LocalApp.current
    var text by remember(item.key) { mutableStateOf("") }
    val doing = app.isDoing("decision.reply", "station" to item.station, "thread" to item.thread, "seq" to item.seq)
    val ready = text.isNotBlank() && !doing
    val send = { if (ready) onReply(text.trim()) }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(22.dp)).background(C.chip).onGloballyPositioned(onField)
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (text.isEmpty()) Text(placeholder?.takeIf { it.isNotBlank() } ?: "写点什么…", fontSize = 15.sp, color = C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
            BasicTextField(
                text, { text = it }, Modifier.fillMaxWidth().semantics { contentDescription = "回复" },
                enabled = !doing, singleLine = true,
                textStyle = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, color = C.ink), cursorBrush = SolidColor(C.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send), keyboardActions = KeyboardActions(onSend = { send() }),
            )
        }
        // Nothing to send: the ink faint over the page (as the composer's).
        Box(
            Modifier.size(40.dp).clip(CircleShape).background(if (ready || doing) C.ink else C.ink.copy(alpha = 0.18f).compositeOver(C.bg))
                .clickable(enabled = ready) { send() }.semantics { contentDescription = "发送" },
            contentAlignment = Alignment.Center,
        ) {
            if (doing) CircularProgressIndicator(Modifier.size(16.dp), color = C.bg, strokeWidth = 2.dp)
            else IconIn(Icons.ArrowUp, 18.dp, C.bg)
        }
    }
}
