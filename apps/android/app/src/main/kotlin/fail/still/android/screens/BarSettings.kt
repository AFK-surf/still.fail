// 设置 · 下方栏: this device's bottom bars (Places.kt, ui/Bar.kt), each a card of its places (up to four), as the
// prototype has it (barSettings): a place taken out with the "−" at its corner, one added from a sheet of all of them,
// a place held and moved sideways to change its order; a bar made the one in view, deleted, or a new one made.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import fail.still.android.AppState
import fail.still.android.BAR_SIZE
import fail.still.android.LocalApp
import fail.still.android.PLACES
import fail.still.android.PlaceIcon
import fail.still.android.placeLabel
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import kotlin.math.roundToInt
import fail.still.android.ui.PickRow

/** What the settings' row says of the bars: how many, or the one bar's places. */
fun barsValue(app: AppState): String {
    val sets = app.bars.sets
    return if (sets.size > 1) t("android-misc.bar.count", "n" to sets.size) else sets.first().joinToString(t("android-misc.bar.sep")) { placeLabel(it) }
}

/**
 * The bars kept whole: an empty one dropped (the core keeps none), the one in view still the same bar after it (or,
 * when it is the one dropped, the next).
 */
private fun save(app: AppState, sets: List<List<String>>, current: Int) {
    var c = current
    val kept = ArrayList<List<String>>()
    sets.forEachIndexed { i, s -> if (s.isEmpty()) { if (i < current) c-- } else kept += s }
    app.setBars(kept, c)
}

@Composable
fun BarSettingsScreen() {
    val app = LocalApp.current
    val bars = app.bars
    val cur = bars.current.toInt()
    // A bar just made, empty until a place is added to it (the core keeps no empty bar): on this page only.
    var adding by rememberSaveable { mutableStateOf(false) }
    val sets = bars.sets + if (adding) listOf(emptyList()) else emptyList()
    fun pickFor(i: Int) = openPick(app, i) { place ->
        if (i >= bars.sets.size) { adding = false; save(app, app.bars.sets + listOf(listOf(place)), cur) }
        else save(app, app.bars.sets.mapIndexed { n, s -> if (n == i && place !in s && s.size < BAR_SIZE) s + place else s }, app.bars.current.toInt())
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle(t("android-misc.bar.small"), t("android-misc.bar.title"))
        PageNote(t("android-misc.bar.note"))
        sets.forEachIndexed { i, set ->
            val made = i < bars.sets.size
            Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("android-misc.bar.set", "n" to i + 1), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                if (made && i == cur) Text(
                    t("android-misc.bar.current"), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = C.accent,
                    modifier = Modifier.padding(start = 8.dp).clip(RoundedCornerShape(50)).background(C.accentBg).padding(horizontal = 7.dp, vertical = 1.dp),
                )
                Spacer(Modifier.weight(1f))
                if (made && i != cur) Text(t("android-misc.bar.use"), fontSize = 13.sp, color = C.accent, modifier = Modifier.clip(Smooth(6.dp)).clickable { save(app, bars.sets, i) }.padding(4.dp))
                if (sets.size > 1) Text(
                    t("android-misc.bar.delete"), fontSize = 13.sp, color = C.red,
                    modifier = Modifier.padding(start = 10.dp).clip(Smooth(6.dp)).clickable {
                        if (!made) { adding = false; return@clickable }
                        val left = bars.sets.filterIndexed { n, _ -> n != i }
                        save(app, left, if (cur > i || cur >= left.size) (cur - 1).coerceAtLeast(0) else cur)
                    }.semantics { contentDescription = t("android-misc.bar.deleteNamed", "n" to i + 1) }.padding(4.dp),
                )
            }
            BarCard(app, i, set, only = bars.sets.size == 1 && set.size == 1, onAdd = { pickFor(i) }) { from, to ->
                if (from == to) return@BarCard
                val moved = set.toMutableList().apply { add(to, removeAt(from)) }
                save(app, bars.sets.mapIndexed { n, s -> if (n == i) moved else s }, cur)
            }
        }
        ListCard(Modifier.padding(top = 14.dp)) {
            ListRow(onClick = { adding = true; pickFor(bars.sets.size) }) {
                IconIn(Icons.Plus, 20.dp, C.accent)
                Text(t("android-misc.bar.new"), fontSize = 15.sp, color = C.accent, modifier = Modifier.weight(1f))
            }
        }
        PageNote(if (bars.sets.size > 1) t("android-misc.bar.foot.many") else t("android-misc.bar.foot.one"))
        Spacer(Modifier.height(30.dp))
    }
}

/** The same, but a touch target is only as big as what is drawn (the "−" at a place's corner, over the place). */
private fun ViewConfiguration.exact(): ViewConfiguration = object : ViewConfiguration by this {
    override val minimumTouchTargetSize: DpSize get() = DpSize.Zero
}

/**
 * A bar's card: its places in four slots, each its icon over its name with a "−" at its corner (none on the last
 * place of the only bar: a bar is never empty), and, with room left, a slot that adds one. A place held and moved
 * sideways goes where it is let go (by how many slots it moved).
 */
@Composable
private fun BarCard(app: AppState, i: Int, set: List<String>, only: Boolean, onAdd: () -> Unit, onMove: (Int, Int) -> Unit) {
    BoxWithConstraints(Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth().clip(Smooth(20.dp)).background(C.surface).padding(horizontal = 4.dp, vertical = 8.dp)) {
        val slot = maxWidth / BAR_SIZE
        val move by androidx.compose.runtime.rememberUpdatedState(onMove)
        Row(Modifier.fillMaxWidth()) {
            set.forEachIndexed { j, key ->
                var dx by remember(key) { mutableFloatStateOf(0f) }
                var lifted by remember(key) { mutableStateOf(false) }
                val slotPx = with(androidx.compose.ui.platform.LocalDensity.current) { slot.toPx() }
                Box(
                    Modifier.width(slot).zIndex(if (lifted) 2f else 0f)
                        .graphicsLayer { translationX = dx; val s = if (lifted) 1.08f else 1f; scaleX = s; scaleY = s }
                        .then(if (lifted) Modifier.shadow(6.dp, Smooth(16.dp), ambientColor = Color.Black.copy(alpha = 0.14f), spotColor = Color.Black.copy(alpha = 0.14f)).clip(Smooth(16.dp)).background(C.surface) else Modifier)
                        .pointerInput(key, j, set.size) {
                            detectHorizontalDragGestures(
                                onDragStart = { lifted = true; dx = 0f },
                                onDragEnd = {
                                    val to = (j + (dx / slotPx).roundToInt()).coerceIn(0, set.size - 1)
                                    lifted = false; dx = 0f
                                    move(j, to)
                                },
                                onDragCancel = { lifted = false; dx = 0f },
                            ) { change, amount -> change.consume(); dx += amount }
                        }
                        .semantics {
                            testTag = "bar-slot-$i-$key"
                            contentDescription = placeLabel(key)
                            customActions = listOfNotNull(
                                if (j > 0) CustomAccessibilityAction(t("android-misc.bar.moveLeft")) { move(j, j - 1); true } else null,
                                if (j < set.size - 1) CustomAccessibilityAction(t("android-misc.bar.moveRight")) { move(j, j + 1); true } else null,
                            )
                        }
                        .padding(top = 12.dp, bottom = 10.dp),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(Modifier.height(30.dp), contentAlignment = Alignment.Center) { PlaceIcon(key, C.ink, Still) }
                        Text(placeLabel(key), fontSize = 12.sp, color = C.muted, maxLines = 1)
                    }
                    if (!only) CompositionLocalProvider(LocalViewConfiguration provides LocalViewConfiguration.current.exact()) {
                        Box(
                            Modifier.align(Alignment.TopCenter).offset(x = 16.dp, y = (-8).dp).size(20.dp).clip(CircleShape).background(C.chip)
                                .clickable { save(app, app.bars.sets.mapIndexed { n, s -> if (n == i) s - key else s }, app.bars.current.toInt()) }
                                .semantics { contentDescription = t("android-misc.bar.remove", "name" to placeLabel(key)); testTag = "bar-remove-$i-$key" },
                            contentAlignment = Alignment.Center,
                        ) { IconIn(Icons.Minus, 12.dp, C.muted) }
                    }
                }
            }
            if (set.size < BAR_SIZE) Box(
                Modifier.width(slot).clip(Smooth(16.dp)).clickable(onClick = onAdd).semantics { testTag = "bar-add-$i" }.padding(top = 12.dp, bottom = 10.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(30.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.size(44.dp).border(1.5.dp, C.line, CircleShape), contentAlignment = Alignment.Center) { IconIn(Icons.Plus, 22.dp, C.subtle) }
                    }
                    Text(t("android-misc.bar.add"), fontSize = 12.sp, color = C.subtle, maxLines = 1)
                }
            }
        }
    }
}

/** The places to add to bar `i` (its number as said): all of them, those in it already greyed ("已在这一栏"), none when it is full. */
private fun openPick(app: AppState, i: Int, picked: (String) -> Unit) {
    // Rows with a line under them ("已在这一栏") are taller: room for every row as one, scrolled if the screen is short.
    app.sheet = SheetSpec(0.6f, fit = (90 + PLACES.size * 66).dp) {
        SheetGrab()
        val set = app.bars.sets.getOrNull(i).orEmpty()
        val full = set.size >= BAR_SIZE
        SheetHead(t("android-misc.bar.pick.title", "n" to i + 1), trailing = {
            Text(if (full) t("android-misc.bar.pick.full") else t("android-misc.bar.pick.left", "n" to BAR_SIZE - set.size), fontSize = 13.sp, color = C.muted)
        }, lead = null)
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) { PLACES.forEach { key ->
            val there = key in set
            PickRow(
                placeLabel(key), sub = if (there) t("android-misc.bar.pick.there") else null, enabled = !there && !full,
                leading = { Box(Modifier.size(28.dp).graphicsLayer { alpha = if (there || full) 0.4f else 1f }, contentAlignment = Alignment.Center) { PlaceIcon(key, C.ink, Still) } },
            ) { app.sheet = null; picked(key) }
        } }
    }
}

/** The stations' icon where no station is meant (the settings' cards, the picker): one station on, as the web's. */
private val Still = fail.still.android.ui.GlyphCounts(1, 0, 0, 0, false)
