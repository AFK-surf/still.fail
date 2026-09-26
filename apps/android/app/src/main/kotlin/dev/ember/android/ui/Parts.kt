// The concept's small parts: model marks with their state badge, people's
// avatars, rings, toggles, segmented choices, navigation bars and list cards.
package dev.ember.android.ui

import kotlinx.coroutines.delay
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.alpha
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.rememberInfiniteTransition
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import dev.ember.android.R
import dev.ember.android.data.ChatState
import dev.ember.android.data.Creator
import dev.ember.android.data.Maker
import dev.ember.android.data.maker

// ── model marks ────────────────────────────────────────────────────────

@Composable
fun MakerIcon(model: String?, runtime: String, size: Dp, modifier: Modifier = Modifier) {
    val m = maker(model, runtime)
    val res = when (m) { Maker.OpenAI -> R.drawable.maker_openai; Maker.Anthropic -> R.drawable.maker_anthropic; Maker.Zhipu -> R.drawable.maker_zhipu; Maker.DeepSeek -> R.drawable.maker_deepseek }
    // OpenAI's and Anthropic's marks are one color: the ink of the page.
    val mono = m == Maker.OpenAI || m == Maker.Anthropic
    Image(painterResource(res), null, modifier.size(size), colorFilter = if (mono) ColorFilter.tint(C.ink) else null)
}

/** A state badge: solid orange = block, a still hollow orange ring = at work, red = failed; done has none. Nothing blinks. */
@Composable
internal fun Badge(state: ChatState, size: Dp, ring: Dp, around: Color, modifier: Modifier = Modifier) {
    val c = C
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2
        drawCircle(around, r)
        val inner = r - ring.toPx()
        when (state) {
            ChatState.Block -> drawCircle(c.accent, inner)
            ChatState.Failed -> drawCircle(c.red, inner)
            ChatState.Done -> {}
            ChatState.Running -> {
                val w = 2.5.dp.toPx().coerceAtMost(inner)
                drawCircle(c.accent, inner - w / 2, style = Stroke(w))
            }
        }
    }
}

/** An agent: its model maker's mark on a soft tile, with its state as a badge. */
@Composable
fun ModelMark(model: String?, runtime: String, size: Dp = 36.dp, state: ChatState? = null, around: Color = C.bg) {
    val xs = size < 30.dp
    Box(Modifier.size(size)) {
        Box(
            Modifier.size(size).clip(RoundedCornerShape(if (xs) 6.dp else 11.dp)).background(C.surface)
                .border(1.dp, C.line, RoundedCornerShape(if (xs) 6.dp else 11.dp)),
            contentAlignment = Alignment.Center,
        ) { MakerIcon(model, runtime, if (xs) size * 0.6f else size * 0.56f) }
        if (state != null && state != ChatState.Done) {
            val badge = if (xs) 11.dp else 15.dp
            Badge(state, badge, if (xs) 1.5.dp else 2.dp, around, Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp))
        }
    }
}

// ── people ─────────────────────────────────────────────────────────────

private val AVATAR = listOf(Color(0xFF5B7BB2), Color(0xFF2F8F5B), Color(0xFFB9471F), Color(0xFF8A6BB0), Color(0xFF3F8C99), Color(0xFFB0842F))

fun avatarColor(id: String): Color = AVATAR[Math.floorMod(id.lowercase().hashCode(), AVATAR.size)]

fun initial(name: String): String = name.trim().firstOrNull()?.uppercase() ?: "?"

@Composable
fun Avatar(id: String, name: String, size: Dp, modifier: Modifier = Modifier, picture: String? = null) {
    // Their picture (a Google account's) once it is here; their initial on their colour until then, or without one.
    val image = rememberPicture(picture)
    Box(modifier.size(size).clip(CircleShape).background(avatarColor(id)), contentAlignment = Alignment.Center) {
        if (image != null) androidx.compose.foundation.Image(image, name, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
        else Text(initial(name), color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = (size.value * 0.5f).sp, lineHeight = (size.value * 0.5f).sp)
    }
}

/** Pictures by URL, once each for the app's life. */
private val pictures = java.util.concurrent.ConcurrentHashMap<String, androidx.compose.ui.graphics.ImageBitmap>()

@Composable
private fun rememberPicture(url: String?): androidx.compose.ui.graphics.ImageBitmap? {
    val known = url?.let { pictures[it] }
    val loaded by androidx.compose.runtime.produceState(known, url) {
        if (url.isNullOrBlank() || value != null) return@produceState
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                java.net.URL(url).openStream().use { android.graphics.BitmapFactory.decodeStream(it) }?.asImageBitmap()
            } catch (_: java.io.IOException) {
                null
            }
        }?.also { pictures[url] = it }
    }
    return loaded
}

/** People overlapping a little, each ringed in the page's color. */
@Composable
fun PeopleStack(people: List<Creator>, size: Dp = 18.dp, ring: Color = C.bg) {
    Row {
        people.forEachIndexed { i, p ->
            Box(Modifier.offset(x = (-5 * i).dp).zIndex(-i.toFloat()).size(size + 3.dp).clip(CircleShape).background(ring), contentAlignment = Alignment.Center) {
                Avatar(p.id, p.name, size)
            }
        }
    }
}

// ── rings ──────────────────────────────────────────────────────────────

/** A percentage as a ring: green, amber past 65, red past 85. */
@Composable
fun Ring(percent: Int, label: String, size: Dp = 46.dp) {
    val c = C
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(size), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val w = 5.dp.toPx() * size.value / 46f
                val inset = w / 2 + 1.dp.toPx()
                val box = Size(this.size.width - inset * 2, this.size.height - inset * 2)
                drawArc(c.line, 0f, 360f, false, Offset(inset, inset), box, style = Stroke(w))
                val p = percent.coerceIn(0, 100)
                if (p > 0) drawArc(if (p > 85) c.red else if (p > 65) c.warn else c.green, -90f, 360f * p / 100, false, Offset(inset, inset), box, style = Stroke(w, cap = StrokeCap.Round))
            }
            Text("$percent", fontSize = if (size < 44.dp) 12.sp else 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        }
        Text(label, fontSize = 12.sp, color = C.muted)
    }
}

/**
 * An allowance as a ring, as the web draws it: what is left, eaten clockwise from the top as it is used; green, amber
 * from 70% used, red from 90%. The number is what is left, and a full one shows none.
 */
@Composable
fun QuotaRing(usedPercent: Double, size: Dp = 20.dp) {
    val c = C
    val used = usedPercent.roundToInt().coerceIn(0, 100)
    val left = 100 - used
    val tone = if (used >= 90) c.red else if (used >= 70) c.warn else c.green
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 2.dp.toPx()
            val inset = w / 2 + 0.5.dp.toPx()
            val box = Size(this.size.width - inset * 2, this.size.height - inset * 2)
            drawArc(c.line, 0f, 360f, false, Offset(inset, inset), box, style = Stroke(w))
            if (left > 0) drawArc(tone, -90f + used * 3.6f, 360f * left / 100, false, Offset(inset, inset), box, style = Stroke(w, cap = StrokeCap.Round))
        }
        if (left < 100) Text("$left", fontSize = (size.value * 0.42f).sp, lineHeight = (size.value * 0.42f).sp, fontWeight = FontWeight.SemiBold, color = C.ink)
    }
}

/** A window's short mark: 5H, 7D, W (weekly), M (monthly). */
fun quotaMark(label: String): Pair<String, Int> {
    if (label.startsWith("每月")) return "M" to 3
    if (label.startsWith("每周")) return "W" to 2
    Regex("^(\\d+) 小时").find(label)?.let { return "${it.groupValues[1]}H" to 0 }
    Regex("^(\\d+) 天").find(label)?.let { return "${it.groupValues[1]}D" to 1 }
    return label to 1
}

/** A profile's allowance in a line: every window, shortest first, a ring with its mark beside it. */
@Composable
fun QuotaRings(quota: dev.ember.android.data.ProfileQuota?) {
    val windows = quota?.takeIf { it.state == "ok" }?.windows.orEmpty().sortedBy { quotaMark(it.label).second }
    if (windows.isEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        windows.forEach { w ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                QuotaRing(w.usedPercent)
                Text(quotaMark(w.label).first, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = C.subtle)
            }
        }
    }
}

/** Whose service a profile runs on: Anthropic or OpenAI for a subscription or a key, OpenCode for OpenCode Go. */
@Composable
fun ProviderMark(runtime: String, kind: String?, size: Dp = 16.dp) {
    if (kind == "opencode-go") {
        val ink = C.ink
        Canvas(Modifier.size(size)) {
            val u = this.size.width / 24f
            drawRect(ink, Offset(6 * u, 4 * u), Size(12 * u, 16 * u), style = Stroke(2.4f * u))
        }
        return
    }
    MakerIcon(if (runtime == "claude" || kind == "anthropic-api") "claude" else "openai", runtime, size)
}

// ── controls ───────────────────────────────────────────────────────────

/** Whether the person asked for less motion (animations off in the system settings). */
@Composable
fun reducedMotion(): Boolean {
    val context = LocalContext.current
    return remember { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/**
 * A segmented choice: a track that tints whatever it sits on (the text colour
 * at 6%), and a light thumb that slides to the chosen option. Without `track`
 * what it sits in (a capsule) is its track.
 */
@Composable
fun Seg(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, height: Dp = 30.dp, fill: Boolean = false, radius: Dp = 10.dp, inset: Dp = 2.dp, track: Boolean = true) {
    // Where each option sits in the track, in px: (x, width).
    val places = remember(options) { mutableStateListOf(*Array(options.size) { 0f to 0f }) }
    val x = remember { Animatable(0f) }
    val w = remember { Animatable(0f) }
    val still = reducedMotion()
    val (tx, tw) = places.getOrElse(selected) { 0f to 0f }
    LaunchedEffect(tx, tw) {
        if (tw == 0f) return@LaunchedEffect
        // The first placement and reduced motion jump; a change of choice slides.
        if (w.value == 0f || still) { x.snapTo(tx); w.snapTo(tw); return@LaunchedEffect }
        val ease = tween<Float>(240, easing = CubicBezierEasing(0f, 0f, 0.2f, 1f))
        launch { x.animateTo(tx, ease) }
        w.animateTo(tw, ease)
    }
    val density = LocalDensity.current
    val thumbShape = RoundedCornerShape((radius - inset).coerceAtLeast(0.dp))
    Box(modifier.height(height).clip(RoundedCornerShape(radius)).let { if (track) it.background(C.ink.copy(alpha = 0.06f)) else it }.padding(inset)) {
        if (w.value > 0f) Box(
            Modifier.offset { IntOffset(x.value.roundToInt(), 0) }.width(with(density) { w.value.toDp() }).fillMaxHeight().let {
                // In a capsule, a soft tint of the text colour: the capsule's glass shows through it. On a track, a light
                // thumb with a hairline all round, not an elevation shadow (which falls below and makes it look low).
                if (!track) it.background(C.ink.copy(alpha = if (C.dark) 0.13f else 0.08f), thumbShape)
                else it.background(if (C.dark) Color(0xFF3A3B40) else Color.White, thumbShape).border(0.5.dp, C.line, thumbShape)
            },
        )
        Row(Modifier.fillMaxHeight().let { if (fill) it.fillMaxWidth() else it }) {
            options.forEachIndexed { i, label ->
                Box(
                    Modifier.let { if (fill) it.weight(1f) else it }.fillMaxHeight()
                        .onPlaced { places[i] = it.positionInParent().x to it.size.width.toFloat() }
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onSelect(i) }
                        .padding(horizontal = if (fill) 12.dp else 10.dp),
                    contentAlignment = Alignment.Center,
                ) { Text(label, fontSize = if (fill) 14.sp else 13.sp, fontWeight = if (i == selected && !track) FontWeight.SemiBold else null, color = if (i == selected) C.ink else C.muted, maxLines = 1) }
            }
        }
    }
}

@Composable
fun IconIn(icon: ImageVector, size: Dp = 18.dp, tint: Color = C.ink, modifier: Modifier = Modifier) = Icon(icon, null, modifier.size(size), tint = tint)

// ── navigation ─────────────────────────────────────────────────────────

/** Back, in the accent color, with where it goes back to. */
@Composable
fun NavBack(label: String, onClick: () -> Unit) {
    Row(Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(end = 6.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconIn(Icons.Back, 22.dp, C.accent)
        Text(label, fontSize = 17.sp, color = C.accent)
    }
}

/** A round chip-colored button in a bar. */
@Composable
fun NavButton(icon: ImageVector, onClick: () -> Unit, iconSize: Dp = 18.dp) {
    // The icon alone, no disc behind it: a bar's buttons are quiet.
    Box(Modifier.size(34.dp).clip(CircleShape).clickable(onClick = onClick), contentAlignment = Alignment.Center) { IconIn(icon, iconSize) }
}

/** A page's compact bar: back, a centered title, and one action. No line under it: the page's paper runs on. */
@Composable
fun NavBar(back: String, onBack: () -> Unit, title: String, sub: (@Composable RowScope.() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().background(C.bg).windowInsetsPadding(WindowInsets.statusBars)) {
        Box(Modifier.fillMaxWidth().padding(start = 10.dp, end = 16.dp, top = 6.dp, bottom = 10.dp)) {
            Box(Modifier.align(Alignment.CenterStart)) { NavBack(back, onBack) }
            Column(Modifier.align(Alignment.Center).padding(horizontal = 84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                if (sub != null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp), content = sub)
            }
            if (trailing != null) Box(Modifier.align(Alignment.CenterEnd)) { trailing() }
        }
    }
}

/** A page's large title (stations, settings): a small line over a big word. */
@Composable
fun LargeTitle(small: String, big: String) {
    Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp)) {
        Text(small, fontSize = 13.sp, color = C.muted)
        Text(big, fontSize = 32.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.6).sp)
    }
}

// ── lists and cards ────────────────────────────────────────────────────

@Composable
fun SectionHeader(title: String, trailing: String? = null, start: Dp = 20.dp) {
    Row(Modifier.fillMaxWidth().padding(start = start, end = 20.dp, top = 14.dp, bottom = 6.dp), verticalAlignment = Alignment.Bottom) {
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, fontSize = 13.sp, color = C.muted)
    }
}

@Composable
fun Card(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(C.surface)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 16.dp, vertical = 14.dp),
        content = content,
    )
}

/** Rows on one rounded card; the card groups them, no lines between. */
@Composable
fun ListCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface), content = content)
}

@Composable
fun ListRow(onClick: (() -> Unit)? = null, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}

/** Something is on its way: said in words, centered on the page. */
@Composable
fun Loading(text: String) {
    Box(Modifier.fillMaxSize().background(C.bg).padding(32.dp), contentAlignment = Alignment.Center) {
        Text(text, color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center)
    }
}

/**
 * The app starting (or waiting for what every page needs): the buddy, floating. What it waits for is said only when
 * it takes a while (after a second), or at once when `now` (a failure).
 */
@Composable
fun Splash(label: String? = null, now: Boolean = false) {
    val still = reducedMotion()
    val float = rememberInfiniteTransition(label = "splash")
    val lift by float.animateFloat(0f, 1f, infiniteRepeatable(tween(900, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "lift")
    var shown by remember { mutableStateOf(now) }
    LaunchedEffect(now) { if (!now) { delay(1000); shown = true } else shown = true }
    Column(Modifier.fillMaxSize().background(C.bg).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
        val px = with(LocalDensity.current) { 5.dp.toPx() }
        Box(Modifier.graphicsLayer { translationY = if (still) 0f else -lift * px }) { Mark(56.dp) }
        if (label != null) Text(label, color = C.muted, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.alpha(if (shown) 1f else 0f))
    }
}

@Composable
fun Mark(size: Dp = 14.dp) = Image(painterResource(if (C.dark) R.drawable.ember_mark_dark else R.drawable.ember_mark), null, Modifier.size(size))

@Composable
fun SlackMark(size: Dp = 13.dp) = Image(painterResource(R.drawable.slack), null, Modifier.size(size))

@Composable
fun Illustration(light: Int, dark: Int, width: Dp) = Image(painterResource(if (C.dark) dark else light), null, Modifier.width(width))

