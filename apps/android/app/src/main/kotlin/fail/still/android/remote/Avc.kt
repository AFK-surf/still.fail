// H.264 and H.265 as a station's screen sends them (docs/remote-screens.md: the avcC or hvcC with each config, then
// access units with each NAL after its length) made what Android's decoder takes: the parameter sets as csd-0 (H.264:
// SPS, csd-1 PPS; H.265: VPS, SPS and PPS all in csd-0), and each access unit with start codes (Annex B) in place of
// the lengths.
package fail.still.android.remote

import android.media.MediaFormat
import java.nio.ByteBuffer

private val START = byteArrayOf(0, 0, 0, 1)

/** A config's parameter sets: how long a frame's NAL lengths are, the decoder's type, its csd. */
internal sealed interface VideoConfig {
    val lengthSize: Int
    val mime: String
    fun into(format: MediaFormat)
}

/** An avcC (ISO/IEC 14496-15 AVCDecoderConfigurationRecord): how long a NAL's length is, and the parameter sets. */
internal class AvcConfig(override val lengthSize: Int, val sps: List<ByteArray>, val pps: List<ByteArray>) : VideoConfig {
    override val mime: String get() = MediaFormat.MIMETYPE_VIDEO_AVC
    /** The SPS, each after a start code: MediaFormat's csd-0. */
    fun csd0(): ByteArray = withStarts(sps)
    /** The PPS, likewise: csd-1. */
    fun csd1(): ByteArray = withStarts(pps)
    override fun into(format: MediaFormat) {
        format.setByteBuffer("csd-0", ByteBuffer.wrap(csd0()))
        format.setByteBuffer("csd-1", ByteBuffer.wrap(csd1()))
    }
}

/** An hvcC (ISO/IEC 14496-15 HEVCDecoderConfigurationRecord): how long a NAL's length is, and its VPS, SPS and PPS. */
internal class HevcConfig(override val lengthSize: Int, val units: List<ByteArray>) : VideoConfig {
    override val mime: String get() = MediaFormat.MIMETYPE_VIDEO_HEVC
    /** Every parameter set, each after a start code: MediaFormat's csd-0. */
    fun csd0(): ByteArray = withStarts(units)
    override fun into(format: MediaFormat) {
        format.setByteBuffer("csd-0", ByteBuffer.wrap(csd0()))
    }
}

/** A config's description as the codec says it is; null when it is not one. */
internal fun parseConfig(codec: String, b: ByteArray): VideoConfig? = when (codec) {
    "h264" -> parseAvcC(b)
    "h265" -> parseHvcC(b)
    else -> null
}

/** Reads an hvcC; null when it is not one (too short, another version, an array that runs past its end, no units). */
internal fun parseHvcC(b: ByteArray): HevcConfig? {
    if (b.size < 23 || b[0].toInt() != 1) return null
    val lengthSize = (b[21].toInt() and 3) + 1
    if (lengthSize == 3) return null
    val u16 = { at: Int -> ((b[at].toInt() and 0xff) shl 8) or (b[at + 1].toInt() and 0xff) }
    val units = ArrayList<ByteArray>()
    var at = 23
    repeat(b[22].toInt() and 0xff) {
        if (at + 3 > b.size) return null
        val n = u16(at + 1)
        at += 3
        repeat(n) {
            if (at + 2 > b.size) return null
            val len = u16(at)
            at += 2
            if (len == 0 || at + len > b.size) return null
            units += b.copyOfRange(at, at + len)
            at += len
        }
    }
    return if (units.isEmpty()) null else HevcConfig(lengthSize, units)
}

private fun withStarts(units: List<ByteArray>): ByteArray {
    val out = ByteArray(units.sumOf { START.size + it.size })
    var at = 0
    for (u in units) {
        START.copyInto(out, at); at += START.size
        u.copyInto(out, at); at += u.size
    }
    return out
}

/** Reads an avcC; null when it is not one (too short, another version, a set that runs past its end, no SPS). */
internal fun parseAvcC(b: ByteArray): AvcConfig? {
    if (b.size < 7 || b[0].toInt() != 1) return null
    val lengthSize = (b[4].toInt() and 3) + 1
    if (lengthSize == 3) return null
    var at = 5
    fun sets(n: Int): List<ByteArray>? {
        val out = ArrayList<ByteArray>(n)
        repeat(n) {
            if (at + 2 > b.size) return null
            val len = ((b[at].toInt() and 0xff) shl 8) or (b[at + 1].toInt() and 0xff)
            at += 2
            if (len == 0 || at + len > b.size) return null
            out += b.copyOfRange(at, at + len)
            at += len
        }
        return out
    }
    val sps = sets(b[at++].toInt() and 0x1f) ?: return null
    if (sps.isEmpty() || at >= b.size) return null
    val pps = sets(b[at++].toInt() and 0xff) ?: return null
    return AvcConfig(lengthSize, sps, pps)
}

/** An access unit's NALs (AVCC: each after its `lengthSize`-byte length) as (offset, length) pairs; null when one runs past its end. */
private fun nals(frame: ByteArray, lengthSize: Int): List<Pair<Int, Int>>? {
    val out = ArrayList<Pair<Int, Int>>(4)
    var at = 0
    while (at < frame.size) {
        if (at + lengthSize > frame.size) return null
        var len = 0L
        for (i in 0 until lengthSize) len = (len shl 8) or (frame[at + i].toLong() and 0xff)
        at += lengthSize
        if (len == 0L || at + len > frame.size) return null
        out += at to len.toInt()
        at += len.toInt()
    }
    return out.takeIf { it.isNotEmpty() }
}

/** How long the access unit is in Annex B; -1 when it is not a sound AVCC one. */
internal fun annexBSize(frame: ByteArray, lengthSize: Int): Int =
    nals(frame, lengthSize)?.sumOf { START.size + it.second } ?: -1

/**
 * Puts the access unit into `out` (a decoder's input buffer, from its position) in Annex B: answers how many bytes it
 * put, or -1 when the frame is not a sound AVCC one or does not fit (nothing put then).
 */
internal fun writeAnnexB(frame: ByteArray, lengthSize: Int, out: ByteBuffer): Int {
    val units = nals(frame, lengthSize) ?: return -1
    val size = units.sumOf { START.size + it.second }
    if (out.remaining() < size) return -1
    for ((offset, length) in units) {
        out.put(START)
        out.put(frame, offset, length)
    }
    return size
}

/** The same, as an array of its own (the tests'). */
internal fun annexB(frame: ByteArray, lengthSize: Int): ByteArray? {
    val size = annexBSize(frame, lengthSize)
    if (size < 0) return null
    val out = ByteBuffer.allocate(size)
    writeAnnexB(frame, lengthSize, out)
    return out.array()
}
