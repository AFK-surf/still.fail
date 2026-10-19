// The app's memory running away, told from inside (docs/telemetry.md → Android): on an OPPO PLP110 in 2026-10 the
// native heap grew some 300 MB a minute until the system killed the app (`Killed`, Crashes.kt), with the Rust shell's
// threads busy while the app sat still, and nothing an emulator did brought it on. Once the native heap passes
// [LIMIT], what is under way then goes to PostHog once per process as `MemoryRunaway`: the shell's calls by operation
// over a short window (a loop between the core and the shell is one operation far ahead), the core's JS sampled for
// that window (its hottest stacks), the busiest threads, and the heap's sizes.
package fail.still.android

import android.content.Context
import android.os.Debug
import fail.still.core.CoreProfile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import java.io.File

object MemoryWatch {
    /** The native heap past which the app reports (it is some 70–200 MB as the app is used). */
    private const val LIMIT = 1536L * 1024 * 1024
    private const val EVERY_MS = 30_000L
    /** How long the calls are counted and the JS sampled. */
    private const val WINDOW_S = 15

    @Volatile private var started = false

    fun start(context: Context) {
        if (started) return
        started = true
        val app = context.applicationContext
        Thread({
            try {
                while (Debug.getNativeHeapAllocatedSize() < LIMIT) Thread.sleep(EVERY_MS)
                Crashes.memoryRunaway(app, look(app))
            } catch (_: Throwable) {
            }
        }, "stillfail-memory").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }.start()
    }

    /** What is under way, over [WINDOW_S] seconds. */
    private fun look(context: Context): Pair<String, JsonObject> {
        val heapBefore = Debug.getNativeHeapAllocatedSize()
        val callsBefore = calls()
        val ticksBefore = threadTicks()
        val trace = File(context.cacheDir, "memory-runaway.cpuprofile").also { it.delete() }
        CoreProfile.sample(WINDOW_S, trace.path)
        Thread.sleep(WINDOW_S * 1000L + 2_000)
        val heapAfter = Debug.getNativeHeapAllocatedSize()
        val stats = stats()
        val callsAfter = calls(stats)
        val ticksAfter = threadTicks()
        val mb = { b: Long -> b / (1024 * 1024) }
        val grew = (heapAfter - heapBefore) * 60 / (WINDOW_S + 2)
        val busiest = callsAfter.map { (op, n) -> op to n - (callsBefore[op] ?: 0) }.filter { it.second > 0 }.sortedByDescending { it.second }.take(15)
        val hot = try { hottest(trace.readText()) } catch (_: Exception) { null }
        trace.delete()
        val facts = buildJsonObject {
            put("native_heap_mb", mb(heapAfter))
            put("native_heap_grew_mb_per_min", mb(grew))
            put("java_heap_mb", mb(Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()))
            put("window_s", WINDOW_S)
            put("shell_calls", buildJsonObject { for ((op, n) in busiest) put(op, n) })
            put("shell_unanswered", buildJsonObject {
                (stats?.get("calls") as? JsonObject)?.map { (op, v) -> op to v.jsonArray[1].jsonPrimitive.long }?.filter { it.second > 0 }
                    ?.sortedByDescending { it.second }?.take(15)?.forEach { (op, open) -> put(op, open) }
            })
            stats?.get("handles")?.let { put("shell_handles", it) }
            stats?.get("sqls")?.let { put("shell_sqls", it) }
            // Each thread's share of one core over the window, in percent (its ticks are 10 ms).
            put("threads", buildJsonObject {
                ticksAfter.map { (tid, v) -> v.first to v.second - (ticksBefore[tid]?.second ?: 0) }.sortedByDescending { it.second }.take(8)
                    .forEach { (name, ticks) -> put(name, ticks / (WINDOW_S + 2)) }
            })
            hot?.let { put("js", it) }
        }
        val top = busiest.take(3).joinToString(", ") { "${it.first} ×${it.second}" }
        return "native heap ${mb(heapAfter)} MB, +${mb(grew)} MB/min; shell: ${top.ifEmpty { "quiet" }}" to facts
    }

    private fun stats(): JsonObject? = try { Json.parseToJsonElement(CoreProfile.shellStats()).jsonObject } catch (_: Throwable) { null }

    private fun calls(stats: JsonObject? = stats()): Map<String, Long> =
        (stats?.get("calls") as? JsonObject)?.mapValues { it.value.jsonArray[0].jsonPrimitive.long } ?: emptyMap()

    /** Each thread of this process: its name and the CPU it has used (user and system, in clock ticks of 10 ms). */
    private fun threadTicks(): Map<String, Pair<String, Long>> =
        (File("/proc/self/task").listFiles() ?: emptyArray()).mapNotNull { task ->
            try {
                val stat = File(task, "stat").readText()
                val name = stat.substring(stat.indexOf('(') + 1, stat.lastIndexOf(')'))
                val rest = stat.substring(stat.lastIndexOf(')') + 2).split(' ')
                // After the name: state is field 3, utime 14 and stime 15.
                task.name to ("$name/${task.name}" to rest[11].toLong() + rest[12].toLong())
            } catch (_: Exception) {
                null
            }
        }.toMap()

    /**
     * The JS sampled (Hermes' trace: `stackFrames` by id with their `parent`, `samples` naming the frame they were in):
     * the share of samples not idle, the functions most in them, and the stacks most sampled. A function is named with
     * where it starts in the core's bundle (`name@line:column`), which that build's core.js says what it is.
     */
    internal fun hottest(text: String): JsonObject {
        val trace = Json.parseToJsonElement(text).jsonObject
        val frames = trace["stackFrames"]!!.jsonObject
        val samples = trace["samples"]!!.jsonArray
        fun short(frame: JsonObject): String {
            val name = frame["name"]!!.jsonPrimitive.content.substringBefore('(').ifEmpty { "(anonymous)" }
            val line = (frame["funcLine"] as? JsonPrimitive)?.content
            val column = (frame["funcColumn"] as? JsonPrimitive)?.content
            return if (line != null) "$name@$line:$column" else name
        }
        val inclusive = HashMap<String, Int>()
        val stacks = HashMap<String, Int>()
        var busy = 0
        for (s in samples) {
            var id = s.jsonObject["sf"]?.jsonPrimitive?.content
            val names = ArrayList<String>()
            while (id != null) {
                val frame = frames[id]?.jsonObject ?: break
                names += short(frame)
                id = (frame["parent"] as? JsonPrimitive)?.content
            }
            val real = names.filter { it != "[root]" }
            if (real.isEmpty()) continue
            busy++
            for (n in real.toSet()) inclusive[n] = (inclusive[n] ?: 0) + 1
            val key = real.take(12).joinToString(" < ")
            stacks[key] = (stacks[key] ?: 0) + 1
        }
        val all = samples.size.coerceAtLeast(1)
        return buildJsonObject {
            put("busy_percent", busy * 100 / all)
            put("functions", buildJsonObject { inclusive.entries.sortedByDescending { it.value }.take(25).forEach { put(it.key, it.value * 100 / all) } })
            put("stacks", buildJsonArray {
                stacks.entries.sortedByDescending { it.value }.take(8).forEach { add(buildJsonObject { put("percent", it.value * 100 / all); put("stack", it.key) }) }
            })
        }
    }
}
