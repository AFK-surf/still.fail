// A web service on a station's machine (a dev server an agent started, a report it serves), full screen: a WebView on
// a host of its own, every request of which goes to the station through the core (station.preview), as the web's
// preview does (web/src/Preview.tsx). No port on the station is open to anyone.
package dev.ember.android.screens

import android.annotation.SuppressLint
import android.util.Base64
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import dev.ember.android.LocalApp
import dev.ember.android.ui.C
import dev.ember.android.ui.NavBar
import dev.ember.core.CoreException
import dev.ember.core.EmberCore
import java.io.ByteArrayInputStream
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
private const val HOST = "preview.ember.invalid"

@Composable
fun PreviewScreen(station: String, port: Int) {
    val app = LocalApp.current
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.navigationBars)) {
        NavBar("对话", app::pop, "localhost:$port", sub = { Text(rememberStationName(station), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        AndroidView(
            factory = { context ->
                @SuppressLint("SetJavaScriptEnabled")
                val view = WebView(context).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = PreviewClient(app.core, station, port)
                    loadUrl("https://$HOST/")
                }
                view
            },
            modifier = Modifier.fillMaxWidth().weight(1f),
        )
    }
}

/** Answers the WebView's requests for the preview's host from the station; anything else goes to the network. */
private class PreviewClient(private val core: EmberCore, private val station: String, private val port: Int) : WebViewClient() {
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
