// A new chat and a chat are one page (web mobile/ChatHost.tsx): what is above changes (a new chat's scene, then the chat
// it made), the composer at its foot is one, kept, with what is typed and the focus, as a new chat becomes its chat. What
// the composer writes to is the page's: it says so (`Host.spec`), and the composer asks it when a message goes.
//
// What is sent is drawn where it arrives and moved from where it comes from (web madeChat.ts), the same in a new chat and
// in a chat: its words stay where they were typed until its row is in the list, then that row (the real one, whatever it
// becomes: outbox, then the chat's message) is drawn over the composer from the words' place and size to its own, its
// bubble and time coming in around it; the composer's hint comes back once the words have left the composer. A new
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
import androidx.compose.ui.layout.LayoutCoordinates
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
class Flight internal constructor(val text: String, val from: Offset, val fromSize: Float, val field: Offset, val fieldWidth: Int, val top: Float, val carried: Boolean, internal val before: Set<String>) {
    /** The row the words went into (its key in the list), once it is there. */
    var key by mutableStateOf<String?>(null)
        internal set
    internal var row: LayoutCoordinates? = null
    internal var bubble: LayoutCoordinates? = null
    /** Where the bubble's letters start in it, and their size. */
    internal var inBubble = Offset.Zero
    internal var toSize = 1f
    /** How far above its place the list starts (a new chat's: the words' way up), once the row is laid out. */
    internal var rise: Float? = null
    internal val progress = Animatable(0f)
    /**
     * How far it has come (eased): across, and up. In an open chat across first and up a little after, so the words
     * rise on a curve (web madeChat.ts flight()); a new chat's first words both at once.
     */
    fun e(): Float = if (carried) Ease.Arrive.transform(progress.value) else Ease.Flight.transform((progress.value / 0.88f).coerceAtMost(1f))
    fun up(): Float = if (carried) e() else Ease.Flight.transform(((progress.value - 0.12f) / 0.88f).coerceAtLeast(0f))
    /** Where the list is drawn now, off its place. */
    fun shift(): Float = if (carried) (rise ?: 0f) * (1f - e()) else 0f
}

/** The page's composer and what moves around it. */
@Stable
class Host {
    val haze = HazeState()
    var spec by mutableStateOf<ComposerSpec?>(null)
    /** The composer's room at the foot, with its margins (what the page above keeps clear of), in px. */
    var composerHeight by mutableIntStateOf(0)
    internal var field: LayoutCoordinates? = null
    internal var capsule: LayoutCoordinates? = null
    internal var overlay: LayoutCoordinates? = null
    internal var layer: GraphicsLayer? = null
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

    /**
     * `text` is sent from the composer (before the draft is emptied): its words stay where they are until their row is in
     * the list, the first outgoing one not among `before` (the outbox's as it was sent: it is this device's own, so what
     * comes into it is what was just sent from here).
     */
    fun sending(text: String, carried: Boolean, before: Set<String> = rows) {
        flight = null
        val field = field?.takeIf { it.isAttached }
        val overlay = overlay?.takeIf { it.isAttached }
        val capsule = capsule?.takeIf { it.isAttached }
        if (still || text.isEmpty() || field == null || overlay == null || capsule == null) return
        val at = overlay.localPositionOf(field, Offset.Zero)
        val d = density ?: return
        // The field's letters sit in its 21sp line as the bubble's in its 23sp one: centred.
        val from = at + Offset(0f, with(d) { (21.sp.toPx() - 16.sp.toPx()) / 2 })
        flight = Flight(text, from, with(d) { 16.sp.toPx() }, at, field.size.width, overlay.localPositionOf(capsule, Offset.Zero).y, carried, before)
        hintAway = true
    }

    /** What was sent did not go (or its row never came): the composer is as it was. */
    fun notSent() {
        if (flight?.key == null) { flight = null; hintAway = false }
    }

    /** A new chat becomes its chat: its scene leaves. */
    fun madeChat() { leaving = true }

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

    internal fun landed(f: Flight) { if (flight === f) { flight = null; hintAway = false } }
    internal var density: androidx.compose.ui.unit.Density? = null
}

/** The flight a row's content is drawn for (its bubble says where its letters are; its ground and time come in with it). */
val LocalFlight = staticCompositionLocalOf<Flight?> { null }
val LocalFlightHost = staticCompositionLocalOf<Host?> { null }

/** A row the words fly into: drawn by the host over the composer, from where they were to here, instead of in the list. */
fun Modifier.flying(host: Host, f: Flight?): Modifier = if (f == null) this else this
    .onGloballyPositioned { f.row = it }
    .drawWithContent {
        // Landed: here again, in the frame the host stops drawing it (not the next, once the list has let it go).
        val layer = host.layer
        if (host.flight === f && layer != null) layer.record { this@drawWithContent.drawContent() } else drawContent()
    }

/** The bubble of a row flown into: where its letters start (`pad`: its padding; `line`, `size`: its line height and letters' size, px). */
internal fun Flight.bubbleAt(coords: LayoutCoordinates, host: Host, pad: Offset, line: Float, size: Float) {
    bubble = coords
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
                    .padding(ComposerInset).morph(morph),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                spec.notices(this)
                DraftExtras(draft)
                ComposerBar(
                    draft, spec.placeholder, onPlus = spec.onPlus, onType = spec.onType, onSend = spec.onSend,
                    hint = { if (host.hintAway) 0f else hint.value }, morph = morph, onField = { host.field = it },
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
        val row = flight.row?.takeIf { it.isAttached } ?: return@drawWithContent
        val bubble = flight.bubble?.takeIf { it.isAttached } ?: return@drawWithContent
        val overlay = host.overlay?.takeIf { it.isAttached } ?: return@drawWithContent
        val layer = host.layer ?: return@drawWithContent
        val e = flight.e()
        val up = flight.up()
        // Where its letters are now (the list carrying them, a new chat's), and where they would be in place.
        val now = overlay.localPositionOf(bubble, Offset.Zero) + flight.inBubble
        val to = now - Offset(0f, flight.shift())
        val at = Offset(flight.from.x + (to.x - flight.from.x) * e, flight.from.y + (to.y - flight.from.y) * up)
        val s = flight.fromSize / flight.toSize + (1f - flight.fromSize / flight.toSize) * up
        val inRow = now - overlay.localPositionOf(row, Offset.Zero)
        translate(at.x, at.y) {
            scale(s, s, pivot = Offset.Zero) {
                translate(-inRow.x, -inRow.y) { drawLayer(layer) }
            }
        }
        // Out of the composer (its top edge as it is now, changing shape as they go): its hint comes back.
        val top = host.capsule?.takeIf { it.isAttached }?.let { overlay.localPositionOf(it, Offset.Zero).y } ?: flight.top
        if (host.hintAway && at.y + (row.size.height - inRow.y) * s <= top) host.hintAway = false
    }) {
        // Until their row is in the list, the words stay as they were typed (the row is found as the list is laid out:
        // they go in the frame it is drawn, not the next).
        if (f != null) Text(
            f.text, style = TextStyle(color = C.ink, fontSize = 16.sp, lineHeight = 21.sp), maxLines = 6,
            modifier = Modifier.offset { IntOffset(f.field.x.roundToInt(), f.field.y.roundToInt()) }.width(with(density) { f.fieldWidth.toDp() })
                .graphicsLayer { alpha = if (f.key == null) 1f else 0f },
        )
    }
    LaunchedEffect(f) {
        if (f == null) return@LaunchedEffect
        // The row never came (the message could not be sent): the composer is as it was.
        delay(2000)
        if (f.key == null) host.notSent()
    }
    val bound = f?.key
    LaunchedEffect(f, bound) {
        if (f == null || bound == null) return@LaunchedEffect
        // A new chat's: once its choices have faded (web: 90 ms after what leaves has begun to).
        f.progress.animateTo(1f, tween(if (f.carried) ARRIVE_MS else FLIGHT_MS, delayMillis = if (f.carried) 90 else 0, easing = LinearEasing))
        host.landed(f)
    }
}

/** How long a new chat's first words take to their place (web madeChat.ts: 480 ms, Ease.Arrive). */
internal const val ARRIVE_MS = 480
/** How long words sent in an open chat take to their row (web madeChat.ts ARRIVE). */
internal const val FLIGHT_MS = 520
