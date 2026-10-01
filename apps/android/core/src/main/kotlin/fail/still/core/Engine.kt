package fail.still.core

import fail.still.core.ffi.CoreListener
import fail.still.core.ffi.StillFailCoreFfi

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

/** The Rust core through uniffi (client/ffi); `beta`: a beta app's (its calls say so, its builds are the beta feed's). */
internal fun ffiEngines(dataDir: String, cloudOrigin: String, beta: Boolean = false): EngineFactory = { deliver ->
    object : Engine, CoreListener {
        private val core: StillFailCoreFfi = fail.still.core.ffi.startAs(dataDir, cloudOrigin, beta, this)
        override fun onMessage(client: ULong, json: String) = deliver(this, json)
        override fun connect() = core.connect().toLong()
        override fun receive(client: Long, json: String) = core.receive(client.toULong(), json)
        override fun close() = core.close()
    }
}
