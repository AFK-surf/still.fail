// Inline visualizations (web/src/Viz.tsx): an HTML file an agent attached and placed in its message's text
// (`[title](figure.html)` on a line of its own), drawn there in a WebView instead of shown as a card; a ```mermaid block
// is drawn the same way, by mermaid (from the CDN the web loads it from) in a page of its own.
//
// The page is the web's: its stylesheet and bridge (web/src/viz/ember-viz.css, bridge.js, the app's assets), the
// web's tokens for the theme shown (as --e-*), the same CSP (scripts and styles from a few public CDNs, no requests
// of its own). It is as tall as its content (the bridge says), keeps what the widget asks to keep (widget.setState,
// on the station, given back by widget.state as it loads), and puts what it asks to send (sendFollowUpMessage, on a
// tap) in the chat's composer for the person to send (LocalFollowUp).
package fail.still.android.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color as AndroidColor
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollDispatcher
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import fail.still.android.data.Attachment
import fail.still.android.data.StillFailJson
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import kotlin.math.abs
import fail.still.android.data.t

/**
 * Where words a visualization asks to send go: the chat's composer (answers whether it took them). None: the chat
 * shown cannot send, and the widget is told so.
 */
val LocalFollowUp = staticCompositionLocalOf<((String) -> Boolean)?> { null }

/** Past this the page scrolls within itself. */
private const val MAX_HEIGHT = 1200
/** What a widget may keep, as Codex's Visualize allows. */
private const val MAX_STATE = 16 * 1024

/** The web's tokens a page is given, as --e-<name> (web/src/styles/global.css.ts, as its root has them). */
private val LIGHT_TOKENS = mapOf(
    "canvas" to "oklch(100% 0 0)", "raised" to "#e4e4e8", "text" to "oklch(27% .009 255)", "muted" to "oklch(52% .012 255)",
    "subtle" to "oklch(57% .01 255)", "line" to "oklch(91% .005 85)", "line-strong" to "oklch(82% .008 255)",
    "hover" to "oklch(25% .02 85 / .065)", "selected" to "oklch(93% .009 85)", "paper" to "oklch(96.3% .012 88)",
    "accent" to "oklch(68% .175 39)", "accent-text" to "oklch(48% .155 38)", "accent-bg" to "oklch(96.5% .025 45)",
    "blue" to "oklch(49% .18 260)", "blue-bg" to "oklch(96% .02 260)", "code-inline" to "#7C3FA0", "green" to "oklch(46% .11 158)",
    "green-bg" to "oklch(96% .02 158)", "amber" to "oklch(48% .10 73)", "amber-bg" to "oklch(97% .028 85)", "red" to "oklch(48% .15 22)",
    "red-bg" to "oklch(97% .02 22)", "neutral-bg" to "oklch(95% .004 255)", "shadow" to "oklch(20% .01 255 / .10)", "primary" to "#24272b",
    "primary-hover" to "#41464c", "on-primary" to "#fff", "field-hover" to "#9a9ea3", "field-focus" to "#646970",
    "r-field" to "12px", "r-card" to "20px", "corner-shape" to "round",
)
private val DARK_TOKENS = LIGHT_TOKENS + mapOf(
    "canvas" to "#1f2023", "raised" to "#2a2c31", "text" to "#e9e9ea", "muted" to "#a3a5a9", "subtle" to "#8c8f94", "line" to "#2d2e32",
    "line-strong" to "#3d3f44", "hover" to "rgb(255 255 255 / .05)", "selected" to "#323338", "paper" to "#26272b",
    "accent" to "oklch(72% .16 42)", "accent-text" to "oklch(78% .13 45)", "accent-bg" to "oklch(30% .05 40)", "blue" to "oklch(75% .12 260)",
    "code-inline" to "#C9A2E6", "blue-bg" to "oklch(30% .05 260)", "green" to "oklch(76% .12 158)", "green-bg" to "oklch(30% .04 158)",
    "amber" to "oklch(80% .12 80)", "amber-bg" to "oklch(32% .05 80)", "red" to "oklch(74% .14 22)", "red-bg" to "oklch(30% .05 22)",
    "neutral-bg" to "#2a2b2f", "shadow" to "oklch(0% 0 0 / .45)", "primary" to "#eceded", "primary-hover" to "#d3d4d6", "on-primary" to "#1f2023",
    "field-hover" to "#5d6066", "field-focus" to "#8a8d93",
)

private const val CDNS = "https://cdnjs.cloudflare.com https://esm.sh https://cdn.jsdelivr.net https://unpkg.com"
private val CSP = listOf(
    "default-src 'none'",
    "script-src 'unsafe-inline' 'unsafe-eval' $CDNS",
    "style-src 'unsafe-inline' $CDNS https://fonts.googleapis.com",
    "font-src data: $CDNS https://fonts.gstatic.com",
    "img-src data: blob:",
    "media-src data: blob:",
    "connect-src 'none'",
).joinToString("; ")

private fun tokens(dark: Boolean): Map<String, String> = (if (dark) DARK_TOKENS else LIGHT_TOKENS).mapKeys { "--e-${it.key}" }

private fun tokensJson(dark: Boolean): String = StillFailJson.encodeToString(JsonObject.serializer(), buildJsonObject { tokens(dark).forEach { (k, v) -> put(k, v) } })

/** The web's stylesheet and bridge, from the app's assets (web/src/viz, packed in by the build). */
private var assets: Pair<String, String>? = null
private fun vizAssets(context: Context): Pair<String, String> = assets ?: run {
    fun read(name: String) = context.assets.open(name).bufferedReader().use { it.readText() }
    (read("ember-viz.css") to read("bridge.js")).also { assets = it }
}

/**
 * What the bridge says to its page (it posts to its parent, which in a WebView of its own is itself), handed to the
 * app: its height, what it keeps, a failure, words to send.
 */
private const val RELAY = """addEventListener("message",function(e){if(e.source===window&&e.data&&e.data.emberViz&&e.data.type!=="theme"){try{StillFailViz.post(JSON.stringify(e.data))}catch(_){}}});"""

/** The page: the content in the stylesheet, the bridge (and what the widget kept) ahead of it, the theme as the app shows it now. */
private fun documentOf(context: Context, html: String, state: JsonElement?, dark: Boolean): String {
    val (stylesheet, bridge) = vizAssets(context)
    val vars = tokens(dark).entries.joinToString(";") { (k, v) -> "$k:${v.replace(Regex("[<>]"), "")}" }
    val theme = if (dark) "dark" else "light"
    val kept = StillFailJson.encodeToString(JsonObject.serializer(), buildJsonObject { put("widgetState", state ?: JsonNull) }).replace("<", "\\u003c")
    return "<!doctype html><html data-theme=\"$theme\"><head><meta charset=\"utf-8\">" +
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" +
        "<meta http-equiv=\"Content-Security-Policy\" content=\"$CSP\">" +
        "<style>:root{color-scheme:$theme;$vars}</style><style>$stylesheet</style>" +
        "<script type=\"application/json\" id=\"ember-viz-state\">$kept</script>" +
        "<script>$RELAY</script><script>$bridge</script></head><body>$html</body></html>"
}

/**
 * A whole page's document (a file that is not a fragment: a player, an app, a page made to fill a window), drawn as
 * written, not in the stylesheet: only the sandbox's CSP and the bridge (with the relay to the app) go into its head,
 * after its doctype, html or head tag so it keeps its mode (web Viz.tsx → pageDocument).
 */
private fun pageDocument(context: Context, html: String): String {
    val (_, bridge) = vizAssets(context)
    val head = "<meta http-equiv=\"Content-Security-Policy\" content=\"$CSP\"><script>$RELAY</script><script>$bridge</script>"
    val at = Regex("<head[^>]*>", RegexOption.IGNORE_CASE).find(html) ?: Regex("<html[^>]*>", RegexOption.IGNORE_CASE).find(html)
        ?: Regex("<!doctype[^>]*>", RegexOption.IGNORE_CASE).find(html)
    return if (at != null) html.substring(0, at.range.last + 1) + head + html.substring(at.range.last + 1) else head + html
}

/** Whether an HTML file is a fragment (as the viz skill has agents write them), to be drawn in the stylesheet. */
fun isFragment(html: String): Boolean = !Regex("<!doctype|<html[\\s>]", RegexOption.IGNORE_CASE).containsMatchIn(html.take(2048))

/** Heights pages were last drawn at, so one drawn again (scrolled back to) takes its room at once. */
private val heights = HashMap<Int, Int>()

private class Bridge(val onMessage: (JsonObject) -> Unit) {
    @JavascriptInterface
    fun post(json: String) {
        val message = try { StillFailJson.parseToJsonElement(json).jsonObject } catch (_: Exception) { return }
        onMessage(message)
    }
}

/**
 * The page itself, in a WebView. `fill`: it takes the room it is given (a page of its own) rather than its
 * content's height. `onState` keeps what the widget keeps next; `onError` hears a failure it reports.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun VizFrame(html: String, state: JsonElement? = null, fill: Boolean = false, modifier: Modifier = Modifier, onState: ((JsonElement) -> Unit)? = null, onError: ((String) -> Unit)? = null) {
    val context = LocalContext.current
    val host = LocalUi.current
    val dark = C.dark
    val followUp = LocalFollowUp.current
    val latest by rememberUpdatedState(Triple(onState, onError, followUp))
    val id = html.hashCode()
    var height by remember(html) { mutableIntStateOf(heights[id] ?: 0) }
    // Made once per content: a new page would lose what it holds (its state, a chart drawn). The theme is told to it as it changes.
    // A whole page sizes itself to its window (height:100%, a stage scaled to fit), so it has no height of its own to be
    // sized to: in a message it gets a screen-shaped window instead (web: a 16:9 window of the message's width, at most
    // 80% of the screen's height, its corners the card's, on the paper).
    val page = remember(html) { !isFragment(html) }
    val doc = remember(html) { if (page) pageDocument(context, html) else documentOf(context, html, state, dark) }
    val dispatcher = remember { NestedScrollDispatcher() }
    var web by remember { mutableStateOf<WebView?>(null) }
    // The theme the page was made in (a fragment's document carries it): told only when it changes, as a page told it
    // as it loads draws again (a chart redrawn, a mermaid chart made twice).
    var told by remember(html) { mutableStateOf(dark) }
    LaunchedEffect(dark, web) {
        val view = web ?: return@LaunchedEffect
        if (dark == told) return@LaunchedEffect
        told = dark
        view.evaluateJavascript("postMessage({emberViz:true,type:\"theme\",tokens:${tokensJson(dark)},scheme:\"${if (dark) "dark" else "light"}\"},\"*\")", null)
    }
    DisposableEffect(Unit) { onDispose { web?.destroy() } }
    val most = (androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp * 0.8f).dp
    val frame = when {
        fill -> modifier
        page -> modifier.fillMaxWidth().layout { m, c ->
            val w = c.maxWidth
            val h = minOf((w * 9f / 16f).toInt(), most.roundToPx())
            val p = m.measure(androidx.compose.ui.unit.Constraints.fixed(w, h))
            layout(w, h) { p.place(0, 0) }
        }.clip(RoundedCornerShape(20.dp)).background(if (dark) androidx.compose.ui.graphics.Color(0xFF26272B) else androidx.compose.ui.graphics.Color(0xFFF6F2EA))
        else -> modifier.fillMaxWidth().height((height.takeIf { it > 0 } ?: 120).dp)
    }
    AndroidView(
        factory = { ctx ->
            // Shown once the page has drawn itself (a fragment at the height it says), not while the WebView is still
            // blank or drawn at the height it had before: what is under it shows meanwhile, then the page at once.
            VizView(ctx).apply {
                alpha = 0f
                // A whole page fills its window: a WebView whose height is WRAP_CONTENT (AndroidView's default) lays its
                // page out in a window 0 high (height:100% is nothing), sizing itself to the content instead.
                if (page) layoutParams = android.view.ViewGroup.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
                setBackgroundColor(AndroidColor.TRANSPARENT)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = false
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                // All of the page kept drawn, not only what was last in view: the chat's list is the source of its frosted
                // bars (Haze), which draw it a second time, clipped to the bar; drawn so, the page dropped the rest and
                // showed blank for a frame each time the bars were drawn again (a caret blinking, an agent at work).
                settings.offscreenPreRaster = true
                isVerticalScrollBarEnabled = fill
                isHorizontalScrollBarEnabled = false
                overScrollMode = WebView.OVER_SCROLL_NEVER
                // Links in a page leave it for the browser (or still.fail's own, the app); the page itself stays.
                webViewClient = object : WebViewClient() {
                    // A whole page (or a fragment that never says its height) is shown once it has loaded and drawn.
                    override fun onPageFinished(view: WebView, url: String?) { (view as VizView).reveal() }

                    override fun shouldOverrideUrlLoading(view: WebView, request: android.webkit.WebResourceRequest): Boolean {
                        val url = request.url.toString()
                        if (request.isForMainFrame && (url.startsWith("http://") || url.startsWith("https://"))) {
                            view.post { host.follow(url) { try { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, request.url)) } catch (_: Exception) { host.note(t("android-misc.link.cantOpen")) } } }
                        }
                        return true
                    }
                }
                addJavascriptInterface(Bridge { m ->
                    post {
                        val (keep, failed, send) = latest
                        // The page says what it likes: a field that is not what it should be is let go.
                        try {
                            when ((m["type"] as? JsonPrimitive)?.content) {
                                "height" -> if (!page) (m["height"] as? JsonPrimitive)?.content?.toDoubleOrNull()?.takeIf { it.isFinite() }?.let { h ->
                                    val shown = minOf(MAX_HEIGHT, kotlin.math.ceil(h).toInt())
                                    heights[id] = shown; height = shown
                                    reveal()
                                }
                                "state" -> { val s = m["state"] ?: JsonNull; if (s.toString().length <= MAX_STATE) keep?.invoke(s) }
                                "failed" -> (m["message"] as? JsonPrimitive)?.content?.let { failed?.invoke(it) }
                                "followup" -> (m["prompt"] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() }?.let { words ->
                                    host.note(if (send?.invoke(words.take(4000)) == true) t("android-misc.viz.followupDrafted") else t("android-misc.viz.cantSend"))
                                }
                            }
                        } catch (_: Exception) {
                        }
                    }
                }, "StillFailViz")
                loadDataWithBaseURL(null, doc, "text/html", "utf-8", null)
                web = this
            }
        },
        modifier = if (fill) frame else frame.nestedScroll(object : NestedScrollConnection {}, dispatcher).passVerticalDrags(dispatcher),
    )
}

/** A page's WebView, hidden until it has drawn. */
private class VizView(context: Context) : WebView(context) {
    private var shown = false

    /** Shows the page once what it has now is drawn (its height applied first: the next layout, then the WebView's own visual state), once. */
    fun reveal() {
        if (shown) return
        shown = true
        post { postVisualStateCallback(0, object : VisualStateCallback() { override fun onComplete(requestId: Long) { alpha = 1f } }) }
    }
}

/**
 * In a list, an upright drag on the page moves the list, as it would over anything else in the message: the page
 * keeps taps and sideways drags (its own controls, a chart's slider). Taken in the first pass, before the page sees
 * the move; the page is told the touch is over, and the drag goes on to the list as nested scrolling, fling included.
 */
private fun Modifier.passVerticalDrags(dispatcher: NestedScrollDispatcher): Modifier = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        val tracker = VelocityTracker()
        tracker.addPosition(down.uptimeMillis, down.position)
        var total = Offset.Zero
        var dragging = false
        var sideways = false
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            if (!change.pressed) break
            tracker.addPosition(change.uptimeMillis, change.position)
            val delta = change.position - change.previousPosition
            if (!dragging && !sideways) {
                total += delta
                if (abs(total.y) > viewConfiguration.touchSlop && abs(total.y) > abs(total.x)) dragging = true
                else if (abs(total.x) > viewConfiguration.touchSlop) sideways = true
            }
            if (dragging) {
                change.consume()
                val move = Offset(0f, delta.y)
                val pre = dispatcher.dispatchPreScroll(move, NestedScrollSource.UserInput)
                dispatcher.dispatchPostScroll(Offset.Zero, move - pre, NestedScrollSource.UserInput)
            }
        }
        if (dragging) {
            val velocity = Velocity(0f, tracker.calculateVelocity().y)
            dispatcher.coroutineScope.launch {
                val pre = dispatcher.dispatchPreFling(velocity)
                dispatcher.dispatchPostFling(Velocity.Zero, velocity - pre)
            }
        }
    }
}

/** A visualization over the whole screen: the page as tall as the screen, its name and a close over it. */
@Composable
internal fun VizFull(name: String, html: String, state: JsonElement?, keep: (JsonElement) -> Unit, onClose: () -> Unit) {
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(C.bg).windowInsetsPadding(WindowInsets.systemBars)) {
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().height(48.dp).padding(start = 18.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Box(Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onClose), contentAlignment = Alignment.Center) { IconIn(Icons.Close, 18.dp, C.ink) }
                }
                VizFrame(html, state, fill = true, modifier = Modifier.fillMaxWidth().weight(1f).padding(horizontal = 12.dp), onState = keep)
            }
        }
    }
}

private const val MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs"

/** A mermaid chart's page: the source, drawn by mermaid in the web's colours, drawn again when the theme changes (web/src/Viz.tsx). */
private fun mermaidDocument(code: String): String = """<pre class="mermaid-src" hidden>${code.replace("&", "&amp;").replace("<", "&lt;")}</pre><div id="chart" style="display:flex;justify-content:center"></div>
<script type="module">
  const post = (m) => parent.postMessage({ emberViz: true, ...m }, "*");
  const source = document.querySelector(".mermaid-src").textContent;
  let mermaid;
  try { mermaid = (await import("$MERMAID")).default; } catch (e) { post({ type: "failed", message: "${t("android-misc.viz.mermaidFailed")}" }); }
  const pixel = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
  const rgb = (color) => { pixel.clearRect(0, 0, 1, 1); pixel.fillStyle = "#000"; pixel.fillStyle = color; pixel.fillRect(0, 0, 1, 1); const [r, g, b] = pixel.getImageData(0, 0, 1, 1).data; return "rgb(" + r + ", " + g + ", " + b + ")"; };
  const v = (name) => { const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim(); return name === "--font-sans" ? value : rgb(value); };
  let n = 0;
  async function draw() {
    if (!mermaid) return;
    try {
      mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "base", fontFamily: v("--font-sans"), themeVariables: {
        darkMode: document.documentElement.dataset.theme === "dark", fontSize: "14px",
        background: v("--background"), primaryColor: v("--card"), primaryTextColor: v("--foreground"), primaryBorderColor: v("--border-strong"),
        secondaryColor: v("--accent"), tertiaryColor: v("--muted"), lineColor: v("--muted-foreground"), textColor: v("--foreground"),
        noteBkgColor: v("--accent"), noteTextColor: v("--foreground"), noteBorderColor: v("--brand"),
        actorBkg: v("--card"), actorBorder: v("--border-strong"), actorTextColor: v("--foreground"), signalColor: v("--foreground"), signalTextColor: v("--foreground"),
      } });
      const { svg } = await mermaid.render("chart-" + ++n, source);
      document.getElementById("chart").innerHTML = svg;
    } catch (e) { post({ type: "failed", message: String(e?.message ?? e) }); }
  }
  addEventListener("ember-viz:theme", draw);
  draw();
</script>"""

/** Charts that would not draw (mermaid not reachable, or the source does not parse): shown as code from then on. */
private val unmade = HashSet<String>()

/** A ```mermaid block: drawn as a chart; shown as code while it will not draw. */
@Composable
fun Mermaid(code: String) {
    var failed by remember(code) { mutableStateOf(code in unmade) }
    if (failed) return CodeBlock(code, "mermaid")
    val html = remember(code) { mermaidDocument(code) }
    Box(Modifier.fillMaxWidth()) { VizFrame(html, onError = { unmade += code; failed = true }) }
}

/**
 * A visualization's document as a page of the preview serves it (web Preview.tsx FileFrame → vizDocument): the file in
 * the stylesheet with what its widget kept (a whole page as written), and `script` (the preview's own page script)
 * inline ahead of the rest, as the page's CSP lets no script of the page's host in.
 */
internal fun vizServed(context: Context, html: String, state: JsonElement?, dark: Boolean, script: String): String {
    val doc = if (isFragment(html)) documentOf(context, html, state, dark) else pageDocument(context, html)
    val tag = "<script>" + script.replace("</script", "<\\/script") + "</script>"
    val at = Regex("<head[^>]*>", RegexOption.IGNORE_CASE).find(doc) ?: Regex("<html[^>]*>", RegexOption.IGNORE_CASE).find(doc)
    return if (at != null) doc.substring(0, at.range.last + 1) + tag + doc.substring(at.range.last + 1) else tag + doc
}

/** What a visualization's page says to the app (its bridge's relay, StillFailViz): here only what its widget keeps. */
internal class VizKeeper(private val keep: (JsonElement) -> Unit) {
    @JavascriptInterface
    fun post(json: String) {
        val m = try { StillFailJson.parseToJsonElement(json).jsonObject } catch (_: Exception) { return }
        if ((m["type"] as? JsonPrimitive)?.content != "state") return
        val state = m["state"] ?: JsonNull
        if (state.toString().length <= MAX_STATE) keep(state)
    }
}
