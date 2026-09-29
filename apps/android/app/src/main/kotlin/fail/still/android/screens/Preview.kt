// A web service an agent started (a dev server, a report it serves), full screen over its chat: found by its job, known
// by its name (never its port). A WebView on a host of its own, every request of which goes to the station through the
// core (station.preview), as the web's preview does (web/src/Preview.tsx, mobile/Preview.tsx); a bar over it goes back,
// forward, reloads and says where it is (typed to go elsewhere). No port on the station is open to anyone.
package fail.still.android.screens

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.util.Base64
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import fail.still.android.LocalApp
import fail.still.android.data.Job
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.NavBar
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import java.io.ByteArrayInputStream
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add

/** The host the WebView loads the service at: nothing answers it but the core. */
private const val HOST = "preview.stillfail.invalid"

/** `service`: its job's id. */
@Composable
fun PreviewScreen(station: String, service: String) {
    val app = LocalApp.current
    var job by remember { mutableStateOf<Job?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    // Found by its job, and read again now and then: a restart is said over the page, which loads anew once it is up.
    LaunchedEffect(station, service) {
        while (true) {
            try { job = app.api(station).job(service); error = null } catch (e: CoreException) { if (job == null) error = e.message }
            delay(4000)
        }
    }
    val shown = job
    val port = shown?.port
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
        NavBar("对话", app::pop, shown?.name ?: "服务", sub = { Text(rememberStationName(station), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        when {
            error != null -> PreviewNote("找不到这个服务：$error")
            shown == null -> Unit
            port == null || (shown.state != "running" && shown.state != "exited") -> PreviewNote("「${shown.name}」已经停了。")
            else -> ServicePage(app.core, station, port.toInt(), shown.name, restarting = shown.state == "exited", restarts = shown.restarts ?: 0)
        }
    }
}

@Composable
private fun PreviewNote(text: String) =
    Text(text, fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp))

/** The service's page under its bar; `restarting`: it ended and the station starts it again (`restarts` so far). */
@Composable
private fun ColumnScope.ServicePage(core: StillFailCore, station: String, port: Int, name: String, restarting: Boolean, restarts: Long) {
    var web by remember { mutableStateOf<WebView?>(null) }
    // Where the page is now (its path, or a whole address off the service), and whether it can step either way.
    var at by remember { mutableStateOf<String?>(null) }
    var canBack by remember { mutableStateOf(false) }
    var canForward by remember { mutableStateOf(false) }
    // The system's back steps the page back first; at its first page it leaves.
    BackHandler(enabled = canBack) { web?.goBack() }
    // Up again after a restart: the page loads anew.
    var was by remember { mutableStateOf(restarting) }
    LaunchedEffect(restarting) {
        if (was && !restarting) web?.reload()
        was = restarting
    }
    PreviewBar(
        name, at, go = { path -> web?.loadUrl("https://$HOST$path") }, reload = { web?.reload() },
        back = { web?.goBack() }, forward = { web?.goForward() }, canBack = canBack, canForward = canForward,
    )
    Box(Modifier.fillMaxWidth().weight(1f)) {
        AndroidView(
            factory = { context ->
                @SuppressLint("SetJavaScriptEnabled")
                val view = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = PreviewClient(core, station, port) { v ->
                        at = v.url?.let { url ->
                            val uri = android.net.Uri.parse(url)
                            if (uri.host == HOST) (uri.encodedPath ?: "/") + (uri.encodedQuery?.let { "?$it" } ?: "") else url
                        }
                        canBack = v.canGoBack()
                        canForward = v.canGoForward()
                    }
                    loadUrl("https://$HOST/")
                }
                web = view
                view
            },
            onRelease = { it.destroy() },
            modifier = Modifier.fillMaxSize(),
        )
        if (restarting) Row(
            Modifier.align(Alignment.TopCenter).padding(12.dp).shadow(8.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp))
                .background(C.surface).padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            JobDot(Tone.Restart)
            Column {
                Text("${name}正在重启", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text((if (restarts > 0) "第 $restarts 次 · " else "") + "起来后自动刷新", fontSize = 12.sp, color = C.muted)
            }
        }
    }
}

/** Back, forward, reload, and where it is as one capsule (its name, then its path, typed to go elsewhere). */
@Composable
private fun PreviewBar(name: String, at: String?, go: (String) -> Unit, reload: () -> Unit, back: () -> Unit, forward: () -> Unit, canBack: Boolean, canForward: Boolean) {
    val focus = LocalFocusManager.current
    var typed by remember { mutableStateOf(at ?: "/") }
    var editing by remember { mutableStateOf(false) }
    // Where it went is what the bar says, unless someone is typing there.
    LaunchedEffect(at, editing) { if (at != null && !editing) typed = at }
    Row(Modifier.fillMaxWidth().padding(start = 6.dp, end = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        BarIcon(Icons.ArrowLeft, canBack, back)
        BarIcon(Icons.ArrowRight, canForward, forward)
        BarIcon(Icons.Refresh, true, reload)
        Row(
            Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(17.dp)).background(C.ink.copy(alpha = 0.05f)).padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            IconIn(Icons.Web, 14.dp, C.muted)
            Text(name, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            BasicTextField(
                typed, { typed = it }, singleLine = true,
                textStyle = TextStyle(fontSize = 13.sp, color = C.ink),
                cursorBrush = SolidColor(C.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = {
                    go(if (typed.startsWith("/")) typed else "/$typed")
                    focus.clearFocus()
                }),
                modifier = Modifier.weight(1f).onFocusChanged { editing = it.isFocused },
            )
        }
    }
}

@Composable
private fun BarIcon(icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(36.dp).clip(CircleShape).clickable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        IconIn(icon, 18.dp, if (enabled) C.ink else C.subtle.copy(alpha = 0.6f))
    }
}

/** Answers the WebView's requests for the preview's host from the station; anything else goes to the network. */
private class PreviewClient(private val core: StillFailCore, private val station: String, private val port: Int, private val moved: (WebView) -> Unit) : WebViewClient() {
    // Where it is, as the page moves (a link, its own history, a reload): for the bar.
    override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) = moved(view)
    override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) = moved(view)

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
        val url = request.url
        if (url.host != HOST) return null
        // Off the main thread already: the station is waited for here. A redirect is followed here (the WebView takes
        // no 3xx from this), up to a few.
        var path = (url.encodedPath ?: "/") + (url.encodedQuery?.let { "?$it" } ?: "")
        repeat(5) {
            val answer = try {
                runBlocking {
                    core.call("station.preview", buildJsonObject {
                        put("station", station); put("port", port); put("method", request.method); put("path", path); put("body", "")
                        putJsonArray("headers") { request.requestHeaders.forEach { (k, v) -> add(JsonArray(listOf(kotlinx.serialization.json.JsonPrimitive(k), kotlinx.serialization.json.JsonPrimitive(v)))) } }
                    }).jsonObject
                }
            } catch (e: CoreException) {
                return text(502, "没能从 station 取到：${e.message}")
            }
            val status = answer["status"]!!.jsonPrimitive.int
            val headers = answer["headers"]!!.jsonArray.associate { h -> h.jsonArray[0].jsonPrimitive.content to h.jsonArray[1].jsonPrimitive.content }
            val location = headers.entries.firstOrNull { it.key.equals("location", ignoreCase = true) }?.value
            if (status in 300..399 && location != null) {
                val next = android.net.Uri.parse(location)
                if (next.host != null && next.host != "localhost" && next.host != "127.0.0.1") return text(502, "这个网页跳到了别的地址：$location")
                path = (next.encodedPath ?: "/") + (next.encodedQuery?.let { "?$it" } ?: "")
                return@repeat
            }
            val body = Base64.decode(answer["body"]!!.jsonPrimitive.content, Base64.DEFAULT)
            val type = headers.entries.firstOrNull { it.key.equals("content-type", ignoreCase = true) }?.value ?: "application/octet-stream"
            val mime = type.substringBefore(';').trim()
            val charset = Regex("charset=([^;]+)").find(type)?.groupValues?.get(1)?.trim()
            return WebResourceResponse(mime, charset, status.coerceIn(200, 599).let { if (it in 300..399) 200 else it }, reason(status), headers, ByteArrayInputStream(body))
        }
        return text(508, "跳转太多次了")
    }

    private fun text(status: Int, message: String) =
        WebResourceResponse("text/plain", "utf-8", status, reason(status), emptyMap(), ByteArrayInputStream(message.toByteArray()))

    /** The WebView wants a reason phrase with every status. */
    private fun reason(status: Int) = when (status) { in 200..299 -> "OK"; 404 -> "Not Found"; in 500..599 -> "Error"; else -> "Status" }
}
