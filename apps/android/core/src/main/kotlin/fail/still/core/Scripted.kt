package fail.still.core

/**
 * A core with no Rust core behind it, for tests of the app's screens (app/src/androidTest: the motion harness): every
 * message the app posts (a call `{id, call, params}`, a `{id, subscribe}`, an `{id, unsubscribe}`) goes to `onMessage`,
 * which answers as the core would (`{id, ok}`, `{id, value}`, `{id, error}`) through `reply`, from any thread, now or
 * later.
 */
fun StillFailCore.Companion.scripted(onMessage: (json: String, reply: (String) -> Unit) -> Unit): StillFailCore =
    scriptedBytes { json, _, reply -> onMessage(json) { reply(it, null) } }

/**
 * The same, its messages able to carry bytes beside their JSON both ways: `bytes` those a call sends (an upload's part),
 * and those an answer or value sends back (`{id, value}` of a `screen.view`: a frame; `{id, ok}` of a `station.file`).
 */
fun StillFailCore.Companion.scriptedBytes(onMessage: (json: String, bytes: ByteArray?, reply: (json: String, bytes: ByteArray?) -> Unit) -> Unit): StillFailCore {
    val core = StillFailCore({ deliver ->
        object : Engine {
            override fun connect() = 1L
            override fun receive(client: Long, json: String, bytes: ByteArray?) = onMessage(json, bytes) { text, back -> deliver(this, text, back) }
            override fun close() {}
        }
    })
    core.open()
    return core
}
