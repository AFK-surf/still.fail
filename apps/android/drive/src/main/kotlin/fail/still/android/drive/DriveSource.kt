// What the player reads a file of a drive through (zdrive's QuicDataSource, over the core): ranged reads (`drive.read`),
// never the whole file first. The window starts small (an MP4's index is a few KB, often at its end), doubles while
// reads run on from each other (playing: fewer, bigger reads are the throughput) up to a part of the core's, and drops
// back to small on a jump, so a seek answers in one small read. Bytes already in the window are served from it (the
// extractor hops between tracks and reopens around seeks). ExoPlayer calls it on its loading thread: the core's call is
// waited for there.
// media3's DataSource and source classes are marked unstable (UnstableApi): their API may change between releases.
@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package fail.still.android.drive

import android.net.Uri
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import fail.still.android.data.DRIVE_PART
import fail.still.android.data.StationApi
import fail.still.core.CoreException
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.runBlocking

private const val TAG = "drive-stream"

/** A file of the drive as the player names it: `stillfail-drive:///<path under its root>`. */
object DriveUri {
    private const val SCHEME = "stillfail-drive"
    fun of(path: String): Uri = Uri.parse("$SCHEME:///${Uri.encode(path, "/")}")
    fun pathOf(uri: Uri): String {
        if (uri.scheme != SCHEME) throw IOException("not a $SCHEME uri: $uri")
        return uri.path.orEmpty().trim('/').ifEmpty { throw IOException("$SCHEME uri names no file: $uri") }
    }
}

/** What the player pulled off the drive, counted where it happened (on the loading thread). */
class StreamStats {
    private val bytes = AtomicLong(0)
    private val reads = AtomicInteger(0)
    private val millis = AtomicLong(0)
    private val window = AtomicInteger(0)

    fun record(n: Int, asked: Int, ms: Long) {
        bytes.addAndGet(n.toLong()); reads.incrementAndGet(); millis.addAndGet(ms); window.set(asked)
    }

    val bytesRead get() = bytes.get()
    val readCount get() = reads.get()
    /** Bytes per second while reading (the time spent in the reads themselves). */
    val rate: Double get() = millis.get().takeIf { it > 0 }?.let { bytes.get() * 1000.0 / it } ?: 0.0
    val windowBytes get() = window.get()
}

/** How many bytes one read asks for: small first, doubling while reads run on, a core's part at most. */
internal object ReadWindow {
    const val FIRST = 256 * 1024
    val MAX = DRIVE_PART
    fun grow(current: Int): Int = (current * 2).coerceAtMost(MAX)
}

class DriveSource(private val api: StationApi, private val root: String, private val sizes: Map<String, Long>, private val stats: StreamStats) : BaseDataSource(true) {
    private var uri: Uri? = null
    private var path = ""
    private var fileSize = -1L
    private var position = 0L
    private var remaining = 0L

    /** The window held: [windowStart, windowStart + windowValid). */
    private var window = ByteArray(0)
    private var windowStart = 0L
    private var windowValid = 0
    private var cursor = 0
    private var windowPath = ""
    private var planned = ReadWindow.FIRST
    private var announced = false

    override fun open(dataSpec: DataSpec): Long {
        path = DriveUri.pathOf(dataSpec.uri)
        uri = dataSpec.uri
        if (windowPath != path) { windowPath = path; windowValid = 0; fileSize = -1 }
        if (fileSize < 0) fileSize = sizes[path] ?: -1
        val start = dataSpec.position
        position = start
        // A reopen inside the window is served from it (the extractor does this around every seek).
        if (start < windowStart || start >= windowStart + windowValid) { windowStart = start; windowValid = 0 }
        cursor = (start - windowStart).toInt()
        // The size not known (not in the listing): the first read says it.
        if (fileSize < 0 && !fill()) fileSize = start
        if (start > fileSize) throw IOException("$path is $fileSize bytes, asked to open at $start")
        remaining = if (dataSpec.length == C.LENGTH_UNSET.toLong()) fileSize - start else minOf(dataSpec.length, fileSize - start)
        if (!announced) { transferInitializing(dataSpec); transferStarted(dataSpec); announced = true }
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length <= 0) return 0
        if (remaining <= 0L) return C.RESULT_END_OF_INPUT
        if (cursor >= windowValid && !fill()) return C.RESULT_END_OF_INPUT
        val count = minOf(length, windowValid - cursor, remaining.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        System.arraycopy(window, cursor, buffer, offset, count)
        cursor += count
        position += count
        remaining -= count
        bytesTransferred(count)
        return count
    }

    override fun getUri(): Uri? = uri

    /** The window is kept: the extractor closes and reopens around seeks, and comes back for what is in it. */
    override fun close() {
        if (announced) { transferEnded(); announced = false }
    }

    /** Reads the window from `position`; false at the file's end. */
    private fun fill(): Boolean {
        if (fileSize in 0..position) return false
        val contiguous = windowValid > 0 && position == windowStart + windowValid
        planned = if (contiguous) ReadWindow.grow(planned) else ReadWindow.FIRST
        val want = if (fileSize >= 0) (fileSize - position).coerceAtMost(planned.toLong()).toInt() else planned
        if (want <= 0) return false
        val began = SystemClock.elapsedRealtime()
        val into = java.io.ByteArrayOutputStream(want)
        val got = try {
            runBlocking { api.driveReadTo(root, path, position, want, into) }
        } catch (e: CoreException) {
            throw IOException("reading $path at $position ($want bytes): ${e.message}", e)
        }
        val ms = SystemClock.elapsedRealtime() - began
        fileSize = got.total
        if (got.count == 0L) return false
        val bytes = into.toByteArray()
        window = bytes
        windowStart = position
        windowValid = bytes.size
        cursor = 0
        stats.record(bytes.size, want, ms)
        Log.i(TAG, "read $path @$position ${bytes.size}B in ${ms}ms (${"%.1f".format(if (ms > 0) bytes.size / 1048.576 / ms else 0.0)} MB/s) total ${stats.bytesRead}B of $fileSize")
        return true
    }

    class Factory(private val api: StationApi, private val root: String, private val sizes: Map<String, Long>, private val stats: StreamStats) : DataSource.Factory {
        override fun createDataSource(): DataSource = DriveSource(api, root, sizes, stats)
    }
}
