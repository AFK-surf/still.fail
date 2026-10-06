// A native crash's tombstone as the system hands it (ApplicationExitInfo.getTraceInputStream on Android 12+): the
// protobuf of AOSP's system/core/debuggerd/proto/tombstone.proto, read here into the text a tombstone file has, the
// crashing thread first and the process's last log lines after. Only the fields used are read; what cannot be read
// (an older format, a cut-off stream) falls back to the printable strings in it.
package fail.still.android

object Tombstone {
    private class Frame(val pc: Long, val function: String, val offset: Long, val file: String)
    private class Thread(val id: Int, val name: String, val frames: List<Frame>)
    private class Log(val time: String, val pid: Int, val tid: Int, val priority: Int, val tag: String, val message: String)

    /** The tombstone as text, at most [Crashes.LOGS] long. */
    fun text(bytes: ByteArray): String = (try {
        read(bytes)
    } catch (_: Exception) {
        null
    } ?: strings(bytes)).take(Crashes.LOGS)

    /** The line a report is titled with: the abort message, or the signal. */
    fun headline(text: String): String? =
        text.lineSequence().firstOrNull { it.startsWith("Abort message: ") }?.removePrefix("Abort message: ")?.trim('\'')
            ?: text.lineSequence().firstOrNull { it.startsWith("signal ") }

    /** The signal's name in the text (SIGABRT), for the exception's type. */
    fun signal(text: String): String? =
        text.lineSequence().firstOrNull { it.startsWith("signal ") }?.substringAfter('(')?.substringBefore(')')?.takeIf { it.isNotEmpty() }

    /** The crashing thread's frames, top first, as `file (function)` without addresses or offsets: what stays the same
     *  from one build or run to the next. */
    fun frames(text: String): List<String> =
        text.lineSequence().dropWhile { it != "backtrace:" }.drop(1).takeWhile { it.startsWith("  #") }.map { line ->
            val rest = line.substringAfter("  pc ").substringAfter("  ")
            val file = rest.substringBefore(" (").substringAfterLast('/')
            val function = rest.substringAfter(" (", "").substringBeforeLast('+')
            if (function.isEmpty()) file else "$file ($function)"
        }.toList()

    private fun read(bytes: ByteArray): String? {
        var pid = 0
        var tid = 0
        var abort = ""
        var signal = ""
        var fingerprint = ""
        val command = mutableListOf<String>()
        val threads = mutableMapOf<Int, Thread>()
        val logs = mutableListOf<Log>()
        Proto(bytes).fields { n, f ->
            when (n) {
                2 -> fingerprint = f.string()
                5 -> pid = f.int()
                6 -> tid = f.int()
                9 -> command += f.string()
                10 -> signal = signal(f.message())
                14 -> abort = f.string()
                16 -> f.message().fields { k, e -> if (k == 2) thread(e.message()).let { threads[it.id] = it } }
                18 -> f.message().fields { k, e -> if (k == 2) logs += log(e.message()) }
            }
        }
        if (pid == 0 && signal.isEmpty() && threads.isEmpty()) return null
        val crashed = threads[tid]
        return buildString {
            if (fingerprint.isNotEmpty()) append("Build fingerprint: '$fingerprint'\n")
            append("pid: $pid, tid: $tid, name: ${crashed?.name ?: "?"}  >>> ${command.joinToString(" ")} <<<\n")
            if (signal.isNotEmpty()) append("$signal\n")
            if (abort.isNotEmpty()) append("Abort message: '$abort'\n")
            crashed?.let { append("\nbacktrace:\n"); frames(it) }
            // Warnings and errors only: the app's own lines that say what went wrong, not whatever else it logged.
            val worth = logs.filter { it.priority >= 5 }.takeLast(50)
            if (worth.isNotEmpty()) {
                append("\n--- log (warnings and errors, last ${worth.size}) ---\n")
                for (l in worth) append("${l.time} ${l.pid} ${l.tid} ${"VDIWEF".getOrElse(l.priority - 2) { '?' }} ${l.tag}: ${l.message}\n")
            }
            for (t in threads.values.filter { it.id != tid }) {
                append("\n\"${t.name}\" tid=${t.id}\n")
                frames(t, 8)
            }
        }
    }

    private fun StringBuilder.frames(t: Thread, most: Int = 64) {
        t.frames.take(most).forEachIndexed { i, f ->
            append("  #${i.toString().padStart(2, '0')} pc ${f.pc.toString(16).padStart(16, '0')}  ${f.file}")
            if (f.function.isNotEmpty()) append(" (${f.function}+${f.offset})")
            append('\n')
        }
    }

    private fun signal(m: Proto): String {
        var number = 0
        var name = ""
        var code = 0
        var codeName = ""
        var fault: Long? = null
        m.fields { n, f ->
            when (n) {
                1 -> number = f.int()
                2 -> name = f.string()
                3 -> code = f.int()
                4 -> codeName = f.string()
                9 -> fault = f.long
            }
        }
        return "signal $number ($name), code $code ($codeName)" + (fault?.let { ", fault addr 0x${it.toString(16)}" } ?: "")
    }

    private fun thread(m: Proto): Thread {
        var id = 0
        var name = ""
        val frames = mutableListOf<Frame>()
        m.fields { n, f ->
            when (n) {
                1 -> id = f.int()
                2 -> name = f.string()
                4 -> frames += frame(f.message())
            }
        }
        return Thread(id, name, frames)
    }

    private fun frame(m: Proto): Frame {
        var pc = 0L
        var function = ""
        var offset = 0L
        var file = ""
        m.fields { n, f ->
            when (n) {
                1 -> pc = f.long
                4 -> function = f.string()
                5 -> offset = f.long
                6 -> file = f.string()
            }
        }
        return Frame(pc, function, offset, file)
    }

    private fun log(m: Proto): Log {
        var time = ""
        var pid = 0
        var tid = 0
        var priority = 0
        var tag = ""
        var message = ""
        m.fields { n, f ->
            when (n) {
                1 -> time = f.string()
                2 -> pid = f.int()
                3 -> tid = f.int()
                4 -> priority = f.int()
                5 -> tag = f.string()
                6 -> message = f.string()
            }
        }
        return Log(time, pid, tid, priority, tag, message)
    }

    /** The runs of printable text in what could not be read as a tombstone. */
    private fun strings(bytes: ByteArray): String {
        val out = StringBuilder()
        var start = -1
        for (i in 0..bytes.size) {
            val b = if (i < bytes.size) bytes[i].toInt() and 0xff else 0
            val printable = b == 0x09 || (b in 0x20..0x7e) || b >= 0x80
            if (printable && start < 0) start = i
            if (!printable && start >= 0) {
                if (i - start >= 6) out.append(String(bytes, start, i - start, Charsets.UTF_8)).append('\n')
                start = -1
                if (out.length > Crashes.LOGS) break
            }
        }
        return out.toString()
    }

    /** One protobuf message: its fields in order, each a varint (`long`) or a length-delimited span. */
    private class Proto(val bytes: ByteArray, val from: Int = 0, val to: Int = bytes.size) {
        class Field(val bytes: ByteArray, val long: Long, val start: Int, val end: Int) {
            fun int() = long.toInt()
            fun string() = String(bytes, start, end - start, Charsets.UTF_8)
            fun message() = Proto(bytes, start, end)
        }

        fun fields(each: (Int, Field) -> Unit) {
            var i = from
            fun varint(): Long {
                var v = 0L
                var shift = 0
                while (true) {
                    require(i < to)
                    val b = bytes[i++].toInt() and 0xff
                    v = v or ((b and 0x7f).toLong() shl shift)
                    if (b < 0x80) return v
                    shift += 7
                    require(shift < 64)
                }
            }
            while (i < to) {
                val tag = varint()
                val n = (tag ushr 3).toInt()
                when ((tag and 7).toInt()) {
                    0 -> each(n, Field(bytes, varint(), 0, 0))
                    1 -> { require(i + 8 <= to); i += 8 }
                    2 -> {
                        val len = varint().toInt()
                        require(len >= 0 && i + len <= to)
                        each(n, Field(bytes, 0, i, i + len))
                        i += len
                    }
                    5 -> { require(i + 4 <= to); i += 4 }
                    else -> throw IllegalArgumentException("wire type")
                }
            }
        }
    }
}
