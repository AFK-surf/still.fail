// A text of a drive, read (zdrive's reader, in still.fail's look): one column that scrolls, nothing over it until a tap
// brings the bars — frosted, floating over the page — and takes them away again. The top one says what and where (its
// chapter, how far) and searches; the bottom one steps chapters, jumps anywhere along a hairline with a knob, and opens
// the contents, the type and paper, and day or night. A hard-wrapped novel is reflowed into paragraphs, Markdown is drawn
// as Markdown, chapters (第X章, Chapter N, # headings) make the contents. Where it was left is kept on this device
// (drivePlace) and opened at next time.
package fail.still.android.drive

import fail.still.android.ui.LIST_ROW_CORNER
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import fail.still.android.ui.LazyColumn
import androidx.compose.foundation.lazy.LazyListLayoutInfo
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.drawBehind
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
import fail.still.android.data.ReaderPrefs
import fail.still.android.data.Topics
import fail.still.android.data.t
import fail.still.android.ui.Button
import fail.still.android.ui.PickRow
import fail.still.android.ui.activity
import fail.still.android.ui.fileSize
import fail.still.android.ui.C
import fail.still.android.ui.GlassBlur
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Seg
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.android.ui.concentric
import fail.still.android.ui.Progress
import fail.still.android.ui.WaitPill
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
import fail.still.android.data.DriveCache

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

/** The text `path` of `root` on `station`, read. */
@Composable
fun ReaderScreen(station: String, root: String, path: String) {
    val app = LocalApp.current
    val name = nameOf(path)
    // How it is laid out: the core's prefs (prefs.reader), the same on every page that reads.
    val prefs = app.readerPrefs
    val paper = Paper.of(prefs.paper)
    val typography = ReaderTypography.of(prefs)
    val p = paper.ink(C.dark)
    PaperBars(p.dark)
    val opening by produceState<Opening>(Opening.Coming(0, null), station, root, path) {
        value = try {
            // Kept on the phone by when it changed, as its folder says (DriveCache); one not in it is read each time.
            val entry = folderOf(app, station, root, parentOf(path)).firstOrNull { !it.dir && it.name == name }
            val (bytes, size) = if (entry != null) DriveCache.bytes(app.api(station), root, path, entry.mtime, entry.size, MAX_NOVEL_BYTES.toLong()) { got, of -> value = Opening.Coming(got, of) }
            else app.api(station).driveBytes(root, path, MAX_NOVEL_BYTES.toLong()) { got, of -> value = Opening.Coming(got, of) }.let { it to ((value as? Opening.Coming)?.of ?: it.size.toLong()) }
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
            is Opening.Ready -> Book(app, station, root, path, o.novel, o.at, p, typography)
            else -> {
                Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
                    when (o) {
                        // Its size known: how much has come, a bar under the words; else a wait's pill on the paper (its words in the
                        // paper's grey), said only once it takes a while.
                        is Opening.Coming -> if (o.of != null && o.of > 0) {
                            Text(t("android-misc.drive.reader.loading.size", "got" to fileSize(o.got), "size" to fileSize(o.of)), fontSize = 13.sp, color = p.muted, textAlign = TextAlign.Center)
                            Progress(o.got.toFloat() / o.of, Modifier.widthIn(max = 220.dp))
                        } else WaitPill(t("common.opening"), ground = Color.Transparent, ink = p.muted)
                        is Opening.Failed -> Text(t("android-misc.drive.reader.failed", "error" to o.why), fontSize = 14.sp, color = C.red, textAlign = TextAlign.Center)
                        else -> {}
                    }
                }
                // The way back is there while it comes.
                val haze = remember { HazeState() }
                TopBar(haze, p, name, "", onBack = app::pop, modifier = Modifier.align(Alignment.TopCenter))
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
private fun Book(app: AppState, station: String, root: String, path: String, novel: Novel, at: Int?, p: PaperInk, typography: ReaderTypography) {
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
        r.matches = withContext(Dispatchers.Default) { searchChunks(novel.chunks, r.query) }
        r.hit = -1
    }

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().hazeSource(haze)) {
            TextColumn(r, typography, p) { chrome = !chrome }
        }
        // The clock and the icons stay on the paper, not over the text running under them.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(p.ground))
        val chapter = r.chapter
        val sub = listOfNotNull(
            if (chapter >= 0 && r.hasChapters) novel.chapters[chapter].title else null,
            if (novel.truncated) t("android-misc.drive.reader.truncated", "size" to fileSize(MAX_NOVEL_BYTES.toLong())) else null,
        ).joinToString(" · ")
        Column(Modifier.align(Alignment.TopCenter)) {
            Box(Modifier.alpha(shown)) { if (shown > 0f) TopBar(haze, p, novel.title, sub, onBack = app::pop) }
            // Gone to a hit: where among them, a step to the one before and after, and away.
            if (r.hit >= 0 && r.matches.isNotEmpty()) FoundPill(haze, p, r, Modifier.align(Alignment.CenterHorizontally).padding(top = if (shown > 0f) 0.dp else 0.dp))
        }
        Box(Modifier.align(Alignment.BottomCenter).alpha(shown)) {
            if (shown > 0f) BottomBar(haze, p, r,
                onChapters = { openChapters(app, r) },
                onFind = { openSearch(app, r) },
                onLayout = { openLayout(app) })
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

/** What is open and where in it: back, its name, its chapter under it. */
@Composable
private fun TopBar(haze: HazeState, p: PaperInk, title: String, sub: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier.windowInsetsPadding(WindowInsets.statusBars).padding(horizontal = 8.dp, vertical = 6.dp).fillMaxWidth()
            // Its round keys (40) 6 from every edge: a capsule, concentric with them.
            .paperGlass(haze, Smooth(26.dp), p).height(52.dp).padding(horizontal = 6.dp),
    ) {
        Box(Modifier.align(Alignment.CenterStart)) { BarIcon(Icons.ChevronLeft, t("common.back"), p, onBack) }
        Column(Modifier.align(Alignment.Center).padding(horizontal = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = p.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
            if (sub.isNotEmpty()) Text(sub, fontSize = 12.sp, color = p.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        }
    }
}

/** A hit gone to: 「what」 which of how many, the one before and after, and the search let go. */
@Composable
private fun FoundPill(haze: HazeState, p: PaperInk, r: Reading, modifier: Modifier = Modifier) {
    Row(
        // A capsule as high as its round keys, the last one its end.
        modifier.padding(top = 6.dp).paperGlass(haze, Smooth(20.dp), p).height(40.dp).padding(start = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(t("android-misc.drive.reader.foundAt", "query" to r.query, "at" to r.hit + 1, "n" to r.matches.size), fontSize = 13.sp, color = p.ink, maxLines = 1, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.padding(end = 6.dp))
        BarIcon(Icons.ChevronLeft, t("android-misc.drive.reader.prevHit"), p) { r.step(-1) }
        BarIcon(Icons.ChevronRight, t("android-misc.drive.reader.nextHit"), p) { r.step(1) }
        BarIcon(Icons.Close, t("common.close"), p) { r.query = ""; r.hit = -1 }
    }
}

/** Chapters before and after, the jump along the whole text, and the contents, search, the layout. */
@Composable
private fun BottomBar(haze: HazeState, p: PaperInk, r: Reading, onChapters: () -> Unit, onFind: () -> Unit, onLayout: () -> Unit) {
    val novel = r.novel
    val ch = r.chapter
    Column(
        Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 8.dp, vertical = 8.dp).fillMaxWidth()
            // Its keys BAR_PAD from every edge, rounded concentric with it.
            .paperGlass(haze, Smooth(BAR_CORNER), p).padding(BAR_PAD),
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
            Text("${(r.fraction * 100).roundToInt()}%", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = p.ink, textAlign = TextAlign.End, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.width(40.dp))
        }
        Row {
            Tool(Icons.List, t("android-misc.drive.reader.contents"), p, onChapters)
            Tool(Icons.Search, t("android-misc.drive.reader.search"), p, onFind)
            Tool(Icons.Text, t("android-misc.drive.reader.type"), p, onLayout)
        }
    }
}

private val BAR_CORNER = 20.dp
private val BAR_PAD = 10.dp

/** A small key on the bar (上一章, 下一章); faded and inert when there is nowhere to go. */
@Composable
private fun TextKey(label: String, p: PaperInk, onClick: (() -> Unit)?) {
    Text(
        label, fontSize = 13.sp, color = if (onClick != null) p.ink else p.ink.copy(alpha = 0.3f), maxLines = 1,
        modifier = Modifier.clip(Smooth(concentric(BAR_CORNER, BAR_PAD))).background(p.ink.copy(alpha = if (onClick != null) 0.07f else 0.04f)).clickable(enabled = onClick != null) { onClick?.invoke() }
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

@Composable
private fun RowScope.Tool(icon: ImageVector, label: String, p: PaperInk, onClick: () -> Unit) {
    Column(
        Modifier.weight(1f).clip(Smooth(concentric(BAR_CORNER, BAR_PAD))).clickable(onClick = onClick).padding(vertical = 6.dp),
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

/** The contents: each chapter, the one being read checked; with none found, a jump by how far. */
private fun openChapters(app: AppState, r: Reading) {
    app.sheet = SheetSpec(if (r.hasChapters) 0.75f else 0.3f, draggable = r.hasChapters, fit = if (r.hasChapters) null else 200.dp) {
        val novel = r.novel
        SheetGrab()
        SheetHead(t("android-misc.drive.reader.contents"))
        if (!r.hasChapters) {
            Text(t("android-misc.drive.reader.noChapters"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            Box(Modifier.padding(horizontal = 20.dp)) { Hairline(r.fraction, C.ink.copy(alpha = 0.12f), C.accent, C.surface) { r.jumpTo(it) } }
        } else {
            val now = r.chapter
            val list = rememberLazyListState(initialFirstVisibleItemIndex = (now - 3).coerceAtLeast(0))
            LazyColumn(Modifier.weight(1f), state = list, contentPadding = PaddingValues(bottom = 16.dp)) {
                itemsIndexed(novel.chapters) { i, c ->
                    PickRow(c.title, checked = i == now) { r.jumpTo(c.chunk, c.offset); app.sheet = null }
                }
            }
        }
    }
}

/** Where a hit is, in a line: a little before it, it, a little after (as the web's search sheet lists them). */
private fun snippet(chunk: String, m: TextMatch, ink: Color, accent: Color): AnnotatedString {
    val from = (m.start - 18).coerceAtLeast(0)
    val to = (m.start + m.length + 40).coerceAtMost(chunk.length)
    val clean = { s: String -> s.replace('\n', ' ').replace('\u3000', ' ') }
    return buildAnnotatedString {
        append(if (from > 0) "…" else "")
        append(clean(chunk.substring(from, m.start)))
        pushStyle(SpanStyle(color = accent, fontWeight = FontWeight.SemiBold))
        append(clean(chunk.substring(m.start, (m.start + m.length).coerceAtMost(chunk.length))))
        pop()
        append(clean(chunk.substring((m.start + m.length).coerceAtMost(chunk.length), to)))
        if (to < chunk.length) append("…")
    }
}

/** Search in the whole text: what is typed found as it is typed, each hit a line to go to; then the pill steps through them. */
private fun openSearch(app: AppState, r: Reading) {
    app.sheet = SheetSpec(0.75f, draggable = true) {
        val focus = remember { FocusRequester() }
        LaunchedEffect(Unit) { delay(50); if (r.query.isEmpty()) runCatching { focus.requestFocus() } }
        val focused = androidx.compose.ui.platform.LocalFocusManager.current
        SheetGrab()
        SheetHead(t("android-misc.drive.reader.search"))
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.fillMaxWidth().clip(CircleShape).border(1.dp, C.line, CircleShape).padding(horizontal = 18.dp, vertical = 11.dp)) {
                if (r.query.isEmpty()) Text(t("android-misc.drive.reader.searchAll"), color = C.subtle, fontSize = 15.sp)
                BasicTextField(
                    r.query, { r.query = it }, singleLine = true, cursorBrush = SolidColor(C.accent),
                    textStyle = TextStyle(color = C.ink, fontSize = 15.sp),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
            if (r.query.isNotBlank()) Text(
                if (r.matches.isEmpty()) t("android-misc.drive.reader.notFound") else t("android-misc.drive.reader.foundCount", "n" to r.matches.size),
                fontSize = 13.sp, color = C.muted,
            )
        }
        LazyColumn(Modifier.weight(1f).padding(top = 6.dp), contentPadding = PaddingValues(bottom = 16.dp)) {
            itemsIndexed(r.matches.take(300)) { i, m ->
                val chunk = r.novel.chunks.getOrElse(m.chunk) { "" }
                val ink = C.ink
                val accent = C.accent
                Text(
                    remember(m, ink, accent) { snippet(chunk, m, ink, accent) }, fontSize = 15.sp, lineHeight = 22.sp, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(Smooth(LIST_ROW_CORNER)).clickable { focused.clearFocus(); r.hit = i; r.jumpTo(m.chunk, m.start); app.sheet = null }.padding(horizontal = 8.dp, vertical = 10.dp),
                )
            }
        }
    }
}

/** The layout: the type's size, the lines' height, the margins, the face, the indent and the paper, each kept by the core as it is changed. */
private fun openLayout(app: AppState) {
    app.sheet = SheetSpec(0.62f, draggable = true) {
        val prefs = app.readerPrefs
        fun put(shown: ReaderPrefs, field: String, value: kotlinx.serialization.json.JsonPrimitive) = app.setReader(shown, field, value)
        SheetGrab()
        SheetHead(t("android-misc.drive.reader.type"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Stepper(t("android-misc.drive.reader.size"), "${prefs.size}", prefs.size > ReaderTypography.MIN_FONT_SP, prefs.size < ReaderTypography.MAX_FONT_SP) { d ->
                val v = prefs.size + d; put(prefs.copy(size = v), "size", kotlinx.serialization.json.JsonPrimitive(v))
            }
            Stepper(t("android-misc.drive.reader.spacing"), "%.1f".format(prefs.line), prefs.line > ReaderTypography.MIN_LINE_SPACING + 1e-6, prefs.line < ReaderTypography.MAX_LINE_SPACING - 1e-6) { d ->
                val v = Math.round((prefs.line + d * 0.1) * 10) / 10.0; put(prefs.copy(line = v), "line", kotlinx.serialization.json.JsonPrimitive(v))
            }
            Stepper(t("android-misc.drive.reader.margin"), "${prefs.margin}", prefs.margin > ReaderTypography.MIN_MARGIN_DP, prefs.margin < ReaderTypography.MAX_MARGIN_DP) { d ->
                val v = prefs.margin + d * 2; put(prefs.copy(margin = v), "margin", kotlinx.serialization.json.JsonPrimitive(v))
            }
            SettingRow(t("android-misc.drive.reader.font")) {
                Seg(ReaderFamily.entries.map { it.label }, ReaderFamily.of(prefs.face).ordinal, { i -> val f = ReaderFamily.entries[i].key; put(prefs.copy(face = f), "face", kotlinx.serialization.json.JsonPrimitive(f)) }, height = 34.dp)
            }
            SettingRow(t("android-misc.drive.reader.indent")) {
                Seg(listOf(t("android-misc.drive.reader.indent.on"), t("android-misc.drive.reader.indent.off")), if (prefs.indent) 0 else 1, { i -> put(prefs.copy(indent = i == 0), "indent", kotlinx.serialization.json.JsonPrimitive(i == 0)) }, height = 34.dp)
            }
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(t("android-misc.drive.reader.paper"), fontSize = 15.sp, color = C.ink)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Paper.entries.forEach { option -> PaperSwatch(option, chosen = option.key == prefs.paper) { put(prefs.copy(paper = option.key), "paper", kotlinx.serialization.json.JsonPrimitive(option.key)) } }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

/** A setting's name on the left, its control on the right. */
@Composable
private fun SettingRow(label: String, control: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
        control()
    }
}

/** A number stepped down and up (− value +), each step stopping at its end. */
@Composable
private fun Stepper(label: String, value: String, less: Boolean, more: Boolean, step: (Int) -> Unit) {
    SettingRow(label) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StepKey(Icons.Minus, t("android-misc.drive.reader.less", "what" to label), less) { step(-1) }
            Text(value, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink, textAlign = TextAlign.Center, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.width(48.dp))
            StepKey(Icons.Plus, t("android-misc.drive.reader.more", "what" to label), more) { step(1) }
        }
    }
}

@Composable
private fun StepKey(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.07f)).clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { IconIn(icon, 18.dp, if (enabled) C.ink else C.subtle) }
}

/** One paper, drawn in itself: 文 on its own ground, its name under it; the chosen one ringed in the accent. */
@Composable
private fun PaperSwatch(option: Paper, chosen: Boolean, onClick: () -> Unit) {
    val ink = option.ink(C.dark)
    Column(Modifier.clip(Smooth(10.dp)).clickable(onClick = onClick).padding(2.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(50.dp).clip(CircleShape).then(if (chosen) Modifier.border(2.dp, C.accent, CircleShape) else Modifier.border(1.dp, C.line, CircleShape)).padding(if (chosen) 3.dp else 0.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.fillMaxSize().clip(CircleShape).then(
                // As the app looks: half its light page, half its dark one.
                if (option == Paper.Follow) Modifier.drawBehind {
                    drawRect(Paper.White.ink(false).ground)
                    drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(size.width, 0f); lineTo(size.width, size.height); lineTo(0f, size.height); close() }, Paper.Night.ink(true).ground)
                } else Modifier.background(ink.ground),
            ), contentAlignment = Alignment.Center) {
                Text(t("android-misc.drive.reader.sample"), fontSize = 18.sp, fontFamily = FontFamily.Serif, color = if (option == Paper.Follow) Color(0xFF808080) else ink.ink)
            }
        }
        Text(option.label, fontSize = 12.sp, color = if (chosen) C.ink else C.muted)
    }
}
