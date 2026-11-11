package dev.mbui;

import com.jcraft.jzlib.GZIPException;
import com.jcraft.jzlib.JZlib;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.zip.CRC32;
import java.util.zip.DataFormatException;
import java.util.zip.Inflater;

/**
 * An update's delta made into the released APK (`apply`), and the zip rewrite that makes an APK one a delta can make
 * (`repack`). Pure Java, no android.*: the build machine runs the same class (`main`) as the app.
 *
 * An APK's big entries are deflated, so the delta (scripts/delta.ts, "SFDELTA1") turns the installed APK with its changed
 * entries inflated (`n_inflate`) into the new APK with its changed entries inflated, and the applier deflates those
 * ranges again (`n_deflate`) as it writes. That gives the released bytes (which its signature covers) only if this
 * deflater gives the bytes the release has: the system's (java.util.zip.Deflater, the platform's zlib) differs between
 * Android versions and CPUs, so the app carries its own, JZlib (mbui/android/jzlib), and the release's APK is repacked by this
 * very code before it is aligned and signed (tools/apk). Inflating is the same everywhere: the system's Inflater does it.
 *
 * Memory is bounded (a phone): the old blob is a temporary file read through a buffer, the delta is read as a stream a
 * chunk (≤ 1 MiB) at a time, the made bytes are written as they come.
 */
public final class Delta {
    static final byte[] MAGIC = "SFDELTA1".getBytes(StandardCharsets.US_ASCII);
    /** The largest raw chunk a delta has (the format's bound on an applier's memory). */
    static final int CHUNK = 1 << 20;
    /** A chunk's deflate at most: stored blocks' few bytes over the raw ones. */
    static final int PACKED_MAX = CHUNK + 4096;
    static final int BUF = 64 * 1024;

    /*
     * The deflater's parameters are part of the delta format now: raw deflate (no zlib header), level 6, a 32 KiB window
     * (15 bits), memLevel 8, the default strategy, fed BUF bytes at a time, one fresh deflater per range, finished at
     * its end. The release's entries (repack) and every installed app's applier must deflate alike: changing any of
     * these, or JZlib's version, makes every installed app's delta come out wrong once (its hash refused: a whole
     * download instead) until the apps carry the change.
     */
    static final int LEVEL = 6, WINDOW_BITS = 15, MEM_LEVEL = 8;

    private Delta() {
    }

    interface Sink {
        void write(byte[] b, int off, int len) throws IOException;
    }

    /** One range deflated by JZlib as the format says (above), into `out`. */
    static final class Deflating {
        private final Sink out;
        private final com.jcraft.jzlib.Deflater z;
        private final byte[] in = new byte[BUF], o = new byte[BUF];
        private int fill;
        long written;

        Deflating(Sink out) throws IOException {
            this.out = out;
            try {
                z = new com.jcraft.jzlib.Deflater(LEVEL, WINDOW_BITS, MEM_LEVEL, JZlib.W_NONE);
            } catch (GZIPException e) {
                throw new IOException("the deflater did not start: " + e.getMessage());
            }
        }

        void write(byte[] b, int off, int len) throws IOException {
            while (len > 0) {
                int k = Math.min(len, BUF - fill);
                System.arraycopy(b, off, in, fill, k);
                fill += k;
                off += k;
                len -= k;
                if (fill == BUF) run(JZlib.Z_NO_FLUSH);
            }
        }

        /** The range's end: what is left deflated and the stream ended; how many bytes it came to. */
        long finish() throws IOException {
            run(JZlib.Z_FINISH);
            z.end();
            return written;
        }

        private void run(int flush) throws IOException {
            z.setInput(in, 0, fill, false);
            for (;;) {
                z.setOutput(o, 0, o.length);
                int r = z.deflate(flush);
                int n = z.getNextOutIndex();
                if (n > 0) {
                    out.write(o, 0, n);
                    written += n;
                }
                if (r == JZlib.Z_STREAM_END) break;
                if (r != JZlib.Z_OK && r != JZlib.Z_BUF_ERROR) throw new IOException("the deflater failed: " + r);
                // (no flush: done once it stopped with room left, all it was given taken)
                if (flush == JZlib.Z_NO_FLUSH && z.getAvailOut() > 0) break;
                if (r == JZlib.Z_BUF_ERROR && n == 0) throw new IOException("the deflater went no further");
            }
            fill = 0;
        }
    }

    /**
     * `packedLen` bytes of `src`, a raw deflate stream, inflated into `dst`: how many bytes it came to. Refused unless the
     * stream ends exactly where those bytes do.
     */
    static long inflate(InputStream src, long packedLen, Sink dst) throws IOException {
        Inflater inf = new Inflater(true);
        try {
            byte[] in = new byte[BUF], out = new byte[BUF];
            long left = packedLen, made = 0;
            boolean dummy = false;
            while (!inf.finished()) {
                if (inf.needsInput()) {
                    if (left > 0) {
                        int k = src.read(in, 0, (int) Math.min(in.length, left));
                        if (k < 0) throw new EOFException("a deflate stream is cut short");
                        left -= k;
                        inf.setInput(in, 0, k);
                    } else if (!dummy) {
                        // (Inflater's nowrap may want a byte past the stream: java.util.zip.Inflater's own advice)
                        dummy = true;
                        inf.setInput(new byte[1], 0, 1);
                    } else {
                        throw new IOException("a deflate stream does not end where it should");
                    }
                }
                int n;
                try {
                    n = inf.inflate(out);
                } catch (DataFormatException e) {
                    throw new IOException("a deflate stream is broken: " + e.getMessage());
                }
                if (n > 0) {
                    dst.write(out, 0, n);
                    made += n;
                } else if (inf.needsDictionary()) {
                    throw new IOException("a deflate stream wants a dictionary");
                }
            }
            if (left > 0 || inf.getRemaining() > (dummy ? 1 : 0)) throw new IOException("a deflate stream ends before its bytes do");
            return made;
        } finally {
            inf.end();
        }
    }

    // ── applying ──────────────────────────────────────────────────────────

    /**
     * The delta made into `out` against `oldApk` (an Android delta: no files, `n_inflate` ranges of the old APK): the
     * old blob built in `tmpDir` (deleted after), bspatch's made bytes written with their `n_deflate` ranges deflated.
     * Anything the format says an applier refuses throws, saying why, and leaves no `out`.
     */
    public static void apply(File oldApk, File delta, File out, File tmpDir) throws IOException {
        File blob = null;
        boolean done = false;
        try (DataInputStream d = new DataInputStream(new BufferedInputStream(new FileInputStream(delta), BUF))) {
            long deltaLen = delta.length();
            byte[] magic = new byte[8];
            readFully(d, magic, "the delta's header is cut short");
            if (!Arrays.equals(magic, MAGIC)) throw new IOException("not a delta (bad magic)");
            long read = 8;
            long nFiles = u32(d);
            read += 4;
            if (nFiles != 0) throw new IOException("a delta of files, not of an APK (n_files " + nFiles + ")");
            long nInflate = u32(d);
            read += 4;
            if (nInflate * 16 > deltaLen - read) throw new IOException("the delta's header is cut short");
            long[] inflate = ranges(d, (int) nInflate, "inflate");
            read += nInflate * 16;
            long oldSize = u64(d);
            byte[] oldSha = new byte[32];
            readFully(d, oldSha, "the delta's header is cut short");
            read += 40;
            long nDeflate = u32(d);
            read += 4;
            if (nDeflate * 16 > deltaLen - read) throw new IOException("the delta's header is cut short");
            long[] deflate = ranges(d, (int) nDeflate, "deflate");
            long madeSize = u64(d);
            if (nDeflate > 0 && deflate[deflate.length - 2] + deflate[deflate.length - 1] > madeSize) {
                throw new IOException("the delta's deflate ranges go past made_size");
            }
            long apkLen = oldApk.length();
            if (nInflate > 0 && inflate[inflate.length - 2] + inflate[inflate.length - 1] > apkLen) {
                throw new IOException("the delta's inflate ranges go past the old APK");
            }

            blob = File.createTempFile("delta-old", ".tmp", tmpDir);
            oldBlob(oldApk, inflate, oldSize, oldSha, blob);

            try (RandomAccessFile old = new RandomAccessFile(blob, "r");
                 RandomAccessFile o = new RandomAccessFile(out, "rw")) {
                o.setLength(0);
                Writer w = new Writer(o);
                DeflatingSink sink = new DeflatingSink(w, deflate);
                patch(new Chunks(d), new OldReader(old, oldSize), madeSize, sink);
                sink.end();
                w.flush();
            }
            done = true;
        } catch (ArithmeticException e) {
            throw new IOException("a record's number is too large");
        } finally {
            if (blob != null) blob.delete();
            if (!done) out.delete();
        }
    }

    /** The old APK with its `inflate` ranges inflated, into `blob`, checked against `size` and `sha` as it is written. */
    private static void oldBlob(File apk, long[] inflate, long size, byte[] sha, File blob) throws IOException {
        MessageDigest md = sha256();
        try (InputStream in = new BufferedInputStream(new FileInputStream(apk), BUF);
             RandomAccessFile f = new RandomAccessFile(blob, "rw")) {
            Writer w = new Writer(f);
            long[] count = {0};
            Sink to = (b, off, len) -> {
                count[0] += len;
                if (count[0] > size) throw new IOException("the old blob is larger than the delta says (not the APK it was made for)");
                md.update(b, off, len);
                w.write(b, off, len);
            };
            long p = 0;
            byte[] buf = new byte[BUF];
            for (int i = 0; i < inflate.length; i += 2) {
                copy(in, inflate[i] - p, to, buf);
                try {
                    inflate(in, inflate[i + 1], to);
                } catch (IOException e) {
                    throw new IOException("the old APK's bytes at " + inflate[i] + " do not inflate (not the APK it was made for): " + e.getMessage());
                }
                p = inflate[i] + inflate[i + 1];
            }
            for (int n; (n = in.read(buf)) > 0; ) to.write(buf, 0, n);
            w.flush();
            if (count[0] != size) throw new IOException("the old blob is not the size the delta says (not the APK it was made for)");
        }
        if (!Arrays.equals(md.digest(), sha)) throw new IOException("the old blob is not the one the delta was made from (sha256)");
    }

    private static void copy(InputStream in, long n, Sink to, byte[] buf) throws IOException {
        while (n > 0) {
            int k = in.read(buf, 0, (int) Math.min(buf.length, n));
            if (k < 0) throw new EOFException("the old APK is shorter than the delta says");
            to.write(buf, 0, k);
            n -= k;
        }
    }

    /** bspatch ("endsley" layout, uncompressed, in chunks): the made bytes, in order, into `sink`. */
    private static void patch(Chunks r, OldReader old, long made, DeflatingSink sink) throws IOException {
        byte[] ctrl = new byte[24], b = new byte[BUF], ob = new byte[BUF];
        long o = 0, p = 0;
        while (o < made) {
            r.read(ctrl, 24);
            long x = le64(ctrl, 0), y = le64(ctrl, 8), z = le64(ctrl, 16);
            // (as the reference applier: beyond ±2^53 refused, what a JavaScript number holds exactly)
            if (Math.abs(x) >= 1L << 53 || Math.abs(y) >= 1L << 53 || z >= 1L << 53 || z < -(1L << 53)) {
                throw new IOException("a record's number is too large");
            }
            if (x < 0 || y < 0)throw new IOException("a record with a negative length");
            if (x > made - o || y > made - o - x) throw new IOException("a record goes past made_size");
            for (long left = x; left > 0; ) {
                int k = (int) Math.min(left, BUF);
                r.read(b, k);
                old.read(p, ob, k);
                for (int i = 0; i < k; i++) b[i] += ob[i];
                sink.write(b, 0, k);
                p = Math.addExact(p, k);
                left -= k;
            }
            for (long left = y; left > 0; ) {
                int k = (int) Math.min(left, BUF);
                r.read(b, k);
                sink.write(b, 0, k);
                left -= k;
            }
            o += x + y;
            p = Math.addExact(p, z);
        }
        r.end();
    }

    /** The bsdiff stream: the delta's chunks inflated one at a time, read across their bounds. */
    private static final class Chunks {
        private final DataInputStream in;
        private final Inflater inf = new Inflater(true);
        private final byte[] raw = new byte[CHUNK + 1];
        private byte[] packed = new byte[BUF];
        private int len, pos;

        Chunks(DataInputStream in) {
            this.in = in;
        }

        void read(byte[] dst, int n) throws IOException {
            for (int got = 0; got < n; ) {
                while (pos == len) if (!next()) throw new IOException("the delta's stream ends early");
                int k = Math.min(n - got, len - pos);
                System.arraycopy(raw, pos, dst, got, k);
                pos += k;
                got += k;
            }
        }

        /** The made bytes are whole: nothing may follow but the end chunk. */
        void end() throws IOException {
            try {
                if (pos != len || next()) throw new IOException("the delta's stream goes on past made_size");
            } finally {
                inf.end();
            }
        }

        private boolean next() throws IOException {
            long rawLen, packedLen;
            try {
                rawLen = u32(in);
                packedLen = u32(in);
            } catch (EOFException e) {
                throw new IOException("the delta has no end chunk");
            }
            if (rawLen == 0) {
                if (packedLen != 0 || in.read() >= 0) throw new IOException("the delta goes on after its end chunk");
                return false;
            }
            if (rawLen > CHUNK) throw new IOException("a chunk of " + rawLen + " bytes, more than " + CHUNK);
            if (packedLen > PACKED_MAX) throw new IOException("a chunk of " + packedLen + " packed bytes, more than a chunk can be");
            if (packed.length < packedLen) packed = new byte[(int) packedLen];
            readFully(in, packed, (int) packedLen, "the delta has no end chunk (a chunk is cut short)");
            inf.reset();
            inf.setInput(packed, 0, (int) packedLen);
            int got = 0;
            try {
                // (room for one more than raw_len: a chunk that inflates to more is seen as such)
                while (!inf.finished() && got < raw.length) {
                    int n = inf.inflate(raw, got, raw.length - got);
                    if (n == 0 && (inf.needsInput() || inf.needsDictionary())) break;
                    got += n;
                }
            } catch (DataFormatException e) {
                throw new IOException("a chunk does not inflate: " + e.getMessage());
            }
            if (!inf.finished() || got != rawLen || inf.getRemaining() != 0) throw new IOException("a chunk does not inflate to its raw_len");
            len = got;
            pos = 0;
            return true;
        }
    }

    /** The old blob read through a buffer (bspatch reads it mostly forward); 0 outside it, as the format says. */
    private static final class OldReader {
        private final RandomAccessFile f;
        private final long size;
        private final byte[] buf = new byte[256 * 1024];
        private long start = -1;
        private int len;

        OldReader(RandomAccessFile f, long size) {
            this.f = f;
            this.size = size;
        }

        void read(long p, byte[] dst, int n) throws IOException {
            int at = 0;
            while (at < n) {
                if (p < 0 || p >= size) {
                    int k = p < 0 ? (int) Math.min(n - at, -p) : n - at;
                    Arrays.fill(dst, at, at + k, (byte) 0);
                    at += k;
                    p += k;
                    continue;
                }
                if (start < 0 || p < start || p >= start + len) {
                    start = p;
                    len = (int) Math.min(buf.length, size - p);
                    f.seek(p);
                    f.readFully(buf, 0, len);
                }
                int k = (int) Math.min(n - at, start + len - p);
                System.arraycopy(buf, (int) (p - start), dst, at, k);
                at += k;
                p += k;
            }
        }
    }

    /** What bspatch makes, written with the `n_deflate` ranges deflated (each by a deflater of its own). */
    private static final class DeflatingSink {
        private final Writer out;
        private final long[] ranges;
        private int k;
        private long o;
        private Deflating range;

        DeflatingSink(Writer out, long[] ranges) {
            this.out = out;
            this.ranges = ranges;
        }

        void write(byte[] b, int off, int len) throws IOException {
            startEmpty();
            while (len > 0) {
                if (k * 2 >= ranges.length || o < ranges[k * 2]) {
                    int n = k * 2 >= ranges.length ? len : (int) Math.min(len, ranges[k * 2] - o);
                    out.write(b, off, n);
                    off += n;
                    len -= n;
                    o += n;
                } else {
                    long end = ranges[k * 2] + ranges[k * 2 + 1];
                    if (range == null) range = new Deflating(out::write);
                    int n = (int) Math.min(len, end - o);
                    range.write(b, off, n);
                    off += n;
                    len -= n;
                    o += n;
                    if (o == end) {
                        range.finish();
                        range = null;
                        k++;
                    }
                }
                startEmpty();
            }
        }

        /** Ranges of no bytes where the made bytes are now (an empty entry's): deflated, nothing taken. */
        private void startEmpty() throws IOException {
            while (range == null && k * 2 < ranges.length && ranges[k * 2] == o && ranges[k * 2 + 1] == 0) {
                new Deflating(out::write).finish();
                k++;
            }
        }

        void end() throws IOException {
            startEmpty();
            if (range != null || k * 2 != ranges.length) throw new IOException("the made bytes end inside a deflate range");
        }
    }

    /** A file written through a buffer, its position known, bytes behind it written again (repack's headers). */
    private static final class Writer {
        private final RandomAccessFile f;
        private final byte[] buf = new byte[BUF];
        private int fill;
        private long flushed;

        Writer(RandomAccessFile f) throws IOException {
            this.f = f;
            this.flushed = f.getFilePointer();
        }

        long pos() {
            return flushed + fill;
        }

        void write(byte[] b, int off, int len) throws IOException {
            if (len >= buf.length) {
                flush();
                f.write(b, off, len);
                flushed += len;
                return;
            }
            if (fill + len > buf.length) flush();
            System.arraycopy(b, off, buf, fill, len);
            fill += len;
        }

        void flush() throws IOException {
            if (fill > 0) {
                f.write(buf, 0, fill);
                flushed += fill;
                fill = 0;
            }
        }

        void patch(long at, byte[] b) throws IOException {
            flush();
            f.seek(at);
            f.write(b);
            f.seek(flushed);
        }
    }

    // ── repacking ─────────────────────────────────────────────────────────

    /**
     * `in` (a zip) written again to `out` with every deflated entry's data deflated anew by this class's deflater (its
     * inflated bytes unchanged); order, names, extra fields, comments, stored entries, times and attributes kept; sizes
     * and offsets put right in the local headers, the data descriptors and the central directory. An APK signing block
     * (a signed APK's, before its central directory) is left out: it signs bytes that are no longer there. No zip64.
     */
    public static void repack(File in, File out) throws IOException {
        boolean done = false;
        try (RandomAccessFile src = new RandomAccessFile(in, "r"); RandomAccessFile dst = new RandomAccessFile(out, "rw")) {
            dst.setLength(0);
            long len = src.length();
            int tail = (int) Math.min(len, 22 + 0xffff);
            byte[] t = new byte[tail];
            src.seek(len - tail);
            src.readFully(t);
            int e = -1;
            for (int i = tail - 22; i >= 0; i--) {
                if (le32(t, i) == 0x06054b50L && i + 22 + le16(t, i + 20) == tail) {
                    e = i;
                    break;
                }
            }
            if (e < 0) throw new IOException("not a zip (no end of central directory)");
            long eocd = len - tail + e;
            if (le16(t, e + 4) != 0 || le16(t, e + 6) != 0) throw new IOException("a zip of several disks");
            int count = le16(t, e + 10);
            long cdSize = le32(t, e + 12), cdOff = le32(t, e + 16);
            if (count == 0xffff || cdSize == 0xffffffffL || cdOff == 0xffffffffL) throw new IOException("a zip64 zip (not taken)");
            if (eocd >= 20) {
                byte[] loc = new byte[4];
                src.seek(eocd - 20);
                src.readFully(loc);
                if (le32(loc, 0) == 0x07064b50L) throw new IOException("a zip64 zip (not taken)");
            }
            if (le16(t, e + 8) != count) throw new IOException("a zip of several disks");
            if (cdOff + cdSize > eocd) throw new IOException("the zip's central directory is broken");
            byte[] cd = new byte[(int) cdSize];
            src.seek(cdOff);
            src.readFully(cd);

            List<long[]> entries = new ArrayList<>(); // {cd position, local offset}
            for (int p = 0, i = 0; i < count; i++) {
                if (p + 46 > cd.length || le32(cd, p) != 0x02014b50L) throw new IOException("the zip's central directory is broken");
                long csize = le32(cd, p + 20), usize = le32(cd, p + 24), local = le32(cd, p + 42);
                if (csize == 0xffffffffL || usize == 0xffffffffL || local == 0xffffffffL || le16(cd, p + 34) == 0xffff) {
                    throw new IOException("a zip64 entry (not taken)");
                }
                entries.add(new long[]{p, local});
                p += 46 + le16(cd, p + 28) + le16(cd, p + 30) + le16(cd, p + 32);
                if (p > cd.length) throw new IOException("the zip's central directory is broken");
            }
            List<long[]> byPlace = new ArrayList<>(entries);
            byPlace.sort((a, b) -> Long.compare(a[1], b[1]));

            Writer w = new Writer(dst);
            long[] moved = new long[cd.length]; // cd position → its local header's new offset
            long[] packedNew = new long[cd.length];
            long at = 0;
            byte[] buf = new byte[BUF];
            for (long[] en : byPlace) {
                int c = (int) en[0];
                long local = en[1];
                if (local < at) throw new IOException("the zip's entries overlap");
                copyRange(src, at, local - at, w, buf);
                byte[] lh = new byte[30];
                src.seek(local);
                src.readFully(lh);
                if (le32(lh, 0) != 0x04034b50L) throw new IOException("a zip entry's local header is missing");
                int flags = le16(lh, 6), method = le16(cd, c + 10);
                if (le16(lh, 8) != method) throw new IOException("a zip entry's local header says another method");
                long crc = le32(cd, c + 16), csize = le32(cd, c + 20), usize = le32(cd, c + 24);
                int nameExtra = le16(lh, 26) + le16(lh, 28);
                long dataAt = local + 30 + nameExtra;
                if (dataAt + csize > cdOff) throw new IOException("a zip entry's data goes past its end");
                long newLocal = w.pos();
                moved[c] = newLocal;
                w.write(lh, 0, 30);
                copyRange(src, local + 30, nameExtra, w, buf);
                long newPacked;
                if (method == 0) {
                    copyRange(src, dataAt, csize, w, buf);
                    newPacked = csize;
                } else if (method == 8) {
                    newPacked = redeflate(src, dataAt, csize, usize, crc, w);
                    w.flush();
                    check(dst, newLocal + 30 + nameExtra, newPacked, usize, crc);
                } else {
                    throw new IOException("a zip entry of method " + method + " (only stored and deflated are taken)");
                }
                packedNew[c] = newPacked;
                at = dataAt + csize;
                if ((flags & 8) != 0) {
                    byte[] dd = new byte[16];
                    src.seek(at);
                    int k = Math.min(16, (int) (cdOff - at));
                    src.readFully(dd, 0, k);
                    boolean sig = k >= 4 && le32(dd, 0) == 0x08074b50L;
                    int ddLen = sig ? 16 : 12;
                    if (k < ddLen) throw new IOException("a zip entry's data descriptor is cut short");
                    put32(dd, sig ? 8 : 4, newPacked);
                    w.write(dd, 0, ddLen);
                    at += ddLen;
                }
                // (the local header's sizes: put right, but left 0 where a data descriptor carries them)
                if (le32(lh, 18) != 0 || (flags & 8) == 0) {
                    byte[] four = new byte[4];
                    put32(four, 0, newPacked);
                    w.patch(newLocal + 18, four);
                }
            }
            if (at > cdOff) throw new IOException("the zip's entries overlap its central directory");
            long gap = cdOff - at;
            if (!signingBlock(src, at, gap)) copyRange(src, at, gap, w, buf);
            long newCd = w.pos();
            for (long[] en : entries) {
                int c = (int) en[0];
                put32(cd, c + 20, packedNew[c]);
                if (moved[c] > 0xfffffffeL) throw new IOException("the zip comes to more than zip64-free offsets reach");
                put32(cd, c + 42, moved[c]);
            }
            w.write(cd, 0, cd.length);
            copyRange(src, cdOff + cdSize, eocd - cdOff - cdSize, w, buf);
            if (newCd > 0xfffffffeL) throw new IOException("the zip comes to more than zip64-free offsets reach");
            put32(t, e + 16, newCd);
            w.write(t, e, tail - e);
            w.flush();
            done = true;
        } finally {
            if (!done) out.delete();
        }
    }

    /** An entry's deflated data inflated and deflated again into `w`, checked against its size and CRC; its new size. */
    private static long redeflate(RandomAccessFile src, long at, long csize, long usize, long crc, Writer w) throws IOException {
        CRC32 sum = new CRC32();
        Deflating d = new Deflating(w::write);
        long raw = inflate(slice(src, at, csize), csize, (b, off, len) -> {
            sum.update(b, off, len);
            d.write(b, off, len);
        });
        long packed = d.finish();
        if (raw != usize || sum.getValue() != crc) throw new IOException("a zip entry's data is not its size or CRC");
        return packed;
    }

    /** What was written at `at` inflated again: the same size and CRC (JZlib's output trusted only once read back). */
    private static void check(RandomAccessFile f, long at, long packed, long usize, long crc) throws IOException {
        CRC32 sum = new CRC32();
        long end = f.getFilePointer();
        long raw = inflate(slice(f, at, packed), packed, (b, off, len) -> sum.update(b, off, len));
        f.seek(end);
        if (raw != usize || sum.getValue() != crc) throw new IOException("the deflater's output does not inflate to the entry");
    }

    /** Whether `n` bytes at `at` are an APK signing block ("APK Sig Block 42" ending them). */
    private static boolean signingBlock(RandomAccessFile f, long at, long n) throws IOException {
        if (n < 32) return false;
        byte[] b = new byte[16];
        f.seek(at + n - 16);
        f.readFully(b);
        return Arrays.equals(b, "APK Sig Block 42".getBytes(StandardCharsets.US_ASCII));
    }

    private static void copyRange(RandomAccessFile f, long at, long n, Writer w, byte[] buf) throws IOException {
        f.seek(at);
        while (n > 0) {
            int k = (int) Math.min(buf.length, n);
            f.readFully(buf, 0, k);
            w.write(buf, 0, k);
            n -= k;
        }
    }

    /** `n` bytes of `f` from `at`, as a stream (seeking for each read: the file is read elsewhere between them). */
    private static InputStream slice(RandomAccessFile f, long at, long n) {
        return new InputStream() {
            long p = at, left = n;

            @Override
            public int read() throws IOException {
                byte[] one = new byte[1];
                return read(one, 0, 1) < 0 ? -1 : one[0] & 0xff;
            }

            @Override
            public int read(byte[] b, int off, int len) throws IOException {
                if (left == 0) return -1;
                int k = (int) Math.min(len, left);
                f.seek(p);
                f.readFully(b, off, k);
                p += k;
                left -= k;
                return k;
            }
        };
    }

    // ── bytes ─────────────────────────────────────────────────────────────

    private static long[] ranges(DataInputStream d, int n, String what) throws IOException {
        long[] r = new long[n * 2];
        long end = 0;
        for (int i = 0; i < n; i++) {
            long at = u64(d), len = u64(d);
            if (at < end) throw new IOException("the delta's " + what + " ranges are not ascending");
            end = Math.addExact(at, len);
            r[i * 2] = at;
            r[i * 2 + 1] = len;
        }
        return r;
    }

    private static void readFully(DataInputStream d, byte[] b, String why) throws IOException {
        readFully(d, b, b.length, why);
    }

    private static void readFully(DataInputStream d, byte[] b, int n, String why) throws IOException {
        try {
            d.readFully(b, 0, n);
        } catch (EOFException e) {
            throw new IOException(why);
        }
    }

    private static long u32(DataInputStream d) throws IOException {
        byte[] b = new byte[4];
        d.readFully(b);
        return le32(b, 0);
    }

    private static long u64(DataInputStream d) throws IOException {
        byte[] b = new byte[8];
        try {
            d.readFully(b);
        } catch (EOFException e) {
            throw new IOException("the delta's header is cut short");
        }
        long v = le64(b, 0);
        if (v < 0 || v >= (1L << 53)) throw new IOException("the delta's header has a number too large");
        return v;
    }

    static int le16(byte[] b, int at) {
        return (b[at] & 0xff) | (b[at + 1] & 0xff) << 8;
    }

    static long le32(byte[] b, int at) {
        return (le16(b, at) | (long) le16(b, at + 2) << 16) & 0xffffffffL;
    }

    static long le64(byte[] b, int at) {
        return le32(b, at) | le32(b, at + 4) << 32;
    }

    static void put32(byte[] b, int at, long v) {
        for (int i = 0; i < 4; i++) b[at + i] = (byte) (v >>> (8 * i));
    }

    private static MessageDigest sha256() throws IOException {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IOException(e);
        }
    }

    /**
     * For the build and release scripts (on the build machine's JVM: the same deflater as the app's):
     *   java -cp CLASSES dev.mbui.Delta apply OLD_APK DELTA OUT     (the old blob's temporary file beside OUT)
     *   java -cp CLASSES dev.mbui.Delta repack IN OUT
     * Failing: exit 1, why on stderr, no OUT.
     */
    public static void main(String[] args) {
        try {
            if (args.length == 4 && args[0].equals("apply")) {
                File out = new File(args[3]).getAbsoluteFile();
                apply(new File(args[1]), new File(args[2]), out, out.getParentFile());
            } else if (args.length == 3 && args[0].equals("repack")) {
                repack(new File(args[1]), new File(args[2]));
            } else {
                System.err.println("usage: dev.mbui.Delta apply OLD_APK DELTA OUT | repack IN OUT");
                System.exit(2);
            }
        } catch (IOException | RuntimeException e) {
            System.err.println("delta: " + (e.getMessage() == null ? e.toString() : e.getMessage()));
            System.exit(1);
        }
    }
}
