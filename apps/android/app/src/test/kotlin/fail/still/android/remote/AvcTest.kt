package fail.still.android.remote

import java.nio.ByteBuffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AvcTest {
    private fun bytes(vararg b: Int) = ByteArray(b.size) { b[it].toByte() }

    // An avcC as encoders write it: version 1, profile 66 (baseline), level 31, 4-byte lengths (0xff: 6 reserved bits
    // set, lengthSizeMinusOne 3), one SPS (0xe1: 3 reserved bits, 1 set), one PPS.
    private val sps = bytes(0x67, 0x42, 0xc0, 0x1f, 0xda, 0x01)
    private val pps = bytes(0x68, 0xce, 0x3c, 0x80)
    private val avcC = bytes(1, 0x42, 0xc0, 0x1f, 0xff, 0xe1, 0, sps.size) + sps + bytes(1, 0, pps.size) + pps

    @Test fun avcCMakesTheCsdWithStartCodes() {
        val c = parseAvcC(avcC)!!
        assertEquals(4, c.lengthSize)
        assertArrayEquals(bytes(0, 0, 0, 1) + sps, c.csd0())
        assertArrayEquals(bytes(0, 0, 0, 1) + pps, c.csd1())
    }

    // An hvcC as VideoToolbox writes it: version 1, Main, 4-byte lengths (lengthSizeMinusOne 3 in byte 21), three
    // arrays (VPS 32, SPS 33, PPS 34), one unit each.
    private val vps = bytes(0x40, 0x01, 0x0c)
    private val hsps = bytes(0x42, 0x01, 0x01, 0x01)
    private val hpps = bytes(0x44, 0x01, 0xc1)
    private val hvcC = bytes(1, 0x01, 0x60, 0, 0, 0, 0xb0, 0, 0, 0, 0, 0, 153, 0xf0, 0, 0xfc, 0xfd, 0xf8, 0xf8, 0, 0, 0x0f, 3) +
        bytes(0x20, 0, 1, 0, vps.size) + vps + bytes(0x21, 0, 1, 0, hsps.size) + hsps + bytes(0x22, 0, 1, 0, hpps.size) + hpps

    @Test fun hvcCMakesOneCsdOfEverySetWithStartCodes() {
        val c = parseHvcC(hvcC)!!
        assertEquals(4, c.lengthSize)
        assertArrayEquals(bytes(0, 0, 0, 1) + vps + bytes(0, 0, 0, 1) + hsps + bytes(0, 0, 0, 1) + hpps, c.csd0())
        assertEquals(c.lengthSize, parseConfig("h265", hvcC)!!.lengthSize)
        assertNull(parseConfig("vp9", hvcC))
    }

    @Test fun anHvcCThatIsNotOneIsNone() {
        assertNull(parseHvcC(bytes()))
        assertNull(parseHvcC(hvcC.copyOfRange(0, hvcC.size - 2)))
        // No arrays: no parameter sets.
        assertNull(parseHvcC(hvcC.copyOfRange(0, 22) + bytes(0)))
    }

    @Test fun anAvcCThatIsNotOneIsNone() {
        assertNull(parseAvcC(bytes()))
        assertNull(parseAvcC(bytes(0) + avcC.copyOfRange(1, avcC.size)))
        // A set that runs past its end.
        assertNull(parseAvcC(avcC.copyOfRange(0, avcC.size - 2)))
    }

    @Test fun anAccessUnitHasStartCodesInPlaceOfItsLengths() {
        val idr = bytes(0x65, 0x88, 0x84, 0x00, 0x33)
        val sei = bytes(0x06, 0x05)
        val au = bytes(0, 0, 0, sei.size) + sei + bytes(0, 0, 0, idr.size) + idr
        assertArrayEquals(bytes(0, 0, 0, 1) + sei + bytes(0, 0, 0, 1) + idr, annexB(au, 4))
        // Two-byte lengths take the start codes' extra room.
        val short = bytes(0, sei.size) + sei + bytes(0, idr.size) + idr
        assertArrayEquals(bytes(0, 0, 0, 1) + sei + bytes(0, 0, 0, 1) + idr, annexB(short, 2))
    }

    @Test fun aBrokenAccessUnitPutsNothing() {
        val au = bytes(0, 0, 0, 9, 0x65, 0x88)
        assertNull(annexB(au, 4))
        val out = ByteBuffer.allocate(64)
        assertEquals(-1, writeAnnexB(au, 4, out))
        assertEquals(0, out.position())
        // One that does not fit the decoder's buffer either.
        assertEquals(-1, writeAnnexB(bytes(0, 0, 0, 2, 0x65, 0x88), 4, ByteBuffer.allocate(3)))
    }
}
