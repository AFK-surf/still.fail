package fail.still.core

import android.content.Context
import java.io.File

/**
 * The core's engine for an app that speaks the core's protocol itself (the React Native app, apps/mobile-rn: its UI's
 * client is web/src/core/client.ts): one engine, its messages as they come, nothing kept on this side. The Kotlin app
 * uses [StillFailCore] instead, which keeps topics and calls here.
 */
class CoreEngine private constructor(private val engine: Engine) {
    /** A new client of the core (a UI): the id its messages are sent with and come back to. */
    fun connect(): Long = engine.connect()

    /** A message from client `client` to the core (JSON, as client.ts posts it). */
    fun receive(client: Long, json: String) = engine.receive(client, json)

    fun close() = engine.close()

    companion object {
        /**
         * Starts the core against `cloudOrigin` (`beta`: the beta app's core), its files in the app's
         * `stillfail-core` folder as the Kotlin app keeps them; what it says goes to `onMessage` on the engine's thread:
         * its JSON, and the bytes a message carries beside it or null.
         */
        fun start(context: Context, cloudOrigin: String, beta: Boolean, onMessage: (json: String, bytes: ByteArray?) -> Unit): CoreEngine {
            val app = context.applicationContext
            val dataDir = File(app.filesDir, "stillfail-core").path
            val engine = hermesEngines(app, dataDir, cloudOrigin, beta).invoke { _, json, bytes -> onMessage(json, bytes) }
            return CoreEngine(engine)
        }
    }
}
