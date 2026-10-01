// A new chat and a chat are one page (web mobile/ChatHost.tsx): what is above changes (a new chat's scene, then the chat
// it made), the composer at its foot is one, kept, with what is typed and the focus, as a new chat becomes its chat. What
// the composer writes to is the page's: it says so (`Host.spec`), and the composer asks it when a message goes.
//
// What is sent is drawn where it arrives and moved from where it comes from (web madeChat.ts), the same in a new chat and
// in a chat: its words stay where they were typed until its row is in the list, then that row (the real one, whatever it
// becomes: outbox, then the chat's message) is drawn over the composer from the words' place and size to its own, its
// bubble and time coming in around it; the composer's hint comes back once the words have left the composer. Its words
// go piece by piece (cut where the field's lines break and where the bubble's do): each from where it was typed to its
// place in the bubble, so a message of many lines leaves the field as it was, its lines neither spreading nor rewrapping
// at once (the field's lines and the bubble's are not as tall, nor as wide). A new
// chat's scene leaves first (up out of view, its choices fading where they are), and the chat's list comes up after the
// words, out of the composer's top edge. Nothing is crossfaded over anything.
package fail.still.android.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.drawText
import androidx.compose.foundation.layout.size
import androidx.compose.ui.layout.layout
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import fail.still.android.Screen
import fail.still.android.data.WorkspaceEntry
import fail.still.android.ui.C
import fail.still.android.ui.ComposerCorner
import fail.still.android.ui.ComposerInset
import fail.still.android.ui.Ease
import fail.still.android.ui.floating
import fail.still.android.ui.reducedMotion
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/** What the composer writes to, as the page above it says: where (its station, and the chat not offered to `@`), the draft, and what its buttons do. */
class ComposerSpec(
    val station: String, val here: String?, val draft: Draft, val placeholder: String,
    val notices: @Composable ColumnScope.() -> Unit = {},
    val onPlus: () -> Unit, val onType: () -> Unit = {}, val onSend: () -> Unit,
)

/**
 * A message's words on their way from the composer to their row: `from`, where their first line's letters start (in the
 * host), at `fromSize`; `field`, the field's own corner and width (where they wait, drawn as typed, until the row is in
 * the list); `top`, the composer's top edge. `carried`: the list comes up with them (a new chat's first message).
 */
@Stable
class Flight internal constructor(
    val text: String, val from: Offset, val fromSize: Float, val field: Offset, val fieldWidth: Int, val fieldHeight: Int, val top: Float,
    val carried: Boolean, internal val before: Set<String>,
    /** The field's words as laid out when sent (`text` starting at `lead` in them: what is sent is trimmed). */
    internal val typed: TextLayoutResult? = null, internal val lead: Int = 0,
) {
    /** How far the field had scrolled its words: to their end (the caret's, as it sends), when they are taller than it. */
    internal val scroll: Float = ((typed?.size?.height ?: 0) - fieldHeight).coerceAtLeast(0).toFloat()
    /** Its row is laid out in the list (not only composed ahead, out of sight): they go from then on. */
    internal var placed by mutableStateOf(false)
    /** The row the words went into (its key in the list), once it is there. */
    var key by mutableStateOf<String?>(null)
        internal set
    internal var row: LayoutCoordinates? = null
    internal var bubble: LayoutCoordinates? = null
    /** Where the bubble's letters start in it, and their size; `pad`, where its words are in it. */
    internal var inBubble = Offset.Zero
    internal var pad = Offset.Zero
    /** The bubble's words as laid out (its row's, as it is now). */
    internal var words: TextLayoutResult? = null
        set(value) { if (field !== value) { field = value; cut = null } }
    private var cut: List<Piece>? = null
    internal var toSize = 1f
    /** How far above its place the list starts (a new chat's: the words' way up), once the row is laid out. */
    internal var rise: Float? = null
    internal val progress = Animatable(0f)
    /**
     * How far it has come (eased): across, and up. In an open chat across first and up a little after, so the words
     * rise on a curve (web madeChat.ts flight()); a new chat's first words both at once.
     */
    fun e(): Float = if (carried) Ease.Arrive.transform(progress.value) else settle()
    fun across(): Float = if (carried) e() else Ease.Flight.transform((fly() / 0.88f).coerceAtMost(1f))
    fun up(): Float = if (carried) e() else Ease.Flight.transform(((fly() - 0.12f) / 0.88f).coerceAtLeast(0f))
    /**
     * In an open chat the words first fly as they were typed (`fly`), all but there; then they settle into their bubble
     * (laid out and sized as in it), its ground and time coming in around them.
     */
    private fun fly(): Float = (progress.value / FLY).coerceAtMost(1f)
    fun settle(): Float = if (carried) e() else Ease.Arrive.transform(((progress.value - SETTLE) / (1f - SETTLE)).coerceIn(0f, 1f))
    private var aim: Offset? = null
    private var aimed = -1f
    /** Where the words make for, `place` (where they go, as it is now) followed a little behind, once a frame. */
    internal fun follow(place: Offset): Offset {
        val was = aim
        val t = progress.value
        if (t != aimed) { aimed = t; aim = if (was == null) place else was + (place - was) * 0.35f }
        return aim ?: place
    }

    /** Where the list is drawn now, off its place. */
    fun shift(): Float = if (carried) (rise ?: 0f) * (1f - e()) else 0f

    /**
     * In an open chat, how much of its row the list does not make room for yet: what the field did not show (the lines
     * above those it did), until they settle; then it comes in, pushing what is above up.
     */
    fun reserve(): Float = hidden() * (1f - settle())

    /** How tall in the bubble what the field did not show is (the lines above those it did). */
    internal fun hidden(): Float {
        if (carried) return 0f
        val ps = pieces() ?: return 0f
        val lead = ps.firstOrNull { it.shown } ?: return 0f
        return lead.clip.top - ps.first().clip.top
    }

    /**
     * How far the row's top is from where it will be (the list put in place frame by frame meanwhile, Chat.kt), or null
     * when the list is not (it is not following): then reckoned from the composer (Host.drop).
     */
    internal var toFinal: Float? = null

    /**
     * The words cut into the pieces that fly on their own: runs that are on one line both in the field and in the
     * bubble. Null when the two are not the same words (a reference to a chat is a chip in the bubble): the row then
     * flies whole.
     */
    internal fun pieces(): List<Piece>? {
        cut?.let { return it }
        val w = words ?: return null
        val t = typed ?: return null
        val s = w.layoutInput.text.text
        val was = t.layoutInput.text.text
        if (s.isEmpty() || lead < 0 || lead + s.length > was.length || !was.regionMatches(lead, s, 0, s.length)) return null
        val cuts = sortedSetOf(0, s.length)
        for (i in 0 until w.lineCount) cuts += w.getLineStart(i)
        for (i in 0 until t.lineCount) (t.getLineStart(i) - lead).let { if (it in 0..s.length) cuts += it }
        val ends = cuts.toList()
        val out = ArrayList<Piece>()
        for (i in 0 until ends.size - 1) {
            val a = ends[i]
            val b = ends[i + 1]
            if (s.substring(a, b).isBlank()) continue
            val lb = w.getLineForOffset(a)
            val lf = t.getLineForOffset(a + lead)
            val x = w.getHorizontalPosition(a, true)
            val left = if (a == w.getLineStart(lb)) 0f else x
            val right = if (b >= w.getLineEnd(lb)) w.size.width.toFloat() else w.getHorizontalPosition(b, true)
            val middle = (t.getLineTop(lf) + t.getLineBottom(lf)) / 2 - scroll
            out += Piece(
                Rect(left, w.getLineTop(lb), right, w.getLineBottom(lb)), Offset(x, w.getLineBaseline(lb)),
                Offset(t.getHorizontalPosition(a + lead, true), t.getLineBaseline(lf) - scroll),
                // Scrolled out of the field: not to be seen there, it comes in on its way.
                shown = middle in 0f..fieldHeight.toFloat(),
            )
        }
        // What was scrolled out of the field comes with the first piece that showed, laid out as in the bubble (one
        // block with it, not each from its own place out of sight).
        val first = out.firstOrNull { it.shown }
        val k = t.layoutInput.style.fontSize.value / w.layoutInput.style.fontSize.value
        if (first != null) for (i in out.indices) if (!out[i].shown) out[i] = out[i].let { Piece(it.clip, it.at, first.from + (it.at - first.at) * k, false) }
        cut = out
        return out
    }
}

/** A piece of the words: `clip`, its room in the bubble's words; `at`, where it starts there (its baseline); `from`, the same in the field's. */
internal class Piece(val clip: Rect, val at: Offset, val from: Offset, val shown: Boolean)

/** The page's composer and what moves around it. */
@Stable
class Host {
    val haze = HazeState()
    var spec by mutableStateOf<ComposerSpec?>(null)
    /** The composer's room at the foot, with its margins (what the page above keeps clear of), in px. */
    var composerHeight by mutableIntStateOf(0)
    /** The composer's room as the chat's list was last given it (composed with it: a frame behind its own changes). */
    internal var listRoom = 0
    /** The composer's room, for the chat's list. */
    fun roomForList(): Int = composerHeight.also { listRoom = it }
    /** The composer's room once it has come to what it holds (not held tall, nor on its way). */
    internal fun naturalRoom(): Int = morph?.let { composerHeight - (it.height() - contentHeight) } ?: composerHeight
    internal var field: LayoutCoordinates? = null
    internal var fieldText: TextLayoutResult? = null
    internal var capsule: LayoutCoordinates? = null
    internal var overlay: LayoutCoordinates? = null
    internal var layer: GraphicsLayer? = null
    /** Shows the chat's message `seq` (in the list, in its middle, flashing), if it is loaded: set by the list. */
    internal var showSaid: ((Long) -> Unit)? = null
    var flight by mutableStateOf<Flight?>(null)
        private set
    /** The composer's hint is away (words just sent are over it). */
    var hintAway by mutableStateOf(false)
        internal set
    /** A new chat's scene leaving, as it becomes its chat. */
    var leaving by mutableStateOf(false)
        internal set
    internal val leave = Animatable(0f)
    internal var still = false
    /** How many messages the composer has sent: the list goes to its end with each (Chat.kt). */
    var sends by mutableIntStateOf(0)
        private set

    /**
     * `text` is sent from the composer (before the draft is emptied): its words stay where they are until their row is in
     * the list, the first outgoing one not among `before` (the outbox's as it was sent: it is this device's own, so what
     * comes into it is what was just sent from here).
     */
    fun sending(text: String, carried: Boolean, before: Set<String> = rows) {
        sends++
        flight = null
        hold = null
        val field = field?.takeIf { it.isAttached }
        val overlay = overlay?.takeIf { it.isAttached }
        val capsule = capsule?.takeIf { it.isAttached }
        if (still || text.isEmpty() || field == null || overlay == null || capsule == null) return
        val at = overlay.localPositionOf(field, Offset.Zero)
        val d = density ?: return
        // The field's letters sit in its 21sp line as the bubble's in its 23sp one: centred.
        val from = at + Offset(0f, with(d) { (21.sp.toPx() - 16.sp.toPx()) / 2 })
        val typed = fieldText
        if (!carried) hold = contentHeight
        flight = Flight(
            text, from, with(d) { 16.sp.toPx() }, at, field.size.width, field.size.height, overlay.localPositionOf(capsule, Offset.Zero).y,
            carried, before, typed, typed?.layoutInput?.text?.text?.indexOf(text) ?: -1,
        )
        hintAway = true
    }

    /** What was sent did not go (or its row never came): the composer is as it was. */
    fun notSent() {
        if (flight?.placed != true) { flight = null; hintAway = false; hold = null }
    }

    /** A new chat becomes its chat: its scene leaves. */
    fun madeChat() { leaving = true }

    /**
     * The composer's content kept as tall as when the words were sent, until they are half way (it comes down then, not
     * from under them as they set out); `contentHeight`, how tall it is as laid out (held or not).
     */
    var hold by mutableStateOf<Int?>(null)
        internal set
    internal var contentHeight = 0
    internal var morph: Morph? = null

    /**
     * How much lower the list will be once the composer has come down to its content (held, or on its way down): the
     * words go where their row will be, not where the composer, still tall, has it for now. The list's room is the
     * composer's as it was given it (it follows the composer a frame behind).
     */
    internal fun drop(): Float = morph?.let { (listRoom - composerHeight + it.height() - contentHeight).coerceAtLeast(0).toFloat() } ?: 0f

    /** The rows the list shows now (by key): what was there before a message is sent is not where it goes. */
    var rows: Set<String> = emptySet()

    /**
     * Whether the row `id` is where the words sent go: the first row of this device's own that was not in the list when
     * they were sent (`mine`: an outbox entry, or a message of the viewer's; the outbox may be let go before the list
     * has shown it, when the station is quick).
     */
    fun takes(id: String, mine: Boolean): Boolean {
        val f = flight ?: return false
        if (f.key == null && mine && id !in f.before) f.key = id
        return f.key == id
    }

    /** How far down the host `c` is. */
    internal fun overlayY(c: LayoutCoordinates?): Float? {
        val o = overlay?.takeIf { it.isAttached } ?: return null
        return c?.takeIf { it.isAttached }?.let { o.localPositionOf(it, Offset.Zero).y }
    }

    internal fun landed(f: Flight) { if (flight === f) { flight = null; hintAway = false; hold = null } }
    internal var density: androidx.compose.ui.unit.Density? = null
}

/** The flight a row's content is drawn for (its bubble says where its letters are; its ground and time come in with it). */
val LocalFlight = staticCompositionLocalOf<Flight?> { null }
val LocalFlightHost = staticCompositionLocalOf<Host?> { null }

/** A row the words fly into: drawn by the host over the composer, from where they were to here, instead of in the list. */
fun Modifier.flying(host: Host, f: Flight?): Modifier = if (f == null) this else this
    // Its top (what the field did not show) not given room in the list yet: the row stands as tall as the rest, its
    // foot where it will be, what is above it lower by that much until the words settle.
    .layout { m, c ->
        val p = m.measure(c)
        val r = if (host.flight === f) f.reserve().roundToInt().coerceIn(0, p.height) else 0
        layout(p.width, p.height - r) { p.place(0, -r) }
    }
    .onGloballyPositioned { f.row = it; f.placed = true }
    .drawWithContent {
        // Landed: here again, in the frame the host stops drawing it (not the next, once the list has let it go).
        val layer = host.layer
        if (host.flight === f && layer != null) layer.record { this@drawWithContent.drawContent() } else drawContent()
    }

/** The bubble of a row flown into: where its letters start (`pad`: its padding; `line`, `size`: its line height and letters' size, px). */
internal fun Flight.bubbleAt(coords: LayoutCoordinates, host: Host, pad: Offset, line: Float, size: Float) {
    bubble = coords
    this.pad = pad
    inBubble = pad + Offset(0f, (line - size) / 2)
    toSize = size
    if (rise == null) host.overlay?.takeIf { it.isAttached }?.let { rise = from.y - (it.localPositionOf(coords, Offset.Zero) + inBubble).y }
}

/** The page: a new chat, or a chat (the one it became), above; the composer at its foot; what flies, over both. */
@Composable
fun ChatHost(current: WorkspaceEntry, screen: Screen) {
    val host = remember { Host() }
    host.still = reducedMotion()
    host.density = LocalDensity.current
    val chat = screen as? Screen.Chat
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
        if (chat != null) key(chat.id) { ChatScreen(chat.station, chat.of, host) }
        // A new chat's scene stays over its chat while it leaves.
        if (chat == null || host.leaving) key("new") { NewChatScreen(current, host, leaving = chat != null) }
        HostComposer(host, Modifier.align(Alignment.BottomCenter))
        FlightLayer(host)
    }
    LaunchedEffect(host.leaving) {
        if (!host.leaving) return@LaunchedEffect
        host.leave.snapTo(0f)
        host.leave.animateTo(SCENE_LEAVE_MS.toFloat(), tween(SCENE_LEAVE_MS, easing = LinearEasing))
        host.leaving = false
    }
}

/** How long a new chat's scene takes to leave (web madeChat.css.ts: up 140 ms; its choices fade in 80). */
internal const val SCENE_LEAVE_MS = 140

@Composable
private fun HostComposer(host: Host, modifier: Modifier) {
    val spec = host.spec ?: return
    val draft = spec.draft
    val morph = rememberMorph()
    host.morph = morph
    // Back once the words are out of the composer, eased (going is at once).
    val hint = remember { Animatable(1f) }
    LaunchedEffect(host.hintAway) { if (host.hintAway) hint.snapTo(0f) else hint.animateTo(1f, tween(200, easing = Ease.Arrive)) }
    Column(modifier.fillMaxWidth()) {
        ChatRefMenu(draft, spec.station, spec.here, host.haze, Modifier.padding(horizontal = 10.dp))
        // A capsule floating over the page, which runs on around it.
        Box(Modifier.fillMaxWidth().onSizeChanged { host.composerHeight = it.height }.padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp)) {
            Column(
                Modifier.fillMaxWidth().onGloballyPositioned { host.capsule = it }.floating(host.haze, RoundedCornerShape(ComposerCorner))
                    // A tap on the capsule's own room is a tap on the field.
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { draft.focus++ }
                    .padding(ComposerInset).morph(morph)
                    // Held taller than what it holds (words just sent leaving it): that at its foot, as it was.
                    .layout { m, c ->
                        val p = m.measure(c)
                        host.contentHeight = p.height
                        val h = maxOf(p.height, host.hold ?: 0)
                        layout(p.width, h) { p.place(0, h - p.height) }
                    },
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                spec.notices(this)
                DraftExtras(draft)
                ComposerBar(
                    draft, spec.placeholder, onPlus = spec.onPlus, onType = spec.onType, onSend = spec.onSend,
                    hint = { if (host.hintAway) 0f else hint.value }, morph = morph, onField = { host.field = it }, onFieldText = { host.fieldText = it },
                )
                draft.error?.let { Text(it, fontSize = 12.sp, color = C.red, modifier = Modifier.padding(horizontal = 6.dp)) }
            }
        }
    }
}

/** Over the composer: the words sent, where they wait, then their row on its way to its place. */
@Composable
private fun FlightLayer(host: Host) {
    host.layer = rememberGraphicsLayer()
    val f = host.flight
    val density = LocalDensity.current
    Box(Modifier.fillMaxSize().onGloballyPositioned { host.overlay = it }.drawWithContent {
        drawContent()
        val flight = host.flight ?: return@drawWithContent
        // Drawn anew each step of the way and as its row comes (read before anything that returns early).
        flight.progress.value
        flight.placed
        val row = flight.row?.takeIf { it.isAttached }
        val bubble = flight.bubble?.takeIf { it.isAttached }
        val overlay = host.overlay?.takeIf { it.isAttached }
        val layer = host.layer
        if (row == null || bubble == null || overlay == null || layer == null) {
            // Until their row is drawn in the list, the words stay as they were typed, as the field showed them
            // (scrolled to its last lines when there were more than it holds); they go in the frame it is.
            val typed = flight.typed ?: return@drawWithContent
            val at = flight.field
            clipRect(at.x, at.y, at.x + flight.fieldWidth, at.y + flight.fieldHeight) { drawText(typed, topLeft = at - Offset(0f, flight.scroll)) }
            return@drawWithContent
        }
        val across = flight.across()
        val up = flight.up()
        val settle = flight.settle()
        // Where its letters are now (the list carrying them, a new chat's), and where they would be in place (the
        // composer down: in an open chat it still holds the list up as they go).
        val now = overlay.localPositionOf(bubble, Offset.Zero) + flight.inBubble
        val drop = if (flight.carried) 0f else flight.toFinal ?: host.drop()
        val place = now - Offset(0f, flight.shift() - drop)
        // Followed, not jumped to: the list going to its end and the composer coming down move it by fits and starts.
        val to = if (flight.carried) place else flight.follow(place) + (place - flight.follow(place)) * settle
        val off = to - place
        val at = Offset(flight.from.x + (to.x - flight.from.x) * across, flight.from.y + (to.y - flight.from.y) * up)
        val k = flight.fromSize / flight.toSize
        // At the size typed until they settle (a new chat's: on the way).
        val s = k + (1f - k) * (if (flight.carried) up else settle)
        val inRow = now - overlay.localPositionOf(row, Offset.Zero)
        val words = flight.words
        val pieces = flight.pieces()
        // Where the bubble's words are once in place.
        val home = overlay.localPositionOf(bubble, Offset.Zero) + flight.pad - Offset(0f, flight.shift() - drop) + off
        // In an open chat the words go as one block, as typed, its first letters (the first that showed) to theirs,
        // seen through the field as it showed them (more than six lines: only those it showed). Come, that window
        // opens out to the whole row as they settle into their bubble.
        val lead = pieces?.let { ps -> ps.firstOrNull { it.shown } ?: ps.firstOrNull() }
        val window = if (flight.carried || lead == null) null else {
            val gone = home + lead.at - (flight.field + lead.from)
            val d = Offset(gone.x * across, gone.y * up)
            val r = overlay.localPositionOf(row, Offset.Zero) - Offset(0f, flight.shift() - drop) + off
            val left = flight.field.x + d.x
            val top = flight.field.y + d.y
            androidx.compose.ui.geometry.Rect(
                left + (r.x - left) * settle, top + (r.y - top) * settle,
                left + flight.fieldWidth + (r.x + row.size.width - left - flight.fieldWidth) * settle,
                top + flight.fieldHeight + (r.y + row.size.height - top - flight.fieldHeight) * settle,
            )
        }
        val view = window ?: androidx.compose.ui.geometry.Rect(-1e5f, -1e5f, 1e5f, 1e5f)
        clipRect(view.left, view.top, view.right, view.bottom) {
            // The row (its words, when they fly apart, drawn by the pieces below and not in it).
            translate(at.x, at.y) {
                scale(s, s, pivot = Offset.Zero) {
                    translate(-inRow.x, -inRow.y) { drawLayer(layer) }
                }
            }
            if (words != null && pieces != null && lead != null) for (p in pieces) {
                // From where the field had it to where the bubble has it.
                val a = flight.field + p.from
                val b = home + p.at
                val there = if (flight.carried) Offset(a.x + (b.x - a.x) * across, a.y + (b.y - a.y) * up) else {
                    val block = home + lead.at + (p.from - lead.from)
                    val m = Offset(a.x + (block.x - a.x) * across, a.y + (block.y - a.y) * up)
                    m + (b - m) * settle
                }
                translate(there.x, there.y) {
                    scale(s, s, pivot = Offset.Zero) {
                        translate(-p.at.x, -p.at.y) {
                            clipRect(p.clip.left, p.clip.top, p.clip.right, p.clip.bottom) {
                                drawText(words, alpha = if (p.shown || !flight.carried) 1f else across)
                            }
                        }
                    }
                }
            }
        }
        // Out of the composer (its top edge as it is now, changing shape as they go): its hint comes back.
        val top = host.capsule?.takeIf { it.isAttached }?.let { overlay.localPositionOf(it, Offset.Zero).y } ?: flight.top
        if (host.hintAway && at.y + (row.size.height - inRow.y) * s <= top) host.hintAway = false
    }) {
        // The words as typed with no layout of the field's to draw them by (see above).
        if (f != null && f.typed == null) Box(
            Modifier.offset { IntOffset(f.field.x.roundToInt(), f.field.y.roundToInt()) }
                .size(with(density) { f.fieldWidth.toDp() }, with(density) { f.fieldHeight.toDp() }).clipToBounds()
                .graphicsLayer { alpha = if (f.placed) 0f else 1f },
        ) {
            // As the field showed them: scrolled to its last lines when there were more than it holds.
            Text(
                f.text, style = TextStyle(color = C.ink, fontSize = 16.sp, lineHeight = 21.sp),
                modifier = Modifier.wrapContentHeight(Alignment.Top, unbounded = true).offset { IntOffset(0, -f.scroll.roundToInt()) },
            )
        }
    }
    LaunchedEffect(f) {
        if (f == null) return@LaunchedEffect
        // The row never came (the message could not be sent): the composer is as it was.
        delay(2000)
        if (!f.placed) host.notSent()
    }
    val bound = f?.key
    LaunchedEffect(f, bound) {
        if (f == null || bound == null) return@LaunchedEffect
        // Not while its row is only composed ahead, out of sight: once the list shows it.
        snapshotFlow { f.placed }.first { it }
        // A new chat's: once its choices have faded (web: 90 ms after what leaves has begun to).
        // The composer comes down once they are half way.
        if (!f.carried) launch { snapshotFlow { f.progress.value }.first { it >= FLY / 2 }; if (host.flight === f) host.hold = null }
        f.progress.animateTo(1f, tween(if (f.carried) ARRIVE_MS else FLIGHT_MS, delayMillis = if (f.carried) 90 else 0, easing = LinearEasing))
        host.landed(f)
    }
}

/** How long a new chat's first words take to their place (web madeChat.ts: 480 ms, Ease.Arrive). */
internal const val ARRIVE_MS = 480
/**
 * How long words sent in an open chat take to their row: flying as typed for the first FLY of it (460 ms), there a
 * moment as they are (100 ms: seen to have come), then settling in their bubble from SETTLE on (240 ms).
 */
internal const val FLIGHT_MS = 800
internal const val FLY = 0.575f
internal const val SETTLE = 0.7f
