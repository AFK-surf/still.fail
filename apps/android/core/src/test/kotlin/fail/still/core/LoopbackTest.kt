package fail.still.core

import java.io.ByteArrayInputStream
import java.net.BindException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * A login's loopback listener (Loopback.kt, the core's `listen.*`; docs/remote-login.md): what comes to the port, a
 * request at a time as the browser sent it, answered once and its connection closed; only loopback; the port taken
 * refused; closed, nothing more taken and the port free again.
 */
class LoopbackTest {
    private val loopback = InetAddress.getByAddress(byteArrayOf(127, 0, 0, 1))

    private fun freePort(): Int = ServerSocket(0, 1, loopback).use { it.localPort }

    private fun obj(text: String) = Json.parseToJsonElement(text).jsonObject

    /** What the browser does: a request, then what came back, whole. */
    private fun send(port: Int, request: String): Socket = Socket(loopback, port).also {
        it.getOutputStream().write(request.toByteArray(Charsets.UTF_8))
        it.getOutputStream().flush()
    }
    private fun answerOf(s: Socket): String = s.use { it.getInputStream().readBytes().toString(Charsets.UTF_8) }

    @Test
    fun aRequestAsItCameAnsweredOnceThenItsConnectionClosed() = runBlocking {
        val l = Loopback()
        val port = freePort()
        val id = obj(l.answer("listen.open", """{"port":$port,"host":"127.0.0.1"}""", null).first)["id"]!!.jsonPrimitive.long
        assertEquals(1, Loopback.open.value)
        val browser = send(port, "GET /callback?code=c0de&state=s3 HTTP/1.1\r\nHost: localhost:$port\r\nUser-Agent: Chrome\r\n\r\n")
        val (head, body) = l.answer("listen.next", """{"id":$id}""", null)
        val r = obj(head)
        assertEquals("GET", r["method"]!!.jsonPrimitive.content)
        assertEquals("/callback?code=c0de&state=s3", r["path"]!!.jsonPrimitive.content)
        assertEquals(listOf("Host" to "localhost:$port", "User-Agent" to "Chrome"), r["headers"]!!.jsonArray.map { it.jsonArray[0].jsonPrimitive.content to it.jsonArray[1].jsonPrimitive.content })
        assertEquals(0, body!!.size)
        val n = r["request"]!!.jsonPrimitive.long
        // The command's answer, as the station brought it back: its own connection's headers not passed on.
        l.answer("listen.respond", """{"id":$id,"request":$n,"status":302,"headers":[["Location","https://cloud.google.com/sdk/auth_success"],["Connection","keep-alive"],["Content-Length","99"]]}""", "moved".toByteArray())
        // A second answer to it finds nothing to write to.
        l.answer("listen.respond", """{"id":$id,"request":$n,"status":500,"headers":[]}""", null)
        val said = answerOf(browser)
        assertTrue(said, said.startsWith("HTTP/1.1 302 Found\r\n"))
        assertTrue(said, said.contains("Location: https://cloud.google.com/sdk/auth_success\r\n"))
        assertTrue(said, said.contains("Connection: close\r\nContent-Length: 5\r\n\r\nmoved"))
        assertTrue(said, !said.contains("keep-alive") && !said.contains("99"))
        l.answer("listen.close", """{"id":$id}""", null)
        assertEquals(0, Loopback.open.value)
    }

    @Test
    fun aFormPostedWithItsBody() = runBlocking {
        val l = Loopback()
        val port = freePort()
        val id = l.open(port, "127.0.0.1")
        val form = "code=c0de&state=s3"
        val browser = send(port, "POST / HTTP/1.1\r\nHost: localhost:$port\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: ${form.length}\r\n\r\n$form")
        val (head, body) = l.answer("listen.next", """{"id":$id}""", null)
        assertEquals("POST", obj(head)["method"]!!.jsonPrimitive.content)
        assertEquals(form, body!!.toString(Charsets.UTF_8))
        l.answer("listen.respond", """{"id":$id,"request":${obj(head)["request"]!!.jsonPrimitive.long},"status":200,"headers":[["Content-Type","text/html"]]}""", "<p>ok</p>".toByteArray())
        assertTrue(answerOf(browser).endsWith("\r\n\r\n<p>ok</p>"))
        l.close(id)
    }

    @Test
    fun thePortTakenRefusedOnlyLoopbackEver() {
        val l = Loopback()
        val port = freePort()
        val id = l.open(port, "127.0.0.1")
        try {
            l.open(port, "127.0.0.1")
            fail("a second listener on a port taken")
        } catch (_: BindException) {}
        try {
            l.open(freePort(), "0.0.0.0")
            fail("listened beyond loopback")
        } catch (_: IllegalArgumentException) {}
        assertEquals(1, Loopback.open.value)
        l.close(id)
        // Free again once closed.
        l.close(l.open(port, "127.0.0.1"))
        assertEquals(0, Loopback.open.value)
    }

    @Test
    fun closedNothingMoreTakenWhatWaitsEnds() = runBlocking {
        val l = Loopback()
        val port = freePort()
        val id = l.open(port, "127.0.0.1")
        // Not HTTP: closed, never handed on.
        answerOf(send(port, "hello\r\n\r\n"))
        val waiting = async(Dispatchers.IO) { l.answer("listen.next", """{"id":$id}""", null) }
        // Asked before it is answered, then the core lets go (the login ended): the browser's connection closed unanswered.
        val late = send(port, "GET /favicon.ico HTTP/1.1\r\nHost: localhost:$port\r\n\r\n")
        val got = obj(waiting.await().first)
        assertEquals("/favicon.ico", got["path"]!!.jsonPrimitive.content)
        l.closeAll()
        assertEquals("", answerOf(late))
        assertEquals("""{"end":true}""", l.answer("listen.next", """{"id":$id}""", null).first)
        assertEquals(0, Loopback.open.value)
    }

    @Test
    fun whatIsNotARequestIsNone() {
        assertNull(Loopback.read(ByteArrayInputStream("GET /\r\n\r\n".toByteArray())))
        assertNull(Loopback.read(ByteArrayInputStream("GET / HTTP/1.1\r\nHost: x\r\n".toByteArray())))
        assertNull(Loopback.read(ByteArrayInputStream("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort".toByteArray())))
        val r = Loopback.read(ByteArrayInputStream("GET /?a=1 HTTP/1.0\r\nHost: 127.0.0.1:1\r\n\r\n".toByteArray()))!!
        assertEquals(listOf("GET", "/?a=1"), listOf(r.method, r.path))
    }
}
