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

/** Starts an engine whose messages go to `onMessage`, tagged with the engine they came from. */
internal typealias EngineFactory = (onMessage: (from: Engine, json: String) -> Unit) -> Engine

/** What the core's engine (cpp/engine.cpp) calls back with: what the core says, as UTF-8. */
internal fun interface HermesListener {
    fun onBytes(json: ByteArray)
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
internal fun hermesEngines(context: Context, dataDir: String, cloudOrigin: String, beta: Boolean = false): EngineFactory {
    val script by lazy { context.assets.open(CORE_SCRIPT).use { it.readBytes() } }
    return { deliver ->
        object : Engine {
            // A message the app fails on is said in the log and dropped: an exception thrown back into the engine's
            // thread through JNI aborts the whole app.
            private val handle: Long = HermesNative.start(script, CORE_SCRIPT, dataDir, cloudOrigin, beta, HermesListener {
                try {
                    deliver(this, String(it, Charsets.UTF_8))
                } catch (e: Throwable) {
                    Log.e("stillfail-core", "a message from the core failed: ${String(it, Charsets.UTF_8).take(300)}", e)
                }
            })
            override fun connect() = HermesNative.connect(handle)
            override fun receive(client: Long, json: String) = HermesNative.receive(handle, client, json)
            override fun close() = HermesNative.close(handle)
        }
    }
}
