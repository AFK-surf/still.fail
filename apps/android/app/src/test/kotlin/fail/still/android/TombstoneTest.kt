package fail.still.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

class TombstoneTest {
    // A protobuf writer for the fields Tombstone reads (tombstone.proto's numbers).
    private class W {
        val out = ByteArrayOutputStream()
        fun varint(v: Long) { var x = v; while (x >= 0x80 || x < 0) { out.write(((x and 0x7f) or 0x80).toInt()); x = x ushr 7 }; out.write(x.toInt()) }
        fun num(n: Int, v: Long) = apply { varint((n shl 3).toLong()); varint(v) }
        fun bytes(n: Int, b: ByteArray) = apply { varint(((n shl 3) or 2).toLong()); varint(b.size.toLong()); out.write(b) }
        fun str(n: Int, s: String) = bytes(n, s.toByteArray())
        fun msg(n: Int, m: W) = bytes(n, m.out.toByteArray())
        fun fixed64(n: Int) = apply { varint(((n shl 3) or 1).toLong()); out.write(ByteArray(8)) }
    }

    private fun frame(pc: Long, function: String, file: String) = W().num(1, pc).num(2, pc + 1).str(4, function).num(5, 12).str(6, file)
    private fun thread(id: Int, name: String, vararg frames: W) = W().num(1, id.toLong()).str(2, name).apply { frames.forEach { msg(4, it) } }
    private fun entry(id: Int, t: W) = W().num(1, id.toLong()).msg(2, t)

    private val tombstone = W()
        .num(1, 1)
        .str(2, "google/panther/panther:16/BP2A/1:user/release-keys")
        .num(5, 4242).num(6, 4250)
        .str(9, "fail.still.android")
        .msg(10, W().num(1, 6).str(2, "SIGABRT").num(3, -1).str(4, "SI_QUEUE"))
        .str(14, "terminating due to uncaught exception of type facebook::jni::JniException")
        .msg(16, entry(4242, thread(4242, "main", frame(0x1000, "__epoll_pwait", "/apex/com.android.runtime/lib64/bionic/libc.so"))))
        .msg(16, entry(4250, thread(4250, "hermes-core", frame(0x5a5c4, "abort", "/apex/com.android.runtime/lib64/bionic/libc.so"), frame(0x8800, "facebook::jni::throwPendingJniExceptionAsCppException()", "/data/app/lib/arm64/libfbjni.so"))))
        .fixed64(19)
        .msg(18, W().str(1, "main").msg(2, W().str(1, "10-07 09:12:01.123").num(2, 4242).num(3, 4250).num(4, 6).str(5, "libc").str(6, "Fatal signal 6 (SIGABRT)")))
        .out.toByteArray()

    @Test fun theCrashingThreadComesFirstWithTheAbortMessageAndLog() {
        val text = Tombstone.text(tombstone)
        assertTrue(text, text.contains("pid: 4242, tid: 4250, name: hermes-core  >>> fail.still.android <<<"))
        assertTrue(text, text.contains("signal 6 (SIGABRT), code -1 (SI_QUEUE)"))
        assertTrue(text, text.contains("#01 pc 0000000000008800  /data/app/lib/arm64/libfbjni.so (facebook::jni::throwPendingJniExceptionAsCppException()+12)"))
        assertTrue(text, text.indexOf("hermes-core") < text.indexOf("\"main\" tid=4242"))
        assertTrue(text, text.contains("10-07 09:12:01.123 4242 4250 E libc: Fatal signal 6 (SIGABRT)"))
        assertEquals("terminating due to uncaught exception of type facebook::jni::JniException", Tombstone.headline(text))
        assertEquals("SIGABRT", Tombstone.signal(text))
        assertEquals(listOf("libc.so (abort)", "libfbjni.so (facebook::jni::throwPendingJniExceptionAsCppException())"), Tombstone.frames(text))
    }

    @Test fun onlyWarningsAndErrorsOfTheLogGo() {
        val bytes = W().num(5, 1).num(6, 1)
            .msg(18, W().str(1, "main")
                .msg(2, W().num(4, 4).str(5, "Chat").str(6, "something someone wrote"))
                .msg(2, W().num(4, 5).str(5, "Core").str(6, "slow answer")))
            .out.toByteArray()
        val text = Tombstone.text(bytes)
        assertTrue(text, text.contains("W Core: slow answer"))
        assertTrue(text, !text.contains("someone wrote"))
    }

    @Test fun anAnrIsKnownByTheMainThreadsTopFrames() {
        val dump = "----- pid 1 -----\n\"main\" prio=5 tid=1 Blocked\n  | group=\"main\"\n  at fail.still.android.Foo.wait(Foo.kt:3)\n  - waiting to lock <0x1>\n  at fail.still.android.Bar.run(Bar.kt:9)\n\n\"other\" tid=2\n  at x.Y.z(Y.kt:1)\n"
        assertEquals(listOf("fail.still.android.Foo.wait", "fail.still.android.Bar.run"), Crashes.mainFrames(dump))
    }

    @Test fun aThrowableBecomesPostHogsExceptionListCrashSiteLast() {
        val e = IllegalStateException("boom", RuntimeException("under"))
        val list = Crashes.exceptions(e).toString()
        assertTrue(list, list.startsWith("[{\"type\":\"IllegalStateException\",\"value\":\"boom\",\"module\":\"java.lang\""))
        assertTrue(list, list.contains("\"type\":\"chained\""))
        assertTrue(list, list.contains("\"function\":\"aThrowableBecomesPostHogsExceptionListCrashSiteLast\",\"platform\":\"java\""))
    }

    @Test fun whatIsNotATombstoneGivesItsStrings() {
        val text = Tombstone.text(byteArrayOf(0x7f, 0x7f) + "Abort message here".toByteArray() + byteArrayOf(0, 0x7f))
        assertEquals("Abort message here\n", text)
    }
}
