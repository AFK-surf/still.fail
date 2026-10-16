// How a screen view's frames get from the core to the app, measured on a device (docs/remote-screens.md): the real
// engine (Hermes, cpp/engine.cpp) and the real StillFailCore, running assets/frame-bench.js in place of the core, which
// says frames of 20, 100 and 300 KB the two ways the core could: beside the JSON (`emitBytes`) or in it as base64
// (`emit`, decoded again here). Not a pass/fail test: it says what it measured (logcat tag "bench", and bench.txt in the
// test's files), for the choice of the frame path. Run it alone:
//   adb shell am instrument -w -e class fail.still.core.FramePathBench fail.still.core.test/androidx.test.runner.AndroidJUnitRunner
package fail.still.core

import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Base64
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Test

class FramePathBench {
    private class Run(val jsMs: Double, val wallMs: Double, val latencies: List<Double>, val count: Int)

    private fun run(core: StillFailCore, mode: String, size: Int, count: Int, every: Int): Run = runBlocking {
        val latencies = ArrayList<Double>(count)
        var got = 0
        val start = System.nanoTime()
        var last = start
        val params = buildJsonObject { put("mode", mode); put("size", size); put("count", count); put("every", every) }
        val ok = core.stream("bench", params) { value, bytes ->
            val frame = (value as JsonObject)["frame"]!!.jsonObject
            // What the viewer would have in hand: the frame's bytes.
            val data = bytes ?: Base64.getDecoder().decode(value["bytes"]!!.jsonPrimitive.content)
            check(data.size == size) { "a frame of ${data.size} bytes, not $size" }
            val now = System.nanoTime()
            // The engine's clock is CLOCK_MONOTONIC, as System.nanoTime.
            latencies += now / 1e6 - frame["at"]!!.jsonPrimitive.double
            last = now
            got++
        }
        assertEquals(count, got)
        Run(ok.jsonObject["ms"]!!.jsonPrimitive.double, (last - start) / 1e6, latencies, count)
    }

    @Test
    fun framePath() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val script = instrumentation.context.assets.open("frame-bench.js").use { it.readBytes() }
        val dir = File(instrumentation.targetContext.cacheDir, "bench-core").apply { deleteRecursively(); mkdirs() }
        val core = StillFailCore(hermesEngines(instrumentation.targetContext, dir.path, "http://127.0.0.1:9", scriptOf = { script })).also { it.open() }
        // Warmed up first (the JIT, the allocator), each way.
        for (mode in listOf("bytes", "base64")) run(core, mode, 100_000, 20, 0)
        val lines = ArrayList<String>()
        lines += "| frame | path | engine thread ms/frame | burst ms/frame | burst frames/s | 30 fps latency ms (median / p95 / max) |"
        lines += "|---|---|---|---|---|---|"
        for (size in listOf(20_000, 100_000, 300_000)) for (mode in listOf("bytes", "base64")) {
            val burst = run(core, mode, size, 120, 0)
            val paced = run(core, mode, size, 90, 33)
            val sorted = paced.latencies.sorted()
            fun at(q: Double) = sorted[((sorted.size - 1) * q).toInt()]
            lines += "| ${size / 1000} KB | ${if (mode == "bytes") "emitBytes" else "base64 in JSON"} | ${"%.2f".format(burst.jsMs / burst.count)} | " +
                "${"%.2f".format(burst.wallMs / burst.count)} | ${"%.0f".format(burst.count * 1000 / burst.wallMs)} | " +
                "${"%.1f".format(at(0.5))} / ${"%.1f".format(at(0.95))} / ${"%.1f".format(sorted.last())} |"
        }
        val table = lines.joinToString("\n")
        Log.i("bench", "\n" + table)
        File(instrumentation.targetContext.getExternalFilesDir(null), "bench.txt").writeText(table + "\n")
    }
}
