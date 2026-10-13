// A text of a drive, read (zdrive's reader, in still.fail's look): one column that scrolls, nothing over it until a tap
// brings the bars — frosted, floating over the page — and takes them away again. The top one says what and where (its
// chapter, how far) and searches; the bottom one steps chapters, jumps anywhere along a hairline with a knob, and opens
// the contents, the type and paper, and day or night. A hard-wrapped novel is reflowed into paragraphs, Markdown is drawn
// as Markdown, chapters (第X章, Chapter N, # headings) make the contents. Where it was left is kept on this device
// (drivePlace) and opened at next time.
package fail.still.android.drive

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListLayoutInfo
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.data.Topics
import fail.still.android.data.t
import fail.still.android.screens.Button
import fail.still.android.screens.PickRow
import fail.still.android.screens.activity
import fail.still.android.screens.fileSize
import fail.still.android.ui.C
import fail.still.android.ui.GlassBlur
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/** How a text comes: how much of it so far (and of how much), then the text itself, or why not. */
private sealed interface Opening {
    class Coming(val got: Long, val of: Long?) : Opening
    class Failed(val why: String) : Opening
    class Ready(val novel: Novel, val at: Int?) : Opening
}

/** The reader's state, which its page and its sheets (contents, search, type) share. */
private class Reading(val novel: Novel, start: Pair<Int, Int>) {
    var chunk by mutableIntStateOf(start.first)
    /** How far down its block the top of the screen is (0–1). */
    var within by mutableFloatStateOf(0f)
    var jump by mutableStateOf<ReaderJump?>(if (start.second > 0) ReaderJump(start.first, start.second, 1, lead = false) else null)
    private var serial = 1L
    var query by mutableStateOf("")
    var matches by mutableStateOf<List<TextMatch>>(emptyList())
    var hit by mutableIntStateOf(-1)

    val last get() = (novel.chunks.size - 1).coerceAtLeast(0)
    val fraction: Float get() = ((chunk + within) / novel.chunks.size.coerceAtLeast(1)).coerceIn(0f, 1f)
    val offsetInChunk: Int get() = (novel.chunks.getOrElse(chunk) { "" }.length * within).roundToInt()
    /** The chapter the top of the screen is in (-1 before the first). */
    val chapter: Int get() = novel.chapters.indexOfLast { it.chunk < chunk || (it.chunk == chunk && it.offset <= offsetInChunk) }
    /** Fewer than two markers is not a table of contents (one is usually a stray line that matched). */
    val hasChapters get() = novel.chapters.size >= 2

    fun jumpTo(chunk: Int, offset: Int) { jump = ReaderJump(chunk.coerceIn(0, last), offset, ++serial) }
    fun jumpTo(fraction: Float) = jumpTo((fraction * last).roundToInt(), 0)
    fun step(delta: Int) {
        if (matches.isEmpty()) return
        hit = ((hit + delta) % matches.size + matches.size) % matches.size
        matches[hit].let { jumpTo(it.chunk, it.start) }
    }
}

/** The reader's look, kept on this device (its type and paper). */
private object ReaderPrefs {
    fun typography(app: AppState) = ReaderTypography.decode(app.strings("drive.reader.type").firstOrNull())
    fun setTypography(app: AppState, v: ReaderTypography) = app.setStrings("drive.reader.type", listOf(ReaderTypography.encode(v)))
    fun paper(app: AppState) = Paper.of(app.strings("drive.reader.paper").firstOrNull())
    fun setPaper(app: AppState, v: Paper) = app.setStrings("drive.reader.paper", listOf(v.name))
}

/** The text `path` of `root` on `station`, read. */
@Composable
fun ReaderScreen(station: String, root: String, path: String) {
    val app = LocalApp.current
    val name = nameOf(path)
    var paper by remember { mutableStateOf(ReaderPrefs.paper(app)) }
    var typography by remember { mutableStateOf(ReaderPrefs.typography(app)) }
    val p = paper.ink(C.dark)
    PaperBars(p.dark)
    val opening by produceState<Opening>(Opening.Coming(0, null), station, root, path) {
        value = try {
            val bytes = app.api(station).driveBytes(root, path, MAX_NOVEL_BYTES.toLong()) { got, of -> value = Opening.Coming(got, of) }
            val size = (value as? Opening.Coming)?.of ?: bytes.size.toLong()
            val novel = withContext(Dispatchers.Default) { buildNovel(name, bytes, size, size > bytes.size) }
            // Where it was left on this device (held here: no wait for a station).
            val held = withTimeoutOrNull(1000) { app.core.topic(Topics.drivePlace(station, root, path)).first { !it.loading } }?.value
            val at = (held as? JsonObject)?.get("at")?.jsonPrimitive?.doubleOrNull?.toInt()
            android.util.Log.i("drive-reader", "open $path: ${novel.encoding}, ${novel.chapters.size} chapters, ${novel.length} chars; left at $at ($held)")
            Opening.Ready(novel, at)
        } catch (e: CoreException) {
            Opening.Failed(e.message)
        }
    }
    Box(Modifier.fillMaxSize().background(p.ground)) {
        when (val o = opening) {
            is Opening.Ready -> Book(app, station, root, path, o.novel, o.at, p, paper, typography,
                setPaper = { paper = it; ReaderPrefs.setPaper(app, it) },
                setTypography = { typography = it; ReaderPrefs.setTypography(app, it) })
            else -> {
                Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
                    when (o) {
                        is Opening.Coming -> {
                            fail.still.android.screens.Spinner(18.dp)
                            Text(
                                if (o.of != null && o.of > 0) t("android-misc.drive.reader.loading.size", "got" to fileSize(o.got), "size" to fileSize(o.of)) else t("android-misc.drive.reader.loading"),
                                fontSize = 14.sp, color = p.muted, textAlign = TextAlign.Center,
                            )
                        }
                        is Opening.Failed -> Text(t("android-misc.drive.reader.failed", "error" to o.why), fontSize = 14.sp, color = C.red, textAlign = TextAlign.Center)
                        else -> {}
                    }
                }
                // The way back is there while it comes.
                val haze = remember { HazeState() }
                TopBar(haze, p, name, "", onBack = app::pop, onSearch = null, modifier = Modifier.align(Alignment.TopCenter))
            }
        }
    }
}

/** The system bars' icons readable on the paper; the app's again once the reader is gone. */
@Composable
private fun PaperBars(dark: Boolean) {
    val view = LocalView.current
    val appLight = !C.dark
    DisposableEffect(dark, appLight) {
        val window = view.context.activity()?.window
        val controller = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        controller?.apply { isAppearanceLightStatusBars = !dark; isAppearanceLightNavigationBars = !dark }
        onDispose { controller?.apply { isAppearanceLightStatusBars = appLight; isAppearanceLightNavigationBars = appLight } }
    }
}

@OptIn(FlowPreview::class)
@Composable
private fun Book(
    app: AppState, station: String, root: String, path: String, novel: Novel, at: Int?, p: PaperInk, paper: Paper, typography: ReaderTypography,
    setPaper: (Paper) -> Unit, setTypography: (ReaderTypography) -> Unit,
) {
    val r = remember(novel) { Reading(novel, at?.let { novel.at(it) } ?: (0 to 0)) }
    var chrome by remember { mutableStateOf(false) }
    val haze = remember { HazeState() }
    val shown by animateFloatAsState(if (chrome) 1f else 0f, tween(180), label = "chrome")

    // Where it was left, written as the reader stops (not on every pixel), and as the page goes.
    val api = remember(station) { app.api(station) }
    fun keep() { val at2 = novel.offsetOf(r.chunk, r.within); app.scope.launch { try { api.drivePlace(root, path, at2.toDouble(), novel.length.toDouble()) } catch (e: CoreException) { android.util.Log.w("drive-reader", "place not kept: ${e.code} ${e.message}") } } }
    LaunchedEffect(r) { snapshotFlow { r.chunk to (r.within * 50).toInt() }.debounce(800).collect { keep() } }
    DisposableEffect(r) { onDispose { keep() } }

    LaunchedEffect(r.query) {
        if (r.query.isBlank()) { r.matches = emptyList(); r.hit = -1; return@LaunchedEffect }
        delay(250)
        val found = withContext(Dispatchers.Default) { searchChunks(novel.chunks, r.query) }
        r.matches = found
        r.hit = if (found.isEmpty()) -1 else firstMatchAfter(found, r.chunk, r.offsetInChunk)
        if (r.hit >= 0) found[r.hit].let { r.jumpTo(it.chunk, it.start) }
    }

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().hazeSource(haze)) {
            TextColumn(r, typography, p) { chrome = !chrome }
        }
        // The clock and the icons stay on the paper, not over the text running under them.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(p.ground))
        val percent = "${(r.fraction * 100).roundToInt()}%"
        val chapter = r.chapter
        val sub = listOfNotNull(
            if (chapter >= 0 && r.hasChapters) novel.chapters[chapter].title else t("android-misc.drive.reader.chars", "n" to novel.charCount),
            percent,
            if (novel.truncated) t("android-misc.drive.reader.truncated", "size" to fileSize(novel.sourceBytes), "mb" to MAX_NOVEL_BYTES / (1024 * 1024)) else null,
        ).joinToString(" · ")
        Box(Modifier.align(Alignment.TopCenter).alpha(shown)) {
            if (shown > 0f) TopBar(haze, p, novel.title, sub, onBack = app::pop, onSearch = { openSearch(app, r) })
        }
        Box(Modifier.align(Alignment.BottomCenter).alpha(shown)) {
            if (shown > 0f) BottomBar(haze, p, r,
                onChapters = { openChapters(app, r) },
                onType = { openType(app, paper, typography, setPaper, setTypography) },
                onDayNight = { setPaper(if (p.dark) Paper.White else Paper.Night) })
        }
    }
}

/** The column of text: one block of it per row of a lazy list; a tap shows or hides the bars. */
@Composable
private fun TextColumn(r: Reading, typography: ReaderTypography, p: PaperInk, onTap: () -> Unit) {
    val novel = r.novel
    val list = rememberLazyListState(initialFirstVisibleItemIndex = r.chunk)
    val style = remember(typography, p) { typography.style(p.ink) }
    val colors = remember(p) { MarkdownColors(muted = p.muted, accent = p.accent, code = p.ink.copy(alpha = 0.8f)) }
    val mark = p.accent.copy(alpha = if (p.dark) 0.28f else 0.18f)
    val markNow = p.accent.copy(alpha = if (p.dark) 0.55f else 0.42f)
    val byChunk = remember(r.matches) { r.matches.groupBy { it.chunk } }
    // A jump (a chapter, a hit, the slider) puts its block at the top, then slides to the offset in it once the block is
    // laid out (its height is not known before).
    LaunchedEffect(r.jump) {
        val target = r.jump ?: return@LaunchedEffect
        val index = target.chunk.coerceIn(0, r.last)
        list.scrollToItem(index, 0)
        val drawn = drawnChunk(novel.chunks.getOrElse(index) { "" }, novel.markdown, typography, colors)
        if (target.offset <= 0 || drawn.text.isEmpty()) return@LaunchedEffect
        var height = heightOf(list.layoutInfo, index)
        var waited = 0
        while (height <= 0 && waited++ < 4) { withFrameNanos { }; height = heightOf(list.layoutInfo, index) }
        if (height <= 0) return@LaunchedEffect
        val at = drawn.at(target.offset).coerceIn(0, drawn.text.length)
        // A little of what is before it in view, under the top bar.
        list.scrollToItem(index, ((height * (at.toFloat() / drawn.text.length)).roundToInt() - if (target.lead) 120 else 0).coerceAtLeast(0))
    }
    LaunchedEffect(list) {
        snapshotFlow { list.firstVisibleItemIndex to list.firstVisibleItemScrollOffset }.collect { (index, _) ->
            val item = list.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }
            r.chunk = index
            r.within = (item?.let { if (it.size > 0) (-it.offset).toFloat() / it.size else 0f } ?: 0f).coerceIn(0f, 1f)
        }
    }
    val tap by rememberUpdatedState(onTap)
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    LazyColumn(
        state = list,
        modifier = Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { tap() } },
        contentPadding = PaddingValues(start = typography.marginDp.dp, end = typography.marginDp.dp, top = top + 12.dp, bottom = bottom + 200.dp),
    ) {
        itemsIndexed(novel.chunks, key = { i, _ -> i }) { i, raw ->
            val drawn = remember(raw, typography.indent, typography.fontSp, colors) { drawnChunk(raw, novel.markdown, typography, colors) }
            val mine = byChunk[i].orEmpty()
            val now = r.matches.getOrNull(r.hit)?.takeIf { it.chunk == i }
            val text = remember(drawn, mine, now, mark, markNow) { drawn.marked(mine, now, mark, markNow) }
            Text(text, style = style, modifier = Modifier.fillMaxWidth().padding(top = drawn.leadingDp.dp))
        }
    }
}

private fun heightOf(info: LazyListLayoutInfo, index: Int): Int = info.visibleItemsInfo.firstOrNull { it.index == index }?.size ?: 0

/** A block as it is drawn: plain text with its paragraphs indented, or Markdown with the map back to the raw offsets search and jumps use. */
private class DrawnChunk(val text: String, val leadingDp: Int, private val raw: String?, private val indent: Boolean, private val markdown: MarkdownChunk?) {
    fun at(rawOffset: Int): Int = markdown?.renderedIndex(rawOffset) ?: renderOffset(raw!!, rawOffset, indent)

    fun marked(marks: List<TextMatch>, current: TextMatch?, color: Color, currentColor: Color): AnnotatedString {
        val md = markdown
        if (md != null && marks.isEmpty() && current == null) return md.styled
        return buildAnnotatedString {
            if (md != null) append(md.styled) else append(text)
            fun paint(m: TextMatch, hue: Color) {
                val from = at(m.start).coerceIn(0, length)
                val to = at(m.start + m.length).coerceIn(from, length)
                if (to > from) addStyle(SpanStyle(background = hue), from, to)
            }
            marks.forEach { paint(it, color) }
            current?.let { paint(it, currentColor) }
        }
    }
}

private fun drawnChunk(raw: String, markdown: Boolean, typography: ReaderTypography, colors: MarkdownColors): DrawnChunk {
    if (!markdown) return DrawnChunk(renderChunk(raw, typography.indent), 0, raw, typography.indent, null)
    val parsed = renderMarkdown(raw, typography.fontSp.toFloat(), colors)
    return DrawnChunk(parsed.styled.text, parsed.leadingDp, null, false, parsed)
}

// ── the bars ────────────────────────────────────────────────────────────

/** Frosted glass of the paper's own bar colour, floating over the text: a breath of shadow, taps kept on it. */
private fun Modifier.paperGlass(haze: HazeState, shape: Shape, p: PaperInk): Modifier =
    shadow(1.dp, shape, ambientColor = Color.Black.copy(alpha = 0.3f), spotColor = Color.Black.copy(alpha = 0.3f)).clip(shape)
        .hazeEffect(haze) {
            backgroundColor = p.ground
            tints = listOf(HazeTint(p.bar.copy(alpha = 0.72f)))
            blurRadius = GlassBlur
            noiseFactor = 0f
        }
        .pointerInput(Unit) { detectTapGestures { } }

@Composable
private fun BarIcon(icon: ImageVector, label: String, p: PaperInk, onClick: () -> Unit) {
    Box(Modifier.size(40.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        IconIn(icon, 20.dp, p.ink)
    }
}

/** What is open and where in it: back, its name and chapter and how far, search. */
@Composable
private fun TopBar(haze: HazeState, p: PaperInk, title: String, sub: String, onBack: () -> Unit, onSearch: (() -> Unit)?, modifier: Modifier = Modifier) {
    Row(
        modifier.windowInsetsPadding(WindowInsets.statusBars).padding(horizontal = 8.dp, vertical = 6.dp).fillMaxWidth()
            .paperGlass(haze, Smooth(16.dp), p).height(48.dp).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BarIcon(Icons.ChevronLeft, t("common.back"), p, onBack)
        Column(Modifier.weight(1f).padding(horizontal = 4.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub.isNotEmpty()) Text(sub, fontSize = 12.sp, color = p.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onSearch != null) BarIcon(Icons.Search, t("android-misc.drive.reader.search"), p, onSearch)
    }
}

/** Chapters before and after, the jump along the whole text, and the contents, the type, day or night. */
@Composable
private fun BottomBar(haze: HazeState, p: PaperInk, r: Reading, onChapters: () -> Unit, onType: () -> Unit, onDayNight: () -> Unit) {
    val novel = r.novel
    val ch = r.chapter
    Column(
        Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 8.dp, vertical = 8.dp).fillMaxWidth()
            .paperGlass(haze, Smooth(20.dp), p).padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (r.hasChapters) Row(verticalAlignment = Alignment.CenterVertically) {
            val before = if (ch > 0) novel.chapters[ch - 1] else null
            val after = novel.chapters.getOrNull(ch + 1)
            TextKey(t("android-misc.drive.reader.prev"), p, before?.let { { r.jumpTo(it.chunk, it.offset) } })
            Text(
                if (ch >= 0) novel.chapters[ch].title else t("android-misc.drive.reader.opening"),
                fontSize = 13.sp, color = p.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            )
            TextKey(t("android-misc.drive.reader.next"), p, after?.let { { r.jumpTo(it.chunk, it.offset) } })
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.weight(1f)) { Hairline(r.fraction, p.ink.copy(alpha = 0.14f), p.accent, p.bar) { r.jumpTo(it) } }
            Text("${(r.fraction * 100).roundToInt()}%", fontSize = 12.sp, color = p.muted, textAlign = TextAlign.End, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.width(36.dp))
        }
        Row {
            Tool(Icons.List, t("android-misc.drive.reader.contents"), p, onChapters)
            Tool(Icons.Text, t("android-misc.drive.reader.type"), p, onType)
            Tool(if (p.dark) Icons.Sun else Icons.Moon, if (p.dark) t("android-misc.drive.reader.day") else t("android-misc.drive.reader.night"), p, onDayNight)
        }
    }
}

/** Text and nothing else, as a card's quieter keys are; faded and inert when there is nowhere to go. */
@Composable
private fun TextKey(label: String, p: PaperInk, onClick: (() -> Unit)?) {
    Text(
        label, fontSize = 13.sp, color = if (onClick != null) p.ink else p.ink.copy(alpha = 0.3f), maxLines = 1,
        modifier = Modifier.clip(Smooth(8.dp)).clickable(enabled = onClick != null) { onClick?.invoke() }.padding(horizontal = 6.dp, vertical = 6.dp),
    )
}

@Composable
private fun RowScope.Tool(icon: ImageVector, label: String, p: PaperInk, onClick: () -> Unit) {
    Column(
        Modifier.weight(1f).clip(Smooth(12.dp)).clickable(onClick = onClick).padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        IconIn(icon, 20.dp, p.ink)
        Text(label, fontSize = 11.sp, color = p.muted)
    }
}

/**
 * Where it is along the whole, to tap or drag to a place: a hairline, what is behind in the accent, a round knob. The
 * knob follows the finger while it drags; the text goes there once it is let go (re-laying a long text per pixel stutters).
 */
@Composable
private fun Hairline(fraction: Float, track: Color, fill: Color, ring: Color, onPick: (Float) -> Unit) {
    var draft by remember { mutableFloatStateOf(fraction) }
    var dragging by remember { mutableStateOf(false) }
    LaunchedEffect(fraction) { if (!dragging) draft = fraction }
    var width by remember { mutableIntStateOf(1) }
    Canvas(
        Modifier.fillMaxWidth().height(28.dp).onSizeChanged { width = it.width.coerceAtLeast(1) }
            .pointerInput(Unit) { detectTapGestures { onPick((it.x / width).coerceIn(0f, 1f)) } }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { dragging = true; draft = (it.x / width).coerceIn(0f, 1f) },
                    onDragEnd = { dragging = false; onPick(draft) },
                    onDragCancel = { dragging = false },
                ) { change, _ -> change.consume(); draft = (change.position.x / width).coerceIn(0f, 1f) }
            },
    ) {
        val knob = (if (dragging) 8.dp else 6.dp).toPx()
        val h = 2.dp.toPx()
        val y = size.height / 2
        val x = knob + (size.width - 2 * knob) * draft
        drawRoundRect(track, Offset(0f, y - h / 2), Size(size.width, h), CornerRadius(h / 2))
        drawRoundRect(fill, Offset(0f, y - h / 2), Size(x, h), CornerRadius(h / 2))
        drawCircle(ring, knob + 2.dp.toPx(), Offset(x, y))
        drawCircle(fill, knob, Offset(x, y))
    }
}

// ── the sheets ──────────────────────────────────────────────────────────

/** The contents: each chapter, the one being read checked; a way into search. With none found, a jump by how far. */
private fun openChapters(app: AppState, r: Reading) {
    app.sheet = SheetSpec(if (r.hasChapters) 0.75f else 0.4f, draggable = r.hasChapters) {
        val novel = r.novel
        SheetGrab()
        SheetHead(t("android-misc.drive.reader.contents"), trailing = {
            Text(listOfNotNull(if (r.hasChapters) t("android-misc.drive.reader.chapters", "n" to novel.chapters.size) else null, t("android-misc.drive.reader.readShare", "n" to (r.fraction * 100).roundToInt())).joinToString(" · "), fontSize = 13.sp, color = C.muted)
        })
        PickRow(t("android-misc.drive.reader.searchAll"), leading = { IconIn(Icons.Search, 18.dp, C.muted) }) { openSearch(app, r) }
        if (!r.hasChapters) {
            Text(t("android-misc.drive.reader.noChapters"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            Box(Modifier.padding(horizontal = 20.dp)) { Hairline(r.fraction, C.ink.copy(alpha = 0.12f), C.accent, C.surface) { r.jumpTo(it) } }
        } else {
            val now = r.chapter
            val list = rememberLazyListState(initialFirstVisibleItemIndex = (now - 3).coerceAtLeast(0))
            LazyColumn(Modifier.weight(1f), state = list, contentPadding = PaddingValues(bottom = 16.dp)) {
                itemsIndexed(novel.chapters) { i, c ->
                    PickRow(c.title, checked = i == now, color = if (i < now) C.muted else C.ink, leading = {
                        Text("${i + 1}", fontSize = 12.sp, color = C.subtle, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.width(30.dp))
                    }) { r.jumpTo(c.chunk, c.offset); app.sheet = null }
                }
            }
        }
    }
}

/** Search in the whole text: as it is typed the hits are marked and the first after here is gone to; ‹ › step through them. */
private fun openSearch(app: AppState, r: Reading) {
    // Tall enough that what it says stays above the keyboard (the sheet keeps its height and makes room for it inside).
    app.sheet = SheetSpec(0.62f) {
        val focus = remember { FocusRequester() }
        LaunchedEffect(Unit) { delay(50); runCatching { focus.requestFocus() } }
        SheetGrab()
        SheetHead(t("android-misc.drive.reader.search"))
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.fillMaxWidth().clip(Smooth(12.dp)).background(C.surface).border(1.dp, C.line, Smooth(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp)) {
                if (r.query.isEmpty()) Text(t("android-misc.drive.reader.searchAll"), color = C.subtle, fontSize = 15.sp)
                BasicTextField(
                    r.query, { r.query = it }, singleLine = true, cursorBrush = SolidColor(C.accent),
                    textStyle = TextStyle(color = C.ink, fontSize = 15.sp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { r.step(1) }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val status = when {
                    r.query.isBlank() -> t("android-misc.drive.reader.searchHint")
                    r.matches.isEmpty() -> t("android-misc.drive.reader.notFound")
                    r.matches.size >= 400 -> t("android-misc.drive.reader.hitsMany", "at" to r.hit + 1, "n" to r.matches.size)
                    else -> t("android-misc.drive.reader.hits", "at" to r.hit + 1, "n" to r.matches.size)
                }
                Text(status, fontSize = 13.sp, color = C.muted, modifier = Modifier.weight(1f))
                Button(t("android-misc.drive.reader.prevHit"), primary = false, enabled = r.matches.isNotEmpty()) { r.step(-1) }
                Button(t("android-misc.drive.reader.nextHit"), primary = false, enabled = r.matches.isNotEmpty()) { r.step(1) }
            }
        }
        DisposableEffect(Unit) { onDispose { if (app.sheet == null) { r.query = "" } } }
    }
}

/** The paper, the type's size, the lines' spacing, the margins, the face and the indent. */
private fun openType(app: AppState, paper0: Paper, type0: ReaderTypography, setPaper: (Paper) -> Unit, setTypography: (ReaderTypography) -> Unit) {
    app.sheet = SheetSpec(0.66f, draggable = true) {
        var paper by remember { mutableStateOf(paper0) }
        var type by remember { mutableStateOf(type0) }
        fun put(v: ReaderTypography) { type = v; setTypography(v) }
        SheetGrab()
        SheetHead(t("android-misc.drive.reader.type"))
        Column(Modifier.weight(1f).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Labeled(t("android-misc.drive.reader.paper")) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Paper.entries.forEach { option ->
                        val chosen = option == paper
                        val ink = option.ink(C.dark)
                        Column(
                            Modifier.weight(1f).height(60.dp).clip(Smooth(14.dp)).background(ink.ground)
                                .let { if (chosen) it.border(2.dp, C.accent, Smooth(14.dp)) else it }
                                .clickable { paper = option; setPaper(option) },
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
                        ) {
                            Text(t("android-misc.drive.reader.sample"), fontSize = 16.sp, fontFamily = FontFamily.Serif, color = ink.ink)
                            Text(option.label, fontSize = 11.sp, color = ink.muted, maxLines = 1)
                        }
                    }
                }
            }
            Labeled(t("android-misc.drive.reader.size")) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button("A−", primary = false, enabled = type.fontSp > ReaderTypography.MIN_FONT_SP) { put(type.copy(fontSp = type.fontSp - 1)) }
                    Text("${type.fontSp}", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                    Button("A+", primary = false, enabled = type.fontSp < ReaderTypography.MAX_FONT_SP) { put(type.copy(fontSp = type.fontSp + 1)) }
                }
            }
            Slide(t("android-misc.drive.reader.spacing"), type.lineSpacing, ReaderTypography.MIN_LINE_SPACING, ReaderTypography.MAX_LINE_SPACING, "${(type.lineSpacing * 100).roundToInt()}%") { put(type.copy(lineSpacing = it)) }
            Slide(t("android-misc.drive.reader.margin"), type.marginDp.toFloat(), ReaderTypography.MIN_MARGIN_DP.toFloat(), ReaderTypography.MAX_MARGIN_DP.toFloat(), "${type.marginDp}") { put(type.copy(marginDp = it.roundToInt())) }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.weight(1f)) { Labeled(t("android-misc.drive.reader.font")) { Seg(ReaderFamily.entries.map { it.label }, type.family.ordinal, { put(type.copy(family = ReaderFamily.entries[it])) }, Modifier.fillMaxWidth(), fill = true, height = 36.dp) } }
                Box(Modifier.weight(1f)) { Labeled(t("android-misc.drive.reader.indent")) { Seg(listOf(t("android-misc.drive.reader.indent.on"), t("android-misc.drive.reader.indent.off")), if (type.indent) 0 else 1, { put(type.copy(indent = it == 0)) }, Modifier.fillMaxWidth(), fill = true, height = 36.dp) } }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun Labeled(label: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, fontSize = 13.sp, color = C.muted)
        content()
    }
}

@Composable
private fun Slide(label: String, value: Float, from: Float, to: Float, shown: String, onValue: (Float) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, fontSize = 13.sp, color = C.muted, modifier = Modifier.width(40.dp))
        Box(Modifier.weight(1f)) { Hairline((value - from) / (to - from), C.ink.copy(alpha = 0.12f), C.accent, C.surface) { onValue(from + it * (to - from)) } }
        Text(shown, fontSize = 13.sp, color = C.ink, textAlign = TextAlign.End, modifier = Modifier.width(40.dp))
    }
}
