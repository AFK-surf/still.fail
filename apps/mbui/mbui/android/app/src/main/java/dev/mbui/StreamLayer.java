package dev.mbui;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.PorterDuff;
import android.graphics.Rect;
import android.graphics.RectF;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Build;
import android.view.PixelCopy;
import android.view.Surface;
import android.view.SurfaceControl;

import java.util.HashMap;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Streams shown by a layer of the system's (src/hostapi/stream.mbt `stream_layers`; @ui's Stream with `layer`: a native
 * view of kind 4, its argument the stream's id), as apple_views.m and apple_stream.m show them on Apple's systems.
 *
 * <p>Each stream's frames are decoded by MediaCodec straight onto a SurfaceControl of its own (Streams.Own, not the
 * framework's feed: nothing goes through a SurfaceTexture or the GL thread), a child of the MBView's surface placed
 * under it (a negative layer: SurfaceFlinger composes it below the canvas's buffer), where the canvas is cleared for it
 * (android_host.c's views_under: the instance of kind 9 takes the canvas away). A frame the app shows is put there by
 * the decoder's releaseOutputBuffer, nothing of the app's built or drawn for it; the compositor scales it to where the
 * view is placed. Where it is placed, cut by its clip, is set as the app paints the view, in the transaction of the
 * canvas's frame that paints its hole (SurfaceView.applyTransactionToFrame, API 34; at once before that).
 *
 * <p>The station's pointer over it (@hostapi.stream_pointer) is a layer of its own over the picture's: the station's
 * shape drawn into it once, moved by the compositor as it moves (pointerAt), nothing of the app's drawn for it.
 *
 * <p>A stream's view no longer shown (the app draws its last frame itself: faded while it reconnects, blurred under the
 * dark once it ended) leaves the app a picture of what its layer showed (PixelCopy, into the stream's texture).
 *
 * <p>Android 13 (API 33) and later: a SurfaceControl's crop, position and scale. Earlier, none (`here` false): the app
 * draws its streams as before.
 */
final class StreamLayer {
    /** Whether view `id` is under the canvas, cleared where it shows (android_host.c views_under). */
    static native void under(int id, boolean on);

    private static Boolean hereKnown, hevcKnown;

    /** Whether streams can show on layers here (android_host.c mb_host_stream_layers asks once). */
    static synchronized boolean here() {
        if (hereKnown == null) hereKnown = Build.VERSION.SDK_INT >= 33 && Streams.h264Here();
        return hereKnown;
    }

    /** Whether the device decodes H.265 in its hardware (for a stream on its layer: Streams.Own). */
    static synchronized boolean hevcHere() {
        if (hevcKnown == null) {
            boolean any = false;
            try {
                for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos()) {
                    if (info.isEncoder() || !info.isHardwareAccelerated()) continue;
                    for (String t : info.getSupportedTypes()) {
                        if (t.equalsIgnoreCase(MediaFormat.MIMETYPE_VIDEO_HEVC)) any = true;
                    }
                }
            } catch (Exception e) {
                any = false;
            }
            hevcKnown = any;
        }
        return hevcKnown;
    }

    /** One stream's layers and where its view is. Under `lock`. */
    static final class Layer {
        final int sid;
        /** its view's id (0: none open) */
        int vid;
        /** the picture's layer and the surface its decoder draws on, its frames' size (the layer's space) */
        SurfaceControl video;
        Surface surface;
        int bw, bh;
        /** whether a frame was put on it since it was made (a picture to grab) */
        volatile boolean rendered;
        /** the pointer's layer and surface, its picture's size in pixels; its size and hot spot in points; where it
         * points (0..1 of the picture's rect) and whether it shows */
        SurfaceControl pointer;
        Surface pointerSurface;
        int pbw, pbh;
        float pw, ph, hx, hy;
        double px, py;
        boolean pointerShown;
        /** where its view is (device pixels: x y w h, clip x0 y0 x1 y1), whether shown, and its place in the stack */
        float[] at;
        boolean shown;
        int z;

        Layer(int sid) {
            this.sid = sid;
        }
    }

    private static final Object lock = new Object();
    private static final HashMap<Integer, Layer> layers = new HashMap<>();
    /** views' ids to their streams' */
    private static final HashMap<Integer, Integer> viewStreams = new HashMap<>();
    private static int zNext;
    /** the layers' place under the canvas's picture (its children's layers, relative to it: below 0, under it) */
    private static final int BASE = -1_000_000;
    /** the host's MBView whose surface they are under now, and that surface's SurfaceControl (null: none) */
    private static MBView parentView;
    private static SurfaceControl parent;

    // ---- the views (NativeViews: GL thread) ----

    /** View `vid` of stream `arg` opened: its stream's frames shown on its layer from now. */
    static boolean open(int vid, String arg) {
        int sid;
        try {
            sid = Integer.parseInt(arg.trim());
        } catch (NumberFormatException e) {
            return false;
        }
        synchronized (lock) {
            Layer l = layers.get(sid);
            if (l == null) layers.put(sid, l = new Layer(sid));
            l.vid = vid;
            l.z = ++zNext;
            viewStreams.put(vid, sid);
        }
        under(vid, true);
        Streams.layered(sid, true);
        Host.log("view " + vid + ": open stream " + sid + "'s layer");
        // (ready at once, told as the app has its ticket: after it opened it)
        MBView v = Host.view;
        if (v != null) v.toGL(() -> Native.outside(Native.OUTSIDE_VIEW, vid, 1));
        return true;
    }

    static boolean has(int vid) {
        synchronized (lock) {
            return viewStreams.containsKey(vid);
        }
    }

    /** Where view `vid` shows (points, as NativeViews.place), as the app paints it (GL thread, in the frame). */
    static void place(int vid, float x, float y, float w, float h, float cx0, float cy0, float cx1, float cy1, boolean shown) {
        MBView v = Host.view;
        float d = v != null ? v.density : 1;
        Layer grab = null;
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        synchronized (lock) {
            Integer sid = viewStreams.get(vid);
            if (sid == null) return;
            Layer l = layers.get(sid);
            if (l == null) return;
            float[] to = {x * d, y * d, w * d, h * d, cx0 * d, cy0 * d, cx1 * d, cy1 * d};
            boolean same = l.shown == shown && l.at != null;
            for (int i = 0; i < to.length && same; i++) same = Math.abs(l.at[i] - to[i]) < 0.01f;
            if (same) return;
            if (l.shown && !shown && l.rendered) grab = l;
            l.at = to;
            l.shown = shown;
            put(l, t);
        }
        commit(t, true);
        if (grab != null) grab(grab);
    }

    /** View `vid` closed: its layer hidden (the stream's own goes with the stream: drop). */
    static void close(int vid) {
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        int sid;
        synchronized (lock) {
            Integer s = viewStreams.remove(vid);
            if (s == null) return;
            sid = s;
            Layer l = layers.get(sid);
            if (l != null && l.vid == vid) {
                l.vid = 0;
                l.shown = false;
                put(l, t);
            }
        }
        t.apply();
        under(vid, false);
        Streams.layered(sid, false);
        Host.log("view " + vid + ": closed");
    }

    /** View `vid` raised over the others (the app paints it after them). */
    static void raise(int vid) {
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        synchronized (lock) {
            Integer sid = viewStreams.get(vid);
            Layer l = sid != null ? layers.get(sid) : null;
            if (l == null) return;
            l.z = ++zNext;
            put(l, t);
        }
        commit(t, true);
    }

    // ---- the decoder's surface (Streams.Own: its thread) ----

    /**
     * The surface stream `sid`'s decoder draws on, its frames `w` × `h`: its picture's layer, made (anew at another
     * size, the old let go: its decoder has stopped) where it is not. Made without a view too (none shown then).
     */
    static Surface surface(int sid, int w, int h) {
        w = Math.max(w, 16);
        h = Math.max(h, 16);
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        SurfaceControl oldVideo;
        Surface oldSurface, made;
        synchronized (lock) {
            Layer l = layers.get(sid);
            if (l == null) layers.put(sid, l = new Layer(sid));
            if (l.video != null && l.bw == w && l.bh == h) return l.surface;
            oldVideo = l.video;
            oldSurface = l.surface;
            SurfaceControl.Builder b = new SurfaceControl.Builder().setName("mbui stream " + sid).setBufferSize(w, h)
                    .setOpaque(true).setHidden(true);
            if (parent != null) b.setParent(parent);
            l.video = b.build();
            l.surface = made = new Surface(l.video);
            l.bw = w;
            l.bh = h;
            l.rendered = false;
            put(l, t);
            if (oldVideo != null) t.reparent(oldVideo, null);
        }
        t.apply();
        if (oldSurface != null) oldSurface.release();
        if (oldVideo != null) oldVideo.release();
        return made;
    }

    /** A frame put on stream `sid`'s layer (its decoder's thread). */
    static void rendered(int sid) {
        synchronized (lock) {
            Layer l = layers.get(sid);
            if (l != null) l.rendered = true;
        }
    }

    /** Stream `sid` closed, its decoder stopped (its thread): its layers let go. */
    static void drop(int sid) {
        Layer l;
        synchronized (lock) {
            l = layers.remove(sid);
        }
        if (l == null) return;
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        if (l.video != null) t.reparent(l.video, null);
        if (l.pointer != null) t.reparent(l.pointer, null);
        t.apply();
        if (l.surface != null) l.surface.release();
        if (l.video != null) l.video.release();
        if (l.pointerSurface != null) l.pointerSurface.release();
        if (l.pointer != null) l.pointer.release();
    }

    // ---- its pointer (GL thread) ----

    /** Stream `sid`'s pointer: picture `png` (empty: none), `w` × `h` points, its hot spot (`hx`, `hy`). */
    static void pointer(int sid, byte[] png, float w, float h, float hx, float hy) {
        MBView v = Host.view;
        float d = v != null ? v.density : 1;
        Bitmap image = png.length > 0 ? BitmapFactory.decodeByteArray(png, 0, png.length) : null;
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        Surface draw = null;
        int pbw = Math.max(1, Math.round(w * d)), pbh = Math.max(1, Math.round(h * d));
        synchronized (lock) {
            Layer l = layers.get(sid);
            if (l == null) layers.put(sid, l = new Layer(sid));
            l.pw = w;
            l.ph = h;
            l.hx = hx;
            l.hy = hy;
            if (image == null) {
                if (l.pointer != null) {
                    t.reparent(l.pointer, null);
                    l.pointerSurface.release();
                    l.pointer.release();
                    l.pointer = null;
                    l.pointerSurface = null;
                }
            } else {
                if (l.pointer == null || l.pbw != pbw || l.pbh != pbh) {
                    if (l.pointer != null) {
                        t.reparent(l.pointer, null);
                        l.pointerSurface.release();
                        l.pointer.release();
                    }
                    SurfaceControl.Builder b = new SurfaceControl.Builder().setName("mbui stream " + sid + " pointer")
                            .setBufferSize(pbw, pbh).setFormat(PixelFormat.RGBA_8888).setOpaque(false).setHidden(true);
                    if (parent != null) b.setParent(parent);
                    l.pointer = b.build();
                    l.pointerSurface = new Surface(l.pointer);
                    l.pbw = pbw;
                    l.pbh = pbh;
                }
                draw = l.pointerSurface;
            }
            if (draw != null) {
                try {
                    Canvas c = draw.lockHardwareCanvas();
                    c.drawColor(0, PorterDuff.Mode.CLEAR);
                    c.drawBitmap(image, null, new RectF(0, 0, pbw, pbh), new Paint(Paint.FILTER_BITMAP_FLAG));
                    draw.unlockCanvasAndPost(c);
                } catch (RuntimeException e) {
                    Host.log("stream " + sid + ": its pointer not drawn: " + e);
                }
            }
            put(l, t);
        }
        t.apply();
    }

    /** Where stream `sid`'s pointer points: (`x`, `y`) of its picture's rect, `shown` false none. */
    static void pointerAt(int sid, double x, double y, boolean shown) {
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        synchronized (lock) {
            Layer l = layers.get(sid);
            if (l == null) return;
            if (l.px == x && l.py == y && l.pointerShown == shown) return;
            l.px = x;
            l.py = y;
            l.pointerShown = shown;
            put(l, t);
        }
        t.apply();
    }

    // ---- where they go (under `lock`) ----

    /** Layer `l` (its picture's and its pointer's) put where its view is, cut by its clip, or hidden, into `t`. */
    private static void put(Layer l, SurfaceControl.Transaction t) {
        float[] a = l.at;
        boolean shows = parent != null && l.vid != 0 && l.shown && a != null && l.video != null && a[2] > 0 && a[3] > 0;
        float x0 = 0, y0 = 0, x1 = 0, y1 = 0;
        if (shows) {
            x0 = Math.max(a[0], a[4]);
            y0 = Math.max(a[1], a[5]);
            x1 = Math.min(a[0] + a[2], a[6]);
            y1 = Math.min(a[1] + a[3], a[7]);
            shows = x1 > x0 && y1 > y0;
        }
        if (l.video != null) {
            if (shows) {
                float sx = a[2] / l.bw, sy = a[3] / l.bh;
                t.setPosition(l.video, a[0], a[1]);
                t.setScale(l.video, sx, sy);
                // (the part within the clip, in the picture's own pixels: a pixel more round it is under the canvas)
                t.setCrop(l.video, new Rect((int) Math.floor((x0 - a[0]) / sx), (int) Math.floor((y0 - a[1]) / sy),
                        (int) Math.ceil((x1 - a[0]) / sx), (int) Math.ceil((y1 - a[1]) / sy)));
                t.setLayer(l.video, BASE + 2 * l.z);
            }
            t.setVisibility(l.video, shows);
        }
        if (l.pointer != null) {
            boolean on = shows && l.pointerShown;
            if (on) {
                float d = parentView != null ? parentView.density : 1;
                float px = (float) (a[0] + l.px * a[2]) - l.hx * d, py = (float) (a[1] + l.py * a[3]) - l.hy * d;
                int cl = (int) Math.floor(Math.max(0, x0 - px)), ct = (int) Math.floor(Math.max(0, y0 - py));
                int cr = (int) Math.ceil(Math.min(l.pbw, x1 - px)), cb = (int) Math.ceil(Math.min(l.pbh, y1 - py));
                on = cr > cl && cb > ct;
                if (on) {
                    t.setPosition(l.pointer, px, py);
                    t.setCrop(l.pointer, new Rect(cl, ct, cr, cb));
                    t.setLayer(l.pointer, BASE + 2 * l.z + 1);
                }
            }
            t.setVisibility(l.pointer, on);
        }
    }

    /**
     * Transaction `t` applied: with the canvas's frame being drawn where it is one (`inFrame`, on the GL thread: the
     * view's hole and its layer moved in one refresh, API 34), else now.
     */
    private static void commit(SurfaceControl.Transaction t, boolean inFrame) {
        MBView v = parentView;
        if (inFrame && Build.VERSION.SDK_INT >= 34 && v != null && v == Host.view) {
            try {
                v.applyTransactionToFrame(t);
                return;
            } catch (RuntimeException e) {
                // (its surface gone meanwhile: at once)
            }
        }
        t.apply();
    }

    // ---- the MBView's surface (main thread) ----

    /** The layers put under `v`'s surface (the host's view, its surface made). */
    static void parentFrom(MBView v) {
        SurfaceControl sc = v.getSurfaceControl();
        if (sc == null || !sc.isValid()) return;
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        synchronized (lock) {
            if (parent == sc && parentView == v) return;
            parent = sc;
            parentView = v;
            for (Layer l : layers.values()) {
                if (l.video != null) t.reparent(l.video, sc);
                if (l.pointer != null) t.reparent(l.pointer, sc);
                put(l, t);
            }
        }
        t.apply();
    }

    /** `v`'s surface gone: the layers off the screen until they are put under another (kept: their pictures too). */
    static void parentGone(MBView v) {
        SurfaceControl.Transaction t = new SurfaceControl.Transaction();
        synchronized (lock) {
            if (parentView != v) return;
            parent = null;
            parentView = null;
            for (Layer l : layers.values()) {
                if (l.video != null) t.reparent(l.video, null);
                if (l.pointer != null) t.reparent(l.pointer, null);
            }
        }
        t.apply();
    }

    // ---- the picture left for the app ----

    /**
     * What layer `l` shows now copied into its stream's texture (the app draws its last frame itself from now: faded,
     * blurred), uploaded on the GL thread and a frame asked for.
     */
    private static void grab(Layer l) {
        Surface s;
        int w, h;
        synchronized (lock) {
            s = l.surface;
            w = l.bw;
            h = l.bh;
        }
        if (s == null || !s.isValid()) return;
        Bitmap b;
        try {
            b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        } catch (RuntimeException | OutOfMemoryError e) {
            return;
        }
        int sid = l.sid;
        try {
            PixelCopy.request(s, b, result -> {
                if (result != PixelCopy.SUCCESS) {
                    Host.log("stream " + sid + ": its layer's picture not copied (" + result + ")");
                    return;
                }
                MBView v = Host.view;
                if (v != null) v.toGL(() -> Streams.grabbed(sid, b));
            }, Host.main);
        } catch (RuntimeException e) {
            Host.log("stream " + sid + ": its layer's picture not copied: " + e);
        }
    }

    // ---- what a stream says (Streams.Stream.say) ----

    /**
     * Stream `s` said something, shown on its layer: the app told on the GL thread, between frames (Native.outside's
     * OUTSIDE_STREAMED: ui's streams_said), once until it has read what it said; it takes what changes nothing drawn
     * then (a frame shown on the layer), and asks for a frame only where something is left for one.
     */
    static void streamed(int id, AtomicBoolean owed) {
        MBView v = Host.view;
        if (v == null) return;
        if (!owed.compareAndSet(false, true)) return;
        v.queueEvent(() -> {
            owed.set(false);
            Native.outside(Native.OUTSIDE_STREAMED, id, 0);
        });
    }
}
