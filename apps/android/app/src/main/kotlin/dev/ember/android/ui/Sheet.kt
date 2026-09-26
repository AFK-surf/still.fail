// What lies over the pages: one sheet from the bottom at a time (dragged by
// its grabber between half and full height, or down to close), a message's
// long-press menu, and a short note.
package dev.ember.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.gestures.detectVerticalDragGestures
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
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val Ease = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)

/** A sheet: how much of the screen it takes at first, and whether its grabber drags it. */
class SheetSpec(val height: Float, val draggable: Boolean = false, val content: @Composable ColumnScope.() -> Unit)

/** Drags the open sheet by its grabber. */
class SheetDrag(val draggable: Boolean, val drag: (Float) -> Unit, val release: () -> Unit, val tap: () -> Unit)

private val LocalSheetDrag = staticCompositionLocalOf<SheetDrag?> { null }

@Composable
fun SheetHost(app: AppState) {
    val spec = app.sheet
    var shown by remember { mutableStateOf<SheetSpec?>(null) }
    if (spec != null && shown !== spec) shown = spec
    BackHandler(enabled = spec != null) { app.sheet = null }
    val current = shown ?: return
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val total = constraints.maxHeight.toFloat()
        val density = LocalDensity.current
        val height = remember { Animatable(current.height * total) }
        val offset = remember { Animatable(total) }
        val scope = rememberCoroutineScope()
        val scrim by animateFloatAsState(if (spec != null) 1f else 0f, tween(300), label = "scrim")
        LaunchedEffect(spec) {
            if (spec != null) {
                val target = spec.height * total
                if (offset.value > 1f) {
                    height.snapTo(target)
                    offset.animateTo(0f, tween(380, easing = Ease))
                } else {
                    height.animateTo(target, tween(320, easing = Ease))
                }
            } else {
                offset.animateTo(height.value, tween(300, easing = Ease))
                shown = null
            }
        }
        val min = with(density) { 120.dp.toPx() }
        // One per sheet: a new one would restart the grabber's gesture halfway through a drag.
        val drag = remember(current, total) { SheetDrag(
            draggable = current.draggable,
            drag = { dy -> scope.launch { height.snapTo((height.value - dy).coerceIn(min, total * 0.94f)) } },
            release = {
                val f = height.value / total
                if (f < 0.3f) app.sheet = null
                else scope.launch { height.animateTo(if (f > 0.72f) total * 0.94f else total * 0.55f, tween(320, easing = Ease)) }
            },
            tap = { scope.launch { height.animateTo(if (height.value > total * 0.9f) total * 0.55f else total * 0.94f, tween(320, easing = Ease)) } },
        ) }
        Box(
            Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f * scrim))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { app.sheet = null },
        )
        Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(with(density) { height.value.toDp() })
                .offset { IntOffset(0, offset.value.toInt()) }
                .shadow(24.dp, RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp))
                .clip(RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)).background(C.surface)
                .pointerInput(Unit) { detectTapGestures { } }
                .windowInsetsPadding(WindowInsets.navigationBars),
        ) {
            CompositionLocalProvider(LocalSheetDrag provides drag) { current.content(this) }
        }
    }
}

/** The sheet's grabber: drags a draggable sheet, and a tap switches it between half and full. */
@Composable
fun SheetGrab() {
    val drag = LocalSheetDrag.current
    Box(
        Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp).let { m ->
            if (drag?.draggable == true) m.pointerInput(drag) {
                detectVerticalDragGestures(onDragEnd = { drag.release() }, onDragCancel = { drag.release() }) { change, dy -> change.consume(); drag.drag(dy) }
            }.pointerInput(drag) { detectTapGestures { drag.tap() } } else m
        }.padding(vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) { Box(Modifier.size(38.dp, 5.dp).clip(RoundedCornerShape(3.dp)).background(C.line)) }
}

@Composable
fun SheetHead(title: String, trailing: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

// ── the long-press menu ────────────────────────────────────────────────

class MenuItem(val label: String, val icon: ImageVector, val action: () -> Unit)
class MenuSpec(val anchor: Rect, val items: List<MenuItem>, val onDismiss: () -> Unit = {})

@Composable
fun MenuHost(app: AppState) {
    val spec = app.menu
    var shown by remember { mutableStateOf<MenuSpec?>(null) }
    if (spec != null) shown = spec
    val current = shown ?: return
    val close = { current.onDismiss(); app.menu = null }
    BackHandler(enabled = spec != null) { close() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val scrim by animateFloatAsState(if (spec != null) 1f else 0f, tween(200), label = "menu-scrim", finishedListener = { if (spec == null) shown = null })
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.28f * scrim)).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() })
        val width = 180.dp
        val x = with(density) { current.anchor.left.toDp() }.coerceAtMost(maxWidth - width - 12.dp).coerceAtLeast(12.dp)
        // Under the message, or over it when there is no room below.
        val menuHeight = 45.dp * current.items.size
        val below = with(density) { current.anchor.bottom.toDp() } + 6.dp
        val y = if (below + menuHeight < maxHeight - 24.dp) below else (with(density) { current.anchor.top.toDp() } - menuHeight - 6.dp).coerceAtLeast(24.dp)
        AnimatedVisibility(
            spec != null,
            Modifier.offset(x, y),
            enter = fadeIn(tween(200)) + scaleIn(tween(200), 0.9f, TransformOrigin(0f, 0f)),
            exit = fadeOut(tween(150)) + scaleOut(tween(150), 0.9f, TransformOrigin(0f, 0f)),
        ) {
            Column(Modifier.widthIn(min = width).width(width).shadow(18.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp)).background(C.surface)) {
                current.items.forEachIndexed { i, item ->
                    Row(
                        Modifier.fillMaxWidth().clickable { app.menu = null; item.action() }.padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(item.label, fontSize = 15.sp, color = C.ink)
                        IconIn(item.icon, 16.dp)
                    }
                }
            }
        }
    }
}

// ── a short note ───────────────────────────────────────────────────────

@Composable
fun ToastHost(app: AppState) {
    val text = app.toast
    LaunchedEffect(text) { if (text != null) { delay(2600); app.toast = null } }
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 90.dp), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(text != null, enter = fadeIn(), exit = fadeOut()) {
            Text(
                text ?: "", color = C.bg, fontSize = 14.sp,
                modifier = Modifier.padding(horizontal = 24.dp).clip(RoundedCornerShape(18.dp)).background(C.ink).padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    }
}

/** A page with one thing in full: what it is (a line, as the history labels it), then all of it. */
class ReaderSpec(val label: @Composable RowScope.() -> Unit, val content: @Composable () -> Unit)

/** The reader comes in from the side over everything; back (or ‹) returns to where it was opened. */
@Composable
fun ReaderHost(app: AppState) {
    val spec = app.reader
    var shown by remember { mutableStateOf<ReaderSpec?>(null) }
    if (spec != null) shown = spec
    BackHandler(enabled = spec != null) { app.reader = null }
    AnimatedVisibility(spec != null, enter = androidx.compose.animation.slideInHorizontally { it }, exit = androidx.compose.animation.slideOutHorizontally { it }) {
        val current = shown ?: return@AnimatedVisibility
        Column(
            Modifier.fillMaxSize().background(C.bg).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                .windowInsetsPadding(WindowInsets.statusBars).windowInsetsPadding(WindowInsets.navigationBars),
        ) {
            Row(Modifier.fillMaxWidth().padding(start = 10.dp, end = 16.dp, top = 6.dp, bottom = 10.dp)) { NavBack("执行历史") { app.reader = null } }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { current.label(this) }
                current.content()
            }
        }
    }
}
