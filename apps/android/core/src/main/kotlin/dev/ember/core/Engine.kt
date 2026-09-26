package dev.ember.core

import dev.ember.core.ffi.CoreListener
import dev.ember.core.ffi.EmberCoreFfi

/** One running core as [EmberCore] sees it: a client id, JSON messages each way. Tests put a fake in its place. */
internal interface Engine {
    /** Returns at once; the core catches up on its own thread. */
    fun connect(): Long
    fun receive(client: Long, json: String)
    /** Stops this core (its thread ends). */
    fun close()
}

/** Starts an engine whose messages go to `onMessage`, tagged with the engine they came from. */
internal typealias EngineFactory = (onMessage: (from: Engine, json: String) -> Unit) -> Engine

/** The Rust core through uniffi (client/ffi). */
internal fun ffiEngines(dataDir: String, cloudOrigin: String): EngineFactory = { deliver ->
    object : Engine, CoreListener {
        private val core: EmberCoreFfi = dev.ember.core.ffi.start(dataDir, cloudOrigin, this)
        override fun onMessage(client: ULong, json: String) = deliver(this, json)
        override fun connect() = core.connect().toLong()
        override fun receive(client: Long, json: String) = core.receive(client.toULong(), json)
        override fun close() = core.close()
    }
}
