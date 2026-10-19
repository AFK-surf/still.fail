// What lies over the pages: one sheet from the bottom at a time (dragged by
// its grabber between half and full height, or down to close), a message's
// long-press menu, and a short note.
package fail.still.android.ui

import androidx.compose.foundation.layout.union
import fail.still.android.ui.keyboard
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitVerticalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.verticalDrag
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.layout.layout
import kotlin.math.roundToInt
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import fail.still.android.data.t


/**
 * A sheet: how much of the screen it takes at first, and whether its grabber drags it. `fit`: as tall as what it shows
 * instead (that much, over the navigation bar), for one whose content is a known few lines. `onClose`: told when it is
 * closed by hand (a tap beside it, dragged down, back), not otherwise. `solid`: on the page's paper, not frosted (over
 * another app, where there is no page of the app's own to frost: share/ShareActivity.kt).
 */
class SheetSpec(val height: Float, val draggable: Boolean = false, val fit: Dp? = null, val onClose: (() -> Unit)? = null, val solid: Boolean = false, val content: @Composable ColumnScope.() -> Unit)

/** Drags the open sheet by its top; `release` has the finger's speed (px/s of height, up is positive). */
class SheetDrag(val draggable: Boolean, val drag: (Float) -> Unit, val release: (Float) -> Unit, val tap: () -> Unit)

/** A vertical drag that starts within the sheet's top 64dp; what is under it (a list) scrolls if it takes the drag first. */
private suspend fun PointerInputScope.dragTop(drag: SheetDrag) {
    val zone = 64.dp.toPx()
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        if (down.position.y > zone) return@awaitEachGesture
        val speed = VelocityTracker().apply { addPointerInputChange(down) }
        val first = awaitVerticalTouchSlopOrCancellation(down.id) { change, over -> change.consume(); speed.addPointerInputChange(change); drag.drag(over) }
            ?: return@awaitEachGesture
        val ended = verticalDrag(first.id) { change ->
            speed.addPointerInputChange(change)
            drag.drag(change.positionChange().y)
            change.consume()
        }
        drag.release(if (ended) -speed.calculateVelocity().y else 0f)
    }
}

private val LocalSheetDrag = staticCompositionLocalOf<SheetDrag?> { null }

@Composable
fun SheetHost(spec: SheetSpec?, haze: HazeState, close: () -> Unit) {
    var shown by remember { mutableStateOf<SheetSpec?>(null) }
    if (spec != null && shown !== spec) shown = spec
    BackHandler(enabled = spec != null) { close() }
    // A sheet comes up in the keyboard's place: what was being typed into lets go of it first.
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    LaunchedEffect(spec) { if (spec != null) { focus.clearFocus(); keyboard?.hide() } }
    val scrim by animateFloatAsState(if (spec != null) 1f else 0f, tween(300, easing = Ease.Css), label = "scrim")
    val current = shown ?: return
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val total = constraints.maxHeight.toFloat()
        val density = LocalDensity.current
        // How tall a sheet is at first: its share of the screen, or what it shows over the navigation bar (most of the screen at most).
        val foot = WindowInsets.navigationBars.getBottom(density)
        fun tall(of: SheetSpec) = of.fit?.let { minOf(with(density) { it.toPx() } + foot, total * 0.9f) } ?: (of.height * total)
        val height = remember { Animatable(tall(current)) }
        val offset = remember { Animatable(tall(current)) }
        val scope = rememberCoroutineScope()
        LaunchedEffect(spec) {
            if (spec != null) {
                val target = tall(spec)
                if (offset.value > 1f) {
                    height.snapTo(target)
                    offset.animateTo(0f, SheetSpring)
                } else {
                    height.animateTo(target, SheetSpring)
                }
            } else {
                offset.animateTo(height.value, SheetSpring)
                shown = null
            }
        }
        val min = with(density) { 120.dp.toPx() }
        val base = tall(current)
        var held by remember { mutableStateOf<Float?>(null) }
        // Let go: on to where it settles at the speed the finger left it (height per second, up is more).
        fun settle(to: Float, velocity: Float = 0f) { scope.launch { height.animateTo(to, SheetSpring, velocity) } }
        val paper = C.bg
        val glass = C.surface.copy(alpha = 0.8f)
        // One per sheet: a new one would restart the grabber's gesture halfway through a drag.
        val drag = remember(current, total) { SheetDrag(
            draggable = current.draggable,
            // A draggable sheet between half and full height (or down to close); any other only down, to close.
            // Where the finger has it, kept here at once (the height follows a moment later, as its snaps run): let go
            // in the same moment as the last move, it is judged by where the finger was.
            drag = { dy ->
                val from = held ?: height.value
                val to = (from - dy).coerceIn(min, if (current.draggable) total * 0.94f else base)
                held = to
                scope.launch { height.snapTo(to) }
            },
            release = { v ->
                val at = held ?: height.value
                held = null
                val f = at / total
                when {
                    !current.draggable -> if (base - at > with(density) { 80.dp.toPx() }) close() else settle(base, v)
                    f < 0.3f -> close()
                    else -> settle(if (f > 0.72f) total * 0.94f else total * 0.55f, v)
                }
            },
            tap = { settle(if (height.value > total * 0.9f) total * 0.55f else total * 0.94f) },
        ) }
        Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f * scrim))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() },
        )
        val typing = WindowInsets.keyboard
        Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                // Its height read as it is laid out: a drag moves it without making its content again. The keyboard up
                // (a field of its own), it grows by what the keyboard takes over the navigation bar, so what it shows
                // stays as tall over the keyboard and not squeezed under it.
                .layout { m, c ->
                    val over = (typing.getBottom(this) - foot).coerceAtLeast(0)
                    val h = (height.value.roundToInt() + over).coerceIn(c.minHeight, c.maxHeight)
                    val p = m.measure(c.copy(minHeight = h, maxHeight = h)); layout(p.width, h) { p.place(0, 0) }
                }
                .offset { IntOffset(0, offset.value.toInt()) }
                .shadow(24.dp, Smooth(topStart = SHEET_CORNER, topEnd = SHEET_CORNER))
                .clip(Smooth(topStart = SHEET_CORNER, topEnd = SHEET_CORNER))
                // Frosted glass over the page, as the bars and capsules are. The web's backdrop has the scrim in it (it
                // frosts all that is behind it); here the pages alone are the source, so the scrim goes under the glass.
                .then(if (current.solid) Modifier.background(paper) else Modifier.hazeEffect(haze) {
                    backgroundColor = paper; blurRadius = cssBlur(28f); noiseFactor = 0f; inputScale = GlassScale
                    tints = listOf(HazeTint(Color.Black.copy(alpha = 0.28f * scrim)), HazeTint(glass))
                })
                .pointerInput(Unit) { detectTapGestures { } }
                // With a finger its top (the grabber and the head, 64dp) drags it, as web mobile's does.
                .pointerInput(drag) { dragTop(drag) }
                // A field of the sheet's own brings the keyboard up under the sheet, not over it.
                .windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars)),
        ) {
            CompositionLocalProvider(LocalSheetDrag provides drag) { current.content(this) }
        }
    }
}

/** A sheet's top corners. */
val SHEET_CORNER = 26.dp
/** How tall the grabber's band is (SheetGrab: 8 and 4 round it, 4 more each side of its 5), and where a head's row begins. */
private val GRAB_HEIGHT = 25.dp
private val HEAD_TOP = GRAB_HEIGHT + 4.dp
private val HEAD_SIDE = 18.dp
/** A button in a sheet's corner (SheetHead action): this high, SHEET_CORNER less its half from both edges. */
val SHEET_ACTION = 32.dp

/** The sheet's grabber: drags a draggable sheet, and a tap switches it between half and full. */
@Composable
fun SheetGrab() {
    val drag = LocalSheetDrag.current
    Box(
        Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp).let { m ->
            // Its drag is the sheet's top's (SheetHost); a tap switches a draggable sheet between half and full.
            if (drag?.draggable == true) m.pointerInput(drag) { detectTapGestures { drag.tap() } } else m
        }.padding(vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) { Box(Modifier.size(38.dp, 5.dp).clip(RoundedCornerShape(3.dp)).background(C.line)) }
}

/**
 * A sheet's head, under its grabber. `action`: a button with a ground of its own (a capsule, SHEET_ACTION high), put in
 * the sheet's corner as far from its top as from its side, so it is concentric with the corner (its half and that
 * distance the sheet's corner), not 18 from the side and under the grabber's band from the top.
 */
@Composable
fun SheetHead(title: String, trailing: (@Composable () -> Unit)? = null, lead: (@Composable () -> Unit)? = null, action: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = HEAD_SIDE, top = HEAD_TOP - GRAB_HEIGHT, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        lead?.invoke()
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.weight(1f))
        trailing?.invoke()
        if (action != null) Box(Modifier.layout { m, c ->
            val p = m.measure(c)
            // Its top HEAD_TOP down the sheet (it is the tallest in the row) and its end HEAD_SIDE in: moved to `inset` from both.
            val inset = SHEET_CORNER.roundToPx() - p.height / 2
            layout(p.width, p.height) { p.place(HEAD_SIDE.roundToPx() - inset, inset - HEAD_TOP.roundToPx()) }
        }) { action() }
    }
}

// ── the long-press menu ────────────────────────────────────────────────

/** `icon` null: the room for one left empty (a check on another item, say). */
class MenuItem(val label: String, val icon: ImageVector?, val action: () -> Unit)
class MenuSpec(val anchor: Rect, val items: List<MenuItem>, val onDismiss: () -> Unit = {})

// A short, nearly critically damped spring: quick off the mark, soft at its
// destination, and continuous in speed when the user reverses it.
private val MenuSpring = motionSpring<Float>(0.24f, bounce = 0.08f, visibilityThreshold = 0.001f)

@Composable
fun MenuHost(spec: MenuSpec?, closed: () -> Unit) {
    var shown by remember { mutableStateOf<MenuSpec?>(null) }
    if (spec != null) shown = spec
    // Keep the closed state alive before the first menu is mounted, and keep its
    // content until both the menu and its backdrop have finished leaving.
    val visible = remember { MutableTransitionState(false) }
    visible.targetState = spec != null
    val scrim by animateFloatAsState(if (spec != null) 1f else 0f, tween(200), label = "menu-scrim")
    LaunchedEffect(spec, visible.isIdle, visible.currentState, scrim) {
        if (spec == null && visible.isIdle && !visible.currentState && scrim == 0f) shown = null
    }
    val current = shown ?: return
    val close = { current.onDismiss(); closed() }
    BackHandler(enabled = spec != null) { close() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f * scrim)).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() })
        val width = 180.dp
        val x = with(density) { current.anchor.left.toDp() }.coerceAtMost(maxWidth - width - 12.dp).coerceAtLeast(12.dp)
        // Under the message, or over it when there is no room below.
        val menuHeight = 45.dp * current.items.size + MENU_PAD * 2
        val below = with(density) { current.anchor.bottom.toDp() } + 6.dp
        val y = if (below + menuHeight < maxHeight - 24.dp) below else (with(density) { current.anchor.top.toDp() } - menuHeight - 6.dp).coerceAtLeast(24.dp)
        val origin = TransformOrigin(0f, if (y == below) 0f else 1f)
        AnimatedVisibility(
            visible,
            Modifier.offset(x, y),
            enter = fadeIn(tween(160, easing = Ease.Out)) + scaleIn(MenuSpring, 0.9f, origin),
            exit = fadeOut(tween(120, easing = Ease.CssOut)) + scaleOut(MenuSpring, 0.9f, origin),
        ) {
            // A list panel's (docs/ui-panels.md 小面板): each row's ground under the finger MENU_PAD from the edge,
            // rounded MENU_ROW, the menu's corner concentric with theirs; their words 16 from the edge.
            val corner = concentricOut(MENU_ROW, MENU_PAD)
            Column(Modifier.widthIn(min = width).width(width).shadow(18.dp, Smooth(corner)).clip(Smooth(corner)).background(C.surface).padding(MENU_PAD)) {
                current.items.forEachIndexed { i, item ->
                    Row(
                        Modifier.fillMaxWidth().clip(Smooth(MENU_ROW)).clickable { closed(); item.action() }.padding(horizontal = 16.dp - MENU_PAD, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(item.label, fontSize = 15.sp, color = C.ink)
                        item.icon?.let { IconIn(it, 16.dp) } ?: Box(Modifier.size(16.dp))
                    }
                }
            }
        }
    }
}

private val MENU_PAD = 6.dp
private val MENU_ROW = 14.dp

// ── a short note ───────────────────────────────────────────────────────

/**
 * What a toast says. A write its station did not answer may have been done (the core's `unconfirmed`, client/core-ts/src/
 * station/sync.ts): said as not known, whatever the page put before it ("没能固定：不确定做没做成：…" → "固定：不确定做没做成：…").
 */
fun said(message: String): String = Regex("^(?:没能|无法)([^：]*)：((?:不确定做没做成|无法确认是否成功)：)").replace(message, "$1：$2")
    .replace(Regex("^Couldn't ([^:]*): ((?:Unsure if it went through|Couldn't confirm it went through): )"), "$1: $2")

@Composable
fun ToastHost(toast: String?, done: () -> Unit) {
    val text = toast?.let(::said)
    LaunchedEffect(text) { if (text != null) { delay(2600); done() } }
    // Kept while it fades, so it fades with its words.
    var last by remember { mutableStateOf("") }
    if (text != null) last = text
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 90.dp), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(text != null, enter = fadeIn(tween(200, easing = Ease.Css)), exit = fadeOut(tween(200, easing = Ease.Css))) {
            Text(
                last, color = C.bg, fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = 24.dp).clip(Smooth(18.dp)).background(C.ink).padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    }
}

/** A page with one thing in full: what it is (a line, as the history labels it), then all of it. */
class ReaderSpec(val label: @Composable RowScope.() -> Unit, val content: @Composable () -> Unit)

/** The reader comes in from the side over everything; back (or ‹) returns to where it was opened. */
@Composable
fun ReaderHost(spec: ReaderSpec?, close: () -> Unit) {
    var shown by remember { mutableStateOf<ReaderSpec?>(null) }
    if (spec != null) shown = spec
    BackHandler(enabled = spec != null) { close() }
    // web mobile's mReader: translateX 100% → 0 and back, 300ms (.4, 0, .2, 1).
    val slide = tween<IntOffset>(300, easing = Ease.Standard)
    AnimatedVisibility(spec != null, enter = androidx.compose.animation.slideInHorizontally(slide) { it }, exit = androidx.compose.animation.slideOutHorizontally(slide) { it }) {
        val current = shown ?: return@AnimatedVisibility
        Column(
            Modifier.fillMaxSize().background(C.bg).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                .windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars),
        ) {
            Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 16.dp, top = 6.dp, bottom = 10.dp)) { NavBack(t("android-misc.reader.back")) { close() } }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { current.label(this) }
                current.content()
            }
        }
    }
}
