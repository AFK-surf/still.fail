package fail.still.rn.core

import android.util.Base64
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import fail.still.core.CoreEngine

/**
 * The core's engine for the UI in JavaScript: one per process (its files are the app's, one SQLite open at a time),
 * kept across the UI's reloads; each module (each JavaScript runtime) is a client of its own, and what the core says
 * goes to the module started last.
 */
class StillfailCoreModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("StillfailCore")
    Events("message")

    Function("start") { cloudOrigin: String, beta: Boolean ->
      val context = appContext.reactContext ?: throw IllegalStateException("no Android context")
      synchronized(Companion) {
        listener = this@StillfailCoreModule
        val engine = running ?: CoreEngine.start(context, cloudOrigin, beta) { json, bytes -> listener?.said(json, bytes) }
        running = engine
        client = engine.connect()
      }
    }

    Function("post") { json: String ->
      val engine = running ?: throw IllegalStateException("the core is not started")
      engine.receive(client, json)
    }

    Function("stop") {
      synchronized(Companion) {
        running?.close()
        running = null
      }
    }

    OnDestroy {
      synchronized(Companion) { if (listener === this@StillfailCoreModule) listener = null }
    }
  }

  private fun said(json: String, bytes: ByteArray?) {
    sendEvent("message", if (bytes == null) mapOf("json" to json) else mapOf("json" to json, "bytes" to Base64.encodeToString(bytes, Base64.NO_WRAP)))
  }

  companion object {
    private var running: CoreEngine? = null
    @Volatile private var listener: StillfailCoreModule? = null
    @Volatile private var client = 0L
  }
}
