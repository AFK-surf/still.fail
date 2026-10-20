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
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.layout.positionInParent
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
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
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
import fail.still.android.shared.R
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
    "dsh" to R.drawable.maker_dsh,
    "cursor" to R.drawable.maker_cursor,
)

/** Marks of one colour, drawn in the page's ink. */
private val MONO = setOf("anthropic", "openai", "kimi", "xai", "mistral", "xiaomi", "ant-ling", "openrouter", "vercel", "cloudflare", "azure", "groq", "together", "fireworks", "cerebras", "huggingface", "nvidia", "baseten", "dsh", "cursor")

/** The mark of the company that made a model (the core says which); for one it does not know, its runtime's maker's (DeepSeek Harness's own; xAI's for Grok Build; Cursor's own). */
@Composable
fun MakerIcon(maker: Maker?, runtime: String?, size: Dp, modifier: Modifier = Modifier) {
    val id = maker?.id?.takeIf { it in MAKER_MARKS } ?: when (runtime) { "codex" -> "openai"; "dsh" -> "dsh"; "grok" -> "xai"; "cursor" -> "cursor"; else -> "anthropic" }
    Image(painterResource(MAKER_MARKS.getValue(id)), maker?.name, modifier.size(size), colorFilter = if (id in MONO) ColorFilter.tint(C.ink) else null)
}

/** A state badge: solid orange = block, a still hollow orange ring = at work, red = failed; done has none. Nothing blinks. */
@Composable
fun Badge(state: ChatState, size: Dp, ring: Dp, around: Color, modifier: Modifier = Modifier) {
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
 * disc of the ground with red in it when it wants someone (blocked, failed); at work yellow spokes 10dp across stepping
 * round (Spokes.kt), with no disc round them (it showed as a dark rim, 2026-10-19); nothing when done. No halo: the mark
 * is small.
 */
@Composable
fun AgentStateMark(state: ChatState, around: Color, modifier: Modifier = Modifier) {
    if (state == ChatState.Done) return
    val step = if (state == ChatState.Running) rememberSpokeStep() else null
    Canvas(modifier.size(12.dp)) {
        val r = size.minDimension / 2
        if (step != null) drawSpokes(step.value, AGENT_YELLOW, 10.dp.toPx())
        else { drawCircle(around, r); drawCircle(AGENT_RED, r - 2.dp.toPx()) }
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
            Modifier.size(size).clip(Smooth(if (xs) 6.dp else 11.dp)).background(C.surface)
                .border(1.dp, C.line, Smooth(if (xs) 6.dp else 11.dp)),
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
            core.callBytes("picture", kotlinx.serialization.json.buildJsonObject { put("url", kotlinx.serialization.json.JsonPrimitive(url)) }).second
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

/** One window of an allowance (the one an agent is short of) as a chip, its mark before what is left: as the web's QuotaChip. */
@Composable
fun QuotaChip(mark: String, left: Long, level: String, small: Boolean = true) = FillChip(leftOf(left), level, mark, "$left%", small)

/** A profile's allowance in a line: the web's chips (QuotaChips), one per window. */
@Composable
fun QuotaRings(quota: fail.still.android.data.Quota?) = QuotaChips(quota)

/**
 * A profile's allowance, compact, as the web's QuotaBars draws it: a rounded box per window (shortest first) with what
 * is left written in it (its mark too when there is more than one), its ground filled from the left as far as is left.
 * Its number in the ink's colour while there is plenty, in its colour once it runs low. `small`: a lower line.
 */
@Composable
fun QuotaChips(quota: fail.still.android.data.Quota?, small: Boolean = false) {
    val windows = quota?.takeIf { it.state == "ok" }?.windows.orEmpty()
    if (windows.isEmpty()) return
    val lone = windows.size == 1
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        windows.forEach { w -> FillChip(leftOf(w.left), w.level, if (lone) null else w.mark, "${w.left}%", small) }
    }
}

/**
 * A machine's CPU, memory and disk as an allowance's boxes are drawn (QuotaChips): each its name and what is left, its
 * ground filled as far as is used (a fuller box, less room). `alerts`: only the ones running low, as the web's station
 * cards do.
 */
@Composable
fun MeterChips(meters: List<fail.still.android.data.Meter>, modifier: Modifier = Modifier, alerts: Boolean = false) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        meters.filter { !alerts || it.level != "ok" }.forEach { m -> FillChip(usedOf(m.left), m.level, m.short, m.remaining) }
    }
}

/** How much of what a runtime's install downloads is in: the allowance's rounded box, filled in the accent as it comes. As the web's ProgressChip. */
@Composable
fun DownloadChip(percent: Long) = FillChip(percent.coerceIn(0L, 100L), "progress", null, "$percent%")

// How far a box is filled or a dial's cells lit, as the web decides it (components.tsx): an allowance as a battery, as
// far as is left; a machine's CPU, memory or disk as a disk's bar, as far as is used, though its words say what is left.
private fun leftOf(left: Long) = left.coerceIn(0L, 100L)
private fun usedOf(left: Long) = 100L - leftOf(left)

/**
 * A rounded box with a figure in it (its mark before it, when given) and its ground filled from the left as far as `fill`
 * (0–100): a quiet grey while it is ok, the colour of the core's level, faintly, once it is not, the figure then in that
 * colour too. Level `progress`: a download's share, in the accent, its fill moving smoothly to each new one. As the
 * web's FillChip (components.tsx).
 */
@Composable
private fun FillChip(fill: Long, level: String, mark: String?, text: String, small: Boolean = false) {
    val c = C
    val tone = levelColor(c, level)
    val low = level == "amber" || level == "red"
    val drawn by animateFloatAsState(fill.coerceIn(0L, 100L).toFloat(), if (level == "progress") tween(500) else snap(), label = "fill")
    val ground = if (low || level == "progress") tone.copy(alpha = 0.2f) else c.muted.copy(alpha = 0.22f)
    Box(Modifier.height(if (small) 16.dp else 20.dp).clip(Smooth(6.dp)).background(c.chip).drawBehind {
        if (drawn > 0f) drawRect(ground, size = Size(size.width * drawn / 100f, size.height))
    }, contentAlignment = Alignment.Center) {
        Row(Modifier.padding(horizontal = if (small) 5.dp else 8.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            val fs = if (small) 10.sp else 11.sp
            // On one baseline: a mark in Chinese (内存) sits lower in its line than figures do.
            if (mark != null) Text(mark, Modifier.alignByBaseline(), fontSize = fs, lineHeight = fs, fontWeight = FontWeight.SemiBold, color = androidx.compose.ui.graphics.lerp(c.ink, c.muted, 0.5f))
            Text(text, Modifier.alignByBaseline(), fontSize = fs, lineHeight = fs, fontWeight = FontWeight.SemiBold, color = if (low) tone else c.ink)
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
    androidx.compose.foundation.layout.FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(36.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        windows.forEach { w -> Dial("${w.left}", "%", leftOf(w.left), w.level, w.label, w.refills, Modifier.widthIn(min = 96.dp)) }
    }
}

/**
 * A machine's CPU, memory and disk on its own page, as an allowance's windows on its profile's (QuotaDials): each what is
 * left large over its cells (lit as far as is used), what it is and what it is out of. As the web's MeterDials (components.tsx); a row of three
 * that share the width, a phone being narrow.
 */
@Composable
fun MeterDials(meters: List<fail.still.android.data.Meter>, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        meters.forEach { m -> Dial(m.big, m.unit, usedOf(m.left), m.level, m.title, m.total, Modifier.weight(1f)) }
    }
}

/** A figure large, ten cells lit as far as `fill` (0–100) in the colour of its level, its name and a quiet note under. */
@Composable
private fun Dial(number: String, unit: String, fill: Long, level: String, label: String, note: String?, modifier: Modifier = Modifier) {
    val tone = levelColor(C, level)
    val low = level == "amber" || level == "red"
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(number, fontSize = 28.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.56).sp, color = if (low) tone else C.ink, maxLines = 1)
            Text(unit, fontSize = 15.sp, lineHeight = 26.sp, fontWeight = FontWeight.Medium, color = C.muted, modifier = Modifier.padding(start = 1.dp), maxLines = 1)
        }
        Row(Modifier.padding(top = 4.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            val lit = Math.round(fill / 10.0).toInt()
            repeat(10) { i -> Box(Modifier.size(7.dp, 14.dp).clip(RoundedCornerShape(2.dp)).background(if (i < lit) tone else C.chip)) }
        }
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1)
        Text(note ?: "\u00a0", fontSize = 12.sp, color = C.muted, maxLines = 1)
    }
}

/** The rest of a machine, a quiet row each (its hostname, chip, how long it has been up, the process): as the web's HostDetails. */
@Composable
fun HostDetails(details: List<fail.still.android.data.HostDetail>, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        details.forEach { d ->
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(d.label, fontSize = 13.sp, lineHeight = 20.sp, color = C.subtle, modifier = Modifier.widthIn(min = 52.dp))
                Text(d.value, fontSize = 13.sp, lineHeight = 20.sp, color = C.muted, modifier = Modifier.weight(1f))
            }
        }
    }
}

/** Whose service a profile runs on: Anthropic, OpenAI, xAI or Cursor for a subscription or a key, OpenCode for OpenCode Go. */
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
    MakerIcon(if (runtime == "claude" || kind == "anthropic-api") Maker("anthropic", "Anthropic") else if (runtime == "grok") Maker("xai", "xAI") else if (runtime == "cursor") Maker("cursor", "Cursor") else Maker("openai", "OpenAI"), runtime, size)
}

// ── controls ───────────────────────────────────────────────────────────

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
    val (tx, tw) = places.getOrElse(selected) { 0f to 0f }
    LaunchedEffect(tx, tw) {
        if (tw == 0f) return@LaunchedEffect
        // The first placement jumps; a change of choice slides.
        if (w.value == 0f) { x.snapTo(tx); w.snapTo(tw); return@LaunchedEffect }
        val ease = tween<Float>(240, easing = CubicBezierEasing(0f, 0f, 0.2f, 1f))
        launch { x.animateTo(tx, ease) }
        w.animateTo(tw, ease)
    }
    val density = LocalDensity.current
    val thumbShape = Smooth(concentric(radius, inset).coerceAtLeast(0.dp))
    Box(modifier.height(height).clip(Smooth(radius)).let { if (track) it.background(C.ink.copy(alpha = 0.06f)) else it }.padding(inset)) {
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

/**
 * A station where it is named (web/src/StationMark.tsx): its `icon` first, one of still.fail's (glyph:<name>, StationIcons;
 * glyph:<name>:<colour> in one of MARK_COLORS, else `tint`) or a picture put up (a data URL); else its emoji; else `none`
 * (nothing when null). A glyph this build does not know shows the emoji kept beside it.
 */
@Composable
fun StationMark(emoji: String?, icon: String?, size: Dp, tint: Color, modifier: Modifier = Modifier, none: ImageVector? = null) {
    val glyph = StationIcons.of(icon)
    val picture = remember(icon) { stationPicture(icon) }
    when {
        glyph != null -> Icon(glyph.icon, null, modifier.size(size), tint = markColor(glyphColor(icon)) ?: tint)
        picture != null -> Image(picture, null, modifier.size(size).clip(Smooth(size * 0.24f)), contentScale = ContentScale.Crop)
        emoji != null -> Text(emoji, fontSize = (size.value * 0.9f).sp, lineHeight = size.value.sp, modifier = modifier)
        none != null -> Icon(none, null, modifier.size(size), tint = tint)
    }
}

/** The colours a glyph can be given, in the picker's order (web/src/StationMark.tsx's MARK_COLORS). */
val MARK_COLORS = listOf("red", "orange", "amber", "green", "teal", "blue", "purple", "pink")

/** The colour a glyph was given (glyph:<name>:<colour>); null for none, or one this build does not know. */
fun glyphColor(icon: String?): String? = icon?.takeIf { it.startsWith("glyph:") }?.removePrefix("glyph:")?.substringAfter(':', "")?.takeIf { it in MARK_COLORS }

/** A colour of MARK_COLORS for the theme in use (web/src/StationMark.css.ts's); null for none. */
@Composable
fun markColor(color: String?): Color? = if (color == null) null else (if (C.dark) MARK_DARK else MARK_LIGHT)[color]

private val MARK_LIGHT = mapOf(
    "red" to Color(0xFFBC4945), "orange" to Color(0xFFB75400), "amber" to Color(0xFFA16700), "green" to Color(0xFF0E8C41),
    "teal" to Color(0xFF008D90), "blue" to Color(0xFF2D74CA), "purple" to Color(0xFF835CBE), "pink" to Color(0xFFB24981),
)
private val MARK_DARK = mapOf(
    "red" to Color(0xFFFB9890), "orange" to Color(0xFFF5A06F), "amber" to Color(0xFFE0AE57), "green" to Color(0xFF7CCD8E),
    "teal" to Color(0xFF3BCFCF), "blue" to Color(0xFF82BAFF), "purple" to Color(0xFFC3A5F9), "pink" to Color(0xFFF197C2),
)

/** Whether a station has anything to be shown by (StationMark draws nothing for it otherwise). */
fun hasStationMark(emoji: String?, icon: String?): Boolean = !emoji.isNullOrEmpty() || !icon.isNullOrEmpty()

/** A picture put up as a station's icon (a data URL), decoded; null for none or one that is not. */
fun stationPicture(icon: String?): ImageBitmap? {
    if (icon == null || !icon.startsWith("data:image/")) return null
    return try {
        val bytes = android.util.Base64.decode(icon.substringAfter("base64,"), android.util.Base64.DEFAULT)
        android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
    } catch (_: IllegalArgumentException) { null }
}

// ── navigation ─────────────────────────────────────────────────────────

/** Back, in the accent color, with where it goes back to. */
@Composable
fun NavBack(label: String, onClick: () -> Unit) {
    // A word that does not fit the room it is given (a bar's title takes the middle) is left out, not cut: the chevron
    // alone still says back, as on iOS.
    Layout(
        content = {
            IconIn(Icons.ChevronLeft, 22.dp, C.accent)
            Text(label, fontSize = 17.sp, color = C.link, maxLines = 1, softWrap = false)
        },
        modifier = Modifier.clip(Smooth(8.dp)).clickable(onClick = onClick).padding(end = 6.dp, top = 4.dp, bottom = 4.dp),
    ) { (chevron, word), constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val c = chevron.measure(loose)
        val w = word.measure(loose.copy(maxWidth = Constraints.Infinity))
        val shown = c.width + w.width <= constraints.maxWidth
        val height = maxOf(c.height, if (shown) w.height else 0)
        layout(if (shown) c.width + w.width else c.width, height) {
            c.place(0, (height - c.height) / 2)
            if (shown) w.place(c.width, (height - w.height) / 2)
        }
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
        // As the web's (mobile/parts.css.ts mNavbar): the buttons and the title's first line share one 32dp line at the
        // top; a title's second line (sub) hangs below it rather than pushing the title up off the back button's line.
        // The title stays in the middle and keeps 84dp clear at each side; the back button and the action get what is
        // left beside it, so a long back word never runs under the title.
        Layout(
            content = {
                Box(Modifier.height(32.dp), contentAlignment = Alignment.CenterStart) { NavBack(back, onBack) }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.height(30.dp), contentAlignment = Alignment.Center) {
                        Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                    }
                    Spacer(Modifier.height(2.dp))
                    if (sub != null) Row(Modifier.offset(y = (-4).dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp), content = sub)
                }
                Box(Modifier.height(32.dp), contentAlignment = Alignment.CenterEnd) { trailing?.invoke() }
            },
            modifier = Modifier.fillMaxWidth().padding(start = 10.dp, end = 16.dp, top = 6.dp, bottom = 10.dp),
        ) { (backPart, titlePart, endPart), constraints ->
            val width = constraints.maxWidth
            val side = 84.dp.roundToPx()
            val gap = 8.dp.roundToPx()
            val loose = constraints.copy(minWidth = 0, minHeight = 0)
            val t = titlePart.measure(loose.copy(maxWidth = (width - 2 * side).coerceAtLeast(0)))
            val titleX = (width - t.width) / 2
            val room = (titleX - gap).coerceAtLeast(0)
            val b = backPart.measure(loose.copy(maxWidth = room))
            val e = endPart.measure(loose.copy(maxWidth = room))
            layout(width, maxOf(t.height, b.height, e.height)) {
                b.place(0, 0)
                t.place(titleX, 0)
                e.place(width - e.width, 0)
            }
        }
    }
}

/** A page's large title (stations, settings): a small line over a big word; none when `small` is empty. `lead` goes before the word (a workspace's mark). */
@Composable
fun LargeTitle(small: String, big: String, lead: (@Composable () -> Unit)? = null) {
    Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 6.dp)) {
        if (small.isNotEmpty()) Text(small, fontSize = 13.sp, color = C.muted)
        if (lead == null) Text(big, fontSize = 32.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.6).sp)
        else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            lead()
            Text(big, fontSize = 32.sp, fontWeight = FontWeight.Bold, color = C.ink, letterSpacing = (-0.6).sp)
        }
    }
}

// ── lists and cards ────────────────────────────────────────────────────

/**
 * Text moved so its characters' ink, not its line, is in the middle of its box: the marks centred beside it are then
 * centred on its words. A Chinese font's line has more room above its characters than below (its ascent is the line's),
 * so they sit low in it; a character's ink is centred 0.38em above the baseline.
 */
fun Modifier.inkCentred(size: androidx.compose.ui.unit.TextUnit) = layout { m, c ->
    val p = m.measure(c)
    val base = p[androidx.compose.ui.layout.FirstBaseline]
    val dy = if (base == androidx.compose.ui.layout.AlignmentLine.Unspecified) 0 else (p.height / 2f - base + 0.38f * size.toPx()).roundToInt()
    layout(p.width, p.height) { p.place(0, dy) }
}

/** A section's title; `mark`: what it holds at a glance (a vendor's mark), before it, centred on its words. */
@Composable
fun SectionHeader(title: String, trailing: String? = null, start: Dp = 20.dp, mark: (@Composable () -> Unit)? = null, action: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(start = start, end = 20.dp, top = 14.dp, bottom = 6.dp), verticalAlignment = Alignment.Bottom) {
        if (mark == null) Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            mark()
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.inkCentred(15.sp))
        }
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, fontSize = 13.sp, color = C.muted)
        // What can be done to the whole section (取消登录), at its end.
        action?.invoke()
    }
}

/**
 * A card of words (web pages.css.ts card, docs/ui-panels.md 页面卡片): CARD_PAD on every side, its words and a solid
 * button's ground on one line. `foot`: a button with a ground of its own (a capsule) sits in a corner, and the card's
 * corner is taken from it, CARD_PAD and its half height, so they are concentric; else CARD_CORNER. `corner`: taken
 * from something else with a ground in its corner (a Seg at its top). `margin`: its room from the page's sides, none in a
 * page padded already.
 */
@Composable
fun Card(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, foot: Boolean = false, corner: Dp? = null, margin: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.padding(horizontal = margin).padding(bottom = 10.dp).fillMaxWidth().clip(Smooth(corner ?: if (foot) CARD_PAD + BUTTON_HEIGHT / 2 else CARD_CORNER)).background(C.surface)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(CARD_PAD),
        content = content,
    )
}

/** A card of words' padding, on every side. */
val CARD_PAD = 20.dp
/** A card of words' corner, with nothing that has a ground of its own in it. */
val CARD_CORNER = 22.dp

/**
 * Rows on one rounded card, to be pressed (web pages.css.ts listCard): each row's ground LIST_PAD from the card's edge,
 * rounded LIST_ROW_CORNER, the card's corner concentric with theirs; their words CARD_PAD from the card's edge.
 */
@Composable
fun ListCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) =
    RowsCard(modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp), content = content)

/** A list card where it is put (in a padded page, a sheet): its rows (ListRow, PickRow) know they are on one. */
@Composable
fun RowsCard(modifier: Modifier = Modifier, ground: Color = C.surface, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(Smooth(LIST_CARD_CORNER)).background(ground).padding(LIST_PAD)) {
        CompositionLocalProvider(LocalOnCard provides true) { content() }
    }
}

/** On a list card: a row's ground is the card's padding in from its edge already. */
val LocalOnCard = staticCompositionLocalOf { false }

/** How far a list card's rows' ground is from its edge, and their corner. */
val LIST_PAD = 8.dp
val LIST_ROW_CORNER = 18.dp
val LIST_CARD_CORNER = concentricOut(LIST_ROW_CORNER, LIST_PAD)

@Composable
fun ListRow(onClick: (() -> Unit)? = null, ground: Color = Color.Transparent, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(Smooth(LIST_ROW_CORNER)).background(ground).let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(horizontal = CARD_PAD - LIST_PAD, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}

/**
 * The app starting (or waiting for what every page needs): the buddy, floating. What it waits for is said only when
 * it takes a while (after a second), or at once when `now` (a failure).
 */
@Composable
fun Splash(label: String? = null, now: Boolean = false) {
    val lift by rememberLoop(0f, 1f, infiniteRepeatable(tween(900, easing = FastOutSlowInEasing), RepeatMode.Reverse), "lift", still = 0f)
    var shown by remember { mutableStateOf(now) }
    LaunchedEffect(now) { if (!now) { delay(1000); shown = true } else shown = true }
    Column(Modifier.fillMaxSize().background(C.bg).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
        val px = with(LocalDensity.current) { 5.dp.toPx() }
        Box(Modifier.graphicsLayer { translationY = -lift * px }) { Mark(56.dp) }
        if (label != null) Text(label, color = C.muted, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.alpha(if (shown) 1f else 0f))
    }
}

@Composable
fun Mark(size: Dp = 14.dp) = Image(painterResource(if (C.dark) R.drawable.stillfail_mark_dark else R.drawable.stillfail_mark), null, Modifier.size(size))

/** Where a thread elsewhere is, by `kind` (a connect's kind, a place's surface, a chat's origin): Feishu's mark for Feishu, else Slack's. */
@Composable
fun SlackMark(size: Dp = 13.dp, kind: String? = null) =
    Image(painterResource(if (kind == "feishu" || kind?.startsWith("feishu:") == true) R.drawable.feishu else R.drawable.slack), null, Modifier.size(size))

@Composable
fun Illustration(light: Int, dark: Int, width: Dp) = Image(painterResource(if (C.dark) dark else light), null, Modifier.width(width))

