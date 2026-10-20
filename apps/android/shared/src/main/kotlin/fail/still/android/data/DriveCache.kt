// Files of a drive kept on the phone once read, so opening one again does not fetch it again: a text the reader reads, a
// picture, PDF or page the viewer shows, a file handed to another app. Each is kept by where it is (station, root, path)
// and as it was (its mtime and size, as its folder says): a file changed on the station is fetched anew and the old one
// deleted. What is kept is the file from its start (the reader reads only the first 16 MB of a longer one), gone on from
// when more is asked; a fetch cut off is gone on from next time. The least lately opened go once all pass FILES_MAX.
// Videos and songs are kept apart, in media3's cache by the ranges played (PLAYED_MAX; the player's CacheDataSource over
// DriveSource). Both are shown and cleared in settings → files kept (KeptFiles.kt).
// media3's cache classes are marked unstable (UnstableApi): their API may change between releases.
@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package fail.still.android.data

import android.content.Context
import android.util.Log
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

private const val TAG = "drive-cache"

object DriveCache {
    /** Files read whole (or from their start): the least lately opened go past this. */
    const val FILES_MAX = 512L * 1024 * 1024
    /** Videos and songs, by the ranges played. */
    const val PLAYED_MAX = 1536L * 1024 * 1024
    /** How many times a file found changed while it is fetched is fetched again from its start before what came is taken. */
    private const val CHANGED_TRIES = 2

    private var context: Context? = null
    fun start(context: Context) { this.context = context.applicationContext }
    private fun context() = context ?: error("DriveCache.start was not called")

    fun dir(context: Context) = File(context.cacheDir, "drive")
    fun playedDir(context: Context) = File(context.cacheDir, "drive-played")

    /** A file kept: where on the phone, and the whole file's size as the station last said. */
    class Kept(val file: File, val total: Long)

    private val locks = HashMap<String, Mutex>()
    private fun lock(id: String) = synchronized(locks) { locks.getOrPut(id) { Mutex() } }
    private fun busy(id: String) = synchronized(locks) { locks[id]?.isLocked == true }

    /** A file's own name in the cache: where it is, hashed (a path may be long, and say more than a name should). */
    private fun idOf(station: String, root: String, path: String): String =
        MessageDigest.getInstance("SHA-256").digest("$station\n$root\n$path".toByteArray()).joinToString("") { "%02x".format(it) }.take(32)

    private fun home(context: Context, id: String, mtime: Long, size: Long) = File(dir(context), "$id-$mtime-$size")
    private fun named(home: File, path: String) = File(home, path.substringAfterLast('/').replace(Regex("[\\u0000-\\u001f]"), "_").trimStart('.').take(120).ifEmpty { "file" })

    /**
     * The file `path` of `root` (`mtime` and `size` as its folder says) kept on the phone, its first `upto` bytes at least
     * (all of it by default): what is kept already is not fetched again, what is missing is, a part at a time.
     * `onProgress` hears the bytes kept so far and the whole size as they come. Found changed on the station meanwhile,
     * it is fetched anew from its start, as it is now.
     */
    suspend fun fetch(api: StationApi, root: String, path: String, mtime: Long, size: Long, upto: Long = Long.MAX_VALUE, onProgress: (Long, Long) -> Unit = { _, _ -> }): Kept {
        val context = context()
        val id = idOf(api.station, root, path)
        return lock(id).withLock {
            var m = mtime
            var total = size
            var tries = 0
            var kept: Kept? = null
            while (kept == null) {
                val home = home(context, id, m, total)
                val file = named(home, path)
                withContext(Dispatchers.IO) {
                    // What was kept of it before it changed.
                    dir(context).listFiles()?.filter { it.name.startsWith("$id-") && it != home }?.forEach { it.deleteRecursively() }
                    home.mkdirs()
                    if (file.length() > total) file.delete()
                }
                val want = minOf(upto, total)
                var have = withContext(Dispatchers.IO) { file.length() }
                var changed = false
                if (have < want) withContext(Dispatchers.IO) { FileOutputStream(file, true) }.use { out ->
                    onProgress(have, total)
                    while (have < want) {
                        val from = have
                        val got = api.driveReadTo(root, path, have, minOf(DRIVE_PART.toLong(), want - have).toInt(), out) { n -> onProgress(from + n, total) }
                        if (got.total != total || (got.mtime != null && got.mtime != m)) {
                            Log.i(TAG, "$path changed: $total B at $m, now ${got.total} B at ${got.mtime}")
                            // What came of it as it is now is not kept with what came before.
                            withContext(Dispatchers.IO) { out.channel.truncate(have) }
                            total = got.total; m = got.mtime ?: m; changed = true
                            break
                        }
                        if (got.count == 0L) break
                        have += got.count
                        onProgress(have, total)
                    }
                }
                if (changed && tries++ < CHANGED_TRIES) continue
                withContext(Dispatchers.IO) {
                    home.setLastModified(System.currentTimeMillis())
                    trim(context, home)
                }
                kept = Kept(file, total)
            }
            kept
        }
    }

    /** The first `upto` bytes of the file (all of it by default), kept or fetched as [fetch] does, and its whole size. */
    suspend fun bytes(api: StationApi, root: String, path: String, mtime: Long, size: Long, upto: Long = Long.MAX_VALUE, onProgress: (Long, Long) -> Unit = { _, _ -> }): Pair<ByteArray, Long> {
        val kept = fetch(api, root, path, mtime, size, upto, onProgress)
        return withContext(Dispatchers.IO) { read(kept.file, minOf(upto, kept.file.length())) } to kept.total
    }

    /** The first `length` bytes of the file if that much is kept (nothing fetched); else null. */
    suspend fun head(station: String, root: String, path: String, mtime: Long, size: Long, length: Int): ByteArray? {
        val file = named(home(context(), idOf(station, root, path), mtime, size), path)
        return withContext(Dispatchers.IO) {
            val n = minOf(length.toLong(), size)
            if (file.length() < n) null else read(file, n)
        }
    }

    private fun read(file: File, n: Long): ByteArray = RandomAccessFile(file, "r").use { f -> ByteArray(n.toInt()).also { f.readFully(it) } }

    private fun sizeOf(f: File): Long = if (f.isDirectory) f.listFiles()?.sumOf { sizeOf(it) } ?: 0L else f.length()

    /** The least lately opened go while all of them are past FILES_MAX: never the one just opened, nor one being fetched. */
    private fun trim(context: Context, keep: File) {
        val homes = dir(context).listFiles()?.filter { it.isDirectory }?.sortedByDescending { it.lastModified() }.orEmpty()
        var total = 0L
        for (h in homes) {
            val n = sizeOf(h)
            total += n
            if (total <= FILES_MAX || h == keep || busy(h.name.substringBefore('-'))) continue
            h.deleteRecursively()
            total -= n
        }
    }

    // ── played ──────────────────────────────────────────────────────────

    private var played: SimpleCache? = null

    /** Videos and songs as played: one cache for the app (media3 allows one per directory). Open it off the main thread. */
    fun played(context: Context = context()): SimpleCache = synchronized(this) {
        played ?: context.applicationContext.let { c -> SimpleCache(playedDir(c), LeastRecentlyUsedCacheEvictor(PLAYED_MAX), StandaloneDatabaseProvider(c)) }.also { played = it }
    }

    /** What a video or song is kept by: where it is and as it was (a file changed is another). */
    fun playedKey(station: String, root: String, path: String, mtime: Long, size: Long) = "$station\n$root\n$path\n$mtime\n$size"

    /** Everything kept: files and what was played. */
    fun size(context: Context): Long = sizeOf(dir(context)) + played(context).cacheSpace

    /** Deletes everything kept: read again from the stations when opened. */
    fun clear(context: Context) {
        dir(context).listFiles()?.filter { !busy(it.name.substringBefore('-')) }?.forEach { it.deleteRecursively() }
        val cache = played(context)
        cache.keys.toList().forEach { cache.removeResource(it) }
    }
}
