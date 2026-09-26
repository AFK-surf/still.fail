package dev.ember.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

private fun json(text: String): JsonElement = Json.parseToJsonElement(text)
private fun obj(text: String): JsonObject = json(text).jsonObject

/** A core stand-in: records what the client posts and answers on demand (as FakeWorkers in test/core-client.test.ts). */
private class FakeEngines {
    val opened = mutableListOf<FakeEngine>()
    var failing = 0
    val factory: EngineFactory = { deliver ->
        if (failing > 0) {
            failing--
            throw IllegalStateException("no core")
        }
        FakeEngine(deliver).also { opened += it }
    }
    val last get() = opened.last()
}

private class FakeEngine(val deliver: (Engine, String) -> Unit) : Engine {
    val sent = mutableListOf<JsonElement>()
    var closed = false
    override fun connect() = 1L
    override fun receive(client: Long, json: String) {
        sent += Json.parseToJsonElement(json)
    }
    override fun close() {
        closed = true
    }
    fun reply(text: String) = deliver(this, text)
}

@OptIn(ExperimentalCoroutinesApi::class)
class EmberCoreTest {
    private fun TestScope.core(engines: FakeEngines): EmberCore =
        EmberCore(engines.factory, StandardTestDispatcher(testScheduler)).also { it.open() }

    private inline fun expectError(code: String, block: () -> Unit): CoreException {
        try {
            block()
        } catch (e: CoreException) {
            assertEquals(code, e.code)
            return e
        }
        fail("expected $code")
        throw AssertionError()
    }

    @Test
    fun aCallIsAnsweredByTheMessageWithItsId() = runTest {
        val engines = FakeEngines()
        val core = core(engines)
        val first = async { core.call("station.request", obj("""{"station":"local","method":"GET","path":"/overview"}""")) }
        // Not a child of the test: its failure is for await() to report.
        val second = async(SupervisorJob()) { core.call("auth.signOut", obj("""{"account":"a"}""")) }
        runCurrent()
        assertEquals(
            listOf(
                json("""{"id":1,"call":"station.request","params":{"station":"local","method":"GET","path":"/overview"}}"""),
                json("""{"id":2,"call":"auth.signOut","params":{"account":"a"}}"""),
            ),
            engines.last.sent,
        )
        engines.last.reply("""{"id":2,"error":{"code":"signed_out","message":"已退出","status":401}}""")
        engines.last.reply("""{"id":1,"ok":{"hosts":1}}""")
        runCurrent()
        assertEquals(json("""{"hosts":1}"""), first.await())
        val error = expectError("signed_out") { second.await() }
        assertEquals("已退出", error.message)
        assertEquals(401, error.status)
    }

    @Test
    fun aTopicIsSharedAndLetGoTwoSecondsAfterItsLastCollector() = runTest {
        val engines = FakeEngines()
        val core = core(engines)
        val seen = mutableListOf<TopicState>()
        val first = launch { core.topic(obj("""{"topic":"sessions","station":"w/s"}""")).collect { seen += it } }
        // The same topic written in another order is the same subscription.
        val second = launch { core.topic(obj("""{"station":"w/s","topic":"sessions"}""")).collect {} }
        runCurrent()
        assertEquals(listOf(json("""{"id":1,"subscribe":{"topic":"sessions","station":"w/s"}}""")), engines.last.sent)
        engines.last.reply("""{"id":1,"value":[]}""")
        runCurrent()
        engines.last.reply("""{"id":1,"error":{"code":"offline","message":"离线"}}""")
        runCurrent()
        engines.last.reply("""{"id":1,"value":[{"key":"k"}]}""")
        runCurrent()
        assertEquals(
            listOf(
                TopicState(null, null, true),
                TopicState(json("[]"), null, false),
                // The last value stays next to the error.
                TopicState(json("[]"), seen[2].error, false),
                TopicState(json("""[{"key":"k"}]"""), null, false),
            ),
            seen,
        )
        assertEquals("offline", seen[2].error?.code)
        first.cancel()
        second.cancel()
        advanceTimeBy(1900)
        runCurrent()
        assertEquals(1, engines.last.sent.size)
        advanceTimeBy(200)
        runCurrent()
        assertEquals(json("""{"id":1,"unsubscribe":true}"""), engines.last.sent.last())
        // Late news for it goes nowhere; collecting again subscribes anew, from loading.
        engines.last.reply("""{"id":1,"value":["late"]}""")
        val again = mutableListOf<TopicState>()
        val third = launch { core.topic(obj("""{"topic":"sessions","station":"w/s"}""")).collect { again += it } }
        runCurrent()
        assertEquals(json("""{"id":2,"subscribe":{"topic":"sessions","station":"w/s"}}"""), engines.last.sent.last())
        assertEquals(listOf(TopicState(null, null, true)), again)
        third.cancel()
    }

    @Test
    fun aCollectorComingBackWithinTwoSecondsKeepsTheSubscription() = runTest {
        val engines = FakeEngines()
        val core = core(engines)
        val topic = obj("""{"topic":"accounts"}""")
        launch { core.topic(topic).collect {} }.also { runCurrent() }.cancel()
        engines.last.reply("""{"id":1,"value":[]}""")
        advanceTimeBy(1000)
        runCurrent()
        val seen = mutableListOf<TopicState>()
        val back = launch { core.topic(topic).collect { seen += it } }
        advanceTimeBy(5000)
        runCurrent()
        assertEquals(listOf(json("""{"id":1,"subscribe":{"topic":"accounts"}}""")), engines.last.sent)
        assertEquals(listOf(TopicState(json("[]"), null, false)), seen)
        back.cancel()
    }

    @Test
    fun deltasApplyToTheSubscriptionsValueCopyingOnlyAlongTheirPaths() = runTest {
        val engines = FakeEngines()
        val core = core(engines)
        val seen = mutableListOf<TopicState>()
        val job = launch { core.topic(obj("""{"topic":"session","station":"w/s","key":"k"}""")).collect { seen += it } }
        runCurrent()
        val reply = { text: String -> engines.last.reply(text); runCurrent() }
        // Before any value there is nothing to apply a delta to.
        reply("""{"id":1,"delta":[{"path":["other"],"set":2}]}""")
        reply("""{"id":1,"value":{"detail":{"timeline":[{"text":"a"}],"usage":{"n":1}},"link":{"state":"offline","message":"断了"},"other":{"x":1}}}""")
        reply(
            """{"id":1,"delta":[
                {"path":["detail","timeline"],"append":[{"text":"b"}]},
                {"path":["detail","usage","n"],"set":2},
                {"path":["link","state"],"set":"online"},
                {"path":["link","message"],"remove":true}]}""",
        )
        reply("""{"id":1,"delta":[{"path":["detail","timeline",1,"text"],"set":"bc"}]}""")
        val values = seen.drop(1).map { it.value!!.jsonObject }
        assertEquals(3, values.size)
        val (first, second, third) = values
        assertEquals(
            json("""{"detail":{"timeline":[{"text":"a"},{"text":"b"}],"usage":{"n":2}},"link":{"state":"online"},"other":{"x":1}}"""),
            second,
        )
        assertEquals("the old value is left as it was", json("""[{"text":"a"}]"""), first["detail"]!!.jsonObject["timeline"])
        assertSame(first["other"], second["other"])
        val timeline = { v: JsonObject -> v["detail"]!!.jsonObject["timeline"]!!.jsonArray }
        assertSame(timeline(first)[0], timeline(second)[0])
        assertEquals(json("""{"text":"bc"}"""), timeline(third)[1])
        assertSame(timeline(first)[0], timeline(third)[0])
        assertSame(second["link"], third["link"])
        assertNotSame(second["detail"], third["detail"])
        // After an error, deltas wait for a whole value again.
        reply("""{"id":1,"error":{"code":"offline","message":"离线"}}""")
        reply("""{"id":1,"delta":[{"path":["other"],"set":3}]}""")
        reply("""{"id":1,"value":{"fresh":true}}""")
        assertEquals(listOf("offline", null), seen.drop(4).map { it.error?.code })
        assertEquals(json("""{"fresh":true}"""), seen.last().value)
        assertEquals(6, seen.size)
        job.cancel()
    }

    @Test
    fun aFailedCoreIsReplacedCallsInFlightFailSubscriptionsComeBack() = runTest {
        val engines = FakeEngines()
        val core = core(engines)
        val values = mutableListOf<JsonElement?>()
        val job = launch { core.topic(obj("""{"topic":"accounts"}""")).collect { values += it.value } }
        runCurrent()
        val pending = async(SupervisorJob()) { core.call("cloud.request") }
        runCurrent()
        val old = engines.last
        old.reply("""{"fatal":"panic"}""")
        runCurrent()
        expectError("core_restarted") { pending.await() }
        assertTrue(old.closed)
        assertEquals(2, engines.opened.size)
        assertEquals(listOf(json("""{"id":1,"subscribe":{"topic":"accounts"}}""")), engines.last.sent)
        // The old core's late words are not the new one's.
        old.reply("""{"id":1,"value":"stale"}""")
        engines.last.reply("""{"id":1,"value":["a"]}""")
        runCurrent()
        assertEquals(listOf(null, json("""["a"]""")), values)
        // Calls get fresh ids.
        val unanswered = launch { core.call("x") }
        runCurrent()
        assertEquals(json("""{"id":3,"call":"x","params":{}}"""), engines.last.sent.last())
        unanswered.cancel()
        job.cancel()
    }

    @Test
    fun aCoreThatKeepsFailingIsRestartedWithGrowingPausesResetByAHealthyAnswer() = runTest {
        val engines = FakeEngines()
        engines.failing = 2
        val core = core(engines)
        // Failed at once, retried after 0 ms (failed again), then after 1000 ms.
        runCurrent()
        assertEquals(0, engines.opened.size)
        advanceTimeBy(999)
        runCurrent()
        assertEquals(0, engines.opened.size)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, engines.opened.size)
        // A call made while the core was down went out once it was up… as does one made now.
        engines.last.reply("""{"fatal":"panic"}""")
        runCurrent()
        val queued = async { core.call("auth.begin", obj("""{"redirect_uri":"r"}""")) }
        advanceTimeBy(1999)
        runCurrent()
        assertEquals(1, engines.opened.size)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, engines.opened.size)
        assertEquals(listOf(json("""{"id":1,"call":"auth.begin","params":{"redirect_uri":"r"}}""")), engines.last.sent)
        engines.last.reply("""{"id":1,"ok":null}""")
        runCurrent()
        queued.await()
        // Healthy again: the next failure is retried at once.
        engines.last.reply("""{"fatal":"panic"}""")
        runCurrent()
        assertEquals(3, engines.opened.size)
    }
}

class DeltaTest {
    @Test
    fun appliesEachKindOfOp() {
        val value = Json.parseToJsonElement("""{"a":[1,2],"b":{"c":1,"d":2}}""")
        fun apply(ops: String) = applyDelta(value, Json.parseToJsonElement(ops) as JsonArray)
        assertEquals(Json.parseToJsonElement("[3]"), apply("""[{"path":[],"set":[3]}]"""))
        assertEquals(Json.parseToJsonElement("""{"a":[1,2,3,4],"b":{"c":1,"d":2}}"""), apply("""[{"path":["a"],"append":[3,4]}]"""))
        assertEquals(Json.parseToJsonElement("""{"a":[1,5],"b":{"c":1,"d":2}}"""), apply("""[{"path":["a",1],"set":5}]"""))
        assertEquals(Json.parseToJsonElement("""{"a":[1,2],"b":{"d":2}}"""), apply("""[{"path":["b","c"],"remove":true}]"""))
        assertEquals(Json.parseToJsonElement("""{"a":[1,2],"b":{"c":1,"d":2},"e":null}"""), apply("""[{"path":["e"],"set":null}]"""))
    }

    @Test
    fun ignoresOpsThatDoNotFitTheValue() {
        val value = Json.parseToJsonElement("""{"a":[1,2],"b":{"c":1}}""")
        for (op in listOf(
            """{"path":["a",2],"set":0}""",
            """{"path":["a","x"],"set":0}""",
            """{"path":["b",0],"set":0}""",
            """{"path":["b","c"],"append":[1]}""",
            """{"path":["x","y"],"set":0}""",
        )) {
            assertEquals(op, value, applyDelta(value, Json.parseToJsonElement("[$op]") as JsonArray))
        }
    }
}
