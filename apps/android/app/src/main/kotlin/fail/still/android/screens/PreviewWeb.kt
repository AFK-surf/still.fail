// The WebView end of a web service's preview (Preview.kt): what the web's preview frame, its service worker and
// previewBridge.ts do there (cloud/src/preview.ts, web/src/previewBridge.ts), for a WebView that is the page itself.
// Every request the page makes of its own host is answered here from the station through the core (station.preview,
// as it comes: an event stream, a long poll, a big file go on as the station sends them), and stopped at the station
// when the page gives it up. The page's own script (assets/preview/page.js, first in each of its pages) carries its
// WebSockets (preview.socket), its requests' bodies (which a WebView never hands over) and marking the page through
// StillFailPreviewNative. No port on the station is open to anyone.
package fail.still.android.screens

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebMessage
import android.webkit.WebMessagePort
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/** The host the WebView loads the service at: nothing answers it but the core. */
internal const val PREVIEW_HOST = "preview.stillfail.invalid"
/** The page's own script, served here (never asked of the service). */
private const val PAGE_JS = "/_stillfail/page.js"
private const val BODY_HEADER = "x-stillfail-body"
/** How long a request waits for its answer's head (a WebView's request thread waits there). */
private const val HEAD_WAIT_S = 60L
/**
 * How much of an answer waits here for the WebView to read it. The station sends as it has it (the core's calls have
 * no way to hold it back, and its thread must not wait): an answer that gets this far ahead of its reader is stopped.
 */
private const val BUFFERED_MAX = 32L shl 20

/** Where one cookie ends in a Set-Cookie header holding several (an Expires date's comma is not followed by name=). */
private val COOKIES_JOINED = Regex(",\\s*(?=[!#$%&'*+.^_`|~0-9A-Za-z-]+=)")

/** A path on the service, as the WebView has it: its path and query. */
internal fun pathOf(url: android.net.Uri): String = (url.encodedPath ?: "/") + (url.encodedQuery?.let { "?$it" } ?: "")

/**
 * One preview's page: its WebView's requests, sockets and marks, for the service at `port` of `station`. Whatever is
 * under way is stopped with [close] (the page gone).
 */
internal class PreviewLink(private val core: StillFailCore, private val station: String, private val port: Int, private val script: ByteArray) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val main = Handler(Looper.getMainLooper())
    var web: WebView? = null
    /** What the page's marking says (its JSON), on the main thread. */
    var onMarked: (JsonObject) -> Unit = {}
    /**
     * Answers the page's requests here instead of the station (a visualization's page, which is a file, not a service:
     * web Preview.tsx FileFrame's `serve`): its method and path in, the answer out.
     */
    var serve: ((method: String, path: String) -> WebResourceResponse)? = null

    /** Requests' bodies the page left here, by the id its request carries. */
    private class Body(val bytes: ByteArray, val type: String?)
    private val bodies = ConcurrentHashMap<String, Body>()
    /** The page's WebSockets still open, by the name the page gave each. */
    private val sockets = ConcurrentHashMap<String, Job>()
    /** What the page sends on its sockets, in the order it sent it. */
    private val outgoing = Channel<JsonObject>(Channel.UNLIMITED)

    init {
        scope.launch {
            for (message in outgoing) {
                try {
                    core.call("preview.socket.send", message)
                } catch (_: CoreException) {
                    // Its station is gone: its close follows from the socket's own call. A close that did not get
                    // there stops the socket's call instead, so nothing is left open for a page that let it go.
                    if (message.containsKey("close")) sockets[message["socket"]!!.jsonPrimitive.content]?.cancel()
                }
            }
        }
    }

    fun close() {
        outgoing.close()
        scope.cancel()
    }

    /** A new page: the sockets of the one before go with it. */
    fun pageStarted() {
        sockets.values.forEach { it.cancel() }
        sockets.clear()
        bodies.clear()
        dropFetches()
    }

    private fun js(code: String) = main.post { web?.evaluateJavascript(code, null) }
    private fun q(text: String) = JsonPrimitive(text).toString()

    // ── the page's script calls these (StillFailPreviewNative) ──

    @JavascriptInterface
    fun open(sid: String, path: String, protocols: String) {
        val event = { kind: String, args: String -> js("window.__stillfailSocketEvent&&__stillfailSocketEvent(${q(sid)},${q(kind)}$args)") }
        val job = scope.launch {
            val closed = try {
                core.call("preview.socket", buildJsonObject {
                    put("station", station); put("port", port); put("path", path); put("socket", sid)
                    putJsonArray("headers") { if (protocols.isNotEmpty()) add(JsonArray(listOf(JsonPrimitive("sec-websocket-protocol"), JsonPrimitive(protocols)))) }
                }) { v ->
                    val o = v as? JsonObject ?: return@call
                    when {
                        o["open"] is JsonObject -> event("open", ",${q(o["open"]!!.jsonObject["protocol"]?.jsonPrimitive?.content ?: "")}")
                        o["text"] is JsonPrimitive -> event("text", ",${o["text"]}")
                        o["binary"] is JsonPrimitive -> event("binary", ",${o["binary"]}")
                    }
                }.jsonObject
            } catch (e: CancellationException) {
                throw e
            } catch (_: CoreException) {
                null
            }
            val code = closed?.get("code")?.jsonPrimitive?.intOrNull ?: 1006
            val reason = closed?.get("reason")?.jsonPrimitive?.content ?: ""
            event("close", ",$code,${q(reason)},${code == 1006}")
        }
        sockets[sid] = job
        job.invokeOnCompletion { sockets.remove(sid, job) }
    }

    @JavascriptInterface
    fun send(sid: String, text: String) { if (sockets.containsKey(sid)) outgoing.trySend(buildJsonObject { put("socket", sid); put("text", text) }) }

    @JavascriptInterface
    fun sendBinary(sid: String, base64: String) { if (sockets.containsKey(sid)) outgoing.trySend(buildJsonObject { put("socket", sid); put("binary", base64) }) }

    @JavascriptInterface
    fun close(sid: String, code: Int, reason: String) {
        if (!sockets.containsKey(sid)) return
        outgoing.trySend(buildJsonObject { put("socket", sid); putJsonArray("close") { add(JsonPrimitive(code)); add(JsonPrimitive(reason)) } })
    }

    @JavascriptInterface
    fun stash(id: String, base64: String, type: String) {
        bodies[id] = Body(Base64.decode(base64, Base64.DEFAULT), type.ifEmpty { null })
    }

    @JavascriptInterface
    fun marked(json: String) {
        val said = try { kotlinx.serialization.json.Json.parseToJsonElement(json).jsonObject } catch (_: Exception) { return }
        main.post { onMarked(said) }
    }

    // ── the page's fetch() (page.js), answered as it comes ──
    // A WebView hands the page what shouldInterceptRequest answers only once its buffer (2 KB) is full, so a body that
    // comes a line at a time would reach the page in lumps. The page's fetch() of its own host comes here instead, over
    // a message port only the page's top frame holds: its head, then each piece of its body as the station sends it.
    // It can only ask the service at `port` of `station`, like every other request of the page's.

    /** The page's port (main thread): one per page, given to it when its script asks (fetchPort). */
    private var fetchPort: WebMessagePort? = null
    /** The page's fetches under way, by the id the page gave each. */
    private val fetches = ConcurrentHashMap<String, Job>()

    /** The page's script asks for its port, which comes as a message (`token`, the port) to its window. False: none (a file's page). */
    @JavascriptInterface
    fun fetchPort(token: String): Boolean {
        if (serve != null || token.isEmpty() || token.length > 64) return false
        main.post {
            val view = web ?: return@post
            if (fetchPort != null) return@post
            val (mine, theirs) = view.createWebMessageChannel()
            fetchPort = mine
            mine.setWebMessageCallback(object : WebMessagePort.WebMessageCallback() {
                override fun onMessage(port: WebMessagePort, message: WebMessage?) {
                    if (port === fetchPort) fetchSaid(port, message?.data ?: return)
                }
            }, main)
            // Only to the preview's own page: a page from anywhere else in this WebView gets nothing.
            view.postWebMessage(WebMessage(token, arrayOf(theirs)), android.net.Uri.parse("https://$PREVIEW_HOST"))
        }
        return true
    }

    /** A new page: the port and fetches of the one before go with it (main thread). */
    private fun dropFetches() {
        fetchPort?.close()
        fetchPort = null
        fetches.values.forEach { it.cancel() }
        fetches.clear()
    }

    /** What the page says on its port: `go` (a request), `stop` (one it gave up). Anything else is let go. */
    private fun fetchSaid(port: WebMessagePort, data: String) {
        val o = try { kotlinx.serialization.json.Json.parseToJsonElement(data) as? JsonObject } catch (_: Exception) { null } ?: return
        val id = (o["id"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotEmpty() && it.length <= 64 } ?: return
        when ((o["t"] as? JsonPrimitive)?.content) {
            "stop" -> fetches.remove(id)?.cancel()
            "go" -> {
                val tell = { reply: JsonObject -> main.post { if (port === fetchPort) port.postMessage(WebMessage(reply.toString())) }; Unit }
                val failed = { message: String -> tell(buildJsonObject { put("t", "error"); put("id", id); put("message", message) }) }
                val method = (o["method"] as? JsonPrimitive)?.content?.uppercase()?.takeIf { Regex("[A-Z]{1,16}").matches(it) }
                val path = (o["path"] as? JsonPrimitive)?.content?.takeIf { it.startsWith("/") && it.length <= 16384 && it.none { c -> c.code <= 0x20 || c.code == 0x7f } }
                val headers = try {
                    (o["headers"] as? JsonArray ?: JsonArray(emptyList())).take(200).map {
                        val pair = it.jsonArray
                        pair[0].jsonPrimitive.content to pair[1].jsonPrimitive.content
                    }.filter { (k, v) -> Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]{1,256}").matches(k) && v.none { c -> c == '\r' || c == '\n' } && !k.equals("host", ignoreCase = true) && !k.equals(BODY_HEADER, ignoreCase = true) }
                } catch (_: Exception) { null }
                val body = try { (o["body"] as? JsonPrimitive)?.content?.takeIf { it.isNotEmpty() }?.let { Base64.decode(it, Base64.DEFAULT) } } catch (_: IllegalArgumentException) { return failed("请求内容不对") }
                if (method == null || path == null || headers == null || fetches.containsKey(id)) return failed("请求不对")
                val follow = (o["redirect"] as? JsonPrimitive)?.content != "manual" && (o["redirect"] as? JsonPrimitive)?.content != "error"
                val withCookies = (o["cookies"] as? JsonPrimitive)?.content != "false"
                val job = scope.launch(Dispatchers.IO) {
                    val answer = try {
                        follow(method, path, headers, body, follow, this, withCookies)
                    } catch (e: Unanswered) {
                        // As the WebView's own requests have it (answer): said as the answer, in words.
                        tell(buildJsonObject {
                            put("t", "head"); put("id", id); put("status", e.status); put("statusText", reason(e.status)); put("path", path); put("redirected", false)
                            putJsonArray("headers") { add(JsonArray(listOf(JsonPrimitive("content-type"), JsonPrimitive("text/plain; charset=utf-8")))) }
                        })
                        tell(buildJsonObject { put("t", "chunk"); put("id", id); put("b", Base64.encodeToString((e.message ?: "").toByteArray(), Base64.NO_WRAP)) })
                        return@launch tell(buildJsonObject { put("t", "end"); put("id", id) })
                    }
                    val head = answer.head
                    tell(buildJsonObject {
                        put("t", "head"); put("id", id); put("status", head.status); put("statusText", reason(head.status))
                        put("path", answer.path); put("redirected", answer.redirected)
                        putJsonArray("headers") { head.headers.forEach { (k, v) -> add(JsonArray(listOf(JsonPrimitive(k), JsonPrimitive(v)))) } }
                    })
                    // Each piece as it comes (a read gives what is there, never waiting for more).
                    val buf = ByteArray(256 shl 10)
                    try {
                        head.body.use { input ->
                            while (true) {
                                val n = input.read(buf, 0, buf.size)
                                if (n < 0) break
                                if (n > 0) tell(buildJsonObject { put("t", "chunk"); put("id", id); put("b", Base64.encodeToString(buf, 0, n, Base64.NO_WRAP)) })
                            }
                        }
                        tell(buildJsonObject { put("t", "end"); put("id", id) })
                    } catch (e: IOException) {
                        failed(e.message ?: "读到一半断了")
                    }
                }
                fetches[id] = job
                job.invokeOnCompletion { fetches.remove(id, job) }
            }
        }
    }

    // ── the WebView's requests ──

    /** An answer's head, its body to come (read from `body`, closed to stop it). */
    private class Head(val status: Int, val headers: List<Pair<String, String>>, val body: Chunks)

    /** Asks the station, and waits here (a WebView's own request thread) until the answer's head is there (a minute at most). */
    private fun ask(method: String, path: String, headers: List<Pair<String, String>>, body: ByteArray?, within: CoroutineScope = scope): Head {
        val head = CompletableFuture<Head>()
        val chunks = Chunks()
        val job = within.launch(Dispatchers.Default) {
            try {
                core.call("station.preview", buildJsonObject {
                    put("station", station); put("port", port); put("method", method); put("path", path); put("stream", true)
                    put("body", body?.let { Base64.encodeToString(it, Base64.NO_WRAP) } ?: "")
                    putJsonArray("headers") { headers.forEach { (k, v) -> add(JsonArray(listOf(JsonPrimitive(k), JsonPrimitive(v)))) } }
                }) { v ->
                    val o = v as? JsonObject ?: return@call
                    val h = o["head"] as? JsonObject
                    val c = o["chunk"] as? JsonPrimitive
                    if (h != null) head.complete(Head(
                        h["status"]!!.jsonPrimitive.int,
                        h["headers"]?.jsonArray?.map { it.jsonArray[0].jsonPrimitive.content to it.jsonArray[1].jsonPrimitive.content } ?: emptyList(),
                        chunks,
                    ))
                    else if (c != null) chunks.put(Base64.decode(c.content, Base64.DEFAULT))
                }
                chunks.end(null)
                head.completeExceptionally(IOException("station 没有给出回答"))
            } catch (e: CancellationException) {
                chunks.end(null)
                head.completeExceptionally(IOException("已取消"))
                throw e
            } catch (e: CoreException) {
                chunks.end(IOException(e.message))
                head.completeExceptionally(e)
            }
        }
        // The page gave it up (read to its end, or let go), or left it unread too long: the station stops asking the service.
        chunks.onClose = { job.cancel() }
        return try {
            head.get(HEAD_WAIT_S, TimeUnit.SECONDS)
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        } catch (e: TimeoutException) {
            job.cancel()
            throw IOException("station 过了 $HEAD_WAIT_S 秒还没有回答")
        } catch (e: InterruptedException) {
            job.cancel()
            throw IOException("已取消")
        }
    }

    /** Why a request got no answer from the service: said to the page with `status`. */
    private class Unanswered(val status: Int, message: String) : IOException(message)

    /** An answer, where it came from in the end (after its redirects) and whether it was redirected there. */
    private class Answer(val head: Head, val path: String, val redirected: Boolean)

    /**
     * Asks the station, following the service's redirects as a browser does (5 at most, to the service only), with the
     * preview's cookies (the WebView's own, for its host: sent along, and what the service sets kept there). `follow`
     * false: a redirect is the answer (its body closed). Throws [Unanswered].
     */
    private fun follow(method: String, path: String, headers: List<Pair<String, String>>, body: ByteArray?, follow: Boolean, within: CoroutineScope = scope, withCookies: Boolean = true): Answer {
        var method = method
        var bytes = body
        var path = path
        var headers = headers
        val cookies = android.webkit.CookieManager.getInstance()
        val given = !withCookies || headers.any { it.first.equals("cookie", ignoreCase = true) }
        repeat(6) { hop ->
            val url = "https://$PREVIEW_HOST$path"
            val asked = if (given) headers else headers + (cookies.getCookie(url)?.takeIf { it.isNotEmpty() }?.let { listOf("Cookie" to it) } ?: emptyList())
            val head = try {
                ask(method, path, asked, bytes, within)
            } catch (e: Exception) {
                throw Unanswered(502, "没能从 station 取到：${e.message}")
            }
            // Several cookies may come joined in one header (", " before the next name=): each is kept.
            if (withCookies) for ((k, v) in head.headers) if (k.equals("set-cookie", ignoreCase = true)) for (one in v.split(COOKIES_JOINED)) cookies.setCookie(url, one)
            val location = head.headers.firstOrNull { it.first.equals("location", ignoreCase = true) }?.second
            if (head.status !in 300..399 || location == null) return Answer(head, path, hop > 0)
            if (!follow) { head.body.close(); return Answer(head, path, hop > 0) }
            head.body.close()
            if (hop == 5) throw Unanswered(508, "跳转太多次了")
            val next = try { java.net.URI("https://$PREVIEW_HOST$path").resolve(location.trim()) } catch (_: Exception) { throw Unanswered(502, "这个网页跳到了一个读不懂的地址：$location") }
            if (next.host != null && next.host != "localhost" && next.host != "127.0.0.1" && next.host != PREVIEW_HOST) throw Unanswered(502, "这个网页跳到了别的地址：$location")
            path = (next.rawPath?.takeIf { it.startsWith("/") } ?: "/") + (next.rawQuery?.let { "?$it" } ?: "")
            if (head.status == 303 || (head.status in 301..302 && method == "POST")) {
                method = "GET"; bytes = null
                headers = headers.filterNot { it.first.equals("content-type", ignoreCase = true) || it.first.equals("content-length", ignoreCase = true) }
            }
        }
        throw Unanswered(508, "跳转太多次了")
    }

    /** Answers a request of the preview's host from the station (following redirects here: a WebView takes no 3xx). */
    fun answer(request: WebResourceRequest): WebResourceResponse {
        val url = request.url
        if (url.encodedPath == PAGE_JS) {
            return WebResourceResponse("text/javascript", "utf-8", 200, "OK", mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(script))
        }
        serve?.let { return it(request.method, pathOf(url)) }
        val asked = request.requestHeaders.toMutableMap()
        val bodyKey = asked.keys.firstOrNull { it.equals(BODY_HEADER, ignoreCase = true) }
        val body = bodyKey?.let { asked.remove(it) }?.let { bodies.remove(it) }
        if (body?.type != null && asked.keys.none { it.equals("content-type", ignoreCase = true) }) asked["Content-Type"] = body.type
        val page = request.isForMainFrame || asked.entries.any { it.key.equals("accept", ignoreCase = true) && it.value.startsWith("text/html") }
        val head = try {
            follow(request.method, pathOf(url), asked.map { it.key to it.value }, body?.bytes, follow = true).head
        } catch (e: Unanswered) {
            return text(e.status, e.message ?: "")
        }
        val type = head.headers.firstOrNull { it.first.equals("content-type", ignoreCase = true) }?.second ?: "application/octet-stream"
        val mime = type.substringBefore(';').trim()
        val charset = Regex("charset=([^;]+)").find(type)?.groupValues?.get(1)?.trim()?.trim('"')
        val encoded = head.headers.any { it.first.equals("content-encoding", ignoreCase = true) && !it.second.equals("identity", ignoreCase = true) }
        // A page of the service gets its script first (its sockets, its bodies, its marks).
        val tagged = page && mime == "text/html" && !encoded
        head.body.events = mime == "text/event-stream" && !encoded
        val out: InputStream = if (tagged) WithTag(head.body) else head.body
        val headers = LinkedHashMap<String, String>()
        for ((k, v) in head.headers) {
            if (tagged && k.equals("content-length", ignoreCase = true)) continue
            headers[k] = headers[k]?.let { "$it, $v" } ?: v
        }
        val status = if (head.status in 200..599 && head.status !in 300..399) head.status else 200
        return WebResourceResponse(mime, charset, status, reason(status), headers, out)
    }

    private fun text(status: Int, message: String) =
        WebResourceResponse("text/plain", "utf-8", status, reason(status), emptyMap(), ByteArrayInputStream(message.toByteArray()))

    /** The WebView wants a reason phrase with every status. */
    private fun reason(status: Int) = when (status) { in 200..299 -> "OK"; 404 -> "Not Found"; in 500..599 -> "Error"; else -> "Status" }

    /** A picture of what the page shows now, `scale` pixels to its CSS pixel (its own size in the app's pixels, at most). */
    fun shot(): Bitmap? {
        val view = web ?: return null
        if (view.width == 0 || view.height == 0) return null
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(android.graphics.Canvas(bitmap))
        return bitmap
    }
}

/**
 * A body as the station sends it: pieces put here as they come (on the core's thread, which never waits here), read
 * by the WebView; closed, it stops coming. At most [BUFFERED_MAX] of it waits: past that it is stopped (`onClose`)
 * and its reader told so.
 */
private class Chunks : InputStream() {
    private object End
    private val queue = LinkedBlockingQueue<Any>()
    /** Bytes put and not yet taken by the reader. */
    private val waiting = java.util.concurrent.atomic.AtomicLong(0)
    @Volatile private var over = false
    private var current: ByteArray? = null
    private var at = 0
    private var done = false
    @Volatile private var closed = false
    var onClose: () -> Unit = {}

    fun put(bytes: ByteArray) {
        if (bytes.isEmpty() || over || closed) return
        if (waiting.addAndGet(bytes.size.toLong()) > BUFFERED_MAX) {
            over = true
            queue.offer(IOException("网页读得太慢，已停止"))
            onClose()
            return
        }
        queue.offer(bytes)
    }
    fun end(error: IOException?) { queue.offer(error ?: End) }

    private fun next(): Boolean {
        while (current == null || at >= current!!.size) {
            if (done) return false
            when (val item = queue.take()) {
                is ByteArray -> { current = item; at = 0; waiting.addAndGet(-item.size.toLong()) }
                is IOException -> { done = true; throw item }
                else -> { done = true; return false }
            }
        }
        return true
    }

    override fun read(): Int {
        if (closed || !next()) return -1
        return current!![at++].toInt() and 0xff
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (len == 0) return 0
        // The WebView reads on until its buffer is full before it hands anything to the page. An event stream's
        // events are to come as they are sent: with nothing more here yet, after a piece that ended its line, the
        // rest of the buffer is filled with a comment (which the page's EventSource passes over).
        if (events && gave && lastByte == '\n'.code.toByte() && (current == null || at >= current!!.size) && queue.isEmpty() && !done && !closed) {
            gave = false
            if (len == 1) { b[off] = '\n'.code.toByte(); return 1 }
            b[off] = ':'.code.toByte()
            java.util.Arrays.fill(b, off + 1, off + len - 1, ' '.code.toByte())
            b[off + len - 1] = '\n'.code.toByte()
            return len
        }
        if (closed || !next()) return -1
        val n = minOf(len, current!!.size - at)
        System.arraycopy(current!!, at, b, off, n)
        at += n
        gave = true
        lastByte = b[off + n - 1]
        return n
    }
    private var gave = false
    private var lastByte: Byte = 0
    /** An event stream (text/event-stream): what comes goes to the page at once. */
    var events = false

    override fun available(): Int = current?.let { it.size - at } ?: 0

    override fun close() {
        if (closed) return
        closed = true
        onClose()
    }
}

/**
 * A page's body with its script's tag in it (as the web's service worker puts it, cloud/src/previewSocket.ts
 * SOCKET_TAG_JS): after the <head> tag, else after <html>, else after the doctype, else first; the first bytes wait
 * until <head> or <html> is there (or 4 KB, or the end), so it never goes before a doctype cut in two.
 */
private class WithTag(private val body: InputStream) : InputStream() {
    private var start: ByteArray? = null
    private var at = 0

    private fun begin(): ByteArray {
        start?.let { return it }
        val head = java.io.ByteArrayOutputStream()
        val buf = ByteArray(4096)
        var whole = false
        var place = -1
        while (place < 0) {
            val n = body.read(buf, 0, minOf(buf.size, 4096 - head.size()).coerceAtLeast(1))
            if (n < 0) whole = true else head.write(buf, 0, n)
            val last = whole || head.size() >= 4096
            place = tagAt(head.toByteArray(), last)
            if (place < 0 && last) place = 0
        }
        val bytes = head.toByteArray()
        val out = java.io.ByteArrayOutputStream(bytes.size + TAG.size)
        out.write(bytes, 0, place)
        out.write(TAG)
        out.write(bytes, place, bytes.size - place)
        return out.toByteArray().also { start = it }
    }

    private fun tagAt(bytes: ByteArray, last: Boolean): Int {
        val text = String(bytes, 0, minOf(bytes.size, 4096), Charsets.ISO_8859_1).lowercase()
        val tags = if (last) listOf(Regex("<head[\\s>]"), Regex("<html[\\s>]"), Regex("<!doctype[\\s>]")) else listOf(Regex("<head[\\s>]"), Regex("<html[\\s>]"))
        for (tag in tags) {
            val found = tag.find(text) ?: continue
            val end = text.indexOf('>', found.range.first)
            if (end >= 0) return end + 1
        }
        return -1
    }

    override fun read(): Int {
        val s = begin()
        if (at < s.size) return s[at++].toInt() and 0xff
        return body.read()
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        val s = begin()
        if (at < s.size) {
            val n = minOf(len, s.size - at)
            System.arraycopy(s, at, b, off, n)
            at += n
            return n
        }
        return body.read(b, off, len)
    }

    override fun close() = body.close()

    companion object {
        val TAG = "<script src=\"$PAGE_JS\"></script>".toByteArray()
    }
}

/**
 * Answers the WebView's requests for the preview's host from the station; anything else goes to the network. Only the
 * preview's host is a page here (it has StillFailPreviewNative): a link to anywhere else goes to `leave` (the app opens
 * it the way it opens links elsewhere).
 */
internal class PreviewClient(private val link: PreviewLink, private val moved: (WebView) -> Unit, private val started: () -> Unit, private val loaded: () -> Unit, private val leave: (android.net.Uri) -> Unit) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        val url = request.url
        if (url.host == PREVIEW_HOST && (url.scheme == "https" || url.scheme == "http")) return false
        // A frame in the page may show what it likes; the page itself stays the preview's.
        if (!request.isForMainFrame) return false
        if (url.scheme == "about") return false
        if (url.scheme in setOf("data", "blob", "javascript")) return true
        view.post { leave(url) }
        return true
    }

    // Where it is, as the page moves (a link, its own history, a reload): for the bar.
    override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) = moved(view)
    override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
        link.pageStarted()
        started()
        moved(view)
    }
    override fun onPageFinished(view: WebView, url: String?) {
        moved(view)
        loaded()
    }

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
        if (request.url.host == PREVIEW_HOST) link.answer(request) else null
}

/** A value the page's script returned (evaluateJavascript gives it as JSON): the JSON string it returned, read. */
internal fun returned(value: String?): JsonElement? {
    if (value == null || value == "null") return null
    return try {
        val outer = kotlinx.serialization.json.Json.parseToJsonElement(value)
        val inner = (outer as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return outer
        kotlinx.serialization.json.Json.parseToJsonElement(inner)
    } catch (_: Exception) {
        null
    }.takeIf { it !is JsonNull }
}
