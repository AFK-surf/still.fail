// The concept's small parts: model marks with their state badge, people's
// avatars, rings, toggles, segmented choices, navigation bars and list cards.
package fail.still.android.ui

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
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
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
import androidx.compose.foundation.layout.widthIn
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
import fail.still.android.R
import fail.still.android.data.ChatState
import fail.still.android.data.Person
import fail.still.android.data.Maker

// ── model marks ────────────────────────────────────────────────────────

private val MAKER_MARKS = mapOf(
    "anthropic" to R.drawable.maker_anthropic, "openai" to R.drawable.maker_openai, "deepseek" to R.drawable.maker_deepseek,
    "qwen" to R.drawable.maker_qwen, "zhipu" to R.drawable.maker_zhipu, "gemini" to R.drawable.maker_gemini,
    "kimi" to R.drawable.maker_kimi, "minimax" to R.drawable.maker_minimax, "xai" to R.drawable.maker_xai,
    "mistral" to R.drawable.maker_mistral,
    "xiaomi" to R.drawable.maker_xiaomi,
    "ant-ling" to R.drawable.maker_ant_ling,
    "openrouter" to R.drawable.maker_openrouter,
    "vercel" to R.drawable.maker_vercel,
    "cloudflare" to R.drawable.maker_cloudflare,
    "azure" to R.drawable.maker_azure,
    "groq" to R.drawable.maker_groq,
    "together" to R.drawable.maker_together,
    "fireworks" to R.drawable.maker_fireworks,
    "cerebras" to R.drawable.maker_cerebras,
    "huggingface" to R.drawable.maker_huggingface,
    "nvidia" to R.drawable.maker_nvidia,
    "baseten" to R.drawable.maker_baseten,
)

/** Marks of one colour, drawn in the page's ink. */
private val MONO = setOf("anthropic", "openai", "kimi", "xai", "mistral", "xiaomi", "ant-ling", "openrouter", "vercel", "cloudflare", "azure", "groq", "together", "fireworks", "cerebras", "huggingface", "nvidia", "baseten")

/** The mark of the company that made a model (the core says which); for one it does not know, its runtime's maker's. */
@Composable
fun MakerIcon(maker: Maker?, runtime: String?, size: Dp, modifier: Modifier = Modifier) {
    val id = maker?.id?.takeIf { it in MAKER_MARKS } ?: if (runtime == "codex") "openai" else "anthropic"
    Image(painterResource(MAKER_MARKS.getValue(id)), maker?.name, modifier.size(size), colorFilter = if (id in MONO) ColorFilter.tint(C.ink) else null)
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

/**
 * An agent's state at its mark's corner in the chat list's colours (web ui.css.ts agentMark, ChatMark.css.ts): a 12dp
 * disc of the ground, red in it when it wants someone (blocked, failed), at work a turning yellow 8dp ring with a faint
 * quarter; nothing when done. No halo: the mark is small.
 */
@Composable
internal fun AgentStateMark(state: ChatState, around: Color, modifier: Modifier = Modifier) {
    if (state == ChatState.Done) return
    val turn = if (state == ChatState.Running && !reducedMotion()) rememberInfiniteTransition(label = "agent-mark")
        .animateFloat(0f, 360f, infiniteRepeatable(tween(1200, easing = androidx.compose.animation.core.LinearEasing)), label = "turn").value else 0f
    Canvas(modifier.size(12.dp)) {
        val r = size.minDimension / 2
        val ring = 2.dp.toPx()
        drawCircle(around, r)
        if (state == ChatState.Running) {
            // The web's 8px box with a 2px border: the stroke's middle 3px from the centre.
            val rr = r - ring - ring / 2
            val at = androidx.compose.ui.geometry.Offset(center.x - rr, center.y - rr)
            val box = androidx.compose.ui.geometry.Size(rr * 2, rr * 2)
            drawArc(AGENT_YELLOW.copy(alpha = 0.25f), 0f, 360f, false, at, box, style = Stroke(ring))
            // Round ends (web: styles/busyRing.ts), the arc shortened by the half stroke they add so the gap stays a quarter.
            val cap = Math.toDegrees((ring / box.width).toDouble()).toFloat()
            drawArc(AGENT_YELLOW, turn + 45f + cap, 270f - 2 * cap, false, at, box, style = Stroke(ring, cap = StrokeCap.Round))
        } else drawCircle(AGENT_RED, r - ring)
    }
}

private val AGENT_RED = Color(0xFFE5484D)
private val AGENT_YELLOW = Color(0xFFF2B01E)

/** An agent: its model maker's mark on a soft tile, with its state as a badge. */
@Composable
fun ModelMark(maker: Maker?, runtime: String, size: Dp = 36.dp, state: ChatState? = null, around: Color = C.bg, listMark: Boolean = false) {
    val xs = size < 30.dp
    Box(Modifier.size(size)) {
        Box(
            Modifier.size(size).clip(RoundedCornerShape(if (xs) 6.dp else 11.dp)).background(C.surface)
                .border(1.dp, C.line, RoundedCornerShape(if (xs) 6.dp else 11.dp)),
            contentAlignment = Alignment.Center,
        ) { MakerIcon(maker, runtime, if (xs) size * 0.6f else size * 0.56f) }
        if (listMark) { if (state != null) AgentStateMark(state, around, Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp)) }
        else if (state != null && state != ChatState.Done) {
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

/** Pictures by URL as drawn, once each for the app's life (the core fetches and keeps their bytes: `picture`). */
private val pictures = java.util.concurrent.ConcurrentHashMap<String, androidx.compose.ui.graphics.ImageBitmap>()

@Composable
private fun rememberPicture(url: String?): androidx.compose.ui.graphics.ImageBitmap? {
    val core = LocalUi.current.core
    val known = url?.let { pictures[it] }
    val loaded by androidx.compose.runtime.produceState(known, url) {
        if (url.isNullOrBlank() || value != null) return@produceState
        val bytes = try {
            val answer = core.call("picture", kotlinx.serialization.json.buildJsonObject { put("url", kotlinx.serialization.json.JsonPrimitive(url)) })
            android.util.Base64.decode((answer as kotlinx.serialization.json.JsonObject)["bytes"]!!.let { (it as kotlinx.serialization.json.JsonPrimitive).content }, android.util.Base64.DEFAULT)
        } catch (_: fail.still.core.CoreException) {
            null
        } ?: return@produceState
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
        }?.also { pictures[url] = it }
    }
    return loaded
}

/** People overlapping a little, each ringed in the page's color. */
@Composable
fun PeopleStack(people: List<Person>, size: Dp = 18.dp, ring: Color = C.bg) {
    Row {
        people.forEachIndexed { i, p ->
            Box(Modifier.offset(x = (-5 * i).dp).zIndex(-i.toFloat()).size(size + 3.dp).clip(CircleShape).background(ring), contentAlignment = Alignment.Center) {
                Avatar(p.id, p.shown.display, size, picture = p.shown.picture)
            }
        }
    }
}

// ── rings ──────────────────────────────────────────────────────────────

/** How full, as a colour: the core's level (ok | amber | red). */
private fun levelColor(c: StillFailColors, level: String): Color = when (level) { "red" -> c.red; "amber" -> c.warn; "progress" -> c.accent; else -> c.green }

/**
 * An allowance as a ring, as the web draws it: what is left, eaten clockwise from the top as it is used; coloured by
 * the core's level. The number is what is left, and a full one shows none.
 */
@Composable
fun QuotaRing(left: Long, level: String, size: Dp = 20.dp) {
    val c = C
    val used = 100 - left
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 2.dp.toPx()
            val inset = w / 2 + 0.5.dp.toPx()
            val box = Size(this.size.width - inset * 2, this.size.height - inset * 2)
            drawArc(c.line, 0f, 360f, false, Offset(inset, inset), box, style = Stroke(w))
            if (left > 0) drawArc(levelColor(c, level), -90f + used * 3.6f, 360f * left / 100, false, Offset(inset, inset), box, style = Stroke(w, cap = StrokeCap.Round))
        }
        if (left < 100) Text("$left", fontSize = (size.value * 0.42f).sp, lineHeight = (size.value * 0.42f).sp, fontWeight = FontWeight.SemiBold, color = C.ink)
    }
}

/** A profile's allowance in a line: the web's chips (QuotaChips), one per window. */
@Composable
fun QuotaRings(quota: fail.still.android.data.Quota?) = QuotaChips(quota)

/**
 * A profile's allowance, compact, as the web's QuotaBars draws it: a rounded box per window (shortest first) with what
 * is left written in it (its mark too when there is more than one), its edge drawn as far as is left, clockwise from
 * the top left. Its number grey while there is plenty, in its colour once it runs low. `small`: a lower line.
 */
@Composable
fun QuotaChips(quota: fail.still.android.data.Quota?, small: Boolean = false) {
    val windows = quota?.takeIf { it.state == "ok" }?.windows.orEmpty()
    if (windows.isEmpty()) return
    val lone = windows.size == 1
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        windows.forEach { w -> EdgeChip(w.left, w.level, if (lone) null else w.mark, small) }
    }
}

/**
 * A machine's CPU, memory and disk as an allowance's boxes are drawn (QuotaChips): each its name and how full, its edge
 * drawn as far as that. `alerts`: only the ones running low, each saying what is left, as the web's station cards do.
 */
@Composable
fun MeterChips(meters: List<fail.still.android.data.Meter>, modifier: Modifier = Modifier, alerts: Boolean = false) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        meters.filter { !alerts || it.level != "ok" }.forEach { m -> EdgeChip(m.percent, m.level, m.short, text = if (alerts) m.remaining else null) }
    }
}

/** How much of what a runtime's install downloads is in: the allowance's rounded box, its edge going round as it comes. As the web's DownloadChip (Versions.tsx). */
@Composable
fun DownloadChip(percent: Long) = EdgeChip(percent, "progress", null)

/**
 * A rounded box with a figure in it (`text`, or how full; its mark before it, when given) and its edge drawn as far as `fill` (0–100),
 * clockwise from the top left, in the colour of the core's level; the figure grey while it is ok, in that colour once
 * it is not. Level `progress`: a download's share, in the accent, its edge moving smoothly to each new one. As the
 * web's EdgeChip (components.tsx).
 */
@Composable
private fun EdgeChip(fill: Long, level: String, mark: String?, small: Boolean = false, text: String? = null) {
    val c = C
    val tone = levelColor(c, level)
    val low = level == "amber" || level == "red"
    val drawn by animateFloatAsState(fill.coerceIn(0L, 100L).toFloat(), if (level == "progress") tween(500) else snap(), label = "edge")
    Box(Modifier.height(if (small) 16.dp else 20.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.matchParentSize()) {
            val sw = (if (small) 2.dp else 2.5.dp).toPx()
            val inset = sw / 2
            val r = 6.dp.toPx() - inset
            val x0 = inset; val y0 = inset; val x1 = size.width - inset; val y1 = size.height - inset
            // As an SVG <rect> is stroked: from the top edge's start, clockwise.
            val path = androidx.compose.ui.graphics.Path().apply {
                moveTo(x0 + r, y0); lineTo(x1 - r, y0)
                arcTo(androidx.compose.ui.geometry.Rect(x1 - 2 * r, y0, x1, y0 + 2 * r), -90f, 90f, false)
                lineTo(x1, y1 - r)
                arcTo(androidx.compose.ui.geometry.Rect(x1 - 2 * r, y1 - 2 * r, x1, y1), 0f, 90f, false)
                lineTo(x0 + r, y1)
                arcTo(androidx.compose.ui.geometry.Rect(x0, y1 - 2 * r, x0 + 2 * r, y1), 90f, 90f, false)
                lineTo(x0, y0 + r)
                arcTo(androidx.compose.ui.geometry.Rect(x0, y0, x0 + 2 * r, y0 + 2 * r), 180f, 90f, false)
                close()
            }
            drawPath(path, c.line, style = Stroke(sw))
            val p = drawn
            if (p > 0f) {
                val measure = androidx.compose.ui.graphics.PathMeasure().apply { setPath(path, false) }
                val part = androidx.compose.ui.graphics.Path()
                measure.getSegment(0f, measure.length * p / 100f, part, true)
                drawPath(part, tone, style = Stroke(sw, cap = StrokeCap.Round))
            }
        }
        Row(Modifier.padding(horizontal = if (small) 5.dp else 7.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val fs = if (small) 10.sp else 11.sp
            // On one baseline: a mark in Chinese (内存) sits lower in its line than figures do.
            if (mark != null) Text(mark, Modifier.alignByBaseline(), fontSize = fs, lineHeight = fs, fontWeight = FontWeight.SemiBold, color = C.muted)
            Text(text ?: "$fill%", Modifier.alignByBaseline(), fontSize = fs, lineHeight = fs, fontWeight = FontWeight.SemiBold, color = if (low) tone else C.muted)
        }
    }
}

/**
 * A profile's allowance on its own page, as the web's QuotaBars draws it there: each window's number large, ten cells
 * lit as far as is left, its name and when it refills. The number is the ink's colour while there is plenty.
 */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun QuotaDials(quota: fail.still.android.data.Quota?, modifier: Modifier = Modifier) {
    val windows = quota?.takeIf { it.state == "ok" }?.windows.orEmpty()
    if (windows.isEmpty()) return
    val c = C
    androidx.compose.foundation.layout.FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(36.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        windows.forEach { w ->
            val tone = levelColor(c, w.level)
            val low = w.level == "amber" || w.level == "red"
            Column(Modifier.widthIn(min = 96.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${w.left}", fontSize = 28.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.56).sp, color = if (low) tone else C.ink)
                    Text("%", fontSize = 15.sp, lineHeight = 26.sp, fontWeight = FontWeight.Medium, color = C.muted, modifier = Modifier.padding(start = 1.dp))
                }
                Row(Modifier.padding(top = 4.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    val lit = Math.round(w.left / 10.0).toInt()
                    repeat(10) { i -> Box(Modifier.size(8.dp, 14.dp).clip(RoundedCornerShape(2.dp)).background(if (i < lit) tone else C.chip)) }
                }
                Text(w.label, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink)
                Text(w.refills ?: "\u00a0", fontSize = 12.sp, color = C.muted)
            }
        }
    }
}

/** Whose service a profile runs on: Anthropic or OpenAI for a subscription or a key, OpenCode for OpenCode Go. */
@Composable
fun ProviderMark(runtime: String, kind: String?, size: Dp = 16.dp, mark: String? = null) {
    if (kind == "opencode-go" || mark == "opencode") {
        val ink = C.ink
        Canvas(Modifier.size(size)) {
            val u = this.size.width / 24f
            drawRect(ink, Offset(6 * u, 4 * u), Size(12 * u, 16 * u), style = Stroke(2.4f * u))
        }
        return
    }
    // A key on a listed provider: its maker's mark, or the generic plug where there is none.
    if (kind == "api-provider") {
        if (mark != null && mark in MAKER_MARKS) MakerIcon(Maker(mark, mark), runtime, size) else IconIn(Icons.Plug, size, C.ink)
        return
    }
    MakerIcon(if (runtime == "claude" || kind == "anthropic-api") Maker("anthropic", "Anthropic") else Maker("openai", "OpenAI"), runtime, size)
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
        IconIn(Icons.ChevronLeft, 22.dp, C.accent)
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
            // As the web's (mobile/parts.css.ts mNavbar): the buttons and the title's first line share one 32dp line at the
            // top; a title's second line (sub) hangs below it rather than pushing the title up off the back button's line.
            Box(Modifier.align(Alignment.TopStart).height(32.dp), contentAlignment = Alignment.CenterStart) { NavBack(back, onBack) }
            Column(Modifier.align(Alignment.TopCenter).padding(horizontal = 84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.height(30.dp), contentAlignment = Alignment.Center) {
                    Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                }
                Spacer(Modifier.height(2.dp))
                if (sub != null) Row(Modifier.offset(y = (-4).dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp), content = sub)
            }
            if (trailing != null) Box(Modifier.align(Alignment.TopEnd).height(32.dp), contentAlignment = Alignment.CenterEnd) { trailing() }
        }
    }
}

/** A page's large title (stations, settings): a small line over a big word; none when `small` is empty. */
@Composable
fun LargeTitle(small: String, big: String) {
    Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp)) {
        if (small.isNotEmpty()) Text(small, fontSize = 13.sp, color = C.muted)
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
fun Mark(size: Dp = 14.dp) = Image(painterResource(if (C.dark) R.drawable.stillfail_mark_dark else R.drawable.stillfail_mark), null, Modifier.size(size))

@Composable
fun SlackMark(size: Dp = 13.dp) = Image(painterResource(R.drawable.slack), null, Modifier.size(size))

@Composable
fun Illustration(light: Int, dark: Int, width: Dp) = Image(painterResource(if (C.dark) dark else light), null, Modifier.width(width))

