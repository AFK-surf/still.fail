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
// at once. Both now share the field's typography and wrapping width. A new
// chat's scene leaves first (up out of view, its choices fading where they are), and the chat's list comes up after the
// words, out of the composer's top edge. Nothing is crossfaded over anything. The files sent with them go the same way,
// each from its tile in the composer to its place in the message (a picture's crop opening out to its own proportions);
// files sent with no words fly on their own, their row coming in where it is.
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
import fail.still.android.ui.keyboard
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
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
import androidx.compose.ui.graphics.isSpecified
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.GraphicsContext
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.platform.LocalGraphicsContext
import androidx.compose.runtime.DisposableEffect
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
import fail.still.android.ui.floatingStill
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
    /** The files sent with them, from their tiles in the composer. */
    internal val files: List<FlyingFile> = emptyList(),
) {
    /** How far the field had scrolled its words: to their end (the caret's, as it sends), when they are taller than it. */
    internal val scroll: Float = ((typed?.size?.height ?: 0) - fieldHeight).coerceAtLeast(0).toFloat()
    /** Its row is laid out in the list (not only composed ahead, out of sight): they go from then on. */
    internal var placed by mutableStateOf(false)
    /** The real list has completed its final layout; only transforms animate after this. */
    internal var ready by mutableStateOf(false)
    internal var beforePositions: Map<String, Float> = emptyMap()
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
     * In an open chat the words start as typed, then unfold into their bubble during the flight.
     * Its ground and time come in with the unfolding, without a pause at the destination.
     */
    private fun fly(): Float = (progress.value / FLY).coerceAtMost(1f)
    fun settle(): Float = if (carried) e() else Ease.Arrive.transform(((progress.value - SETTLE) / (1f - SETTLE)).coerceIn(0f, 1f))
    /** How much of the bubble's ground shows (around the words, drawn by the host in an open chat): coming in from half way, all there as they come. */
    fun ground(): Float = if (carried) e() else ((progress.value - SETTLE) / (FLY - SETTLE)).coerceIn(0f, 1f)
    /** The bubble's ground, as its row draws it. */
    internal var groundColor = androidx.compose.ui.graphics.Color.Unspecified
    /** Where the list is drawn now, off its place. */
    fun shift(): Float = if (carried) (rise ?: 0f) * (1f - e()) else 0f

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

/**
 * A file sent with the words (`path`, the station's): `from`, its tile in the composer (in the host), drawn as `tile`
 * until its place in the message is laid out (`to`, drawn there into `layer` instead of in the row).
 */
internal class FlyingFile(val path: String, val from: Rect, val tile: GraphicsLayer) {
    var to: LayoutCoordinates? = null
    var layer: GraphicsLayer? = null
}

/** A file's tile in the composer: where it is and how it is drawn (`taken` by a flight, which lets its layer go). */
internal class Tile(val layer: GraphicsLayer) {
    var at: LayoutCoordinates? = null
    var taken = false
}

/** The page's composer and what moves around it. */
@Stable
class Host {
    val haze = HazeState()
    var spec by mutableStateOf<ComposerSpec?>(null)
    /** The composer's room at the foot, with its margins (what the page above keeps clear of), in px. */
    var composerHeight by mutableIntStateOf(0)
    /** Measured from the composer's final content, independent of its visual height animation. */
    internal var naturalHeight by mutableIntStateOf(0)
    fun roomForList(): Int {
        val shown = if (flight?.carried == false && naturalHeight > 0) naturalHeight else composerHeight
        // One text line, its padding, toolbar and margins: focusing uses space already kept by the list.
        val reserved = density?.run {
            maxOf(36.dp.roundToPx(), SendTextStyle.lineHeight.roundToPx() + 14.dp.roundToPx()) +
                (ComposerInset * 2 + 18.dp + 4.dp + 36.dp).roundToPx()
        } ?: 0
        return maxOf(shown, reserved)
    }
    internal val rowPositions = mutableMapOf<String, Float>()
    internal var prepareFlight: (suspend (Flight) -> Unit)? = null
    internal var field: LayoutCoordinates? = null
    internal var fieldText: TextLayoutResult? = null
    internal var fieldWidth by mutableIntStateOf(0)
    internal var capsule: LayoutCoordinates? = null
    internal var overlay: LayoutCoordinates? = null
    internal var layer: GraphicsLayer? = null
    internal var graphics: GraphicsContext? = null
    /** The composer's file tiles, by the draft's id for each. */
    internal val tiles = mutableMapOf<Long, Tile>()
    /** Shows the chat's message `seq` (in the list, at its top, flashing), if it is loaded: set by the list. */
    internal var showSaid: ((Long) -> Unit)? = null
    /** A message (seq) to show once the chat's list is in place (Screen.Chat.at), the pages before it brought in. */
    internal var goTo: Long? = null
    /** The words to mark in that message (opened from a search, Search.kt), instead of flashing it. */
    internal var goToWords: List<String> = emptyList()
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
     * comes into it is what was just sent from here). `files`, the draft's as it is sent: those up go from their tiles.
     */
    fun sending(text: String, carried: Boolean, files: List<Pending> = emptyList(), before: Set<String> = rows) {
        sends++
        let(flight)
        flight = null
        hold = null
        val field = field?.takeIf { it.isAttached }
        val overlay = overlay?.takeIf { it.isAttached }
        val capsule = capsule?.takeIf { it.isAttached }
        if (still || field == null || overlay == null || capsule == null) return
        val taken = files.mapNotNull { p ->
            val path = p.done?.path ?: return@mapNotNull null
            val tile = tiles[p.id] ?: return@mapNotNull null
            val at = tile.at?.takeIf { it.isAttached } ?: return@mapNotNull null
            tile to FlyingFile(path, overlay.localBoundingBoxOf(at, clipBounds = false), tile.layer)
        }
        if (text.isEmpty() && taken.isEmpty()) return
        taken.forEach { (tile, _) -> tile.taken = true }
        val at = overlay.localPositionOf(field, Offset.Zero)
        val d = density ?: return
        // The field and bubble share the same line metrics.
        val from = at + Offset(0f, with(d) { (SendTextStyle.lineHeight.toPx() - SendTextStyle.fontSize.toPx()) / 2 })
        val typed = fieldText
        if (!carried) hold = contentHeight
        flight = Flight(
            text, from, with(d) { SendTextStyle.fontSize.toPx() }, at, field.size.width, field.size.height, overlay.localPositionOf(capsule, Offset.Zero).y,
            carried, before, typed, typed?.layoutInput?.text?.text?.indexOf(text) ?: -1, taken.map { it.second },
        )
        flight?.beforePositions = rowPositions.toMap()
        // Only words pass over the hint; files alone leave it where it is.
        hintAway = text.isNotEmpty()
    }

    /** What was sent did not go (or its row never came): the composer is as it was. */
    fun notSent() {
        if (flight?.placed != true) { let(flight); flight = null; hintAway = false; hold = null }
    }

    /** A flight over: the tiles it took from the composer are drawn no more. */
    private fun let(f: Flight?) { f?.files?.forEach { graphics?.releaseGraphicsLayer(it.tile) } }

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

    internal fun landed(f: Flight) { if (flight === f) { let(f); flight = null; hintAway = false; hold = null } }
    internal var density: androidx.compose.ui.unit.Density? = null
}

/** The flight a row's content is drawn for (its bubble says where its letters are; its ground and time come in with it). */
val LocalFlight = staticCompositionLocalOf<Flight?> { null }
val LocalFlightHost = staticCompositionLocalOf<Host?> { null }

/** A row the words fly into: drawn by the host over the composer, from where they were to here, instead of in the list. */
fun Modifier.flying(host: Host, f: Flight?): Modifier = if (f == null) this else this
    .onGloballyPositioned { f.row = it; f.placed = true }
    .drawWithContent {
        // Landed: here again, in the frame the host stops drawing it (not the next, once the list has let it go).
        val layer = host.layer
        if (host.flight === f && layer != null) layer.record { this@drawWithContent.drawContent() } else drawContent()
    }

/** A file's tile in the composer, kept drawn (and where) for the flight that may take it from there. */
@Composable
internal fun Modifier.sendTile(host: Host?, id: Long): Modifier {
    if (host == null) return this
    val graphics = LocalGraphicsContext.current
    val tile = remember(id) { Tile(graphics.createGraphicsLayer()).also { host.tiles[id] = it } }
    DisposableEffect(id) {
        onDispose {
            if (host.tiles[id] === tile) host.tiles.remove(id)
            if (!tile.taken) graphics.releaseGraphicsLayer(tile.layer)
        }
    }
    return onGloballyPositioned { tile.at = it }.drawWithContent {
        tile.layer.record { this@drawWithContent.drawContent() }
        drawLayer(tile.layer)
    }
}

/** A file in a message flown into: drawn by the host from its tile in the composer to here, instead of here. */
@Composable
internal fun Modifier.landingFile(path: String): Modifier {
    val f = LocalFlight.current
    val host = LocalFlightHost.current
    val file = f?.files?.firstOrNull { it.path == path }
    val layer = rememberGraphicsLayer()
    if (f == null || host == null || file == null) return this
    file.layer = layer
    return onGloballyPositioned {
        file.to = it
        // Sent with no words: the list rises (a new chat's) from where the first file was.
        if (f.text.isEmpty() && f.rise == null) host.overlay?.takeIf { o -> o.isAttached }?.let { o -> f.rise = file.from.top - o.localPositionOf(it, Offset.Zero).y }
    }.drawWithContent { if (host.flight === f) layer.record { this@drawWithContent.drawContent() } else drawContent() }
}

/** Existing rows also use FLIP: lay out once at their destination, undo that displacement in drawing. */
@Composable
internal fun Modifier.sendReflow(host: Host, id: String): Modifier {
    var laidOutY by remember(id) { mutableStateOf<Float?>(null) }
    return onGloballyPositioned { laidOutY = host.overlayY(it) }.drawWithContent {
        val f = host.flight
        val from = f?.beforePositions?.get(id)
        val to = laidOutY
        val shift = if (f != null && !f.carried && from != null && to != null) (from - to) * (1f - f.up()) else 0f
        if (to != null) host.rowPositions[id] = to + shift
        // A draw transform cannot feed back into the layout coordinates used to calculate it.
        translate(top = shift) { this@drawWithContent.drawContent() }
    }
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
    host.graphics = LocalGraphicsContext.current
    val chat = screen as? Screen.Chat
    // Where to go, once each time the chat or its place changes (not on every recomposition: the page clears it once there).
    remember(chat?.id, chat?.at, chat?.words) { host.goTo = chat?.at; host.goToWords = chat?.words.orEmpty(); chat?.at }
    CompositionLocalProvider(LocalSendTextWidth provides host.fieldWidth) {
      Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars))) {
        if (chat != null) key(chat.id) { ChatScreen(chat.station, chat.of, host) }
        // A new chat's scene stays over its chat while it leaves.
        if (chat == null || host.leaving) key("new") { NewChatScreen(current, host, leaving = chat != null) }
        HostComposer(host, Modifier.align(Alignment.BottomCenter))
        FlightLayer(host)
      }
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
internal fun HostComposer(host: Host, modifier: Modifier, overContent: Boolean = true) {
    val spec = host.spec ?: return
    val draft = spec.draft
    val density = LocalDensity.current
    val composerChrome = with(density) { (ComposerInset * 2 + 18.dp).roundToPx() }
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
                Modifier.fillMaxWidth().onGloballyPositioned { host.capsule = it }
                    .then(if (overContent) Modifier.floating(host.haze, RoundedCornerShape(ComposerCorner)) else Modifier.floatingStill(RoundedCornerShape(ComposerCorner)))
                    // A tap on the capsule's own room is a tap on the field.
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { draft.focus++ }
                    .padding(ComposerInset).morph(morph)
                    // Held taller than what it holds (words just sent leaving it): that at its foot, as it was.
                    .layout { m, c ->
                        val p = m.measure(c)
                        // Own bubbles always wrap at the expanded field width, so focusing cannot reflow the history.
                        host.fieldWidth = (p.width - with(density) { 28.dp.roundToPx() }).coerceAtLeast(0)
                        host.contentHeight = p.height
                        host.naturalHeight = p.height + composerChrome
                        val h = maxOf(p.height, host.hold ?: 0)
                        layout(p.width, h) { p.place(0, h - p.height) }
                    },
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                spec.notices(this)
                DraftExtras(draft, host)
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
        val wordless = flight.text.isEmpty()
        if ((!flight.carried && !flight.ready) || row == null || (bubble == null && !wordless) || overlay == null || layer == null) {
            // Until their row is drawn in the list, the words stay as they were typed, as the field showed them
            // (scrolled to its last lines when there were more than it holds), and the files as their tiles were; they
            // go in the frame it is.
            for (ff in flight.files) translate(ff.from.left, ff.from.top) { drawLayer(ff.tile) }
            val typed = flight.typed?.takeIf { !wordless } ?: return@drawWithContent
            val at = flight.field
            clipRect(at.x, at.y, at.x + flight.fieldWidth, at.y + flight.fieldHeight) { drawText(typed, topLeft = at - Offset(0f, flight.scroll)) }
            return@drawWithContent
        }
        if (wordless || bubble == null) {
            // Files alone: the row comes in where it is (its time with it), the files flying into it.
            val r = overlay.localPositionOf(row, Offset.Zero) - Offset(0f, flight.shift())
            translate(r.x, r.y) { drawLayer(layer) }
            files(flight, overlay)
            return@drawWithContent
        }
        val across = flight.across()
        val up = flight.up()
        val settle = flight.settle()
        // The destination is the real bubble's laid-out position. No predicted foot, scroll delta or follower.
        val now = overlay.localPositionOf(bubble, Offset.Zero) + flight.inBubble
        val to = now - Offset(0f, flight.shift())
        val at = Offset(flight.from.x + (to.x - flight.from.x) * across, flight.from.y + (to.y - flight.from.y) * up)
        val k = flight.fromSize / flight.toSize
        // At the size typed until they settle (a new chat's: on the way).
        val s = k + (1f - k) * (if (flight.carried) up else settle)
        val inRow = now - overlay.localPositionOf(row, Offset.Zero)
        val words = flight.words
        val pieces = flight.pieces()
        // Where the bubble's words are once in place.
        val home = overlay.localPositionOf(bubble, Offset.Zero) + flight.pad - Offset(0f, flight.shift())
        // In an open chat the words go as one block, as typed, its first letters (the first that showed) to theirs,
        // only those the field showed (more than six lines: the rest come in as they settle), their bubble's ground
        // coming in round them from half way; come, it opens out to the whole bubble as they settle into it.
        val lead = pieces?.let { ps -> ps.firstOrNull { it.shown } ?: ps.firstOrNull() }
        val spots = if (pieces == null || lead == null) null else pieces.map { p ->
            // From where the field had it to where the bubble has it.
            val a = flight.field + p.from
            val b = home + p.at
            if (flight.carried) Offset(a.x + (b.x - a.x) * across, a.y + (b.y - a.y) * up) else {
                val block = home + lead.at + (p.from - lead.from)
                val m = Offset(a.x + (block.x - a.x) * across, a.y + (block.y - a.y) * up)
                m + (b - m) * settle
            }
        }
        val ground = if (flight.carried || pieces == null || spots == null || lead == null) null else {
            val shown = pieces.indices.filter { pieces[it].shown }.ifEmpty { pieces.indices.toList() }
            fun topOf(i: Int) = spots[i].y + (pieces[i].clip.top - pieces[i].at.y) * s
            fun footOf(i: Int) = spots[i].y + (pieces[i].clip.bottom - pieces[i].at.y) * s
            val seen = shown.minOf(::topOf)
            val top = seen + (pieces.indices.minOf(::topOf) - seen) * settle - flight.pad.y
            val bottom = shown.maxOf(::footOf) + flight.pad.y
            val left = home.x - flight.pad.x + (spots[pieces.indexOf(lead)].x - (home + lead.at).x)
            androidx.compose.ui.geometry.Rect(left, top, left + bubble.size.width, bottom)
        }
        // What shows: the bubble (what the field did not show is not there yet), then the row as it is (its time).
        val view = ground?.let { g ->
            val r = overlay.localPositionOf(row, Offset.Zero) - Offset(0f, flight.shift())
            androidx.compose.ui.geometry.Rect(-1e5f, g.top, 1e5f, g.bottom + (r.y + row.size.height - g.bottom).coerceAtLeast(0f) * settle)
        } ?: androidx.compose.ui.geometry.Rect(-1e5f, -1e5f, 1e5f, 1e5f)
        // Under the words: where they cross on the way, the words stay readable.
        files(flight, overlay)
        clipRect(view.left, view.top, view.right, view.bottom) {
            // The row (its words, when they fly apart, drawn by the pieces below and not in it; and its ground, above).
            translate(at.x, at.y) {
                scale(s, s, pivot = Offset.Zero) {
                    translate(-inRow.x, -inRow.y) { drawLayer(layer) }
                }
            }
            if (ground != null && flight.groundColor.isSpecified) {
                val corner = 18.dp.toPx()
                drawRoundRect(flight.groundColor, ground.topLeft, ground.size, androidx.compose.ui.geometry.CornerRadius(corner), alpha = flight.ground())
            }
            if (words != null && pieces != null && spots != null) for ((i, p) in pieces.withIndex()) {
                val there = spots[i]
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
                f.text, style = SendTextStyle.copy(color = C.ink),
                modifier = Modifier.wrapContentHeight(Alignment.Top, unbounded = true).offset { IntOffset(0, -f.scroll.roundToInt()) },
            )
        }
    }
    LaunchedEffect(f) {
        if (f == null) return@LaunchedEffect
        // The row never came into sight: the composer is as it was. Not a wait for the station: a flight only starts for a
        // row the core makes here at once (Composer.kt's onSend), and a refused send gives the words back by itself.
        delay(2000)
        if (!f.placed) host.notSent()
    }
    val bound = f?.key
    LaunchedEffect(f, bound) {
        if (f == null || bound == null) return@LaunchedEffect
        // Not while its row is only composed ahead, out of sight: once the list shows it.
        snapshotFlow { f.placed }.first { it }
        if (!f.carried) { host.prepareFlight?.invoke(f); f.ready = true }
        // A new chat's: once its choices have faded (web: 90 ms after what leaves has begun to).
        // The composer comes down once they are half way.
        if (!f.carried) launch { snapshotFlow { f.progress.value }.first { it >= SETTLE }; if (host.flight === f) host.hold = null }
        f.progress.animateTo(1f, tween(if (f.carried) ARRIVE_MS else FLIGHT_MS, delayMillis = if (f.carried) 90 else 0, easing = LinearEasing))
        host.landed(f)
    }
}

/**
 * The files of a flight, each from its tile in the composer to its place in the message: across and up as the words go
 * (on a curve in an open chat), its box growing from the tile's to its own, what is in it cropped to the box as it is
 * (a picture opening out from the tile's square crop), corners from the composer's to its own.
 */
private fun DrawScope.files(flight: Flight, overlay: LayoutCoordinates) {
    if (flight.files.isEmpty()) return
    val across = flight.across()
    val up = flight.up()
    val fromCorner = (ComposerCorner - ComposerInset).toPx()
    val toCorner = 10.dp.toPx()
    for (ff in flight.files) {
        val to = ff.to?.takeIf { it.isAttached }
        val drawn = ff.layer?.takeIf { !it.isReleased }
        if (to == null || drawn == null || to.size.width == 0 || to.size.height == 0) {
            translate(ff.from.left, ff.from.top) { drawLayer(ff.tile) }
            continue
        }
        val end = overlay.localBoundingBoxOf(to, clipBounds = false).translate(0f, -flight.shift())
        val a = ff.from
        val left = a.left + (end.left - a.left) * across
        val top = a.top + (end.top - a.top) * up
        val w = a.width + (end.width - a.width) * up
        val h = a.height + (end.height - a.height) * up
        val c = maxOf(w / end.width, h / end.height)
        val corner = fromCorner + (toCorner - fromCorner) * up
        val box = Path().apply { addRoundRect(RoundRect(left, top, left + w, top + h, CornerRadius(corner))) }
        clipPath(box) {
            translate(left + (w - end.width * c) / 2, top + (h - end.height * c) / 2) {
                scale(c, c, pivot = Offset.Zero) { drawLayer(drawn) }
            }
        }
    }
}

/** How long a new chat's first words take to their place (web madeChat.ts: 480 ms, Ease.Arrive). */
internal const val ARRIVE_MS = 480
/**
 * One continuous motion: start unfolding 144 ms into the 480 ms flight, then finish opening by 600 ms.
 * There is no pause at the destination; the composer starts closing as the bubble opens.
 */
internal const val FLIGHT_MS = 600
internal const val FLY = 0.8f
internal const val SETTLE = 0.24f
