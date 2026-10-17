// Files picked on the phone that go onto the machine of a screen being driven (docs/remote-screens.md "Clipboard and
// files"): each up with the drive's upload (`drive.upload.part`), `root` the folder the screen's state names (`drop`),
// one after another, under a free name beside one already there; once there, where it is, for the viewer to paste its
// path or show it in the machine's file manager. They go on past 只看 and the view opening again; the activity's end
// ends them.
package fail.still.android.remote

import android.content.ContentResolver
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import fail.still.android.data.ScreenDrop
import fail.still.android.data.StationApi
import fail.still.android.data.t
import fail.still.android.data.freeName
import fail.still.android.data.picked
import fail.still.core.CoreException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The most names tried for one file before it is said to have failed. */
private const val TRIES = 50

/** Where a file named `name` is in `folder` on the station's machine (its own separator, `\` for a Windows one). */
fun dropPath(folder: String, name: String): String {
    val sep = if ('\\' in folder && '/' !in folder) '\\' else '/'
    return if (folder.endsWith('/') || folder.endsWith('\\')) folder + name else "$folder$sep$name"
}

/** The station refused a file for its name: one is there already (a file, or a folder: 409 `exists`). */
fun nameTaken(e: CoreException): Boolean = e.code == "exists" || e.status == 409

/**
 * Puts a file up as `name` with `put`, and when that name is taken there, as `name (1).ext`, `name (2).ext`… Answers the
 * name it got. Any other failure is thrown as it came.
 */
suspend fun putFree(name: String, put: suspend (String) -> Unit): String {
    val tried = mutableSetOf<String>()
    var next = name
    while (true) {
        try {
            put(next)
            return next
        } catch (e: CoreException) {
            if (!nameTaken(e) || tried.size >= TRIES) throw e
            tried += next
            next = freeName(name, tried)
        }
    }
}

/** The bytes left in `input`, read to its end. */
fun lengthOf(input: java.io.InputStream): Long {
    val buffer = ByteArray(64 * 1024)
    var n = 0L
    while (true) { val got = input.read(buffer); if (got < 0) return n; n += got }
}

/** A file picked to go onto the machine: its name there (a free one, once its own was taken), how far it has got. */
class Drop(val uri: Uri, name: String, val folder: String, val reveal: Boolean) {
    var name by mutableStateOf(name); internal set
    /** Its bytes (-1 until its provider says), and those the station has. */
    var size by mutableLongStateOf(-1L); internal set
    var sent by mutableLongStateOf(0L); internal set
    /** `waiting`, `going`, `done` or `failed` (why in `error`). */
    var state by mutableStateOf("waiting"); internal set
    var error by mutableStateOf<String?>(null); internal set
    /** Where it is (or goes) on the machine. */
    val path: String get() = dropPath(folder, name)
    internal var job: Job? = null
}

/** The files picked for one view, going up one at a time; `station` its address. */
class ScreenDrops(private val core: fail.still.core.StillFailCore, private val station: String, private val scope: CoroutineScope) {
    /** Those going, waiting, done or failed, until let go of, in the order picked. */
    val list = mutableStateListOf<Drop>()
    private var pumping = false

    /** Files picked (`uris`), for `to` (the state's `drop` as it was when they were asked for). */
    fun send(resolver: ContentResolver, uris: List<Uri>, to: ScreenDrop) {
        if (uris.isEmpty()) return
        scope.launch {
            val named = uris.map { uri -> Drop(uri, withContext(Dispatchers.IO) { picked(resolver, uri).first }, to.folder, to.reveal) }
            list += named
            pump(resolver)
        }
    }

    /** Let go of: off the list, stopped if it was going. */
    fun dismiss(d: Drop) {
        d.job?.cancel()
        list.remove(d)
    }

    /** Failed: tried again from the start. */
    fun retry(resolver: ContentResolver, d: Drop) {
        if (d.state != "failed") return
        d.state = "waiting"; d.error = null; d.sent = 0
        pump(resolver)
    }

    private fun pump(resolver: ContentResolver) {
        if (pumping) return
        pumping = true
        scope.launch {
            try {
                while (true) {
                    val d = list.firstOrNull { it.state == "waiting" } ?: break
                    val job = launch { up(resolver, d) }
                    d.job = job
                    job.join()
                }
            } finally { pumping = false }
        }
    }

    private suspend fun up(resolver: ContentResolver, d: Drop) {
        d.state = "going"
        try {
            val known = withContext(Dispatchers.IO) { picked(resolver, d.uri).second }
            // A provider that does not say how big it is: read it once to know (counted, not skipped: a file's stream
            // refuses a skip past its end).
            d.size = if (known >= 0) known else withContext(Dispatchers.IO) { resolver.openInputStream(d.uri)?.use(::lengthOf) ?: 0L }
            val open = { resolver.openInputStream(d.uri) ?: throw java.io.IOException(t("android-misc.drive.upload.unreadable")) }
            val api = StationApi(core, station)
            d.name = putFree(d.name) { name ->
                d.name = name
                d.sent = 0
                api.driveUpload(d.folder, name, d.size, open) { d.sent = it }
            }
            d.state = "done"
        } catch (e: CancellationException) {
            throw e
        } catch (e: CoreException) {
            d.state = "failed"; d.error = e.message
        } catch (e: java.io.IOException) {
            d.state = "failed"; d.error = e.message ?: ""
        }
    }
}
