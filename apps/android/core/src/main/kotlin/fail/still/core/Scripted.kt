package fail.still.core

/**
 * A core with no Rust core behind it, for tests of the app's screens (app/src/androidTest: the motion harness): every
 * message the app posts (a call `{id, call, params}`, a `{id, subscribe}`, an `{id, unsubscribe}`) goes to `onMessage`,
 * which answers as the core would (`{id, ok}`, `{id, value}`, `{id, error}`) through `reply`, from any thread, now or
 * later.
 */
fun StillFailCore.Companion.scripted(onMessage: (json: String, reply: (String) -> Unit) -> Unit): StillFailCore {
    val core = StillFailCore({ deliver ->
        object : Engine {
            override fun connect() = 1L
            override fun receive(client: Long, json: String) = onMessage(json) { deliver(this, it) }
            override fun close() {}
        }
    })
    core.open()
    return core
}
