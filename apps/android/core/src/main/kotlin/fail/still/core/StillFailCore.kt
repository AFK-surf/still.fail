package fail.still.core

import android.content.Context
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.shareIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** A call or topic that failed; `code` is the core's (still.fail cloud's codes pass through), `status` the HTTP status behind it. */
class CoreException(val code: String, override val message: String, val status: Int?) : Exception(message)

/** A topic as the UI shows it: the last value stays next to an error; `loading` until the first value or error. */
data class TopicState(val value: JsonElement?, val error: CoreException?, val loading: Boolean)

/**
 * The app's side of the core (docs/client-core.md), as web/src/core/client.ts
 * and react.ts are the web's: calls with request ids, topics shared by
 * everyone who collects the same one, deltas applied. The core runs on a
 * thread of its own (client/ffi); if it dies it is started again and the
 * topics are subscribed anew, while calls in flight fail with `core_restarted`.
 */
class StillFailCore internal constructor(
    private val engines: EngineFactory,
    dispatcher: CoroutineDispatcher = Dispatchers.Default,
) {
    companion object {
        private val started = Mutex()
        private var instance: StillFailCore? = null

        /** One per process. `cloudOrigin` e.g. "https://app.still.fail" (the emulator reaches a dev cloud at http://10.0.2.2:8787). */
        suspend fun start(context: Context, cloudOrigin: String): StillFailCore = started.withLock {
            instance?.let { core ->
                require(core.cloudOrigin == cloudOrigin) { "the core already runs against ${core.cloudOrigin}" }
                return core
            }
            val dataDir = File(context.applicationContext.filesDir, "stillfail-core").path
            // Loads the library off the caller's thread; it is the slow part of starting.
            withContext(Dispatchers.IO) { fail.still.core.ffi.utcOffsetMin(0.0) }
            val core = StillFailCore(ffiEngines(dataDir, cloudOrigin))
            core.cloudOrigin = cloudOrigin
            withContext(core.confined) { core.open() }
            instance = core
            core
        }
    }

    private var cloudOrigin = ""
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    /** Every bit of state below is touched only here, one thing at a time, in the order messages arrived. */
    private val confined = dispatcher.limitedParallelism(1)

    private var engine: Engine? = null
    private var client = 0L
    private var nextId = 1L
    private val calls = HashMap<Long, CompletableDeferred<JsonElement>>()
    /** What calls that say how they go (`{id, value}` before their answer: a streamed preview, a preview socket) hear. */
    private val progress = HashMap<Long, (JsonElement) -> Unit>()
    private val subs = HashMap<Long, Subscription>()
    /** Calls made while the core is being restarted, sent once it is up. */
    private val queue = ArrayList<String>()
    private var failures = 0
    private val topics = ConcurrentHashMap<JsonObject, Flow<TopicState>>()

    private class Subscription(val topic: JsonObject, val onState: (TopicState) -> Unit) {
        /** The whole current value deltas apply to; null before the first value and after an error. */
        var value: JsonElement? = null
        var state = TopicState(null, null, true)
    }

    /** One call of docs/client-core.md → Calls. Throws [CoreException]. */
    suspend fun call(name: String, params: JsonObject = buildJsonObject {}): JsonElement {
        val answer = CompletableDeferred<JsonElement>()
        val id = withContext(confined) {
            val id = nextId++
            calls[id] = answer
            send(buildJsonObject { put("id", id); put("call", name); put("params", params) }.toString())
            id
        }
        try {
            return answer.await()
        } catch (e: CancellationException) {
            scope.launch(confined) { calls.remove(id) }
            throw e
        }
    }

    /**
     * A call that says how it goes before it answers (docs/client-core.md: a streamed `station.preview`, a
     * `preview.socket`, `station.file` with `progress`): each value to `onProgress` (on the core's own thread, in
     * order), then its answer. Cancelling the coroutine cancels the call (`{id, cancel}`), which the core stops.
     */
    suspend fun call(name: String, params: JsonObject, onProgress: (JsonElement) -> Unit): JsonElement {
        val answer = CompletableDeferred<JsonElement>()
        val id = withContext(confined) {
            val id = nextId++
            calls[id] = answer
            progress[id] = onProgress
            send(buildJsonObject { put("id", id); put("call", name); put("params", params) }.toString())
            id
        }
        try {
            return answer.await()
        } catch (e: CancellationException) {
            scope.launch(confined) {
                progress.remove(id)
                if (calls.remove(id) != null) send(buildJsonObject { put("id", id); put("cancel", true) }.toString())
            }
            throw e
        }
    }

    /**
     * A topic (docs/client-core.md → Topics / Views) as a Flow: subscribes on
     * first collector, shared by identical topics, deltas applied,
     * unsubscribes 2 s after the last collector leaves (so a screen coming
     * back at once does not resubscribe).
     */
    fun topic(topic: JsonObject): Flow<TopicState> = topics.getOrPut(topic) { shared(topic) }

    private fun shared(topic: JsonObject): Flow<TopicState> {
        lateinit var flow: Flow<TopicState>
        flow = callbackFlow {
            val id = withContext(confined) { subscribe(topic) { trySend(it) } }
            awaitClose {
                scope.launch(confined) { unsubscribe(id) }
                topics.remove(topic, flow)
            }
        }
            // Each state is whole: a slow collector only needs the latest.
            .conflate()
            .shareIn(scope, SharingStarted.WhileSubscribed(LINGER_MS, replayExpirationMillis = 0), replay = 1)
        return flow
    }

    private fun subscribe(topic: JsonObject, onState: (TopicState) -> Unit): Long {
        val id = nextId++
        val sub = Subscription(topic, onState)
        subs[id] = sub
        onState(sub.state)
        // While the core is being restarted, open() subscribes everything anew.
        if (engine != null) post(buildJsonObject { put("id", id); put("subscribe", topic) }.toString())
        return id
    }

    private fun unsubscribe(id: Long) {
        if (subs.remove(id) != null && engine != null) post(buildJsonObject { put("id", id); put("unsubscribe", true) }.toString())
    }

    /** Starts a core and brings it up to date: every topic subscribed, queued calls sent. */
    internal fun open() {
        val next = try {
            engines { from, json -> scope.launch(confined) { if (from === engine) receive(json) } }
        } catch (e: Exception) {
            android.util.Log.e("StillFailCore", "the core did not start", e)
            retry()
            return
        }
        engine = next
        client = next.connect()
        for ((id, sub) in subs) post(buildJsonObject { put("id", id); put("subscribe", sub.topic) }.toString())
        val queued = queue.toList()
        queue.clear()
        queued.forEach(::post)
    }

    private fun restart(reason: String) {
        android.util.Log.e("StillFailCore", "the core failed: $reason")
        engine?.close()
        engine = null
        // Whether they ran is unknown: the caller decides whether to try again.
        val failed = calls.values.toList()
        calls.clear()
        progress.clear()
        queue.clear()
        failed.forEach { it.completeExceptionally(CoreException("core_restarted", "核心已重启，请重试", null)) }
        for (sub in subs.values) sub.value = null
        retry()
    }

    private fun retry() {
        val wait = RETRY_MS[minOf(failures, RETRY_MS.size - 1)]
        failures++
        scope.launch(confined) {
            delay(wait)
            open()
        }
    }

    private fun send(json: String) {
        if (engine != null) post(json) else queue.add(json)
    }

    private fun post(json: String) {
        engine?.receive(client, json)
    }

    private fun receive(json: String) {
        val message = try {
            Json.parseToJsonElement(json).jsonObject
        } catch (e: Exception) {
            android.util.Log.e("StillFailCore", "unreadable message from the core", e)
            return
        }
        message["fatal"]?.let {
            restart(it.jsonPrimitive.contentOrNull ?: "")
            return
        }
        // A healthy answer: the core is up again.
        failures = 0
        val id = (message["id"] as? JsonPrimitive)?.longOrNull ?: return
        val error = message["error"]?.let(::coreException)
        // How a call goes, before its answer.
        val going = message["value"]
        if (going != null && error == null && message["ok"] == null) progress[id]?.let { it(going); return }
        progress.remove(id)
        calls.remove(id)?.let { call ->
            if (error != null) call.completeExceptionally(error) else call.complete(message["ok"] ?: JsonNull)
            return
        }
        val sub = subs[id] ?: return // unsubscribed while a value was on its way
        val value = message["value"]
        val delta = message["delta"]
        when {
            error != null -> {
                sub.value = null
                // The last value stays on screen next to the error.
                update(sub, TopicState(sub.state.value, error, false))
            }
            value != null -> {
                sub.value = value
                update(sub, TopicState(value, null, false))
            }
            delta is JsonArray && sub.value != null -> {
                val next = applyDelta(sub.value!!, delta)
                sub.value = next
                update(sub, TopicState(next, null, false))
            }
        }
    }

    private fun update(sub: Subscription, state: TopicState) {
        sub.state = state
        sub.onState(state)
    }
}

private fun coreException(body: JsonElement): CoreException {
    val error = body as? JsonObject
    val code = (error?.get("code") as? JsonPrimitive)?.contentOrNull ?: "unknown"
    val message = (error?.get("message") as? JsonPrimitive)?.contentOrNull ?: code
    return CoreException(code, message, (error?.get("status") as? JsonPrimitive)?.intOrNull)
}

// A core that keeps failing (a panic on start) is restarted with growing pauses rather than in a tight loop.
private val RETRY_MS = longArrayOf(0, 1000, 2000, 5000, 10_000, 30_000)
private const val LINGER_MS = 2000L
