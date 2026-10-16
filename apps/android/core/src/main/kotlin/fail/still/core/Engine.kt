package fail.still.core

import android.content.Context
import android.util.Log

/** One running core as [StillFailCore] sees it: a client id, JSON messages each way. Tests put a fake in its place. */
internal interface Engine {
    /** Returns at once; the core catches up on its own thread. */
    fun connect(): Long
    fun receive(client: Long, json: String)
    /** Stops this core (its thread ends). */
    fun close()
}

/**
 * Starts an engine whose messages go to `onMessage`, tagged with the engine they came from; `bytes`: what a message
 * carries beside its JSON (a screen view's frame, docs/client-core.md "Protocol"), null for the rest.
 */
internal typealias EngineFactory = (onMessage: (from: Engine, json: String, bytes: ByteArray?) -> Unit) -> Engine

/** What the core's engine (cpp/engine.cpp) calls back with, on its thread: what the core says, as UTF-8. */
internal interface HermesListener {
    fun onBytes(json: ByteArray)
    /** A message with bytes beside it (`__native.emitBytes`): its JSON without them, and the bytes as they are. */
    fun onFrame(json: ByteArray, bytes: ByteArray)
}

/** The engine's JNI (cpp/engine.cpp): Hermes running the core in TypeScript, its IO in the Rust shell (client/shell). */
internal object HermesNative {
    init {
        System.loadLibrary("stillfail_hermes")
    }

    external fun start(script: ByteArray, url: String, dataDir: String, cloudOrigin: String, beta: Boolean, listener: HermesListener): Long
    external fun connect(handle: Long): Long
    external fun receive(handle: Long, client: Long, json: String)
    external fun close(handle: Long)
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
    return { deliver ->
        object : Engine {
            // A message the app fails on is said in the log and dropped: an exception thrown back into the engine's
            // thread through JNI aborts the whole app.
            private val handle: Long = HermesNative.start(script, CORE_SCRIPT, dataDir, cloudOrigin, beta, object : HermesListener {
                override fun onBytes(json: ByteArray) = said(json, null)
                override fun onFrame(json: ByteArray, bytes: ByteArray) = said(json, bytes)
            })

            private fun said(json: ByteArray, bytes: ByteArray?) {
                try {
                    deliver(this, String(json, Charsets.UTF_8), bytes)
                } catch (e: Throwable) {
                    Log.e("stillfail-core", "a message from the core failed: ${String(json, Charsets.UTF_8).take(300)}", e)
                }
            }
            override fun connect() = HermesNative.connect(handle)
            override fun receive(client: Long, json: String) = HermesNative.receive(handle, client, json)
            override fun close() = HermesNative.close(handle)
        }
    }
}
