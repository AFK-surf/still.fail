package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.SurfaceTexture;
import android.media.MediaCodec;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.opengl.GLES11Ext;
import android.opengl.GLES30;
import android.opengl.GLUtils;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.view.Surface;

import java.nio.ByteBuffer;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Streams (src/host/stream.mbt, @ui's Stream): a picture decoded frame by frame, drawn by the app as an image. As
 * still.fail's Android app decodes a remote screen (its remote/Decoders.kt), with what is shown said by the app:
 *
 * <p>H.264 by MediaCodec (asynchronous, its callbacks on a thread of the stream's own) onto a SurfaceTexture of the
 * app's GL context. A decoded frame waits in its output buffer; one at a time is released onto the SurfaceTexture, and
 * once it is there ("frame available") the app is told ("f TS W H"). The app shows it (`show`, on the GL thread, as its
 * frame takes the event): latched (updateTexImage) and drawn into a plain texture of the frame's size, what the
 * renderer draws the stream with (android_host.c), then the next decoded frame released. So the picture drawn is the
 * one the app took, never one that came after.
 *
 * <p>JPEG by BitmapFactory on a thread of its own, each bitmap kept until the app shows it (uploaded into the same
 * texture) or a later one is shown.
 *
 * <p>Frames let go ("d TS": the decoder not there or not past a key frame, one it cannot take, the older of two it
 * holds back, those inside it as it starts anew, a JPEG that does not decode) and the decoder broken ("b": an error, a
 * new SurfaceTexture after the GL context was lost) are told the same way. Each event asks for a frame.
 *
 * <p>Called from the C host (android_host.c mb_host_stream_*) on the GL thread, but for the decoders' own threads.
 */
final class Streams {
    // ---- android_host.c: the conversion of src/host/avc.h, and the texture a stream is drawn with ----

    /** An avcC's NAL length size, -1 when it is not one. */
    static native int avcLengthSize(byte[] avcc);
    /** Its parameter sets of a kind (0 SPS, 1 PPS), each after a start code (csd-0, csd-1); null when it is not one. */
    static native byte[] avcCsd(byte[] avcc, int kind);
    /** An AVCC access unit in Annex B; null when it is not a sound one. */
    static native byte[] annexB(byte[] frame, int lengthSize);
    /** The texture stream `id` is drawn with now (0: none). */
    static native void texture(int id, int tex);

    private static final HashMap<Integer, Stream> streams = new HashMap<>();
    /** SurfaceTextures whose decoder has stopped, let go of on the GL thread (their context's) as it next calls here. */
    private static final ConcurrentLinkedQueue<SurfaceTexture> stopped = new ConcurrentLinkedQueue<>();

    /** A SurfaceTexture and its Surface done with (the decoder's thread, once the decoder on it stopped). */
    static void letGo(SurfaceTexture t, Surface s) {
        if (t == null) return;
        s.release();
        stopped.add(t);
        Host.requestFrame();
    }

    private static void dropSurfaces() {
        for (SurfaceTexture t; (t = stopped.poll()) != null; ) t.release();
    }
    private static int nextId;

    /** Whether there is an H.264 decoder here at all (else the app asks for JPEG only). */
    static boolean h264Here() {
        if (h264Known == 0) {
            boolean any = false;
            try {
                for (android.media.MediaCodecInfo info : new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()) {
                    if (info.isEncoder()) continue;
                    for (String t : info.getSupportedTypes()) {
                        if (t.equalsIgnoreCase(MediaFormat.MIMETYPE_VIDEO_AVC)) any = true;
                    }
                }
            } catch (Exception e) {
                any = false;
            }
            h264Known = any ? 1 : -1;
        }
        return h264Known > 0;
    }

    private static int h264Known;

    static int open() {
        dropSurfaces();
        int id = ++nextId;
        streams.put(id, new Stream(id));
        return id;
    }

    static void h264(int id, byte[] avcc, int w, int h) {
        Stream s = streams.get(id);
        if (s != null) s.configure(avcc, w, h);
    }

    static void frame(int id, byte[] data, boolean key, double ts) {
        Stream s = streams.get(id);
        if (s == null) return;
        if (s.video == null) s.say("d " + num(ts));
        else s.video.frame(data, key, ts);
    }

    static void jpeg(int id, byte[] data, double ts) {
        Stream s = streams.get(id);
        if (s != null) s.jpeg(data, ts);
    }

    static String next(int id) {
        dropSurfaces();
        Stream s = streams.get(id);
        if (s == null) return "";
        synchronized (s.events) {
            String e = s.events.poll();
            return e == null ? "" : e;
        }
    }

    // MBUI_STREAM_THROW_SHOW=N (a test's, android-streams.sh thrown): the Nth show() throws, for the host to clear
    private static final String throwShow = System.getenv("MBUI_STREAM_THROW_SHOW");
    private static int shows;

    static void show(int id, double ts) {
        dropSurfaces();
        Stream s = streams.get(id);
        if (s != null) s.show(ts);
        if (throwShow != null && throwShow.equals(String.valueOf(++shows))) throw new RuntimeException("MBUI_STREAM_THROW_SHOW: show " + shows);
    }

    static void close(int id) {
        Stream s = streams.remove(id);
        if (s != null) s.close();
    }

    /** The GL context was lost (android_host.c images_lost): every stream's textures made anew in the new one. */
    static void lost() {
        blit = 0;
        // MBUI_STREAM_HOLD_DECODER=MS (a test's, android-streams.sh anew): each decoder's thread held that long first,
        // as on a CPU it does not get, so the GL thread's frames after the new context come before anything the
        // decoder does about it
        int hold = 0;
        try { hold = Integer.parseInt(System.getenv("MBUI_STREAM_HOLD_DECODER")); } catch (Exception e) {}
        for (Stream s : streams.values()) {
            if (hold > 0 && s.video != null) s.video.hold(hold);
            s.lost();
        }
    }

    /** A time as the app's events say it: a whole number without a fraction. */
    static String num(double v) {
        return v == Math.rint(v) && Math.abs(v) < 1e15 ? Long.toString((long) v) : Double.toString(v);
    }

    // ---- the copy of a SurfaceTexture's frame into a plain texture (GL thread) ----

    private static int blit, blitMatrix, blitFb;

    private static int shader(int type, String src) {
        int s = GLES30.glCreateShader(type);
        GLES30.glShaderSource(s, src);
        GLES30.glCompileShader(s);
        int[] ok = {0};
        GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0);
        if (ok[0] == 0) Host.log("stream: shader: " + GLES30.glGetShaderInfoLog(s));
        return s;
    }

    private static void blitProgram() {
        if (blit != 0) return;
        // a triangle over the whole target; the frame's top in the texture's first row, as a bitmap's upload has it
        String vs = "#version 300 es\n"
                + "uniform mat4 u_m;\n"
                + "out vec2 v_uv;\n"
                + "void main() {\n"
                + "  vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);\n"
                + "  v_uv = (u_m * vec4(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5, 0.0, 1.0)).xy;\n"
                + "  gl_Position = vec4(p, 0.0, 1.0);\n"
                + "}\n";
        String fs = "#version 300 es\n"
                + "#extension GL_OES_EGL_image_external_essl3 : require\n"
                + "precision mediump float;\n"
                + "uniform samplerExternalOES u_t;\n"
                + "in vec2 v_uv;\n"
                + "out vec4 o;\n"
                + "void main() { o = vec4(texture(u_t, v_uv).rgb, 1.0); }\n";
        int p = GLES30.glCreateProgram();
        GLES30.glAttachShader(p, shader(GLES30.GL_VERTEX_SHADER, vs));
        GLES30.glAttachShader(p, shader(GLES30.GL_FRAGMENT_SHADER, fs));
        GLES30.glLinkProgram(p);
        int[] ok = {0};
        GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0);
        if (ok[0] == 0) Host.log("stream: program: " + GLES30.glGetProgramInfoLog(p));
        blit = p;
        blitMatrix = GLES30.glGetUniformLocation(p, "u_m");
        GLES30.glUseProgram(p);
        GLES30.glUniform1i(GLES30.glGetUniformLocation(p, "u_t"), 3);
        int[] fb = {0};
        GLES30.glGenFramebuffers(1, fb, 0);
        blitFb = fb[0];
    }

    /** A plain texture `w` × `h` (made, or made anew at another size): its name. */
    private static int target(Stream s, int w, int h) {
        if (s.tex != 0 && s.texW == w && s.texH == h) return s.tex;
        if (s.tex == 0) {
            int[] t = {0};
            GLES30.glGenTextures(1, t, 0);
            s.tex = t[0];
        }
        GLES30.glActiveTexture(GLES30.GL_TEXTURE1);
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, s.tex);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, w, h, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null);
        s.texW = w;
        s.texH = h;
        texture(s.id, s.tex);
        return s.tex;
    }

    // ---- a stream ----

    static final class Stream {
        final int id;
        /** What it says, oldest first, taken by the app as a frame begins. */
        final ArrayDeque<String> events = new ArrayDeque<>();
        /** The plain texture it is drawn with, and its size (GL thread). */
        int tex, texW, texH;
        /** Its SurfaceTexture, the external texture under it, its Surface (GL thread; the decoder has the surface). */
        SurfaceTexture st;
        int ext;
        Surface surface;
        H264 video;
        Jpeg jpeg;
        /** The JPEG frame shown last, kept to upload again into a new context. */
        Bitmap shownBitmap;

        Stream(int id) {
            this.id = id;
        }

        void say(String e) {
            synchronized (events) {
                events.add(e);
            }
            Host.requestFrame();
        }

        void configure(byte[] avcc, int w, int h) {
            if (video == null) {
                video = new H264(this);
                surfaceAnew();
            }
            video.configure(avcc, w, h);
        }

        /** A SurfaceTexture on a new external texture of the context there is, handed to the decoder (GL thread). */
        void surfaceAnew() {
            SurfaceTexture oldSt = st;
            Surface oldSurface = surface;
            int[] t = {0};
            GLES30.glGenTextures(1, t, 0);
            ext = t[0];
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ext);
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
            GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
            st = new SurfaceTexture(ext);
            surface = new Surface(st);
            // the old one let go once the decoder drawing on it has stopped (on its thread)
            video.surface(st, surface, oldSt, oldSurface);
        }

        void jpeg(byte[] data, double ts) {
            if (jpeg == null) jpeg = new Jpeg(this);
            jpeg.frame(data, ts);
        }

        /** Frame `ts` (its "f" taken) drawn into the texture: a JPEG's bitmap uploaded, or the decoder's frame latched. */
        void show(double ts) {
            if (jpeg != null) {
                Bitmap b = jpeg.take(ts);
                if (b != null) {
                    upload(b);
                    if (shownBitmap != null) jpeg.reuse(shownBitmap);
                    shownBitmap = b;
                    return;
                }
            }
            if (video != null && st != null) video.latch(ts);
        }

        void upload(Bitmap b) {
            int w = b.getWidth(), h = b.getHeight();
            boolean anew = tex == 0 || texW != w || texH != h;
            if (anew) target(this, w, h);
            GLES30.glActiveTexture(GLES30.GL_TEXTURE1);
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, tex);
            // (a JPEG is opaque: premultiplied or not, the same)
            GLUtils.texSubImage2D(GLES30.GL_TEXTURE_2D, 0, 0, 0, b);
        }

        /** The SurfaceTexture's frame, latched, drawn into the plain texture (GL thread). */
        void copy(int w, int h) {
            blitProgram();
            int t = target(this, w, h);
            float[] m = new float[16];
            st.getTransformMatrix(m);
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, blitFb);
            GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, t, 0);
            GLES30.glViewport(0, 0, w, h);
            GLES30.glDisable(GLES30.GL_BLEND);
            GLES30.glUseProgram(blit);
            GLES30.glUniformMatrix4fv(blitMatrix, 1, false, m, 0);
            GLES30.glActiveTexture(GLES30.GL_TEXTURE3);
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ext);
            GLES30.glBindVertexArray(0);
            GLES30.glDrawArrays(GLES30.GL_TRIANGLES, 0, 3);
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, 0);
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0);
            GLES30.glEnable(GLES30.GL_BLEND);
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0);
        }

        /** A new GL context (GL thread): the textures of the old gone with it. A JPEG shown is uploaded again; the
         * decoder goes onto a new SurfaceTexture, from a key frame (broken: the app asks for one). */
        void lost() {
            tex = 0;
            texW = texH = 0;
            texture(id, 0);
            if (shownBitmap != null) upload(shownBitmap);
            if (video != null) surfaceAnew();
        }

        void close() {
            // the SurfaceTexture let go once the decoder drawing on it has stopped (on its thread)
            if (video != null) video.release(st, surface);
            else if (st != null) {
                st.release();
                surface.release();
            }
            if (jpeg != null) jpeg.release();
            st = null;
            surface = null;
            int[] t = {tex, ext};
            GLES30.glDeleteTextures(2, t, 0);
            texture(id, 0);
            shownBitmap = null;
        }
    }

    // ---- H.264 ----

    /** Decoders.kt's H264Decoder, its frames told to the app as they reach the SurfaceTexture (one at a time). */
    static final class H264 {
        private static final class Frame {
            final byte[] data;
            final boolean key;
            final double ts;

            Frame(byte[] data, boolean key, double ts) {
                this.data = data;
                this.key = key;
                this.ts = ts;
            }
        }

        private static final class Out {
            final int index;
            final double ts;

            Out(int index, double ts) {
                this.index = index;
                this.ts = ts;
            }
        }

        private final Stream stream;
        private final HandlerThread thread;
        private final Handler handler;
        private MediaCodec codec;
        private Surface surface;
        private byte[] avcc;
        private int lengthSize;
        private int width, height;
        /** The decoded picture's size, as its output format says (its crop). */
        private int outW, outH;
        /** Frames waiting for an input buffer, and the free input buffers. */
        private final ArrayDeque<Frame> waiting = new ArrayDeque<>();
        private final ArrayDeque<Integer> inputs = new ArrayDeque<>();
        /** Frames in the decoder, not out yet (their times, in order). */
        private final ArrayDeque<Double> inside = new ArrayDeque<>();
        /** Frames decoded, in their output buffers, not released onto the SurfaceTexture yet. */
        private final ArrayDeque<Out> held = new ArrayDeque<>();
        /** Until a key frame comes, frames are let go (a decoder started anew, or broken). */
        private boolean needKey = true;
        private boolean released;

        // The frame on the SurfaceTexture (one at a time), under `slot`: released onto it (busy, its time), arrived
        // (ready: the app told), how many frames arrived that were not latched yet.
        private final Object slot = new Object();
        private boolean slotBusy, slotReady;
        private double slotTs;
        private int available;
        /** Set on the GL thread (which latches from it), read on the decoder's (whose frames arrive on it). */
        private volatile SurfaceTexture st;

        H264(Stream stream) {
            this.stream = stream;
            thread = new HandlerThread("mbui-h264-" + stream.id);
            thread.start();
            handler = new Handler(thread.getLooper());
        }

        /** The SurfaceTexture it draws on (made on the GL thread), new: a decoder on it starts anew, from a key frame. */
        void surface(SurfaceTexture t, Surface s, SurfaceTexture oldT, Surface oldS) {
            t.setOnFrameAvailableListener(this::arrived, handler);
            // the GL thread latches from it from now on (the old one's frames arriving after are not counted)
            synchronized (slot) {
                st = t;
                available = 0;
                // a frame told and not shown yet was on the old one: let go with it (its "f" still comes)
                if (slotReady) slotBusy = slotReady = false;
            }
            handler.post(() -> {
                surface = s;
                if (start()) stream.say("b");
                letGo(oldT, oldS);
            });
        }

        /** Its thread held `ms` from now (a test's: MBUI_STREAM_HOLD_DECODER). */
        void hold(int ms) {
            synchronized (slot) {
                Host.log("stream " + stream.id + ": decoder held " + ms + " ms, a frame told and not shown: " + slotReady);
            }
            handler.post(() -> android.os.SystemClock.sleep(ms));
        }

        void configure(byte[] avcc, int w, int h) {
            handler.post(() -> {
                int n = avcLengthSize(avcc);
                if (n < 0) {
                    Host.log("stream " + stream.id + ": an avcC that is not one (" + avcc.length + " bytes)");
                    this.avcc = null;
                    stop();
                    return;
                }
                this.avcc = avcc;
                lengthSize = n;
                width = w;
                height = h;
                outW = w;
                outH = h;
                // the sender's next frame after a config is a key frame
                start();
            });
        }

        void frame(byte[] data, boolean key, double ts) {
            handler.post(() -> {
                if (codec == null || (needKey && !key)) {
                    stream.say("d " + num(ts));
                    return;
                }
                needKey = false;
                waiting.add(new Frame(data, key, ts));
                feed();
            });
        }

        void release(SurfaceTexture t, Surface s) {
            handler.post(() -> {
                released = true;
                stop();
                letGo(t, s);
                thread.quitSafely();
            });
        }

        /** A decoder for the config and surface there are (none without either): whether there is one now. */
        private boolean start() {
            stop();
            if (avcc == null || surface == null || released) return false;
            try {
                MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, Math.max(width, 16), Math.max(height, 16));
                format.setByteBuffer("csd-0", ByteBuffer.wrap(avcCsd(avcc, 0)));
                format.setByteBuffer("csd-1", ByteBuffer.wrap(avcCsd(avcc, 1)));
                // a key frame of a whole screen can be large; the decoder's own guess for the size is often too small
                format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, Math.max(width * height, 1 << 20));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1);
                format.setInteger(MediaFormat.KEY_PRIORITY, 0);
                MediaCodec made = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
                made.setCallback(callback, handler);
                made.configure(format, surface, null, 0);
                made.start();
                codec = made;
                needKey = true;
                return true;
            } catch (Exception e) {
                Host.log("stream " + stream.id + ": no H.264 decoder: " + e);
                stop();
                return false;
            }
        }

        private void stop() {
            if (codec != null) {
                try {
                    codec.stop();
                } catch (Exception ignored) {
                }
                try {
                    codec.release();
                } catch (Exception ignored) {
                }
            }
            codec = null;
            inputs.clear();
            // what was waiting, inside, decoded and not on the SurfaceTexture, or released onto it and not arrived, is let
            // go: taken, as far as the sender is concerned
            double max = Double.NEGATIVE_INFINITY;
            for (Frame f : waiting) max = Math.max(max, f.ts);
            for (double t : inside) max = Math.max(max, t);
            for (Out o : held) max = Math.max(max, o.ts);
            synchronized (slot) {
                if (slotBusy && !slotReady) {
                    max = Math.max(max, slotTs);
                    slotBusy = false;
                }
            }
            if (max != Double.NEGATIVE_INFINITY) stream.say("d " + num(max));
            waiting.clear();
            inside.clear();
            held.clear();
            needKey = true;
        }

        private void feed() {
            MediaCodec c = codec;
            if (c == null) return;
            while (!inputs.isEmpty() && !waiting.isEmpty()) {
                int index = inputs.poll();
                Frame f = waiting.poll();
                ByteBuffer buffer = c.getInputBuffer(index);
                if (buffer == null) continue;
                buffer.clear();
                byte[] b = annexB(f.data, lengthSize);
                if (b == null || buffer.remaining() < b.length) {
                    // not a frame it can take: given back empty, the next key frame asked for
                    c.queueInputBuffer(index, 0, 0, (long) f.ts, 0);
                    stream.say("d " + num(f.ts));
                    needKey = true;
                    stream.say("b");
                    continue;
                }
                buffer.put(b);
                c.queueInputBuffer(index, 0, b.length, (long) f.ts, f.key ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0);
                inside.add(f.ts);
                // a decoder that holds frames back (some keep one or two before the first comes out) would wait for more
                // while the sender waits for an acknowledgement: with two inside, the older one counts as taken
                if (inside.size() >= 2) stream.say("d " + num(inside.poll()));
            }
        }

        /** The next decoded frame onto the SurfaceTexture, when none is there. */
        private void pump() {
            MediaCodec c = codec;
            if (c == null) return;
            synchronized (slot) {
                if (slotBusy || held.isEmpty()) return;
                Out o = held.poll();
                try {
                    c.releaseOutputBuffer(o.index, true);
                } catch (Exception e) {
                    stream.say("d " + num(o.ts));
                    return;
                }
                slotBusy = true;
                slotReady = false;
                slotTs = o.ts;
            }
        }

        /** A frame reached the SurfaceTexture (the decoder's thread): the app told, if it is the one released. */
        private void arrived(SurfaceTexture t) {
            String said = null;
            synchronized (slot) {
                if (t != st) return;
                available++;
                if (slotBusy && !slotReady) {
                    slotReady = true;
                    said = "f " + num(slotTs) + " " + outW + " " + outH;
                }
            }
            if (said != null) stream.say(said);
        }

        /** Frame `ts` (its "f" taken) latched and copied (GL thread); then the next one released. */
        void latch(double ts) {
            SurfaceTexture t = st;
            int w = outW, h = outH;
            boolean got = false;
            synchronized (slot) {
                if (!slotReady || slotTs != ts || t == null) return;
                // the one released: past any that arrived from a decoder before (its timestamp, ns, the frame's time)
                long want = (long) ts * 1000L;
                while (available > 0) {
                    try {
                        t.updateTexImage();
                    } catch (RuntimeException e) {
                        // (let go since it was told: the picture stays as it was)
                        Host.log("stream " + stream.id + ": updateTexImage: " + e);
                        available = 0;
                        got = false;
                        break;
                    }
                    available--;
                    got = true;
                    if (t.getTimestamp() == want) break;
                }
                slotBusy = false;
                slotReady = false;
            }
            // (none there: the SurfaceTexture made anew since, its frame gone with the old; the picture stays as it was)
            if (got) stream.copy(w > 0 ? w : 16, h > 0 ? h : 16);
            handler.post(this::pump);
        }

        private final MediaCodec.Callback callback = new MediaCodec.Callback() {
            @Override
            public void onInputBufferAvailable(MediaCodec c, int index) {
                if (c != codec) return;
                inputs.add(index);
                feed();
            }

            @Override
            public void onOutputBufferAvailable(MediaCodec c, int index, MediaCodec.BufferInfo info) {
                if (c != codec) return;
                boolean config = (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
                if (config || info.size <= 0) {
                    try {
                        c.releaseOutputBuffer(index, false);
                    } catch (Exception ignored) {
                    }
                    return;
                }
                double ts = info.presentationTimeUs;
                while (!inside.isEmpty() && inside.peek() <= ts) inside.poll();
                held.add(new Out(index, ts));
                pump();
            }

            @Override
            public void onError(MediaCodec c, MediaCodec.CodecException e) {
                if (c != codec) return;
                Host.log("stream " + stream.id + ": the H.264 decoder failed: " + e);
                // anew, from the next key frame
                if (start()) stream.say("b");
            }

            @Override
            public void onOutputFormatChanged(MediaCodec c, MediaFormat f) {
                if (c != codec) return;
                int w = f.getInteger(MediaFormat.KEY_WIDTH), h = f.getInteger(MediaFormat.KEY_HEIGHT);
                if (f.containsKey("crop-right") && f.containsKey("crop-left")) w = f.getInteger("crop-right") - f.getInteger("crop-left") + 1;
                if (f.containsKey("crop-bottom") && f.containsKey("crop-top")) h = f.getInteger("crop-bottom") - f.getInteger("crop-top") + 1;
                if (w > 0 && h > 0) {
                    outW = w;
                    outH = h;
                }
            }
        };
    }

    // ---- JPEG ----

    /** Decoders.kt's JpegDecoder: bitmaps decoded on a thread of their own, kept until shown or passed over. */
    static final class Jpeg {
        private final Stream stream;
        private final ExecutorService executor;
        /** Decoded, not shown yet, by time (under `this`); bitmaps done with, to decode into again. */
        private final TreeMap<Double, Bitmap> decoded = new TreeMap<>();
        private final ArrayDeque<Bitmap> spare = new ArrayDeque<>();
        private volatile boolean released;

        Jpeg(Stream stream) {
            this.stream = stream;
            executor = Executors.newSingleThreadExecutor(r -> new Thread(r, "mbui-jpeg-" + stream.id));
        }

        void frame(byte[] data, double ts) {
            if (released) return;
            executor.execute(() -> {
                if (released) return;
                BitmapFactory.Options bounds = new BitmapFactory.Options();
                bounds.inJustDecodeBounds = true;
                BitmapFactory.decodeByteArray(data, 0, data.length, bounds);
                Bitmap into = null;
                synchronized (this) {
                    for (Iterator<Bitmap> i = spare.iterator(); i.hasNext(); ) {
                        Bitmap b = i.next();
                        if (b.getWidth() == bounds.outWidth && b.getHeight() == bounds.outHeight && b.isMutable() && !b.isRecycled()) {
                            into = b;
                            i.remove();
                            break;
                        }
                    }
                }
                BitmapFactory.Options o = new BitmapFactory.Options();
                o.inMutable = true;
                o.inPreferredConfig = Bitmap.Config.ARGB_8888;
                o.inBitmap = into;
                Bitmap b;
                try {
                    b = BitmapFactory.decodeByteArray(data, 0, data.length, o);
                } catch (IllegalArgumentException e) {
                    // the spare one did not fit after all: into a new one
                    o.inBitmap = null;
                    b = BitmapFactory.decodeByteArray(data, 0, data.length, o);
                }
                if (b == null) {
                    stream.say("d " + num(ts));
                    return;
                }
                synchronized (this) {
                    if (released) return;
                    decoded.put(ts, b);
                }
                stream.say("f " + num(ts) + " " + b.getWidth() + " " + b.getHeight());
            });
        }

        /** Frame `ts`'s bitmap, those before it given back to decode into (GL thread); null when it is not one of these. */
        synchronized Bitmap take(double ts) {
            Bitmap b = decoded.remove(ts);
            if (b == null) return null;
            for (Iterator<Map.Entry<Double, Bitmap>> i = decoded.headMap(ts).entrySet().iterator(); i.hasNext(); ) {
                reuse(i.next().getValue());
                i.remove();
            }
            return b;
        }

        /** A bitmap the stream is done with, to decode into again. */
        synchronized void reuse(Bitmap b) {
            if (!released && spare.size() < 2) spare.add(b);
        }

        void release() {
            released = true;
            executor.shutdown();
            synchronized (this) {
                decoded.clear();
                spare.clear();
            }
        }
    }
}
