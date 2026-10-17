// A station's screen, full screen (docs/remote-screens.md): the frame fitted whole (letterboxed), zoomed in place with
// two fingers; while driving it, a tap clicks, a long press right-clicks, a drag drags, two fingers moving together
// scroll, and the keyboard types into it. Upright, the bar is above the frame (close, the title and who is on it,
// 只看/控制, sending a file, pasting, the keyboard); sideways, a rail beside it. While driving it, a copy made on the
// screen lands on the phone's clipboard, the phone's text is pasted into it, and files picked go onto its machine (how
// far they have got, then where they are, over the frame's foot). How the view is (connecting, reconnecting, ended…) is
// the core's, said over the frame, which stays as it was last shown.
package fail.still.android.remote

import android.content.ClipData
import fail.still.android.ui.Smooth
import fail.still.android.ui.WaitPill
import android.content.ClipboardManager
import android.content.Context
import android.graphics.SurfaceTexture
import android.os.Build
import android.os.SystemClock
import android.content.pm.ActivityInfo
import android.view.HapticFeedbackConstants
import android.view.Surface
import android.view.TextureView
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.toSize
import androidx.compose.ui.viewinterop.AndroidView
import fail.still.android.data.ScreenCursor
import fail.still.android.data.ScreenDrop
import fail.still.android.data.errorText
import fail.still.android.data.t
import fail.still.android.ui.fileSize
import fail.still.android.ui.Button
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Seg
import fail.still.android.ui.ToastHost
import fail.still.android.ui.floatingStill
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/** The stage's tag (the tests find the frame by it). */
internal const val STAGE = "screen-stage"

/** The most a screen is zoomed in, over its fitted size. */
private const val MAX_ZOOM = 5f

/**
 * The frame's own zoom, on this phone only (never sent): `scale` over the fitted size, the frame moved by `x`, `y` (px)
 * from where it sits fitted. Kept within the stage: smaller than it, centred; larger, no gap at its edges.
 */
internal class ViewZoom {
    var scale by mutableFloatStateOf(1f); private set
    var x by mutableFloatStateOf(0f); private set
    var y by mutableFloatStateOf(0f); private set
    val zoomed get() = scale > 1.01f

    /** Where the frame is drawn on the stage, fitted at `fit`. */
    fun shown(fit: Rect): Rect = Rect(fit.left + x, fit.top + y, fit.left + x + fit.width * scale, fit.top + y + fit.height * scale)

    /** At `next` over `fit`, its top left at `left`, `top` on the stage as near as its edges let it be. */
    private fun put(next: Float, left: Float, top: Float, fit: Rect, box: Size) {
        fun place(want: Float, size: Float, room: Float) = if (size <= room) (room - size) / 2 else want.coerceIn(room - size, 0f)
        scale = next
        x = place(left, fit.width * next, box.width) - fit.left
        y = place(top, fit.height * next, box.height) - fit.top
    }

    /** By `factor` around `focus`, and moved by `pan` (on the stage, px). */
    fun by(factor: Float, focus: Offset, pan: Offset, fit: Rect, box: Size) {
        if (fit.width <= 0f) return
        val before = shown(fit)
        val next = (scale * factor).coerceIn(1f, MAX_ZOOM)
        val u = Offset((focus.x - before.left) / before.width, (focus.y - before.top) / before.height)
        put(next, focus.x - u.x * fit.width * next + pan.x, focus.y - u.y * fit.height * next + pan.y, fit, box)
    }

    fun pan(d: Offset, fit: Rect, box: Size) = by(1f, Offset(fit.center.x, fit.center.y), d, fit, box)

    /** `at` (0..1 of the frame) brought `margin` px within the stage's edges, the frame moved as little as it takes. */
    fun keep(at: Offset, margin: Float, fit: Rect, box: Size) {
        val s = shown(fit)
        val p = Offset(s.left + at.x * s.width, s.top + at.y * s.height)
        fun off(v: Float, room: Float) = when {
            room < 2 * margin -> room / 2 - v
            v < margin -> margin - v
            v > room - margin -> room - margin - v
            else -> 0f
        }
        val d = Offset(off(p.x, box.width), off(p.y, box.height))
        if (d != Offset.Zero) pan(d, fit, box)
    }

    /**
     * The stage resized (the keyboard up or down): the frame drawn as large as it was, so what is typed into stays as
     * legible, `at` (0..1 of the frame; else what was in the middle) where it was on the stage and kept in sight.
     */
    fun refit(before: Rect, after: Rect, box: Size, at: Offset?, margin: Float) {
        if (before.width <= 0f || after.width <= 0f) { reset(); return }
        val was = shown(before)
        val u = at ?: Offset((before.center.x - was.left) / was.width, (before.center.y - was.top) / was.height)
        val next = (was.width / after.width).coerceIn(1f, MAX_ZOOM)
        put(next, was.left + u.x * was.width - u.x * after.width * next, was.top + u.y * was.height - u.y * after.height * next, after, box)
        keep(u, margin, after, box)
    }

    fun reset() { scale = 1f; x = 0f; y = 0f }
}

/**
 * Where the pointer is as the trackpad moves it (0..1 of the frame), ahead of the station saying so; where the station
 * says it is once the finger has been still a moment (something else moved it, or the screen's edge held it).
 */
internal class PadPointer {
    var x by mutableFloatStateOf(0.5f); private set
    var y by mutableFloatStateOf(0.5f); private set
    val at get() = Offset(x, y)
    /** When the finger last moved it (uptime, ms). */
    private var movedAt = Long.MIN_VALUE / 2

    fun by(dx: Float, dy: Float, now: Long) {
        x = (x + dx).coerceIn(0f, 1f)
        y = (y + dy).coerceIn(0f, 1f)
        movedAt = now
    }

    fun follow(cursor: ScreenCursor?, now: Long) {
        if (cursor == null || now - movedAt < PAD_SETTLE_MS) return
        x = cursor.x.toFloat().coerceIn(0f, 1f)
        y = cursor.y.toFloat().coerceIn(0f, 1f)
    }
}

/** How long after the finger moved the pointer the station's word on it is taken again (its echo of the moves is behind). */
private const val PAD_SETTLE_MS = 600L

/**
 * How far the pointer goes for a finger's move of 1 px, by how fast it moves (px per ms, in dp): slowly, less than the
 * finger, to land on something small; fast, further, to cross the screen in a stroke.
 */
private fun padGain(dpPerMs: Float): Float = 0.55f + 1.6f * ((dpPerMs - 0.1f) / 1.4f).coerceIn(0f, 1f)

/** The viewer: `title` until the core says one (the link's own, or the row's it was opened from); `onExit` closes it. */
@Composable
fun ScreenViewer(session: ScreenSession, title: String?, onExit: () -> Unit) {
    val zoom = remember { ViewZoom() }
    val pad = remember { PadPointer() }
    val held = remember { HeldKeys() }
    val context = LocalContext.current
    var catcher by remember { mutableStateOf<KeyCatcher?>(null) }
    // The pointer where the station says it is, once the finger has let it be (and again once its echo has come).
    val cursor = session.state?.cursor
    LaunchedEffect(cursor) {
        pad.follow(cursor, SystemClock.uptimeMillis())
        kotlinx.coroutines.delay(PAD_SETTLE_MS + 100)
        pad.follow(cursor, SystemClock.uptimeMillis())
    }
    val density = LocalDensity.current
    val ime = WindowInsets.ime
    val typing = ime.getBottom(density) > 0
    fun keyboard() {
        val view = catcher ?: return
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (typing) { imm.hideSoftInputFromWindow(view.windowToken, 0); view.clearFocus() }
        else { view.requestFocus(); imm.showSoftInput(view, 0) }
    }
    // No longer driving it (只看, the view ended): the keyboard goes.
    LaunchedEffect(session.driving) {
        val view = catcher ?: return@LaunchedEffect
        if (!session.driving && view.hasFocus()) {
            (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(view.windowToken, 0)
            view.clearFocus()
        }
    }
    // A short note over the viewer (a copy taken, the clipboard empty, what failed and why).
    var note by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val clipboard = remember(context) { context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager }
    // A copy made on the screen: onto the phone's clipboard. Android 13 and later say so themselves; before, it is said here.
    DisposableEffect(session, clipboard) {
        session.copied = { text ->
            if (text == null) note = t("android-misc.screen.copiedImage")
            else {
                clipboard.setPrimaryClip(ClipData.newPlainText(session.state?.title ?: "still.fail", text))
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) note = t("android-misc.screen.copied")
            }
        }
        onDispose { session.copied = null }
    }
    /** `run` (a call to the screen), its failure said as 没能<what>：<why>. */
    fun act(what: String, run: suspend () -> Unit) {
        scope.launch {
            try { run() } catch (e: CoreException) { note = t("android-misc.act.failed", "what" to what, "error" to errorText(e)) }
        }
    }
    var pasting by remember { mutableStateOf(false) }
    // The phone's clipboard, pasted into the screen where its focus is.
    fun paste() {
        if (pasting) return
        val text = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
        if (text.isEmpty()) { note = t("android-misc.screen.clipboardEmpty"); return }
        pasting = true
        act(t("android-misc.screen.pasteWhat")) { try { session.paste(text) } finally { pasting = false } }
    }
    // Where the files picked go: as the state said when the picker was asked for (the view opens again meanwhile, the
    // activity out of sight under the picker).
    var dropTo by remember { mutableStateOf<ScreenDrop?>(null) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        dropTo?.let { session.drops.send(context.contentResolver, uris, it) }
    }
    fun send() {
        dropTo = session.dropsTo ?: return
        pick.launch(arrayOf("*/*"))
    }
    /** Trackpad or direct, said as it is chosen: how a finger drives it now. */
    fun choosePad(on: Boolean) {
        note = t(if (on) "android-misc.screen.padOn" else "android-misc.screen.padOff")
        act(t("android-misc.screen.touchWhat")) { session.choosePad(on) }
    }
    // 全屏: the screen alone on the phone, sideways, the system bars away (a swipe from an edge shows them a moment), the
    // tools folded into one button over the frame's corner; back (or 退出全屏) as it was.
    var full by rememberSaveable { mutableStateOf(false) }
    val window = LocalView.current
    DisposableEffect(full) {
        val activity = context as? android.app.Activity
        val controller = activity?.window?.let { WindowCompat.getInsetsController(it, window) }
        controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (full) controller?.hide(WindowInsetsCompat.Type.systemBars()) else controller?.show(WindowInsetsCompat.Type.systemBars())
        activity?.requestedOrientation = if (full) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        onDispose { if (full) { controller?.show(WindowInsetsCompat.Type.systemBars()); activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED } }
    }
    BackHandler(full) { full = false }
    val tools = Tools(pasting, ::paste, ::send, ::choosePad, full) { full = it }
    val dropActs = DropActs(
        pastePath = { d -> act(t("android-misc.screen.pasteWhat")) { session.paste(d.path) } },
        reveal = { d -> act(t("android-misc.screen.revealWhat")) { session.reveal(d.path) } },
    )
    // Full, edge to edge (only the keyboard keeps its room), on black as a video is.
    BoxWithConstraints(Modifier.fillMaxSize().background(if (full) Color.Black else C.bg).windowInsetsPadding(if (full) WindowInsets.ime else WindowInsets.safeDrawing)) {
        // Unseen, where the keyboard's input goes.
        AndroidView({ KeyCatcher(it, held) { input -> session.input(input) }.also { catcher = it } }, Modifier.size(1.dp).alpha(0f))
        val sideways = maxWidth > maxHeight
        if (full) Box(Modifier.fillMaxSize()) {
            Stage(session, zoom, pad, dropActs, Modifier.fillMaxSize(), onExit)
            if (session.canTakeOver) TakeOver(session, Modifier.align(Alignment.TopCenter).padding(top = 12.dp))
            if (session.driving && typing) KeysRow(session, held, Modifier.align(Alignment.BottomCenter).padding(8.dp).floatingStill(CircleShape).padding(4.dp))
            FullTools(session, typing, ::keyboard, tools, Modifier.align(Alignment.TopEnd).padding(12.dp))
        } else if (sideways) Row(Modifier.fillMaxSize()) {
            Rail(session, typing, ::keyboard, tools, onExit)
            Box(Modifier.weight(1f).fillMaxHeight()) {
                Stage(session, zoom, pad, dropActs, Modifier.fillMaxSize(), onExit)
                // Sideways the frame takes the height: who drives it floats over its top, while it does.
                if (session.canTakeOver) TakeOver(session, Modifier.align(Alignment.TopCenter).padding(top = 12.dp))
                // The keys a phone's keyboard has not, over the frame's foot while it is up.
                if (session.driving && typing) KeysRow(session, held, Modifier.align(Alignment.BottomCenter).padding(8.dp).floatingStill(CircleShape).padding(4.dp))
            }
        } else Column(Modifier.fillMaxSize()) {
            Bar(session, title, tools, onExit)
            if (session.canTakeOver) TakeOver(session, Modifier.align(Alignment.CenterHorizontally).padding(horizontal = 12.dp, vertical = 4.dp))
            Stage(session, zoom, pad, dropActs, Modifier.weight(1f).fillMaxWidth(), onExit)
            // Upright, under the frame: trackpad or direct, the keys a phone's keyboard has not, the keyboard.
            if (session.driving) Foot(session, held, typing, ::keyboard, tools)
        }
        ToastHost(note) { note = null }
    }
}

/**
 * The clipboard and files, from the bar: pasting the phone's text (under way: `pasting`), picking files to send; and
 * trackpad or direct, chosen.
 */
private class Tools(
    val pasting: Boolean, val paste: () -> Unit, val send: () -> Unit, val choosePad: (Boolean) -> Unit,
    /** 全屏, and asking for it (or out of it). */
    val full: Boolean, val setFull: (Boolean) -> Unit,
)

/** What can be done with a file once it is on the machine: its path pasted, shown in the machine's file manager. */
private class DropActs(val pastePath: (Drop) -> Unit, val reveal: (Drop) -> Unit)

/** Sending a file (where the station takes them) and pasting (where it carries text), while driving it. */
@Composable
private fun ClipButtons(session: ScreenSession, tools: Tools) {
    if (session.dropsTo != null) RoundButton(Icons.Upload, t("android-misc.screen.sendFile"), onClick = tools.send)
    if (session.pastes) RoundButton(Icons.Paste, t("android-misc.screen.paste"), pressed = tools.pasting, onClick = tools.paste)
}

/** The view is open (on its way, live, or back on its way), not over. */
private fun open(session: ScreenSession) = session.phase in setOf("connecting", "live", "reconnecting")

/** 只看 / 控制, while it may be driven and the view is open. */
private fun choosable(session: ScreenSession) = session.state?.may == true && open(session)

/**
 * Why it is not driven though 控制 was chosen, live (the station lacks a grant: macOS's Accessibility), in the station's
 * words; null when it is driven, or only looked at.
 */
private fun undriven(session: ScreenSession): String? {
    val state = session.state ?: return null
    if (session.phase != "live" || !session.controlling || state.control || !state.may || state.takeOver == true) return null
    return state.access?.message?.takeIf { it.isNotEmpty() }
}

/** Upright: close, the title over the core's line (只看 or 控制, who else is on it), 只看/控制, the clipboard and files. */
@Composable
private fun Bar(session: ScreenSession, title: String?, tools: Tools, onExit: () -> Unit) {
    val state = session.state
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(start = 6.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        RoundButton(Icons.Close, t("android-misc.screen.close"), onClick = onExit)
        Column(Modifier.weight(1f)) {
            Text(state?.title?.takeIf { it.isNotEmpty() } ?: title ?: t("android-misc.screen.title"), fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            // While another drives it, who does is said below (with 接管), not twice.
            state?.line?.takeIf { it.isNotEmpty() && open(session) && !session.canTakeOver }?.let { Text(it, fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        if (choosable(session)) Seg(
            listOf(t("android-misc.screen.look"), t("android-misc.screen.drive")), if (session.controlling) 1 else 0,
            { session.control(it == 1) }, height = 32.dp, radius = 16.dp,
        )
        ClipButtons(session, tools)
        FullButton(tools)
    }
}

/** 全屏 (on) or not. */
@Composable
private fun FullButton(tools: Tools) =
    RoundButton(Icons.Landscape, t(if (tools.full) "android-misc.screen.unfull" else "android-misc.screen.full"), pressed = tools.full) { tools.setFull(!tools.full) }

/**
 * 全屏's tools, folded into one round button over the frame's corner (in the letterbox, as a screen wider than the phone
 * leaves one): open, the same as the rail's down from it — 只看/控制, trackpad, the clipboard and files, the keyboard,
 * 退出全屏 (closed from there, or with back twice).
 */
@Composable
private fun FullTools(session: ScreenSession, typing: Boolean, keyboard: () -> Unit, tools: Tools, modifier: Modifier) {
    var open by remember { mutableStateOf(false) }
    // A round button 4 in from the capsule's edge: its corner 20 + 4.
    Column(
        modifier.floatingStill(Smooth(24.dp)).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        RoundButton(if (open) Icons.Close else Icons.More, t(if (open) "android-misc.screen.toolsClose" else "android-misc.screen.tools"), pressed = open) { open = !open }
        if (open) {
            if (choosable(session)) RoundButton(
                if (session.controlling) Icons.Cursor else Icons.Eye,
                if (session.controlling) t("android-misc.screen.drive") else t("android-misc.screen.look"),
                pressed = session.controlling,
            ) { session.control(!session.controlling) }
            if (session.driving) PadButton(session, tools)
            ClipButtons(session, tools)
            if (session.driving) RoundButton(Icons.Keyboard, t("android-misc.screen.keyboard"), pressed = typing, onClick = keyboard)
            FullButton(tools)
        }
    }
}

/** Trackpad (on) or direct, as a round button that is on while it is a trackpad. */
@Composable
private fun PadButton(session: ScreenSession, tools: Tools) =
    RoundButton(Icons.Trackpad, t("android-misc.screen.trackpad"), pressed = session.pad) { tools.choosePad(!session.pad) }

/** Upright, under the frame while driving it: trackpad or direct, the keys row, the keyboard. */
@Composable
private fun Foot(session: ScreenSession, held: HeldKeys, typing: Boolean, keyboard: () -> Unit, tools: Tools) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        PadButton(session, tools)
        KeysRow(session, held, Modifier.weight(1f))
        RoundButton(Icons.Keyboard, t("android-misc.screen.keyboard"), pressed = typing, onClick = keyboard)
    }
}

/** A key of the keys row: what it sends, or a modifier held for the next key (`mod`, its bit). */
private class RowKeyDef(val label: String, val name: String, val key: String = "", val code: String = "", val mod: Int = 0, val icon: ImageVector? = null)

private fun rowKeys() = listOf(
    RowKeyDef("Esc", "Esc", "Escape", "Escape"),
    RowKeyDef("Tab", "Tab", "Tab", "Tab"),
    RowKeyDef("⌘", t("android-misc.screen.key.command"), mod = META),
    RowKeyDef("⌃", t("android-misc.screen.key.control"), mod = CTRL),
    RowKeyDef("⌥", t("android-misc.screen.key.option"), mod = ALT),
    RowKeyDef("⇧", t("android-misc.screen.key.shift"), mod = SHIFT),
    RowKeyDef("", t("android-misc.screen.key.left"), "ArrowLeft", "ArrowLeft", icon = Icons.ArrowLeft),
    RowKeyDef("", t("android-misc.screen.key.up"), "ArrowUp", "ArrowUp", icon = Icons.ArrowUp),
    RowKeyDef("", t("android-misc.screen.key.down"), "ArrowDown", "ArrowDown", icon = Icons.ArrowDown),
    RowKeyDef("", t("android-misc.screen.key.right"), "ArrowRight", "ArrowRight", icon = Icons.ArrowRight),
)

/**
 * The keys a phone's keyboard has not (Esc, Tab, the arrows) and the modifiers (⌘ ⌃ ⌥ ⇧: held, shown solid, for the
 * next key, typed or here), in a row that scrolls when it is wider than its room.
 */
@Composable
private fun KeysRow(session: ScreenSession, held: HeldKeys, modifier: Modifier) {
    Row(modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        rowKeys().forEach { k ->
            val on = k.mod != 0 && held.mods and k.mod != 0
            Box(
                Modifier.height(36.dp).widthIn(min = 40.dp).clip(CircleShape).background(if (on) C.ink else C.ink.copy(alpha = 0.06f))
                    .clickable {
                        if (k.mod != 0) held.toggle(k.mod) else stroke(session::input, k.key, k.code, held.take())
                    }
                    .semantics { contentDescription = k.name }.padding(horizontal = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (k.icon != null) IconIn(k.icon, 18.dp, C.ink)
                else Text(k.label, fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold, color = if (on) C.bg else C.ink, maxLines = 1)
            }
        }
    }
}

/** Sideways: the same down the side, the line said when the people on it are tapped. */
@Composable
private fun Rail(session: ScreenSession, typing: Boolean, keyboard: () -> Unit, tools: Tools, onExit: () -> Unit) {
    val state = session.state
    var saying by remember { mutableStateOf(false) }
    LaunchedEffect(saying) { if (saying) { kotlinx.coroutines.delay(3000); saying = false } }
    Box {
        Column(
            Modifier.fillMaxHeight().width(60.dp).padding(vertical = 8.dp),
            // Eight at most down a phone's short side: close together.
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            RoundButton(Icons.Close, t("android-misc.screen.close"), onClick = onExit)
            Spacer(Modifier.weight(1f))
            if (state != null && state.line.isNotEmpty() && open(session)) Box(contentAlignment = Alignment.TopEnd) {
                RoundButton(Icons.Users, state.line, pressed = saying) { saying = !saying }
                if (state.others.isNotEmpty()) Text(
                    "${state.others.size}", fontSize = 10.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, color = C.bg, textAlign = TextAlign.Center,
                    modifier = Modifier.offset(x = 4.dp, y = (-2).dp).widthIn(min = 14.dp).height(14.dp).clip(CircleShape).background(C.ink),
                )
            }
            if (choosable(session)) RoundButton(
                if (session.controlling) Icons.Cursor else Icons.Eye,
                if (session.controlling) t("android-misc.screen.drive") else t("android-misc.screen.look"),
                pressed = session.controlling,
            ) { session.control(!session.controlling) }
            if (session.driving) PadButton(session, tools)
            ClipButtons(session, tools)
            if (session.driving) RoundButton(Icons.Keyboard, t("android-misc.screen.keyboard"), pressed = typing, onClick = keyboard)
            FullButton(tools)
        }
        if (saying && state != null) Text(
            state.line, fontSize = 13.sp, lineHeight = 18.sp, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomStart).offset(x = 64.dp, y = (-8).dp).widthIn(max = 280.dp)
                .floatingStill(Smooth(18.dp)).padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}

/**
 * Someone else drives it (an agent at work) and this view only looks: who, and 接管 in one tap (`screen.control` true:
 * their input waits while this person drives; the line then says so).
 */
@Composable
private fun TakeOver(session: ScreenSession, modifier: Modifier) {
    val who = session.state?.controllers.orEmpty()
    // A capsule round a 32 high button 6 in from its edge: its corner 6 + 16.
    Row(
        modifier.widthIn(max = 480.dp).floatingStill(Smooth(22.dp)).padding(start = 14.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(C.warn))
        Text(
            if (who.isEmpty()) t("android-misc.screen.someoneDrives") else t("android-misc.screen.drives", "who" to who.joinToString("、")),
            fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        // The main solid button, as the web's primary (dark in the light theme, light in the dark one), not the accent.
        Box(
            Modifier.height(32.dp).clip(Smooth(16.dp)).background(C.ink).clickable { session.control(true) }.padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) { Text(t("android-misc.screen.takeOver"), fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.SemiBold, color = C.bg, maxLines = 1) }
    }
}

/** A round button with an icon, its name for those who cannot see it; `pressed`: on (the keyboard up, 控制). */
@Composable
private fun RoundButton(icon: ImageVector, label: String, pressed: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(if (pressed) C.ink.copy(alpha = 0.1f) else Color.Transparent)
            .clickable(onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { IconIn(icon, 20.dp, C.ink) }
}

/** The frame, fitted and zoomed, its pointer; the gestures; how the view is, and the files sent, over it. */
@Composable
private fun Stage(session: ScreenSession, zoom: ViewZoom, pad: PadPointer, dropActs: DropActs, modifier: Modifier, onExit: () -> Unit) {
    val picture = session.picture
    val size = session.size ?: picture?.let { IntSize(it.bitmap.width, it.bitmap.height) }
    var box by remember { mutableStateOf(Size.Zero) }
    val fit = if (size == null) Rect.Zero else fitIn(box, Size(size.width.toFloat(), size.height.toFloat()))
    // Another size of frame: fitted again.
    LaunchedEffect(size) { zoom.reset() }
    val phase = session.phase
    val density = LocalDensity.current
    val margin = with(density) { 40.dp.toPx() }
    val fitNow by rememberUpdatedState(fit)
    val boxNow by rememberUpdatedState(box)
    val sizeNow by rememberUpdatedState(size)
    val view = LocalView.current
    /** Where the pointer is now as this phone draws it: the trackpad's while it drives it so, else the station's. */
    val padNow = session.driving && session.pad
    fun resized(next: Size) {
        val frame = sizeNow?.let { Size(it.width.toFloat(), it.height.toFloat()) }
        if (frame != null && boxNow != Size.Zero) {
            // Turned: fitted again; else (the keyboard up or down) drawn as large as it was, the pointer in sight.
            if ((boxNow.width > boxNow.height) != (next.width > next.height)) zoom.reset()
            else zoom.refit(fitIn(boxNow, frame), fitIn(next, frame), next, if (padNow) pad.at else session.state?.cursor?.let { Offset(it.x.toFloat(), it.y.toFloat()) }, margin)
        }
        box = next
    }
    Box(
        modifier.clipToBounds().testTag(STAGE).onSizeChanged { resized(it.toSize()) }
            .pointerInput(session, zoom) { gestures(session, zoom, pad, margin, { fitNow }, { boxNow }, { sizeNow }) { view.performHapticFeedback(it) } },
    ) {
        if (size != null && fit.width > 0f) {
            val still = phase != "live" && session.shownAny
            Box(
                Modifier.offset { IntOffset(fit.left.roundToInt(), fit.top.roundToInt()) }
                    .size(with(density) { fit.width.toDp() }, with(density) { fit.height.toDp() })
                    .graphicsLayer {
                        transformOrigin = TransformOrigin(0f, 0f)
                        scaleX = zoom.scale; scaleY = zoom.scale
                        translationX = zoom.x; translationY = zoom.y
                        alpha = if (still) 0.4f else 1f
                    },
            ) {
                if (session.codec == "h264") Texture(session)
                else Canvas(Modifier.fillMaxSize()) {
                    val p = session.picture ?: return@Canvas
                    drawImage(p.bitmap.asImageBitmap(), dstSize = IntSize(this.size.width.roundToInt(), this.size.height.roundToInt()), filterQuality = FilterQuality.Medium)
                    session.drew(p)
                }
            }
            // Drawn over the frame at its own size, however zoomed: where the trackpad has it, else where the station says.
            Pointer({ if (padNow) pad.at else session.state?.cursor?.let { Offset(it.x.toFloat(), it.y.toFloat()) } }, { zoom.shown(fitNow) })
        }
        Over(session, phase, Modifier.align(Alignment.Center), onExit)
        Column(
            Modifier.align(Alignment.BottomCenter).padding(16.dp).widthIn(max = 420.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Drops(session, dropActs)
            undriven(session)?.let { why ->
                Row(
                    Modifier.floatingStill(Smooth(18.dp)).padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    IconIn(Icons.Info, 16.dp, C.muted)
                    Text(why, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** The files sent to the machine, one row each, until let go of: how far each has got, or where it is now, or why it failed. */
@Composable
private fun Drops(session: ScreenSession, acts: DropActs) {
    val list = session.drops.list
    if (list.isEmpty()) return
    // Its corner as the panel the view's end is said in (Over).
    Column(Modifier.fillMaxWidth().floatingStill(Smooth(24.dp)).padding(vertical = 6.dp)) {
        list.forEach { d -> key(d) { DropRow(session, d, acts) } }
    }
}

@Composable
private fun DropRow(session: ScreenSession, d: Drop, acts: DropActs) {
    val resolver = LocalContext.current.contentResolver
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 8.dp, top = 8.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        when (d.state) {
            "done" -> IconIn(Icons.CheckCircle, 20.dp, C.accent, Modifier.padding(top = 1.dp))
            "failed" -> IconIn(Icons.Info, 20.dp, C.red, Modifier.padding(top = 1.dp))
            else -> IconIn(Icons.Upload, 20.dp, C.muted, Modifier.padding(top = 1.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(d.name, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            when (d.state) {
                "done" -> {
                    Text(d.path, fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    // What is done with it there goes through the view: while driving it.
                    if (session.driving) Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (session.pastes) Button(t("android-misc.screen.pastePath"), primary = false) { acts.pastePath(d) }
                        if (d.reveal) Button(t("android-misc.screen.reveal"), primary = false) { acts.reveal(d) }
                    }
                }
                "failed" -> Text(t("android-misc.drive.upload.failed", "error" to (d.error ?: "")), fontSize = 12.sp, lineHeight = 16.sp, color = C.red, maxLines = 3, overflow = TextOverflow.Ellipsis)
                else -> {
                    Text(
                        if (d.size < 0) t("android-misc.screen.sendWaiting") else t("android-misc.drive.upload.going", "sent" to fileSize(d.sent), "size" to fileSize(d.size)),
                        fontSize = 12.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1,
                    )
                    val share = if (d.size > 0) (d.sent.toFloat() / d.size).coerceIn(0f, 1f) else 0f
                    Box(Modifier.padding(top = 5.dp).fillMaxWidth().height(3.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.08f))) {
                        Box(Modifier.fillMaxWidth(share).height(3.dp).clip(CircleShape).background(C.accent))
                    }
                }
            }
        }
        if (d.state == "failed") RowKey(Icons.Retry, t("android-misc.drive.retry")) { session.drops.retry(resolver, d) }
        RowKey(Icons.Close, if (d.state == "done" || d.state == "failed") t("common.close") else t("common.cancel")) { session.drops.dismiss(d) }
    }
}

/** A small round key at a row's end (DriveScreen's). */
@Composable
private fun RowKey(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(34.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) { IconIn(icon, 16.dp, C.muted) }
}

/** H.264 decoded straight onto a texture of the frame's size (MediaCodec, Decoders.kt). */
@Composable
private fun Texture(session: ScreenSession) {
    AndroidView({ ctx ->
        TextureView(ctx).apply {
            isOpaque = false
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                private var surface: Surface? = null
                override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                    surface = Surface(st).also(session::surface)
                }
                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                    session.surface(null)
                    surface?.release()
                    surface = null
                    return true
                }
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
            }
        }
    }, Modifier.fillMaxSize())
}

/**
 * Where the pointer is (`at`, 0..1 of the frame drawn at `shown` on the stage; read as it is drawn, it moves without
 * the page composed again): an arrow, white with a dark edge, its tip there.
 */
@Composable
private fun Pointer(at: () -> Offset?, shown: () -> Rect) {
    Canvas(Modifier.fillMaxSize()) {
        val at = at() ?: return@Canvas
        val shown = shown()
        val k = 1.dp.toPx()
        val arrow = Path().apply {
            moveTo(0f, 0f); lineTo(0f, 16 * k); lineTo(4 * k, 12.5f * k); lineTo(7 * k, 18.5f * k)
            lineTo(9.5f * k, 17.5f * k); lineTo(6.5f * k, 11.5f * k); lineTo(11.5f * k, 11.5f * k); close()
        }
        translate(shown.left + at.x * shown.width, shown.top + at.y * shown.height) {
            drawPath(arrow, Color.White)
            drawPath(arrow, Color(0xFF1B1C1F), style = Stroke(1.2f * k))
        }
    }
}

/** How the view is, when it is not simply live: on its way, back on its way, or over (why, and what can be done). */
@Composable
private fun Over(session: ScreenSession, phase: String, modifier: Modifier, onExit: () -> Unit) {
    val message = session.message
    when (phase) {
        "live" -> if (!session.shownAny) Waiting(t("android-misc.screen.starting"), modifier)
        "connecting" -> Waiting(message ?: t("common.connecting"), modifier)
        "reconnecting" -> Waiting(message ?: t("common.reconnecting"), modifier)
        else -> Column(
            modifier.padding(24.dp).widthIn(max = 360.dp).floatingStill(Smooth(24.dp)).padding(horizontal = 24.dp, vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconIn(if (session.state?.kind == "browser") Icons.Web else Icons.Monitor, 28.dp, C.muted)
            Text(t("android-misc.screen.$phase"), fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, color = C.ink, textAlign = TextAlign.Center)
            if (message != null) Text(message, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, textAlign = TextAlign.Center)
            // What to turn on where (macOS's grants), when the station says and its message did not already.
            session.state?.access?.message?.takeIf { it.isNotEmpty() && it != message }?.let {
                Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, textAlign = TextAlign.Center)
            }
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (phase in setOf("ended", "denied", "failed")) Button(t("android-misc.screen.retry"), primary = true) { session.open() }
                Button(t("android-misc.screen.exit"), primary = false, onClick = onExit)
            }
        }
    }
}

/** On its way: why, in the pill every wait is said in (ui/Waiting.kt), floating over the frame (kept as it was) or the empty stage. */
@Composable
private fun Waiting(text: String, modifier: Modifier) =
    WaitPill(text, modifier = modifier.padding(24.dp).floatingStill(CircleShape), ground = Color.Transparent, ink = C.ink)

private fun centroid(fingers: List<PointerInputChange>): Offset =
    fingers.fold(Offset.Zero) { s, c -> s + c.position } / fingers.size.toFloat()

private fun spread(fingers: List<PointerInputChange>, around: Offset): Float =
    fingers.sumOf { (it.position - around).getDistance().toDouble() }.toFloat() / fingers.size

/** A tap's end on the trackpad (uptime, ms; where): a finger down again soon after, and moved, drags. */
private class LastTap(var at: Long = Long.MIN_VALUE / 2, var where: Offset = Offset.Zero)

/**
 * The stage's gestures. Driving it as a trackpad (`session.pad`): one finger moves the pointer, a tap clicks where it
 * points, tapped again and moved (or held still) it drags, two fingers tapped click the right button, two moving
 * together scroll. Driving it directly: a tap is a click where it is (down and up, the primary button), a press held a
 * right click, a drag a drag (down, moves, up), two fingers moving together a wheel. Either way two fingers spreading
 * zoom the frame here (it is not sent); only looking, moving together pan it when zoomed, one finger too.
 */
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.gestures(
    session: ScreenSession, zoom: ViewZoom, pad: PadPointer, margin: Float, fit: () -> Rect, box: () -> Size, frame: () -> IntSize?,
    buzz: (Int) -> Unit,
) {
    val tapped = LastTap()
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        if (session.driving && session.pad) padGesture(down, session, zoom, pad, margin, fit, box, frame, tapped, buzz)
        else directGesture(down, session, zoom, fit, box, frame, buzz)
    }
}

/** Two fingers on the stage: spreading (1, zooming here), or moving together (2), once they have gone past the slop. */
private class TwoFingers(fingers: List<PointerInputChange>) {
    var kind = 0
    private val c0 = centroid(fingers)
    private val s0 = spread(fingers, c0)
    var from = c0; private set
    var spreadWas = s0; private set

    /** Where they are now: what they are doing told once they have moved enough, and then how far since the last. */
    fun at(fingers: List<PointerInputChange>, slop: Float): Pair<Offset, Float> {
        val c = centroid(fingers)
        val s = spread(fingers, c)
        if (kind == 0) {
            val spreading = abs(s - s0)
            val moving = (c - c0).getDistance()
            if (spreading > slop || moving > slop) kind = if (spreading > moving) 1 else 2
        }
        return c to s
    }

    /** Gone on to `c`, `s`: once told what they are doing (until then measured from where they began, none of the way lost). */
    fun went(c: Offset, s: Float) { if (kind != 0) { from = c; spreadWas = s } }
}

/** Two fingers moving together over `d` (stage px) as a wheel at `at` (0..1): the page under them moves with them. */
private fun scrollBy(session: ScreenSession, d: Offset, at: Offset, shown: Rect, frame: IntSize?) {
    if (frame == null || shown.width <= 0f) return
    // The fingers' way in the frame's own pixels.
    val k = frame.width / shown.width
    session.input(wheel(at, -d.x * k, -d.y * k))
}

private suspend fun androidx.compose.ui.input.pointer.AwaitPointerEventScope.padGesture(
    down: PointerInputChange, session: ScreenSession, zoom: ViewZoom, pad: PadPointer, margin: Float,
    fit: () -> Rect, box: () -> Size, frame: () -> IntSize?, tapped: LastTap, buzz: (Int) -> Unit,
) {
    val slop = viewConfiguration.touchSlop
    val hold = viewConfiguration.longPressTimeoutMillis
    // Down again soon after a tap, near it: a move (or holding still) drags from where it points.
    val again = down.uptimeMillis - tapped.at < viewConfiguration.doubleTapTimeoutMillis && (down.position - tapped.where).getDistance() < slop * 4
    // 0: not yet told, 1: moving the pointer, 2: dragging (the button down), 3: two fingers, 4: nothing more.
    var mode = 0
    var two: TwoFingers? = null
    var twoAt = 0L
    var twoMoved = false
    var lastTime = down.uptimeMillis
    fun press(kind: String, buttons: Int) = session.input(pointer(kind, pad.at, buttons))
    while (true) {
        val event = if (mode == 0) withTimeoutOrNull(max(1L, hold - (lastTime - down.uptimeMillis))) { awaitPointerEvent() } else awaitPointerEvent()
        if (event == null) {
            // Held still: the button down where it points, for what moves next to drag.
            press("down", PRIMARY)
            buzz(HapticFeedbackConstants.LONG_PRESS)
            mode = 2
            continue
        }
        event.changes.firstOrNull()?.let { lastTime = it.uptimeMillis }
        val pressed = event.changes.filter { it.pressed }
        if (pressed.isEmpty()) {
            // Let go on something over the frame that took it (a button of the files' panel): a tap not for the screen.
            val taken = event.changes.any { it.isConsumed }
            when (mode) {
                0 -> if (!taken) {
                    press("down", PRIMARY); press("up", PRIMARY)
                    tapped.at = event.changes.first().uptimeMillis; tapped.where = down.position
                }
                2 -> press("up", PRIMARY)
                3 -> if (!taken && !twoMoved && event.changes.first().uptimeMillis - twoAt < hold) {
                    press("down", SECONDARY); press("up", SECONDARY)
                    buzz(HapticFeedbackConstants.CONTEXT_CLICK)
                }
            }
            break
        }
        if (pressed.size >= 2 && mode != 3) {
            // A second finger: a drag under way ends where it points.
            if (mode == 2) press("up", PRIMARY)
            mode = 3
            two = TwoFingers(pressed)
            twoAt = event.changes.first().uptimeMillis
            event.changes.forEach { it.consume() }
            continue
        }
        val finger = pressed.firstOrNull { it.id == down.id } ?: pressed.first()
        when (mode) {
            0 -> if ((finger.position - down.position).getDistance() > slop) {
                if (again) { press("down", PRIMARY); mode = 2 } else mode = 1
            }
            1, 2 -> {
                val d = finger.position - finger.previousPosition
                val dt = max(1L, finger.uptimeMillis - finger.previousUptimeMillis)
                val shown = zoom.shown(fit())
                if (shown.width > 0f && d != Offset.Zero) {
                    val gain = padGain(d.getDistance() / density / dt)
                    pad.by(d.x * gain / shown.width, d.y * gain / shown.height, finger.uptimeMillis)
                    session.input(pointer("move", pad.at, if (mode == 2) PRIMARY else 0))
                    if (zoom.zoomed) zoom.keep(pad.at, margin, fit(), box())
                }
            }
            3 -> {
                val t = two ?: return
                if (pressed.size >= 2) {
                    val (c, sp) = t.at(pressed, slop)
                    if (t.kind != 0) twoMoved = true
                    if (t.kind == 1) zoom.by(if (t.spreadWas > 0f) sp / t.spreadWas else 1f, c, c - t.from, fit(), box())
                    else if (t.kind == 2) scrollBy(session, c - t.from, pad.at, zoom.shown(fit()), frame())
                    t.went(c, sp)
                }
            }
        }
        event.changes.forEach { if (it.positionChanged()) it.consume() }
    }
}

private suspend fun androidx.compose.ui.input.pointer.AwaitPointerEventScope.directGesture(
    down: PointerInputChange, session: ScreenSession, zoom: ViewZoom, fit: () -> Rect, box: () -> Size, frame: () -> IntSize?,
    buzz: (Int) -> Unit,
) {
    val slop = viewConfiguration.touchSlop
    val hold = viewConfiguration.longPressTimeoutMillis
    val drives = session.driving
    val start = down.position
    fun at(p: Offset, clamp: Boolean) = frameAt(p, zoom.shown(fit()), clamp)
    // 0: not yet told, 1: a drag sent, 2: panning here, 3: two fingers, 4: nothing more (a right click sent, or ignored).
    var mode = 0
    var last = start
    var lastTime = down.uptimeMillis
    var two: TwoFingers? = null
    while (true) {
        val event = if (mode == 0) withTimeoutOrNull(max(1L, hold - (lastTime - down.uptimeMillis))) { awaitPointerEvent() } else awaitPointerEvent()
        if (event == null) {
            // Held still: a right click where it is.
            if (drives) at(start, false)?.let {
                session.input(pointer("down", it, SECONDARY)); session.input(pointer("up", it, SECONDARY))
                buzz(HapticFeedbackConstants.LONG_PRESS)
            }
            mode = 4
            continue
        }
        event.changes.firstOrNull()?.let { lastTime = it.uptimeMillis }
        val pressed = event.changes.filter { it.pressed }
        if (pressed.isEmpty()) {
            // Let go on something over the frame that took it (a button of the files' panel): a tap not for the screen.
            val taken = event.changes.any { it.isConsumed }
            when (mode) {
                0 -> if (drives && !taken) at(start, false)?.let { session.input(pointer("down", it, PRIMARY)); session.input(pointer("up", it, PRIMARY)) }
                1 -> at(last, true)?.let { session.input(pointer("up", it, PRIMARY)) }
            }
            break
        }
        if (pressed.size >= 2 && mode != 3) {
            // A second finger: what the first was doing ends where it is.
            if (mode == 1) at(last, true)?.let { session.input(pointer("up", it, PRIMARY)) }
            mode = 3
            two = TwoFingers(pressed)
            event.changes.forEach { it.consume() }
            continue
        }
        val finger = pressed.firstOrNull { it.id == down.id } ?: pressed.first()
        when (mode) {
            0 -> if ((finger.position - start).getDistance() > slop) {
                mode = when {
                    drives -> at(start, false)?.let { session.input(pointer("down", it, PRIMARY)); 1 } ?: 4
                    zoom.zoomed -> 2
                    else -> 4
                }
                if (mode == 1) at(finger.position, true)?.let { session.input(pointer("move", it, PRIMARY)) }
                last = finger.position
            }
            1 -> {
                at(finger.position, true)?.let { session.input(pointer("move", it, PRIMARY)) }
                last = finger.position
            }
            2 -> zoom.pan(finger.position - finger.previousPosition, fit(), box())
            3 -> {
                val t = two ?: return
                if (pressed.size >= 2) {
                    val (c, sp) = t.at(pressed, slop)
                    if (t.kind == 1) zoom.by(if (t.spreadWas > 0f) sp / t.spreadWas else 1f, c, c - t.from, fit(), box())
                    else if (t.kind == 2) {
                        if (drives) at(c, true)?.let { scrollBy(session, c - t.from, it, zoom.shown(fit()), frame()) }
                        else if (zoom.zoomed) zoom.pan(c - t.from, fit(), box())
                    }
                    t.went(c, sp)
                }
            }
        }
        event.changes.forEach { if (it.positionChanged()) it.consume() }
    }
}
