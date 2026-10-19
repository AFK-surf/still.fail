package fail.still.android

import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class MemoryWatchTest {
    // Hermes' sampled trace as the core's profile writes it: frames by id with their parent, samples naming one.
    private val trace = """
        {"traceEvents": [], "stackFrames": {
          "1": {"name": "[root]", "category": "root"},
          "2": {"line": "10", "column": "5", "funcLine": "10", "funcColumn": "1", "name": "runLoop(/x/core.js:10:5)", "category": "JavaScript", "parent": 1},
          "3": {"line": "20", "column": "9", "funcLine": "20", "funcColumn": "3", "name": "feed(/x/core.js:20:9)", "category": "JavaScript", "parent": 2},
          "4": {"name": "[HostFunction] callSync", "category": "Native", "parent": 3}
        }, "samples": [
          {"sf": 1, "tid": "5"}, {"sf": 1, "tid": "5"}, {"sf": 4, "tid": "5"}, {"sf": 4, "tid": "5"}, {"sf": 3, "tid": "5"}
        ]}
    """.trimIndent()

    @Test
    fun theHottestStacksOfATrace() {
        val hot = MemoryWatch.hottest(trace)
        assertEquals(60, hot["busy_percent"]!!.jsonPrimitive.int)
        val functions = hot["functions"]!!.jsonObject
        assertEquals(60, functions["runLoop@10:1"]!!.jsonPrimitive.int)
        assertEquals(60, functions["feed@20:3"]!!.jsonPrimitive.int)
        assertEquals(40, functions["[HostFunction] callSync"]!!.jsonPrimitive.int)
        val top = hot["stacks"]!!.jsonArray[0].jsonObject
        assertEquals(40, top["percent"]!!.jsonPrimitive.int)
        assertEquals("[HostFunction] callSync < feed@20:3 < runLoop@10:1", top["stack"]!!.jsonPrimitive.content)
    }
}
