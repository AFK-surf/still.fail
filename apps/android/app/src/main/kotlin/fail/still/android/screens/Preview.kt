// A web service an agent started (a dev server, a report it serves), full screen over its chat: found by its job, known
// by its name (never its port), as web mobile's is (web/src/mobile/Preview.tsx over web/src/Preview.tsx). Its bar goes
// back, forward, reloads and says where it is (typed to go elsewhere); the page may be laid out at a size of its own
// (a phone's, a desktop's) on a canvas, moved and zoomed (PreviewStage.tsx), its sizes in a toolbar under the page, not
// over it; and it can be marked for the chat's agent (annotate/Marks.tsx): what is picked on the page, a word about
// each, then into the chat's draft with a screenshot per mark. The WebView's requests, sockets and marks go through
// PreviewWeb.kt. The job is its chat's, kept as the chat changes (a restart is said over the page, which loads again
// once the service is back).
package fail.still.android.screens

import fail.still.android.ui.t
import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.view.View
import android.view.ViewOutlineProvider
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import fail.still.android.ui.keyboard
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.Job
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.NavBar
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.core.CoreException
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** `service`: its job's id. */
@Composable
fun PreviewScreen(station: String, service: String) {
    val app = LocalApp.current
    // Kept current by the core (its events, or read again from a station too old to send them).
    val found by rememberTopic<Job>(app.core, Topics.job(station, service))
    val job = found.value
    val error = found.error?.message
    val session = job?.session
    val port = job?.port
    val up = port != null && job.open == true
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars))) {
        NavBar(t("android-chat.preview.back"), app::pop, job?.name ?: t("android-chat.preview.service"), sub = { Text(rememberStationName(station), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        when {
            error != null && job == null -> PreviewNote(t("android-chat.preview.notFound", "error" to error))
            job == null -> Unit
            !up -> PreviewNote(t("android-chat.preview.stopped", "name" to job.name))
            else -> ServicePage(station, service, port!!.toInt(), job.name, restarting = job.state == "exited", restarts = job.restarts ?: 0, session = session)
        }
    }
}

/**
 * A visualization an agent posted, as a page of its own (web mobile's Preview.tsx for a `file:` service): the file
 * served to the preview's page from here, with what its widget kept (and keeps from now on); its bar has only its name.
 */
@Composable
fun PreviewFileScreen(station: String, session: String, path: String, name: String) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val file = remember(path, name) { fail.still.android.data.Attachment(name = name, path = path, size = 0) }
    val loaded = fail.still.android.ui.rememberViz(station, session, file)
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars))) {
        NavBar(t("android-chat.preview.back"), app::pop, name, sub = { Text(rememberStationName(station), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        when (val l = loaded) {
            fail.still.android.ui.Loaded.Failed -> PreviewNote(t("android-chat.preview.unreadable", "name" to name))
            fail.still.android.ui.Loaded.Waiting -> Unit
            is fail.still.android.ui.Loaded.Ready -> {
                val kept = remember(l) { arrayOf(l.state) }
                val page = FilePage(l.html, { kept[0] }) { s ->
                    kept[0] = s
                    scope.launch { try { app.api(station).setWidgetState(session, path, s) } catch (_: CoreException) {} }
                }
                ServicePage(station, "file:$session\n$path", 0, name, restarting = false, restarts = 0, session = session, file = page)
            }
        }
    }
}

/** A visualization's page for [ServicePage]: its file, what its widget keeps now, and keeping what it keeps next. */
private class FilePage(val html: String, val state: () -> JsonElement?, val keep: (JsonElement) -> Unit)

@Composable
private fun PreviewNote(text: String) =
    Text(text, fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp))

// ── the page's size (web/src/viewport.ts) ──────────────────────────────

/** A window `width` wide and `height` high (null: as high as the preview leaves it, at its scale). */
private data class Viewport(val width: Int, val height: Int?)

private class Preset(val key: String, val width: Int, val height: Int) {
    val name: String get() = t("android-chat.preview.preset.$key")
}
private val PRESETS = listOf(Preset("phone", 390, 844), Preset("tablet", 820, 1180), Preset("laptop", 1280, 800), Preset("desktop", 1440, 900))
private const val LIMIT_MIN = 240
private const val LIMIT_MAX = 3840
private fun clampSize(n: Int) = n.coerceIn(LIMIT_MIN, LIMIT_MAX)

private fun presetOf(v: Viewport?): String? {
    if (v?.height == null) return null
    return PRESETS.firstOrNull { (it.width == v.width && it.height == v.height) || (it.width == v.height && it.height == v.width) }?.name
}

/** `390 × 844`, with `×` a little apart. */
private fun dims(w: Int, h: Int?) = "$w × ${h?.toString() ?: t("android-chat.preview.auto")}"

/** Kept per service, on this device. */
private fun viewportKey(station: String, service: String) = "previewViewport.$station\n$service"
private fun AppState.viewportOf(key: String): Viewport? {
    val kept = strings(key)
    val w = kept.getOrNull(0)?.toIntOrNull() ?: return null
    return Viewport(clampSize(w), kept.getOrNull(1)?.toIntOrNull()?.let(::clampSize))
}
private fun AppState.keepViewport(key: String, v: Viewport?) = setStrings(key, if (v == null) emptyList() else listOfNotNull(v.width.toString(), v.height?.toString()))

private const val FOLDED = "previewToolbarFolded"

// ── the page: its bar, its stage, its toolbar ──────────────────────────

/** A mark: what was picked on the page (annotate/frame.ts's Picked), and what is said about it. */
@Serializable
private data class Box4(val x: Float, val y: Float, val width: Float, val height: Float)
@Serializable
private data class Size2(val width: Int, val height: Int)
@Serializable
private data class PagePick(
    val n: Int, val path: String, val viewport: Size2, val label: String, val kind: String, val selector: String,
    val text: String, val rect: Box4, val page: Box4, val component: String? = null,
)
private class Mark(val picked: PagePick) { var comment by mutableStateOf("") }

/** A page's state that outlives its recompositions: where it is, its marks. */
private class PageState {
    var at by mutableStateOf<String?>(null)
    var canBack by mutableStateOf(false)
    var canForward by mutableStateOf(false)
    var marking by mutableStateOf(false)
    val marks = mutableStateListOf<Mark>()
    /** Where each mark is in the page's viewport, as the page last said; the viewport's width in CSS pixels. */
    val at2 = mutableStateMapOf<Int, Box4>()
    var cssWidth by mutableFloatStateOf(0f)
    var editing by mutableStateOf<Int?>(null)
    var busy by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
}

/** The service's page under its bar; `restarting`: it ended and the station starts it again (`restarts` so far). */
@Composable
private fun ColumnScope.ServicePage(station: String, service: String, port: Int, name: String, restarting: Boolean, restarts: Long, session: String?, file: FilePage? = null) {
    val app = LocalApp.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val state = remember { PageState() }
    // Typed: lint looks for the @JavascriptInterface methods of what is added to the WebView by its declared type.
    val link: PreviewLink = remember(station, port) {
        val script = context.assets.open("preview/page.js").use { it.readBytes() }
        PreviewLink(app.core, station, port, script)
    }
    DisposableEffect(link) { onDispose { link.close() } }
    // A visualization: its page is served from here (reloaded, with what it kept since), anything else it asks is not
    // there (as the web's FileFrame answers).
    val dark = C.dark
    if (file != null) link.serve = { method, path ->
        val served = method == "GET" && !Regex("\\.[a-z0-9]+$", RegexOption.IGNORE_CASE).containsMatchIn(path.substringBefore('?'))
        if (!served) android.webkit.WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), java.io.ByteArrayInputStream("Not found".toByteArray()))
        else {
            val doc = fail.still.android.ui.vizServed(context, file.html, file.state(), dark, String(pageScript(context.assets.open("preview/page.js").use { it.readBytes() })))
            android.webkit.WebResourceResponse("text/html", "utf-8", 200, "OK", mapOf("Cache-Control" to "no-store"), java.io.ByteArrayInputStream(doc.toByteArray()))
        }
    }
    // The system's back steps the page back first; at its first page it leaves.
    BackHandler(enabled = state.canBack) { link.web?.goBack() }
    // Up again after a restart: the page loads anew.
    var was by remember { mutableStateOf(restarting) }
    LaunchedEffect(restarting) {
        if (was && !restarting) link.web?.reload()
        was = restarting
    }
    val key = viewportKey(station, service)
    var viewport by remember(key) { mutableStateOf(app.viewportOf(key)) }
    val setViewport = { v: Viewport? -> val c = v?.let { Viewport(clampSize(it.width), it.height?.let(::clampSize)) }; viewport = c; app.keepViewport(key, c) }
    var folded by remember { mutableStateOf(app.flag(FOLDED, false)) }
    val fold = { v: Boolean -> folded = v; app.setFlag(FOLDED, v) }
    val stage = remember { StageState() }
    val turn = {
        val v = viewport
        if (v?.height != null) { stage.view = null; setViewport(Viewport(v.height, v.width)) }
    }
    val js = { code: String -> link.web?.evaluateJavascript(code, null); Unit }
    // What the page's marking says.
    link.onMarked = { said ->
        // The page's script says it (a page of the service may say anything there): what does not read is let go.
        try {
            when ((said["event"] as? JsonPrimitive)?.content) {
                "picked" -> {
                    val picked = try { StillFailJson.decodeFromJsonElement(PagePick.serializer(), said["mark"] ?: JsonNull) } catch (_: Exception) { null }
                    if (picked != null) {
                        state.marks += Mark(picked)
                        state.at2[picked.n] = picked.rect
                        state.cssWidth = picked.viewport.width.toFloat()
                        state.editing = picked.n
                        state.error = null
                    }
                }
                "focus" -> state.editing = (said["n"] as? JsonPrimitive)?.intOrNull
                "at" -> {
                    state.cssWidth = (said["width"] as? JsonPrimitive)?.content?.toFloatOrNull() ?: state.cssWidth
                    val boxes = (said["at"] as? JsonArray)?.mapNotNull { b ->
                        val o = b as? JsonObject ?: return@mapNotNull null
                        val n = (o["n"] as? JsonPrimitive)?.intOrNull ?: return@mapNotNull null
                        n to StillFailJson.decodeFromJsonElement(Box4.serializer(), o)
                    }?.toMap() ?: emptyMap()
                    state.at2.keys.retainAll(boxes.keys)
                    state.at2.putAll(boxes)
                }
            }
        } catch (_: Exception) {
        }
    }
    val markable = session != null
    val leave = { state.marks.clear(); state.at2.clear(); state.editing = null; state.error = null; state.marking = false; js("__stillfailMarks&&(__stillfailMarks.clear(),__stillfailMarks.on(false))") }
    PreviewBar(
        name, state.at, loading = if (file == null) ({ PreviewLoad(station, port) }) else null, go = { path -> link.web?.loadUrl("https://$PREVIEW_HOST$path") }, reload = { link.web?.reload() },
        back = { link.web?.goBack() }, forward = { link.web?.goForward() }, canBack = state.canBack, canForward = state.canForward,
        size = if (folded) ({ SizeButton(viewport) { fold(false) } }) else null, fixed = file != null,
        extra = if (markable) ({
            BarIcon(Icons.Edit, true, pressed = state.marking) {
                state.marking = !state.marking
                js("__stillfailMarks&&__stillfailMarks.on(${state.marking})")
            }
        }) else null,
        instead = if (markable && (state.marking || state.marks.isNotEmpty())) ({
            MarkMode(state, leave) {
                scope.launch { putIntoChat(app, link, state, station, session!!, name, leave) }
            }
        }) else null,
    )
    Stage(stage, viewport, moving = stage.moving, onFit = { stage.view = null }) { placed ->
        AndroidView(
            factory = { ctx ->
                // PreviewLink's methods the page calls are @JavascriptInterface (PreviewWeb.kt); lint, typed val or not,
                // sees remember's type parameter (T) here and finds none.
                @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
                val web = WebView(ctx).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    setBackgroundColor(android.graphics.Color.WHITE)
                    addJavascriptInterface(link, "StillFailPreviewNative")
                    if (file != null) addJavascriptInterface(fail.still.android.ui.VizKeeper { s -> post { file.keep(s) } }, "StillFailViz")
                    webViewClient = PreviewClient(link, moved = { v ->
                        state.at = v.url?.let { url ->
                            val uri = android.net.Uri.parse(url)
                            if (uri.host == PREVIEW_HOST) pathOf(uri) else url
                        }
                        state.canBack = v.canGoBack()
                        state.canForward = v.canGoForward()
                    }, started = {
                        // Another page: the marks of the one before are gone (picking goes on).
                        state.marks.clear(); state.at2.clear(); state.editing = null
                    }, loaded = {
                        if (state.marking) js("__stillfailMarks&&__stillfailMarks.on(true)")
                    }, leave = { url ->
                        app.openLink(url.toString()) { try { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, url)) } catch (_: Exception) { app.toast = t("android-chat.link.failed") } }
                    })
                    loadUrl("https://$PREVIEW_HOST/")
                }
                link.web = web
                FrameLayout(ctx).apply { clipChildren = true; addView(web, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)) }
            },
            update = { frame -> place(frame.getChildAt(0), placed) },
            onRelease = { frame -> (frame.getChildAt(0) as? WebView)?.destroy(); link.web = null },
            modifier = Modifier.fillMaxSize(),
        )
        if (markable && state.marks.isNotEmpty()) MarksOver(state, placed, js)
        if (restarting) Restart(name, restarts, Modifier.align(Alignment.BottomCenter).padding(bottom = 18.dp))
    }
    if (!folded) Dock(viewport != null) {
        Toolbar(stage, viewport, setViewport, turn, fold = { fold(true) }, custom = { openViewportSheet(app, viewport, setViewport, turn) })
    }
}

// ── the bar ────────────────────────────────────────────────────────────

/** Back, forward, reload, where it is (its name, then its path, typed to go elsewhere), then its size and marking. */
@Composable
private fun PreviewBar(
    name: String, at: String?, go: (String) -> Unit, reload: () -> Unit, back: () -> Unit, forward: () -> Unit, canBack: Boolean, canForward: Boolean,
    loading: (@Composable () -> Unit)? = null, size: (@Composable () -> Unit)?, extra: (@Composable () -> Unit)?, instead: (@Composable () -> Unit)?, fixed: Boolean = false,
) {
    val focus = LocalFocusManager.current
    var typed by remember { mutableStateOf(at ?: "/") }
    var editing by remember { mutableStateOf(false) }
    // Where it went is what the bar says, unless someone is typing there.
    LaunchedEffect(at, editing) { if (at != null && !editing) typed = at }
    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 10.dp, top = 4.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        BarIcon(Icons.ArrowLeft, canBack, onClick = back)
        BarIcon(Icons.ArrowRight, canForward, onClick = forward)
        BarIcon(Icons.Refresh, true, onClick = reload)
        loading?.invoke()
        if (instead != null) Box(Modifier.weight(1f).padding(horizontal = 4.dp)) { instead() }
        else Row(
            Modifier.weight(1f).padding(horizontal = 4.dp).height(30.dp).clip(RoundedCornerShape(15.dp))
                .background(if (editing) C.surface else C.chip)
                .then(if (editing) Modifier.border(1.5.dp, C.accent.copy(alpha = 0.5f), RoundedCornerShape(15.dp)) else Modifier)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            IconIn(Icons.Web, 14.dp, C.muted)
            Text(name, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis, modifier = if (fixed) Modifier.weight(1f, fill = false) else Modifier)
            // Nowhere else to go (a visualization): the address is only its name.
            if (!fixed) BasicTextField(
                typed, { typed = it }, singleLine = true,
                textStyle = TextStyle(fontSize = 16.sp, color = if (editing) C.ink else C.muted),
                cursorBrush = SolidColor(C.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go, keyboardType = KeyboardType.Uri),
                keyboardActions = KeyboardActions(onGo = {
                    go(if (typed.startsWith("/")) typed else "/$typed")
                    focus.clearFocus()
                }),
                modifier = Modifier.weight(1f).onFocusChanged { editing = it.isFocused },
            )
        }
        size?.invoke()
        extra?.invoke()
    }
}

@Composable
private fun BarIcon(icon: ImageVector, enabled: Boolean, pressed: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier.size(28.dp).clip(CircleShape).background(if (pressed) C.accent.copy(alpha = 0.14f) else Color.Transparent).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { IconIn(icon, 14.dp, if (pressed) C.accentInk else C.ink, Modifier.alpha(if (enabled) 1f else 0.35f)) }
}

/** The bar's size button, once the toolbar was folded away: it opens it again. */
@Composable
private fun SizeButton(viewport: Viewport?, onClick: () -> Unit) {
    Row(
        Modifier.height(28.dp).clip(RoundedCornerShape(14.dp)).background(if (viewport != null) C.chip else Color.Transparent).clickable(onClick = onClick).padding(horizontal = if (viewport != null) 9.dp else 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        IconIn(Icons.Devices, 14.dp, C.ink)
        if (viewport != null) Text(dims(viewport.width, viewport.height), fontSize = 12.sp, color = C.ink, maxLines = 1)
    }
}

/** Over the page while its service starts again; once it is up the page loads anew. */
@Composable
private fun Restart(name: String, restarts: Long, modifier: Modifier) {
    Row(
        modifier.shadow(8.dp, CircleShape).clip(CircleShape).background(C.surface).padding(start = 16.dp, end = 18.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        JobDot(Tone.Restart)
        Column {
            Text(t("android-chat.preview.restarting", "name" to name), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(if (restarts > 0) t("android-chat.preview.restarts", "n" to restarts) else t("android-chat.preview.reloads"), fontSize = 12.sp, color = C.muted)
        }
    }
}

// ── the stage (PreviewStage.tsx) ───────────────────────────────────────

/** Where the page is drawn in the stage, in pixels: its top-left, its scale, the size it is laid out at. */
private data class Placed(val x: Float, val y: Float, val scale: Float, val width: Float, val height: Float, val corner: Float)
private data class ViewAt(val x: Float, val y: Float, val scale: Float)

private class StageState {
    /** Moved or zoomed by hand (null: fitted). */
    var view by mutableStateOf<ViewAt?>(null)
    var moving by mutableStateOf(false)
    var placed: Placed? = null
    var room = androidx.compose.ui.geometry.Size.Zero
    var pad = Offset.Zero
    fun zoom(factor: Float, about: Offset? = null) {
        val p = placed ?: return
        val scale = (p.scale * factor).coerceIn(0.05f, 4f)
        val at = about ?: Offset(pad.x + room.width / 2, pad.y + room.height / 2)
        view = ViewAt(at.x - (at.x - p.x) * scale / p.scale, at.y - (at.y - p.y) * scale / p.scale, scale)
    }
}

/** Two fingers gone from `was` to `at`: the page (drawn as `from` when they came down) zoomed by how far apart they went. */
private fun pinch(from: ViewAt, was: List<Offset>, at: List<Offset>): ViewAt {
    val mid = { ps: List<Offset> -> (ps[0] + ps[1]) / 2f }
    val apart = { ps: List<Offset> -> hypot(ps[0].x - ps[1].x, ps[0].y - ps[1].y).coerceAtLeast(1f) }
    val m0 = mid(was); val m1 = mid(at)
    val scale = (from.scale * apart(at) / apart(was)).coerceIn(0.05f, 4f)
    return ViewAt(m1.x - (m0.x - from.x) * scale / from.scale, m1.y - (m0.y - from.y) * scale / from.scale, scale)
}

/** The page's corners, as its screen's: a phone's round, a tablet's less, a desktop's all but square. */
private fun cornerOf(width: Int, scale: Float): Float = when { width <= 600 -> 44f; width < 1024 -> 24f; else -> 5f / scale }

/**
 * All of the preview, or — laid out at a size of its own — a canvas with the page on it: fitted and centred at first;
 * then the ground dragged (or, in the toolbar's moving mode, the page), two fingers anywhere zoom and move it, a double
 * tap on the ground fits it again. `content` gets where the page is (null: all of it).
 */
@Composable
private fun ColumnScope.Stage(stage: StageState, viewport: Viewport?, moving: Boolean, onFit: () -> Unit, content: @Composable androidx.compose.foundation.layout.BoxScope.(Placed?) -> Unit) {
    val density = LocalDensity.current
    val ground = lerp(C.surface, C.chip, 0.55f)
    // A size chosen (or turned) is fitted anew.
    LaunchedEffect(viewport) { stage.view = null }
    BoxWithConstraints(Modifier.fillMaxWidth().weight(1f).clipToBounds().background(if (viewport != null) ground else C.surface)) {
        val pad = if (viewport != null) with(density) { 16.dp.toPx() } else 0f
        val roomW = constraints.maxWidth - 2 * pad
        val roomH = constraints.maxHeight - 2 * pad
        val px = density.density
        val placed = if (viewport != null && roomW > 0 && roomH > 0) {
            val w = viewport.width * px
            val fitted = maxOf(0.05f, floor(minOf(1f, roomW / w, viewport.height?.let { roomH / (it * px) } ?: 1f) * 1000f) / 1000f)
            val free = stage.view
            val scale = free?.scale ?: fitted
            val h = (viewport.height ?: maxOf(LIMIT_MIN, floor(roomH / fitted / px).toInt())) * px
            Placed(
                x = free?.x ?: (pad + maxOf(0f, (roomW - w * scale) / 2)).roundToInt().toFloat(),
                y = free?.y ?: (pad + maxOf(0f, (roomH - h * scale) / 2)).roundToInt().toFloat(),
                scale = scale, width = w, height = h, corner = cornerOf(viewport.width, scale) * px,
            )
        } else null
        stage.placed = placed
        stage.room = androidx.compose.ui.geometry.Size(roomW, roomH)
        stage.pad = Offset(pad, pad)
        val canvas = placed != null
        val fit by rememberUpdatedState(onFit)
        Box(
            Modifier.fillMaxSize().pointerInput(canvas, moving) {
                if (!canvas) return@pointerInput
                var lastTap = 0L
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    val p0 = stage.placed ?: return@awaitEachGesture
                    val onPage = down.position.x in p0.x..(p0.x + p0.width * p0.scale) && down.position.y in p0.y..(p0.y + p0.height * p0.scale)
                    var grabbing = moving || !onPage
                    if (grabbing) down.consume()
                    var from = ViewAt(p0.x, p0.y, p0.scale)
                    var was = listOf(down.position)
                    var travelled = 0f
                    val began = System.currentTimeMillis()
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        val pressed = event.changes.filter { it.pressed }
                        if (pressed.isEmpty()) break
                        val at = pressed.map { it.position }
                        if (!grabbing && pressed.size >= 2) grabbing = true
                        if (!grabbing) continue
                        if (at.size != was.size) {
                            // A finger came or went: from where the page is now.
                            val p = stage.placed ?: break
                            from = ViewAt(p.x, p.y, p.scale); was = at
                        } else if (at.size == 1) {
                            travelled += (at[0] - was[0]).getDistance()
                            stage.view = ViewAt(from.x + at[0].x - was[0].x, from.y + at[0].y - was[0].y, from.scale)
                        } else {
                            stage.view = pinch(from, was.take(2), at.take(2))
                        }
                        event.changes.forEach { it.consume() }
                    }
                    // A double tap on the ground fits it again.
                    if (!onPage && travelled < 12f && System.currentTimeMillis() - began < 300) {
                        val now = System.currentTimeMillis()
                        if (now - lastTap < 350) { fit(); lastTap = 0L } else lastTap = now
                    }
                }
            },
        ) {
            // Its slight shadow and its screen's corners are the page's view's own (PreviewWeb's place()).
            content(placed)
        }
    }
}

/** Puts the page's view where the stage has it: all of the stage, or its own size at its place and scale. */
private fun place(view: View, placed: Placed?) {
    val lp = view.layoutParams as FrameLayout.LayoutParams
    val w = placed?.width?.roundToInt() ?: FrameLayout.LayoutParams.MATCH_PARENT
    val h = placed?.height?.roundToInt() ?: FrameLayout.LayoutParams.MATCH_PARENT
    if (lp.width != w || lp.height != h) { lp.width = w; lp.height = h; view.layoutParams = lp }
    view.pivotX = 0f
    view.pivotY = 0f
    view.translationX = placed?.x ?: 0f
    view.translationY = placed?.y ?: 0f
    view.scaleX = placed?.scale ?: 1f
    view.scaleY = placed?.scale ?: 1f
    val corner = placed?.corner ?: 0f
    view.outlineProvider = object : ViewOutlineProvider() {
        override fun getOutline(v: View, outline: Outline) = outline.setRoundRect(0, 0, v.width, v.height, corner)
    }
    view.clipToOutline = placed != null
    view.elevation = if (placed != null) 6f * view.resources.displayMetrics.density else 0f
}

// ── the toolbar under the page (PreviewStage.tsx's Toolbar) ────────────

/** The toolbar's place, under the stage, on its ground. */
@Composable
private fun Dock(sized: Boolean, content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().background(if (sized) lerp(C.surface, C.chip, 0.55f) else C.surface).padding(start = 10.dp, end = 10.dp, bottom = 10.dp)) { content() }
}

/**
 * A floating capsule: the sizes (the one chosen marked; "自定义" opens them all in a sheet), turning, moving the page by
 * a finger, and fitting it again once moved. Held down, it folds away (the bar's size button opens it again).
 */
@Composable
private fun Toolbar(stage: StageState, viewport: Viewport?, set: (Viewport?) -> Unit, turn: () -> Unit, fold: () -> Unit, custom: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val choose = { v: Viewport? -> stage.moving = false; set(v) }
    val preset = presetOf(viewport)
    val isCustom = viewport != null && preset == null
    val glass = if (C.dark) C.surface2.copy(alpha = 0.84f) else C.surface.copy(alpha = 0.72f)
    Row(
        Modifier.fillMaxWidth().height(48.dp).shadow(4.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.12f), spotColor = Color.Black.copy(alpha = 0.12f))
            .clip(CircleShape).background(glass)
            // Held half a second without moving: folded away, and what it was held on is not tapped.
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    val held = withTimeoutOrNull(500) {
                        var still = true
                        while (still) {
                            val e = awaitPointerEvent(PointerEventPass.Initial)
                            val c = e.changes.firstOrNull { it.id == down.id }
                            if (c == null || !c.pressed || (c.position - down.position).getDistance() > 8.dp.toPx()) still = false
                        }
                        false
                    } == null
                    if (held) {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        stage.moving = false
                        fold()
                        while (true) {
                            val e = awaitPointerEvent(PointerEventPass.Initial)
                            e.changes.forEach { it.consume() }
                            if (e.changes.none { it.pressed }) break
                        }
                    }
                }
            }
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Chip(t("android-chat.preview.fit"), viewport == null) { choose(null) }
            PRESETS.forEach { p -> Chip(p.name, preset == p.name) { choose(if (preset == p.name) viewport else Viewport(p.width, p.height)) } }
            Chip(if (isCustom) dims(viewport!!.width, viewport.height) else t("android-chat.preview.custom"), isCustom, custom)
        }
        if (viewport != null) Row(Modifier.padding(start = 4.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            if (viewport.height != null) Tool(Icons.Landscape, false, turn)
            Tool(Icons.Move, stage.moving) { stage.moving = !stage.moving }
            if (stage.view != null) Box(
                Modifier.height(36.dp).clip(CircleShape).background(C.surface).clickable { stage.view = null; stage.moving = false }.padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) { Text(t("android-chat.preview.fitView"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1) }
        }
    }
}

@Composable
private fun Chip(label: String, on: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.height(36.dp).then(if (on) Modifier.shadow(1.dp, CircleShape) else Modifier).clip(CircleShape)
            .background(if (on) (if (C.dark) C.bg else C.surface) else Color.Transparent).clickable(onClick = onClick).padding(horizontal = 13.dp),
        contentAlignment = Alignment.Center,
    ) { Text(label, fontSize = 13.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, color = if (on) C.ink else C.muted, maxLines = 1, softWrap = false) }
}

@Composable
private fun Tool(icon: ImageVector, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(36.dp).clip(CircleShape).background(if (on) C.accent else Color.Transparent).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        IconIn(icon, 18.dp, if (on) Color.White else C.ink)
    }
}

/** All the sizes in a sheet (the toolbar's "自定义"): as big as the preview, the presets, any size typed, turned. */
private fun openViewportSheet(app: AppState, first: Viewport?, set: (Viewport?) -> Unit, turn: () -> Unit) {
    app.sheet = SheetSpec(0.62f) {
        var viewport by remember { mutableStateOf(first) }
        val put = { v: Viewport? -> viewport = v; set(v) }
        val choose = { v: Viewport? -> put(v); app.sheet = null }
        val preset = presetOf(viewport)
        SheetGrab()
        SheetHead(t("android-chat.preview.size.title"))
        Column(Modifier.padding(start = 10.dp, end = 10.dp, bottom = 24.dp)) {
            SizeOption(viewport == null, t("android-chat.preview.fit"), t("android-chat.preview.fit.note")) { choose(null) }
            PRESETS.forEach { p -> SizeOption(preset == p.name, p.name, dims(p.width, p.height)) { choose(if (preset == p.name) viewport else Viewport(p.width, p.height)) } }
            Spacer(Modifier.height(10.dp))
            CustomSize(viewport, put) {
                val v = viewport
                if (v?.height != null) { viewport = Viewport(v.height, v.width); turn() }
            }
        }
    }
}

@Composable
private fun SizeOption(checked: Boolean, name: String, note: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.width(18.dp), contentAlignment = Alignment.Center) { if (checked) IconIn(Icons.Check, 16.dp, C.accent) }
        Text(name, fontSize = 15.sp, color = C.ink, fontWeight = if (checked) FontWeight.Medium else FontWeight.Normal, modifier = Modifier.weight(1f))
        Text(note, fontSize = 13.sp, color = C.muted)
    }
}

/** Any size, typed: the width, and the height (empty: as high as the preview leaves it); turned by the button. */
@Composable
private fun CustomSize(viewport: Viewport?, set: (Viewport?) -> Unit, turn: () -> Unit) {
    var w by remember { mutableStateOf(viewport?.width?.toString() ?: "") }
    var h by remember { mutableStateOf(viewport?.height?.toString() ?: "") }
    var typing by remember { mutableStateOf(false) }
    LaunchedEffect(viewport, typing) { if (!typing) { w = viewport?.width?.toString() ?: ""; h = viewport?.height?.toString() ?: "" } }
    val commit = {
        val width = w.toIntOrNull()
        val height = if (h.isBlank()) null else h.toIntOrNull()
        if (width != null && (h.isBlank() || height != null) && !(viewport != null && width == viewport.width && height == viewport.height)) set(Viewport(width, height))
    }
    val focus = LocalFocusManager.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(t("android-chat.preview.custom"), fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
        @Composable fun Field(value: String, change: (String) -> Unit, hint: String) = Box(
            Modifier.width(72.dp).height(36.dp).clip(RoundedCornerShape(10.dp)).background(C.chip).padding(horizontal = 10.dp), contentAlignment = Alignment.CenterStart,
        ) {
            if (value.isEmpty()) Text(hint, fontSize = 15.sp, color = C.subtle)
            BasicTextField(
                value, { change(it.filter(Char::isDigit).take(4)) }, singleLine = true,
                textStyle = TextStyle(fontSize = 15.sp, color = C.ink, textAlign = TextAlign.Start), cursorBrush = SolidColor(C.accent),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { commit(); focus.clearFocus() }),
                modifier = Modifier.fillMaxWidth().onFocusChanged { if (it.isFocused) typing = true else if (typing) { typing = false; commit() } },
            )
        }
        Field(w, { w = it }, t("android-chat.preview.width"))
        Text("×", fontSize = 14.sp, color = C.muted)
        Field(h, { h = it }, t("android-chat.preview.auto"))
        val turnable = viewport?.height != null
        Box(Modifier.size(36.dp).clip(CircleShape).clickable(enabled = turnable, onClick = turn), contentAlignment = Alignment.Center) {
            IconIn(Icons.Landscape, 18.dp, C.ink, Modifier.alpha(if (turnable) 1f else 0.35f))
        }
    }
}

// ── marking the page (annotate/Marks.tsx) ──────────────────────────────

/** In the address's place while marking: what to do or how many, then putting them into the chat. */
@Composable
private fun MarkMode(state: PageState, leave: () -> Unit, send: () -> Unit) {
    val n = state.marks.size
    Row(
        Modifier.fillMaxWidth().height(30.dp).clip(RoundedCornerShape(15.dp)).background(lerp(C.chip, C.accent, 0.10f)).padding(start = 12.dp, end = 3.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(if (state.marking) 13.dp else 7.dp).clip(CircleShape).background(if (state.marking) C.accent.copy(alpha = 0.22f) else Color.Transparent),
            contentAlignment = Alignment.Center,
        ) { Box(Modifier.size(7.dp).clip(CircleShape).background(if (state.marking) C.accent else C.muted)) }
        val error = state.error
        if (error != null) Text(error, fontSize = 13.sp, color = C.red, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        else Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (n > 0) t("android-chat.preview.marked", "n" to n) else t("android-chat.preview.pick"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, softWrap = false)
            if (state.marking && n > 0) Text(t("android-chat.preview.pickMore"), fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.size(24.dp).clip(CircleShape).clickable(enabled = !state.busy, onClick = leave), contentAlignment = Alignment.Center) { IconIn(Icons.Close, 12.dp, C.muted) }
        val able = !state.busy && n > 0
        val ground = if (able) C.ink else C.ink.copy(alpha = 0.4f)
        val ink = if (C.dark) C.bg else Color.White
        Row(
            Modifier.height(24.dp).clip(RoundedCornerShape(12.dp)).background(ground)
                .clickable(enabled = able, onClick = send).padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            IconIn(Icons.Send, 12.dp, ink)
            Text(if (state.busy) t("android-chat.preview.shooting") else t("android-chat.preview.put"), fontSize = 12.sp, fontWeight = FontWeight.Medium, color = ink, maxLines = 1, softWrap = false)
        }
    }
}

/** The marks over the page, where it is drawn: each a numbered pin on its element's corner, what is said beside it. */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.MarksOver(state: PageState, placed: Placed?, js: (String) -> Unit) {
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val stageW = constraints.maxWidth.toFloat()
        val originX = placed?.x ?: 0f
        val originY = placed?.y ?: 0f
        val viewW = placed?.width ?: stageW
        val scale = placed?.scale ?: 1f
        // CSS pixels to the stage's: the page's own ratio, then the stage's scale.
        val k = if (state.cssWidth > 0) viewW / state.cssWidth * scale else density.density * scale
        with(density) {
            state.marks.forEach { m ->
                val b = state.at2[m.picked.n] ?: m.picked.rect
                val x = originX + b.x * k; val y = originY + b.y * k
                val w = b.width * k; val h = b.height * k
                val open = state.editing == m.picked.n
                Box(
                    Modifier.offset { IntOffset(x.roundToInt(), y.roundToInt()) }.size(w.toDp(), h.toDp())
                        .border(if (open) 2.dp else 1.5.dp, if (open) C.accent else C.accent.copy(alpha = 0.55f), RoundedCornerShape(4.dp))
                        .background(if (open) C.accent.copy(alpha = 0.08f) else Color.Transparent, RoundedCornerShape(4.dp)),
                )
                // The pin's point on the element's top-left corner (kept in sight at the page's edges).
                val pinX = maxOf(2.dp.toPx(), x); val pinY = maxOf(24.dp.toPx(), y)
                val pinShape = RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp, bottomEnd = 12.dp, bottomStart = 3.dp)
                Box(
                    Modifier.offset { IntOffset((pinX - 2.dp.toPx()).roundToInt(), (pinY - 22.dp.toPx()).roundToInt()) }.size(24.dp)
                        .shadow(3.dp, pinShape).clip(pinShape).background(Color.White).padding(2.dp).clip(pinShape).background(C.accent)
                        .clickable { state.editing = if (open) null else m.picked.n },
                    contentAlignment = Alignment.Center,
                ) { Text("${m.picked.n}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White) }
                if (open) Note(m, pinX, pinY, stageW, onDone = { state.editing = null }, onRemove = {
                    state.marks.remove(m); state.at2.remove(m.picked.n); state.editing = null
                    js("__stillfailMarks&&__stillfailMarks.remove(${m.picked.n})")
                })
                else if (m.comment.isNotEmpty()) {
                    // Beside the pin, on its left when the right has too little room.
                    val right = stageW - pinX - 36.dp.toPx() >= minOf(220.dp.toPx(), pinX - 14.dp.toPx())
                    val maxW = if (right) stageW - pinX - 36.dp.toPx() else pinX - 14.dp.toPx()
                    Box(
                        Modifier.offset { IntOffset(if (right) (pinX + 28.dp.toPx()).roundToInt() else 0, (pinY - 23.dp.toPx()).roundToInt()) }
                            .then(if (right) Modifier else Modifier.width((pinX - 6.dp.toPx()).toDp()))
                            .widthIn(max = maxW.coerceAtLeast(40f).toDp()),
                        contentAlignment = if (right) Alignment.CenterStart else Alignment.CenterEnd,
                    ) {
                        Text(
                            m.comment, fontSize = 12.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.height(26.dp).shadow(3.dp, RoundedCornerShape(13.dp)).clip(RoundedCornerShape(13.dp)).background(bubble())
                                .clickable { state.editing = m.picked.n }.padding(horizontal = 10.dp, vertical = 5.dp),
                        )
                    }
                }
            }
        }
    }
}

/** Frosted, as still.fail's own floating things are (over a page, which cannot be blurred here: thick). */
@Composable
private fun bubble() = if (C.dark) C.surface2.copy(alpha = 0.94f) else C.surface.copy(alpha = 0.94f)

/** What is said about one mark, in a bubble beside its pin. */
@Composable
private fun Note(mark: Mark, x: Float, y: Float, stageW: Float, onDone: () -> Unit, onRemove: () -> Unit) {
    val density = LocalDensity.current
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    with(density) {
        val width = minOf(280.dp.toPx(), stageW - 16.dp.toPx())
        val left = (x + 28.dp.toPx()).coerceIn(8.dp.toPx(), maxOf(8.dp.toPx(), stageW - width - 8.dp.toPx()))
        val top = maxOf(8.dp.toPx(), y - 28.dp.toPx())
        Row(
            Modifier.offset { IntOffset(left.roundToInt(), top.roundToInt()) }.width(width.toDp()).height(36.dp)
                .shadow(6.dp, RoundedCornerShape(18.dp)).clip(RoundedCornerShape(18.dp)).background(bubble()).padding(start = 12.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (mark.comment.isEmpty()) Text(t("android-chat.preview.mark.comment", "kind" to mark.picked.kind), fontSize = 13.sp, color = C.muted, maxLines = 1)
                BasicTextField(
                    mark.comment, { mark.comment = it }, singleLine = true,
                    textStyle = TextStyle(fontSize = 13.sp, color = C.ink), cursorBrush = SolidColor(C.accent),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { onDone() }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
            Box(Modifier.size(28.dp).clip(CircleShape).clickable(onClick = onRemove), contentAlignment = Alignment.Center) { IconIn(Icons.Trash, 14.dp, C.muted) }
        }
    }
}

/**
 * Where a mark is, as the agent reads it with its screenshot `shot` (the file's name). The first line is also what
 * the composer shows.
 */
private fun where(p: PagePick, shot: String): String = listOfNotNull(
    if (p.text.isNotEmpty()) t("android-chat.preview.where.text", "kind" to p.kind, "text" to p.text) else p.kind,
    t("android-chat.preview.where.element", "label" to p.label, "selector" to p.selector),
    t("android-chat.preview.where.page", "path" to p.path, "width" to p.viewport.width, "height" to p.viewport.height, "shot" to shot),
    p.component?.let { t("android-chat.preview.where.component", "name" to it) },
).joinToString("\n")

/** Runs the page's script, and hands back what it returned. */
private suspend fun WebView.eval(code: String): String? = suspendCancellableCoroutine { done -> evaluateJavascript(code) { done.resume(it) } }

/**
 * Puts the marks into the chat's draft: one screenshot each, of what the window shows with only that mark drawn on it
 * (a mark scrolled out of sight gets the window's worth of page around it), and a quote each saying where it is.
 */
private suspend fun putIntoChat(app: AppState, link: PreviewLink, state: PageState, station: String, session: String, name: String, leave: () -> Unit) {
    val web = link.web ?: return
    if (state.marks.isEmpty()) return
    state.busy = true
    state.error = null
    state.editing = null
    try {
        val stamp = java.text.SimpleDateFormat("HHmmss", java.util.Locale.ROOT).format(java.util.Date())
        val y0 = returned(web.eval("scrollY"))?.jsonPrimitive?.content?.toFloatOrNull() ?: 0f
        // What the window shows now, taken once for every mark in sight.
        var now: Bitmap? = null
        val pictures = ArrayList<Picked2>()
        val quotes = ArrayList<OfferQuote>()
        for (m in state.marks.toList()) {
            var place = returned(web.eval("__stillfailMarks.place(${m.picked.n},false)"))?.jsonObject ?: throw IllegalStateException(t("android-chat.preview.mark.gone", "n" to m.picked.n))
            val cssW = place["width"]!!.jsonPrimitive.content.toFloat()
            val ratio = web.width / cssW
            val inSight = place.box().let { b -> b.y + b.height > 0 && b.y * ratio < web.height }
            val shot = if (inSight) {
                now ?: link.shot().also { now = it }
            } else {
                place = returned(web.eval("__stillfailMarks.place(${m.picked.n},true)"))?.jsonObject ?: place
                delay(160)
                link.shot().also { web.eval("__stillfailMarks.back($y0)") }
            } ?: throw IllegalStateException(t("android-chat.preview.shot.failed"))
            val b = place.box()
            val drawn = withContext(Dispatchers.Default) { drawMark(shot, m.picked.n, b.x * ratio, b.y * ratio, b.width * ratio, b.height * ratio, ratio) }
            val file = t("android-chat.preview.mark.file", "name" to name, "n" to m.picked.n, "stamp" to stamp)
            pictures += drawn.copy(name = file)
            quotes += OfferQuote(t("android-chat.preview.mark.quote", "name" to name, "n" to m.picked.n), where(m.picked, file), m.comment.trim(), file)
        }
        DraftOffers.waiting += MarkOffer(station, session, pictures.map { Picked(it.name, it.bytes, it.width, it.height, it.preview) }, quotes)
        app.toast = t("android-chat.preview.put.done")
        leave()
    } catch (e: Exception) {
        state.error = t("android-chat.preview.put.failed", "error" to e.message)
    } finally {
        state.busy = false
    }
}

private fun JsonObject.box() = Box4(this["x"]!!.jsonPrimitive.content.toFloat(), this["y"]!!.jsonPrimitive.content.toFloat(), this["width"]!!.jsonPrimitive.content.toFloat(), this["height"]!!.jsonPrimitive.content.toFloat())

private data class Picked2(val name: String, val bytes: ByteArray, val width: Int, val height: Int, val preview: androidx.compose.ui.graphics.ImageBitmap?)

/** A picture with one mark drawn on it, as the page shows marks: its outline, its number in a pin on its corner. */
private fun drawMark(shot: Bitmap, n: Int, x: Float, y: Float, w: Float, h: Float, ratio: Float): Picked2 {
    // At most two pixels to the page's CSS pixel.
    val k = minOf(1f, 2f / ratio)
    val out = Bitmap.createBitmap((shot.width * k).roundToInt().coerceAtLeast(1), (shot.height * k).roundToInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
    val g = android.graphics.Canvas(out)
    g.scale(k, k)
    g.drawBitmap(shot, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
    val mark = 0xFFEF6A3C.toInt()
    val u = ratio
    val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 2f * u; color = mark }
    g.drawRoundRect(RectF(x, y, x + w, y + h), 3f * u, 3f * u, line)
    val px = maxOf(2f * u, x) - 2f * u
    val py = maxOf(24f * u, y) - 22f * u
    fun pin(l: Float, t: Float, s: Float, r: Float, paint: Paint) {
        val path = android.graphics.Path()
        path.addRoundRect(RectF(l, t, l + s, t + s), floatArrayOf(r, r, r, r, r, r, 3f * u, 3f * u), android.graphics.Path.Direction.CW)
        g.drawPath(path, paint)
    }
    pin(px, py, 24f * u, 12f * u, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE; setShadowLayer(6f * u, 0f, u, 0x40000000) })
    pin(px + 2f * u, py + 2f * u, 20f * u, 10f * u, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = mark })
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE; textSize = 12f * u; textAlign = Paint.Align.CENTER; isFakeBoldText = true }
    g.drawText("$n", px + 12f * u, py + 12f * u - (text.descent() + text.ascent()) / 2, text)
    val bytes = ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    val thumb = Bitmap.createScaledBitmap(out, 160, (160f * out.height / out.width).roundToInt().coerceAtLeast(1), true)
    return Picked2("", bytes, out.width, out.height, thumb.asImageBitmap())
}

// ── into the chat's draft (web/src/draft.ts offerToDraft) ──────────────

/** A quote a mark puts into the draft, with the screenshot's file name it goes with (none: an image's mark, ImageMarks.kt), and whose it is. */
class OfferQuote(val author: String, val text: String, val comment: String, val file: String?, val role: String = "page")

/** What a preview's marks put into the draft of the chat whose agent is `session`: screenshots and quotes. */
class MarkOffer(val station: String, val session: String, val pictures: List<Picked>, val quotes: List<OfferQuote>)

/** Offers waiting for their chat's composer (the chat's page takes them as it shows: TakeDraftOffers). */
object DraftOffers { val waiting = mutableStateListOf<MarkOffer>() }

/** Takes what a preview offered to this chat's draft (its agents' `sessions`): the files go up, the quotes go in. */
@Composable
fun TakeDraftOffers(station: String, sessions: List<String>, draft: Draft) {
    val app = LocalApp.current
    LaunchedEffect(DraftOffers.waiting.size, sessions) {
        val mine = DraftOffers.waiting.filter { it.station == station && it.session in sessions }
        if (mine.isEmpty()) return@LaunchedEffect
        DraftOffers.waiting.removeAll(mine)
        for (offer in mine) {
            offer.pictures.forEach { app.upload(draft, station, it, app.scope) }
            offer.quotes.forEach { q ->
                draft.quotes += DraftQuote(System.nanoTime(), q.author, q.text, null, q.role, q.file).also { it.comment = q.comment }
            }
        }
    }
}
