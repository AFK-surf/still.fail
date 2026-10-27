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
 * Streams (src/hostapi/stream.mbt, @ui's Stream): a picture decoded frame by frame, drawn by the app as an image. As
 * still.fail's Android app decodes a remote screen (its remote/Decoders.kt), with what is shown said by the app:
 *
 * <p>H.264 by MediaCodec (asynchronous, its callbacks on a thread of the stream's own) onto a SurfaceTexture of the
 * app's GL context, driven by the framework (@ui's stream_feed.mbt, @hostapi.stream_feeds): what the decoder and the
 * SurfaceTexture say goes up as the stream's events ("c ..."), what to do with them comes down (`codec`): which frame
 * into which input buffer, which decoded frame onto the SurfaceTexture, when a frame there is latched (updateTexImage)
 * and drawn into a plain texture of the frame's size, what the renderer draws the stream with (android_host.c), and
 * when the decoder starts anew. Nothing here decides; every order those callbacks come in is the framework's tests'.
 *
 * <p>JPEG by BitmapFactory on a thread of its own, each bitmap kept until the app shows it (uploaded into the same
 * texture) or a later one is shown.
 *
 * <p>A JPEG decoded is told ("f TS W H"), one that does not decode let go ("d TS"). Each event asks for a frame.
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
        // (the framework's feed hands H.264 frames over as "queue" commands: `codec`)
        Stream s = streams.get(id);
        if (s != null) s.say("d " + num(ts));
    }

    /** A command for stream `id`'s decoder or SurfaceTexture (@ui's stream_feed.mbt); "latch" is a frame shown. */
    static void codec(int id, String cmd, byte[] data) {
        dropSurfaces();
        Stream s = streams.get(id);
        if (s != null && s.video != null) s.video.command(cmd, data);
        if (cmd.startsWith("latch ") && throwShow != null && throwShow.equals(String.valueOf(++shows))) throw new RuntimeException("MBUI_STREAM_THROW_SHOW: show " + shows);
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

    // A host contract injects a synchronous codec failure, which MediaCodec can throw instead of calling onError.
    private static final String failInput = System.getenv("MBUI_STREAM_FAIL_INPUT");
    private static final String failStart = System.getenv("MBUI_STREAM_FAIL_START");
    private static int inputCalls, startCalls;

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

    // MBUI_STREAM_HOLD_DECODER=MS (a test's, android-streams.sh anew): as the context is lost each decoder's thread held
    // that long first, as on a CPU it does not get, so the GL thread's frames after the new context come before
    // anything the decoder does about it
    private static final int hold = holdDecoder();

    private static int holdDecoder() {
        try {
            return Integer.parseInt(System.getenv("MBUI_STREAM_HOLD_DECODER"));
        } catch (Exception e) {
            return 0;
        }
    }

    /** The GL context was lost (android_host.c images_lost): every stream's textures made anew in the new one. */
    static void lost() {
        blitLost();
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

    /** A new GL context: the copy's program and framebuffer made anew in it as they are next used (GL thread). */
    static void blitLost() {
        blit = 0;
    }

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
        s.tex = plain(s.tex, w, h);
        s.texW = w;
        s.texH = h;
        texture(s.id, s.tex);
        return s.tex;
    }

    /** Plain texture `tex` (0: a new one) made `w` × `h`, as the renderer samples it: its name (GL thread). */
    static int plain(int tex, int w, int h) {
        if (tex == 0) {
            int[] t = {0};
            GLES30.glGenTextures(1, t, 0);
            tex = t[0];
        }
        GLES30.glActiveTexture(GLES30.GL_TEXTURE1);
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, tex);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, w, h, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null);
        return tex;
    }

    /** A new external texture, for a SurfaceTexture on it: its name (GL thread). */
    static int external() {
        int[] t = {0};
        GLES30.glGenTextures(1, t, 0);
        GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, t[0]);
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR);
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE);
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE);
        return t[0];
    }

    /**
     * The frame latched on SurfaceTexture `st` (on external texture `ext`) drawn into plain texture `tex`, `w` × `h`,
     * whole, its top in the texture's first row (GL thread): a stream's frame shown, a native view's picture
     * (NativeViews.Picture).
     */
    static void blitFrame(SurfaceTexture st, int ext, int tex, int w, int h) {
        blitProgram();
        float[] m = new float[16];
        st.getTransformMatrix(m);
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, blitFb);
        GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, tex, 0);
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
            ext = external();
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
            blitFrame(st, ext, target(this, w, h), w, h);
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

    /**
     * MediaCodec onto the stream's SurfaceTexture, driven by the framework (@ui's stream_feed.mbt): it does what it is
     * told (`run`: start, stop, queue, empty, release, discard on its thread; `latch`, `drop` on the GL thread) and says
     * what the decoder and the surface said, as they said it ("c ..." events, in the order they came), deciding
     * nothing: which frame goes where and what the app is told are the feed's, where a test gives every order.
     */
    static final class H264 {
        private final Stream stream;
        private final HandlerThread thread;
        private final Handler handler;
        /** The decoder there is and its number (the feed's), null and 0 when none. */
        private Dec codec;
        private int gen;
        private Surface surface;
        /** Surfaces done with, let go once no decoder draws on them (the next stop, or now when none does). */
        private final ArrayDeque<Object[]> old = new ArrayDeque<>();
        private byte[] avcc;
        private int lengthSize;
        private int width, height;
        private boolean released;
        private static final boolean scripted = "script".equals(System.getenv("MBUI_STREAM_CODEC"));
        /** The SurfaceTexture it draws on and its number (GL thread sets them; its frames arrive on this thread). */
        private volatile SurfaceTexture st;
        private int surfaceNo;

        H264(Stream stream) {
            this.stream = stream;
            thread = new HandlerThread("mbui-h264-" + stream.id);
            thread.start();
            handler = new Handler(thread.getLooper());
        }

        /** A new SurfaceTexture to draw on (GL thread): said ("c surf N"); the old one let go once no decoder draws on it. */
        void surface(SurfaceTexture t, Surface s, SurfaceTexture oldT, Surface oldS) {
            final int no = ++surfaceNo;
            t.setOnFrameAvailableListener(x -> stream.say("c arr " + no), handler);
            st = t;
            handler.post(() -> {
                surface = s;
                if (oldT != null) old.add(new Object[] {oldT, oldS});
                if (codec == null) letGoOld();
                stream.say("c surf " + no);
            });
        }

        private void letGoOld() {
            for (Object[] o; (o = old.poll()) != null; ) letGo((SurfaceTexture) o[0], (Surface) o[1]);
        }

        /** Its thread held `ms` from now (a test's: MBUI_STREAM_HOLD_DECODER). */
        void hold(int ms) {
            Host.log("stream " + stream.id + ": decoder held " + ms + " ms");
            handler.post(() -> android.os.SystemClock.sleep(ms));
        }

        void configure(byte[] avcc, int w, int h) {
            handler.post(() -> {
                this.avcc = avcc;
                lengthSize = avcLengthSize(avcc);
                width = w;
                height = h;
            });
        }

        void release(SurfaceTexture t, Surface s) {
            handler.post(() -> {
                released = true;
                stopCodec();
                if (t != null) old.add(new Object[] {t, s});
                letGoOld();
                thread.quitSafely();
            });
        }

        /** A command of the feed's: on the GL thread those of the SurfaceTexture, the decoder's on its own thread. */
        void command(String cmd, byte[] data) {
            String[] w = cmd.split(" ");
            switch (w[0]) {
                case "latch":
                    latch(Double.parseDouble(w[1]), Integer.parseInt(w[2]), Integer.parseInt(w[3]), Integer.parseInt(w[4]));
                    return;
                case "drop":
                    drop(Integer.parseInt(w[1]));
                    return;
                default:
                    handler.post(() -> run(w, data));
            }
        }

        private void run(String[] w, byte[] data) {
            if (released) return;
            int g = Integer.parseInt(w[1]);
            if (w[0].equals("start")) {
                start(g);
                return;
            }
            if (g != gen || codec == null) return;
            Dec c = codec;
            switch (w[0]) {
                case "stop":
                    stopCodec();
                    letGoOld();
                    break;
                case "queue": {
                    int index = Integer.parseInt(w[2]);
                    double ts = Double.parseDouble(w[3]);
                    try {
                        ByteBuffer buffer = c.input(index);
                        byte[] b = annexB(data, lengthSize);
                        if (buffer == null || b == null || buffer.capacity() < b.length) {
                            stream.say("c rej " + g + " " + index + " " + num(ts));
                            return;
                        }
                        buffer.clear();
                        buffer.put(b);
                        if (failInput != null && failInput.equals(String.valueOf(++inputCalls))) throw new IllegalStateException("MBUI_STREAM_FAIL_INPUT: input " + inputCalls);
                        c.queue(index, b.length, (long) ts, w[4].equals("1") ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0);
                    } catch (Exception e) {
                        Host.log("stream " + stream.id + ": the H.264 decoder failed: " + e);
                        stream.say("c err " + g);
                    }
                    break;
                }
                case "empty":
                    try {
                        c.queue(Integer.parseInt(w[2]), 0, (long) Double.parseDouble(w[3]), 0);
                    } catch (Exception e) {
                        Host.log("stream " + stream.id + ": the H.264 decoder failed: " + e);
                        stream.say("c err " + g);
                    }
                    break;
                case "release":
                    try {
                        c.release(Integer.parseInt(w[2]), true);
                    } catch (Exception e) {
                        stream.say("c lost " + g + " " + w[3]);
                    }
                    break;
                case "discard":
                    try {
                        c.release(Integer.parseInt(w[2]), false);
                    } catch (Exception ignored) {
                    }
                    break;
                default:
                    break;
            }
        }

        /** Decoder `g` for the config and surface there are: "c up G", or "c nostart G" with nothing of it kept. */
        private void start(int g) {
            stopCodec();
            gen = g;
            if (avcc == null || surface == null || lengthSize < 0) {
                stream.say("c nostart " + g);
                return;
            }
            if (scripted) {
                // (the scripted decoder: what it says in an order of its own, a frame drawn for each it is told to show)
                if (failStart != null && failStart.equals(String.valueOf(++startCalls))) {
                    Host.log("stream " + stream.id + ": no H.264 decoder: java.lang.IllegalStateException: MBUI_STREAM_FAIL_START: start " + startCalls);
                    stream.say("c nostart " + g);
                    return;
                }
                ScriptDec d = new ScriptDec(g, st, surface, width, height);
                codec = d;
                stream.say("c up " + g);
                d.begin();
                return;
            }
            MediaCodec made = null;
            try {
                MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, Math.max(width, 16), Math.max(height, 16));
                format.setByteBuffer("csd-0", ByteBuffer.wrap(avcCsd(avcc, 0)));
                format.setByteBuffer("csd-1", ByteBuffer.wrap(avcCsd(avcc, 1)));
                // a key frame of a whole screen can be large; the decoder's own guess for the size is often too small
                format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, Math.max(width * height, 1 << 20));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1);
                format.setInteger(MediaFormat.KEY_PRIORITY, 0);
                made = avcDecoder(width, height);
                // A Snapdragon's decoder, low-latency one or not, gives a picture back only once the next frame is
                // queued, whatever KEY_LOW_LATENCY and the SPS say (traced on an SM8850, 2026-10-28): the last frame of
                // a screen gone still is never shown nor acknowledged, and the station sends nothing more. Its own keys
                // have it give each back in decode order as soon as decoded (a screen's encoders never reorder).
                String named = made.getName();
                if (named.startsWith("c2.qti.") || named.startsWith("OMX.qcom.")) {
                    format.setInteger("vendor.qti-ext-dec-picture-order.enable", 1);
                    format.setInteger("vendor.qti-ext-dec-low-latency.enable", 1);
                }
                if (failStart != null && failStart.equals(String.valueOf(++startCalls))) throw new IllegalStateException("MBUI_STREAM_FAIL_START: start " + startCalls);
                made.setCallback(callback(g), handler);
                made.configure(format, surface, null, 0);
                made.start();
                codec = new RealDec(made);
                stream.say("c up " + g);
            } catch (Exception e) {
                Host.log("stream " + stream.id + ": no H.264 decoder: " + e);
                if (made != null) {
                    try {
                        made.release();
                    } catch (Exception ignored) {
                    }
                }
                stream.say("c nostart " + g);
            }
        }

        /**
         * An H.264 decoder that gives each frame back as soon as it is decoded, where the device has one: KEY_LOW_LATENCY
         * asks it only of a decoder that can, and the first a device lists may not (a Snapdragon's c2.qti.avc.decoder
         * keeps the newest frame until another comes; its c2.qti.avc.decoder.low_latency does not). A frame kept so is
         * neither shown nor acknowledged while the screen stays still, and the station sends nothing more until it is.
         */
        private static MediaCodec avcDecoder(int w, int h) throws java.io.IOException {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                MediaFormat ask = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, Math.max(w, 16), Math.max(h, 16));
                ask.setFeatureEnabled(android.media.MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency, true);
                String name = new MediaCodecList(MediaCodecList.REGULAR_CODECS).findDecoderForFormat(ask);
                if (name != null) return MediaCodec.createByCodecName(name);
            }
            return MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
        }

        private void stopCodec() {
            if (codec != null) codec.stop();
            codec = null;
        }

        /** What is asked of a decoder: MediaCodec's (RealDec), or the scripted one's (ScriptDec). */
        interface Dec {
            ByteBuffer input(int index);

            void queue(int index, int size, long ts, int flags);

            void release(int index, boolean render);

            void stop();
        }

        static final class RealDec implements Dec {
            final MediaCodec c;

            RealDec(MediaCodec c) {
                this.c = c;
            }

            public ByteBuffer input(int index) {
                return c.getInputBuffer(index);
            }

            public void queue(int index, int size, long ts, int flags) {
                c.queueInputBuffer(index, 0, size, ts, flags);
            }

            public void release(int index, boolean render) {
                c.releaseOutputBuffer(index, render);
            }

            public void stop() {
                try {
                    c.stop();
                } catch (Exception ignored) {
                }
                try {
                    c.release();
                } catch (Exception ignored) {
                }
            }
        }

        /**
         * MBUI_STREAM_CODEC=script (android-streams.sh's, the check CI holds to): a decoder whose callbacks come in an
         * order of its own, not the system's: four input buffers free as it starts; a frame queued comes out at once
         * in the output buffer of its number, its input buffer free again; one released is drawn onto the surface
         * (a Canvas: its frame-available, as a decoder's). What the check then holds is this host's own: the commands
         * done, the callbacks said on, the SurfaceTexture latched and copied, JNI, the injected failures. The system's
         * MediaCodec, whose start has a deadline a busy emulator misses, is the smoke run's (REAL=1), which holds nothing.
         */
        final class ScriptDec implements Dec {
            final int g;
            final ByteBuffer[] in = new ByteBuffer[4];
            final SurfaceTexture t;
            final Surface s;

            ScriptDec(int g, SurfaceTexture t, Surface s, int w, int h) {
                this.g = g;
                this.t = t;
                this.s = s;
                if (t != null) t.setDefaultBufferSize(Math.max(w, 16), Math.max(h, 16));
                for (int i = 0; i < in.length; i++) in[i] = ByteBuffer.allocate(Math.max(w * h, 1 << 20));
            }

            void begin() {
                for (int i = 0; i < in.length; i++) stream.say("c in " + g + " " + i);
            }

            public ByteBuffer input(int index) {
                return index >= 0 && index < in.length ? in[index] : null;
            }

            public void queue(int index, int size, long ts, int flags) {
                if (size > 0) stream.say("c out " + g + " " + index + " " + ts + " 1");
                stream.say("c in " + g + " " + index);
            }

            public void release(int index, boolean render) {
                if (!render) return;
                android.graphics.Canvas cv = s.lockCanvas(null);
                cv.drawColor(0xFF000000 | (index * 0x403020));
                s.unlockCanvasAndPost(cv);
            }

            public void stop() {
            }
        }

        /** Decoder `g`'s callbacks: what it said, said on. */
        private MediaCodec.Callback callback(int g) {
            return new MediaCodec.Callback() {
                @Override
                public void onInputBufferAvailable(MediaCodec c, int index) {
                    stream.say("c in " + g + " " + index);
                }

                @Override
                public void onOutputBufferAvailable(MediaCodec c, int index, MediaCodec.BufferInfo info) {
                    boolean shows = (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && info.size > 0;
                    stream.say("c out " + g + " " + index + " " + info.presentationTimeUs + " " + (shows ? 1 : 0));
                }

                @Override
                public void onError(MediaCodec c, MediaCodec.CodecException e) {
                    Host.log("stream " + stream.id + ": the H.264 decoder failed: " + e);
                    stream.say("c err " + g);
                }

                @Override
                public void onOutputFormatChanged(MediaCodec c, MediaFormat f) {
                    int w = f.getInteger(MediaFormat.KEY_WIDTH), h = f.getInteger(MediaFormat.KEY_HEIGHT);
                    if (f.containsKey("crop-right") && f.containsKey("crop-left")) w = f.getInteger("crop-right") - f.getInteger("crop-left") + 1;
                    if (f.containsKey("crop-bottom") && f.containsKey("crop-top")) h = f.getInteger("crop-bottom") - f.getInteger("crop-top") + 1;
                    stream.say("c fmt " + g + " " + w + " " + h);
                }
            };
        }

        /** The SurfaceTexture's frame latched, at most `n` updates up to the one of time `ts`, and drawn into the
         * stream's texture, `w` × `h` (GL thread). */
        void latch(double ts, int n, int w, int h) {
            SurfaceTexture t = st;
            if (t == null) return;
            long want = (long) ts * 1000L;
            boolean got = false;
            for (int i = 0; i < n; i++) {
                try {
                    t.updateTexImage();
                } catch (RuntimeException e) {
                    // (the picture stays as it was)
                    Host.log("stream " + stream.id + ": updateTexImage: " + e);
                    got = false;
                    break;
                }
                got = true;
                if (t.getTimestamp() == want) break;
            }
            if (got) stream.copy(w > 0 ? w : 16, h > 0 ? h : 16);
        }

        /** The SurfaceTexture's `n` frames no one was told of latched away (GL thread). */
        void drop(int n) {
            SurfaceTexture t = st;
            if (t == null) return;
            for (int i = 0; i < n; i++) {
                try {
                    t.updateTexImage();
                } catch (RuntimeException e) {
                    Host.log("stream " + stream.id + ": updateTexImage: " + e);
                    return;
                }
            }
        }
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
