package fail.still.core

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Where the calls the app does are done (`secure.*`, `listen.*`, `picked.*`): off the engine's thread (the Keystore is
 * slow; a prompt waits on the person; a listener waits on the browser; a picked file is read from its disk).
 */
private val sealedScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

/** One running core as [StillFailCore] sees it: a client id, JSON messages each way. Tests put a fake in its place. */
internal interface Engine {
    /** Returns at once; the core catches up on its own thread. */
    fun connect(): Long
    /** `bytes`: what a call carries beside its JSON (an upload's part, a preview's request body), null for the rest. */
    fun receive(client: Long, json: String, bytes: ByteArray? = null)
    /** Stops this core (its thread ends). */
    fun close()
}

/**
 * Starts an engine whose messages go to `onMessage`, tagged with the engine they came from; `bytes`: what a message
 * carries beside its JSON (a screen view's frame, a file's part, docs/client-core.md "Protocol"), null for the rest.
 */
internal typealias EngineFactory = (onMessage: (from: Engine, json: String, bytes: ByteArray?) -> Unit) -> Engine

/** What the core's engine (cpp/engine.cpp) calls back with, on its thread: what the core says, as UTF-8. */
internal interface HermesListener {
    fun onBytes(json: ByteArray)
    /** A message with bytes beside it (`__native.emitBytes`): its JSON without them, and the bytes as they are. */
    fun onFrame(json: ByteArray, bytes: ByteArray)
    /**
     * A call the app does, not the shell (client/core-ts hosts/bridge.ts): `secure.*` (SecureStore.kt), `listen.*`
     * (Loopback.kt), `picked.*` (PickedFiles.kt); its JSON as UTF-8, and the bytes it carries (null: none). Answered later, on another thread, through
     * [HermesNative.complete].
     */
    fun onApp(id: Long, op: String, json: ByteArray, bytes: ByteArray?)
}

/** The engine's JNI (cpp/engine.cpp): Hermes running the core in TypeScript, its IO in the Rust shell (client/shell). */
internal object HermesNative {
    init {
        System.loadLibrary("stillfail_hermes")
    }

    external fun start(script: ByteArray, url: String, dataDir: String, cloudOrigin: String, beta: Boolean, listener: HermesListener): Long
    external fun connect(handle: Long): Long
    external fun receive(handle: Long, client: Long, json: String)
    /** A call with bytes beside its JSON: they reach the core as an ArrayBuffer (`__stillfail.receiveBytes`). */
    external fun receiveBytes(handle: Long, client: Long, json: String, bytes: ByteArray)
    external fun close(handle: Long)
    /** The answer to a call the engine handed to Kotlin ([HermesListener.onApp]): `error` null when it succeeded. */
    external fun complete(handle: Long, id: Long, json: String?, error: String?, bytes: ByteArray?)
    /** The core's JS sampled for `seconds`, its trace written to `path` then (CoreProfile). */
    external fun profile(seconds: Int, path: String)
    /** What the shell has been asked so far: `{calls: {op: [started, unanswered]}, handles: {kind: n}, sqls}`. */
    external fun shellStats(): String
}

/**
 * What the core spends its time on, in the app as shipped: its JS sampled for a while, the trace (Chrome's format, for
 * DevTools' Performance panel) written to a file. Asked from adb (the app's CoreProfileReceiver).
 */
object CoreProfile {
    fun sample(seconds: Int, path: String) = HermesNative.profile(seconds, path)
    /** What the Rust shell has been asked since the process started, as JSON (client/shell `sf_shell_stats`). */
    fun shellStats(): String = HermesNative.shellStats()
}

/** The core's script as the app carries it (apps/android/build.py: client/core-ts as Hermes bytecode). */
internal const val CORE_SCRIPT = "core.hbc"

/**
 * The core in TypeScript (client/core-ts) in Hermes, its files in `dataDir` as the Rust core kept them; `beta`: a beta
 * app's (its calls say so, its builds are the beta feed's).
 */
internal fun hermesEngines(
    context: Context, dataDir: String, cloudOrigin: String, beta: Boolean = false,
    /** The script it runs: the core's, but for a test's own (the frame path's benchmark, src/androidTest). */
    scriptOf: () -> ByteArray = { context.assets.open(CORE_SCRIPT).use { it.readBytes() } },
): EngineFactory {
    val script by lazy(scriptOf)
    val sealed by lazy { SecureStore.of(context) }
    return { deliver ->
        object : Engine {
            /** Answers to the app's calls go only to an engine not closed yet: [close] takes this before it ends the engine. */
            private val answering = Any()
            /** This core's loopback listeners (a login's browser coming back): closed with it. */
            private val loopback = Loopback()
            private var closed = false
            private val started = CompletableDeferred<Long>()

            // A message the app fails on is said in the log and dropped: an exception thrown back into the engine's
            // thread through JNI aborts the whole app.
            private val handle: Long = HermesNative.start(script, CORE_SCRIPT, dataDir, cloudOrigin, beta, object : HermesListener {
                override fun onBytes(json: ByteArray) = said(json, null)
                override fun onFrame(json: ByteArray, bytes: ByteArray) = said(json, bytes)
                override fun onApp(id: Long, op: String, json: ByteArray, bytes: ByteArray?) {
                    sealedScope.launch {
                        val answer = try {
                            val text = String(json, Charsets.UTF_8)
                            Result.success(when {
                                op.startsWith("listen.") -> loopback.answer(op, text, bytes)
                                op.startsWith("picked.") -> PickedFiles.answer(op, text)
                                else -> sealed.answer(op, text, bytes)
                            })
                        } catch (e: Throwable) {
                            Result.failure(e)
                        }
                        // The call may come before `start` returned the engine's handle.
                        val at = started.await()
                        synchronized(answering) {
                            if (closed) return@launch
                            answer.fold(
                                { (head, body) -> HermesNative.complete(at, id, head, null, body) },
                                { e -> HermesNative.complete(at, id, null, SecureStore.errorText(e), null) },
                            )
                        }
                    }
                }
            }).also { started.complete(it) }

            private fun said(json: ByteArray, bytes: ByteArray?) {
                try {
                    deliver(this, String(json, Charsets.UTF_8), bytes)
                } catch (e: Throwable) {
                    Log.e("stillfail-core", "a message from the core failed: ${String(json, Charsets.UTF_8).take(300)}", e)
                }
            }
            override fun connect() = HermesNative.connect(handle)
            override fun receive(client: Long, json: String, bytes: ByteArray?) =
                if (bytes == null) HermesNative.receive(handle, client, json) else HermesNative.receiveBytes(handle, client, json, bytes)
            override fun close() {
                synchronized(answering) { closed = true }
                loopback.closeAll()
                HermesNative.close(handle)
            }
        }
    }
}
